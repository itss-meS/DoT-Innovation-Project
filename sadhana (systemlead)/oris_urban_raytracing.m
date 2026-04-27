%% O-RIS Urban Ray-Tracing Simulation
% Purpose: Model RF signal propagation in urban environments
% Author: SOOZI - Integration & Presentation Lead
% Project: O-RIS Proof of Concept
% Phase 1, Part 1: Days 1-6

clear all; close all; clc;

%% System Parameters
freq = 3.5e9;              % Operating frequency: 3.5 GHz
c = 3e8;                   % Speed of light (m/s)
lambda = c / freq;         % Wavelength (m)
tx_power = 30;             % Transmit power (dBm)
tx_gain = 5;               % Transmitter antenna gain (dBi)
rx_gain = 0;               % Receiver antenna gain (dBi)

%% Urban Environment Setup
% Create 3D urban canyon model with buildings
area_size = 500;           % Simulation area: 500m x 500m
num_buildings = 15;        % Number of buildings
building_heights = 20 + 30*rand(num_buildings, 1); % Random heights 20-50m

% Generate random building positions
building_positions = area_size * rand(num_buildings, 2);
building_width = 30 + 20*rand(num_buildings, 1);  % Building widths 30-50m

% Transmitter position (O-RIS location)
tx_pos = [area_size/2, area_size/2, 15]; % Center of area, 15m height

% Create receiver grid for coverage map
grid_resolution = 2;       % 2m resolution
[X, Y] = meshgrid(0:grid_resolution:area_size, 0:grid_resolution:area_size);
Z = 1.5 * ones(size(X));   % Receiver height: 1.5m (pedestrian level)

%% Friis Transmission Equation Implementation
% Calculate free-space path loss
fprintf('Calculating RF propagation using Friis equation...\n');

% Initialize received signal strength matrix
RSSI = zeros(size(X));

% For each receiver location
for i = 1:size(X, 1)
    for j = 1:size(X, 2)
        rx_pos = [X(i,j), Y(i,j), Z(i,j)];
        
        % Calculate direct path distance
        distance = norm(rx_pos - tx_pos);
        
        % Skip if too close (avoid singularity)
        if distance < 1
            RSSI(i,j) = tx_power;
            continue;
        end
        
        % Friis free-space path loss (dB)
        % L = 20*log10(d) + 20*log10(f) + 20*log10(4*pi/c)
        fspl = 20*log10(distance) + 20*log10(freq) + 20*log10(4*pi/c);
        
        % Check for Line-of-Sight (LOS)
        has_los = check_los(tx_pos, rx_pos, building_positions, building_width, building_heights);
        
        if has_los
            % Direct path only
            RSSI(i,j) = tx_power + tx_gain + rx_gain - fspl;
        else
            % Calculate multipath reflections
            reflection_power = calculate_reflections(tx_pos, rx_pos, ...
                building_positions, building_width, building_heights, ...
                tx_power, tx_gain, rx_gain, freq);
            RSSI(i,j) = reflection_power;
        end
    end
    
    % Progress indicator
    if mod(i, 20) == 0
        fprintf('Progress: %.1f%%\n', 100*i/size(X,1));
    end
end

%% Coverage Map Visualization
fprintf('Generating coverage maps...\n');

figure('Position', [100, 100, 1200, 500]);

% Subplot 1: 2D Coverage Heat Map
subplot(1, 2, 1);
imagesc([0 area_size], [0 area_size], RSSI);
set(gca, 'YDir', 'normal');
colorbar;
colormap('jet');
caxis([-100 -40]);
hold on;

% Plot buildings
for b = 1:num_buildings
    rectangle('Position', [building_positions(b,1) - building_width(b)/2, ...
                          building_positions(b,2) - building_width(b)/2, ...
                          building_width(b), building_width(b)], ...
             'FaceColor', [0.3 0.3 0.3], 'EdgeColor', 'k', 'LineWidth', 1.5);
end

% Plot transmitter
plot(tx_pos(1), tx_pos(2), 'r^', 'MarkerSize', 15, 'MarkerFaceColor', 'r');
text(tx_pos(1)+10, tx_pos(2)+10, 'O-RIS TX', 'Color', 'white', ...
    'FontWeight', 'bold', 'FontSize', 10);

xlabel('X Distance (m)', 'FontSize', 12);
ylabel('Y Distance (m)', 'FontSize', 12);
title('O-RIS Coverage Map - Urban Environment', 'FontSize', 14, 'FontWeight', 'bold');
grid on;
hold off;

% Subplot 2: 3D Coverage Visualization
subplot(1, 2, 2);
surf(X, Y, RSSI, 'EdgeColor', 'none');
hold on;

% Plot buildings in 3D
for b = 1:num_buildings
    x_corners = building_positions(b,1) + building_width(b)/2 * [-1 1 1 -1 -1];
    y_corners = building_positions(b,2) + building_width(b)/2 * [-1 -1 1 1 -1];
    z_base = zeros(1, 5);
    z_top = building_heights(b) * ones(1, 5);
    
    % Draw building walls
    fill3(x_corners, y_corners, z_base, [0.5 0.5 0.5], 'EdgeColor', 'k');
    fill3(x_corners, y_corners, z_top, [0.4 0.4 0.4], 'EdgeColor', 'k');
end

plot3(tx_pos(1), tx_pos(2), tx_pos(3), 'r^', 'MarkerSize', 15, 'MarkerFaceColor', 'r');

xlabel('X Distance (m)', 'FontSize', 12);
ylabel('Y Distance (m)', 'FontSize', 12);
zlabel('RSSI (dBm)', 'FontSize', 12);
title('3D Coverage Visualization', 'FontSize', 14, 'FontWeight', 'bold');
colorbar;
colormap('jet');
view(45, 30);
grid on;
hold off;

%% Performance Statistics
fprintf('\n=== Coverage Analysis ===\n');
fprintf('Total area: %.0f m²\n', area_size^2);
fprintf('Mean RSSI: %.2f dBm\n', mean(RSSI(:)));
fprintf('Max RSSI: %.2f dBm\n', max(RSSI(:)));
fprintf('Min RSSI: %.2f dBm\n', min(RSSI(:)));

% Coverage quality metrics
good_coverage = RSSI > -70;  % RSSI > -70 dBm considered good
coverage_percent = 100 * sum(good_coverage(:)) / numel(RSSI);
fprintf('Good coverage (>-70 dBm): %.1f%%\n', coverage_percent);

dead_zones = RSSI < -90;     % RSSI < -90 dBm considered dead zone
dead_zone_percent = 100 * sum(dead_zones(:)) / numel(RSSI);
fprintf('Dead zones (<-90 dBm): %.1f%%\n', dead_zone_percent);

%% Save Results
fprintf('\nSaving results...\n');
save('oris_coverage_results.mat', 'RSSI', 'X', 'Y', 'building_positions', ...
    'building_width', 'building_heights', 'tx_pos', 'freq');

% Export high-resolution figure
saveas(gcf, 'oris_urban_coverage_map.png');
fprintf('Coverage map saved as oris_urban_coverage_map.png\n');

fprintf('\n✓ Ray-tracing simulation complete!\n');

%% Helper Functions

function has_los = check_los(tx_pos, rx_pos, building_pos, building_width, building_heights)
    % Check if there's Line-of-Sight between transmitter and receiver
    has_los = true;
    
    % Create ray from TX to RX
    ray_vec = rx_pos - tx_pos;
    ray_length = norm(ray_vec);
    ray_dir = ray_vec / ray_length;
    
    % Check intersection with each building
    for b = 1:length(building_heights)
        % Building boundaries
        x_min = building_pos(b, 1) - building_width(b)/2;
        x_max = building_pos(b, 1) + building_width(b)/2;
        y_min = building_pos(b, 2) - building_width(b)/2;
        y_max = building_pos(b, 2) + building_width(b)/2;
        z_max = building_heights(b);
        
        % Ray-box intersection test (simplified)
        % Check if ray passes through building volume
        t_min = -inf;
        t_max = inf;
        
        for dim = 1:3
            if abs(ray_dir(dim)) > 1e-6
                if dim == 1  % X dimension
                    t1 = (x_min - tx_pos(dim)) / ray_dir(dim);
                    t2 = (x_max - tx_pos(dim)) / ray_dir(dim);
                elseif dim == 2  % Y dimension
                    t1 = (y_min - tx_pos(dim)) / ray_dir(dim);
                    t2 = (y_max - tx_pos(dim)) / ray_dir(dim);
                else  % Z dimension
                    t1 = (0 - tx_pos(dim)) / ray_dir(dim);
                    t2 = (z_max - tx_pos(dim)) / ray_dir(dim);
                end
                
                if t1 > t2
                    temp = t1; t1 = t2; t2 = temp;
                end
                
                t_min = max(t_min, t1);
                t_max = min(t_max, t2);
            end
        end
        
        % If intersection exists and is between TX and RX
        if t_min <= t_max && t_min < ray_length && t_max > 0
            has_los = false;
            return;
        end
    end
end

function power = calculate_reflections(tx_pos, rx_pos, building_pos, building_width, building_heights, tx_power, tx_gain, rx_gain, freq)
    % Calculate received power from multipath reflections
    % Simplified: consider first-order reflections from building walls
    
    c = 3e8;
    reflection_coeff = 0.7;  % Wall reflection coefficient
    max_reflections = 5;     % Limit number of reflections to consider
    
    total_power_linear = 0;
    
    % For each building, check potential reflection points
    for b = 1:min(max_reflections, length(building_heights))
        % Consider 4 walls of each building as potential reflectors
        walls = [
            building_pos(b,1) - building_width(b)/2, building_pos(b,2), building_heights(b)/2;  % Left wall
            building_pos(b,1) + building_width(b)/2, building_pos(b,2), building_heights(b)/2;  % Right wall
            building_pos(b,1), building_pos(b,2) - building_width(b)/2, building_heights(b)/2;  % Front wall
            building_pos(b,1), building_pos(b,2) + building_width(b)/2, building_heights(b)/2   % Back wall
        ];
        
        for w = 1:size(walls, 1)
            reflection_point = walls(w, :);
            
            % Calculate path: TX -> reflection -> RX
            d1 = norm(reflection_point - tx_pos);
            d2 = norm(rx_pos - reflection_point);
            total_distance = d1 + d2;
            
            % Path loss for reflected path
            fspl = 20*log10(total_distance) + 20*log10(freq) + 20*log10(4*pi/c);
            reflection_loss = 20*log10(reflection_coeff);
            
            % Received power for this path (dBm)
            path_power_db = tx_power + tx_gain + rx_gain - fspl + reflection_loss;
            
            % Convert to linear and accumulate
            path_power_linear = 10^(path_power_db/10);
            total_power_linear = total_power_linear + path_power_linear;
        end
    end
    
    % Convert back to dBm
    if total_power_linear > 0
        power = 10*log10(total_power_linear);
    else
        power = -120;  % Very weak signal
    end
end
