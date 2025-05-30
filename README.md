# energyHub-LUT

A MATLAB-based optimisation framework for designing and operating energy hubs that combine renewable energy sources with Power-to-X (PtX) technologies for synthetic fuel production.

![image](https://github.com/rasul385/energyHub/blob/main/energy-Hub%20LUT%20Schematic.png)

## Usage
The core of the project is the energyHub_LUT.m function. Before running the function, you need to prepare the input data:
- **profiles**: A structure containing hourly capacity factors for renewable energy sources. This typically includes 8760 data points for a full year.
  - profiles.wind: Wind power capacity factors [8760x1]
  - profiles.pvo: PV fixed-tilt capacity factors [8760x1]
  - profiles.pva: PV single-axis tracking capacity factors [8760x1]
  - profiles.wave: Wave power capacity factors [8760x1]
- **assumptionsTable**: A MATLAB table containing technology cost data, efficiencies, and technical parameters as in the "Financial and Technical Assumptions.xlsx" file
- **nh3_demand**: Annual ammonia demand [MWh/year]
- **ch4_demand**: Annual synthetic methane demand [MWh/year]
- **meoh_demand**: Annual methanol demand [MWh/year]
- **ft_demand**: Annual Fischer-Tropsch liquid demand [MWh/year]
- **wavePotential**: Maximum available wave energy capacity [MW]
- **landArea**: Available land area for onshore renewables [km²]

Example usage is shown in setup_energyHub_LUT.m file.

## Citing energyHub-LUT
If you use energyHub-LUT for your research, we would appreciate it if you would cite the following paper:
