"""
urban_canyon_env.py
===================
Custom Gymnasium environment simulating an urban canyon for O-RIS beam steering.

Physics model
-------------
- Free-space path loss (Friis):  L = 20*log10(d) + 20*log10(f) + 32.45  [dB]
- Building blockage:             +15–30 dB extra attenuation per wall hit
- O-RIS aperture gain:           G = 10*log10(N * A / λ²)  where N = active elements
- Beam steering (Snell):         sin(θr) − sin(θi) = (λ/2π) * (dφ/dx)
- Total RSSI at user:            RSSI = TX_power − path_loss + ris_gain − blockage

State Space  (21 dims)
----------------------
[ RSSI_panel_0..7 (8), SNR (1), user_x (1), user_y (1), obstacle_x0..y4 (10) ]

Action Space (2056 dims)
------------------------
[ servo_angles_0..7 (8 cont, ±15°) | phase_matrix_0..2047 (2048 binary) ]
"""

import numpy as np
import gymnasium as gym
from gymnasium import spaces
from typing import Optional, Tuple, Dict, Any

# ─── Physical constants ────────────────────────────────────────────────────────
FREQ_GHZ      = 3.5          # n78 band
FREQ_HZ       = FREQ_GHZ * 1e9
C             = 3e8
LAMBDA        = C / FREQ_HZ  # ~0.0857 m
TX_POWER_DBM  = 43.0         # typical gNB EIRP dBm
N_PANELS      = 8
CELLS_PER_PANEL = 256        # 16×16
N_PHASE_ELEMENTS = N_PANELS * CELLS_PER_PANEL  # 2048
PANEL_AREA    = 0.23 * 0.23  # 230mm × 230mm per panel
TOTAL_APERTURE = N_PANELS * PANEL_AREA
NOISE_FLOOR_DBM = -100.0
N_OBSTACLES   = 5
GRID_SIZE     = 200.0        # metres × metres simulation area
OBS_SIZE      = 4.0          # obstacle footprint radius (metres)

# ─── Map layout ───────────────────────────────────────────────────────────────
# Buildings defined as axis-aligned rectangles [x_min, y_min, x_max, y_max]
BUILDINGS = np.array([
    [ 10,  10,  60,  60],   # NW block
    [ 10, 130,  60, 190],   # SW block
    [140,  10, 190,  60],   # NE block
    [140, 130, 190, 190],   # SE block
    [ 70,  20, 130,  50],   # N mid block
    [ 70, 150, 130, 180],   # S mid block
    [ 20,  70,  50, 130],   # W mid block
    [150,  70, 180, 130],   # E mid block
], dtype=np.float32)

TOWER_POS   = np.array([5.0,  100.0])   # cell tower (200 m from O-RIS)
ORIS_POS    = np.array([100.0, 100.0])  # O-RIS at intersection centre


class UrbanCanyonEnv(gym.Env):
    """O-RIS Urban Canyon Reinforcement Learning Environment."""

    metadata = {"render_modes": ["human", "rgb_array"], "render_fps": 10}

    def __init__(self, render_mode: Optional[str] = None,
                 max_steps: int = 200, seed: Optional[int] = None):
        super().__init__()
        self.render_mode = render_mode
        self.max_steps   = max_steps
        self._rng        = np.random.default_rng(seed)

        # ── Observation space ─────────────────────────────────────────────────
        # [rssi×8, snr×1, user_xy×2, obs_xy×(5×2)] = 21 dims
        low  = np.array([-120.0]*8 + [-30.0] + [0.0]*2 + [0.0]*(N_OBSTACLES*2),
                        dtype=np.float32)
        high = np.array([  -30.0]*8 + [60.0] + [GRID_SIZE]*2 + [GRID_SIZE]*(N_OBSTACLES*2),
                        dtype=np.float32)
        self.observation_space = spaces.Box(low=low, high=high, dtype=np.float32)

        # ── Action space ──────────────────────────────────────────────────────
        # 8 servo angles ∈ [-15, +15] (degrees) + 2048 binary phase states
        servo_low  = np.full(N_PANELS, -15.0, dtype=np.float32)
        servo_high = np.full(N_PANELS,  15.0, dtype=np.float32)
        self.action_space = spaces.Dict({
            "servo_angles":  spaces.Box(low=servo_low, high=servo_high, dtype=np.float32),
            "phase_matrix":  spaces.MultiBinary(N_PHASE_ELEMENTS),
        })

        # Internal state
        self._step_count    = 0
        self._user_pos      = np.array([150.0, 150.0], dtype=np.float32)
        self._obstacle_pos  = np.zeros((N_OBSTACLES, 2), dtype=np.float32)
        self._servo_angles  = np.zeros(N_PANELS, dtype=np.float32)
        self._phase_matrix  = np.zeros(N_PHASE_ELEMENTS, dtype=np.float32)
        self._prev_rssi     = NOISE_FLOOR_DBM
        self._panel_azimuths = np.array([i * 45.0 for i in range(N_PANELS)],
                                        dtype=np.float32)  # degrees

    # ─────────────────────────────────────────────────────────────────────────
    # Physics helpers
    # ─────────────────────────────────────────────────────────────────────────

    def _free_space_loss(self, d: float) -> float:
        """Friis FSPL in dB.  d in metres, f in GHz.
        Formula: L = 20·log10(d_m) + 20·log10(f_GHz) + 32.44
        e.g.  95 m @ 3.5 GHz → 82.9 dB  ✓
        """
        if d < 0.1:
            d = 0.1
        return 20 * np.log10(d) + 20 * np.log10(FREQ_GHZ) + 32.44

    def _count_building_hits(self, p1: np.ndarray, p2: np.ndarray) -> int:
        """Count how many buildings the segment p1→p2 intersects."""
        hits = 0
        dx, dy = p2 - p1
        for b in BUILDINGS:
            xmin, ymin, xmax, ymax = b
            # Liang–Barsky line-box intersection
            p = [-dx, dx, -dy, dy]
            q = [p1[0]-xmin, xmax-p1[0], p1[1]-ymin, ymax-p1[1]]
            t0, t1 = 0.0, 1.0
            for pi, qi in zip(p, q):
                if abs(pi) < 1e-8:
                    if qi < 0:
                        t0 = 1.1  # no intersection
                        break
                else:
                    t = qi / pi
                    if pi < 0:
                        t0 = max(t0, t)
                    else:
                        t1 = min(t1, t)
            if t0 < t1:
                hits += 1
        return hits

    def _ris_gain_db(self, servo_angles: np.ndarray,
                     phase_matrix: np.ndarray) -> Tuple[float, float]:
        """
        Calculate O-RIS passive gain and optimal beam azimuth.

        Uses aperture synthesis: G = 10*log10(N_active * A / λ²)
        Beam steering via phase gradient (Generalised Snell's Law).
        Returns (gain_dB, beam_azimuth_deg).
        """
        # Compute phase gradient per panel
        # phase_matrix is (N_PANELS, CELLS_PER_PANEL)
        pm = phase_matrix.reshape(N_PANELS, CELLS_PER_PANEL)
        cell_pitch = 0.0057   # 5.7 mm in metres

        panel_gains = []
        azimuths = []
        for i in range(N_PANELS):
            panel_phases = pm[i] * np.pi  # 0 or π
            # Mean phase gradient (simplified 1D)
            cells_1d = int(np.sqrt(CELLS_PER_PANEL))  # 16
            phase_row = panel_phases[:cells_1d]
            if cells_1d > 1:
                dphi_dx = np.mean(np.diff(phase_row)) / cell_pitch
            else:
                dphi_dx = 0.0

            # Generalised Snell's Law: sin(θr) = sin(θi) + (λ/2π)*dφ/dx
            sin_theta_r = np.clip((LAMBDA / (2 * np.pi)) * dphi_dx, -1.0, 1.0)
            steer_angle_rad = np.arcsin(sin_theta_r)

            # Elevation from servo
            elev_rad = np.radians(np.clip(servo_angles[i], -15.0, 15.0))

            # Active elements: fraction of '1' states determines coherence
            n_active = int(np.sum(pm[i])) + 1  # avoid log(0)
            gain = 10 * np.log10(n_active * PANEL_AREA / (LAMBDA ** 2))
            gain = np.clip(gain, 0.0, 30.0)

            # Elevation taper
            elev_factor = np.cos(elev_rad) ** 2
            panel_gains.append(gain * elev_factor)
            # Panel azimuth + steering offset
            panel_az = self._panel_azimuths[i] + np.degrees(steer_angle_rad)
            azimuths.append(panel_az % 360)

        total_gain = float(np.max(panel_gains))
        best_panel  = int(np.argmax(panel_gains))
        beam_az     = float(azimuths[best_panel])
        return total_gain, beam_az

    def _obstacle_blockage(self, p1: np.ndarray) -> float:
        """Attenuation from dynamic obstacles near user."""
        blockage = 0.0
        for obs in self._obstacle_pos:
            d = np.linalg.norm(p1 - obs)
            if d < OBS_SIZE * 2:
                blockage += max(0.0, 10.0 * (1 - d / (OBS_SIZE * 2)))
        return blockage

    def _compute_rssi(self, servo_angles: np.ndarray,
                      phase_matrix: np.ndarray,
                      user_pos: np.ndarray) -> Tuple[float, float, np.ndarray]:
        """
        Compute RSSI (dBm) and SNR (dB) at user_pos given current O-RIS config.
        Also returns per-panel RSSI contributions.
        """
        # Direct path: tower → user (usually blocked in urban canyon)
        d_direct  = float(np.linalg.norm(TOWER_POS - user_pos))
        hits_direct = self._count_building_hits(TOWER_POS, user_pos)
        direct_loss = self._free_space_loss(d_direct) + hits_direct * 20.0
        # In deep shadow the direct path is blocked — floor it
        rssi_direct = TX_POWER_DBM - direct_loss

        # Reflected path: tower → O-RIS → user
        # For a passive RIS the two-hop signal scales as 1/(d1²·d2²), not 1/(d1+d2)².
        # We model this by using a single equivalent distance = sqrt(d_inc * d_refl)
        # then deducting a constant 6 dB penalty for the two-hop geometry.
        d_inc  = float(np.linalg.norm(TOWER_POS - ORIS_POS))
        d_refl = float(np.linalg.norm(ORIS_POS  - user_pos))
        d_equiv = float(np.sqrt(d_inc * d_refl))    # geometric mean ≈ effective 1-hop d
        hits_inc  = self._count_building_hits(TOWER_POS, ORIS_POS)
        hits_refl = self._count_building_hits(ORIS_POS,  user_pos)
        ris_gain, _ = self._ris_gain_db(servo_angles, phase_matrix)

        path_loss_ris = (self._free_space_loss(d_equiv)
                         + 6.0                        # two-hop penalty
                         + hits_inc  * 8.0
                         + hits_refl * 8.0
                         - ris_gain)
        rssi_ris = TX_POWER_DBM - path_loss_ris

        # Dynamic obstacle blockage near user
        obs_att  = self._obstacle_blockage(user_pos)
        rssi_ris -= obs_att

        # Combined RSSI (incoherent sum in linear then back to dB)
        def db2lin(x): return 10 ** (x / 10)
        def lin2db(x): return 10 * np.log10(max(x, 1e-20))
        rssi_total = lin2db(db2lin(rssi_direct) + db2lin(rssi_ris))
        rssi_total = float(np.clip(rssi_total, -120.0, -30.0))

        noise_floor = NOISE_FLOOR_DBM + float(self._rng.normal(0, 0.5))
        snr = float(np.clip(rssi_total - noise_floor, -30.0, 60.0))

        # Per-panel RSSI (jitter for realism)
        pm = phase_matrix.reshape(N_PANELS, CELLS_PER_PANEL)
        panel_rssi = np.array([
            rssi_total + float(self._rng.normal(0, 1.5))
            - max(0, 5 * (1 - np.sum(pm[i]) / CELLS_PER_PANEL))
            for i in range(N_PANELS)
        ], dtype=np.float32)
        panel_rssi = np.clip(panel_rssi, -120.0, -30.0)

        return rssi_total, snr, panel_rssi

    # ─────────────────────────────────────────────────────────────────────────
    # Gymnasium interface
    # ─────────────────────────────────────────────────────────────────────────

    def reset(self, *, seed=None, options=None) -> Tuple[np.ndarray, Dict]:
        super().reset(seed=seed)
        if seed is not None:
            self._rng = np.random.default_rng(seed)

        self._step_count = 0

        # Randomise user in NLoS shadow zone (SE quadrant away from tower)
        self._user_pos = self._rng.uniform(
            [110.0, 110.0], [190.0, 190.0]).astype(np.float32)

        # Randomise obstacle positions around user
        for i in range(N_OBSTACLES):
            offset = self._rng.uniform(-30.0, 30.0, 2)
            self._obstacle_pos[i] = np.clip(
                self._user_pos + offset, 5.0, GRID_SIZE - 5.0).astype(np.float32)

        # Default action: all zeros
        self._servo_angles = np.zeros(N_PANELS, dtype=np.float32)
        self._phase_matrix = np.zeros(N_PHASE_ELEMENTS, dtype=np.float32)

        rssi, snr, panel_rssi = self._compute_rssi(
            self._servo_angles, self._phase_matrix, self._user_pos)
        self._prev_rssi = rssi

        obs = self._build_obs(panel_rssi, snr)
        return obs, {"rssi": rssi, "snr": snr}

    def step(self, action: Dict) -> Tuple[np.ndarray, float, bool, bool, Dict]:
        self._step_count += 1

        servo = np.clip(action["servo_angles"].astype(np.float32), -15.0, 15.0)
        phase = np.clip(action["phase_matrix"].astype(np.float32), 0.0, 1.0)

        self._servo_angles = servo
        self._phase_matrix = phase

        # Move obstacles slightly each step (dynamic environment)
        move = self._rng.uniform(-1.0, 1.0, (N_OBSTACLES, 2)).astype(np.float32)
        self._obstacle_pos = np.clip(
            self._obstacle_pos + move, 5.0, GRID_SIZE - 5.0)

        rssi, snr, panel_rssi = self._compute_rssi(servo, phase, self._user_pos)
        _, beam_az = self._ris_gain_db(servo, phase)

        # ── Reward ────────────────────────────────────────────────────────────
        alpha, beta, gamma = 1.0, 0.01, 0.005
        delta_rssi  = rssi - self._prev_rssi
        power_penalty = float(np.mean(np.abs(servo)) / 15.0 +
                               np.mean(phase) * 0.5)
        # Latency penalty: fraction of active phase elements (proxy for compute)
        latency_proxy = float(np.sum(phase)) / N_PHASE_ELEMENTS

        reward = (alpha * delta_rssi
                  - beta * latency_proxy
                  - gamma * power_penalty)

        # Bonus: if RSSI crosses useful threshold
        if rssi > -70.0:
            reward += 1.0
        if rssi > -60.0:
            reward += 2.0

        self._prev_rssi = rssi

        obs = self._build_obs(panel_rssi, snr)
        terminated = False
        truncated   = self._step_count >= self.max_steps

        info = {
            "rssi":      rssi,
            "snr":       snr,
            "beam_az":   beam_az,
            "step":      self._step_count,
            "delta_rssi": delta_rssi,
        }
        return obs, float(reward), terminated, truncated, info

    def _build_obs(self, panel_rssi: np.ndarray, snr: float) -> np.ndarray:
        obs = np.concatenate([
            panel_rssi,                          # 8
            [snr],                               # 1
            self._user_pos,                      # 2
            self._obstacle_pos.flatten(),        # 10
        ]).astype(np.float32)
        return obs

    def get_json_payload(self) -> dict:
        """Return current action as JSON-serialisable dict (for API/integration)."""
        _, beam_az = self._ris_gain_db(self._servo_angles, self._phase_matrix)
        return {
            "timestamp":      self._step_count,
            "servo_angles":   self._servo_angles.tolist(),
            "phase_matrix":   self._phase_matrix.astype(int).tolist(),
            "target_azimuth": round(float(beam_az), 1),
            "target_elevation": round(float(np.mean(self._servo_angles)), 1),
        }

    def render(self):
        if self.render_mode == "human":
            rssi, snr, _ = self._compute_rssi(
                self._servo_angles, self._phase_matrix, self._user_pos)
            print(f"Step {self._step_count:3d} | RSSI={rssi:.1f} dBm | "
                  f"SNR={snr:.1f} dB | User=({self._user_pos[0]:.0f},{self._user_pos[1]:.0f})")

    def close(self):
        pass
