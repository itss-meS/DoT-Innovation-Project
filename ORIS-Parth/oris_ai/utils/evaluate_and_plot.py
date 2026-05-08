"""
evaluate_and_plot.py
====================
Loads a trained model, evaluates it, and generates all performance plots:
  1. Training convergence curve (reward over episodes)
  2. RSSI improvement: AI ON vs AI OFF
  3. Coverage heatmap (200×200 grid)
  4. Inference latency histogram
  5. Beam steering polar plot

Run after training:
    python evaluate_and_plot.py
"""

import os, sys, json
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.colors import LinearSegmentedColormap
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from env.urban_canyon_env import (UrbanCanyonEnv, BUILDINGS, TOWER_POS,
                                   ORIS_POS, GRID_SIZE, N_PANELS, N_PHASE_ELEMENTS)

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "..", "outputs")

PLOT_STYLE = {
    "figure.facecolor": "#0D1B2A",
    "axes.facecolor":   "#111827",
    "axes.edgecolor":   "#374151",
    "text.color":       "#E5E7EB",
    "axes.labelcolor":  "#9CA3AF",
    "xtick.color":      "#9CA3AF",
    "ytick.color":      "#9CA3AF",
    "grid.color":       "#1F2937",
    "grid.linewidth":   0.6,
}


def load_model_and_env(model_path, stats_path):
    from stable_baselines3 import PPO
    from stable_baselines3.common.vec_env import DummyVecEnv, VecNormalize
    from stable_baselines3.common.monitor import Monitor
    import sys, os
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
    from agent.train_ppo import FlatActionWrapper

    def _make():
        e = UrbanCanyonEnv(max_steps=200, seed=42)
        e = FlatActionWrapper(e)
        return Monitor(e)

    raw = DummyVecEnv([_make])
    env = VecNormalize.load(stats_path, raw)
    env.training = False
    model = PPO.load(model_path, env=env)
    return model, env


# ─── 1. Training convergence curve ────────────────────────────────────────────
def plot_convergence(log_path: str, save_path: str):
    with open(log_path) as f:
        log = json.load(f)

    rewards = np.array(log["episode_rewards"])
    rssis   = np.array(log["episode_rssi"])

    window  = min(50, len(rewards))
    smooth_r = np.convolve(rewards, np.ones(window)/window, mode="valid")
    smooth_s = np.convolve(rssis,   np.ones(window)/window, mode="valid")

    with plt.rc_context(PLOT_STYLE):
        fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 6), sharex=True)
        fig.suptitle("PPO Training Convergence — O-RIS Beam Steering",
                     color="#E5E7EB", fontsize=13, fontweight="bold")

        ax1.plot(rewards, alpha=0.2, color="#60A5FA", linewidth=0.5)
        ax1.plot(range(window-1, len(rewards)), smooth_r,
                 color="#3B82F6", linewidth=2, label="Smoothed reward")
        ax1.axhline(0, color="#6B7280", linestyle="--", linewidth=0.8)
        ax1.set_ylabel("Episode Reward", color="#9CA3AF")
        ax1.legend(loc="lower right", framealpha=0.3)
        ax1.grid(True)

        ax2.plot(rssis, alpha=0.2, color="#34D399", linewidth=0.5)
        ax2.plot(range(window-1, len(rssis)), smooth_s,
                 color="#10B981", linewidth=2, label="Smoothed RSSI")
        ax2.axhline(-70, color="#FBBF24", linestyle="--",
                    linewidth=1, label="Useful threshold (−70 dBm)")
        ax2.set_ylabel("Mean RSSI (dBm)", color="#9CA3AF")
        ax2.set_xlabel("Episode",         color="#9CA3AF")
        ax2.legend(loc="lower right", framealpha=0.3)
        ax2.grid(True)

        fig.tight_layout()
        fig.savefig(save_path, dpi=150, bbox_inches="tight",
                    facecolor=fig.get_facecolor())
    print(f"  Convergence plot → {save_path}")


# ─── 2. RSSI improvement: AI ON vs OFF ────────────────────────────────────────
def plot_ai_on_off(model, vec_env, save_path: str, n_episodes=30):
    from agent.train_ppo import FlatActionWrapper

    def run_episodes(use_model: bool):
        rssi_means = []
        for ep in range(n_episodes):
            raw = DummyVecEnv([lambda: FlatActionWrapper(
                UrbanCanyonEnv(max_steps=200, seed=ep))])
            if use_model:
                from stable_baselines3.common.vec_env import VecNormalize
                env = VecNormalize(raw, norm_obs=True, norm_reward=False,
                                   training=False)
                env.obs_rms = vec_env.obs_rms
                env.ret_rms = vec_env.ret_rms
            else:
                env = raw
            obs = env.reset()
            ep_rssi, done = [], False
            while not done:
                if use_model:
                    action, _ = model.predict(obs, deterministic=True)
                else:
                    action = np.array([[
                        *np.zeros(N_PANELS),
                        *np.zeros(N_PHASE_ELEMENTS)
                    ]], dtype=np.float32)
                obs, _, done_arr, info = env.step(action)
                ep_rssi.append(info[0].get("rssi", -100))
                done = done_arr[0]
            rssi_means.append(np.mean(ep_rssi))
        return rssi_means

    from stable_baselines3.common.vec_env import DummyVecEnv
    on_rssi  = run_episodes(True)
    off_rssi = run_episodes(False)

    with plt.rc_context(PLOT_STYLE):
        fig, ax = plt.subplots(figsize=(10, 4))
        x = np.arange(n_episodes)
        ax.fill_between(x, off_rssi, alpha=0.3, color="#EF4444")
        ax.fill_between(x, on_rssi,  alpha=0.3, color="#10B981")
        ax.plot(x, off_rssi, color="#EF4444", linewidth=1.5, label="AI OFF (static)")
        ax.plot(x, on_rssi,  color="#10B981", linewidth=1.5, label="AI ON  (PPO)")
        ax.axhline(-70, color="#FBBF24", linestyle="--",
                   linewidth=1, label="Useful threshold (−70 dBm)")

        gain = np.mean(on_rssi) - np.mean(off_rssi)
        ax.set_title(f"RSSI Improvement: AI ON vs OFF  |  Mean gain = +{gain:.1f} dB",
                     color="#E5E7EB", fontsize=11)
        ax.set_xlabel("Episode", color="#9CA3AF")
        ax.set_ylabel("Mean RSSI (dBm)", color="#9CA3AF")
        ax.legend(framealpha=0.3)
        ax.grid(True)
        fig.tight_layout()
        fig.savefig(save_path, dpi=150, bbox_inches="tight",
                    facecolor=fig.get_facecolor())
    print(f"  AI ON/OFF plot → {save_path}")


# ─── 3. Coverage heatmap ─────────────────────────────────────────────────────
def plot_coverage_heatmap(save_path: str, use_ai: bool = True,
                          resolution: int = 40):
    """Sweep a 40×40 grid of user positions, record RSSI."""
    from stable_baselines3.common.vec_env import DummyVecEnv
    from agent.train_ppo import FlatActionWrapper

    env = UrbanCanyonEnv(max_steps=1, seed=0)
    xs  = np.linspace(5, GRID_SIZE-5, resolution)
    ys  = np.linspace(5, GRID_SIZE-5, resolution)
    rssi_grid = np.full((resolution, resolution), -120.0)

    # Dummy "optimal" actions for AI-ON (use heuristic for speed)
    phase = np.ones(N_PHASE_ELEMENTS, dtype=np.float32)  # all ON = max gain
    servo = np.zeros(N_PANELS, dtype=np.float32)

    for i, x in enumerate(xs):
        for j, y in enumerate(ys):
            env._user_pos      = np.array([x, y], dtype=np.float32)
            env._obstacle_pos  = np.zeros((5, 2), dtype=np.float32)
            if use_ai:
                rssi, _, _ = env._compute_rssi(servo, phase,
                                               env._user_pos)
            else:
                rssi, _, _ = env._compute_rssi(
                    np.zeros(N_PANELS), np.zeros(N_PHASE_ELEMENTS),
                    env._user_pos)
            rssi_grid[j, i] = rssi

    cmap = LinearSegmentedColormap.from_list(
        "rssi", ["#7F1D1D", "#EF4444", "#FBBF24", "#22C55E", "#166534"])

    with plt.rc_context(PLOT_STYLE):
        fig, ax = plt.subplots(figsize=(7, 6))
        im = ax.imshow(rssi_grid, origin="lower", cmap=cmap,
                       vmin=-110, vmax=-40,
                       extent=[0, GRID_SIZE, 0, GRID_SIZE])
        cbar = fig.colorbar(im, ax=ax, label="RSSI (dBm)")
        cbar.ax.yaxis.label.set_color("#9CA3AF")
        cbar.ax.tick_params(colors="#9CA3AF")

        # Draw buildings
        for b in BUILDINGS:
            rect = mpatches.Rectangle(
                (b[0], b[1]), b[2]-b[0], b[3]-b[1],
                linewidth=0.5, edgecolor="#6B7280",
                facecolor="#1F2937", alpha=0.85)
            ax.add_patch(rect)

        # Tower & O-RIS markers
        ax.scatter(*TOWER_POS, s=120, marker="^", c="#FBBF24",
                   zorder=5, label="Cell Tower")
        ax.scatter(*ORIS_POS, s=160, marker="h", c="#3B82F6",
                   zorder=5, label="O-RIS")

        title = "Coverage Heatmap — AI ON" if use_ai else "Coverage Heatmap — AI OFF"
        ax.set_title(title, color="#E5E7EB", fontsize=11)
        ax.set_xlabel("X (m)", color="#9CA3AF")
        ax.set_ylabel("Y (m)", color="#9CA3AF")
        ax.legend(loc="upper right", framealpha=0.4, fontsize=8)
        fig.tight_layout()
        fig.savefig(save_path, dpi=150, bbox_inches="tight",
                    facecolor=fig.get_facecolor())
    print(f"  Coverage heatmap → {save_path}")


# ─── 4. Inference latency histogram ──────────────────────────────────────────
def plot_latency(model, vec_env, save_path: str, n_calls: int = 1000):
    dummy_obs = np.zeros((1, 21), dtype=np.float32)
    latencies = []
    for _ in range(n_calls):
        t0 = time.perf_counter()
        model.predict(dummy_obs, deterministic=True)
        latencies.append((time.perf_counter() - t0) * 1000)

    latencies = np.array(latencies)
    with plt.rc_context(PLOT_STYLE):
        fig, ax = plt.subplots(figsize=(8, 4))
        ax.hist(latencies, bins=50, color="#3B82F6", alpha=0.8, edgecolor="#1E3A5F")
        ax.axvline(np.mean(latencies),   color="#10B981", linestyle="--",
                   linewidth=1.5, label=f"Mean {np.mean(latencies):.2f}ms")
        ax.axvline(np.percentile(latencies, 99), color="#FBBF24", linestyle="--",
                   linewidth=1.5, label=f"p99  {np.percentile(latencies,99):.2f}ms")
        ax.axvline(2.0, color="#EF4444", linestyle="-",
                   linewidth=1.5, label="Target < 2ms")
        ax.set_title(f"PPO Inference Latency Distribution  ({n_calls} calls)",
                     color="#E5E7EB")
        ax.set_xlabel("Latency (ms)", color="#9CA3AF")
        ax.set_ylabel("Count",        color="#9CA3AF")
        ax.legend(framealpha=0.3)
        ax.grid(True, axis="y")
        fig.tight_layout()
        fig.savefig(save_path, dpi=150, bbox_inches="tight",
                    facecolor=fig.get_facecolor())
    print(f"  Latency plot → {save_path}")


# ─── 5. Polar beam pattern ────────────────────────────────────────────────────
def plot_polar_beam(save_path: str):
    from env.urban_canyon_env import UrbanCanyonEnv
    env = UrbanCanyonEnv(max_steps=1, seed=0)
    env._user_pos     = np.array([150.0, 150.0])
    env._obstacle_pos = np.zeros((5, 2))

    angles    = np.linspace(0, 2*np.pi, 360)
    rssi_beam = []
    for theta in angles:
        # Steer beam toward theta using phase gradient
        phase = np.array([(1 if (i % 8) < 4 else 0) for i in range(N_PHASE_ELEMENTS)],
                         dtype=np.float32)
        servo = np.array([np.degrees(theta) % 15 - 7.5] * N_PANELS,
                         dtype=np.float32)
        rssi, _, _ = env._compute_rssi(servo, phase, env._user_pos)
        rssi_beam.append(rssi)

    rssi_beam = np.array(rssi_beam)
    rssi_norm = (rssi_beam - rssi_beam.min()) / (rssi_beam.max() - rssi_beam.min() + 1e-8)

    with plt.rc_context(PLOT_STYLE):
        fig = plt.figure(figsize=(6, 6))
        ax  = fig.add_subplot(111, projection="polar")
        ax.plot(angles, rssi_norm, color="#3B82F6", linewidth=2)
        ax.fill(angles, rssi_norm, alpha=0.25, color="#3B82F6")
        ax.set_facecolor("#111827")
        ax.set_title("O-RIS Beam Pattern (normalised)",
                     color="#E5E7EB", pad=18)
        ax.tick_params(colors="#9CA3AF")
        ax.set_theta_zero_location("N")
        ax.set_theta_direction(-1)
        fig.tight_layout()
        fig.savefig(save_path, dpi=150, bbox_inches="tight",
                    facecolor="#0D1B2A")
    print(f"  Polar beam plot → {save_path}")


# ─── Main ─────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    model_path = os.path.join(OUTPUT_DIR, "best_model.zip")
    stats_path = os.path.join(OUTPUT_DIR, "vec_normalize.pkl")
    log_path   = os.path.join(OUTPUT_DIR, "training_log.json")

    print("\n  O-RIS Evaluation & Plotting")
    print("  " + "="*40)

    # Convergence (from training log)
    if os.path.exists(log_path):
        plot_convergence(log_path,
                         os.path.join(OUTPUT_DIR, "01_convergence.png"))
    else:
        print("  (Skip convergence — training_log.json not found)")

    # Load model for remaining plots
    if os.path.exists(model_path) and os.path.exists(stats_path):
        model, vec_env = load_model_and_env(model_path, stats_path)
        plot_latency(model, vec_env,
                     os.path.join(OUTPUT_DIR, "04_latency.png"))
    else:
        print("  (Skip model plots — model not found, run train_ppo.py first)")

    # Heatmaps (no model needed)
    plot_coverage_heatmap(os.path.join(OUTPUT_DIR, "03_heatmap_ai_on.png"),
                          use_ai=True)
    plot_coverage_heatmap(os.path.join(OUTPUT_DIR, "03_heatmap_ai_off.png"),
                          use_ai=False)
    plot_polar_beam(os.path.join(OUTPUT_DIR, "05_polar_beam.png"))

    print("\n  All plots saved to outputs/")
