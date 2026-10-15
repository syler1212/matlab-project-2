clear;
%simulation of a runners heart being influenced by the nervous system on a
%run

%%
%defining constants
mass_runner = 75;  % (kg)
Constant_Velocity = 1.5; %(m/s) 8.88 = max V at no incline
theta = 10;% (degrees) of incline.
aerodynamic_drag_coefficient = 0.9;
frontal_surface_area = 0.65;  %(m^2) 1.82m by 0.45m
air_density = 1.2; % (kg/m^3)
gravitational_acceleration = 9.81; % (m/s^2)

resistive_force = (mass_runner*gravitational_acceleration*sind(theta)) + 1/2 * air_density * aerodynamic_drag_coefficient * frontal_surface_area * (Constant_Velocity^2);%(N)
mechanical_power = resistive_force * Constant_Velocity; %(Nm/s) or (Watts)
mechanical_efficiency = 0.22; % (%)
power_baseline = 80; % (Watts)
power_metabolic = power_baseline + (mechanical_power/mechanical_efficiency);
power_max = 1200;

sympathetic_stimulation = (power_metabolic-power_baseline)/(power_max - power_baseline)% a range from 0 to 1. This is the signal from the brain to increase blood flow to the organs based on need.

intrinsic_rate = 100; % the intrinsic pacemaker with no nervous sysstem input.
constant_parasympathetic_inhibition = 30; % the breaks on the heart.
baseline_heart_rate = intrinsic_rate - constant_parasympathetic_inhibition;

sympathetic_sensitivity = 110; % this is our maximum increase above the baseline heart rate.

heart_rate = baseline_heart_rate + sympathetic_sensitivity * sympathetic_stimulation 

