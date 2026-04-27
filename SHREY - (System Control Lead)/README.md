# SHREY RF Patch Controller Simulator

Interactive C++ simulator for controlling **2048 RF reflective patches** (8 panels x 16x16 patches) through a virtual **64 x 74HC595** shift-register chain. The app combines:

- logical diode-state patch control,
- frame generation for direct and matrix-scan mappings,
- an RF-inspired phase/reflection model,
- a Dear ImGui desktop UI with live 2D and 3D visualization.

## What this project does

The simulator models an octagonal RF panel assembly where each side is a 16x16 patch matrix. You can switch patch states, stream register frames, and observe how control values influence reflection behavior and phase error.

Core model sizes:

- Panels: `8`
- Patches per panel: `16 x 16 = 256`
- Total patches: `2048`
- Shift registers: `64`
- Total shift-register outputs: `512`

## Architecture

Main runtime components:

- `rf::PatchController` (`include/rf/patch_controller.hpp`, `src/patch_controller.cpp`)
  - Owns all patch states.
  - Builds output frames in `Direct` or `MatrixScan` mode.
  - Applies patterns and patch/matrix/row/column operations.

- `rf::ShiftRegisterChain` (`include/rf/shift_register_chain.hpp`, `src/shift_register_chain.cpp`)
  - Simulates clock/latch behavior of chained 74HC595-style registers.
  - Converts between bytes and per-bit output state.

- `rf::SimulationEngine` (`include/rf/simulation_engine.hpp`, `src/simulation_engine.cpp`)
  - Coordinates controller + shift-register chain.
  - Maintains runtime state (`tick`, active matrix, last frame).
  - Computes phase shift, target phase, phase error, and reflection angle.

- `rf::RenderFrontend` (`include/rf/imgui_frontend.hpp`, `src/imgui_frontend.cpp`)
  - Renders UI controls, register editor, matrix grid, and 3D octagonal prism visualization.

- `main.cpp`
  - Sets up GLFW + OpenGL2 + Dear ImGui loop and calls `RenderFrontend`.

## Requirements

- Windows 10/11
- CMake `>= 3.20`
- C++20-capable compiler (GCC 11+ recommended, or modern MSVC)
- Ninja (recommended generator)
- Internet access on first configure (CMake `FetchContent` downloads `glfw` and `imgui`)

## Build and run (PowerShell)

### Option A: Use tools from PATH

```powershell
Set-Location "D:\DoT\SHREY"
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build --target SHREY
.\build\SHREY.exe
```

### Option B: Use explicit CLion-bundled tools

```powershell
Set-Location "D:\DoT\SHREY"
$cmake = "D:\CLion 2026.1\bin\cmake\win\x64\bin\cmake.exe"
$ninja = "D:\CLion 2026.1\bin\ninja\win\x64\ninja.exe"

& $cmake -S . -B cmake-build-default -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_MAKE_PROGRAM="$ninja"
& $cmake --build cmake-build-default --target SHREY
& ".\cmake-build-default\SHREY.exe"
```

## CLion setup

- Open folder: `D:\DoT\SHREY`
- CMake profile:
  - Generator: `Ninja`
  - Build type: `Debug`
  - Toolchain/compiler: C++20-capable
- Build target: `SHREY`
- Run configuration executable: `<build-dir>\SHREY.exe`

## UI and controls

The UI is fixed-layout and split into panels:

- **RF Patch Control**
  - Auto scan toggle and manual step.
  - Mapping mode switch (`Direct` / `Matrix scan`).
  - Matrix selector (`0..7`).
  - Physical/control sliders:
	- incident angle,
	- diode bias voltage,
	- thermal rise,
	- focus point `(X, Y, Z)`,
	- octagon radius,
	- patch pitch.
  - Fast actions: all ON/OFF and 4 presets (checkerboard, H stripes, V stripes, quadrants).

- **64 Shift Register Control**
  - Inspect and edit any register byte (`R0..R63`).
  - Per-bit toggle controls (`b0..b7`).
  - Rebuild frame from logical patch state.

- **3D Octagonal Prism Array**
  - Interactive 3D view of all 8 panels.
  - Drag to rotate yaw/pitch, wheel to zoom.
  - Click a side face to select the active matrix.

## Mapping modes

### MatrixScan (default)

- Uses a 256-bit patch window for the currently active matrix.
- Uses one-hot matrix select and row mask bits.
- Requires at least `280` outputs (`35` bytes), so 64 registers are sufficient.

Important frame regions shown in UI:

- `R0..R31` -> 256 patch bits (active matrix)
- `R32 bit0..7` -> one-hot active matrix select
- `R33..R34` -> 16 row-enable bits

### Direct

- Maps patch states directly to shift-register outputs in index order.
- Throws an overflow error if ON patches require more outputs than available.

## RF/phase model notes

The simulation computes per-patch metrics from current logical state and geometric settings:

- `phaseShiftDeg(index)`
- `targetPhaseDeg(index)`
- `phaseErrorDeg(index)`
- `reflectionAngleDeg(index)`

These values drive the reflection gradient coloring and steering feedback shown in the UI.

## Screenshots

These captures show the simulator in different interaction states from one session: baseline view, control adjustments, and later reflection-map changes.

![Screenshot 2026-04-27 094250](imgs/Screenshot%202026-04-27%20094250.png)

![Screenshot 2026-04-27 094317](imgs/Screenshot%202026-04-27%20094317.png)

![Screenshot 2026-04-27 094337](imgs/Screenshot%202026-04-27%20094337.png)

![Screenshot 2026-04-27 094400](imgs/Screenshot%202026-04-27%20094400.png)

## Troubleshooting

- `cmake` not recognized:
  - Add CMake to PATH, or run CMake by full path.

- Cache path mismatch error (`CMakeCache.txt` created on another drive/path):
  - Remove stale build directory and reconfigure.

- Build fails with old compiler:
  - Ensure your compiler supports C++20.

- FetchContent/download issues:
  - Check internet/proxy/firewall access to GitHub.

- `build.py` / `rebuild.bat` path problems:
  - These scripts currently contain hardcoded `E:\...` paths and may need local updates.

## Project layout

```text
SHREY/
  CMakeLists.txt
  main.cpp
  include/rf/
	patch_types.hpp
	patch_controller.hpp
	shift_register_chain.hpp
	simulation_engine.hpp
	imgui_frontend.hpp
  src/
	patch_controller.cpp
	shift_register_chain.cpp
	simulation_engine.cpp
	imgui_frontend.cpp
  imgs/
	Screenshot ... .png
```

## Notes for contributors

- Keep UI changes aligned with fixed-layout behavior unless intentionally redesigning.
- Prefer updating `CMakeLists.txt` over adding machine-specific build scripts.
- If you add new simulation parameters, expose them through both `SimulationEngine` and `RenderFrontend` for observability.
