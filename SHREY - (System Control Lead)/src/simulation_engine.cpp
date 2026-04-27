#include "rf/simulation_engine.hpp"

#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <utility>

namespace rf {

namespace {

struct Vec3 {
    float x;
    float y;
    float z;
};

struct PanelFrame {
    Vec3 center;
    Vec3 tangent;
    Vec3 up;
    Vec3 normal;
};

constexpr float kPi = 3.14159265358979323846F;

float Wrap360(float value) {
    float wrapped = std::fmod(value, 360.0F);
    if (wrapped < 0.0F) {
        wrapped += 360.0F;
    }
    return wrapped;
}

float WrapSigned180(float value) {
    float wrapped = Wrap360(value);
    if (wrapped > 180.0F) {
        wrapped -= 360.0F;
    }
    return wrapped;
}

float Length(const Vec3& v) {
    return std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
}

float Dot(const Vec3& a, const Vec3& b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

Vec3 Sub(const Vec3& a, const Vec3& b) {
    return Vec3{a.x - b.x, a.y - b.y, a.z - b.z};
}

Vec3 Add(const Vec3& a, const Vec3& b) {
    return Vec3{a.x + b.x, a.y + b.y, a.z + b.z};
}

Vec3 Scale(const Vec3& v, const float s) {
    return Vec3{v.x * s, v.y * s, v.z * s};
}

Vec3 Normalize(const Vec3& v) {
    const float len = Length(v);
    if (len <= 1e-6F) {
        return Vec3{0.0F, 0.0F, 0.0F};
    }
    return Scale(v, 1.0F / len);
}

PanelFrame BuildPanelFrame(const std::uint8_t matrix, const float panelRadius) {
    const float theta = (2.0F * kPi * static_cast<float>(matrix)) / static_cast<float>(kMatrixCount);
    const Vec3 center{panelRadius * std::cos(theta), panelRadius * std::sin(theta), 0.0F};
    const Vec3 normal = Normalize(Vec3{std::cos(theta), std::sin(theta), 0.0F});
    const Vec3 tangent = Normalize(Vec3{-std::sin(theta), std::cos(theta), 0.0F});
    const Vec3 up{0.0F, 0.0F, 1.0F};
    return PanelFrame{center, tangent, up, normal};
}

Vec3 IncidentDirection(const float incidentAngleDeg) {
    const float incRad = incidentAngleDeg * (kPi / 180.0F);
    // Angle 0 deg means a broadside plane wave traveling toward -Y.
    return Normalize(Vec3{0.0F, -std::cos(incRad), -std::sin(incRad)});
}

Vec3 PatchPosition(const PatchCoordinate& coord, const float panelRadius, const float patchPitch) {
    const PanelFrame frame = BuildPanelFrame(coord.matrix, panelRadius);
    const float localX = (static_cast<float>(coord.col) - 7.5F) * patchPitch;
    const float localY = (static_cast<float>(coord.row) - 7.5F) * patchPitch;
    const Vec3 offset = Add(Scale(frame.tangent, localX), Scale(frame.up, localY));
    return Add(frame.center, offset);
}

} // namespace

SimulationEngine::SimulationEngine(const std::size_t registerCount)
    : controller_(registerCount), chain_(registerCount), lastFrame_{std::vector<std::uint8_t>(registerCount, 0)} {}

PatchController& SimulationEngine::controller() {
    return controller_;
}

const PatchController& SimulationEngine::controller() const {
    return controller_;
}

const ShiftRegisterChain& SimulationEngine::chain() const {
    return chain_;
}

const ShiftRegisterFrame& SimulationEngine::lastFrame() const {
    return lastFrame_;
}

bool SimulationEngine::autoScanEnabled() const {
    return autoScanEnabled_;
}

void SimulationEngine::setAutoScan(const bool enabled) {
    autoScanEnabled_ = enabled;
}

std::uint64_t SimulationEngine::tickCount() const {
    return tickCount_;
}

std::uint8_t SimulationEngine::activeMatrix() const {
    return activeMatrix_;
}

const std::vector<std::uint8_t>& SimulationEngine::registerBytes() const {
    return lastFrame_.bytes;
}

float SimulationEngine::incidentAngleDeg() const {
    return incidentAngleDeg_;
}

void SimulationEngine::setIncidentAngleDeg(const float value) {
    incidentAngleDeg_ = std::clamp(value, -89.0F, 89.0F);
}

float SimulationEngine::biasVoltage() const {
    return biasVoltage_;
}

void SimulationEngine::setBiasVoltage(const float value) {
    biasVoltage_ = std::clamp(value, 0.0F, 5.0F);
}

float SimulationEngine::thermalRise() const {
    return thermalRise_;
}

void SimulationEngine::setThermalRise(const float value) {
    thermalRise_ = std::clamp(value, 0.0F, 80.0F);
}

float SimulationEngine::focusX() const {
    return focusX_;
}

void SimulationEngine::setFocusX(const float value) {
    focusX_ = std::clamp(value, -5.0F, 5.0F);
}

float SimulationEngine::focusY() const {
    return focusY_;
}

void SimulationEngine::setFocusY(const float value) {
    focusY_ = std::clamp(value, -5.0F, 5.0F);
}

float SimulationEngine::focusZ() const {
    return focusZ_;
}

void SimulationEngine::setFocusZ(const float value) {
    focusZ_ = std::clamp(value, 0.1F, 20.0F);
}

float SimulationEngine::panelRadius() const {
    return panelRadius_;
}

void SimulationEngine::setPanelRadius(const float value) {
    panelRadius_ = std::clamp(value, 0.1F, 3.0F);
}

float SimulationEngine::patchPitch() const {
    return patchPitch_;
}

void SimulationEngine::setPatchPitch(const float value) {
    patchPitch_ = std::clamp(value, 0.001F, 0.05F);
}

float SimulationEngine::phaseShiftDeg(const std::size_t globalIndex) const {
    if (globalIndex >= controller_.states().size()) {
        throw std::out_of_range("Patch index is out of range.");
    }

    const auto coord = FromGlobalIndex(globalIndex);
    const bool on = controller_.states()[globalIndex] == DiodeState::On;
    const float diodePhase = on ? (biasVoltage_ * 35.0F + thermalRise_ * 2.8F) : (thermalRise_ * 0.5F);
    const float latticePhase = static_cast<float>(coord.row) * 1.1F + static_cast<float>(coord.col) * 0.75F;
    return Wrap360(diodePhase + latticePhase);
}

float SimulationEngine::targetPhaseDeg(const std::size_t globalIndex) const {
    if (globalIndex >= controller_.states().size()) {
        throw std::out_of_range("Patch index is out of range.");
    }

    const PatchCoordinate coord = FromGlobalIndex(globalIndex);
    const Vec3 patch = PatchPosition(coord, panelRadius_, patchPitch_);
    const Vec3 focus = Vec3{focusX_, focusY_, focusZ_};
    const Vec3 toFocus = Sub(focus, patch);
    const float pathOut = Length(toFocus);

    const Vec3 incidentDir = IncidentDirection(incidentAngleDeg_);
    const float pathIn = -Dot(patch, incidentDir);

    constexpr float kLambda = 0.03F;
    constexpr float kK = (2.0F * kPi) / kLambda;
    const float phase = (pathOut + pathIn) * kK * (180.0F / kPi);
    return Wrap360(phase);
}

float SimulationEngine::phaseErrorDeg(const std::size_t globalIndex) const {
    const float delta = targetPhaseDeg(globalIndex) - phaseShiftDeg(globalIndex);
    return WrapSigned180(delta);
}

float SimulationEngine::reflectionAngleDeg(const std::size_t globalIndex) const {
    if (globalIndex >= controller_.states().size()) {
        throw std::out_of_range("Patch index is out of range.");
    }
    const PatchCoordinate coord = FromGlobalIndex(globalIndex);
    const PanelFrame frame = BuildPanelFrame(coord.matrix, panelRadius_);
    const Vec3 patch = PatchPosition(coord, panelRadius_, patchPitch_);
    const Vec3 focus = Vec3{focusX_, focusY_, focusZ_};
    const Vec3 toFocus = Normalize(Sub(focus, patch));
    const float boresight = Dot(toFocus, frame.normal);
    const float lateral = Dot(toFocus, frame.tangent);
    const float steering = std::atan2(lateral, boresight) * (180.0F / kPi);
    const float correction = std::clamp(phaseErrorDeg(globalIndex) * 0.03F, -8.0F, 8.0F);
    return std::clamp(steering + correction, -89.0F, 89.0F);
}

void SimulationEngine::step() {
    if (autoScanEnabled_ && controller_.mappingMode() == MappingMode::MatrixScan) {
        activeMatrix_ = static_cast<std::uint8_t>((activeMatrix_ + 1) % kMatrixCount);
        controller_.setActiveMatrix(activeMatrix_);
    }
    pushFrame(controller_.buildFrame());
    ++tickCount_;
}

ShiftRegisterFrame SimulationEngine::setPatch(const PatchCoordinate& coord, const DiodeState state) {
    return pushFrame(controller_.setPatch(coord, state));
}

ShiftRegisterFrame SimulationEngine::togglePatch(const PatchCoordinate& coord) {
    return pushFrame(controller_.togglePatch(coord));
}

ShiftRegisterFrame SimulationEngine::setMatrix(const std::uint8_t matrix, const DiodeState state) {
    return pushFrame(controller_.setMatrix(matrix, state));
}

ShiftRegisterFrame SimulationEngine::setRow(const std::uint8_t matrix, const std::uint8_t row, const DiodeState state) {
    return pushFrame(controller_.setRow(matrix, row, state));
}

ShiftRegisterFrame SimulationEngine::setColumn(const std::uint8_t matrix, const std::uint8_t col, const DiodeState state) {
    return pushFrame(controller_.setColumn(matrix, col, state));
}

ShiftRegisterFrame SimulationEngine::setAll(const DiodeState state) {
    return pushFrame(controller_.setAll(state));
}

ShiftRegisterFrame SimulationEngine::applyPattern(const PatternPreset preset) {
    return pushFrame(controller_.applyPattern(preset));
}

ShiftRegisterFrame SimulationEngine::setRegisterByte(const std::size_t registerIndex, const std::uint8_t value) {
    if (registerIndex >= lastFrame_.bytes.size()) {
        throw std::out_of_range("Register index is out of range.");
    }
    auto updated = lastFrame_;
    updated.bytes[registerIndex] = value;
    return writeRegisterFrame(updated);
}

ShiftRegisterFrame SimulationEngine::setRegisterBit(const std::size_t registerIndex,
                                                    const std::uint8_t bitIndex,
                                                    const bool enabled) {
    if (registerIndex >= lastFrame_.bytes.size()) {
        throw std::out_of_range("Register index is out of range.");
    }
    if (bitIndex > 7) {
        throw std::out_of_range("Bit index is out of range.");
    }

    auto updated = lastFrame_;
    const std::uint8_t mask = static_cast<std::uint8_t>(1U << bitIndex);
    if (enabled) {
        updated.bytes[registerIndex] |= mask;
    } else {
        updated.bytes[registerIndex] &= static_cast<std::uint8_t>(~mask);
    }
    return writeRegisterFrame(updated);
}

ShiftRegisterFrame SimulationEngine::writeRegisterFrame(const ShiftRegisterFrame& frame) {
    const auto interpreted = controller_.applyShiftRegisterFrame(frame);
    chain_.loadFrame(frame);
    lastFrame_ = frame;

    if (controller_.mappingMode() == MappingMode::MatrixScan) {
        activeMatrix_ = controller_.activeMatrix();
    }
    return interpreted;
}

ShiftRegisterFrame SimulationEngine::rebuildFrame() {
    return pushFrame(controller_.buildFrame());
}

ShiftRegisterFrame SimulationEngine::pushFrame(const ShiftRegisterFrame& frame) {
    chain_.loadFrame(frame);
    lastFrame_ = frame;
    activeMatrix_ = controller_.activeMatrix();
    return lastFrame_;
}

} // namespace rf
