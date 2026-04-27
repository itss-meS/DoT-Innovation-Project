#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace rf {

struct ShiftRegisterFrame {
    std::vector<std::uint8_t> bytes;
};

class ShiftRegisterChain {
public:
    explicit ShiftRegisterChain(std::size_t registerCount = 64);

    [[nodiscard]] std::size_t registerCount() const;
    [[nodiscard]] std::size_t outputCount() const;

    void clearShift();
    void clockInBit(bool bit);
    void latch();
    void loadFrame(const ShiftRegisterFrame& frame);

    [[nodiscard]] const std::vector<bool>& latchedBits() const;
    [[nodiscard]] const std::vector<std::uint8_t>& latchedBytes() const;

private:
    std::vector<std::uint8_t> BytesFromBits(const std::vector<bool>& bits) const;
    std::vector<bool> BitsFromBytes(const std::vector<std::uint8_t>& bytes) const;

    std::size_t registerCount_{};
    std::vector<bool> shiftBits_{};
    std::vector<bool> latchedBits_{};
    std::vector<std::uint8_t> latchedBytes_{};
};

} // namespace rf
