%% O-RIS PIN DIODE SWITCHING CIRCUIT SIMULATOR
% Simulates BAP64-02 PIN diode switching for metasurface unit cell
% Analyzes phase shift, S-parameters, and switching dynamics
% Author: ALICE - O-RIS PoC Project
% Date: 2024

clear all; close all; clc;

%% ========================================================================
%  SECTION 1: COMPONENT PARAMETERS
%% ========================================================================

fprintf('=== O-RIS PIN Diode Circuit Simulator ===\n\n');

% Frequency parameters
f_center = 3.5e9;           % 3.5 GHz (n78 band center)
f_min = 3.3e9;              % Lower band edge
f_max = 3.7e9;              % Upper band edge
f_points = 201;             % Frequency points for sweep
freq = linspace(f_min, f_max, f_points);
omega = 2*pi*freq;
lambda_center = 3e8/f_center;  % Wavelength at center

% BAP64-02 PIN Diode Parameters (from datasheet)
% ON State (Forward Bias)
R_on = 4;                   % Series resistance (Ohms) - typical
L_on = 0.6e-9;              % Series inductance (nH)
C_on = 0.15e-12;            % Junction capacitance (pF) - minimal when ON

% OFF State (Reverse Bias)
R_off = 10e3;               % Series resistance (kOhms) - high impedance
L_off = 0.6e-9;             % Series inductance (nH) - same
C_off = 0.18e-12;           % Junction capacitance (pF) - increased

% Bias Network Components
R_bias = 100;               % Bias resistor (Ohms) - RF choke
C_dc_block = 10e-12;        % DC blocking capacitor (pF)
L_rf_choke = 100e-9;        % RF choke inductor (nH)

% Substrate Parameters (FR4)
er = 4.4;                   % Relative permittivity
h = 1.6e-3;                 % Substrate thickness (mm)
tan_delta = 0.02;           % Loss tangent

% Patch Geometry (from work plan)
patch_size = 5.7e-3;        % 5.7 mm square patch
Z0 = 50;                    % Characteristic impedance (Ohms)

%% ========================================================================
%  SECTION 2: DIODE IMPEDANCE CALCULATION
%% ========================================================================

fprintf('Calculating diode impedance vs frequency...\n');

% ON State Impedance
Z_diode_ON = R_on + 1i*omega*L_on + 1./(1i*omega*C_on);

% OFF State Impedance  
Z_diode_OFF = R_off + 1i*omega*L_off + 1./(1i*omega*C_off);

% Bias Network Impedance (parallel with diode at RF)
Z_bias = R_bias + 1i*omega*L_rf_choke;  % Series R and L for choke
Z_cap = 1./(1i*omega*C_dc_block);       % DC block capacitor

%% ========================================================================
%  SECTION 3: S-PARAMETER CALCULATION (SIMPLIFIED TRANSMISSION LINE MODEL)
%% ========================================================================

fprintf('Computing S-parameters for ON and OFF states...\n');

% Transmission line model for unit cell with switchable load
% S21 (Transmission) and S11 (Reflection) calculation

% ON State
Gamma_ON = (Z_diode_ON - Z0) ./ (Z_diode_ON + Z0);  % Reflection coefficient
S11_ON = Gamma_ON;
S21_ON = 1 + Gamma_ON;  % Simplified transmission (assumes lossless)

% OFF State
Gamma_OFF = (Z_diode_OFF - Z0) ./ (Z_diode_OFF + Z0);
S11_OFF = Gamma_OFF;
S21_OFF = 1 + Gamma_OFF;

% Convert to dB
S11_ON_dB = 20*log10(abs(S11_ON));
S21_ON_dB = 20*log10(abs(S21_ON));
S11_OFF_dB = 20*log10(abs(S11_OFF));
S21_OFF_dB = 20*log10(abs(S21_OFF));

% Phase extraction (in degrees)
Phase_S21_ON = angle(S21_ON) * 180/pi;
Phase_S21_OFF = angle(S21_OFF) * 180/pi;

% Phase difference (target: 160-180 degrees)
Phase_Diff = Phase_S21_ON - Phase_S21_OFF;
Phase_Diff = mod(Phase_Diff + 180, 360) - 180;  % Wrap to [-180, 180]

%% ========================================================================
%  SECTION 4: PERFORMANCE METRICS AT CENTER FREQUENCY
%% ========================================================================

[~, idx_center] = min(abs(freq - f_center));

fprintf('\n=== Performance at 3.5 GHz ===\n');
fprintf('ON State:\n');
fprintf('  S11 = %.2f dB, Phase = %.2f deg\n', S11_ON_dB(idx_center), angle(S11_ON(idx_center))*180/pi);
fprintf('  S21 = %.2f dB, Phase = %.2f deg\n', S21_ON_dB(idx_center), Phase_S21_ON(idx_center));
fprintf('  |Z_diode| = %.2f Ohms\n', abs(Z_diode_ON(idx_center)));
fprintf('\nOFF State:\n');
fprintf('  S11 = %.2f dB, Phase = %.2f deg\n', S11_OFF_dB(idx_center), angle(S11_OFF(idx_center))*180/pi);
fprintf('  S21 = %.2f dB, Phase = %.2f deg\n', S21_OFF_dB(idx_center), Phase_S21_OFF(idx_center));
fprintf('  |Z_diode| = %.2f Ohms\n', abs(Z_diode_OFF(idx_center)));
fprintf('\nPhase Shift:\n');
fprintf('  Δφ = %.2f degrees\n', Phase_Diff(idx_center));

% Check if target achieved
if abs(Phase_Diff(idx_center)) >= 160 && abs(Phase_Diff(idx_center)) <= 180
    fprintf('  ✓ TARGET ACHIEVED (160-180 deg)\n');
else
    fprintf('  ✗ Target not met (adjust patch size or diode position)\n');
end

%% ========================================================================
%  SECTION 5: SWITCHING DYNAMICS (TIME DOMAIN)
%% ========================================================================

fprintf('\nSimulating switching transient response...\n');

% Time parameters
t_max = 500e-9;             % 500 ns simulation
dt = 0.1e-9;                % 0.1 ns time step
t = 0:dt:t_max;

% Control signal (square wave switching)
f_switch = 10e6;            % 10 MHz switching rate
V_control = 5 * square(2*pi*f_switch*t);  % 0V to 5V GPIO signal

% Diode switching time constants
tau_on = 1e-9;              % Turn-on time ~1 ns (fast)
tau_off = 10e-9;            % Turn-off time ~10 ns (carrier recombination)

% Simulate diode resistance change
R_diode = zeros(size(t));
for i = 2:length(t)
    if V_control(i) > 2.5  % Switching to ON
        R_diode(i) = R_off + (R_on - R_off) * (1 - exp(-(t(i)-t(i-1))/tau_on));
    else  % Switching to OFF
        R_diode(i) = R_on + (R_off - R_on) * (1 - exp(-(t(i)-t(i-1))/tau_off));
    end
end

%% ========================================================================
%  SECTION 6: POWER CONSUMPTION ANALYSIS
%% ========================================================================

fprintf('Analyzing power consumption...\n');

% Per diode power (ON state, forward bias)
V_forward = 0.9;            % Forward voltage drop (V)
I_forward = 10e-3;          % Forward current (mA)
P_diode_ON = V_forward * I_forward;  % Power per diode (mW)

% Total array power (16×16 = 256 diodes, worst case all ON)
N_diodes_per_panel = 16 * 16;
N_panels = 8;
N_diodes_total = N_diodes_per_panel * N_panels;

P_total_array = P_diode_ON * N_diodes_total / 2;  % Assume 50% ON average

fprintf('\nPower Consumption:\n');
fprintf('  Per diode (ON): %.2f mW\n', P_diode_ON * 1000);
fprintf('  Per panel (256 diodes, 50%% duty): %.2f W\n', P_diode_ON * N_diodes_per_panel / 2);
fprintf('  Total array (8 panels): %.2f W\n', P_total_array);
fprintf('  12V SMPS rating: 10A = 120W (sufficient)\n');

%% ========================================================================
%  SECTION 7: VISUALIZATION
%% ========================================================================

fprintf('\nGenerating plots...\n');

% Figure 1: S-Parameters vs Frequency
figure('Name', 'S-Parameters Analysis', 'Position', [100 100 1200 800]);

subplot(2,2,1);
plot(freq/1e9, S11_ON_dB, 'b-', 'LineWidth', 2); hold on;
plot(freq/1e9, S11_OFF_dB, 'r--', 'LineWidth', 2);
grid on;
xlabel('Frequency (GHz)');
ylabel('S11 (dB)');
title('Reflection Coefficient (S11)');
legend('ON State', 'OFF State', 'Location', 'best');
xlim([f_min/1e9 f_max/1e9]);

subplot(2,2,2);
plot(freq/1e9, S21_ON_dB, 'b-', 'LineWidth', 2); hold on;
plot(freq/1e9, S21_OFF_dB, 'r--', 'LineWidth', 2);
grid on;
xlabel('Frequency (GHz)');
ylabel('S21 (dB)');
title('Transmission Coefficient (S21)');
legend('ON State', 'OFF State', 'Location', 'best');
xlim([f_min/1e9 f_max/1e9]);

subplot(2,2,3);
plot(freq/1e9, Phase_S21_ON, 'b-', 'LineWidth', 2); hold on;
plot(freq/1e9, Phase_S21_OFF, 'r--', 'LineWidth', 2);
grid on;
xlabel('Frequency (GHz)');
ylabel('Phase (degrees)');
title('S21 Phase Response');
legend('ON State', 'OFF State', 'Location', 'best');
xlim([f_min/1e9 f_max/1e9]);

subplot(2,2,4);
plot(freq/1e9, Phase_Diff, 'k-', 'LineWidth', 2.5); hold on;
plot([f_min/1e9 f_max/1e9], [160 160], 'g--', 'LineWidth', 1.5);
plot([f_min/1e9 f_max/1e9], [180 180], 'g--', 'LineWidth', 1.5);
plot([f_min/1e9 f_max/1e9], [-160 -160], 'g--', 'LineWidth', 1.5);
plot([f_min/1e9 f_max/1e9], [-180 -180], 'g--', 'LineWidth', 1.5);
grid on;
xlabel('Frequency (GHz)');
ylabel('Phase Difference (degrees)');
title('Phase Shift (Δφ = ON - OFF)');
legend('Δφ', 'Target Range', 'Location', 'best');
xlim([f_min/1e9 f_max/1e9]);
ylim([-200 200]);

% Figure 2: Impedance Analysis
figure('Name', 'Diode Impedance Analysis', 'Position', [150 150 1200 600]);

subplot(1,2,1);
plot(freq/1e9, abs(Z_diode_ON), 'b-', 'LineWidth', 2); hold on;
plot(freq/1e9, abs(Z_diode_OFF), 'r--', 'LineWidth', 2);
plot([f_min/1e9 f_max/1e9], [Z0 Z0], 'k:', 'LineWidth', 1.5);
grid on;
xlabel('Frequency (GHz)');
ylabel('|Z| (Ohms)');
title('Diode Impedance Magnitude');
legend('ON State', 'OFF State', '50Ω Reference', 'Location', 'best');
set(gca, 'YScale', 'log');
xlim([f_min/1e9 f_max/1e9]);

subplot(1,2,2);
plot(freq/1e9, angle(Z_diode_ON)*180/pi, 'b-', 'LineWidth', 2); hold on;
plot(freq/1e9, angle(Z_diode_OFF)*180/pi, 'r--', 'LineWidth', 2);
grid on;
xlabel('Frequency (GHz)');
ylabel('Phase (degrees)');
title('Diode Impedance Phase');
legend('ON State', 'OFF State', 'Location', 'best');
xlim([f_min/1e9 f_max/1e9]);

% Figure 3: Switching Dynamics
figure('Name', 'Switching Transient Response', 'Position', [200 200 1200 600]);

subplot(2,1,1);
plot(t*1e9, V_control, 'k-', 'LineWidth', 1.5);
grid on;
xlabel('Time (ns)');
ylabel('Control Voltage (V)');
title('GPIO Control Signal (5V Logic)');
ylim([-1 6]);

subplot(2,1,2);
plot(t*1e9, R_diode, 'b-', 'LineWidth', 2);
grid on;
xlabel('Time (ns)');
ylabel('Diode Resistance (Ohms)');
title('Diode Resistance Transient (ON/OFF Switching)');
set(gca, 'YScale', 'log');
ylim([1 1e5]);

%% ========================================================================
%  SECTION 8: DATA EXPORT FOR CST VALIDATION
%% ========================================================================

fprintf('\nExporting data for CST validation...\n');

% Save S-parameters to text file (for Soozi's plotting)
output_data = [freq', S11_ON_dB', S21_ON_dB', Phase_S21_ON', ...
               S11_OFF_dB', S21_OFF_dB', Phase_S21_OFF', Phase_Diff'];

fileID = fopen('/home/claude/s_parameters_export.txt', 'w');
fprintf(fileID, 'Frequency(Hz)\tS11_ON(dB)\tS21_ON(dB)\tPhase_ON(deg)\tS11_OFF(dB)\tS21_OFF(dB)\tPhase_OFF(deg)\tPhaseDiff(deg)\n');
fprintf(fileID, '%.6e\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\n', output_data');
fclose(fileID);

fprintf('  ✓ S-parameters saved to: s_parameters_export.txt\n');

% Save MATLAB workspace for further analysis
save('/home/claude/pin_diode_simulation.mat');
fprintf('  ✓ Workspace saved to: pin_diode_simulation.mat\n');

%% ========================================================================
%  SECTION 9: OPTIMIZATION RECOMMENDATIONS
%% ========================================================================

fprintf('\n=== Optimization Recommendations ===\n');

if abs(Phase_Diff(idx_center)) < 160
    fprintf('⚠ Phase shift too low. Try:\n');
    fprintf('   1. Increase patch size by +0.2mm (5.9mm)\n');
    fprintf('   2. Move diode closer to patch edge\n');
    fprintf('   3. Use thinner substrate (1.2mm instead of 1.6mm)\n');
elseif abs(Phase_Diff(idx_center)) > 180
    fprintf('⚠ Phase shift too high. Try:\n');
    fprintf('   1. Decrease patch size by -0.2mm (5.5mm)\n');
    fprintf('   2. Move diode toward patch center\n');
else
    fprintf('✓ Phase shift within target range!\n');
    fprintf('  Proceed to CST full-wave simulation for validation.\n');
end

fprintf('\n=== Simulation Complete ===\n');
fprintf('Next Steps:\n');
fprintf('  1. Import these results into CST for EM validation\n');
fprintf('  2. Share s_parameters_export.txt with Soozi\n');
fprintf('  3. Use phase shift data in control matrix simulator\n');
