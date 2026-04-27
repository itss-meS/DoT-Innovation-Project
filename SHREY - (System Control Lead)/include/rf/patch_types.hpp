#pragma once

#include <cstddef>
#include <cstdint>
#include <stdexcept>

namespace rf {

constexpr std::size_t kMatrixCount = 8;
constexpr std::size_t kMatrixRows = 16;
constexpr std::size_t kMatrixCols = 16;
constexpr std::size_t kPatchesPerMatrix = kMatrixRows * kMatrixCols;
constexpr std::size_t kTotalPatches = kMatrixCount * kPatchesPerMatrix;
constexpr std::size_t kScanPatchWindowStart = 0;
constexpr std::size_t kScanMatrixSelectStart = 256;
constexpr std::size_t kScanRowMaskStart = 264;
constexpr std::size_t kScanRequiredBits = 280;

enum class DiodeState : std::uint8_t {
    Off = 0,
    On = 1
};

enum class MappingMode : std::uint8_t {
    Direct = 0,
    MatrixScan = 1
};

enum class PatternPreset : std::uint8_t {
    Checkerboard = 0,
    HorizontalStripes = 1,
    VerticalStripes = 2,
    Quadrants = 3
};

struct PatchCoordinate {
    std::uint8_t matrix{};
    std::uint8_t row{};
    std::uint8_t col{};
};

inline bool IsValidCoordinate(const PatchCoordinate coord) {
    return coord.matrix < kMatrixCount && coord.row < kMatrixRows && coord.col < kMatrixCols;
}

inline std::size_t ToGlobalIndex(const PatchCoordinate coord) {
    if (!IsValidCoordinate(coord)) {
        throw std::out_of_range("Patch coordinate is out of range.");
    }
    return static_cast<std::size_t>(coord.matrix) * kPatchesPerMatrix +
           static_cast<std::size_t>(coord.row) * kMatrixCols +
           static_cast<std::size_t>(coord.col);
}

inline PatchCoordinate FromGlobalIndex(const std::size_t index) {
    if (index >= kTotalPatches) {
        throw std::out_of_range("Patch index is out of range.");
    }
    const std::size_t matrix = index / kPatchesPerMatrix;
    const std::size_t inMatrix = index % kPatchesPerMatrix;
    const std::size_t row = inMatrix / kMatrixCols;
    const std::size_t col = inMatrix % kMatrixCols;
    return PatchCoordinate{
            static_cast<std::uint8_t>(matrix),
            static_cast<std::uint8_t>(row),
            static_cast<std::uint8_t>(col)};
}

} // namespace rf
