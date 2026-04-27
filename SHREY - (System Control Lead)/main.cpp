#include "rf/imgui_frontend.hpp"
#include "rf/simulation_engine.hpp"

#include "imgui.h"
#include "backends/imgui_impl_glfw.h"
#include "backends/imgui_impl_opengl2.h"

#include <GLFW/glfw3.h>
#include <GL/gl.h>

#include <exception>
#include <iostream>

namespace {

void ConfigureLightTheme() {
    ImGui::StyleColorsLight();
    ImGuiStyle& style = ImGui::GetStyle();
    style.WindowRounding = 8.0F;
    style.ChildRounding = 6.0F;
    style.FrameRounding = 6.0F;
    style.ScrollbarRounding = 8.0F;
    style.GrabRounding = 6.0F;
    style.WindowBorderSize = 1.0F;
    style.FrameBorderSize = 0.0F;
    style.ItemSpacing = ImVec2(10.0F, 8.0F);
    style.WindowPadding = ImVec2(12.0F, 12.0F);

    ImVec4* colors = style.Colors;
    colors[ImGuiCol_WindowBg] = ImVec4(0.97F, 0.97F, 0.98F, 1.0F);
    colors[ImGuiCol_ChildBg] = ImVec4(0.97F, 0.97F, 0.98F, 1.0F);
    colors[ImGuiCol_FrameBg] = ImVec4(0.92F, 0.93F, 0.95F, 1.0F);
    colors[ImGuiCol_FrameBgHovered] = ImVec4(0.85F, 0.89F, 0.95F, 1.0F);
    colors[ImGuiCol_FrameBgActive] = ImVec4(0.80F, 0.86F, 0.95F, 1.0F);
    colors[ImGuiCol_Button] = ImVec4(0.80F, 0.86F, 0.95F, 1.0F);
    colors[ImGuiCol_ButtonHovered] = ImVec4(0.74F, 0.82F, 0.94F, 1.0F);
    colors[ImGuiCol_ButtonActive] = ImVec4(0.68F, 0.78F, 0.93F, 1.0F);
    colors[ImGuiCol_Header] = ImVec4(0.80F, 0.86F, 0.95F, 1.0F);
    colors[ImGuiCol_HeaderHovered] = ImVec4(0.74F, 0.82F, 0.94F, 1.0F);
    colors[ImGuiCol_HeaderActive] = ImVec4(0.68F, 0.78F, 0.93F, 1.0F);
}

} // namespace

int main() {
    if (!glfwInit()) {
        std::cerr << "Failed to initialize GLFW.\n";
        return 1;
    }

    constexpr int windowWidth = 1400;
    constexpr int windowHeight = 900;
    GLFWwindow* window = glfwCreateWindow(windowWidth, windowHeight, "RF Patch Controller Simulator", nullptr, nullptr);
    if (window == nullptr) {
        std::cerr << "Failed to create GLFW window.\n";
        glfwTerminate();
        return 1;
    }

    glfwMakeContextCurrent(window);
    glfwSwapInterval(1);

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    (void)io;
    ConfigureLightTheme();

    ImGui_ImplGlfw_InitForOpenGL(window, true);
    ImGui_ImplOpenGL2_Init();

    rf::SimulationEngine engine(64);
    rf::UiState uiState{};
    engine.rebuildFrame();

    while (!glfwWindowShouldClose(window)) {
        glfwPollEvents();

        if (engine.autoScanEnabled()) {
            engine.step();
        }

        ImGui_ImplOpenGL2_NewFrame();
        ImGui_ImplGlfw_NewFrame();
        ImGui::NewFrame();

        try {
            rf::RenderFrontend(engine, uiState);
        } catch (const std::exception& ex) {
            ImGui::Begin("Runtime Error");
            ImGui::TextWrapped("%s", ex.what());
            ImGui::End();
        }

        ImGui::Render();

        int displayWidth = 0;
        int displayHeight = 0;
        glfwGetFramebufferSize(window, &displayWidth, &displayHeight);
        glViewport(0, 0, displayWidth, displayHeight);
        glClearColor(0.94F, 0.95F, 0.97F, 1.0F);
        glClear(GL_COLOR_BUFFER_BIT);
        ImGui_ImplOpenGL2_RenderDrawData(ImGui::GetDrawData());

        glfwSwapBuffers(window);
    }

    ImGui_ImplOpenGL2_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
    glfwDestroyWindow(window);
    glfwTerminate();
    return 0;
}
