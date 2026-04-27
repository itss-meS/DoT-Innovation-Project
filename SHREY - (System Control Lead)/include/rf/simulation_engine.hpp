#pragma once

#include "rf/patch_controller.hpp"
#include "rf/shift_register_chain.hpp"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace rf {

class SimulationEngine {
public:
    explicit SimulationEngine(std::size_t registerCount = 64);

    [[nodiscard]] PatchController& controller();
    [[nodiscard]] const PatchController& controller() const;
    [[nodiscard]] const ShiftRegisterChain& chain() const;
    [[nodiscard]] const ShiftRegisterFrame& lastFrame() const;

    [[nodiscard]] bool autoScanEnabled() const;
    void setAutoScan(bool enabled);

    [[nodiscard]] std::uint64_t tickCount() const;
    [[nodiscard]] std::uint8_t activeMatrix() const;
    [[nodiscard]] const std::vector<std::uint8_t>& registerBytes() const;

    [[nodiscard]] float incidentAngleDeg() const;
    void setIncidentAngleDeg(float value);
    [[nodiscard]] float biasVoltage() const;
    void setBiasVoltage(float value);
    [[nodiscard]] float thermalRise() const;
    void setThermalRise(float value);
    [[nodiscard]] float focusX() const;
    void setFocusX(float value);
    [[nodiscard]] float focusY() const;
    void setFocusY(float value);
    [[nodiscard]] float focusZ() const;
    void setFocusZ(float value);
    [[nodiscard]] float panelRadius() const;
    void setPanelRadius(float value);
    [[nodiscard]] float patchPitch() const;
    void setPatchPitch(float value);

    [[nodiscard]] float phaseShiftDeg(std::size_t globalIndex) const;
    [[nodiscard]] float targetPhaseDeg(std::size_t globalIndex) const;
    [[nodiscard]] float phaseErrorDeg(std::size_t globalIndex) const;
    [[nodiscard]] float reflectionAngleDeg(std::size_t globalIndex) const;

    void step();

    ShiftRegisterFrame setPatch(const PatchCoordinate& coord, DiodeState state);
    ShiftRegisterFrame togglePatch(const PatchCoordinate& coord);
    ShiftRegisterFrame setMatrix(std::uint8_t matrix, DiodeState state);
    ShiftRegisterFrame setRow(std::uint8_t matrix, std::uint8_t row, DiodeState state);
    ShiftRegisterFrame setColumn(std::uint8_t matrix, std::uint8_t col, DiodeState state);
    ShiftRegisterFrame setAll(DiodeState state);
    ShiftRegisterFrame applyPattern(PatternPreset preset);
    ShiftRegisterFrame setRegisterByte(std::size_t registerIndex, std::uint8_t value);
    ShiftRegisterFrame setRegisterBit(std::size_t registerIndex, std::uint8_t bitIndex, bool enabled);
    ShiftRegisterFrame writeRegisterFrame(const ShiftRegisterFrame& frame);
    ShiftRegisterFrame rebuildFrame();

private:
    ShiftRegisterFrame pushFrame(const ShiftRegisterFrame& frame);

    PatchController controller_;
    ShiftRegisterChain chain_;
    ShiftRegisterFrame lastFrame_{};
    bool autoScanEnabled_{true};
    std::uint64_t tickCount_{0};
    std::uint8_t activeMatrix_{0};
    float incidentAngleDeg_{25.0F};
    float biasVoltage_{2.5F};
    float thermalRise_{12.0F};
    float focusX_{0.0F};
    float focusY_{0.0F};
    float focusZ_{1.5F};
    float panelRadius_{0.55F};
    float patchPitch_{0.012F};
};

} // namespace rf
