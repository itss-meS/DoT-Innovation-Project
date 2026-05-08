# O-RIS Layer 3 - AI/ML Beam Steering

Team: The Prism of Zero-Lat Futures  
Event: DoT 5G Innovation Hackathon 2026

## Overview

This project demonstrates AI-driven beam steering for an O-RIS metasurface in a realistic urban canyon setup. The main showcase is a browser-based 3D dashboard with:

- A procedural 3D city scene with realistic roads, dense buildings, parks, tower source, O-RIS node, user marker, and vehicle obstacles
- Real-time AI beam steering behavior with live RSSI, SNR, beam direction, latency, and gain indicators
- Interactive placement of the user and obstacles directly in the 3D scene
- Stable presentation mode for demos and hackathon judging

## Recommended Run Flow

```bash
# Install dependencies
pip install -r requirements.txt

# Validate project health
python quick_test.py

# Open the main 3D dashboard
dashboard/index.html
```

You can also run:

```bash
# Full PPO training
python agent/train_ppo.py --timesteps 2048000

# Generate evaluation plots
python utils/evaluate_and_plot.py

# Start inference server
python server/inference_server.py --model outputs/best_model.zip --stats outputs/vec_normalize.pkl --port 8765
```

## Main Files

```text
oris_ai/
├── agent/train_ppo.py
├── env/urban_canyon_env.py
├── server/inference_server.py
├── utils/evaluate_and_plot.py
├── dashboard/
│   ├── index.html
│   ├── styles.css
│   ├── simulation.js
│   ├── scene3d.js
│   └── dashboard.js
├── outputs/
├── quick_test.py
└── requirements.txt
```

## Dashboard Controls

- Click in the 3D scene to place the user
- `Add Obstacle` then click to place a 3D vehicle obstacle
- `AI ON/OFF` toggles beam steering
- `Camera` or keyboard `C` cycles camera presets
- `F` fullscreen
- `R` reset
- `P` show or hide presentation overlay

## Status

Current build focus:

- Browser-first 3D demo experience
- Stable visual presentation for judging
- Training and evaluation utilities preserved
