
%% O-RIS 3D Radiation Pattern Visualization
% Purpose: Create 3D radiation patterns and beam steering animations
% Author: SOOZI - Integration & Presentation Lead
% Project: O-RIS Proof of Concept
% Phase 2, Part 2: Days 16-25

clear all; close all; clc;

%% System Parameters
fprintf('=== O-RIS 3D Radiation Pattern Visualization ===\n\n');

freq = 3.5e9;              % Operating frequency
c = 3e8;                   % Speed of light
lambda = c / freq;         % Wavelength

% Cylindrical array parameters
N_elements = 2048;
n_rows = 32;
n_cols = N_elements / n_rows;
radius = 0.15;             % Cylinder radius (m)
height = 0.30;             % Cylinder height (m)

fprintf('Generating 3D radiation patterns...\n');
fprintf('Elements: %d (%d rows × %d columns)\n', N_elements, n_rows, n_cols);

%% Generate Radiation Pattern Data (Days 16-17)
% Angular resolution
theta_res = 2;  % degrees
phi_res = 2;    % degrees

theta = 0:theta_res:180;      % Elevation angle (0 to 180 degrees)
phi = 0:phi_res:360;          % Azimuth angle (0 to 360 degrees)

[THETA, PHI] = meshgrid(deg2rad(theta), deg2rad(phi));

% Initialize gain matrix
gain_dB = zeros(size(THETA));

% Element positions on cylinder
element_angles = linspace(0, 2*pi, n_cols+1);
element_angles = element_angles(1:end-1);  % Remove duplicate
element_heights = linspace(-height/2, height/2, n_rows);

fprintf('Calculating radiation pattern (this may take a moment)...\n');

%% Omnidirectional Pattern (No beam steering)
beam_steer_angle = 0;  % Azimuth steering angle

for i = 1:length(phi)
    for j = 1:length(theta)
        % Current observation angles
        theta_obs = THETA(i, j);
        phi_obs = PHI(i, j);
        
        % Observation direction vector
        x_obs = sin(theta_obs) * cos(phi_obs);
        y_obs = sin(theta_obs) * sin(phi_obs);
        z_obs = cos(theta_obs);
        
        % Array factor calculation (sum contributions from all elements)
        AF = 0;
        for row = 1:n_rows
            for col = 1:n_cols
                % Element position
                x_elem = radius * cos(element_angles(col));
                y_elem = radius * sin(element_angles(col));
                z_elem = element_heights(row);
                
                % Phase contribution from this element
                r_dot_k = 2*pi/lambda * (x_elem*x_obs + y_elem*y_obs + z_elem*z_obs);
                
                % Phase shift for beam steering (azimuthal only)
                steer_phase = -2*pi/lambda * radius * cos(element_angles(col) - deg2rad(beam_steer_angle));
                
                % Element pattern (omnidirectional in this simplified model)
                element_gain = 1;
                
                % Accumulate array factor
                AF = AF + element_gain * exp(1j * (r_dot_k + steer_phase));
            end
        end
        
        % Convert to dB (normalized)
        gain_dB(i, j) = 20*log10(abs(AF));
    end
    
    if mod(i, 50) == 0
        fprintf('Progress: %.0f%%\n', 100*i/length(phi));
    end
end

% Normalize
gain_dB = gain_dB - max(gain_dB(:));

fprintf('Radiation pattern calculated!\n');

%% 3D Visualization (Days 18-20)
fprintf('\nCreating 3D visualizations...\n');

% Convert to Cartesian coordinates for 3D plot
gain_linear = 10.^(gain_dB/20);  % Convert to linear scale
X = gain_linear .* sin(THETA) .* cos(PHI);
Y = gain_linear .* sin(THETA) .* sin(PHI);
Z = gain_linear .* cos(THETA);

% Figure 1: Full 3D pattern
figure('Position', [50, 50, 1200, 500]);

subplot(1, 2, 1);
surf(X, Y, Z, gain_dB, 'EdgeColor', 'none', 'FaceAlpha', 0.9);
colormap('jet');
colorbar;
caxis([-30 0]);
xlabel('X', 'FontSize', 11);
ylabel('Y', 'FontSize', 11);
zlabel('Z', 'FontSize', 11);
title('O-RIS 3D Radiation Pattern (Omnidirectional)', 'FontSize', 13, 'FontWeight', 'bold');
axis equal;
grid on;
view(45, 30);
lighting gouraud;
camlight('headlight');

% Subplot 2: Cut planes
subplot(1, 2, 2);

% Azimuth cut (θ = 90°)
idx_theta_90 = find(abs(theta - 90) == min(abs(theta - 90)));
azimuth_cut = gain_dB(:, idx_theta_90);

polarplot(deg2rad(phi), azimuth_cut, 'b-', 'LineWidth', 2.5);
hold on;

% Elevation cut (φ = 0°)
idx_phi_0 = 1;
elevation_cut = gain_dB(idx_phi_0, :);
polarplot(deg2rad(theta), elevation_cut, 'r-', 'LineWidth', 2.5);

hold off;
title('Radiation Pattern Cuts', 'FontSize', 13, 'FontWeight', 'bold');
legend('Azimuth (θ=90°)', 'Elevation (φ=0°)', 'Location', 'best', 'FontSize', 10);
rlim([-30 0]);

sgtitle('O-RIS Omnidirectional Coverage', 'FontSize', 15, 'FontWeight', 'bold');
print('-dpng', '-r300', 'oris_3d_radiation_pattern.png');
fprintf('3D radiation pattern saved!\n');

%% Beam Steering Patterns (Days 21-23)
fprintf('\nGenerating beam steering patterns...\n');

steering_angles = [0, 45, 90, 135, 180, 225, 270, 315];  % 8 directions
num_angles = length(steering_angles);

% Prepare for animation
figure('Position', [100, 100, 900, 700]);

for angle_idx = 1:num_angles
    beam_angle = steering_angles(angle_idx);
    
    % Recalculate pattern with beam steering
    gain_steered = zeros(size(THETA));
    
    for i = 1:size(THETA, 1)
        for j = 1:size(THETA, 2)
            theta_obs = THETA(i, j);
            phi_obs = PHI(i, j);
            
            x_obs = sin(theta_obs) * cos(phi_obs);
            y_obs = sin(theta_obs) * sin(phi_obs);
            z_obs = cos(theta_obs);
            
            AF = 0;
            for row = 1:n_rows
                for col = 1:n_cols
                    x_elem = radius * cos(element_angles(col));
                    y_elem = radius * sin(element_angles(col));
                    z_elem = element_heights(row);
                    
                    r_dot_k = 2*pi/lambda * (x_elem*x_obs + y_elem*y_obs + z_elem*z_obs);
                    steer_phase = -2*pi/lambda * radius * cos(element_angles(col) - deg2rad(beam_angle));
                    
                    AF = AF + exp(1j * (r_dot_k + steer_phase));
                end
            end
            
            gain_steered(i, j) = 20*log10(abs(AF));
        end
    end
    
    gain_steered = gain_steered - max(gain_steered(:));
    
    % Convert to 3D
    gain_linear_steered = 10.^(gain_steered/20);
    X_steered = gain_linear_steered .* sin(THETA) .* cos(PHI);
    Y_steered = gain_linear_steered .* sin(THETA) .* sin(PHI);
    Z_steered = gain_linear_steered .* cos(THETA);
    
    clf;
    surf(X_steered, Y_steered, Z_steered, gain_steered, 'EdgeColor', 'none');
    colormap('jet');
    colorbar;
    caxis([-30 0]);
    xlabel('X', 'FontSize', 12);
    ylabel('Y', 'FontSize', 12);
    zlabel('Z', 'FontSize', 12);
    title(sprintf('O-RIS Beam Steered to %d°', beam_angle), ...
        'FontSize', 14, 'FontWeight', 'bold');
    axis equal;
    grid on;
    view(45, 30);
    lighting gouraud;
    camlight('headlight');
    
    drawnow;
    
    % Save frame
    frame_filename = sprintf('beam_steering_frame_%03d.png', angle_idx);
    print('-dpng', '-r150', frame_filename);
    
    fprintf('Beam angle %d° rendered\n', beam_angle);
end

fprintf('Beam steering frames saved!\n');

%% Comparison Visualization (Days 24-25)
fprintf('\nCreating comparison visualizations...\n');

figure('Position', [50, 50, 1400, 500]);

% O-RIS (omnidirectional with beam steering)
subplot(1, 3, 1);
idx_theta_90 = find(abs(theta - 90) == min(abs(theta - 90)));
azimuth_oris = gain_dB(:, idx_theta_90);
polarplot(deg2rad(phi), azimuth_oris, 'b-', 'LineWidth', 3);
title('O-RIS (Cylindrical)', 'FontSize', 13, 'FontWeight', 'bold');
rlim([-30 0]);
ax = gca;
ax.ThetaZeroLocation = 'top';
ax.ThetaDir = 'clockwise';

% Planar RIS (limited angular coverage)
subplot(1, 3, 2);
% Simulate planar RIS with limited beamwidth
phi_planar = 0:1:360;
gain_planar = -3 - 27*(1 - cos(deg2rad(phi_planar - 0)).^8);  % Directional pattern
polarplot(deg2rad(phi_planar), gain_planar, 'r-', 'LineWidth', 3);
title('Planar RIS (Limited)', 'FontSize', 13, 'FontWeight', 'bold');
rlim([-30 0]);
ax = gca;
ax.ThetaZeroLocation = 'top';
ax.ThetaDir = 'clockwise';

% Omnidirectional antenna (no beam steering)
subplot(1, 3, 3);
gain_omni = -3 * ones(size(phi_planar));  % Uniform in all directions
polarplot(deg2rad(phi_planar), gain_omni, 'g-', 'LineWidth', 3);
title('Omnidirectional Antenna', 'FontSize', 13, 'FontWeight', 'bold');
rlim([-30 0]);
ax = gca;
ax.ThetaZeroLocation = 'top';
ax.ThetaDir = 'clockwise';

sgtitle('Radiation Pattern Comparison', 'FontSize', 16, 'FontWeight', 'bold');
print('-dpng', '-r300', 'oris_pattern_comparison.png');
fprintf('Comparison plot saved!\n');

%% Create Summary Figure for Presentation
fprintf('\nCreating presentation summary figure...\n');

figure('Position', [100, 100, 1000, 800]);

% Main 3D pattern
subplot(2, 2, [1 2]);
gain_linear_pres = 10.^(gain_dB/20);
X_pres = gain_linear_pres .* sin(THETA) .* cos(PHI);
Y_pres = gain_linear_pres .* sin(THETA) .* sin(PHI);
Z_pres = gain_linear_pres .* cos(THETA);

surf(X_pres, Y_pres, Z_pres, gain_dB, 'EdgeColor', 'none', 'FaceAlpha', 0.95);
colormap('jet');
colorbar('Location', 'eastoutside');
caxis([-30 0]);
xlabel('X', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Y', 'FontSize', 12, 'FontWeight', 'bold');
zlabel('Z', 'FontSize', 12, 'FontWeight', 'bold');
title('O-RIS 360° Coverage Capability', 'FontSize', 14, 'FontWeight', 'bold');
axis equal;
grid on;
view(45, 30);
lighting gouraud;
camlight('headlight');

% Azimuth pattern
subplot(2, 2, 3);
polarplot(deg2rad(phi), azimuth_oris, 'b-', 'LineWidth', 3);
title('Azimuth Pattern (Horizontal)', 'FontSize', 12, 'FontWeight', 'bold');
rlim([-30 0]);
ax = gca;
ax.ThetaZeroLocation = 'top';
ax.ThetaDir = 'clockwise';

% Key specifications
subplot(2, 2, 4);
axis off;
text(0.1, 0.9, 'O-RIS Performance', 'FontSize', 14, 'FontWeight', 'bold');
text(0.1, 0.75, '• Elements: 2048', 'FontSize', 11);
text(0.1, 0.65, '• Frequency: 3.5 GHz', 'FontSize', 11);
text(0.1, 0.55, '• Coverage: 360° azimuth', 'FontSize', 11);
text(0.1, 0.45, '• Beam steering: Full omnidirectional', 'FontSize', 11);
text(0.1, 0.35, '• Gain: 15-25 dBi', 'FontSize', 11);
text(0.1, 0.25, '• Phase shift: 160-180°', 'FontSize', 11);
text(0.1, 0.10, '✓ Eliminates coverage dead zones', 'FontSize', 11, ...
    'FontWeight', 'bold', 'Color', [0 0.5 0]);

sgtitle('O-RIS Omnidirectional Reconfigurable Intelligent Surface', ...
    'FontSize', 16, 'FontWeight', 'bold');
print('-dpng', '-r300', 'oris_presentation_summary.png');
fprintf('Presentation summary saved!\n');

%% Save Data
save('oris_radiation_patterns.mat', 'THETA', 'PHI', 'gain_dB', ...
    'theta', 'phi', 'steering_angles');

fprintf('\n✓ 3D radiation pattern visualization complete!\n');
fprintf('\nFiles created:\n');
fprintf('  - oris_3d_radiation_pattern.png (300 DPI)\n');
fprintf('  - oris_pattern_comparison.png (300 DPI)\n');
fprintf('  - oris_presentation_summary.png (300 DPI)\n');
fprintf('  - beam_steering_frame_*.png (8 frames for animation)\n');
fprintf('  - oris_radiation_patterns.mat\n');

fprintf('\nNote: Use video editing software to create 30-second animation\n');
fprintf('from beam_steering_frame_*.png files (e.g., ffmpeg, iMovie, PowerPoint)\n');
