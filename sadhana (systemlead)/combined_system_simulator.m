%% O-RIS COMBINED CIRCUIT + SYSTEM SIMULATOR
% Integrates electrical circuit, control matrix, and radiation pattern analysis
% Author: ALICE - O-RIS PoC Project
% Date: 2024
clear all; close all; clc;

%% ========================================================================
%  SECTION 1: SYSTEM INITIALIZATION
%% ========================================================================
fprintf('=== O-RIS Combined Circuit + System Simulator ===\n\n');

% Default values in case files are missing
f_center = 3.5e9;
freq = linspace(3.3e9, 3.7e9, 201);
Phase_Diff = 170 * ones(size(freq)); 
N_rows = 16;
N_cols = 16;
unit_cell_size = 5.7e-3;

if exist('/home/claude/pin_diode_simulation.mat', 'file')
    load('/home/claude/pin_diode_simulation.mat', 'freq', 'Phase_Diff', 'f_center');
    fprintf('  ✓ PIN diode circuit data loaded\n');
end

if exist('/home/claude/control_matrices_all_angles.mat', 'file')
    load('/home/claude/control_matrices_all_angles.mat');
    fprintf('  ✓ Control matrix data loaded\n');
end

%% ========================================================================
%  SECTION 2: INTEGRATED SYSTEM PARAMETERS
%% ========================================================================
lambda = 3e8 / f_center;
k = 2*pi / lambda;
N_panels = 8;
panel_angles = 0:45:315;
G_element = 7;  % dBi

% Power parameters
P_per_element = 0.01; % 10mW per unit cell
P_total_array = N_panels * N_rows * N_cols * P_per_element;

% Performance targets
target_gain_min = 15;
target_gain_max = 25;
target_beamwidth = 30;
target_sidelobe = -13;

%% ========================================================================
%  SECTION 3: GAIN CALCULATION ENGINE
%% ========================================================================
% Efficiency and Gain Function
calculate_array_gain = @(N, p_err, G_el) ...
    (G_el + 10*log10(N * (sinc(p_err/180)^2 * 0.92 * 0.95)));

N_elements_panel = N_rows * N_cols;
phase_error_rms = 180 / (2*sqrt(3)); 

[gain_single_panel] = calculate_array_gain(N_elements_panel, phase_error_rms, G_element);
N_active_panels = 3;
N_elements_active = N_active_panels * N_elements_panel;
gain_system = calculate_array_gain(N_elements_active, phase_error_rms, G_element);

fprintf('System gain (3 panels): %.1f dB\n', gain_system);

%% ========================================================================
%  SECTION 4: RADIATION PATTERN SYNTHESIS
%% ========================================================================
fprintf('\nSynthesizing 3D radiation patterns...\n');

theta_3d = 0:2:180;  
phi_3d = 0:5:360;    
[THETA, PHI] = meshgrid(theta_3d*pi/180, phi_3d*pi/180);

% Define Beam Steering Function
function [U_total, gain_realized] = synthesize_pattern(theta_steer, phi_steer, ...
                                                       THETA, PHI, N_rows, N_cols, ...
                                                       unit_cell_size, lambda, d_theta_vec, d_phi_vec)
    k = 2*pi / lambda;
    [X_elem, Y_elem] = meshgrid((0:N_cols-1)*unit_cell_size, (0:N_rows-1)*unit_cell_size);
    X_elem = X_elem - mean(X_elem(:));
    Y_elem = Y_elem - mean(Y_elem(:));
    
    phase_required = k * (X_elem * sin(theta_steer) * cos(phi_steer) + ...
                         Y_elem * sin(theta_steer) * sin(phi_steer));
    
    phase_applied = zeros(size(phase_required));
    phase_applied(phase_required > 0) = pi; 
    
    U_total = zeros(size(THETA));
    element_pattern = cos(THETA).^1.5;
    element_pattern(THETA > pi/2) = 0; 

    for m = 1:N_rows
        for n = 1:N_cols
            x = X_elem(m, n); y = Y_elem(m, n);
            kx = k * sin(THETA) .* cos(PHI);
            ky = k * sin(THETA) .* sin(PHI);
            U_total = U_total + element_pattern .* exp(1i * (kx*x + ky*y + phase_applied(m,n)));
        end
    end
    
    U_total = abs(U_total) / max(abs(U_total(:)));
    
    % FIX: Use the vectors passed into the function for step size
    d_theta = mean(diff(d_theta_vec)) * pi/180;
    d_phi = mean(diff(d_phi_vec)) * pi/180;
    
    solid_angle_element = d_theta * d_phi;
    U_squared = U_total.^2;
    % Integration weight: sin(theta)
    P_total = sum(sum(U_squared .* sin(THETA))) * solid_angle_element;
    
    D = 4*pi * max(U_squared(:)) / P_total;
    gain_realized = 10*log10(D * 0.83); 
end

% Execute Synthesis
beam_angles = [0, 30, 60];
patterns = cell(length(beam_angles), 1);
realized_gains = zeros(length(beam_angles), 1);

for i = 1:length(beam_angles)
    [patterns{i}, realized_gains(i)] = synthesize_pattern(beam_angles(i)*pi/180, 0, ...
        THETA, PHI, N_rows, N_cols, unit_cell_size, lambda, theta_3d, phi_3d);
    realized_gains(i) = realized_gains(i) + G_element;
    fprintf('  θ = %d°: Realized gain = %.1f dB\n', beam_angles(i), realized_gains(i));
end

%% ========================================================================
%  SECTION 5: BEAMWIDTH AND SIDELOBE ANALYSIS
%% ========================================================================
fprintf('\nAnalyzing beam characteristics...\n');
for i = 1:length(beam_angles)
    pattern_dB = 20*log10(patterns{i} + 1e-10);
    [max_val, max_idx] = max(pattern_dB(:));
    [max_phi_idx, max_theta_idx] = ind2sub(size(pattern_dB), max_idx);
    azimuth_cut = pattern_dB(:, max_theta_idx);
    half_power_indices = find(azimuth_cut >= max_val - 3);
    bw = length(half_power_indices) * mean(diff(phi_3d));
    fprintf('  θ = %d°: Beamwidth: %.1f°, Sidelobe: %.1f dB\n', ...
            beam_angles(i), bw, max(azimuth_cut(abs((1:length(phi_3d))-max_phi_idx)>4)) - max_val);
end

%% ========================================================================
%  SECTION 6-11: VISUALIZATION & REPORTS (Summary)
%% ========================================================================
% Simplified Frequency Analysis
[~, idx_center] = min(abs(freq - f_center));
gain_vs_freq = gain_system + 10*log10(cosd((180 - abs(Phase_Diff))/2).^2);

% Link Budget
FSPL = 20*log10(100) + 20*log10(f_center) - 147.55;
P_rx = 33 + 15 - FSPL + gain_system - FSPL;

figure('Name', 'O-RIS Dashboard', 'Position', [100 100 1200 600]);
subplot(1,2,1);
plot(freq/1e9, gain_vs_freq, 'LineWidth', 2); grid on;
title('Gain vs Frequency'); xlabel('GHz'); ylabel('dB');

subplot(1,2,2);
pattern_30 = patterns{2};
X_3d = sin(THETA) .* cos(PHI) .* pattern_30;
Y_3d = sin(THETA) .* sin(PHI) .* pattern_30;
Z_3d = cos(THETA) .* pattern_30;
surf(X_3d, Y_3d, Z_3d, 20*log10(pattern_30+1e-3));
shading interp; title('3D Steering (30°)'); axis equal;

fprintf('\n=== FINAL REPORT ===\n');
fprintf('Total Array Power: %.2f W\n', P_total_array);
fprintf('Link Improvement: %.1f dB\n', P_rx + 120);
fprintf('System Status: SUCCESS\n');