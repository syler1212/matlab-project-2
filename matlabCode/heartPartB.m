clear; clc; close all;
%% 1. Runner and Environmental Constants
mass_runner = 75;                  % (kg)
Constant_Velocity = 1.5;           % (m/s)
theta = 0;                         % (degrees) of incline
aerodynamic_drag_coefficient = 0.9;
frontal_surface_area = 0.65;       % (m^2)
air_density = 1.2;                 % (kg/m^3)
gravitational_acceleration = 9.81; % (m/s^2)
mechanical_efficiency = 0.22;      % (%)
power_baseline = 80;               % (Watts)
power_max = 1200;                  % (Watts)
C_rr = 0.0245;                     % Locomotion resistance coefficient
%% 2. Operating Point Calculation (Current Run)
f_ground = C_rr * mass_runner * gravitational_acceleration * cosd(theta);
resistive_force = (mass_runner * gravitational_acceleration * sind(theta)) + ...
    f_ground + ...
    0.5 * air_density * aerodynamic_drag_coefficient * frontal_surface_area * (Constant_Velocity^2); %(N)
mechanical_power = resistive_force * Constant_Velocity; %(Nm/s) or (Watts)
power_metabolic = power_baseline + (mechanical_power / mechanical_efficiency);
% Sympathetic stimulation operating point
sympathetic_stimulation = (power_metabolic - power_baseline) / (power_max - power_baseline);
sympathetic_stimulation = max(0, min(1, sympathetic_stimulation));
%% 3. Autonomic Response Model Parameters
intrinsic_rate = 100;                 % Intrinsic pacemaker rate (bpm)
parasympathetic_inhibition_rest = 30; % Resting vagal tone (bpm)
sympathetic_sensitivity = 80;         % Pure sympathetic slope (bpm per unit S)
% Operating point heart rate
parasympathetic_inhibition = parasympathetic_inhibition_rest * max(0, 1 - (sympathetic_stimulation / 0.4));
heart_rate = intrinsic_rate + (sympathetic_sensitivity * sympathetic_stimulation) - parasympathetic_inhibition;
%% 4. Vectorized Simulation (0 to 1 Sympathetic Drive)
sympathetic_stimulation_vector = linspace(0, 1, 101);
% Vagal tone drops linearly to 0 at 0.4 and clamps at 0 for values >= 0.4
parasympathetic_inhibition_vector = parasympathetic_inhibition_rest * max(0, 1 - (sympathetic_stimulation_vector ./ 0.4));
% Resulting dual-slope heart rate vector
heart_rate_vector = intrinsic_rate + (sympathetic_sensitivity .* sympathetic_stimulation_vector) - parasympathetic_inhibition_vector;
%% 5. Plotting
figure('Color', 'w', 'Position', [150, 150, 850, 600]);
% Main heart rate curve
plot(sympathetic_stimulation_vector, heart_rate_vector, 'b-', 'LineWidth', 2.5, 'DisplayName', 'Heart Rate Response'); 
hold on;
% Threshold line at S = 0.4 (complete vagal withdrawal)
xline(0.4, 'k--', 'LineWidth', 1.2, 'DisplayName', 'Complete Vagal Withdrawal (S = 0.4)');
% Labels and Styling
grid on;
box on;
xlabel('Sympathetic Stimulation (S)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Heart Rate (bpm)', 'FontSize', 12, 'FontWeight', 'bold');
title('Heart Rate Regulation: Dual Autonomic Control (Project 1b)', 'FontSize', 14);
legend('Location', 'northwest', 'FontSize', 10);
xlim([0, 1]);
ylim([60, 195]);
