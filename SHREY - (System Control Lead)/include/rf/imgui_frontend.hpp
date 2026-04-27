#pragma once

#include "rf/simulation_engine.hpp"

namespace rf {

struct UiState {
    int selectedMatrix = 0;
    int selectedRegister = 0;
    float octagonRotationDeg = 0.0F;
    float pitchDeg = -18.0F;
    float octagonZoom = 1.0F;
};

void RenderFrontend(SimulationEngine& engine, UiState& state);

} // namespace rf
