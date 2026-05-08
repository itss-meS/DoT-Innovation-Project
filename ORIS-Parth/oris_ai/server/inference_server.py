"""
inference_server.py
===================
Lightweight HTTP + WebSocket inference server.
Person B's GUI connects here to get real-time beam commands.

Endpoints
---------
POST /state   → send 21-dim state JSON → get JSON beam command back
GET  /status  → health check
WS   /ws      → bidirectional websocket stream

Usage
-----
    python inference_server.py --model outputs/best_model.zip \
                               --stats  outputs/vec_normalize.pkl \
                               --port   8765
"""

import argparse, asyncio, json, os, sys, time
import numpy as np
import torch
from http.server import BaseHTTPRequestHandler, HTTPServer
import threading

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from env.urban_canyon_env import UrbanCanyonEnv, N_PANELS, N_PHASE_ELEMENTS

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "..", "outputs")


class ORISInferenceEngine:
    """Wraps the trained PPO model for <2ms inference."""

    def __init__(self, model_path: str, stats_path: str):
        from stable_baselines3 import PPO
        from stable_baselines3.common.vec_env import DummyVecEnv, VecNormalize

        # Minimal env just for loading normalisation stats
        def _make():
            from agent.train_ppo import FlatActionWrapper
            from stable_baselines3.common.monitor import Monitor
            e = UrbanCanyonEnv(max_steps=200)
            e = FlatActionWrapper(e)
            return Monitor(e)

        raw = DummyVecEnv([_make])
        self.vec_env = VecNormalize.load(stats_path, raw)
        self.vec_env.training = False
        self.model = PPO.load(model_path, env=self.vec_env)
        self.model.policy.eval()
        print(f"  Model loaded from {model_path}")
        self._warmup()

    def _warmup(self):
        dummy = np.zeros((1, 21), dtype=np.float32)
        for _ in range(10):
            self.model.predict(dummy, deterministic=True)
        print("  Inference engine warmed up.")

    def predict(self, state_vec: np.ndarray) -> dict:
        """
        state_vec: np.ndarray shape (21,)
        Returns JSON-ready dict with servo_angles, phase_matrix, etc.
        """
        t0 = time.perf_counter()
        obs = state_vec.reshape(1, -1).astype(np.float32)
        # Normalise using VecNormalize stats
        obs_norm = self.vec_env.normalize_obs(obs)
        action, _ = self.model.predict(obs_norm, deterministic=True)
        action = action[0]

        servo = np.clip(action[:N_PANELS] * 15.0, -15.0, 15.0)
        phase = (action[N_PANELS:] > 0.5).astype(int)

        latency_ms = (time.perf_counter() - t0) * 1000

        return {
            "timestamp":        int(time.time() * 1000),
            "servo_angles":     servo.tolist(),
            "phase_matrix":     phase.tolist(),
            "target_azimuth":   float(round(np.mean(np.abs(servo)), 1)),
            "target_elevation": float(round(float(np.mean(servo)), 1)),
            "inference_ms":     round(latency_ms, 3),
        }


# ── Global engine (loaded once) ────────────────────────────────────────────────
_engine: ORISInferenceEngine = None


class RequestHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # silence default logs

    def _send_json(self, code: int, data: dict):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if self.path == "/status":
            self._send_json(200, {
                "status": "ok",
                "model": "oris_ppo",
                "device": "cuda" if torch.cuda.is_available() else "cpu",
            })
        else:
            self._send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/state":
            length = int(self.headers.get("Content-Length", 0))
            body   = self.rfile.read(length)
            try:
                payload = json.loads(body)
                state   = np.array(payload["state"], dtype=np.float32)
                if state.shape != (21,):
                    self._send_json(400, {"error": "state must be 21 floats"})
                    return
                result = _engine.predict(state)
                self._send_json(200, result)
            except Exception as e:
                self._send_json(500, {"error": str(e)})
        else:
            self._send_json(404, {"error": "not found"})


def start_server(model_path: str, stats_path: str, port: int = 8765):
    global _engine
    print(f"\n  Loading inference engine...")
    _engine = ORISInferenceEngine(model_path, stats_path)

    server = HTTPServer(("0.0.0.0", port), RequestHandler)
    print(f"\n  ✓ O-RIS Inference Server running on http://0.0.0.0:{port}")
    print(f"    POST /state  — send 21-dim state, get beam command")
    print(f"    GET  /status — health check")
    print(f"    Press Ctrl+C to stop\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n  Server stopped.")


# ─── Quick demo client (for testing) ──────────────────────────────────────────
def demo_client(port: int = 8765, n_calls: int = 20):
    import urllib.request
    url = f"http://localhost:{port}/state"
    latencies = []
    print(f"\n  Demo client — {n_calls} inference calls to {url}")
    for i in range(n_calls):
        # Random 21-dim state
        state = np.random.uniform(-100, -40, 21).tolist()
        payload = json.dumps({"state": state}).encode()
        t0 = time.perf_counter()
        req = urllib.request.Request(url, data=payload,
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=2) as resp:
            result = json.loads(resp.read())
        ms = (time.perf_counter() - t0) * 1000
        latencies.append(ms)
        print(f"  [{i+1:2d}] az={result['target_azimuth']:5.1f}°  "
              f"el={result['target_elevation']:+5.1f}°  "
              f"inf={result['inference_ms']:.2f}ms  "
              f"total={ms:.2f}ms")
    print(f"\n  Mean latency : {np.mean(latencies):.2f}ms")
    print(f"  P99  latency : {np.percentile(latencies,99):.2f}ms")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default=os.path.join(OUTPUT_DIR,"best_model.zip"))
    parser.add_argument("--stats", default=os.path.join(OUTPUT_DIR,"vec_normalize.pkl"))
    parser.add_argument("--port",  type=int, default=8765)
    parser.add_argument("--demo-client", action="store_true")
    args = parser.parse_args()

    if args.demo_client:
        demo_client(args.port)
    else:
        start_server(args.model, args.stats, args.port)
