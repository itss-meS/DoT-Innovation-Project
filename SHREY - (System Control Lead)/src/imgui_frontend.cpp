#include "rf/imgui_frontend.hpp"

#include "imgui.h"

#include <algorithm>
#include <array>
#include <cfloat>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <string>

namespace rf {

namespace {

struct GridGeometry {
    float cell = 0.0F;
    float gap = 0.0F;
    float offsetX = 0.0F;
    float offsetY = 0.0F;
};

std::uint32_t CountOnInMatrix(const SimulationEngine& engine, const std::uint8_t matrix) {
    const auto& states = engine.controller().states();
    const std::size_t base = static_cast<std::size_t>(matrix) * kPatchesPerMatrix;
    std::uint32_t count = 0;
    for (std::size_t i = 0; i < kPatchesPerMatrix; ++i) {
        if (states[base + i] == DiodeState::On) {
            ++count;
        }
    }
    return count;
}

float SmoothStep(float t) {
    const float x = std::clamp(t, 0.0F, 1.0F);
    return x * x * (3.0F - 2.0F * x);
}

GridGeometry ComputeGridGeometry(const float width,
                                 const float height,
                                 const std::size_t cols,
                                 const std::size_t rows,
                                 const float minCell,
                                 const float maxCell,
                                 const float gap) {
    const float safeWidth = std::max(1.0F, width);
    const float safeHeight = std::max(1.0F, height);
    const float xGaps = gap * static_cast<float>(cols - 1U);
    const float yGaps = gap * static_cast<float>(rows - 1U);

    const float fitByWidth = (safeWidth - xGaps) / static_cast<float>(cols);
    const float fitByHeight = (safeHeight - yGaps) / static_cast<float>(rows);
    float cell = std::floor(std::min(fitByWidth, fitByHeight));
    cell = std::clamp(cell, minCell, maxCell);

    if (cell > fitByWidth || cell > fitByHeight) {
        cell = std::max(4.0F, std::floor(std::min(fitByWidth, fitByHeight)));
    }

    const float usedWidth = cell * static_cast<float>(cols) + xGaps;
    const float usedHeight = cell * static_cast<float>(rows) + yGaps;
    return GridGeometry{
            cell,
            gap,
            std::max(0.0F, (safeWidth - usedWidth) * 0.5F),
            std::max(0.0F, (safeHeight - usedHeight) * 0.5F)};
}

ImVec4 ReflectionColor(const SimulationEngine& engine, const std::size_t index) {
    const bool isOn = engine.controller().states()[index] == DiodeState::On;
    const float reflectionDeg = engine.reflectionAngleDeg(index);
    const float signedValue = std::clamp(reflectionDeg / 90.0F, -1.0F, 1.0F);
    const float t = (signedValue + 1.0F) * 0.5F;

    // High-contrast diverging map for better visibility during fast fluctuation.
    const ImVec4 stops[] = {
            {0.06F, 0.20F, 0.90F, 1.0F}, // negative extreme: deep blue
            {0.00F, 0.78F, 0.95F, 1.0F}, // negative mid: cyan
            {0.97F, 0.91F, 0.16F, 1.0F}, // near zero: yellow
            {0.98F, 0.52F, 0.12F, 1.0F}, // positive mid: orange
            {0.88F, 0.12F, 0.12F, 1.0F}  // positive extreme: red
    };

    constexpr float segment = 0.25F;
    const int idx = static_cast<int>(std::min(3.0F, std::floor(t / segment)));
    const float localT = SmoothStep((t - segment * static_cast<float>(idx)) / segment);
    const ImVec4 a = stops[idx];
    const ImVec4 b = stops[idx + 1];
    ImVec4 out{
            a.x + (b.x - a.x) * localT,
            a.y + (b.y - a.y) * localT,
            a.z + (b.z - a.z) * localT,
            1.0F};

    if (!isOn) {
        out.x *= 0.45F;
        out.y *= 0.45F;
        out.z *= 0.45F;
    }
    return out;
}

void DrawPatchButton(SimulationEngine& engine,
                     const PatchCoordinate& coord,
                     const ImVec2& size,
                     const std::string& idPrefix) {
    const std::size_t index = ToGlobalIndex(coord);
    const ImVec4 base = ReflectionColor(engine, index);
    ImVec4 hover = base;
    hover.x = std::min(1.0F, hover.x + 0.12F);
    hover.y = std::min(1.0F, hover.y + 0.12F);
    hover.z = std::min(1.0F, hover.z + 0.12F);
    ImVec4 active = base;
    active.x *= 0.8F;
    active.y *= 0.8F;
    active.z *= 0.8F;

    const ImVec4 border = engine.controller().states()[index] == DiodeState::On
                                  ? ImVec4(0.08F, 0.08F, 0.08F, 0.75F)
                                  : ImVec4(0.20F, 0.20F, 0.20F, 0.55F);
    ImGui::PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1.0F);
    ImGui::PushStyleColor(ImGuiCol_Button, base);
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, hover);
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, active);
    ImGui::PushStyleColor(ImGuiCol_Border, border);

    const std::string id = idPrefix + "_" + std::to_string(coord.matrix) + "_" +
                           std::to_string(coord.row) + "_" + std::to_string(coord.col);
    if (ImGui::Button(id.c_str(), size)) {
        engine.togglePatch(coord);
    }
    ImGui::PopStyleColor(4);
    ImGui::PopStyleVar();
}

constexpr ImGuiWindowFlags kFixedWindowFlags =
        ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoCollapse;

void BeginFixedWindow(const char* title, const ImVec2& pos, const ImVec2& size) {
    ImGui::SetNextWindowPos(pos, ImGuiCond_Always);
    ImGui::SetNextWindowSize(size, ImGuiCond_Always);
    ImGui::Begin(title, nullptr, kFixedWindowFlags);
}

void RenderControlPanel(SimulationEngine& engine, UiState& state, const ImVec2& pos, const ImVec2& size) {
    BeginFixedWindow("RF Patch Control", pos, size);
    if (ImGui::BeginChild("control_scroll_region", ImVec2(0.0F, 0.0F), false, ImGuiWindowFlags_AlwaysVerticalScrollbar)) {

        const float spacing = ImGui::GetStyle().ItemSpacing.x;

        bool autoScan = engine.autoScanEnabled();
        if (ImGui::BeginTable("scan_controls", 2, ImGuiTableFlags_SizingStretchSame)) {
            ImGui::TableNextColumn();
            if (ImGui::Checkbox("Auto scan matrices", &autoScan)) {
                engine.setAutoScan(autoScan);
            }
            ImGui::TableNextColumn();
            if (ImGui::Button("Step once", ImVec2(-FLT_MIN, 0.0F))) {
                engine.step();
            }
            ImGui::EndTable();
        }

        int mappingMode = engine.controller().mappingMode() == MappingMode::MatrixScan ? 1 : 0;
        if (ImGui::BeginTable("mapping_controls", 2, ImGuiTableFlags_SizingStretchSame)) {
            ImGui::TableNextColumn();
            if (ImGui::RadioButton("Direct map", mappingMode == 0)) {
                engine.controller().setMappingMode(MappingMode::Direct);
                engine.rebuildFrame();
            }
            ImGui::TableNextColumn();
            if (ImGui::RadioButton("Matrix scan", mappingMode == 1)) {
                engine.controller().setMappingMode(MappingMode::MatrixScan);
                engine.rebuildFrame();
            }
            ImGui::EndTable();
        }

        ImGui::SetNextItemWidth(-FLT_MIN);
        if (ImGui::SliderInt("Selected matrix", &state.selectedMatrix, 0, static_cast<int>(kMatrixCount - 1))) {
            engine.controller().setActiveMatrix(static_cast<std::uint8_t>(state.selectedMatrix));
            engine.rebuildFrame();
        }

        float incident = engine.incidentAngleDeg();
        ImGui::SetNextItemWidth(-FLT_MIN);
        if (ImGui::SliderFloat("Incident angle (deg)", &incident, -80.0F, 80.0F, "%.1f")) {
            engine.setIncidentAngleDeg(incident);
        }
        float voltage = engine.biasVoltage();
        ImGui::SetNextItemWidth(-FLT_MIN);
        if (ImGui::SliderFloat("Diode bias voltage (V)", &voltage, 0.0F, 5.0F, "%.2f")) {
            engine.setBiasVoltage(voltage);
        }
        float thermal = engine.thermalRise();
        ImGui::SetNextItemWidth(-FLT_MIN);
        if (ImGui::SliderFloat("Thermal rise (C)", &thermal, 0.0F, 80.0F, "%.1f")) {
            engine.setThermalRise(thermal);
        }
        float fx = engine.focusX();
        ImGui::SetNextItemWidth(-FLT_MIN);
        if (ImGui::SliderFloat("Focus X (m)", &fx, -3.0F, 3.0F, "%.2f")) {
            engine.setFocusX(fx);
        }
        float fy = engine.focusY();
        ImGui::SetNextItemWidth(-FLT_MIN);
        if (ImGui::SliderFloat("Focus Y (m)", &fy, -3.0F, 3.0F, "%.2f")) {
            engine.setFocusY(fy);
        }
        float fz = engine.focusZ();
        ImGui::SetNextItemWidth(-FLT_MIN);
        if (ImGui::SliderFloat("Focus Z (m)", &fz, 0.1F, 8.0F, "%.2f")) {
            engine.setFocusZ(fz);
        }
        float radius = engine.panelRadius();
        ImGui::SetNextItemWidth(-FLT_MIN);
        if (ImGui::SliderFloat("Octagon radius (m)", &radius, 0.1F, 2.0F, "%.2f")) {
            engine.setPanelRadius(radius);
        }
        float pitch = engine.patchPitch();
        ImGui::SetNextItemWidth(-FLT_MIN);
        if (ImGui::SliderFloat("Patch pitch (m)", &pitch, 0.002F, 0.03F, "%.3f")) {
            engine.setPatchPitch(pitch);
        }

        const float halfWidth = (ImGui::GetContentRegionAvail().x - spacing) * 0.5F;
        if (ImGui::Button("All ON", ImVec2(halfWidth, 0.0F))) {
            engine.setAll(DiodeState::On);
        }
        ImGui::SameLine();
        if (ImGui::Button("All OFF", ImVec2(halfWidth, 0.0F))) {
            engine.setAll(DiodeState::Off);
        }

        if (ImGui::BeginTable("pattern_controls", 2, ImGuiTableFlags_SizingStretchSame)) {
            ImGui::TableNextColumn();
            if (ImGui::Button("Checkerboard", ImVec2(-FLT_MIN, 0.0F))) {
                engine.applyPattern(PatternPreset::Checkerboard);
            }
            ImGui::TableNextColumn();
            if (ImGui::Button("H Stripes", ImVec2(-FLT_MIN, 0.0F))) {
                engine.applyPattern(PatternPreset::HorizontalStripes);
            }
            ImGui::TableNextRow();
            ImGui::TableNextColumn();
            if (ImGui::Button("V Stripes", ImVec2(-FLT_MIN, 0.0F))) {
                engine.applyPattern(PatternPreset::VerticalStripes);
            }
            ImGui::TableNextColumn();
            if (ImGui::Button("Quadrants", ImVec2(-FLT_MIN, 0.0F))) {
                engine.applyPattern(PatternPreset::Quadrants);
            }
            ImGui::EndTable();
        }

        ImGui::Separator();
        if (ImGui::BeginTable("runtime_info", 2, ImGuiTableFlags_SizingStretchSame)) {
            ImGui::TableNextRow();
            ImGui::TableNextColumn();
            ImGui::TextUnformatted("Tick");
            ImGui::TableNextColumn();
            ImGui::Text("%llu", static_cast<unsigned long long>(engine.tickCount()));

            ImGui::TableNextRow();
            ImGui::TableNextColumn();
            ImGui::TextUnformatted("Active matrix");
            ImGui::TableNextColumn();
            ImGui::Text("%u", static_cast<unsigned>(engine.controller().activeMatrix()));

            ImGui::TableNextRow();
            ImGui::TableNextColumn();
            ImGui::TextUnformatted("Shift registers");
            ImGui::TableNextColumn();
            ImGui::Text("%u", static_cast<unsigned>(engine.controller().registerCount()));
            ImGui::EndTable();
        }

        ImGui::TextWrapped("8 independent 16x16 panels are arranged on an octagonal prism.");
        ImGui::TextWrapped("Right-side prism: drag mouse to rotate yaw and pitch in 3D.");
    }
    ImGui::EndChild();
    ImGui::End();
}

void RenderMatrixGrid(SimulationEngine& engine, const UiState& state, const ImVec2& pos, const ImVec2& size) {
    BeginFixedWindow("Matrix Grid (16x16) - Reflection Gradient", pos, size);
    const auto matrix = static_cast<std::uint8_t>(state.selectedMatrix);

    const float footerHeight = ImGui::GetTextLineHeightWithSpacing() * 4.2F;
    const ImVec2 available = ImGui::GetContentRegionAvail();
    const float gridHeight = std::max(120.0F, available.y - footerHeight);
    const GridGeometry geometry = ComputeGridGeometry(
            available.x, gridHeight, kMatrixCols, kMatrixRows, 12.0F, 30.0F, 2.0F);

    ImGui::Dummy(ImVec2(0.0F, geometry.offsetY));
    const float startX = ImGui::GetCursorPosX() + geometry.offsetX;
    ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(geometry.gap, geometry.gap));
    for (std::size_t row = 0; row < kMatrixRows; ++row) {
        ImGui::SetCursorPosX(startX);
        for (std::size_t col = 0; col < kMatrixCols; ++col) {
            const auto coord = PatchCoordinate{
                    matrix,
                    static_cast<std::uint8_t>(row),
                    static_cast<std::uint8_t>(col)};
            DrawPatchButton(engine, coord, ImVec2(geometry.cell, geometry.cell), "##p");

            if (col + 1 < kMatrixCols) {
                ImGui::SameLine();
            }
        }
    }
    ImGui::PopStyleVar();

    const auto sampleCoord = PatchCoordinate{matrix, 0, 0};
    const std::size_t sampleIndex = ToGlobalIndex(sampleCoord);
    ImGui::Separator();
    ImGui::Text("Sample patch [M%d R0 C0]: phase %.1f deg, reflection %.1f deg",
                state.selectedMatrix,
                engine.phaseShiftDeg(sampleIndex),
                engine.reflectionAngleDeg(sampleIndex));
    ImGui::Text("Target phase %.1f deg | phase error %.1f deg",
                engine.targetPhaseDeg(sampleIndex),
                engine.phaseErrorDeg(sampleIndex));

    ImGui::End();
}

void RenderRegisterControl(SimulationEngine& engine, UiState& state, const ImVec2& pos, const ImVec2& size) {
    BeginFixedWindow("64 Shift Register Control", pos, size);
    if (ImGui::BeginChild("register_scroll_region", ImVec2(0.0F, 0.0F), false, ImGuiWindowFlags_AlwaysVerticalScrollbar)) {
    const auto& bytes = engine.registerBytes();

    ImGui::SetNextItemWidth(-FLT_MIN);
    if (ImGui::SliderInt("Register index", &state.selectedRegister, 0, static_cast<int>(bytes.size() - 1))) {
    }

    const auto regIndex = static_cast<std::size_t>(state.selectedRegister);
    unsigned int regValue = bytes[regIndex];
    ImGui::SetNextItemWidth(-FLT_MIN);
    if (ImGui::InputScalar("Register byte (hex)", ImGuiDataType_U32, &regValue, nullptr, nullptr, "%02X",
                           ImGuiInputTextFlags_CharsHexadecimal)) {
        engine.setRegisterByte(regIndex, static_cast<std::uint8_t>(regValue & 0xFFU));
    }

    ImGui::Text("Bit controls for R%u", static_cast<unsigned>(regIndex));
    if (ImGui::BeginTable("bit_controls", 4, ImGuiTableFlags_SizingStretchSame)) {
        for (std::uint8_t bit = 0; bit < 8; ++bit) {
            ImGui::TableNextColumn();
            bool enabled = (engine.registerBytes()[regIndex] & static_cast<std::uint8_t>(1U << bit)) != 0;
            const std::string label = "b" + std::to_string(bit);
            if (ImGui::Checkbox(label.c_str(), &enabled)) {
                engine.setRegisterBit(regIndex, bit, enabled);
            }
        }
        ImGui::EndTable();
    }

    ImGui::Separator();
    ImGui::Text("Matrix-scan important regions");
    ImGui::Text("R0..R31 => 256 patch bits for active matrix");
    ImGui::Text("R32 bit0..7 => active matrix select (one-hot)");
    ImGui::Text("R33..R34 => row enables (16 bits)");
    ImGui::TextWrapped("To program all 2048 patches with 64 registers: write one matrix frame at a time (matrix select + 256 bits), repeat for 8 matrices.");

    if (ImGui::Button("Rebuild current frame from logical state", ImVec2(ImGui::GetContentRegionAvail().x, 0.0F))) {
        engine.rebuildFrame();
    }
    }
    ImGui::EndChild();
    ImGui::End();
}

struct Vec3 {
    float x = 0.0F;
    float y = 0.0F;
    float z = 0.0F;

    Vec3 operator+(const Vec3& v) const { return {x + v.x, y + v.y, z + v.z}; }
    Vec3 operator-(const Vec3& v) const { return {x - v.x, y - v.y, z - v.z}; }
    Vec3 operator*(const float s) const { return {x * s, y * s, z * s}; }
    Vec3& operator+=(const Vec3& v) {
        x += v.x;
        y += v.y;
        z += v.z;
        return *this;
    }
};

float Dot(const Vec3& a, const Vec3& b) {
    return (a.x * b.x) + (a.y * b.y) + (a.z * b.z);
}

Vec3 Cross(const Vec3& a, const Vec3& b) {
    return {
            (a.y * b.z) - (a.z * b.y),
            (a.z * b.x) - (a.x * b.z),
            (a.x * b.y) - (a.y * b.x)};
}

float Length(const Vec3& v) {
    return std::sqrt(Dot(v, v));
}

Vec3 Normalize(const Vec3& v) {
    const float len = Length(v);
    if (len <= 1.0e-6F) {
        return {0.0F, 0.0F, 1.0F};
    }
    return v * (1.0F / len);
}

Vec3 Lerp(const Vec3& a, const Vec3& b, const float t) {
    return a + ((b - a) * t);
}

Vec3 RotateX(const Vec3& v, const float angle) {
    const float c = std::cos(angle);
    const float s = std::sin(angle);
    return {v.x, (v.y * c) - (v.z * s), (v.y * s) + (v.z * c)};
}

Vec3 RotateY(const Vec3& v, const float angle) {
    const float c = std::cos(angle);
    const float s = std::sin(angle);
    return {(v.x * c) + (v.z * s), v.y, (-v.x * s) + (v.z * c)};
}

Vec3 TransformModel(const Vec3& v, const float yawRad, const float pitchRad) {
    return RotateY(RotateX(v, pitchRad), yawRad);
}

ImVec2 ProjectPoint(const Vec3& v,
                    const ImVec2& screenCenter,
                    const float scale,
                    const float cameraDistance,
                    float& outDepth) {
    const float depth = v.z + cameraDistance;
    outDepth = depth;
    const float safeDepth = std::max(0.15F, depth);
    const float perspective = cameraDistance / safeDepth;
    return ImVec2{screenCenter.x + (v.x * perspective * scale), screenCenter.y - (v.y * perspective * scale)};
}

ImVec4 MultiplyColor(const ImVec4& color, const float scale) {
    return ImVec4{
            std::clamp(color.x * scale, 0.0F, 1.0F),
            std::clamp(color.y * scale, 0.0F, 1.0F),
            std::clamp(color.z * scale, 0.0F, 1.0F),
            std::clamp(color.w, 0.0F, 1.0F)};
}

ImU32 ToImColor(const ImVec4& color) {
    return IM_COL32(static_cast<int>(std::clamp(color.x, 0.0F, 1.0F) * 255.0F),
                    static_cast<int>(std::clamp(color.y, 0.0F, 1.0F) * 255.0F),
                    static_cast<int>(std::clamp(color.z, 0.0F, 1.0F) * 255.0F),
                    static_cast<int>(std::clamp(color.w, 0.0F, 1.0F) * 255.0F));
}

ImVec2 LerpPoint(const ImVec2& a, const ImVec2& b, const float t) {
    return ImVec2{a.x + ((b.x - a.x) * t), a.y + ((b.y - a.y) * t)};
}

template <std::size_t N>
std::array<ImVec2, N> InsetPolygon(const std::array<ImVec2, N>& points, const float scale) {
    std::array<ImVec2, N> inset{};
    ImVec2 center{0.0F, 0.0F};
    for (const ImVec2& point : points) {
        center.x += point.x;
        center.y += point.y;
    }
    center.x /= static_cast<float>(N);
    center.y /= static_cast<float>(N);

    for (std::size_t i = 0; i < N; ++i) {
        inset[i] = ImVec2{
                center.x + ((points[i].x - center.x) * scale),
                center.y + ((points[i].y - center.y) * scale)};
    }
    return inset;
}

bool PointInConvexPolygon(const ImVec2* points, const std::size_t count, const ImVec2& p) {
    bool hasPos = false;
    bool hasNeg = false;
    for (std::size_t i = 0; i < count; ++i) {
        const ImVec2& a = points[i];
        const ImVec2& b = points[(i + 1U) % count];
        const float cross = ((b.x - a.x) * (p.y - a.y)) - ((b.y - a.y) * (p.x - a.x));
        hasPos |= cross > 0.0F;
        hasNeg |= cross < 0.0F;
        if (hasPos && hasNeg) {
            return false;
        }
    }
    return true;
}

struct PrismFace {
    enum class Kind {
        Side,
        Top,
        Bottom
    } kind = Kind::Side;

    std::uint8_t matrix = 0;
    std::size_t vertexCount = 0;
    std::array<Vec3, 8> world{};
    std::array<ImVec2, 8> screen{};
    std::array<float, 8> depth{};
    Vec3 normal{};
    Vec3 center{};
    float shade = 1.0F;
    bool visible = false;
};

std::array<Vec3, 16> BuildOctagonalPrismVertices(const float radius, const float height) {
    std::array<Vec3, 16> vertices{};
    constexpr float kPi = 3.14159265359F;
    constexpr float kAngleOffset = kPi / 8.0F;
    const float halfHeight = height * 0.5F;

    for (std::size_t i = 0; i < kMatrixCount; ++i) {
        const float angle = kAngleOffset + ((2.0F * kPi * static_cast<float>(i)) / static_cast<float>(kMatrixCount));
        const float x = std::cos(angle) * radius;
        const float z = std::sin(angle) * radius;
        vertices[i] = Vec3{x, halfHeight, z};
        vertices[kMatrixCount + i] = Vec3{x, -halfHeight, z};
    }

    return vertices;
}

Vec3 ComputeFaceCenter(const std::array<Vec3, 8>& world, const std::size_t vertexCount) {
    Vec3 center{};
    for (std::size_t i = 0; i < vertexCount; ++i) {
        center += world[i];
    }
    return center * (1.0F / static_cast<float>(vertexCount));
}

Vec3 ComputeFaceNormal(const std::array<Vec3, 8>& world, const std::size_t vertexCount) {
    if (vertexCount < 3U) {
        return {0.0F, 0.0F, 1.0F};
    }
    return Normalize(Cross(world[1] - world[0], world[2] - world[0]));
}

float ComputeFaceShade(const PrismFace::Kind kind, const Vec3& normal) {
    const Vec3 lightDir = Normalize(Vec3{-0.30F, 0.80F, -1.0F});
    const float diffuse = std::max(0.0F, Dot(normal, lightDir));
    float shade = 0.22F + (0.78F * diffuse);

    switch (kind) {
    case PrismFace::Kind::Top:
        shade = std::max(shade, 0.90F);
        break;
    case PrismFace::Kind::Bottom:
        shade *= 0.40F;
        break;
    case PrismFace::Kind::Side:
        break;
    }

    return std::clamp(shade, 0.14F, 1.0F);
}

std::array<PrismFace, 10> BuildPrismFaces(const std::array<Vec3, 16>& worldVerts, const float cameraDistance) {
    std::array<PrismFace, 10> faces{};

    for (std::size_t i = 0; i < kMatrixCount; ++i) {
        const auto next = (i + 1U) % kMatrixCount;
        PrismFace face{};
        face.kind = PrismFace::Kind::Side;
        face.matrix = static_cast<std::uint8_t>(i);
        face.vertexCount = 4;
        face.world[0] = worldVerts[i];
        face.world[1] = worldVerts[next];
        face.world[2] = worldVerts[kMatrixCount + next];
        face.world[3] = worldVerts[kMatrixCount + i];
        face.center = ComputeFaceCenter(face.world, face.vertexCount);
        face.normal = ComputeFaceNormal(face.world, face.vertexCount);
        face.visible = Dot(face.normal, face.center + Vec3{0.0F, 0.0F, cameraDistance}) < 0.0F;
        face.shade = ComputeFaceShade(face.kind, face.normal);

        for (std::size_t v = 0; v < face.vertexCount; ++v) {
            face.depth[v] = face.world[v].z + cameraDistance;
        }

        faces[i] = face;
    }

    {
        PrismFace face{};
        face.kind = PrismFace::Kind::Top;
        face.vertexCount = kMatrixCount;
        for (std::size_t i = 0; i < kMatrixCount; ++i) {
            face.world[i] = worldVerts[i];
            const auto depth = face.world[i].z + cameraDistance;
            face.depth[i] = depth;
        }
        face.center = ComputeFaceCenter(face.world, face.vertexCount);
        face.normal = ComputeFaceNormal(face.world, face.vertexCount);
        face.visible = Dot(face.normal, face.center + Vec3{0.0F, 0.0F, cameraDistance}) < 0.0F;
        face.shade = ComputeFaceShade(face.kind, face.normal);
        faces[8] = face;
    }

    {
        PrismFace face{};
        face.kind = PrismFace::Kind::Bottom;
        face.vertexCount = kMatrixCount;
        for (std::size_t i = 0; i < kMatrixCount; ++i) {
            face.world[i] = worldVerts[kMatrixCount + (kMatrixCount - 1U - i)];
            const auto depth = face.world[i].z + cameraDistance;
            face.depth[i] = depth;
        }
        face.center = ComputeFaceCenter(face.world, face.vertexCount);
        face.normal = ComputeFaceNormal(face.world, face.vertexCount);
        face.visible = Dot(face.normal, face.center + Vec3{0.0F, 0.0F, cameraDistance}) < 0.0F;
        face.shade = ComputeFaceShade(face.kind, face.normal);
        faces[9] = face;
    }

    return faces;
}

ImVec2 FacePoint(const std::array<Vec3, 8>& world,
                 const float u,
                 const float v,
                 const float cameraDistance,
                 const ImVec2& screenCenter,
                 const float scale,
                 float& outDepth) {
    const Vec3 top = Lerp(world[0], world[1], u);
    const Vec3 bottom = Lerp(world[3], world[2], u);
    const Vec3 point = Lerp(top, bottom, v);
    return ProjectPoint(point, screenCenter, scale, cameraDistance, outDepth);
}

void DrawProjectedPolygon(ImDrawList* drawList, const std::array<ImVec2, 8>& points, const std::size_t count, const ImU32 fillColor, const ImU32 borderColor, const float borderThickness) {
    if (count < 3U) {
        return;
    }

    drawList->AddConvexPolyFilled(points.data(), static_cast<int>(count), fillColor);
    drawList->AddPolyline(points.data(), static_cast<int>(count), borderColor, true, borderThickness);
}

void RenderFullReflectionMap(SimulationEngine& engine, UiState& state, const ImVec2& pos, const ImVec2& size) {
    BeginFixedWindow("3D Octagonal Prism Array", pos, size);
    ImGui::Text("Drag on the prism to rotate yaw and pitch. Click a side face to select it.");

    if (ImGui::BeginChild("octagon_3d_canvas", ImVec2(0.0F, 0.0F), true, ImGuiWindowFlags_NoScrollbar)) {
        const ImVec2 canvasSize = ImGui::GetContentRegionAvail();
        ImGui::InvisibleButton("octagon_canvas", canvasSize, ImGuiButtonFlags_MouseButtonLeft);

        const ImVec2 canvasMin = ImGui::GetItemRectMin();
        const ImVec2 canvasMax = ImGui::GetItemRectMax();
        const ImVec2 canvasCenter{
                canvasMin.x + (canvasSize.x * 0.5F),
                canvasMin.y + (canvasSize.y * 0.52F)};

        ImDrawList* drawList = ImGui::GetWindowDrawList();
        drawList->AddRectFilled(canvasMin, canvasMax, IM_COL32(24, 24, 28, 255));
        drawList->AddCircleFilled(ImVec2{canvasCenter.x, canvasCenter.y + (canvasSize.y * 0.18F)}, canvasSize.x * 0.18F, IM_COL32(0, 0, 0, 36), 48);

        const ImGuiIO& io = ImGui::GetIO();
        const bool canvasHovered = ImGui::IsItemHovered();
        const bool canvasActive = ImGui::IsItemActive();

        if (canvasHovered && std::abs(io.MouseWheel) > 0.0F) {
            constexpr float kZoomStep = 1.08F;
            const float wheel = io.MouseWheel;
            const float factor = wheel > 0.0F ? std::pow(kZoomStep, wheel) : std::pow(1.0F / kZoomStep, -wheel);
            state.octagonZoom = std::clamp(state.octagonZoom * factor, 0.55F, 2.50F);
        }

        if (canvasActive && ImGui::IsMouseDragging(ImGuiMouseButton_Left)) {
            state.octagonRotationDeg += io.MouseDelta.x * 0.45F;
            state.pitchDeg = std::clamp(state.pitchDeg - (io.MouseDelta.y * 0.35F), -65.0F, 65.0F);
        }

        constexpr float kPi = 3.14159265359F;
        const float yawRad = state.octagonRotationDeg * (kPi / 180.0F);
        const float pitchRad = state.pitchDeg * (kPi / 180.0F);

        const float prismRadius = 1.14F;
        const float prismHeight = 1.28F;
        const float cameraDistance = 4.7F;
        const float drawScale = (std::min(canvasSize.x, canvasSize.y) * 0.39F) * state.octagonZoom;
        const std::array<Vec3, 16> modelVerts = BuildOctagonalPrismVertices(prismRadius, prismHeight);

        std::array<Vec3, 16> worldVerts{};
        for (std::size_t i = 0; i < worldVerts.size(); ++i) {
            worldVerts[i] = TransformModel(modelVerts[i], yawRad, pitchRad);
        }

        std::array<PrismFace, 10> faces = BuildPrismFaces(worldVerts, cameraDistance);
        std::array<std::size_t, 10> drawOrder{};
        std::size_t visibleFaceCount = 0;
        for (std::size_t i = 0; i < faces.size(); ++i) {
            if (faces[i].visible) {
                drawOrder[visibleFaceCount++] = i;
            }
        }

        std::sort(drawOrder.begin(), drawOrder.begin() + static_cast<std::ptrdiff_t>(visibleFaceCount), [&](const std::size_t a, const std::size_t b) {
            return faces[a].center.z > faces[b].center.z;
        });

        std::uint8_t clickedMatrix = 255U;
        const ImVec2 mousePos = io.MousePos;
        const bool clickedCanvas = canvasHovered && ImGui::IsMouseClicked(ImGuiMouseButton_Left);
        std::array<std::array<ImVec2, 8>, 10> projectedFaces{};
        std::array<bool, 10> projectedValid{};

        for (std::size_t orderIndex = 0; orderIndex < visibleFaceCount; ++orderIndex) {
            const std::size_t faceIndex = drawOrder[orderIndex];
            const PrismFace& face = faces[faceIndex];
            std::array<ImVec2, 8> projected{};
            std::array<float, 8> projectedDepth{};
            for (std::size_t v = 0; v < face.vertexCount; ++v) {
                projected[v] = ProjectPoint(face.world[v], canvasCenter, drawScale, cameraDistance, projectedDepth[v]);
            }
            projectedFaces[faceIndex] = projected;
            projectedValid[faceIndex] = true;

            if (face.kind == PrismFace::Kind::Side) {
                const bool selected = static_cast<std::uint8_t>(state.selectedMatrix) == face.matrix;
                const float selectedBoost = selected ? 1.10F : 1.0F;
                const float faceBoost = face.shade * selectedBoost;

                std::array<ImVec2, 8> patchPoints{};
                constexpr float kInset = 0.045F;

                const std::array<ImVec2, 4> faceCorners{projected[0], projected[1], projected[2], projected[3]};
                if (clickedMatrix == 255U && clickedCanvas && PointInConvexPolygon(faceCorners.data(), faceCorners.size(), mousePos)) {
                    clickedMatrix = face.matrix;
                    break;
                }

                const ImVec4 baseFaceTint = MultiplyColor(ImVec4{0.93F, 0.93F, 0.95F, 1.0F}, std::clamp(faceBoost * 0.95F, 0.25F, 1.0F));
                DrawProjectedPolygon(
                        drawList,
                        projected,
                        face.vertexCount,
                        ToImColor(baseFaceTint),
                        selected ? IM_COL32(255, 214, 112, 235) : IM_COL32(42, 42, 46, 180),
                        selected ? 2.0F : 1.0F);

                const ImVec4 topEdgeTint = MultiplyColor(ImVec4{1.0F, 1.0F, 1.0F, 0.28F}, std::clamp(faceBoost, 0.25F, 1.0F));
                const ImVec4 bottomEdgeTint = MultiplyColor(ImVec4{0.0F, 0.0F, 0.0F, 0.20F}, std::clamp(1.05F - faceBoost, 0.10F, 1.0F));
                const std::array<ImVec2, 4> topStrip{
                        projected[0],
                        projected[1],
                        LerpPoint(projected[1], projected[2], 0.12F),
                        LerpPoint(projected[0], projected[3], 0.12F)};
                const std::array<ImVec2, 4> bottomStrip{
                        LerpPoint(projected[0], projected[3], 0.88F),
                        LerpPoint(projected[1], projected[2], 0.88F),
                        projected[2],
                        projected[3]};
                drawList->AddConvexPolyFilled(topStrip.data(), 4, ToImColor(topEdgeTint));
                drawList->AddConvexPolyFilled(bottomStrip.data(), 4, ToImColor(bottomEdgeTint));

                // Fit a centered square UV window on each face so patch cells stay square.
                const float faceWidth = Length(face.world[1] - face.world[0]);
                const float faceHeight = Length(face.world[3] - face.world[0]);
                const float safeWidth = std::max(faceWidth, 1.0e-6F);
                const float safeHeight = std::max(faceHeight, 1.0e-6F);
                const float usedEdge = std::min(safeWidth, safeHeight);
                const float uScale = usedEdge / safeWidth;
                const float vScale = usedEdge / safeHeight;
                const float uOffset = (1.0F - uScale) * 0.5F;
                const float vOffset = (1.0F - vScale) * 0.5F;

                for (std::size_t row = 0; row < kMatrixRows; ++row) {
                    for (std::size_t col = 0; col < kMatrixCols; ++col) {
                        const float rawU0 = (static_cast<float>(col) + kInset) / static_cast<float>(kMatrixCols);
                        const float rawU1 = (static_cast<float>(col + 1U) - kInset) / static_cast<float>(kMatrixCols);
                        const float rawV0 = (static_cast<float>(row) + kInset) / static_cast<float>(kMatrixRows);
                        const float rawV1 = (static_cast<float>(row + 1U) - kInset) / static_cast<float>(kMatrixRows);

                        const float u0 = uOffset + (rawU0 * uScale);
                        const float u1 = uOffset + (rawU1 * uScale);
                        const float v0 = vOffset + (rawV0 * vScale);
                        const float v1 = vOffset + (rawV1 * vScale);

                        float d0 = 0.0F;
                        float d1 = 0.0F;
                        float d2 = 0.0F;
                        float d3 = 0.0F;
                        patchPoints[0] = FacePoint(face.world, u0, v0, cameraDistance, canvasCenter, drawScale, d0);
                        patchPoints[1] = FacePoint(face.world, u1, v0, cameraDistance, canvasCenter, drawScale, d1);
                        patchPoints[2] = FacePoint(face.world, u1, v1, cameraDistance, canvasCenter, drawScale, d2);
                        patchPoints[3] = FacePoint(face.world, u0, v1, cameraDistance, canvasCenter, drawScale, d3);

                        const auto coord = PatchCoordinate{face.matrix,
                                                           static_cast<std::uint8_t>(row),
                                                           static_cast<std::uint8_t>(col)};
                        const std::size_t globalIdx = ToGlobalIndex(coord);
                        ImVec4 patchColor = MultiplyColor(ReflectionColor(engine, globalIdx), std::clamp(faceBoost * 0.95F, 0.20F, 1.0F));
                        patchColor.x = std::clamp(patchColor.x * 0.95F, 0.0F, 1.0F);
                        patchColor.y = std::clamp(patchColor.y * 0.95F, 0.0F, 1.0F);
                        patchColor.z = std::clamp(patchColor.z * 0.95F, 0.0F, 1.0F);
                        patchColor.w = 1.0F;

                        drawList->AddConvexPolyFilled(patchPoints.data(), 4, ToImColor(patchColor));
                        drawList->AddPolyline(patchPoints.data(), 4, IM_COL32(0, 0, 0, 48), true, 1.0F);
                    }
                }

                const ImVec2 faceCenter2D{
                        (projected[0].x + projected[1].x + projected[2].x + projected[3].x) * 0.25F,
                        (projected[0].y + projected[1].y + projected[2].y + projected[3].y) * 0.25F};
                drawList->AddText(ImVec2{faceCenter2D.x - 5.0F, faceCenter2D.y - 7.0F}, IM_COL32(255, 255, 255, 180), std::to_string(face.matrix).c_str());
            } else {
                for (std::size_t v = 0; v < face.vertexCount; ++v) {
                    projected[v] = ProjectPoint(face.world[v], canvasCenter, drawScale, cameraDistance, projectedDepth[v]);
                }
                projectedFaces[faceIndex] = projected;
                projectedValid[faceIndex] = true;
                const ImU32 fillColor = face.kind == PrismFace::Kind::Top
                                              ? ToImColor(MultiplyColor(ImVec4{0.97F, 0.97F, 0.98F, 1.0F}, face.shade))
                                              : ToImColor(MultiplyColor(ImVec4{0.47F, 0.47F, 0.50F, 1.0F}, face.shade));
                const ImU32 borderColor = face.kind == PrismFace::Kind::Top ? IM_COL32(220, 220, 225, 255) : IM_COL32(115, 115, 122, 210);
                DrawProjectedPolygon(drawList, projected, face.vertexCount, fillColor, borderColor, 1.5F);

                if (face.kind == PrismFace::Kind::Top || face.kind == PrismFace::Kind::Bottom) {
                    const auto inner = InsetPolygon(projected, face.kind == PrismFace::Kind::Top ? 0.84F : 0.88F);
                    const ImU32 innerFill = face.kind == PrismFace::Kind::Top
                                                  ? ToImColor(MultiplyColor(ImVec4{1.0F, 1.0F, 1.0F, 0.55F}, face.shade))
                                                  : ToImColor(MultiplyColor(ImVec4{0.22F, 0.22F, 0.24F, 0.82F}, 1.0F));
                    const ImU32 innerBorder = face.kind == PrismFace::Kind::Top ? IM_COL32(255, 255, 255, 78) : IM_COL32(0, 0, 0, 110);
                    DrawProjectedPolygon(drawList, inner, face.vertexCount, innerFill, innerBorder, 1.0F);
                }
            }
        }

        if (clickedCanvas) {
            for (std::size_t orderIndex = visibleFaceCount; orderIndex-- > 0;) {
                const std::size_t faceIndex = drawOrder[orderIndex];
                const PrismFace& face = faces[faceIndex];
                if (face.kind != PrismFace::Kind::Side || !projectedValid[faceIndex]) {
                    continue;
                }

                const std::array<ImVec2, 4> faceCorners{
                        projectedFaces[faceIndex][0],
                        projectedFaces[faceIndex][1],
                        projectedFaces[faceIndex][2],
                        projectedFaces[faceIndex][3]};
                if (PointInConvexPolygon(faceCorners.data(), faceCorners.size(), mousePos)) {
                    clickedMatrix = face.matrix;
                    break;
                }
            }
        }

        if (clickedMatrix != 255U) {
            state.selectedMatrix = static_cast<int>(clickedMatrix);
        }

        if (canvasHovered || canvasActive) {
            drawList->AddText(
                    ImVec2{canvasMin.x + 10.0F, canvasMin.y + 10.0F},
                    IM_COL32(255, 255, 255, 210),
                    "Yaw drag: left/right | Pitch drag: up/down");
            const std::string status = "Face: " + std::to_string(state.selectedMatrix) +
                                       " | Yaw: " + std::to_string(static_cast<int>(std::round(state.octagonRotationDeg))) +
                                       " deg | Pitch: " + std::to_string(static_cast<int>(std::round(state.pitchDeg))) +
                                       " deg | Zoom: " + std::to_string(static_cast<int>(std::round(state.octagonZoom * 100.0F))) + "%";
            drawList->AddText(ImVec2{canvasMin.x + 10.0F, canvasMin.y + 28.0F}, IM_COL32(220, 220, 220, 210), status.c_str());
        }
    }
    ImGui::EndChild();
    ImGui::End();
}

void RenderOverview(SimulationEngine& engine, const ImVec2& pos, const ImVec2& size) {
    BeginFixedWindow("8-Matrix Octagonal Focus Overview", pos, size);
    for (std::uint8_t matrix = 0; matrix < kMatrixCount; ++matrix) {
        const auto count = CountOnInMatrix(engine, matrix);
        const auto probeIndex = ToGlobalIndex(PatchCoordinate{matrix, 8, 8});
        ImGui::Text("Panel %u: %u / 256 ON | probe reflect %.1f deg | probe err %.1f deg",
                    static_cast<unsigned>(matrix),
                    static_cast<unsigned>(count),
                    engine.reflectionAngleDeg(probeIndex),
                    engine.phaseErrorDeg(probeIndex));
    }
    ImGui::Text("Total patches: %u", static_cast<unsigned>(kTotalPatches));
    ImGui::Text("Shift registers: %u (outputs %u)",
                static_cast<unsigned>(engine.controller().registerCount()),
                static_cast<unsigned>(engine.controller().registerCount() * 8));
    ImGui::End();
}

} // namespace

void RenderFrontend(SimulationEngine& engine, UiState& state) {
    const ImGuiViewport* viewport = ImGui::GetMainViewport();
    const ImVec2 origin = viewport->WorkPos;
    const ImVec2 work = viewport->WorkSize;
    constexpr float pad = 10.0F;

    const float usableWidth = std::max(0.0F, work.x - (pad * 3.0F));
    constexpr float minLeft = 320.0F;
    constexpr float minRight = 500.0F;
    float leftW = minLeft;
    float rightW = minRight;
    const float minimumTotal = minLeft + minRight;
    if (usableWidth <= minimumTotal && minimumTotal > 0.0F) {
        const float scale = usableWidth / minimumTotal;
        leftW = minLeft * scale;
        rightW = minRight * scale;
    } else {
        const float extra = usableWidth - minimumTotal;
        constexpr float leftRatio = 3.0F;
        constexpr float rightRatio = 7.0F;
        constexpr float ratioTotal = leftRatio + rightRatio;
        leftW = minLeft + extra * (leftRatio / ratioTotal);
        rightW = minRight + extra * (rightRatio / ratioTotal);
    }
    rightW = std::max(0.0F, usableWidth - leftW);

    const float usableHeight = std::max(0.0F, work.y - (pad * 3.0F));
    constexpr float minBottom = 210.0F;
    float topH = usableHeight * 0.60F;
    if (usableHeight <= 260.0F) {
        topH = usableHeight * 0.5F;
    } else {
        const float topMin = std::min(260.0F, usableHeight * 0.55F);
        const float topMax = std::max(160.0F, usableHeight - minBottom);
        topH = std::clamp(topH, topMin, topMax);
    }
    const float bottomH = std::max(0.0F, usableHeight - topH);

    const ImVec2 leftTopPos{origin.x + pad, origin.y + pad};
    const ImVec2 leftTopSize{leftW, topH};
    const ImVec2 leftBottomPos{origin.x + pad, origin.y + pad + topH + pad};
    const ImVec2 leftBottomSize{leftW, bottomH};

    const ImVec2 rightPos{origin.x + (pad * 2.0F) + leftW, origin.y + pad};
    const ImVec2 rightSize{rightW, work.y - (pad * 2.0F)};

    RenderControlPanel(engine, state, leftTopPos, leftTopSize);
    RenderRegisterControl(engine, state, leftBottomPos, leftBottomSize);
    RenderFullReflectionMap(engine, state, rightPos, rightSize);
}

} // namespace rf
