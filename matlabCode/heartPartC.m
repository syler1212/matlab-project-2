clear; close all;

%% 1. Runner and Environmental Constants
mass_runner = 75;                  % (kg)
Base_Velocity = 1.5;               % (m/s)
run_velocity = 7.0;                % (m/s) 
theta = 0;                         % (degrees) Flat terrain throughout
aerodynamic_drag_coefficient = 0.9;
frontal_surface_area = 0.65;       % (m^2)
air_density = 1.2;                 % (kg/m^3)
gravitational_acceleration = 9.81; % (m/s^2)
mechanical_efficiency = 0.22;      % (%)

% Calibrated so that v = 7.0 m/s hits exactly P_max = 1200 W (S = 1.0)
C_rr = 0.0245;                     % Locomotion resistance coefficient

power_baseline = 80;               % Resting metabolic rate (Watts)
power_max = 1200;                  % Max aerobic metabolic power (Watts)

% Stage timing definitions (in minutes)
duration_accel = 15/60;             % Linear transition ramp duration (~15 seconds)
t_rest_end     = 2.0;              % Rest ends, light jog begins
t_accel_start  = 6.0;              % Sprint acceleration begins
t_accel_end    = t_accel_start + duration_accel; % Sprint acceleration ends
t_decel1_start = 18.25;             % Sprint ends, decel to Base_Velocity begins
t_decel1_end   = t_decel1_start + duration_accel; % Reaches Base_Velocity
t_cooldown_end = 15.0;             % Jog/cooldown ends, decel to rest begins
t_decel2_end   = t_cooldown_end + duration_accel; % Fully stopped

%% 2. VO2 Conversions
caloric_equivalent = 20900; % J / L O2
VO2_rest_L_min = (power_baseline / caloric_equivalent) * 60;
VO2_max_L_min  = (power_max      / caloric_equivalent) * 60;
VO2_rel_rest = (VO2_rest_L_min * 1000) / mass_runner; % mL/kg/min
VO2_rel_max  = (VO2_max_L_min  * 1000) / mass_runner; % mL/kg/min

%% 3. Epinephrine Parameters
intrinsic_rate = 100;                 % Intrinsic pacemaker rate (bpm)
parasympathetic_inhibition_rest = 30; % Resting vagal tone (bpm)
sympathetic_sensitivity = 60;         % Pure sympathetic neural gain (bpm per unit S)
epinephrine_sensitivity = 60;         % Hormonal sensitivity (bpm per unit conc)
HR_max = 220;                         % Maximum physiological ceiling (bpm)

half_life_epinephrine = 2.5;                            % Half-life in blood (minutes)
clearance_rate_constant = log(2) / half_life_epinephrine; % k (1/min) 

%% 4. Time Setup
dt = 0.001;                          % Step size (minutes, 0.06 s for smooth ramps)
end_time = 30;                       % Total simulation time (minutes)
time = 0:dt:end_time;
N = length(time);

% Preallocate vectors
epinephrine_stock = zeros(1, N);     % (starts at 0)
velocity_vector = zeros(1, N);
sympathetic_stimulation_vector = zeros(1, N);
inflow_rate_vector = zeros(1, N);
heart_rate_vector = zeros(1, N);

%% 5. Simulation Loop (Euler Integration)
for i = 1:N
    t_curr = time(i);
    
    % Dynamic run protocol with linear velocity ramps (flat ground throughout):
    % 0 to 2 min: Standing rest
    if t_curr < t_rest_end
        current_v = 0.0;
        
    % 2 to 6 min Base jog
    elseif t_curr >= t_rest_end && t_curr < t_accel_start
        current_v = Base_Velocity;
        
    % Linear acceleration ramp up to sprint speed
    elseif t_curr >= t_accel_start && t_curr < t_accel_end
        fraction = (t_curr - t_accel_start) / duration_accel;
        current_v = Base_Velocity + fraction * (run_velocity - Base_Velocity);
        
    % High sprint
    elseif t_curr >= t_accel_end && t_curr < t_decel1_start
        current_v = run_velocity;
        
    % Linear deceleration ramp down to Base_Velocity
    elseif t_curr >= t_decel1_start && t_curr < t_decel1_end
        fraction = (t_curr - t_decel1_start) / duration_accel;
        current_v = run_velocity - fraction * (run_velocity - Base_Velocity);
        
    %Cooldown jog at Base_Velocity
    elseif t_curr >= t_decel1_end && t_curr < t_cooldown_end
        current_v = Base_Velocity;
        
    % Linear deceleration down to complete stop
    elseif t_curr >= t_cooldown_end && t_curr < t_decel2_end
        fraction = (t_curr - t_cooldown_end) / duration_accel;
        current_v = Base_Velocity * (1 - fraction);
        
    % Post-run rest recovery
    else
        current_v = 0.0;
    end
    
    velocity_vector(i) = current_v;
    
    % Biomechanical Ground Locomotion Resistance
    if current_v > 0
        f_ground = C_rr * mass_runner * gravitational_acceleration * cosd(theta);
    else
        f_ground = 0.0;
    end
    
    % Total resistive force
    resistive_force = (mass_runner * gravitational_acceleration * sind(theta)) + ...
                      f_ground + ...
                      0.5 * air_density * aerodynamic_drag_coefficient * frontal_surface_area * (current_v^2);
                  
    mechanical_power = resistive_force * current_v;
    power_metabolic = power_baseline + (mechanical_power / mechanical_efficiency);
    VO2_L_min = (power_metabolic / caloric_equivalent) * 60;
    VO2_rel = (VO2_L_min * 1000) / mass_runner;
    
    % Instantaneous sympathetic neural drive S
    sympathetic_stimulation = (VO2_rel - VO2_rel_rest) / (VO2_rel_max - VO2_rel_rest);
    sympathetic_stimulation_vector(i) = sympathetic_stimulation;
    
   % Adrenal release (inflow)
    if sympathetic_stimulation < 0.50
        inflow_rate = 0.0;
    elseif sympathetic_stimulation >= 0.50 && sympathetic_stimulation < 0.75
        % Linear onset between S = 0.50 and 0.75
        inflow_rate = 0.14 * ((sympathetic_stimulation - 0.50) / 0.25);
    else
        
        inflow_rate = 0.14 + 0.14 * ((sympathetic_stimulation - 0.75) / 0.25);
    end
    inflow_rate_vector(i) = inflow_rate;
    
    % Proportional clearance (outflow)
    outflow_rate = clearance_rate_constant * epinephrine_stock(i);
    
    % Euler numerical integration: Stock(i+1) = Stock(i) + (Inflow - Outflow)*dt
    if i < N
        d_epinephrine_dt = inflow_rate - outflow_rate;
        epinephrine_stock(i+1) = max(0, epinephrine_stock(i) + d_epinephrine_dt * dt);
    end
    
    % Parasympathetic brake
    parasympathetic_inhibition = parasympathetic_inhibition_rest * max(0, 1 - (sympathetic_stimulation / 0.4));
    
    % Heart rate under dual neural + hormonal control
    heart_rate = intrinsic_rate + ...
                     (sympathetic_sensitivity * sympathetic_stimulation) + ...
                     (epinephrine_sensitivity * epinephrine_stock(i)) - ...
                     parasympathetic_inhibition;
                 
    % Enforce hard physiological limit
    
    heart_rate_vector(i) = heart_rate;
end

%% 6. Plotting Part 1.c Dynamic Results
figure('Color', 'w', 'Position', [120, 120, 950, 700]);

% Subplot 1: Dynamic Drive & Hormonal Concentration
subplot(2, 1, 1);
plot(time, sympathetic_stimulation_vector, 'b-', 'LineWidth', 2, 'DisplayName', 'Sympathetic Stimulation (S)');
hold on;
plot(time, epinephrine_stock, 'r-', 'LineWidth', 2.2, 'DisplayName', 'Epinephrine Stock [Conc]');
plot(time, inflow_rate_vector, 'm--', 'LineWidth', 1.2, 'DisplayName', 'Adrenal Inflow Rate');
yline(0.5, 'k:', 'LineWidth', 1.1, 'DisplayName', 'Epi Release Threshold (S = 0.50)');
grid on; box on;
xlim([0, end_time]);
ylim([0, 1.5]);
xlabel('Time (minutes)', 'FontWeight', 'bold');
ylabel('Activity / Concentration', 'FontWeight', 'bold');
title('Neural Drive vs. Adrenal Epinephrine Dynamics (Project 1c, \theta = 0^\circ, v_{max} = 7.0 m/s)', 'FontSize', 12);
legend('Location', 'northeast');

% Subplot 2: Dynamic Heart Rate Over Time
subplot(2, 1, 2);
plot(time, heart_rate_vector, 'k-', 'LineWidth', 2.2, 'DisplayName', 'Heart Rate');
hold on;
yline(HR_max, 'r--', 'LineWidth', 1.2, 'DisplayName', 'Max Physiological Ceiling (220 bpm)');
yline(intrinsic_rate, 'k:', 'LineWidth', 1.2, 'DisplayName', 'Intrinsic Pacemaker (100 bpm)');
yline(intrinsic_rate - parasympathetic_inhibition_rest, 'g--', 'LineWidth', 1.2, 'DisplayName', 'Resting Baseline (70 bpm)');
grid on; box on;
xlim([0, end_time]);
ylim([60, 235]);
xlabel('Time (minutes)', 'FontWeight', 'bold');
ylabel('Heart Rate (bpm)', 'FontWeight', 'bold');
title('Heart Rate Regulation with Epinephrine Accumulation and Washout Lag', 'FontSize', 12);
legend('Location', 'northeast');