% HRB_LOADCONFIG - Load the configurations for a specific function. It
% merges the default configurations with the custom. This function is
% called at the beginning of every function of the toolbox.
%
% Usage:
%     >> [config] = HRB_loadConfig(module, func);
%     >> [config] = HRB_loadConfig(module, func, customConfig);
%
% Inputs:
%   module = [struct] The module of the function you want to load
%   func = [string] The function you want to load from the specific module.
%           If the function is not present in the module it will load the whole
%           module.
%
% Optional inputs
%   customConfig  = [struct] The custom configuration for the specified
%                    function. These configuration will be merged with the
%                    default configuration values for that function.
%
% Outputs:
%    config = [struct] Structure with the configuration of the requested
%               function
%
% Authors: Alessandro Tonin, IRCCS San Camillo Hospital, 2024
% 
% See also: HRB_DEFAULTCONFIG, MERGESTRUCT


function config = HRB_loadConfig(module, func, customConfig)
    arguments
        module (1,1) string {mustBeMember(module, ["general", "preprocessing", "headmodel", "source", "sourceestimation", "connectivity", "network"])}
        func (1,1) string = ""
        customConfig (1,1) struct = struct()
    end

    % Load all default config
    config = HRB_defaultConfig;

    % Extract only the desired module
    switch module
        case "general"
            config = config.general;
        case "preprocessing"
            config = config.preprocessing;
        case "headmodel"
            config = config.headModel;
        case {"source", "sourceestimation"}
            config = config.sourceEstimation;
        case "connectivity"
            config = config.connectivity;
        case "network"
            config = config.network;
    end

    if isfield(config, func)
        config = config.(func);
        % else ignore
    end

    config = mergeStruct(config, customConfig);

end

