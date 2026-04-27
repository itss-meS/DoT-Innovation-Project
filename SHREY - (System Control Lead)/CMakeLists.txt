cmake_minimum_required(VERSION 3.20)
project(SHREY LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(FetchContent)

set(GLFW_BUILD_DOCS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
        glfw
        GIT_REPOSITORY https://github.com/glfw/glfw.git
        GIT_TAG 3.4
)

FetchContent_Declare(
        imgui
        GIT_REPOSITORY https://github.com/ocornut/imgui.git
        GIT_TAG v1.91.8
)

FetchContent_MakeAvailable(glfw imgui)

find_package(OpenGL REQUIRED)

add_library(imgui_static STATIC
        ${imgui_SOURCE_DIR}/imgui.cpp
        ${imgui_SOURCE_DIR}/imgui_demo.cpp
        ${imgui_SOURCE_DIR}/imgui_draw.cpp
        ${imgui_SOURCE_DIR}/imgui_tables.cpp
        ${imgui_SOURCE_DIR}/imgui_widgets.cpp
        ${imgui_SOURCE_DIR}/backends/imgui_impl_glfw.cpp
        ${imgui_SOURCE_DIR}/backends/imgui_impl_opengl2.cpp
)

target_include_directories(imgui_static PUBLIC
        ${imgui_SOURCE_DIR}
        ${imgui_SOURCE_DIR}/backends
)

target_link_libraries(imgui_static PUBLIC glfw OpenGL::GL)

if (MSVC)
    target_compile_definitions(imgui_static PRIVATE _CRT_SECURE_NO_WARNINGS)
endif ()

add_executable(SHREY
        main.cpp
        src/patch_controller.cpp
        src/shift_register_chain.cpp
        src/simulation_engine.cpp
        src/imgui_frontend.cpp
)

target_include_directories(SHREY PRIVATE include)
target_link_libraries(SHREY PRIVATE imgui_static)
