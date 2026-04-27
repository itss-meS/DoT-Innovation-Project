@echo off
cd cmake-build-debug
ninja
if %ERRORLEVEL% EQU 0 (
    echo Build successful!
    cd ..
) else (
    echo Build failed!
    exit /b 1
)
