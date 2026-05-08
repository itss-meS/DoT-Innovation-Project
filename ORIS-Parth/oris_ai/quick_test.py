"""
quick_test.py
=============
Validates the environment and runs a short PPO training (5 000 timesteps).
Use this on Day 7 to confirm everything works before full training.

    python quick_test.py
"""

import sys, os, time
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from env.urban_canyon_env import UrbanCanyonEnv, N_PANELS, N_PHASE_ELEMENTS
from agent.train_ppo import FlatActionWrapper, make_env, OUTPUT_DIR

from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import DummyVecEnv, VecNormalize
from stable_baselines3.common.monitor import Monitor


def test_environment():
    print("\n── 1. Environment Tests ─────────────────────────────")
    env = UrbanCanyonEnv(render_mode="human", max_steps=10, seed=42)
    env = FlatActionWrapper(env)

    # Reset
    obs, info = env.reset()
    assert obs.shape == (21,), f"Obs shape {obs.shape} != (21,)"
    print(f"  ✓ Observation shape: {obs.shape}")
    print(f"  ✓ Initial RSSI: {info['rssi']:.1f} dBm")

    # Random rollout
    rewards, rssis = [], []
    obs, _ = env.reset()
    for step in range(10):
        action = env.action_space.sample()
        obs, reward, terminated, truncated, info = env.step(action)
        rewards.append(reward)
        rssis.append(info["rssi"])
        env.render()

    print(f"  ✓ 10 random steps OK")
    print(f"    Mean reward : {np.mean(rewards):.3f}")
    print(f"    Mean RSSI   : {np.mean(rssis):.1f} dBm")
    print(f"    RSSI range  : [{min(rssis):.1f}, {max(rssis):.1f}] dBm")

    # Action space
    assert env.action_space.shape == (N_PANELS + N_PHASE_ELEMENTS,)
    print(f"  ✓ Action space shape: {env.action_space.shape}")
    env.close()


def test_physics():
    print("\n── 2. Physics Validation ────────────────────────────")
    env = UrbanCanyonEnv(max_steps=1, seed=0)

    # All-zero phases (AI OFF)
    env.reset()
    env._user_pos = np.array([150.0, 150.0])
    rssi_off, snr_off, _ = env._compute_rssi(
        np.zeros(N_PANELS), np.zeros(N_PHASE_ELEMENTS), env._user_pos)

    # All-one phases (max aperture)
    rssi_on, snr_on, _ = env._compute_rssi(
        np.zeros(N_PANELS), np.ones(N_PHASE_ELEMENTS), env._user_pos)

    gain = rssi_on - rssi_off
    print(f"  AI OFF RSSI : {rssi_off:.1f} dBm")
    print(f"  AI ON  RSSI : {rssi_on:.1f} dBm")
    print(f"  O-RIS Gain  : +{gain:.1f} dB  (target > 10 dB)")
    assert gain > 5.0, f"Gain {gain:.1f} dB too low — check physics model"
    print(f"  ✓ Gain validation passed")
    print(f"  ✓ SNR: {snr_on:.1f} dB")
    env.close()


def test_quick_training():
    print("\n── 3. Quick PPO Training (5 000 steps) ──────────────")
    env = DummyVecEnv([make_env(seed=0)])
    env = VecNormalize(env, norm_obs=True, norm_reward=True)

    model = PPO("MlpPolicy", env, learning_rate=3e-4, n_steps=512,
                batch_size=64, verbose=0,
                policy_kwargs=dict(net_arch=[64, 64]))

    t0 = time.time()
    model.learn(5_000)
    elapsed = time.time() - t0

    # Save & reload
    model.save(os.path.join(OUTPUT_DIR, "quick_test_model.zip"))
    env.save(os.path.join(OUTPUT_DIR, "quick_test_stats.pkl"))
    print(f"  ✓ 5 000 steps trained in {elapsed:.1f}s")
    print(f"  ✓ Model saved to outputs/quick_test_model.zip")

    # Single inference latency
    dummy = np.zeros((1, 21), dtype=np.float32)
    times = []
    for _ in range(500):
        s = time.perf_counter()
        model.predict(dummy, deterministic=True)
        times.append((time.perf_counter()-s)*1000)
    print(f"  ✓ Inference: mean={np.mean(times):.3f}ms  "
          f"p99={np.percentile(times,99):.3f}ms  "
          f"(target < 2ms)")


def test_json_payload():
    print("\n── 4. JSON Payload Test ─────────────────────────────")
    env = UrbanCanyonEnv(max_steps=5, seed=0)
    env.reset()
    env._servo_angles = np.random.uniform(-15, 15, N_PANELS).astype(np.float32)
    env._phase_matrix = np.random.randint(0, 2, N_PHASE_ELEMENTS).astype(np.float32)

    payload = env.get_json_payload()
    assert "servo_angles"  in payload
    assert "phase_matrix"  in payload
    assert "target_azimuth" in payload
    assert len(payload["servo_angles"])  == N_PANELS
    assert len(payload["phase_matrix"])  == N_PHASE_ELEMENTS
    import json
    print(f"  ✓ Payload keys: {list(payload.keys())}")
    print(f"  ✓ Servo angles: {[round(a,1) for a in payload['servo_angles']]}")
    print(f"  ✓ Azimuth: {payload['target_azimuth']}°")
    print(f"  ✓ JSON size: {len(json.dumps(payload))} bytes")
    env.close()


if __name__ == "__main__":
    print("=" * 55)
    print("  O-RIS AI Layer 3 — Quick Test Suite")
    print("=" * 55)
    try:
        test_environment()
        test_physics()
        test_quick_training()
        test_json_payload()
        print("\n" + "=" * 55)
        print("  ✓✓ ALL TESTS PASSED — environment is ready!")
        print("  Next step: python agent/train_ppo.py")
        print("=" * 55)
    except AssertionError as e:
        print(f"\n  ✗ TEST FAILED: {e}")
        sys.exit(1)
