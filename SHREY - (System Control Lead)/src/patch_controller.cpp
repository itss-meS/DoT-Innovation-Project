#include "rf/patch_controller.hpp"

#include <algorithm>
#include <stdexcept>

namespace rf {

namespace {

void SetBit(std::vector<std::uint8_t>& bytes, const std::size_t bitIndex, const bool value) {
    const std::size_t byteIndex = bitIndex / 8;
    const std::size_t bitOffset = bitIndex % 8;
    if (byteIndex >= bytes.size()) {
        throw std::out_of_range("Bit index exceeds frame size.");
    }

    const std::uint8_t mask = static_cast<std::uint8_t>(1U << bitOffset);
    if (value) {
        bytes[byteIndex] |= mask;
    } else {
        bytes[byteIndex] &= static_cast<std::uint8_t>(~mask);
    }
}

bool GetBit(const std::vector<std::uint8_t>& bytes, const std::size_t bitIndex) {
    const std::size_t byteIndex = bitIndex / 8;
    const std::size_t bitOffset = bitIndex % 8;
    if (byteIndex >= bytes.size()) {
        throw std::out_of_range("Bit index exceeds frame size.");
    }
    return (bytes[byteIndex] & static_cast<std::uint8_t>(1U << bitOffset)) != 0;
}

} // namespace

PatchController::PatchController(const std::size_t registerCount)
    : registerCount_(registerCount), states_(kTotalPatches, DiodeState::Off) {
    if (registerCount_ == 0) {
        throw std::invalid_argument("registerCount must be greater than zero.");
    }
}

void PatchController::setMappingMode(const MappingMode mode) {
    mappingMode_ = mode;
}

MappingMode PatchController::mappingMode() const {
    return mappingMode_;
}

void PatchController::setActiveMatrix(const std::uint8_t matrix) {
    if (matrix >= kMatrixCount) {
        throw std::out_of_range("Matrix index is out of range.");
    }
    activeMatrix_ = matrix;
}

std::uint8_t PatchController::activeMatrix() const {
    return activeMatrix_;
}

const std::vector<DiodeState>& PatchController::states() const {
    return states_;
}

std::size_t PatchController::registerCount() const {
    return registerCount_;
}

ShiftRegisterFrame PatchController::setPatch(const PatchCoordinate& coord, const DiodeState state) {
    return setPatch(ToGlobalIndex(coord), state);
}

ShiftRegisterFrame PatchController::setPatch(const std::size_t globalIndex, const DiodeState state) {
    if (globalIndex >= states_.size()) {
        throw std::out_of_range("Patch index is out of range.");
    }
    states_[globalIndex] = state;
    return buildFrame();
}

ShiftRegisterFrame PatchController::togglePatch(const PatchCoordinate& coord) {
    const std::size_t index = ToGlobalIndex(coord);
    states_[index] = states_[index] == DiodeState::On ? DiodeState::Off : DiodeState::On;
    return buildFrame();
}

ShiftRegisterFrame PatchController::setMatrix(const std::uint8_t matrix, const DiodeState state) {
    if (matrix >= kMatrixCount) {
        throw std::out_of_range("Matrix index is out of range.");
    }
    const std::size_t base = static_cast<std::size_t>(matrix) * kPatchesPerMatrix;
    std::fill(states_.begin() + base,
              states_.begin() + base + kPatchesPerMatrix,
              state);
    return buildFrame();
}

ShiftRegisterFrame PatchController::setRow(const std::uint8_t matrix, const std::uint8_t row, const DiodeState state) {
    if (matrix >= kMatrixCount || row >= kMatrixRows) {
        throw std::out_of_range("Matrix/row is out of range.");
    }
    for (std::size_t col = 0; col < kMatrixCols; ++col) {
        states_[ToGlobalIndex(PatchCoordinate{matrix, row, static_cast<std::uint8_t>(col)})] = state;
    }
    return buildFrame();
}

ShiftRegisterFrame PatchController::setColumn(const std::uint8_t matrix, const std::uint8_t col, const DiodeState state) {
    if (matrix >= kMatrixCount || col >= kMatrixCols) {
        throw std::out_of_range("Matrix/column is out of range.");
    }
    for (std::size_t row = 0; row < kMatrixRows; ++row) {
        states_[ToGlobalIndex(PatchCoordinate{matrix, static_cast<std::uint8_t>(row), col})] = state;
    }
    return buildFrame();
}

ShiftRegisterFrame PatchController::setAll(const DiodeState state) {
    std::fill(states_.begin(), states_.end(), state);
    return buildFrame();
}

ShiftRegisterFrame PatchController::applyPattern(const PatternPreset preset) {
    for (std::size_t index = 0; index < states_.size(); ++index) {
        const PatchCoordinate coord = FromGlobalIndex(index);
        bool turnOn = false;
        switch (preset) {
            case PatternPreset::Checkerboard:
                turnOn = ((coord.row + coord.col) % 2) == 0;
                break;
            case PatternPreset::HorizontalStripes:
                turnOn = (coord.row % 2) == 0;
                break;
            case PatternPreset::VerticalStripes:
                turnOn = (coord.col % 2) == 0;
                break;
            case PatternPreset::Quadrants:
                turnOn = (coord.row < 8 && coord.col < 8) || (coord.row >= 8 && coord.col >= 8);
                break;
        }
        states_[index] = turnOn ? DiodeState::On : DiodeState::Off;
    }
    return buildFrame();
}

ShiftRegisterFrame PatchController::applyShiftRegisterFrame(const ShiftRegisterFrame& frame) {
    if (frame.bytes.size() != registerCount_) {
        throw std::invalid_argument("Frame size does not match register count.");
    }

    if (mappingMode_ == MappingMode::Direct) {
        const std::size_t capacity = registerCount_ * 8;
        const std::size_t affected = std::min(capacity, states_.size());
        for (std::size_t i = 0; i < affected; ++i) {
            states_[i] = GetBit(frame.bytes, i) ? DiodeState::On : DiodeState::Off;
        }
        for (std::size_t i = affected; i < states_.size(); ++i) {
            states_[i] = DiodeState::Off;
        }
        return buildFrame();
    }

    const std::size_t capacity = registerCount_ * 8;
    if (capacity < kScanRequiredBits) {
        throw std::runtime_error("Matrix-scan mapping needs at least 280 outputs.");
    }

    std::uint8_t decodedMatrix = activeMatrix_;
    for (std::size_t matrix = 0; matrix < kMatrixCount; ++matrix) {
        if (GetBit(frame.bytes, kScanMatrixSelectStart + matrix)) {
            decodedMatrix = static_cast<std::uint8_t>(matrix);
            break;
        }
    }
    activeMatrix_ = decodedMatrix;

    const std::size_t base = static_cast<std::size_t>(decodedMatrix) * kPatchesPerMatrix;
    for (std::size_t row = 0; row < kMatrixRows; ++row) {
        if (!GetBit(frame.bytes, kScanRowMaskStart + row)) {
            continue;
        }
        for (std::size_t col = 0; col < kMatrixCols; ++col) {
            const std::size_t localBit = row * kMatrixCols + col;
            const bool on = GetBit(frame.bytes, kScanPatchWindowStart + localBit);
            states_[base + localBit] = on ? DiodeState::On : DiodeState::Off;
        }
    }
    return buildFrame();
}

ShiftRegisterFrame PatchController::buildFrame() const {
    if (mappingMode_ == MappingMode::Direct) {
        return buildDirectFrame();
    }
    return buildMatrixScanFrame();
}

ShiftRegisterFrame PatchController::buildDirectFrame() const {
    ShiftRegisterFrame frame{std::vector<std::uint8_t>(registerCount_, 0)};
    const std::size_t capacity = registerCount_ * 8;

    for (std::size_t index = 0; index < states_.size(); ++index) {
        if (states_[index] != DiodeState::On) {
            continue;
        }
        if (index >= capacity) {
            throw std::runtime_error("Direct mapping overflow: more patches than direct outputs.");
        }
        SetBit(frame.bytes, index, true);
    }
    return frame;
}

ShiftRegisterFrame PatchController::buildMatrixScanFrame() const {
    const std::size_t capacity = registerCount_ * 8;
    if (capacity < kScanRequiredBits) {
        throw std::runtime_error("Matrix-scan mapping needs at least 280 outputs.");
    }

    ShiftRegisterFrame frame{std::vector<std::uint8_t>(registerCount_, 0)};
    const std::size_t base = static_cast<std::size_t>(activeMatrix_) * kPatchesPerMatrix;

    for (std::size_t row = 0; row < kMatrixRows; ++row) {
        for (std::size_t col = 0; col < kMatrixCols; ++col) {
            const std::size_t localBit = row * kMatrixCols + col;
            const bool on = states_[base + localBit] == DiodeState::On;
            SetBit(frame.bytes, kScanPatchWindowStart + localBit, on);
        }
        SetBit(frame.bytes, kScanRowMaskStart + row, true);
    }

    SetBit(frame.bytes, kScanMatrixSelectStart + activeMatrix_, true);
    return frame;
}

} // namespace rf
