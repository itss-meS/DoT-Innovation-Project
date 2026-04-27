@echo off
REM Build script for SHREY 3D Octagon visualization
echo Building SHREY with 3D Octagonal Visualization...
cd /d E:\DoT\SHREY\cmake-build-debug
echo Running Ninja build...
ninja
if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo  Build SUCCESSFUL!
    echo  Executable: E:\DoT\SHREY\cmake-build-debug\SHREY.exe
    echo  You can now run the application.
    echo ========================================
    cd ..
) else (
    echo.
    echo ERROR: Build failed with code %ERRORLEVEL%
    exit /b %ERRORLEVEL%
)
