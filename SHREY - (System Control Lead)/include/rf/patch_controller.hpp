#pragma once

#include "rf/patch_types.hpp"
#include "rf/shift_register_chain.hpp"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace rf {

class PatchController {
public:
    explicit PatchController(std::size_t registerCount = 64);

    void setMappingMode(MappingMode mode);
    [[nodiscard]] MappingMode mappingMode() const;

    void setActiveMatrix(std::uint8_t matrix);
    [[nodiscard]] std::uint8_t activeMatrix() const;

    [[nodiscard]] const std::vector<DiodeState>& states() const;
    [[nodiscard]] std::size_t registerCount() const;

    ShiftRegisterFrame setPatch(const PatchCoordinate& coord, DiodeState state);
    ShiftRegisterFrame setPatch(std::size_t globalIndex, DiodeState state);
    ShiftRegisterFrame togglePatch(const PatchCoordinate& coord);
    ShiftRegisterFrame setMatrix(std::uint8_t matrix, DiodeState state);
    ShiftRegisterFrame setRow(std::uint8_t matrix, std::uint8_t row, DiodeState state);
    ShiftRegisterFrame setColumn(std::uint8_t matrix, std::uint8_t col, DiodeState state);
    ShiftRegisterFrame setAll(DiodeState state);
    ShiftRegisterFrame applyPattern(PatternPreset preset);
    ShiftRegisterFrame applyShiftRegisterFrame(const ShiftRegisterFrame& frame);

    [[nodiscard]] ShiftRegisterFrame buildFrame() const;

private:
    ShiftRegisterFrame buildDirectFrame() const;
    ShiftRegisterFrame buildMatrixScanFrame() const;

    std::size_t registerCount_{};
    MappingMode mappingMode_{MappingMode::MatrixScan};
    std::uint8_t activeMatrix_{0};
    std::vector<DiodeState> states_{};
};

} // namespace rf
