%% O-RIS S-Parameter Processing and Visualization
% Purpose: Process and visualize S-parameter data from Alice's hardware design
% Author: SOOZI - Integration & Presentation Lead
% Project: O-RIS Proof of Concept
% Phase 2, Part 1: Days 8-15

clear all; close all; clc;

%% Generate Sample S-Parameter Data
% Note: Replace this section with actual data from Alice when available
fprintf('=== O-RIS S-Parameter Analysis ===\n\n');
fprintf('Generating sample S-parameter data...\n');
fprintf('(Replace with actual data from Alice by Day 8)\n\n');

% Frequency range: 2-5 GHz (O-RIS operates at 3.5 GHz)
freq_start = 2e9;
freq_end = 5e9;
num_points = 301;
frequency = linspace(freq_start, freq_end, num_points);

% Operating frequency
f_operating = 3.5e9;

% Simulate realistic S11 (reflection coefficient)
% Good design has S11 < -10 dB at operating frequency
S11_mag_dB = -15 - 5*exp(-((frequency - f_operating).^2) / (0.5e9)^2) + ...
             0.5*randn(1, num_points);
S11_phase_deg = -45 + 90*((frequency - freq_start)/(freq_end - freq_start)) + ...
                5*randn(1, num_points);

% Simulate S21 (transmission coefficient)
% High transmission desired at operating frequency
S21_mag_dB = -3 - 2*abs((frequency - f_operating)/(1e9)) + ...
             0.3*randn(1, num_points);
S21_phase_deg = unwrap(2*pi*((frequency - freq_start)/(freq_end - freq_start)) + ...
                0.1*randn(1, num_points)) * 180/pi;

% Phase shift capability (critical parameter)
phase_shift_capability = 160 + 20*exp(-((frequency - f_operating).^2) / (0.3e9)^2) + ...
                        2*randn(1, num_points);

fprintf('Sample data generated for %d frequency points\n', num_points);

%% Data Import Function (for actual Alice data)
% Uncomment and modify when Alice provides actual .s2p files
%{
function [freq, S11_dB, S11_phase, S21_dB, S21_phase] = load_s2p_file(filename)
    % Load .s2p Touchstone file
    data = read(rfdata.data, filename);
    freq = data.Freq;
    S11 = data.S_Parameters(1,1,:);
    S21 = data.S_Parameters(2,1,:);
    
    S11_dB = 20*log10(abs(S11(:)));
    S11_phase = angle(S11(:)) * 180/pi;
    S21_dB = 20*log10(abs(S21(:)));
    S21_phase = angle(S21(:)) * 180/pi;
end
%}

%% S-Parameter Visualization (Days 11-12)
fprintf('Creating S-parameter visualizations...\n');

figure('Position', [50, 50, 1400, 900]);

% Subplot 1: S11 Magnitude
subplot(3, 2, 1);
plot(frequency/1e9, S11_mag_dB, 'b-', 'LineWidth', 2);
hold on;
xline(f_operating/1e9, 'r--', 'LineWidth', 1.5, 'Label', '3.5 GHz');
yline(-10, 'g--', 'LineWidth', 1.5, 'Label', 'Target');
hold off;
grid on;
xlabel('Frequency (GHz)', 'FontSize', 11);
ylabel('S11 (dB)', 'FontSize', 11);
title('Reflection Coefficient (S11)', 'FontSize', 12, 'FontWeight', 'bold');
legend('Measured', 'Operating Freq', 'Target Level', 'Location', 'best');
ylim([-30 0]);

% Subplot 2: S11 Phase
subplot(3, 2, 2);
plot(frequency/1e9, S11_phase_deg, 'b-', 'LineWidth', 2);
hold on;
xline(f_operating/1e9, 'r--', 'LineWidth', 1.5);
hold off;
grid on;
xlabel('Frequency (GHz)', 'FontSize', 11);
ylabel('Phase (degrees)', 'FontSize', 11);
title('S11 Phase Response', 'FontSize', 12, 'FontWeight', 'bold');

% Subplot 3: S21 Magnitude
subplot(3, 2, 3);
plot(frequency/1e9, S21_mag_dB, 'r-', 'LineWidth', 2);
hold on;
xline(f_operating/1e9, 'b--', 'LineWidth', 1.5, 'Label', '3.5 GHz');
yline(-3, 'g--', 'LineWidth', 1.5, 'Label', 'Target');
hold off;
grid on;
xlabel('Frequency (GHz)', 'FontSize', 11);
ylabel('S21 (dB)', 'FontSize', 11);
title('Transmission Coefficient (S21)', 'FontSize', 12, 'FontWeight', 'bold');
legend('Measured', 'Operating Freq', 'Target Level', 'Location', 'best');
ylim([-10 0]);

% Subplot 4: S21 Phase
subplot(3, 2, 4);
plot(frequency/1e9, S21_phase_deg, 'r-', 'LineWidth', 2);
hold on;
xline(f_operating/1e9, 'b--', 'LineWidth', 1.5);
hold off;
grid on;
xlabel('Frequency (GHz)', 'FontSize', 11);
ylabel('Phase (degrees)', 'FontSize', 11);
title('S21 Phase Response', 'FontSize', 12, 'FontWeight', 'bold');

% Subplot 5: Phase Shift Capability
subplot(3, 2, 5);
plot(frequency/1e9, phase_shift_capability, 'Color', [0.4 0.2 0.6], 'LineWidth', 2);
hold on;
xline(f_operating/1e9, 'r--', 'LineWidth', 1.5, 'Label', '3.5 GHz');
yline(160, 'g--', 'LineWidth', 1.5, 'Label', 'Min Target (160°)');
yline(180, 'b--', 'LineWidth', 1.5, 'Label', 'Max Target (180°)');
hold off;
grid on;
xlabel('Frequency (GHz)', 'FontSize', 11);
ylabel('Phase Shift (degrees)', 'FontSize', 11);
title('Phase Shift Capability', 'FontSize', 12, 'FontWeight', 'bold');
legend('Measured', 'Operating Freq', 'Location', 'best');
ylim([120 200]);

% Subplot 6: Smith Chart (S11)
subplot(3, 2, 6);
S11_complex = 10.^(S11_mag_dB/20) .* exp(1j * S11_phase_deg * pi/180);

% Operating frequency point
idx_operating = find(abs(frequency - f_operating) == min(abs(frequency - f_operating)));
S11_at_3p5GHz = S11_complex(idx_operating);

% Plot Smith Chart
theta = linspace(0, 2*pi, 100);
plot(cos(theta), sin(theta), 'k-', 'LineWidth', 1.5);  % Unit circle
hold on;
plot([-1 1], [0 0], 'k-', 'LineWidth', 0.5);  % Real axis
plot([0 0], [-1 1], 'k-', 'LineWidth', 0.5);  % Imaginary axis
plot(real(S11_complex), imag(S11_complex), 'b-', 'LineWidth', 1.5);
plot(real(S11_at_3p5GHz), imag(S11_at_3p5GHz), 'ro', ...
    'MarkerSize', 12, 'MarkerFaceColor', 'r');
hold off;
axis equal;
grid on;
xlabel('Real(S11)', 'FontSize', 11);
ylabel('Imag(S11)', 'FontSize', 11);
title('Smith Chart - S11', 'FontSize', 12, 'FontWeight', 'bold');
legend('Unit Circle', '', '', 'S11 vs Freq', '3.5 GHz', 'Location', 'best');

sgtitle('O-RIS S-Parameter Analysis', 'FontSize', 16, 'FontWeight', 'bold');

% Save high-resolution figure
set(gcf, 'PaperPositionMode', 'auto');
print('-dpng', '-r300', 'oris_s_parameters_full_analysis.png');
fprintf('Full S-parameter analysis saved (300 DPI)\n');

%% Performance Metrics at Operating Frequency (Days 13-14)
fprintf('\n--- Performance at 3.5 GHz ---\n');

S11_at_op = S11_mag_dB(idx_operating);
S21_at_op = S21_mag_dB(idx_operating);
phase_shift_at_op = phase_shift_capability(idx_operating);

fprintf('S11 (Reflection): %.2f dB ', S11_at_op);
if S11_at_op < -10
    fprintf('✓ (Good impedance matching)\n');
else
    fprintf('✗ (Poor matching - needs improvement)\n');
end

fprintf('S21 (Transmission): %.2f dB ', S21_at_op);
if S21_at_op > -3
    fprintf('✓ (Low insertion loss)\n');
else
    fprintf('✗ (High loss - check design)\n');
end

fprintf('Phase Shift Range: %.1f° ', phase_shift_at_op);
if phase_shift_at_op >= 160 && phase_shift_at_op <= 180
    fprintf('✓ (Meets specification)\n');
else
    fprintf('✗ (Outside target range)\n');
end

%% Comparison with Ideal/Target Values
fprintf('\nCreating comparison plots...\n');

figure('Position', [100, 100, 1200, 400]);

% Target/Ideal values
S11_ideal = -20 * ones(size(frequency));
S21_ideal = -1 * ones(size(frequency));

% Subplot 1: S11 Comparison
subplot(1, 2, 1);
plot(frequency/1e9, S11_mag_dB, 'b-', 'LineWidth', 2.5);
hold on;
plot(frequency/1e9, S11_ideal, 'g--', 'LineWidth', 2);
xline(f_operating/1e9, 'r--', 'LineWidth', 1.5);
hold off;
grid on;
xlabel('Frequency (GHz)', 'FontSize', 12);
ylabel('S11 (dB)', 'FontSize', 12);
title('S11: Measured vs Ideal', 'FontSize', 13, 'FontWeight', 'bold');
legend('Measured', 'Ideal Target', '3.5 GHz', 'Location', 'best', 'FontSize', 10);
ylim([-30 0]);

% Subplot 2: S21 Comparison
subplot(1, 2, 2);
plot(frequency/1e9, S21_mag_dB, 'r-', 'LineWidth', 2.5);
hold on;
plot(frequency/1e9, S21_ideal, 'g--', 'LineWidth', 2);
xline(f_operating/1e9, 'b--', 'LineWidth', 1.5);
hold off;
grid on;
xlabel('Frequency (GHz)', 'FontSize', 12);
ylabel('S21 (dB)', 'FontSize', 12);
title('S21: Measured vs Ideal', 'FontSize', 13, 'FontWeight', 'bold');
legend('Measured', 'Ideal Target', '3.5 GHz', 'Location', 'best', 'FontSize', 10);
ylim([-10 0]);

sgtitle('O-RIS Performance vs Target Specifications', 'FontSize', 14, 'FontWeight', 'bold');
print('-dpng', '-r300', 'oris_s_parameters_comparison.png');
fprintf('Comparison plots saved (300 DPI)\n');

%% Bandwidth Analysis
fprintf('\nPerforming bandwidth analysis...\n');

% Find -3dB bandwidth for S21
S21_max = max(S21_mag_dB);
S21_3dB_level = S21_max - 3;
idx_3dB = find(S21_mag_dB >= S21_3dB_level);

if ~isempty(idx_3dB)
    bandwidth = frequency(idx_3dB(end)) - frequency(idx_3dB(1));
    bw_percent = 100 * bandwidth / f_operating;
    
    fprintf('3-dB Bandwidth: %.2f MHz (%.1f%% fractional)\n', ...
        bandwidth/1e6, bw_percent);
else
    fprintf('Could not determine 3-dB bandwidth\n');
end

%% Export Data for Presentation (Day 15)
fprintf('\nExporting presentation-ready graphics...\n');

% Create simplified single-plot versions for slides
% Figure 1: S11 only
figure('Position', [100, 100, 800, 500]);
plot(frequency/1e9, S11_mag_dB, 'b-', 'LineWidth', 3);
hold on;
xline(f_operating/1e9, 'r--', 'LineWidth', 2.5, 'Label', 'Operating: 3.5 GHz', ...
    'LabelOrientation', 'horizontal', 'FontSize', 11);
yline(-10, 'g--', 'LineWidth', 2, 'Label', 'Target: -10 dB');
hold off;
grid on;
xlabel('Frequency (GHz)', 'FontSize', 14, 'FontWeight', 'bold');
ylabel('S11 (dB)', 'FontSize', 14, 'FontWeight', 'bold');
title('O-RIS Reflection Coefficient', 'FontSize', 16, 'FontWeight', 'bold');
set(gca, 'FontSize', 12);
print('-dpng', '-r300', 'oris_S11_presentation.png');

% Figure 2: Phase Shift Capability only
figure('Position', [100, 100, 800, 500]);
plot(frequency/1e9, phase_shift_capability, 'Color', [0.4 0.2 0.6], 'LineWidth', 3);
hold on;
xline(f_operating/1e9, 'r--', 'LineWidth', 2.5, 'Label', 'Operating: 3.5 GHz', ...
    'LabelOrientation', 'horizontal', 'FontSize', 11);
fill([2 5 5 2], [160 160 180 180], 'g', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
text(3.5, 170, 'Target Range', 'FontSize', 12, 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center');
hold off;
grid on;
xlabel('Frequency (GHz)', 'FontSize', 14, 'FontWeight', 'bold');
ylabel('Phase Shift Capability (degrees)', 'FontSize', 14, 'FontWeight', 'bold');
title('O-RIS Phase Shift Performance', 'FontSize', 16, 'FontWeight', 'bold');
set(gca, 'FontSize', 12);
ylim([120 200]);
print('-dpng', '-r300', 'oris_phase_shift_presentation.png');

fprintf('Presentation graphics exported!\n');

%% Save Processed Data
save('oris_s_parameters_processed.mat', 'frequency', 'S11_mag_dB', 'S11_phase_deg', ...
    'S21_mag_dB', 'S21_phase_deg', 'phase_shift_capability', 'f_operating');

fprintf('\n✓ S-parameter processing complete!\n');
fprintf('Files saved:\n');
fprintf('  - oris_s_parameters_full_analysis.png (300 DPI)\n');
fprintf('  - oris_s_parameters_comparison.png (300 DPI)\n');
fprintf('  - oris_S11_presentation.png (300 DPI)\n');
fprintf('  - oris_phase_shift_presentation.png (300 DPI)\n');
fprintf('  - oris_s_parameters_processed.mat\n');
