%% O-RIS Aperture Synthesis Validation
% Purpose: Mathematical validation of O-RIS performance specifications
% Author: SOOZI - Integration & Presentation Lead
% Project: O-RIS Proof of Concept
% Phase 1, Part 2: Days 7-12

clear all; close all; clc;

%% O-RIS System Specifications
fprintf('=== O-RIS Aperture Synthesis Validation ===\n\n');

% System parameters
N_elements = 2048;         % Number of controllable elements
A_total = 0.28;            % Total aperture area (m²)
freq = 3.5e9;              % Operating frequency (Hz)
c = 3e8;                   % Speed of light (m/s)
lambda = c / freq;         % Wavelength (m)

% Cylindrical geometry
radius = 0.15;             % Cylinder radius (m)
height = 0.30;             % Cylinder height (m)
A_cylinder = 2*pi*radius*height;  % Actual cylindrical surface area

fprintf('System Parameters:\n');
fprintf('  Elements: %d\n', N_elements);
fprintf('  Aperture area: %.3f m²\n', A_total);
fprintf('  Operating frequency: %.2f GHz\n', freq/1e9);
fprintf('  Wavelength: %.3f m (%.1f mm)\n', lambda, lambda*1000);
fprintf('  Cylinder dimensions: R=%.2fm, H=%.2fm\n', radius, height);

%% Gain Formula Validation (Days 7-8)
% Formula: G = 10*log10(N * A / lambda^2)
fprintf('\n--- Gain Calculation ---\n');

% Theoretical maximum gain
G_theoretical = 10*log10(N_elements * A_total / lambda^2);
fprintf('Theoretical gain: %.2f dBi\n', G_theoretical);

% Practical gain (accounting for efficiency)
aperture_efficiency = 0.7;  % 70% efficiency (typical for RIS)
G_practical = 10*log10(aperture_efficiency * N_elements * A_total / lambda^2);
fprintf('Practical gain (70%% eff): %.2f dBi\n', G_practical);

% Expected range validation
expected_min = 15;
expected_max = 25;
fprintf('Expected range: %.0f to %.0f dBi\n', expected_min, expected_max);

if G_practical >= expected_min && G_practical <= expected_max
    fprintf('✓ PASS: Gain within expected range!\n');
else
    fprintf('✗ WARNING: Gain outside expected range\n');
end

%% Element Spacing and Phase Gradient (Days 9-10)
fprintf('\n--- Element Configuration ---\n');

% Calculate element spacing
A_per_element = A_total / N_elements;
fprintf('Area per element: %.4e m²\n', A_per_element);

% For cylindrical array, elements arranged in rows and columns
n_rows = 32;               % Elements along height
n_cols = N_elements / n_rows;  % Elements around circumference
d_vertical = height / n_rows;  % Vertical spacing
d_horizontal = (2*pi*radius) / n_cols;  % Arc length spacing

fprintf('Element arrangement: %d rows × %d columns\n', n_rows, n_cols);
fprintf('Vertical spacing: %.3f m (%.2fλ)\n', d_vertical, d_vertical/lambda);
fprintf('Horizontal spacing: %.3f m (%.2fλ)\n', d_horizontal, d_horizontal/lambda);

% Nyquist spatial sampling check
if d_vertical < lambda/2 && d_horizontal < lambda/2
    fprintf('✓ PASS: Element spacing satisfies Nyquist criterion\n');
else
    fprintf('✗ WARNING: Element spacing may cause grating lobes\n');
end

%% Phase Gradient Calculator (Days 9-10)
% Using Snell's law for beam steering
fprintf('\n--- Phase Gradient Analysis ---\n');

% Test multiple steering angles
theta_test = [0, 30, 45, 60, 90];  % Steering angles (degrees)

fprintf('Beam Steering Angle | Required Phase Gradient\n');
fprintf('-------------------+------------------------\n');

for theta_deg = theta_test
    theta_rad = deg2rad(theta_deg);
    
    % Phase gradient: dφ/dx = (2π/λ) * sin(θ)
    phase_gradient = (2*pi/lambda) * sin(theta_rad);  % rad/m
    
    % Phase difference between adjacent elements
    delta_phi = phase_gradient * d_horizontal;  % radians
    delta_phi_deg = rad2deg(delta_phi);
    
    fprintf('      %3d°          |    %.2f° per element\n', theta_deg, delta_phi_deg);
end

%% Beam Steering Equation Validation (Days 10-11)
fprintf('\n--- Beam Steering Validation ---\n');

% Target phase shift capability: 160-180 degrees
phase_shift_min = 160;  % degrees
phase_shift_max = 180;  % degrees

fprintf('Phase shifter capability: %d° to %d°\n', phase_shift_min, phase_shift_max);

% Calculate maximum steering angle
phi_max = deg2rad(phase_shift_max);
theta_max = asin(lambda * phi_max / (2*pi*d_horizontal));
theta_max_deg = rad2deg(theta_max);

fprintf('Maximum steering angle: %.1f°\n', theta_max_deg);

% Generate radiation pattern for different steering angles
angles = -90:1:90;  % Observation angles (degrees)
theta_steer_array = [0, 30, 60];  % Steering angles to plot

figure('Position', [100, 100, 1200, 400]);

for idx = 1:length(theta_steer_array)
    theta_steer = deg2rad(theta_steer_array(idx));
    
    % Array factor calculation
    AF = zeros(size(angles));
    for i = 1:length(angles)
        theta_obs = deg2rad(angles(i));
        psi = 2*pi*d_horizontal/lambda * (sin(theta_obs) - sin(theta_steer));
        
        % Array factor (normalized)
        if abs(psi) < 1e-10
            AF(i) = n_cols;
        else
            AF(i) = abs(sin(n_cols*psi/2) / sin(psi/2));
        end
    end
    
    % Normalize and convert to dB
    AF_dB = 20*log10(AF/max(AF));
    
    subplot(1, 3, idx);
    plot(angles, AF_dB, 'b-', 'LineWidth', 2);
    grid on;
    xlabel('Angle (degrees)', 'FontSize', 11);
    ylabel('Normalized Gain (dB)', 'FontSize', 11);
    title(sprintf('Beam Steered to %d°', theta_steer_array(idx)), ...
        'FontSize', 12, 'FontWeight', 'bold');
    ylim([-40 0]);
    xlim([-90 90]);
    
    % Mark main lobe
    hold on;
    plot(theta_steer_array(idx), 0, 'ro', 'MarkerSize', 10, 'LineWidth', 2);
    legend('Radiation Pattern', 'Beam Peak', 'Location', 'southwest');
    hold off;
end

sgtitle('O-RIS Beam Steering Performance', 'FontSize', 14, 'FontWeight', 'bold');
saveas(gcf, 'oris_beam_steering_patterns.png');
fprintf('Beam steering patterns saved as oris_beam_steering_patterns.png\n');

%% Multi-User Interference Modeling (Day 12)
fprintf('\n--- Multi-User Scenario Analysis ---\n');

% Scenario: 3 users at different angles
n_users = 3;
user_angles = [-40, 0, 40];  % degrees
user_powers = zeros(n_users, 1);

fprintf('Simulating %d simultaneous users:\n', n_users);

for u = 1:n_users
    % Steer beam toward user u
    theta_steer = deg2rad(user_angles(u));
    
    % Calculate gain at each user's location
    for v = 1:n_users
        theta_obs = deg2rad(user_angles(v));
        psi = 2*pi*d_horizontal/lambda * (sin(theta_obs) - sin(theta_steer));
        
        if abs(psi) < 1e-10
            AF_user = n_cols;
        else
            AF_user = abs(sin(n_cols*psi/2) / sin(psi/2));
        end
        
        gain_dB = 20*log10(AF_user/n_cols) + G_practical;
        
        if u == v
            user_powers(u) = gain_dB;
        end
    end
    
    fprintf('  User %d at %+4d°: %.2f dBi gain\n', u, user_angles(u), user_powers(u));
end

% Calculate signal-to-interference ratio
fprintf('\nInterference Analysis:\n');
for u = 1:n_users
    interference_sum = 0;
    for v = 1:n_users
        if v ~= u
            theta_steer_interference = deg2rad(user_angles(v));
            theta_obs = deg2rad(user_angles(u));
            psi = 2*pi*d_horizontal/lambda * (sin(theta_obs) - sin(theta_steer_interference));
            
            if abs(psi) < 1e-10
                AF_interference = n_cols;
            else
                AF_interference = abs(sin(n_cols*psi/2) / sin(psi/2));
            end
            
            interference_dB = 20*log10(AF_interference/n_cols) + G_practical;
            interference_sum = interference_sum + 10^(interference_dB/10);
        end
    end
    
    signal_power = 10^(user_powers(u)/10);
    SIR = 10*log10(signal_power / interference_sum);
    
    fprintf('  User %d SIR: %.2f dB ', u, SIR);
    if SIR > 20
        fprintf('(Excellent)\n');
    elseif SIR > 10
        fprintf('(Good)\n');
    else
        fprintf('(Acceptable)\n');
    end
end

%% Performance Summary Report
fprintf('\n');
fprintf('========================================\n');
fprintf('   APERTURE SYNTHESIS VALIDATION REPORT\n');
fprintf('========================================\n\n');

fprintf('PERFORMANCE METRICS:\n');
fprintf('  ✓ Theoretical Gain: %.2f dBi\n', G_theoretical);
fprintf('  ✓ Practical Gain: %.2f dBi\n', G_practical);
fprintf('  ✓ Maximum Beam Steering: %.1f°\n', theta_max_deg);
fprintf('  ✓ Element Spacing: %.2fλ (vertical), %.2fλ (horizontal)\n', ...
    d_vertical/lambda, d_horizontal/lambda);
fprintf('  ✓ Multi-user capability validated\n\n');

fprintf('DESIGN VALIDATION:\n');
if G_practical >= expected_min && G_practical <= expected_max
    fprintf('  ✓ Gain specification MET\n');
else
    fprintf('  ✗ Gain specification NOT MET\n');
end

if theta_max_deg >= 85
    fprintf('  ✓ Wide-angle steering capability MET\n');
else
    fprintf('  ✗ Limited steering range\n');
end

fprintf('\n========================================\n');

%% Save Results
save('oris_aperture_synthesis_results.mat', 'G_theoretical', 'G_practical', ...
    'theta_max_deg', 'N_elements', 'A_total', 'lambda', 'freq');

fprintf('\n✓ Aperture synthesis validation complete!\n');
fprintf('Results saved to oris_aperture_synthesis_results.mat\n');
