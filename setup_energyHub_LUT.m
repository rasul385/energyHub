% energyHub-LUT setup script
% =====================================

%% Reading Input Data
% Load financial and technical assumptions from Excel file
assumptionsTable = readtable("Financial and Technical Assumptions.xlsx", 'ReadVariableNames', true, 'Range', 'A1:I132', 'Sheet','Main'); clc

%% New Zealand
location = 'newZealand'; disp(location)
profiles = readtable("profilesNewZealand.csv");

nh3_demand = (395.9 + 211.6) * 0.39*10^6; %MWh
meoh_demand = (1340.4 + 870.8) * 0.39*10^6; %MWh
ft_demand = (1613 + 244) * 0.39*10^6; %MWh
ch4_demand = (872.7 + 254.6) * 0.39*10^6; %MWh

% Update CAPEX and OPEX values for wave power technology in the year 2050
assumptionsTable.x2050(matches(assumptionsTable.Tech, 'Wave') & matches(assumptionsTable.Comp, 'CAPEX')) = 2020;
assumptionsTable.x2050(matches(assumptionsTable.Tech, 'Wave') & matches(assumptionsTable.Comp, 'OPEX')) = 2020*0.024;

for scenario = {'Wave', 'Wave-PV-Wind'}
    switch scenario{1}
        case 'Wave'
            landArea = 0; % block onshore RE
            sheetName = 'Wave';
        case 'Wave-PV-Wind'
            landArea = 31219; %km2
            sheetName = 'Wave-PV-Wind';
    end
    disp(sheetName)
    wavePotential = 646 * 10^3; %MW
    [results, sol] = energyHub_LUT(profiles, assumptionsTable, nh3_demand, ch4_demand, meoh_demand, ft_demand, wavePotential, landArea);
    writecell(results, [location '_energyHub-LUT.xlsx'], 'Sheet', sheetName)
    save([location '_' sheetName '_output.mat'], 'sol')
end



%% Chile
location = 'chile'; disp(location)
profiles = readtable("profilesChile.csv");

ch4_demand = (872.7 + 254.6) * 0.067 * 10^6; %MWh
nh3_demand = (395.9 + 211.6) * 0.067 * 10^6; %MWh
meoh_demand = (1340.4 + 870.8) * 0.067 * 10^6; %MWh
ft_demand = (1613 + 244) * 0.067 * 10^6; %MWh

% Update CAPEX and OPEX values for wave power technology in the year 2050
assumptionsTable.x2050(matches(assumptionsTable.Tech, 'Wave') & matches(assumptionsTable.Comp, 'CAPEX')) = 1852;
assumptionsTable.x2050(matches(assumptionsTable.Tech, 'Wave') & matches(assumptionsTable.Comp, 'OPEX')) = 1852*0.024;

for scenario = {'Wave', 'Wave-PV-Wind'}
    switch scenario{1}
        case 'Wave'
            landArea = 0; % km2 = block onshore RE
            sheetName = 'Wave';
        case 'Wave-PV-Wind'
            landArea = 132291; %km2
            sheetName = 'Wave-PV-Wind';
    end
    disp(sheetName)
    wavePotential = 112 * 10^3; % MW
    [results, sol] = energyHub_LUT(profiles, assumptionsTable, nh3_demand, ch4_demand, meoh_demand, ft_demand, wavePotential, landArea);
    writecell(results, [location '_energyHub-LUT.xlsx'], 'Sheet', sheetName)
    save([location '_' sheetName '_output.mat'], 'sol')
end



%% Ireland
location = 'ireland'; disp(location)
profiles = readtable("profilesIreland.csv");

ch4_demand = (872.7 + 254.6) * 0.19 * 10^6; %MWh
nh3_demand = (395.9 + 211.6) * 0.19 * 10^6; %MWh
meoh_demand = (1340.4 + 870.8) * 0.19 * 10^6; %MWh
ft_demand = (1613 + 244) * 0.19 * 10^6; %MWh

% Update CAPEX and OPEX values for wave power technology in the year 2050
assumptionsTable.x2050(matches(assumptionsTable.Tech, 'Wave') & matches(assumptionsTable.Comp, 'CAPEX')) = 1970;
assumptionsTable.x2050(matches(assumptionsTable.Tech, 'Wave') & matches(assumptionsTable.Comp, 'OPEX')) = 1970*0.024;

for scenario = {'Wave', 'Wave-PV-Wind'}
    switch scenario{1}
        case 'Wave'
            landArea = 0; % km2 = block onshore RE
            sheetName = 'Wave';
        case 'Wave-PV-Wind'
            landArea = 84421; %km2
            sheetName = 'Wave-PV-Wind';
    end
    disp(sheetName)
    wavePotential = 393 * 10^3; %MW
    [results, sol] = energyHub_LUT(profiles, assumptionsTable, nh3_demand, ch4_demand, meoh_demand, ft_demand, wavePotential, landArea);
    writecell(results, [location '_energyHub-LUT.xlsx'], 'Sheet', sheetName)
    save([location '_' sheetName '_output.mat'], 'sol')
end



%% Kerguelen
%{
location = 'kerguelen'; disp(location)
profiles = readtable("profilesKerguelen.csv");

nh3_demand = (395.9 + 211.6) * 0.29 * 10^6; %MWh
meoh_demand = (1340.4 + 870.8) * 0.29 * 10^6; %MWh
ft_demand = (1613 + 244) * 0.29 * 10^6; %MWh
ch4_demand = (872.7 + 254.6) * 0.29 * 10^6; %MWh

% Update CAPEX and OPEX values for wave power technology in the year 2050
assumptionsTable.x2050(matches(assumptionsTable.Tech, 'Wave') & matches(assumptionsTable.Comp, 'CAPEX')) = 1973;
assumptionsTable.x2050(matches(assumptionsTable.Tech, 'Wave') & matches(assumptionsTable.Comp, 'OPEX')) = 1973*0.024;

for scenario = {'Wave', 'Wave-PV-Wind'}
    switch scenario{1}
        case 'Wave'
            landArea = 0; % km2 = block onshore RE
            wavePotential = 426 * 10^3; % MW
            sheetName = 'Wave';
        case 'Wave-PV-Wind'
            landArea = 7215; % km2
            wavePotential = 426 * 10^3; % MW
            sheetName = 'Wave-PV-Wind';
    end
    disp(sheetName)
    [results, sol] = energyHub_LUT(profiles, assumptionsTable, nh3_demand, ch4_demand, meoh_demand, ft_demand, wavePotential, landArea);
    writecell(results, [location '_energyHub-LUT.xlsx'], 'Sheet', sheetName)
    save([location '_' sheetName '_output.mat'], 'sol')
end
%}

