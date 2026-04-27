%% O-RIS Master System Integration and Orchestration
% Purpose: Integrate all subsystems into unified demonstration
% Author: SOOZI - Integration & Presentation Lead
% Project: O-RIS Proof of Concept
% Phase 3: System Integration (Days 15-35)

clear all; close all; clc;

%% Initialization
fprintf('========================================\n');
fprintf('  O-RIS SYSTEM INTEGRATION FRAMEWORK\n');
fprintf('========================================\n\n');

% Create log file
log_filename = sprintf('oris_integration_log_%s.txt', datestr(now, 'yyyymmdd_HHMMSS'));
log_fid = fopen(log_filename, 'w');
log_message(log_fid, 'O-RIS Integration Started');

%% Configuration
config = struct();
config.operating_freq = 3.5e9;          % Hz
config.num_elements = 2048;
config.num_users = 3;
config.update_rate = 10;                % Hz (real-time update frequency)
config.simulation_duration = 30;        % seconds
config.latency_target = 100;            % milliseconds

log_message(log_fid, sprintf('Configuration loaded: %d elements, %d users', ...
    config.num_elements, config.num_users));

%% System Status Dashboard
system_status = struct();
system_status.ai_module = 'INITIALIZING';
system_status.control_system = 'INITIALIZING';
system_status.visualization = 'INITIALIZING';
system_status.overall = 'STARTING';

display_status(system_status);

%% Initialize Subsystems

% 1. AI Module (Parth's work)
fprintf('\n[1/4] Initializing AI Beam Steering Module...\n');
try
    ai_module = initialize_ai_module(config);
    system_status.ai_module = 'READY';
    log_message(log_fid, 'AI Module initialized successfully');
    fprintf('  ✓ AI Module ready\n');
catch ME
    system_status.ai_module = 'ERROR';
    log_message(log_fid, sprintf('AI Module error: %s', ME.message));
    fprintf('  ✗ AI Module initialization failed: %s\n', ME.message);
end

% 2. Control System (Shrey's work)
fprintf('\n[2/4] Initializing Real-Time Control System...\n');
try
    control_system = initialize_control_system(config);
    system_status.control_system = 'READY';
    log_message(log_fid, 'Control System initialized successfully');
    fprintf('  ✓ Control System ready\n');
catch ME
    system_status.control_system = 'ERROR';
    log_message(log_fid, sprintf('Control System error: %s', ME.message));
    fprintf('  ✗ Control System initialization failed: %s\n', ME.message);
end

% 3. Visualization System
fprintf('\n[3/4] Initializing Visualization System...\n');
try
    viz_system = initialize_visualization(config);
    system_status.visualization = 'READY';
    log_message(log_fid, 'Visualization System initialized successfully');
    fprintf('  ✓ Visualization System ready\n');
catch ME
    system_status.visualization = 'ERROR';
    log_message(log_fid, sprintf('Visualization error: %s', ME.message));
    fprintf('  ✗ Visualization initialization failed: %s\n', ME.message);
end

% 4. Performance Monitor
fprintf('\n[4/4] Initializing Performance Monitor...\n');
perf_monitor = initialize_performance_monitor(config);
fprintf('  ✓ Performance Monitor ready\n');

% Update overall status
if strcmp(system_status.ai_module, 'READY') && ...
   strcmp(system_status.control_system, 'READY') && ...
   strcmp(system_status.visualization, 'READY')
    system_status.overall = 'OPERATIONAL';
    fprintf('\n✓ All subsystems initialized successfully!\n');
else
    system_status.overall = 'DEGRADED';
    fprintf('\n⚠ Some subsystems failed to initialize\n');
end

display_status(system_status);

%% Main Integration Loop
fprintf('\n========================================\n');
fprintf('  STARTING INTEGRATED DEMONSTRATION\n');
fprintf('========================================\n\n');

% Simulate user positions
user_positions = generate_user_scenario(config.num_users);
fprintf('User scenario generated: %d users\n', config.num_users);

% Time tracking
num_iterations = config.simulation_duration * config.update_rate;
dt = 1 / config.update_rate;

% Performance metrics storage
metrics.latency = zeros(1, num_iterations);
metrics.beam_accuracy = zeros(1, num_iterations);
metrics.throughput = zeros(1, num_iterations);
metrics.errors = 0;

fprintf('\nRunning integrated system for %d seconds...\n', config.simulation_duration);
fprintf('Press Ctrl+C to stop early\n\n');

% Main loop
for iter = 1:num_iterations
    tic;
    
    try
        % Step 1: AI determines optimal beam directions
        if strcmp(system_status.ai_module, 'READY')
            [beam_directions, ai_confidence] = ai_module.predict(user_positions);
            t_ai = toc * 1000;  % milliseconds
        else
            % Fallback: simple geometric beamforming
            beam_directions = simple_beamforming(user_positions);
            ai_confidence = 0.5;
            t_ai = 0;
        end
        
        % Step 2: Control system applies phase shifts
        if strcmp(system_status.control_system, 'READY')
            tic;
            control_status = control_system.apply_beams(beam_directions);
            t_control = toc * 1000;  % milliseconds
        else
            control_status = struct('success', false);
            t_control = 0;
        end
        
        % Step 3: Update visualization
        if strcmp(system_status.visualization, 'READY')
            tic;
            viz_system.update(user_positions, beam_directions, ai_confidence);
            t_viz = toc * 1000;  % milliseconds
        else
            t_viz = 0;
        end
        
        % Calculate total latency
        total_latency = t_ai + t_control + t_viz;
        metrics.latency(iter) = total_latency;
        
        % Record other metrics
        metrics.beam_accuracy(iter) = ai_confidence;
        metrics.throughput(iter) = calculate_throughput(beam_directions, user_positions);
        
        % Update performance monitor
        perf_monitor.update(metrics, iter);
        
        % Display progress
        if mod(iter, config.update_rate) == 0  % Every second
            elapsed = iter / config.update_rate;
            fprintf('[%.1fs] Latency: %.1fms | Accuracy: %.1f%% | Status: ', ...
                elapsed, total_latency, ai_confidence*100);
            
            if total_latency < config.latency_target
                fprintf('✓ OK\n');
            else
                fprintf('⚠ SLOW\n');
            end
        end
        
        % Wait for next update cycle
        pause(max(0, dt - toc));
        
    catch ME
        metrics.errors = metrics.errors + 1;
        log_message(log_fid, sprintf('Error in iteration %d: %s', iter, ME.message));
        fprintf('✗ Error in iteration %d: %s\n', iter, ME.message);
        
        % Attempt recovery
        if metrics.errors > 10
            fprintf('\n⚠ Too many errors, stopping demonstration\n');
            break;
        end
    end
end

fprintf('\n✓ Integration demonstration complete!\n');

%% Performance Analysis
fprintf('\n========================================\n');
fprintf('  PERFORMANCE ANALYSIS\n');
fprintf('========================================\n\n');

% Latency statistics
fprintf('--- Latency Analysis ---\n');
fprintf('Mean latency: %.2f ms\n', mean(metrics.latency));
fprintf('Max latency: %.2f ms\n', max(metrics.latency));
fprintf('Min latency: %.2f ms\n', min(metrics.latency));
fprintf('Std deviation: %.2f ms\n', std(metrics.latency));
fprintf('Target: %.0f ms\n', config.latency_target);

latency_pass_rate = 100 * sum(metrics.latency < config.latency_target) / length(metrics.latency);
fprintf('Latency target met: %.1f%% of time\n', latency_pass_rate);

if latency_pass_rate >= 95
    fprintf('✓ PASS: Latency requirement met\n');
else
    fprintf('✗ FAIL: Latency exceeds target\n');
end

% Accuracy statistics
fprintf('\n--- Beam Accuracy ---\n');
fprintf('Mean accuracy: %.1f%%\n', mean(metrics.beam_accuracy)*100);
fprintf('Min accuracy: %.1f%%\n', min(metrics.beam_accuracy)*100);

% Reliability
fprintf('\n--- System Reliability ---\n');
fprintf('Total iterations: %d\n', num_iterations);
fprintf('Errors encountered: %d\n', metrics.errors);
reliability = 100 * (1 - metrics.errors/num_iterations);
fprintf('Reliability: %.2f%%\n', reliability);

if reliability >= 95
    fprintf('✓ PASS: System reliability acceptable\n');
else
    fprintf('✗ FAIL: Too many errors\n');
end

%% Generate Performance Plots
fprintf('\nGenerating performance visualizations...\n');

figure('Position', [100, 100, 1200, 800]);

% Subplot 1: Latency over time
subplot(2, 2, 1);
time_axis = (1:num_iterations) / config.update_rate;
plot(time_axis, metrics.latency, 'b-', 'LineWidth', 1.5);
hold on;
yline(config.latency_target, 'r--', 'LineWidth', 2, 'Label', 'Target');
hold off;
grid on;
xlabel('Time (seconds)', 'FontSize', 11);
ylabel('Latency (ms)', 'FontSize', 11);
title('End-to-End System Latency', 'FontSize', 12, 'FontWeight', 'bold');
legend('Measured', 'Target', 'Location', 'best');

% Subplot 2: Latency histogram
subplot(2, 2, 2);
histogram(metrics.latency, 30, 'FaceColor', [0.2 0.5 0.8]);
hold on;
xline(config.latency_target, 'r--', 'LineWidth', 2.5);
xline(mean(metrics.latency), 'g--', 'LineWidth', 2.5);
hold off;
grid on;
xlabel('Latency (ms)', 'FontSize', 11);
ylabel('Frequency', 'FontSize', 11);
title('Latency Distribution', 'FontSize', 12, 'FontWeight', 'bold');
legend('Samples', 'Target', 'Mean', 'Location', 'best');

% Subplot 3: Beam accuracy
subplot(2, 2, 3);
plot(time_axis, metrics.beam_accuracy * 100, 'g-', 'LineWidth', 1.5);
grid on;
xlabel('Time (seconds)', 'FontSize', 11);
ylabel('Accuracy (%)', 'FontSize', 11);
title('AI Beam Steering Accuracy', 'FontSize', 12, 'FontWeight', 'bold');
ylim([0 100]);

% Subplot 4: Throughput
subplot(2, 2, 4);
plot(time_axis, metrics.throughput, 'Color', [0.8 0.4 0.1], 'LineWidth', 1.5);
grid on;
xlabel('Time (seconds)', 'FontSize', 11);
ylabel('Throughput (Mbps)', 'FontSize', 11);
title('System Throughput', 'FontSize', 12, 'FontWeight', 'bold');

sgtitle('O-RIS System Integration Performance', 'FontSize', 14, 'FontWeight', 'bold');
print('-dpng', '-r300', 'oris_integration_performance.png');
fprintf('Performance plots saved!\n');

%% Save Results
save('oris_integration_results.mat', 'metrics', 'config', 'system_status');
log_message(log_fid, 'Integration test completed successfully');
log_message(log_fid, sprintf('Final reliability: %.2f%%', reliability));
fclose(log_fid);

fprintf('\n✓ Integration complete!\n');
fprintf('Log saved: %s\n', log_filename);
fprintf('Results saved: oris_integration_results.mat\n');
fprintf('Performance plot: oris_integration_performance.png\n');

%% Helper Functions

function log_message(fid, message)
    timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    fprintf(fid, '[%s] %s\n', timestamp, message);
end

function display_status(status)
    fprintf('\n--- System Status ---\n');
    fprintf('AI Module:        %s\n', status.ai_module);
    fprintf('Control System:   %s\n', status.control_system);
    fprintf('Visualization:    %s\n', status.visualization);
    fprintf('Overall:          %s\n', status.overall);
    fprintf('--------------------\n');
end

function ai_module = initialize_ai_module(config)
    % Simulated AI module initialization
    % In actual implementation, this would load Parth's trained model
    ai_module = struct();
    ai_module.model_loaded = true;
    ai_module.predict = @(user_pos) predict_beam_directions(user_pos);
    pause(0.5);  % Simulate initialization time
end

function control_system = initialize_control_system(config)
    % Simulated control system initialization
    % In actual implementation, this would connect to Shrey's hardware interface
    control_system = struct();
    control_system.connected = true;
    control_system.apply_beams = @(beams) apply_beam_directions(beams);
    pause(0.5);  % Simulate initialization time
end

function viz_system = initialize_visualization(config)
    % Initialize real-time visualization
    viz_system = struct();
    viz_system.figure_handle = figure('Position', [100, 100, 800, 600]);
    viz_system.update = @(users, beams, conf) update_visualization(users, beams, conf, viz_system.figure_handle);
end

function perf_monitor = initialize_performance_monitor(config)
    perf_monitor = struct();
    perf_monitor.start_time = tic;
    perf_monitor.update = @(m, i) update_performance(m, i);
end

function [beam_dirs, confidence] = predict_beam_directions(user_positions)
    % Simulated AI prediction
    % In actual implementation, this calls Parth's ML model
    num_users = size(user_positions, 1);
    beam_dirs = zeros(num_users, 1);
    
    for i = 1:num_users
        % Calculate angle to user
        beam_dirs(i) = atan2d(user_positions(i, 2), user_positions(i, 1));
    end
    
    confidence = 0.85 + 0.1*rand();  % Simulated confidence
end

function beam_dirs = simple_beamforming(user_positions)
    % Fallback: simple geometric beamforming
    num_users = size(user_positions, 1);
    beam_dirs = zeros(num_users, 1);
    
    for i = 1:num_users
        beam_dirs(i) = atan2d(user_positions(i, 2), user_positions(i, 1));
    end
end

function status = apply_beam_directions(beam_dirs)
    % Simulated control application
    % In actual implementation, this sends commands to hardware
    pause(0.001);  % Simulate control latency
    status = struct('success', true, 'applied_beams', beam_dirs);
end

function update_visualization(users, beams, confidence, fig_handle)
    % Update real-time visualization
    figure(fig_handle);
    clf;
    
    theta = linspace(0, 2*pi, 100);
    radius = 100;
    
    % Draw coverage area
    plot(radius*cos(theta), radius*sin(theta), 'k--', 'LineWidth', 1);
    hold on;
    
    % Draw O-RIS at center
    plot(0, 0, 'bs', 'MarkerSize', 15, 'MarkerFaceColor', 'b');
    
    % Draw users
    plot(users(:, 1), users(:, 2), 'ro', 'MarkerSize', 12, 'MarkerFaceColor', 'r');
    
    % Draw beams
    for i = 1:length(beams)
        beam_length = 80;
        x_end = beam_length * cosd(beams(i));
        y_end = beam_length * sind(beams(i));
        plot([0 x_end], [0 y_end], 'g-', 'LineWidth', 2.5);
    end
    
    hold off;
    axis equal;
    grid on;
    xlabel('X Position (m)', 'FontSize', 10);
    ylabel('Y Position (m)', 'FontSize', 10);
    title(sprintf('O-RIS Real-Time Beam Steering (Confidence: %.1f%%)', confidence*100), ...
        'FontSize', 11, 'FontWeight', 'bold');
    legend('Coverage', 'O-RIS', 'Users', 'Beams', 'Location', 'best');
    drawnow;
end

function users = generate_user_scenario(num_users)
    % Generate random user positions
    angles = 360 * rand(num_users, 1);
    distances = 30 + 50 * rand(num_users, 1);
    
    users = [distances .* cosd(angles), distances .* sind(angles)];
end

function throughput = calculate_throughput(beam_dirs, user_pos)
    % Simulated throughput calculation based on beam alignment
    num_users = length(beam_dirs);
    throughput = 0;
    
    for i = 1:num_users
        user_angle = atan2d(user_pos(i, 2), user_pos(i, 1));
        alignment_error = abs(beam_dirs(i) - user_angle);
        
        % Throughput decreases with misalignment
        user_throughput = 100 * exp(-(alignment_error/10)^2);
        throughput = throughput + user_throughput;
    end
end

function update_performance(metrics, iteration)
    % Performance monitor update (placeholder)
    % Can add real-time plotting or logging here
end
