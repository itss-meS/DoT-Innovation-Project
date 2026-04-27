#include "rf/shift_register_chain.hpp"

#include <algorithm>
#include <stdexcept>

namespace rf {

ShiftRegisterChain::ShiftRegisterChain(const std::size_t registerCount)
    : registerCount_(registerCount),
      shiftBits_(registerCount_ * 8, false),
      latchedBits_(registerCount_ * 8, false),
      latchedBytes_(registerCount_, 0) {
    if (registerCount_ == 0) {
        throw std::invalid_argument("registerCount must be greater than zero.");
    }
}

std::size_t ShiftRegisterChain::registerCount() const {
    return registerCount_;
}

std::size_t ShiftRegisterChain::outputCount() const {
    return registerCount_ * 8;
}

void ShiftRegisterChain::clearShift() {
    std::fill(shiftBits_.begin(), shiftBits_.end(), false);
}

void ShiftRegisterChain::clockInBit(const bool bit) {
    for (std::size_t i = shiftBits_.size(); i > 1; --i) {
        shiftBits_[i - 1] = shiftBits_[i - 2];
    }
    shiftBits_[0] = bit;
}

void ShiftRegisterChain::latch() {
    latchedBits_ = shiftBits_;
    latchedBytes_ = BytesFromBits(latchedBits_);
}

void ShiftRegisterChain::loadFrame(const ShiftRegisterFrame& frame) {
    if (frame.bytes.size() != registerCount_) {
        throw std::invalid_argument("Frame size does not match register chain size.");
    }
    clearShift();
    const auto bits = BitsFromBytes(frame.bytes);
    for (const bool bit : bits) {
        clockInBit(bit);
    }
    latch();
}

const std::vector<bool>& ShiftRegisterChain::latchedBits() const {
    return latchedBits_;
}

const std::vector<std::uint8_t>& ShiftRegisterChain::latchedBytes() const {
    return latchedBytes_;
}

std::vector<std::uint8_t> ShiftRegisterChain::BytesFromBits(const std::vector<bool>& bits) const {
    std::vector<std::uint8_t> bytes(registerCount_, 0);
    for (std::size_t bitIndex = 0; bitIndex < bits.size(); ++bitIndex) {
        if (bits[bitIndex]) {
            const std::size_t byteIndex = bitIndex / 8;
            const std::size_t offset = bitIndex % 8;
            bytes[byteIndex] |= static_cast<std::uint8_t>(1U << offset);
        }
    }
    return bytes;
}

std::vector<bool> ShiftRegisterChain::BitsFromBytes(const std::vector<std::uint8_t>& bytes) const {
    std::vector<bool> bits(outputCount(), false);
    for (std::size_t byteIndex = 0; byteIndex < bytes.size(); ++byteIndex) {
        for (std::size_t bitOffset = 0; bitOffset < 8; ++bitOffset) {
            const bool bit = (bytes[byteIndex] & static_cast<std::uint8_t>(1U << bitOffset)) != 0;
            bits[byteIndex * 8 + bitOffset] = bit;
        }
    }
    return bits;
}

} // namespace rf
