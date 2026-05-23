function [EEG] = HRB_ica(EEG, opt)
% HRB_ica runs the full ica pipeline:
% 1. Decomposition (RunICA)
% 2. Classification (ICLabel)
% 3. Flagging (ICFlag)
% 4. Removal (SubComp) with optional Visual Check
%
% Usage:
%   >>> EEG = HRB_ica(EEG, 'Visualize', true);
%   >>> EEG = HRB_ica(EEG, 'Extended', 1, 'Muscle', [0.8 1]);
%
% Authors: Ettore Napoli, University of Bologna, 2026

    arguments(Input)
        EEG struct
        % Optional parameter for HRB_runica
        opt.Extended double = 1
        opt.Seed double 
        % Optional parameter for HRB_iclabel
        opt.Version string {mustBeMember(opt.Version, ["default", "lite", "beta"])} = "default"
        % Optional parameters for HRB_icflag
        opt.Brain           (1, 2) double = [0 0]
        opt.Muscle          (1, 2) double = [0 0]
        opt.Eye             (1, 2) double = [0 0]
        opt.Heart           (1, 2) double = [0 0]
        opt.LineNoise       (1, 2) double = [0 0]
        opt.ChannelNoise    (1, 2) double = [0 0]
        opt.Other           (1, 2) double = [0 0]
        % Optional intermediate save option
        opt.SaveWeights logical = false      % Save dataset with ICA weights BEFORE removal
        opt.SaveWeightsName string = ""      % Name for the intermediate file
        % Optional parameter for HRB_subcomp
        opt.Visualize logical = false
        % Save Options
        opt.Save logical
        opt.SaveName string
        opt.OutputFolder string
        % Log options
        opt.LogEnabled logical
        opt.LogLevel double {mustBeInteger, mustBeInRange(opt.LogLevel, 0,6)}
        opt.LogToFile logical
        opt.LogFileDir string
        opt.LogFileName string
    end
    
    %% Constants
    module = "preprocessing";

    %% Parsing Arguments
    config = HRB_loadConfig(module, "ica", opt);

    %% Logger
    logConfig = HRB_loadConfig(module, "logging", opt);
    log = HRB_loggerSetUp(module, logConfig);

    %% Consistency check for output folder
    if config.OutputFolder == ""
        % Generate Timestamp
        timestamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
        
        config.OutputFolder = fullfile("output", timestamp);
    end
    
    % Create output folder
    if ~exist(config.OutputFolder, 'dir')
        mkdir(config.OutputFolder);
    end

    %% 1. Run ICA
    log.info("Initiating ICA pipeline")
    log.info("Step 1/4: Running ICA decomposition");
    EEG = HRB_runica(EEG, ...
        'Extended', config.Extended, ...
        'Seed', config.Seed, ...
        'Save', false, ... 
        'LogEnabled', logConfig.LogEnabled, 'LogLevel', logConfig.LogLevel);

    %% 2. ICLabel
    log.info("Step 2/4: Labeling Components")
    EEG = HRB_iclabel(EEG, ...
        'Version', config.Version, ...
        'Save', false, ...
        'LogEnabled', logConfig.LogEnabled, ...
        'LogLevel', logConfig.LogLevel);

    %% 3. ICFlag
    log.info("Step 3/4: Flagging Components")
    EEG = HRB_icflag(EEG, ...
        'Brain', config.Brain, ...
        'Muscle', config.Muscle, ...
        'Eye', config.Eye, ...
        'Heart',config.Heart, ...
        'LineNoise', config.LineNoise, ...
        'ChannelNoise',config.ChannelNoise, ...
        'Other', config.Other, ...
        'Save', false, ...
        'LogEnabled',logConfig.LogEnabled, ...
        'LogLevel', logConfig.LogLevel);

    %% Intermediate Save Point
    if config.SaveWeights
        log.info("Creating intermediate save before rejection");

        if config.SaveWeightsName == ""
            mid_name = EEG.setname + "_ica_weights";
        else
            mid_name = config.SaveWeightsName;
        end

        % Save
        logParams = unpackStruct(logConfig);
        HRB_saveData(EEG, "Name", mid_name, "Folder", module, "OutputFolder", config.OutputFolder, logParams{:});
    end

    %% 4. Components Subtraction
    log.info("Step 4/4: Removing components");
    
    % Prepare Save name
    if config.SaveName == ""
        final_name = EEG.setname + "_ICRej";
    else
        final_name = config.SaveName;
    end
    
    % Run HRB_subcomp
    EEG = HRB_subcomp(EEG, ...
        'Visualize', config.Visualize, ...
        'Components', [], ... 
        'Save', config.Save, ... 
        'SaveName', final_name, ...
        'OutputFolder', config.OutputFolder, ...
        'LogEnabled', logConfig.LogEnabled, 'LogLevel', logConfig.LogLevel);

    log.info("ICA pipeline completed");
end




