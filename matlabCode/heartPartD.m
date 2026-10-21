clear; close all;

%% 1. Runner and Environmental Constants
mass_runner = 75;                  % Runner body mass (kg)
Base_Velocity = 1.5;               % Light jog speed (m/s)
run_velocity = 7.0;                % Sprint speed (m/s) 
theta = 0;                         % Incline angle (degrees, flat surface)
aerodynamic_drag_coefficient = 0.9;
frontal_surface_area = 0.65;       % m^2
air_density = 1.2;                 % kg/m^3
gravitational_acceleration = 9.81; % m/s^2
mechanical_efficiency = 0.22;      % Human muscular efficiency (~22%)

% Locomotion resistance calibrated so 7.0 m/s hits metabolic P_max = 1200 W
C_rr = 0.0245;                     

power_baseline = 80;               % Resting metabolic rate (Watts)
power_max = 1200;                  % Maximum aerobic power (Watts)

% Run protocol intervals (minutes)
duration_accel = 15/60;            % 15-second speed ramp
t_rest_end     = 2.0;              % Rest ends, light jog begins
t_accel_start  = 6.0;              % Sprint acceleration begins
t_accel_end    = t_accel_start + duration_accel;
t_decel1_start = 18.25;            % Sprint ends, decel to jog begins
t_decel1_end   = t_decel1_start + duration_accel;
t_cooldown_end = 22.0;             % Jog ends, decel to full stop begins
t_decel2_end   = t_cooldown_end + duration_accel;

%% 2. VO2 Conversions
caloric_equivalent = 20900; % J per Liter O2
VO2_rest_L_min = (power_baseline / caloric_equivalent) * 60;
VO2_max_L_min  = (power_max      / caloric_equivalent) * 60;
VO2_rel_rest = (VO2_rest_L_min * 1000) / mass_runner; % mL/kg/min
VO2_rel_max  = (VO2_max_L_min  * 1000) / mass_runner; % mL/kg/min

%% 3. Autonomic & Cardiovascular Parameters
intrinsic_rate = 100;                 % SA node intrinsic pace (bpm)
parasympathetic_inhibition_rest = 30; % Resting vagal tone reduction (bpm)
heartRate_base = intrinsic_rate - parasympathetic_inhibition_rest;
sympathetic_sensitivity = 60;         % Max neural HR gain (bpm)
epinephrine_sensitivity = 60;         % Max hormonal HR gain (bpm)
HR_max = 220;                         % Physiological ceiling (bpm)

half_life_epinephrine = 2.5;                            % Half-life in blood (min)
clearance_rate_constant = log(2) / half_life_epinephrine; % First-order decay k (1/min)

StrokeVolume_base = 70;              % Baseline resting SV (mL)
EndSystolicVolume_base = 60;         % Post-beat residual reserve (mL)
EndDiastolicVolume_base = 130;       % Resting filled volume (mL)
DeltaEndDiastolicVolume_max = 25;    % Max Frank-Starling stretch during exertion (mL)
EjectionFraction_base = StrokeVolume_base / EndDiastolicVolume_base;
EjectionFraction_max = 0.85;

% Contractility partition: 80% direct neural, 20% hormonal
K_sympathetic_sensitivity = (EjectionFraction_max - EjectionFraction_base) * 0.80;
K_sympathetic_sensitivity_epinephrine = (EjectionFraction_max - EjectionFraction_base) * 0.20;

elapsed_beat_time = 0;               % Accumulator for beat phase
TotalBloodVolume = 5000;             % Total systemic blood volume (mL)

%% 4. Time Setup
dt = 0.00001;                        % Simulation step (minutes)
end_time = 30;                       % Total duration (minutes)
time = 0:dt:end_time;
N = length(time);

% Preallocation
epinephrine_stock = zeros(1, N);     
velocity_vector = zeros(1, N);
sympathetic_stimulation_vector = zeros(1, N);
inflow_rate_vector = zeros(1, N);
heart_rate_vector = zeros(1, N);
EjectionFraction = zeros(1, N);
EndDiastolicVolume = zeros(1, N);
StrokeVolume = zeros(1, N);             % mL
CardiacOutput_continuous = zeros(1, N); % mL/min
CardiacOutput_pulsatile = zeros(1, N);  % mL/min
Flow = zeros(1, N);
ventricle_volume = zeros(1, N);
EndSystolicVolume = zeros(1, N);

ventricle_volume(1) = EndSystolicVolume_base; % Start post-beat at 60 mL
EndSystolicVolume(1) = EndSystolicVolume_base;

%% 5. Simulation Loop (Euler Integration)
for i = 1:N
    t_curr = time(i);
    
    % Piecewise runner velocity schedule
    if t_curr < t_rest_end
        current_v = 0.0;
    elseif t_curr >= t_rest_end && t_curr < t_accel_start
        current_v = Base_Velocity;
    elseif t_curr >= t_accel_start && t_curr < t_accel_end
        fraction = (t_curr - t_accel_start) / duration_accel;
        current_v = Base_Velocity + fraction * (run_velocity - Base_Velocity);
    elseif t_curr >= t_accel_end && t_curr < t_decel1_start
        current_v = run_velocity;
    elseif t_curr >= t_decel1_start && t_curr < t_decel1_end
        fraction = (t_curr - t_decel1_start) / duration_accel;
        current_v = run_velocity - fraction * (run_velocity - Base_Velocity);
    elseif t_curr >= t_decel1_end && t_curr < t_cooldown_end
        current_v = Base_Velocity;
    elseif t_curr >= t_cooldown_end && t_curr < t_decel2_end
        fraction = (t_curr - t_cooldown_end) / duration_accel;
        current_v = Base_Velocity * (1 - fraction);
    else
        current_v = 0.0;
    end
    velocity_vector(i) = current_v;
    
    % Ground and aerodynamic resistances
    if current_v > 0
        f_ground = C_rr * mass_runner * gravitational_acceleration * cosd(theta);
    else
        f_ground = 0.0;
    end
    
    resistive_force = (mass_runner * gravitational_acceleration * sind(theta)) + ...
                      f_ground + ...
                      0.5 * air_density * aerodynamic_drag_coefficient * frontal_surface_area * (current_v^2);
                  
    % Metabolic demand and relative VO2
    mechanical_power = resistive_force * current_v;
    power_metabolic = power_baseline + (mechanical_power / mechanical_efficiency);
    VO2_L_min = (power_metabolic / caloric_equivalent) * 60;
    VO2_rel = (VO2_L_min * 1000) / mass_runner;
    
    % Normalized sympathetic drive S (clamped between 0 and 1)
    sympathetic_raw = (VO2_rel - VO2_rel_rest) / (VO2_rel_max - VO2_rel_rest);
    sympathetic_stimulation = min(max(sympathetic_raw, 0.0), 1.0);
    sympathetic_stimulation_vector(i) = sympathetic_stimulation;
    
    % Adrenal epinephrine release kicks in past 50% exertion
    if sympathetic_stimulation < 0.50
        inflow_rate = 0.0;
    elseif sympathetic_stimulation >= 0.50 && sympathetic_stimulation < 0.75
        inflow_rate = 0.14 * ((sympathetic_stimulation - 0.50) / 0.25);
    else
        inflow_rate = 0.14 + 0.14 * ((sympathetic_stimulation - 0.75) / 0.25);
    end
    inflow_rate = max(0.0, inflow_rate); % Clamp non-negative
    inflow_rate_vector(i) = inflow_rate;
    
    % Epinephrine first-order clearance
    outflow_rate = clearance_rate_constant * epinephrine_stock(i);
    
    if i < N
        d_epinephrine_dt = inflow_rate - outflow_rate;
        epinephrine_stock(i+1) = max(0.0, epinephrine_stock(i) + d_epinephrine_dt * dt); % Clamp non-negative
    end
    
    % Vagal withdrawal as exertion increases (clamped >= 0)
    parasympathetic_inhibition = parasympathetic_inhibition_rest * (1 - (sympathetic_stimulation / 0.4));
    parasympathetic_inhibition = max(0.0, parasympathetic_inhibition);
    
    % Heart rate from combined neural and hormonal controls (clamped between rest and HR_max)
    heart_rate_raw = intrinsic_rate + ...
                     (sympathetic_sensitivity * sympathetic_stimulation) + ...
                     (epinephrine_sensitivity * epinephrine_stock(i)) - ...
                     parasympathetic_inhibition;
    heart_rate = min(max(heart_rate_raw, heartRate_base), HR_max);
    heart_rate_vector(i) = heart_rate;

    % Ejection fraction increases with inotropic drive (clamped between base and max)
    EF_raw = EjectionFraction_base + ...
             (K_sympathetic_sensitivity * sympathetic_stimulation) + ...
             (K_sympathetic_sensitivity_epinephrine * epinephrine_stock(i));
    EjectionFraction(i) = min(max(EF_raw, EjectionFraction_base), EjectionFraction_max);

    % Frank-Starling EDV expansion (clamped between base and max EDV)
    EDV_max = EndDiastolicVolume_base + DeltaEndDiastolicVolume_max;
    EDV_raw = EndDiastolicVolume_base + (DeltaEndDiastolicVolume_max * sympathetic_stimulation);
    EndDiastolicVolume(i) = min(max(EDV_raw, EndDiastolicVolume_base), EDV_max);

    StrokeVolume(i) = EjectionFraction(i) * EndDiastolicVolume(i);
    EndSystolicVolume(i) = EndDiastolicVolume(i) * (1 - EjectionFraction(i));

    % Version 1: Continuous mean cardiac output
    CardiacOutput_continuous(i) = StrokeVolume(i) * heart_rate_vector(i);

    % Version 2: Discrete pulsatile outflow
    T_beat = 1.0 / heart_rate_vector(i); % Cycle period in minutes
    elapsed_beat_time = elapsed_beat_time + dt;

    if elapsed_beat_time >= T_beat
        % Eject volume down to dynamic EndSystolicVolume(i) (clamped non-negative)
        ejected_volume = max(0.0, ventricle_volume(i) - EndSystolicVolume(i));
        Flow(i) = ejected_volume / dt; 
        elapsed_beat_time = elapsed_beat_time - T_beat; % Keep phase remainder
    else
        Flow(i) = 0.0;
    end
    CardiacOutput_pulsatile(i) = Flow(i);

    % Ventricular stock Euler integration
    if i < N
        % Venous inflow refills SV over beat period T_beat
        venous_return = StrokeVolume(i) * heart_rate_vector(i); 
        ventricle_next = ventricle_volume(i) + ...
                         (venous_return - CardiacOutput_pulsatile(i)) * dt;
        % Guard against negative volume stock
        ventricle_volume(i+1) = max(0.0, ventricle_next);
    end
end

%% 6. Plotting Results

% Figure 1: Autonomic Inputs
figure('Name', 'Autonomic Drivers', 'NumberTitle', 'off');
plot(time, sympathetic_stimulation_vector, 'b', 'LineWidth', 1.8); hold on;
plot(time, epinephrine_stock, 'r', 'LineWidth', 1.5);
xlim([0, end_time]);
grid on;
xlabel('Time (minutes)');
ylabel('Drive / Concentration');
legend('Sympathetic Neural Drive (S)', 'Circulating Epinephrine [E]', 'Location', 'northwest');
title('Autonomic Neural and Hormonal Inputs (0–30 min)');

% Figure 2: Heart Rate
figure('Name', 'Heart Rate', 'NumberTitle', 'off');
plot(time, heart_rate_vector, 'k', 'LineWidth', 1.8);
xlim([0, end_time]);
grid on;
xlabel('Time (minutes)');
ylabel('Heart Rate (bpm)');
title('Heart Rate Regulation (0–30 min)');

% Figure 3: Ventricular Capacities
figure('Name', 'Ventricular Volumes', 'NumberTitle', 'off');
plot(time, EndDiastolicVolume, 'b', 'LineWidth', 1.5); hold on;
plot(time, StrokeVolume, 'g', 'LineWidth', 1.5); hold on;
plot(time, EndSystolicVolume, 'r--', 'LineWidth', 1.5);
xlim([0, end_time]);
grid on;
xlabel('Time (minutes)');
ylabel('Volume (mL)');
legend('End-Diastolic Volume (EDV)', 'Stroke Volume (SV)', 'End-Systolic Volume (ESV)', 'Location', 'northwest');
title('Ventricular Volumes (0–30 min)');

% Figure 4: Version 1 Continuous Cardiac Output
figure('Name', 'Continuous Cardiac Output', 'NumberTitle', 'off');
plot(time, CardiacOutput_continuous / 1000, 'm', 'LineWidth', 1.5);
xlim([0, end_time]);
grid on;
xlabel('Time (minutes)');
ylabel('Cardiac Output (L/min)');
title('Continuous Mean Cardiac Output (0–30 min)');

% Figure 5: Version 2 Discrete Stroke Volume Dump (Zoomed Transition)
figure('Name', 'Discrete Systolic Volume Dump', 'NumberTitle', 'off');
stem(time, (CardiacOutput_pulsatile * dt), 'Color', [0.85 0.325 0.098], 'Marker', 'none', 'LineWidth', 1.8);
xlim([6.0, 6.3]);
ylim([0, 160]);
grid on;
xlabel('Time (minutes)');
ylabel('Volume Ejected (mL)');
title('Discharged Stroke Volume per Beat (6.0–6.3 min Zoom)');

% Figure 6: Version 2 Discrete Stroke Volume Dump (Full 30 min)
figure('Name', 'Discrete Systolic Volume Dump', 'NumberTitle', 'off');
stem(time, (CardiacOutput_pulsatile * dt), 'Color', [0.85 0.325 0.098], 'Marker', 'none');
xlim([0, end_time]);
ylim([0, 160]);
grid on;
xlabel('Time (minutes)');
ylabel('Volume Ejected (mL)');
title('Discharged Stroke Volume per Beat (30 min)');

% Figure 7: Left Ventricle Stock (Full 30 min)
figure('Name', 'Ventricular Blood Stock', 'NumberTitle', 'off');
plot(time, ventricle_volume, 'Color', [0 0.447 0.741]);
xlim([0, end_time]);
grid on;
xlabel('Time (minutes)');
ylabel('Blood Volume (mL)');
title('Ventricular Stock Volume (0–30 min)');

% Figure 8: Left Ventricle Stock (Zoomed Sawtooth Filling/Emptying)
figure('Name', 'Ventricular Blood Stock', 'NumberTitle', 'off');
plot(time, ventricle_volume, 'Color', [0 0.447 0.741], 'LineWidth', 1.8);
xlim([6.0, 6.3]);
grid on;
xlabel('Time (minutes)');
ylabel('Blood Volume (mL)');
title('Ventricular Stock Volume (6.0 to 6.3 min)');
