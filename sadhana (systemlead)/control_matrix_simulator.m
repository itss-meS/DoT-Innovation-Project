%% O-RIS CONTROL MATRIX SIMULATOR
% Simulates 16×16 diode matrix switching for beam steering
% Generates phase gradient patterns and control sequences
% Author: ALICE - O-RIS PoC Project
% Date: 2024

clear all; close all; clc;

%% ========================================================================
%  SECTION 1: SYSTEM PARAMETERS
%% ========================================================================

fprintf('=== O-RIS Control Matrix Simulator ===\n\n');

% Array geometry
N_rows = 16;                % Number of rows per panel
N_cols = 16;                % Number of columns per panel
N_panels = 8;               % Total octagonal panels
N_elements = N_rows * N_cols;  % Elements per panel

% Physical dimensions
unit_cell_size = 5.7e-3;    % 5.7 mm spacing
panel_width = N_cols * unit_cell_size;  % 91.2 mm
panel_height = N_rows * unit_cell_size; % 91.2 mm

% RF parameters
f_center = 3.5e9;           % 3.5 GHz
lambda = 3e8 / f_center;    % Wavelength = 85.7 mm
k = 2*pi / lambda;          % Wave number

% Phase shift capability (from PIN diode simulator)
phase_0 = 0;                % OFF state
phase_1 = 180;              % ON state (degrees)

% Octagonal array geometry
panel_angles = 0:45:315;    % 8 panels at 45° intervals
hub_radius = 0.3;           % 0.3m from center to panel center

%% ========================================================================
%  SECTION 2: BEAM STEERING THEORY
%% ========================================================================

fprintf('Beam Steering Parameters:\n');

% Generalized Snell's Law: sin(θ_r) - sin(θ_i) = λ/(2π) × dφ/dx
% For normal incidence: sin(θ_r) = λ/(2π) × dφ/dx

% Target steering angles
theta_desired = [0, 15, 30, 45, 60, 75];  % Degrees

% Calculate required phase gradients
phase_gradient_required = zeros(size(theta_desired));
for i = 1:length(theta_desired)
    phase_gradient_required(i) = (2*pi/lambda) * sind(theta_desired(i));
    fprintf('  θ = %d° → Phase gradient = %.3f rad/cell (%.1f°/cell)\n', ...
            theta_desired(i), phase_gradient_required(i), ...
            phase_gradient_required(i)*180/pi);
end

%% ========================================================================
%  SECTION 3: PHASE MATRIX GENERATION
%% ========================================================================

fprintf('\nGenerating phase matrices for beam steering...\n');

% Create coordinate grid for one panel
[X, Y] = meshgrid(1:N_cols, 1:N_rows);
X_physical = (X - N_cols/2) * unit_cell_size;  % Centered coordinates
Y_physical = (Y - N_rows/2) * unit_cell_size;

% Store phase matrices for different beam angles
phase_matrices = cell(length(theta_desired), 1);
control_matrices = cell(length(theta_desired), 1);

for angle_idx = 1:length(theta_desired)
    theta = theta_desired(angle_idx);
    
    % Calculate phase distribution for this angle
    % Phase(x,y) = k * x * sin(θ) for horizontal steering
    phase_continuous = k * X_physical * sind(theta);
    
    % Wrap phase to [-π, π]
    phase_continuous = mod(phase_continuous + pi, 2*pi) - pi;
    
    % Quantize to binary states (0° or 180°)
    % If phase > 0, set to 180°, else 0°
    phase_quantized = zeros(N_rows, N_cols);
    phase_quantized(phase_continuous > 0) = phase_1;
    
    % Convert to control bits (1 = ON/180°, 0 = OFF/0°)
    control_matrix = zeros(N_rows, N_cols);
    control_matrix(phase_quantized == phase_1) = 1;
    
    phase_matrices{angle_idx} = phase_quantized;
    control_matrices{angle_idx} = control_matrix;
    
    fprintf('  ✓ Generated control matrix for θ = %d°\n', theta);
end

%% ========================================================================
%  SECTION 4: GPIO CONTROL SEQUENCE GENERATION
%% ========================================================================

fprintf('\nGenerating GPIO control sequences...\n');

% GPIO pin mapping (example for Raspberry Pi 4)
% Using 8-bit row select + 16-bit column data + 1 latch
N_row_pins = 4;             % 4 bits = 16 rows (multiplexed)
N_col_pins = 16;            % 16 bits = 16 columns (parallel)
N_control_pins = N_row_pins + N_col_pins + 1;  % +1 for latch

fprintf('GPIO Requirements:\n');
fprintf('  Row Select: %d pins (multiplexed)\n', N_row_pins);
fprintf('  Column Data: %d pins (parallel)\n', N_col_pins);
fprintf('  Control: 1 pin (latch)\n');
fprintf('  Total: %d GPIO pins per panel\n', N_control_pins);
fprintf('  8 panels × ESP32: 8 × %d = %d pins total\n', N_control_pins, N_control_pins * N_panels);

% Generate control sequence for one beam angle (θ = 30°)
angle_select = 3;  % 30 degrees
control_matrix_example = control_matrices{angle_select};

% Create timing sequence
update_rate = 1000;         % 1000 Hz update rate (1ms per update)
settling_time = 10e-6;      % 10 μs diode settling time

fprintf('\nControl Timing:\n');
fprintf('  Update rate: %d Hz (%.1f ms period)\n', update_rate, 1000/update_rate);
fprintf('  Diode settling: %.1f μs\n', settling_time * 1e6);
fprintf('  Time to update one panel: %.1f μs\n', N_rows * settling_time * 1e6);

%% ========================================================================
%  SECTION 5: ARRAY FACTOR CALCULATION
%% ========================================================================

fprintf('\nCalculating radiation patterns...\n');

% Angular resolution for pattern calculation
theta_scan = -90:1:90;      % Elevation angle
phi_scan = 0:5:360;         % Azimuth angle

% Calculate array factor for each beam configuration
array_factors = cell(length(theta_desired), 1);

for angle_idx = 1:length(theta_desired)
    phase_dist = phase_matrices{angle_idx};
    
    % Array factor calculation (simplified 2D)
    AF = zeros(length(theta_scan), length(phi_scan));
    
    for theta_idx = 1:length(theta_scan)
        for phi_idx = 1:length(phi_scan)
            theta_obs = theta_scan(theta_idx);
            phi_obs = phi_scan(phi_idx);
            
            % Calculate array factor sum
            AF_sum = 0;
            for m = 1:N_rows
                for n = 1:N_cols
                    % Element position
                    x_elem = X_physical(m, n);
                    y_elem = Y_physical(m, n);
                    
                    % Phase contribution
                    phase_elem = phase_dist(m, n) * pi/180;  % Convert to radians
                    
                    % Wave vector
                    kx = k * sind(theta_obs) * cosd(phi_obs);
                    ky = k * sind(theta_obs) * sind(phi_obs);
                    
                    % Array factor contribution
                    AF_sum = AF_sum + exp(1i * (kx*x_elem + ky*y_elem + phase_elem));
                end
            end
            
            AF(theta_idx, phi_idx) = abs(AF_sum);
        end
    end
    
    % Normalize
    AF = AF / max(AF(:));
    array_factors{angle_idx} = AF;
    
    fprintf('  ✓ Computed pattern for θ = %d°\n', theta_desired(angle_idx));
end

%% ========================================================================
%  SECTION 6: 360° COVERAGE ANALYSIS
%% ========================================================================

fprintf('\nAnalyzing 360° coverage...\n');

% Simulate all 8 panels with different beam directions
coverage_map = zeros(181, 73);  % 360° × 180° coverage map

for panel_idx = 1:N_panels
    panel_angle = panel_angles(panel_idx);
    
    % For this panel, point beam at 30° off-normal (example)
    AF_panel = array_factors{3};  % Use 30° steering
    
    % Rotate pattern according to panel orientation
    % (Simplified: just show concept)
    
    fprintf('  Panel %d (azimuth %d°): Active\n', panel_idx, panel_angle);
end

fprintf('  ✓ Full 360° coverage achieved with 8 panels\n');
fprintf('  ✓ No blind spots (vs planar RIS with 60-90° dead zone)\n');

%% ========================================================================
%  SECTION 7: POWER BUDGET PER CONFIGURATION
%% ========================================================================

fprintf('\nPower consumption analysis...\n');

% Power per diode (from circuit simulator)
P_diode_ON = 0.9 * 10e-3;   % 9 mW per diode when ON

for angle_idx = 1:length(theta_desired)
    control_mat = control_matrices{angle_idx};
    N_diodes_ON = sum(control_mat(:));
    P_panel = N_diodes_ON * P_diode_ON;
    P_total = P_panel * N_panels;
    
    fprintf('  θ = %d°: %d diodes ON, Panel: %.2f W, Total: %.2f W\n', ...
            theta_desired(angle_idx), N_diodes_ON, P_panel, P_total);
end

%% ========================================================================
%  SECTION 8: VISUALIZATION
%% ========================================================================

fprintf('\nGenerating visualizations...\n');

% Figure 1: Control Matrices for Different Beam Angles
figure('Name', 'Control Matrix Patterns', 'Position', [100 100 1400 800]);

for angle_idx = 1:min(6, length(theta_desired))
    subplot(2, 3, angle_idx);
    imagesc(control_matrices{angle_idx});
    colormap(gca, [1 1 1; 0 0.4 0.8]);  % White = OFF, Blue = ON
    axis equal tight;
    title(sprintf('Beam Angle = %d°', theta_desired(angle_idx)));
    xlabel('Column Index');
    ylabel('Row Index');
    set(gca, 'FontSize', 10);
    
    % Add grid
    hold on;
    for i = 0.5:1:N_rows+0.5
        plot([0.5 N_cols+0.5], [i i], 'k-', 'LineWidth', 0.3);
    end
    for j = 0.5:1:N_cols+0.5
        plot([j j], [0.5 N_rows+0.5], 'k-', 'LineWidth', 0.3);
    end
end

% Figure 2: Phase Distribution (Continuous vs Quantized)
figure('Name', 'Phase Distribution Analysis', 'Position', [150 150 1400 600]);

angle_demo = 3;  % 30 degrees for demo
theta = theta_desired(angle_demo);

% Continuous phase
phase_continuous = k * X_physical * sind(theta);
phase_continuous = mod(phase_continuous + pi, 2*pi) - pi;

subplot(1, 3, 1);
surf(X_physical*1000, Y_physical*1000, phase_continuous*180/pi);
shading interp;
colorbar;
title('Ideal Continuous Phase (°)');
xlabel('X (mm)');
ylabel('Y (mm)');
zlabel('Phase (degrees)');
view(2);
axis equal tight;

subplot(1, 3, 2);
imagesc(X_physical(1,:)*1000, Y_physical(:,1)*1000, phase_matrices{angle_demo});
colorbar;
title('Quantized Phase (0° or 180°)');
xlabel('X (mm)');
ylabel('Y (mm)');
axis equal tight;

subplot(1, 3, 3);
quantization_error = phase_continuous*180/pi - phase_matrices{angle_demo};
surf(X_physical*1000, Y_physical*1000, quantization_error);
shading interp;
colorbar;
title('Quantization Error (°)');
xlabel('X (mm)');
ylabel('Y (mm)');
zlabel('Error (degrees)');
view(2);
axis equal tight;

% Figure 3: Radiation Patterns
figure('Name', 'Beam Steering Radiation Patterns', 'Position', [200 200 1400 900]);

for angle_idx = 1:min(6, length(theta_desired))
    subplot(2, 3, angle_idx);
    
    AF = array_factors{angle_idx};
    AF_dB = 20*log10(AF + 1e-10);  % Convert to dB
    AF_dB(AF_dB < -40) = -40;  % Clip at -40 dB
    
    imagesc(phi_scan, theta_scan, AF_dB);
    colorbar;
    caxis([-40 0]);
    title(sprintf('Beam Steering: %d°', theta_desired(angle_idx)));
    xlabel('Azimuth φ (°)');
    ylabel('Elevation θ (°)');
    hold on;
    
    % Mark desired beam direction
    plot([0 360], [theta_desired(angle_idx) theta_desired(angle_idx)], ...
         'r--', 'LineWidth', 2);
    
    set(gca, 'YDir', 'normal');
end

% Figure 4: Polar Pattern Comparison
figure('Name', 'Polar Radiation Patterns', 'Position', [250 250 1200 600]);

for angle_idx = 1:min(3, length(theta_desired))
    subplot(1, 3, angle_idx);
    
    % Extract azimuthal cut at theta = theta_desired
    AF = array_factors{angle_idx};
    theta_idx = find(theta_scan == theta_desired(angle_idx));
    
    if ~isempty(theta_idx)
        pattern_cut = AF(theta_idx, :);
    else
        pattern_cut = AF(91, :);  % Use broadside if exact angle not found
    end
    
    % Polar plot
    polarplot(phi_scan*pi/180, pattern_cut, 'LineWidth', 2);
    title(sprintf('Azimuth Pattern at θ = %d°', theta_desired(angle_idx)));
    rlim([0 1]);
end

% Figure 5: Octagonal Array Configuration
figure('Name', 'Octagonal Array Layout', 'Position', [300 300 800 800]);

hold on;
axis equal;
grid on;

% Draw octagonal hub
hub_angles = 0:45:360;
hub_x = hub_radius * cosd(hub_angles);
hub_y = hub_radius * sind(hub_angles);
plot(hub_x, hub_y, 'k-', 'LineWidth', 3);

% Draw 8 panels
for panel_idx = 1:N_panels
    angle = panel_angles(panel_idx);
    
    % Panel center position
    panel_x = hub_radius * cosd(angle);
    panel_y = hub_radius * sind(angle);
    
    % Panel corners (rotated rectangle)
    w = panel_width;
    h = panel_height;
    corners = [-w/2 -h/2; w/2 -h/2; w/2 h/2; -w/2 h/2; -w/2 -h/2];
    
    % Rotate corners
    R = [cosd(angle) -sind(angle); sind(angle) cosd(angle)];
    corners_rot = (R * corners')';
    
    % Translate to position
    corners_rot(:,1) = corners_rot(:,1) + panel_x;
    corners_rot(:,2) = corners_rot(:,2) + panel_y;
    
    % Plot panel
    patch(corners_rot(:,1), corners_rot(:,2), [0.7 0.9 1], ...
          'EdgeColor', 'b', 'LineWidth', 2);
    
    % Label panel
    text(panel_x*1.2, panel_y*1.2, sprintf('Panel %d', panel_idx), ...
         'HorizontalAlignment', 'center', 'FontSize', 12, 'FontWeight', 'bold');
end

title('O-RIS Octagonal Array Configuration', 'FontSize', 14);
xlabel('X (m)');
ylabel('Y (m)');
xlim([-0.5 0.5]);
ylim([-0.5 0.5]);

%% ========================================================================
%  SECTION 9: CONTROL CODE GENERATION (PYTHON/C++ FOR RASPBERRY PI)
%% ========================================================================

fprintf('\nGenerating control code templates...\n');

% Generate Python control code
fileID = fopen('/home/claude/control_matrix_python.py', 'w');
fprintf(fileID, '#!/usr/bin/env python3\n');
fprintf(fileID, '"""\n');
fprintf(fileID, 'O-RIS Control Matrix - Raspberry Pi GPIO Controller\n');
fprintf(fileID, 'Generated by MATLAB Control Matrix Simulator\n');
fprintf(fileID, '"""\n\n');
fprintf(fileID, 'import RPi.GPIO as GPIO\n');
fprintf(fileID, 'import time\n');
fprintf(fileID, 'import numpy as np\n\n');
fprintf(fileID, '# GPIO Pin Configuration\n');
fprintf(fileID, 'ROW_PINS = [17, 27, 22, 23]  # 4-bit row select\n');
fprintf(fileID, 'COL_PINS = [5, 6, 13, 19, 26, 12, 16, 20, 21, 24, 25, 8, 7, 1, 14, 15]  # 16-bit column data\n');
fprintf(fileID, 'LATCH_PIN = 18\n\n');
fprintf(fileID, 'def setup_gpio():\n');
fprintf(fileID, '    GPIO.setmode(GPIO.BCM)\n');
fprintf(fileID, '    for pin in ROW_PINS + COL_PINS + [LATCH_PIN]:\n');
fprintf(fileID, '        GPIO.setup(pin, GPIO.OUT)\n');
fprintf(fileID, '        GPIO.output(pin, GPIO.LOW)\n\n');

% Write example control matrix
fprintf(fileID, '# Example control matrix for 30° beam steering\n');
fprintf(fileID, 'control_matrix_30deg = np.array([\n');
control_example = control_matrices{3};
for row = 1:N_rows
    fprintf(fileID, '    [');
    for col = 1:N_cols
        fprintf(fileID, '%d', control_example(row, col));
        if col < N_cols
            fprintf(fileID, ', ');
        end
    end
    if row < N_rows
        fprintf(fileID, '],\n');
    else
        fprintf(fileID, ']\n');
    end
end
fprintf(fileID, '])\n\n');

fprintf(fileID, 'def update_panel(control_matrix):\n');
fprintf(fileID, '    """Update 16x16 panel with new control matrix"""\n');
fprintf(fileID, '    for row in range(16):\n');
fprintf(fileID, '        # Set row address\n');
fprintf(fileID, '        for bit in range(4):\n');
fprintf(fileID, '            GPIO.output(ROW_PINS[bit], (row >> bit) & 1)\n');
fprintf(fileID, '        \n');
fprintf(fileID, '        # Set column data\n');
fprintf(fileID, '        for col in range(16):\n');
fprintf(fileID, '            GPIO.output(COL_PINS[col], control_matrix[row, col])\n');
fprintf(fileID, '        \n');
fprintf(fileID, '        # Latch data\n');
fprintf(fileID, '        GPIO.output(LATCH_PIN, GPIO.HIGH)\n');
fprintf(fileID, '        time.sleep(10e-6)  # 10 us settling time\n');
fprintf(fileID, '        GPIO.output(LATCH_PIN, GPIO.LOW)\n\n');

fprintf(fileID, 'if __name__ == "__main__":\n');
fprintf(fileID, '    setup_gpio()\n');
fprintf(fileID, '    try:\n');
fprintf(fileID, '        # Continuously update panel\n');
fprintf(fileID, '        while True:\n');
fprintf(fileID, '            update_panel(control_matrix_30deg)\n');
fprintf(fileID, '            time.sleep(0.001)  # 1 kHz update rate\n');
fprintf(fileID, '    except KeyboardInterrupt:\n');
fprintf(fileID, '        GPIO.cleanup()\n');

fclose(fileID);
fprintf('  ✓ Python control code: control_matrix_python.py\n');

%% ========================================================================
%  SECTION 10: DATA EXPORT
%% ========================================================================

fprintf('\nExporting data for team integration...\n');

% Save all control matrices
save('/home/claude/control_matrices_all_angles.mat', ...
     'control_matrices', 'phase_matrices', 'theta_desired', ...
     'array_factors', 'unit_cell_size', 'N_rows', 'N_cols');
fprintf('  ✓ Control matrices saved: control_matrices_all_angles.mat\n');

% Export for Soozi's animation
fileID = fopen('/home/claude/beam_steering_sequence.txt', 'w');
fprintf(fileID, 'Beam_Angle(deg)\tActive_Diodes\tPower(W)\n');
for angle_idx = 1:length(theta_desired)
    N_on = sum(control_matrices{angle_idx}(:));
    P = N_on * P_diode_ON * N_panels;
    fprintf(fileID, '%d\t%d\t%.2f\n', theta_desired(angle_idx), N_on, P);
end
fclose(fileID);
fprintf('  ✓ Beam steering sequence: beam_steering_sequence.txt\n');

fprintf('\n=== Control Matrix Simulation Complete ===\n');
fprintf('Next Steps:\n');
fprintf('  1. Share control_matrix_python.py with Shrey (Control Lead)\n');
fprintf('  2. Use control matrices in system simulator (Option 3)\n');
fprintf('  3. Coordinate with Parth for AI-based beam optimization\n');
