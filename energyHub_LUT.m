function [results, sol] = energyHub_LUT(profiles, assumptionsTable, nh3_demand, ch4_demand, meoh_demand, ft_demand, wavePotential, landArea)
%energyHub_LUT Optimisation with Power-to-X
%
% This function optimises the design and operation of an integrated energy hub
% that combines renewable energy sources with power-to-X technologies for
% synthetic fuel production (e-ammonia, e-methanol, e-methane, e-Fischer-Tropsch-liquids).
%
% INPUTS:
%   profiles      - Structure containing hourly renewable energy profiles:
%                   .wind - Wind power capacity factors [8760x1]
%                   .pvo  - PV fixed-tilt capacity factors [8760x1]
%                   .pva  - PV single-axis tracking capacity factors [8760x1]
%                   .wave - Wave power capacity factors [8760x1]
%   costTable     - Table with technology cost data including CAPEX, OPEX,
%                   efficiencies, and technical parameters for year 2050
%   nh3_demand    - Annual ammonia demand [MWh/year]
%   ch4_demand    - Annual synthetic methane demand [MWh/year]
%   meoh_demand   - Annual methanol demand [MWh/year]
%   ft_demand     - Annual Fischer-Tropsch liquid demand [MWh/year]
%   wavePotential - Maximum wave energy capacity [MW]
%   landArea      - Available land area [km²]
%
% OUTPUTS:
%   results - Cell array with system capacities, costs, and energy flows
%   sol     - Optimization solution structure with all decision variables
%
% The optimisation minimises total system cost (annualised CAPEX + OPEX + ramping costs)
% subject to energy balance constraints and technical limitations.
%
% Author: Rasul Satymov
% Date: May 2025
% Version: 1.0

numHours = 8760;
wind_prof = profiles.wind(1:numHours);
pvo_prof = profiles.pvo(1:numHours); % PV fixed-tilt
pva_prof = profiles.pva(1:numHours); % PV single-axis tracking
wave_prof = profiles.wave(1:numHours);

%% Extract Technology Parameters from Cost Table
% Helper function to extract cost table values
getCostParam = @(tech, comp) assumptionsTable.x2050(matches(assumptionsTable.Tech, tech) & matches(assumptionsTable.Comp, comp));

% Battery parameters
charg_efficiency = getCostParam('Battery', 'Charging eff');
discharg_efficiency = getCostParam('Battery', 'Discharging eff');
battery_EP_ratio = getCostParam('Battery', 'E/P ratio'); % Energy-to-Power ratio [-]

% Fuel storage Energy-to-Power ratios
h2_rockCavern_EP_ratio = getCostParam('H2 Storage - lined rock cavern', 'E/P ratio');
h2_pipe_EP_ratio = getCostParam('H2 Storage - underground pipe', 'E/P ratio');
co2_storage_EP_ratio = getCostParam('CO2 Storage', 'E/P ratio');
meoh_storage_EP_ratio = getCostParam('Methanol Storage', 'E/P ratio');
nh3_storage_EP_ratio = getCostParam('Ammonia Storage', 'E/P ratio');

% Power-to-X electricity consumption ratios [MWh_elec/MWh_product]
el_to_wel = getCostParam('Alkaline Water Electrolyser (BCS)', 'Electricity in');
el_to_dac = getCostParam('Direct Air Capture', 'Electricity in');
el_to_nh3 = getCostParam('Ammonia Synthesis', 'Electricity in');
el_to_meoh = getCostParam('Methanol Synthesis', 'Electricity in');
el_to_ft = getCostParam('Fischer-Tropsch', 'Electricity in');

% Hydrogen consumption ratios [MWh_H2/MWh_product]
h2_to_nh3 = getCostParam('Ammonia Synthesis', 'Hydrogen in');
h2_to_ch4 = getCostParam('Methanation', 'Hydrogen in');
h2_to_meoh = getCostParam('Methanol Synthesis', 'Hydrogen in');
h2_to_ft = getCostParam('Fischer-Tropsch', 'Hydrogen in');
h2_to_gasTurbine = getCostParam('Multi-fuel Gas Turbine', 'Hydrogen in');
ch4_to_gasTurbine = getCostParam('Multi-fuel Gas Turbine', 'Gas in');

% CO2 consumption ratios [t_CO2/MWh_product]
co2_to_ch4 = getCostParam('Methanation', 'CO2 in');
co2_to_meoh = getCostParam('Methanol Synthesis', 'CO2 in');
co2_to_ft = getCostParam('Fischer-Tropsch', 'CO2 in');

% Heat system parameters
he_to_dac = getCostParam('Direct Air Capture', 'Heat in');
he_from_nh3 = getCostParam('Ammonia Synthesis', 'Excess heat');
he_from_ft = getCostParam('Fischer-Tropsch', 'Excess heat');
he_from_wel = getCostParam('Alkaline Water Electrolyser (BCS)', 'PtHeat eff.');
cop_ambient = getCostParam('Heat Pump', 'COP'); % Coefficient of Performance
cop_wel = 9.99 - 0.2049*(100-75) + 0.001249*(100-75)^2; % COP for waste heat recovery
el_to_elecHeat = getCostParam('Electric Heater', 'Electricity in');

% Convert annual demands to hourly constant demands
nh3_demand = ones(numHours,1) * nh3_demand/numHours;
ch4_demand = ones(numHours,1) * ch4_demand/numHours;
meoh_demand = ones(numHours,1) * meoh_demand/numHours;
ft_demand = ones(numHours,1) * ft_demand/numHours;

%% Define optimisation problem
prob = optimproblem("Description", "energyHub-LUT");

%% Decision variables - RES capacities [MW]
PVO_cap = optimvar("PVO_cap", "LowerBound", 0, "UpperBound", landArea * 0.1 * 150);
PVA_cap = optimvar("PVA_cap", "LowerBound", 0, "UpperBound", landArea * 0.1 * 150);
wind_cap = optimvar("wind_cap", "LowerBound", 0, "UpperBound", landArea * 0.1 * 8.4);
wave_cap = optimvar("wave_cap", "LowerBound", 0, "UpperBound", wavePotential);

% Land area constraint for onshore renewables
% Assumes: PV = 150 MW/km² at 10% land use, Wind = 8.4 MW/km² at 10% land use
prob.Constraints.totalOnshoreRECap = (PVO_cap + PVA_cap)/(0.1 * 150) + wind_cap/(0.1 * 8.4) <= landArea;

%% Decision Variables - Conversion Technologies

% Heat Pump
heatPump_cap = optimvar("heatPump_cap", "LowerBound", 0);
heatPump_wel_prod = optimvar("heatPump_wel_prod", numHours, "LowerBound", 0);
heatPump_ambient_prod = optimvar("heatPump_ambient_prod", numHours, "LowerBound", 0);
% Electric heaters
elecHeat_cap = optimvar("elecHeat_cap", "LowerBound", 0);
elecHeat_prod = optimvar("elecHeat_prod", numHours, "LowerBound", 0);
% Multi-fuel gas turbine
gasTurbine_cap = optimvar("gasTurbine_cap", "LowerBound", 0);
gasTurbine_prod = optimvar("gasTurbine_prod", numHours, "LowerBound", 0);
gasTurbine_h2_cons = optimvar("gasTurbine_h2_cons", numHours, "LowerBound", 0);
gasTurbine_ch4_cons = optimvar("gasTurbine_ch4_cons", numHours, "LowerBound", 0);
% Electrolyser
wel_cap = optimvar("wel_cap", "LowerBound", 0);
wel_prod = optimvar("wel_prod", numHours, "LowerBound", 0);
% Direct air capture
dac_cap = optimvar("dac_cap", "LowerBound", 0);
dac_prod = optimvar("dac_prod", numHours, "LowerBound", 0);
% Ammonia
nh3_cap = optimvar("nh3_cap", "LowerBound", 0);
nh3_prod = optimvar("nh3_prod", numHours, "LowerBound", 0);
nh3_ramp_up = optimvar("nh3_ramp_up", numHours, "LowerBound", 0);
% Methanol
meoh_cap = optimvar("meoh_cap", "LowerBound", 0);
meoh_prod = optimvar("meoh_prod", numHours, "LowerBound", 0);
meoh_ramp_up = optimvar("meoh_ramp_up", numHours, "LowerBound", 0);
% Fischer-Tropsch
ft_cap = optimvar("ft_cap", "LowerBound", 0);
ft_prod = optimvar("ft_prod", numHours, "LowerBound", 0);
% Methanation
ch4_cap = optimvar("ch4_cap", "LowerBound", 0);
ch4_prod = optimvar("ch4_prod", numHours, "LowerBound", 0);

%% Decision Variables - Energy Storage Systems

% Batteries
battery_cap = optimvar("battery_cap", "LowerBound", 0);
battery_discharge = optimvar("battery_discharge", numHours, "LowerBound", 0);
battery_charge = optimvar("battery_charge", numHours, "LowerBound", 0);
battery_SOC = optimvar("battery_SOC", numHours, "LowerBound", 0);
% Thermal Energy Storage
tes_cap = optimvar("tes_cap", "LowerBound", 0);
tes_discharge = optimvar("tes_discharge", numHours, "LowerBound", 0);
tes_charge = optimvar("tes_charge", numHours, "LowerBound", 0);
tes_SOC = optimvar("tes_SOC", numHours, "LowerBound", 0);
% H2 Storage - lined rock cavern
h2_rockCavern_cap = optimvar("h2_rockCavern_cap", "LowerBound", 0);
h2_rockCavern_discharge = optimvar("h2_rockCavern_discharge", numHours, "LowerBound", 0);
h2_rockCavern_charge = optimvar("h2_rockCavern_charge", numHours, "LowerBound", 0);
h2_rockCavern_SOC = optimvar("h2_rockCavern_SOC", numHours, "LowerBound", 0);
% H2 Storage - underground pipe
h2_pipe_cap = optimvar("h2_pipe_cap", "LowerBound", 0);
h2_pipe_discharge = optimvar("h2_pipe_discharge", numHours, "LowerBound", 0);
h2_pipe_charge = optimvar("h2_pipe_charge", numHours, "LowerBound", 0);
h2_pipe_SOC = optimvar("h2_pipe_SOC", numHours, "LowerBound", 0);
% CO2 Storage
co2_storage_cap = optimvar("co2_storage_cap", "LowerBound", 0);
co2_storage_discharge = optimvar("co2_storage_discharge", numHours, "LowerBound", 0);
co2_storage_charge = optimvar("co2_storage_charge", numHours, "LowerBound", 0);
co2_storage_SOC = optimvar("co2_storage_SOC", numHours, "LowerBound", 0);
% Ammonia Storage
nh3_storage_cap = optimvar("nh3_storage_cap", "LowerBound", 0);
nh3_storage_discharge = optimvar("nh3_storage_discharge", numHours, "LowerBound", 0);
nh3_storage_charge = optimvar("nh3_storage_charge", numHours, "LowerBound", 0);
nh3_storage_SOC = optimvar("nh3_storage_SOC", numHours, "LowerBound", 0);
% Methanol Storage
meoh_storage_cap = optimvar("meoh_storage_cap", "LowerBound", 0);
meoh_storage_discharge = optimvar("meoh_storage_discharge", numHours, "LowerBound", 0);
meoh_storage_charge = optimvar("meoh_storage_charge", numHours, "LowerBound", 0);
meoh_storage_SOC = optimvar("meoh_storage_SOC", numHours, "LowerBound", 0);
% Liquid Fuel Storage
ft_storage_cap = optimvar("ft_storage_cap", "LowerBound", 0);
ft_storage_discharge = optimvar("ft_storage_discharge", numHours, "LowerBound", 0);
ft_storage_charge = optimvar("ft_storage_charge", numHours, "LowerBound", 0);
ft_storage_SOC = optimvar("ft_storage_SOC", numHours, "LowerBound", 0);
% CH4 Storage
ch4_storage_cap = optimvar("ch4_storage_cap", "LowerBound", 0);
ch4_storage_discharge = optimvar("ch4_storage_discharge", numHours, "LowerBound", 0);
ch4_storage_charge = optimvar("ch4_storage_charge", numHours, "LowerBound", 0);
ch4_storage_SOC = optimvar("ch4_storage_SOC", numHours, "LowerBound", 0);

%% Constraints

% Production + Storage Discharge >= Demand + Storage Charge
prob.Constraints.balance_fuels = [ch4_prod; nh3_prod; meoh_prod; ft_prod] + [ch4_storage_discharge; nh3_storage_discharge; meoh_storage_discharge; ft_storage_discharge] >= ...
     [ch4_demand+gasTurbine_ch4_cons; nh3_demand; meoh_demand; ft_demand] + [ch4_storage_charge; nh3_storage_charge; meoh_storage_charge; ft_storage_charge];

prob.Constraints.balance_h2 = wel_prod + h2_rockCavern_discharge + h2_pipe_discharge >= nh3_prod*h2_to_nh3 + ch4_prod*h2_to_ch4 + meoh_prod*h2_to_meoh + ft_prod*h2_to_ft + gasTurbine_h2_cons + h2_rockCavern_charge + h2_pipe_charge;

prob.Constraints.balance_co2 = dac_prod + co2_storage_discharge >= ch4_prod*co2_to_ch4 + meoh_prod*co2_to_meoh + ft_prod*co2_to_ft + co2_storage_charge;

prob.Constraints.balance_el = PVO_cap*pvo_prof + PVA_cap*pva_prof + wind_cap*wind_prof + wave_cap*wave_prof + gasTurbine_prod + battery_discharge >= ...
    heatPump_wel_prod/cop_wel + heatPump_ambient_prod/cop_ambient + elecHeat_prod*el_to_elecHeat + wel_prod*el_to_wel + nh3_prod*el_to_nh3 + dac_prod*el_to_dac + meoh_prod*el_to_meoh + ft_prod*el_to_ft + battery_charge;

prob.Constraints.balance_he = heatPump_wel_prod + heatPump_ambient_prod + elecHeat_prod  + nh3_prod*he_from_nh3 + ft_prod*he_from_ft + tes_discharge >= dac_prod * he_to_dac + tes_charge;

% Gas Turbine Fuel Balance
prob.Constraints.gasTurbine_fuel = gasTurbine_prod == gasTurbine_h2_cons*h2_to_gasTurbine + gasTurbine_ch4_cons*ch4_to_gasTurbine;

% Limit heat pump production using excess heat from electrolyzers
prob.Constraints.heatPump_wel_limit = heatPump_wel_prod <= wel_prod * he_from_wel;

%% Storage Operation Constraints

% Define max storage charge and discharge rates based on E/P ratios
prob.Constraints.battery_charge = battery_charge <= battery_cap/battery_EP_ratio;
prob.Constraints.battery_discharge = battery_discharge <= battery_cap/battery_EP_ratio;

prob.Constraints.h2_rockCavern_charge = h2_rockCavern_charge <= h2_rockCavern_cap/h2_rockCavern_EP_ratio;
prob.Constraints.h2_rockCavern_discharge = h2_rockCavern_discharge <= h2_rockCavern_cap/h2_rockCavern_EP_ratio;

prob.Constraints.h2_pipe_charge = h2_pipe_charge <= h2_pipe_cap/h2_pipe_EP_ratio;
prob.Constraints.h2_pipe_discharge = h2_pipe_discharge <= h2_pipe_cap/h2_pipe_EP_ratio;

prob.Constraints.co2_storage_charge = co2_storage_charge <= co2_storage_cap/co2_storage_EP_ratio;
prob.Constraints.co2_storage_discharge = co2_storage_discharge <= co2_storage_cap/co2_storage_EP_ratio;

prob.Constraints.nh3_storage_charge = nh3_storage_charge <= nh3_storage_cap/nh3_storage_EP_ratio;
prob.Constraints.nh3_storage_discharge = nh3_storage_discharge <= nh3_storage_cap/nh3_storage_EP_ratio;

prob.Constraints.meoh_storage_charge = meoh_storage_charge <= meoh_storage_cap/meoh_storage_EP_ratio;
prob.Constraints.meoh_storage_discharge = meoh_storage_discharge <= meoh_storage_cap/meoh_storage_EP_ratio;

% State Of Charge (SOC) difference for all hours except the first one
prob.Constraints.battery_SOC_diff = battery_SOC(2:numHours) == battery_SOC(1:numHours-1) + battery_charge(1:numHours-1) * charg_efficiency - battery_discharge(1:numHours-1) / discharg_efficiency;
prob.Constraints.battery_SOC_max = battery_SOC <= battery_cap;
prob.Constraints.battery_SOC_initial = battery_SOC(1) == battery_SOC(end) + battery_charge(end) * charg_efficiency - battery_discharge(end) / discharg_efficiency;

prob.Constraints.tes_SOC_diff = tes_SOC(2:numHours) == tes_SOC(1:numHours-1) + tes_charge(1:numHours-1) - tes_discharge(1:numHours-1);
prob.Constraints.tes_SOC_max = tes_SOC <= tes_cap;
prob.Constraints.tes_SOC_initial = tes_SOC(1) == tes_SOC(end) + tes_charge(end) - tes_discharge(end);

prob.Constraints.h2_rockCavern_SOC_diff = h2_rockCavern_SOC(2:numHours) == h2_rockCavern_SOC(1:numHours-1) + h2_rockCavern_charge(1:numHours-1) - h2_rockCavern_discharge(1:numHours-1);
prob.Constraints.h2_rockCavern_SOC_max = h2_rockCavern_SOC <= h2_rockCavern_cap;
prob.Constraints.h2_rockCavern_SOC_initial = h2_rockCavern_SOC(1) == h2_rockCavern_SOC(end) + h2_rockCavern_charge(end) - h2_rockCavern_discharge(end);

prob.Constraints.h2_pipe_SOC_diff = h2_pipe_SOC(2:numHours) == h2_pipe_SOC(1:numHours-1) + h2_pipe_charge(1:numHours-1) - h2_pipe_discharge(1:numHours-1);
prob.Constraints.h2_pipe_SOC_max = h2_pipe_SOC <= h2_pipe_cap;
prob.Constraints.h2_pipe_SOC_initial = h2_pipe_SOC(1) == h2_pipe_SOC(end) + h2_pipe_charge(end) - h2_pipe_discharge(end);

prob.Constraints.nh3_storage_SOC_diff = nh3_storage_SOC(2:numHours) == nh3_storage_SOC(1:numHours-1) + nh3_storage_charge(1:numHours-1) - nh3_storage_discharge(1:numHours-1);
prob.Constraints.nh3_storage_SOC_max = nh3_storage_SOC <= nh3_storage_cap;
prob.Constraints.nh3_storage_SOC_initial = nh3_storage_SOC(1) == nh3_storage_SOC(end) + nh3_storage_charge(end) - nh3_storage_discharge(end);

prob.Constraints.co2_storage_SOC_diff = co2_storage_SOC(2:numHours) == co2_storage_SOC(1:numHours-1) + co2_storage_charge(1:numHours-1) - co2_storage_discharge(1:numHours-1);
prob.Constraints.co2_storage_SOC_max = co2_storage_SOC <= co2_storage_cap;
prob.Constraints.co2_storage_SOC_initial = co2_storage_SOC(1) == co2_storage_SOC(end) + co2_storage_charge(end) - co2_storage_discharge(end);

prob.Constraints.ch4_storage_SOC_diff = ch4_storage_SOC(2:numHours) == ch4_storage_SOC(1:numHours-1) + ch4_storage_charge(1:numHours-1) - ch4_storage_discharge(1:numHours-1);
prob.Constraints.ch4_storage_SOC_max = ch4_storage_SOC <= ch4_storage_cap;
prob.Constraints.ch4_storage_SOC_initial = ch4_storage_SOC(1) == ch4_storage_SOC(end) + ch4_storage_charge(end) - ch4_storage_discharge(end);

prob.Constraints.meoh_storage_SOC_diff = meoh_storage_SOC(2:numHours) == meoh_storage_SOC(1:numHours-1) + meoh_storage_charge(1:numHours-1) - meoh_storage_discharge(1:numHours-1);
prob.Constraints.meoh_storage_SOC_max = meoh_storage_SOC <= meoh_storage_cap;
prob.Constraints.meoh_storage_SOC_initial = meoh_storage_SOC(1) == meoh_storage_SOC(end) + meoh_storage_charge(end) - meoh_storage_discharge(end);

prob.Constraints.ft_storage_SOC_diff = ft_storage_SOC(2:numHours) == ft_storage_SOC(1:numHours-1) + ft_storage_charge(1:numHours-1) - ft_storage_discharge(1:numHours-1);
prob.Constraints.ft_storage_SOC_max = ft_storage_SOC <= ft_storage_cap;
prob.Constraints.ft_storage_SOC_initial = ft_storage_SOC(1) == ft_storage_SOC(end) + ft_storage_charge(end) - ft_storage_discharge(end);

%% Technology Capacity and Operation Constraints

% Max production constraint
prob.Constraints.heatPump_cap = heatPump_wel_prod + heatPump_ambient_prod <= heatPump_cap;
prob.Constraints.elecHeat_cap = elecHeat_prod <= elecHeat_cap;
prob.Constraints.wel_cap = wel_prod <= wel_cap;
prob.Constraints.nh3_cap_max = nh3_prod <= nh3_cap;
prob.Constraints.dac_cap = dac_prod <= dac_cap;
prob.Constraints.ch4_cap = ch4_prod <= ch4_cap;
prob.Constraints.meoh_cap = meoh_prod <= meoh_cap;
prob.Constraints.ft_cap = ft_prod <= ft_cap;
prob.Constraints.gasTurbine_cap = gasTurbine_prod <= gasTurbine_cap;

% Minimum load constraints for chemical processes (technical limitations)
prob.Constraints.wel_cap_min = wel_prod   >= wel_cap * 0.2;  % 20% minimum load
prob.Constraints.nh3_cap_min = nh3_prod   >= nh3_cap * 0.5;  % 50% minimum load
prob.Constraints.meoh_cap_min = meoh_prod >= meoh_cap * 0.5; % 50% minimum load
prob.Constraints.ft_cap_min = ft_prod     >= ft_cap * 0.5;   % 50% minimum load

%% Ramping Constraints for Chemical Processes

% Ramp-up is defined as the positive difference between consecutive generation values
prob.Constraints.nh3_ramp_up_constraint = nh3_ramp_up(2:numHours) >= nh3_prod(2:numHours) - nh3_prod(1:numHours-1);
prob.Constraints.nh3_ramp_up_nonnegative = nh3_ramp_up >= 0;

prob.Constraints.meoh_ramp_up_constraint = meoh_ramp_up(2:numHours) >= meoh_prod(2:numHours) - meoh_prod(1:numHours-1);
prob.Constraints.meoh_ramp_up_nonnegative = meoh_ramp_up >= 0;

%% Cost Assumptions

% Helper function for annualised capital cost calculation
% Uses capital recovery factor with 7% discount rate and technology lifetime
getAnnualisedCAPEX = @(tech) getCostParam(tech, 'CAPEX') * 0.07 / (1 - (1 + 0.07)^-getCostParam(tech, 'Lifetime'));

capex = getAnnualisedCAPEX('PV fixed-tilt') * PVO_cap + ...
    getAnnualisedCAPEX('PV single-axis tracking') * PVA_cap + ...
    getAnnualisedCAPEX('Onshore Wind') * wind_cap + ...
    getAnnualisedCAPEX('Wave') * wave_cap + ...
    getAnnualisedCAPEX('Multi-fuel Gas Turbine') * gasTurbine_cap + ...
    getAnnualisedCAPEX('Battery') * battery_cap + ...
    getAnnualisedCAPEX('Battery Interface') * (battery_cap / battery_EP_ratio) + ...
    getAnnualisedCAPEX('Heat Pump') * heatPump_cap + ...
    getAnnualisedCAPEX('Electric Heater') * elecHeat_cap + ...
    getAnnualisedCAPEX('Thermal Energy Storage') * tes_cap + ...
    getAnnualisedCAPEX('Alkaline Water Electrolyser (BCS)') * wel_cap +...
    getAnnualisedCAPEX('H2 Storage - lined rock cavern') * h2_rockCavern_cap +...
    getAnnualisedCAPEX('H2 Storage - underground pipe') * h2_pipe_cap +...
    getAnnualisedCAPEX('Direct Air Capture') * dac_cap * numHours +...
    getAnnualisedCAPEX('CO2 Storage') * co2_storage_cap +...
    getAnnualisedCAPEX('Ammonia Synthesis') * nh3_cap +...
    getAnnualisedCAPEX('Ammonia Storage') * nh3_storage_cap +...
    getAnnualisedCAPEX('Methanation') * ch4_cap +...
    getAnnualisedCAPEX('CH4 Storage') * ch4_storage_cap +...
    getAnnualisedCAPEX('Methanol Synthesis') * meoh_cap +...
    getAnnualisedCAPEX('Methanol Storage') * meoh_storage_cap +...
    getAnnualisedCAPEX('Fischer-Tropsch') * ft_cap +...
    getAnnualisedCAPEX('Liquid Fuel Storage') * ft_storage_cap;

opex = getCostParam('PV fixed-tilt', 'OPEX') * PVO_cap + ...
    getCostParam('PV single-axis tracking', 'OPEX') * PVA_cap + ...
    getCostParam('Onshore Wind', 'OPEX') * wind_cap + ...
    getCostParam('Wave', 'OPEX') * wave_cap + ...
    getCostParam('Multi-fuel Gas Turbine', 'OPEX') * gasTurbine_cap + ...
    getCostParam('Battery', 'OPEX') * battery_cap + ...
    getCostParam('Battery Interface', 'OPEX') * (battery_cap / battery_EP_ratio) + ...
    getCostParam('Heat Pump', 'OPEX') * heatPump_cap + ...
    getCostParam('Electric Heater', 'OPEX') * elecHeat_cap + ...
    getCostParam('Thermal Energy Storage', 'OPEX') * tes_cap + ...
    getCostParam('Alkaline Water Electrolyser (BCS)', 'OPEX') * wel_cap + ...
    getCostParam('H2 Storage - lined rock cavern', 'OPEX') * h2_rockCavern_cap + ...
    getCostParam('H2 Storage - underground pipe', 'OPEX') * h2_pipe_cap + ...
    getCostParam('Direct Air Capture', 'OPEX') * dac_cap * numHours + ...
    getCostParam('CO2 Storage', 'OPEX') * co2_storage_cap + ...
    getCostParam('Ammonia Synthesis', 'OPEX') * nh3_cap + ...
    getCostParam('Ammonia Storage', 'OPEX') * nh3_storage_cap + ...
    getCostParam('Methanation', 'OPEX') * ch4_cap + ...
    getCostParam('CH4 Storage', 'OPEX') * ch4_storage_cap + ...
    getCostParam('Methanol Synthesis', 'OPEX') * meoh_cap + ...
    getCostParam('Methanol Storage', 'OPEX') * meoh_storage_cap + ...
    getCostParam('Fischer-Tropsch', 'OPEX') * ft_cap + ...
    getCostParam('Liquid Fuel Storage', 'OPEX') * ft_storage_cap;

rampingCost = getCostParam('Ammonia Synthesis', 'Ramp up') * sum(nh3_ramp_up) + getCostParam('Methanol Synthesis', 'Ramp up') * sum(meoh_ramp_up);

prob.Objective = capex + opex + rampingCost;
%% Solve the optimization problem
opts = optimoptions('linprog', 'Algorithm','interior-point');
tic
[sol, fval] = solve(prob, 'Options', opts);
toc
% sol contains the optimisation solution variables
% fval is the objective function value, i.e., the system cost
%% Post-processing
results = {
    'System Cost', '[MEUR]', fval/10^3;
    'PV fixed-tilt capacity', '[MW]', sol.PVO_cap;
    'PV single-axis capacity', '[MW]', sol.PVA_cap;
    'Wind capacity', '[MW]', sol.wind_cap;
    'Wave capacity', '[MW]', sol.wave_cap;
    'Gas Turbine capacity', '[MW]', sol.gasTurbine_cap;
    'Battery capacity', '[MWh]', sol.battery_cap;
    'Battery Interface', '[MW]', sol.battery_cap/battery_EP_ratio;
    'Heat pump capacity', '[MW]', sol.heatPump_cap;
    'Electric Heater capacity', '[MW]', sol.elecHeat_cap;
    'TES capacity', '[MWh]', sol.tes_cap;
    'Electrolyser', '[MW]', sol.wel_cap;
    'H2 Storage - lined rock cavern', '[MWh]', sol.h2_rockCavern_cap;
    'H2 Storage - underground pipe', '[MWh]', sol.h2_pipe_cap;
    'DAC capacity', '[t/h]', sol.dac_cap;
    'CO2 Storage', '[t]', sol.co2_storage_cap;
    'Methanation', '[MW]', sol.ch4_cap;
    'CH4 Storage', '[MWh]', sol.ch4_storage_cap;
    'Ammonia synthesis', '[MW]', sol.nh3_cap;
    'Ammonia storage', '[MWh]', sol.nh3_storage_cap;
    'Methanol synthesis', '[MW]', sol.meoh_cap;
    'Methanol storage', '[MWh]', sol.meoh_storage_cap;
    'FT', '[MW]', sol.ft_cap;
    'Liquid Fuel Storage', '[MWh]', sol.ft_storage_cap;
    '','','Output';
    'PV fixed-tilt electricity', '[MWh]', sum(pvo_prof)*sol.PVO_cap;
    'PV single-axis electricity', '[MWh]', sum(pva_prof)*sol.PVA_cap;
    'Onshore Wind electricity', '[MWh]', sum(wind_prof)*sol.wind_cap;
    'Wave electricity', '[MWh]', sum(wave_prof)*sol.wave_cap;
    'Gas Turbine electricity', '[MWh]', sum(sol.gasTurbine_prod);
    'Heat Pump heat', '[MWh]', sum(sol.heatPump_wel_prod + sol.heatPump_ambient_prod);
    'Electric Heater heat', '[MWh]', sum(sol.elecHeat_prod);
    'Electrolyser production', '[MWh,H2]', sum(sol.wel_prod);
    'DAC production', '[t]', sum(sol.dac_prod);
    'CH4 production', '[MWh,CH4]', sum(sol.ch4_prod);
    'NH3 production', '[MWh,NH3]', sum(sol.nh3_prod);
    'MeOH production', '[MWh,MeOH]', sum(sol.meoh_prod);
    'FT production', '[MWh,FT]', sum(sol.ft_prod);
    '','','Electricity in';
    'Heat Pump electricity consumption', '[MWh]', sum(sol.heatPump_wel_prod/cop_wel + sol.heatPump_ambient_prod/cop_ambient);
    'Electric Heater electricity consumption', '[MWh]', sum(sol.elecHeat_prod);
    'Electrolyser electricity consumption', '[MWh]', sum(sol.wel_prod)*el_to_wel;
    'DAC electricity consumption', '[MWh]', sum(sol.dac_prod)*el_to_dac;
    'CH4 electricity consumption', '[MWh]', 0;
    'NH3 electricity consumption', '[MWh]', sum(sol.nh3_prod) * el_to_nh3;
    'MeOH electricity consumption', '[MWh]', sum(sol.meoh_prod) * el_to_meoh;
    'FT electricity consumption', '[MWh]', sum(sol.ft_prod) * el_to_ft;
    '','','Gas in';
    'Gas Turbine CH4 consumption', '[MWh]', sum(sol.gasTurbine_ch4_cons);
    '','','Hydrogen in';
    'Gas Turbine H2 consumption', '[MWh]', sum(sol.gasTurbine_h2_cons);
    'CH4 H2 consumption', '[MWh]', sum(sol.ch4_prod) * h2_to_ch4;
    'NH3 H2 consumption', '[MWh]', sum(sol.nh3_prod) * h2_to_nh3;
    'MeOH H2 consumption', '[MWh]', sum(sol.meoh_prod) * h2_to_meoh;
    'FT H2 consumption', '[MWh]', sum(sol.ft_prod) * h2_to_ft;
    '','','CO2 in';
    'CH4 CO2 consumption', '[t]', sum(sol.ch4_prod) * co2_to_ch4;
    'NH3 CO2 consumption', '[t]', 0;
    'MeOH CO2 consumption', '[t]', sum(sol.meoh_prod) * co2_to_meoh;
    'FT CO2 consumption', '[t]', sum(sol.ft_prod) * co2_to_ft;
    '', '', 'Annual Inv';
    'PV fixed-tilt', '[€]', 1000 * getAnnualisedCAPEX('PV fixed-tilt') * sol.PVO_cap;
    'PV single-axis', '[€]', 1000 * getAnnualisedCAPEX('PV single-axis tracking') * sol.PVA_cap;
    'Wind power', '[€]', 1000 * getAnnualisedCAPEX('Onshore Wind') * sol.wind_cap;
    'Wave power', '[€]', 1000 * getAnnualisedCAPEX('Wave') * sol.wave_cap;
    'Gas Turbine', '[€]', 1000 * getAnnualisedCAPEX('Multi-fuel Gas Turbine') * sol.gasTurbine_cap;
    'Battery capacity', '[€]', 1000 * getAnnualisedCAPEX('Battery') * sol.battery_cap;
    'Battery Interface', '[€]', 1000 * getAnnualisedCAPEX('Battery Interface') * sol.battery_cap/battery_EP_ratio;
    'Heat Pump', '[€]', 1000 * getAnnualisedCAPEX('Heat Pump') * sol.heatPump_cap;
    'Electric Heater', '[€]', 1000 * getAnnualisedCAPEX('Electric Heater') * sol.elecHeat_cap;
    'TES', '[€]', 1000 * getAnnualisedCAPEX('Thermal Energy Storage') * sol.tes_cap;
    'Electrolyser', '[€]', 1000 * getAnnualisedCAPEX('Alkaline Water Electrolyser (BCS)') * sol.wel_cap;
    'H2 Storage - lined rock cavern', '[€]', 1000 * getAnnualisedCAPEX('H2 Storage - lined rock cavern') * sol.h2_rockCavern_cap;
    'H2 Storage - underground pipe', '[€]', 1000 * getAnnualisedCAPEX('H2 Storage - underground pipe') * sol.h2_pipe_cap;
    'DAC', '[€]', 1000 * getAnnualisedCAPEX('Direct Air Capture') * sol.dac_cap * numHours;
    'CO2 Storage', '[€]', 1000 * getAnnualisedCAPEX('CO2 Storage') * sol.co2_storage_cap;
    'Methanation', '[€]', 1000 * getAnnualisedCAPEX('Methanation') * sol.ch4_cap;
    'CH4 Storage', '[€]', 1000 * getAnnualisedCAPEX('CH4 Storage') * sol.ch4_storage_cap;
    'Ammonia synthesis', '[€]', 1000 * getAnnualisedCAPEX('Ammonia Synthesis') * sol.nh3_cap;
    'Ammonia storage', '[€]', 1000 * getAnnualisedCAPEX('Ammonia Storage') * sol.nh3_storage_cap;
    'Methanol synthesis', '[€]', 1000 * getAnnualisedCAPEX('Methanol Synthesis') * sol.meoh_cap;
    'Methanol storage', '[€]', 1000 * getAnnualisedCAPEX('Methanol Storage') * sol.meoh_storage_cap;
    'FT', '[€]', 1000 * getAnnualisedCAPEX('Fischer-Tropsch') * sol.ft_cap;
    'Liquid Fuel Storage', '[€]', 1000 * getAnnualisedCAPEX('Liquid Fuel Storage') * sol.ft_storage_cap;
    '', '', 'Opex';
    'PV fixed-tilt', '[€]', 1000 * getCostParam('PV fixed-tilt', 'OPEX') * sol.PVO_cap;
    'PV single-axis', '[€]', 1000 * getCostParam('PV single-axis tracking', 'OPEX') * sol.PVA_cap;
    'Wind power', '[€]', 1000 * getCostParam('Onshore Wind', 'OPEX') * sol.wind_cap;
    'Wave power', '[€]', 1000 * getCostParam('Wave', 'OPEX') * sol.wave_cap;
    'Gas Turbine', '[€]', 1000 * getCostParam('Multi-fuel Gas Turbine', 'OPEX') * sol.gasTurbine_cap;
    'Battery capacity', '[€]', 1000 * getCostParam('Battery', 'OPEX') * sol.battery_cap;
    'Battery Interface', '[€]', 1000 * getCostParam('Battery Interface', 'OPEX') * (sol.battery_cap / battery_EP_ratio);
    'Heat Pump', '[€]', 1000 * getCostParam('Heat Pump', 'OPEX') * sol.heatPump_cap;
    'Electric Heater', '[€]', 1000 * getCostParam('Electric Heater', 'OPEX') * sol.elecHeat_cap;
    'TES', '[€]', 1000 * getCostParam('Thermal Energy Storage', 'OPEX') * sol.tes_cap;
    'Electrolyser', '[€]', 1000 * getCostParam('Alkaline Water Electrolyser (BCS)', 'OPEX') * sol.wel_cap;
    'H2 Storage - lined rock cavern', '[€]', 1000 * getCostParam('H2 Storage - lined rock cavern', 'OPEX') * sol.h2_rockCavern_cap;
    'H2 Storage - underground pipe', '[€]', 1000 * getCostParam('H2 Storage - underground pipe', 'OPEX') * sol.h2_pipe_cap;
    'DAC', '[€]', 1000 * getCostParam('Direct Air Capture', 'OPEX') * sol.dac_cap * numHours;
    'CO2 Storage', '[€]', 1000 * getCostParam('CO2 Storage', 'OPEX') * sol.co2_storage_cap;
    'Methanation', '[€]', 1000 * getCostParam('Methanation', 'OPEX') * sol.ch4_cap;
    'CH4 Storage', '[€]', 1000 * getCostParam('CH4 Storage', 'OPEX') * sol.ch4_storage_cap;
    'Ammonia synthesis', '[€]', 1000 * getCostParam('Ammonia Synthesis', 'OPEX') * sol.nh3_cap;
    'Ammonia storage', '[€]', 1000 * getCostParam('Ammonia Storage', 'OPEX') * sol.nh3_storage_cap;
    'Methanol synthesis', '[€]', 1000 * getCostParam('Methanol Synthesis', 'OPEX') * sol.meoh_cap;
    'Methanol storage', '[€]', 1000 * getCostParam('Methanol Storage', 'OPEX') * sol.meoh_storage_cap;
    'FT', '[€]', 1000 * getCostParam('Fischer-Tropsch', 'OPEX') * sol.ft_cap;
    'Liquid Fuel Storage', '[€]', 1000 * getCostParam('Liquid Fuel Storage', 'OPEX') * sol.ft_storage_cap;
    };
end