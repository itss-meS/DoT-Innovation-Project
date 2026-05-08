"""
train_ppo.py
============
Trains a PPO agent on the UrbanCanyonEnv.
Uses Stable-Baselines3 with a custom flat-action wrapper.

Usage
-----
    python train_ppo.py                    # default 10 000 episodes
    python train_ppo.py --timesteps 50000  # quick smoke-test
    python train_ppo.py --eval-only --model-path outputs/best_model.zip
"""

import argparse
import os
import time
import json
import numpy as np
import torch

import gymnasium as gym
from gymnasium import spaces
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import DummyVecEnv, VecNormalize
from stable_baselines3.common.callbacks import (
    EvalCallback, CheckpointCallback, BaseCallback
)
from stable_baselines3.common.monitor import Monitor

import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from env.urban_canyon_env import UrbanCanyonEnv, N_PANELS, N_PHASE_ELEMENTS

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "..", "outputs")
os.makedirs(OUTPUT_DIR, exist_ok=True)


# ─── Flat-action wrapper ──────────────────────────────────────────────────────
class FlatActionWrapper(gym.ActionWrapper):
    """
    Converts the Dict action space to a flat Box so SB3 PPO can handle it.
    First 8 dims = servo angles (continuous, scaled to [-1,1]).
    Last 2048 dims = phase states (continuous, thresholded at 0.5 → binary).
    """
    def __init__(self, env):
        super().__init__(env)
        self.action_space = spaces.Box(
            low  = np.concatenate([np.full(N_PANELS, -1.0),
                                   np.zeros(N_PHASE_ELEMENTS)]),
            high = np.concatenate([np.full(N_PANELS,  1.0),
                                   np.ones(N_PHASE_ELEMENTS)]),
            dtype=np.float32,
        )

    def action(self, act: np.ndarray) -> dict:
        servo = act[:N_PANELS] * 15.0          # scale [-1,1] → [-15°,+15°]
        phase = (act[N_PANELS:] > 0.5).astype(np.float32)   # binarise
        return {"servo_angles": servo.astype(np.float32),
                "phase_matrix": phase}

    def reverse_action(self, action):
        raise NotImplementedError


# ─── Custom logging callback ──────────────────────────────────────────────────
class MetricsCallback(BaseCallback):
    def __init__(self, log_path: str, verbose=0):
        super().__init__(verbose)
        self.log_path   = log_path
        self.ep_rewards = []
        self.ep_rssis   = []
        self.ep_snrs    = []
        self._ep_rew    = 0.0
        self._ep_rssi   = []
        self._ep_snr    = []

    def _on_step(self) -> bool:
        info = self.locals["infos"][0]
        self._ep_rew  += self.locals["rewards"][0]
        self._ep_rssi.append(info.get("rssi",  -100.0))
        self._ep_snr.append( info.get("snr",   0.0))

        if self.locals["dones"][0]:
            self.ep_rewards.append(self._ep_rew)
            self.ep_rssis.append(float(np.mean(self._ep_rssi)))
            self.ep_snrs.append( float(np.mean(self._ep_snr)))
            self._ep_rew  = 0.0
            self._ep_rssi = []
            self._ep_snr  = []

            if len(self.ep_rewards) % 50 == 0:
                n = len(self.ep_rewards)
                recent_rew  = np.mean(self.ep_rewards[-50:])
                recent_rssi = np.mean(self.ep_rssis[-50:])
                recent_snr  = np.mean(self.ep_snrs[-50:])
                print(f"  [Ep {n:5d}]  reward={recent_rew:+7.2f}  "
                      f"RSSI={recent_rssi:.1f} dBm  SNR={recent_snr:.1f} dB")
        return True

    def _on_training_end(self):
        log = {
            "episode_rewards": [float(x) for x in self.ep_rewards],
            "episode_rssi":    [float(x) for x in self.ep_rssis],
            "episode_snr":     [float(x) for x in self.ep_snrs],
        }
        with open(self.log_path, "w") as f:
            json.dump(log, f, indent=2)
        print(f"\n  Training log saved → {self.log_path}")


# ─── Success-rate callback ────────────────────────────────────────────────────
class SuccessRateCallback(BaseCallback):
    """Stops training early if 90% of last-100-ep rewards are positive."""
    def __init__(self, threshold=0.90, window=100, verbose=0):
        super().__init__(verbose)
        self.threshold = threshold
        self.window    = window
        self._rewards  = []

    def _on_step(self) -> bool:
        if self.locals["dones"][0]:
            self._rewards.append(self.locals["rewards"][0])
            if len(self._rewards) >= self.window:
                recent = self._rewards[-self.window:]
                rate   = sum(1 for r in recent if r > 0) / self.window
                if rate >= self.threshold:
                    print(f"\n  ✓ 90%+ success rate achieved "
                          f"({rate*100:.1f}%). Early stop.")
                    return False
        return True


# ─── Make env factory ─────────────────────────────────────────────────────────
def make_env(seed=0, render_mode=None):
    def _init():
        env = UrbanCanyonEnv(render_mode=render_mode, max_steps=200, seed=seed)
        env = FlatActionWrapper(env)
        env = Monitor(env)
        return env
    return _init


# ─── Train ────────────────────────────────────────────────────────────────────
def train(total_timesteps: int = 2_048_000, n_envs: int = 1):
    print("=" * 60)
    print("  O-RIS PPO Training")
    print(f"  Timesteps : {total_timesteps:,}")
    print(f"  Device    : {'cuda' if torch.cuda.is_available() else 'cpu'}")
    print("=" * 60)

    env = DummyVecEnv([make_env(seed=i) for i in range(n_envs)])
    env = VecNormalize(env, norm_obs=True, norm_reward=True, clip_obs=10.0)

    eval_raw = DummyVecEnv([make_env(seed=99)])
    eval_env = VecNormalize(eval_raw, norm_obs=True, norm_reward=False,
                            training=False)

    model = PPO(
        policy          = "MlpPolicy",
        env             = env,
        learning_rate   = 3e-4,
        n_steps         = 2048,
        batch_size      = 64,
        n_epochs        = 10,
        gamma           = 0.99,
        gae_lambda      = 0.95,
        clip_range      = 0.2,
        ent_coef        = 0.01,
        vf_coef         = 0.5,
        max_grad_norm   = 0.5,
        policy_kwargs   = dict(net_arch=[256, 256, 128]),
        verbose         = 0,
        tensorboard_log = os.path.join(OUTPUT_DIR, "tensorboard"),
        device          = "cuda" if torch.cuda.is_available() else "cpu",
    )

    callbacks = [
        MetricsCallback(
            log_path=os.path.join(OUTPUT_DIR, "training_log.json")),
        CheckpointCallback(
            save_freq    = 50_000,
            save_path    = os.path.join(OUTPUT_DIR, "checkpoints"),
            name_prefix  = "oris_ppo",
            verbose      = 0),
        EvalCallback(
            eval_env,
            best_model_save_path = OUTPUT_DIR,
            log_path             = os.path.join(OUTPUT_DIR, "eval_logs"),
            eval_freq            = 20_000,
            n_eval_episodes      = 20,
            deterministic        = True,
            verbose              = 0),
        SuccessRateCallback(threshold=0.90, window=100),
    ]

    t0 = time.time()
    model.learn(total_timesteps=total_timesteps,
                callback=callbacks,
                progress_bar=False)
    elapsed = time.time() - t0

    # Save final model + VecNormalize stats
    model_path = os.path.join(OUTPUT_DIR, "oris_ppo_final.zip")
    stats_path = os.path.join(OUTPUT_DIR, "vec_normalize.pkl")
    model.save(model_path)
    env.save(stats_path)

    print(f"\n  Training complete in {elapsed:.1f}s")
    print(f"  Model saved → {model_path}")
    print(f"  VecNorm  saved → {stats_path}")
    return model, env


# ─── Evaluate ─────────────────────────────────────────────────────────────────
def evaluate(model_path: str, stats_path: str, n_episodes: int = 50):
    print(f"\n  Evaluating {model_path}")
    raw_env = DummyVecEnv([make_env(seed=42)])
    eval_env = VecNormalize.load(stats_path, raw_env)
    eval_env.training = False

    model = PPO.load(model_path, env=eval_env)

    results = {"rssi": [], "snr": [], "reward": [], "steps": []}
    for ep in range(n_episodes):
        obs = eval_env.reset()
        done, ep_rew, ep_rssi, ep_snr, step = False, 0.0, [], [], 0
        while not done:
            action, _ = model.predict(obs, deterministic=True)
            obs, reward, done, info = eval_env.step(action)
            ep_rew  += float(reward[0])
            ep_rssi.append(info[0].get("rssi", -100))
            ep_snr.append( info[0].get("snr",  0))
            step    += 1
        results["rssi"].append(np.mean(ep_rssi))
        results["snr"].append( np.mean(ep_snr))
        results["reward"].append(ep_rew)
        results["steps"].append(step)

    print(f"\n  ── Evaluation over {n_episodes} episodes ──")
    print(f"  Mean RSSI   : {np.mean(results['rssi']):.2f} dBm")
    print(f"  Mean SNR    : {np.mean(results['snr']):.2f}  dB")
    print(f"  Mean Reward : {np.mean(results['reward']):.2f}")
    print(f"  RSSI > -70  : {sum(1 for r in results['rssi'] if r>-70)/n_episodes*100:.1f}%")

    eval_path = os.path.join(OUTPUT_DIR, "eval_results.json")
    with open(eval_path, "w") as f:
        json.dump(results, f, indent=2)
    print(f"  Results saved → {eval_path}")
    return results


# ─── Export to TorchScript (PyTorch Lite) ─────────────────────────────────────
def export_torchscript(model_path: str, stats_path: str):
    """Export policy network as TorchScript for <2ms inference."""
    raw_env = DummyVecEnv([make_env(seed=0)])
    env = VecNormalize.load(stats_path, raw_env)
    env.training = False
    model = PPO.load(model_path, env=env)

    # Wrap just the policy network
    policy = model.policy
    policy.eval()

    dummy_obs = torch.zeros(1, 21)   # 21-dim state

    with torch.no_grad():
        try:
            scripted = torch.jit.trace(policy.mlp_extractor, dummy_obs)
            ts_path  = os.path.join(OUTPUT_DIR, "oris_policy_lite.pt")
            scripted.save(ts_path)
            print(f"\n  TorchScript model saved → {ts_path}")

            # Benchmark inference
            import time as t
            times = []
            for _ in range(1000):
                s = t.perf_counter()
                scripted(dummy_obs)
                times.append((t.perf_counter() - s) * 1000)
            print(f"  Inference latency: mean={np.mean(times):.3f}ms  "
                  f"p99={np.percentile(times,99):.3f}ms")
        except Exception as e:
            print(f"  TorchScript export note: {e}")
            print("  (Full model saved as .zip — use model.predict() for inference)")


# ─── CLI ──────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--timesteps", type=int, default=2_048_000)
    parser.add_argument("--eval-only", action="store_true")
    parser.add_argument("--model-path", default=None)
    parser.add_argument("--stats-path", default=None)
    args = parser.parse_args()

    model_path = args.model_path or os.path.join(OUTPUT_DIR, "best_model.zip")
    stats_path = args.stats_path or os.path.join(OUTPUT_DIR, "vec_normalize.pkl")

    if args.eval_only:
        evaluate(model_path, stats_path)
        export_torchscript(model_path, stats_path)
    else:
        model, env = train(total_timesteps=args.timesteps)
        evaluate(model_path, stats_path)
        export_torchscript(model_path, stats_path)
