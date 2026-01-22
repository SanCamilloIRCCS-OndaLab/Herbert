function [EEG] = SPMA_icflag(EEG, opt)
% SPMA_icflag flags artifactual components based on ICLabel
%
% Usage:
%   >>> EEG = SPMA_icflag(EEG, 'Muscle', [0.9, 1], 'Eye', [0.9, 1])
%
% Parameters:
%   EEG (struct): EEG struct using EEGLAB struct system. ICs weights must
%   have been computed and labeled through SPMA_iclabel
%
% Other Parameters:
%   Threshold parameters (Name-value): Each parameter accept a [min max]
%   vector (1x2 double). Components with probabilities inside this range
%   will be flagged. Default is [NaN NaN]. 
%   The parameters are as follow: Brain, Muscle, Eye, Heart,
%   LineNoise,ChannelNoise, Other. 
%
%   Save (logical): Whether to save the dataset with the flagged
%   components.
%
% See also: EEGLAB, pop_iclabel, pop_icflag
%
% Authors: Ettore Napoli, University of Bologna, 2026

    arguments(Input)
        EEG struct
        % Optional
        opt.Brain           (1, 2) double = [0 0]
        opt.Muscle          (1, 2) double = [0 0]
        opt.Eye             (1, 2) double = [0 0]
        opt.Heart           (1, 2) double = [0 0]
        opt.LineNoise       (1, 2) double = [0 0]
        opt.ChannelNoise    (1, 2) double = [0 0]
        opt.Other           (1, 2) double = [0 0]
        % Save Options
        opt.Save logical
        opt.SaveName string
        opt.OutputFolder string
        % Log Options
        opt.LogEnabled logical
        opt.LogLevel double {mustBeInteger, mustBeInRange(opt.LogLevel, 0,6)}
        opt.LogToFile logical
        opt.LogFileDir string
        opt.LogFileName string
    end

    %% Constants
    module = "preprocessing";

    %% Parsing Arguments
    config = SPMA_loadConfig(module, "icflag", opt);

    %% Logger
    logConfig = SPMA_loadConfig(module, "logging", opt);
    log = SPMA_loggerSetUp(module, logConfig);

    %% Check prerequisites
    if isempty(EEG.icaweights)
        error("SPMA: No ICA" , "No ICs weights found for the current EEG structure.")
    end

    if isempty(EEG.etc.ic_classification.ICLabel)
        error("SPMA: No Classification", "No ICLabel classification found")
    end

    %% Build Threshold Matrix
    % pop_icflag expects a 7x2 matrix in a specific order: 
    % 1.Brain, 2.Muscle, 3.Eye, 4.Heart, 5.LineNoise, 6.ChannelNoise,
    % 7.Other

    thresh_matrix = [
        config.Brain;
        config.Muscle;
        config.Eye;
        config.Heart;
        config.LineNoise;
        config.ChannelNoise;
        config.Other
        ];

    try
        [EEG, ~] = pop_icflag(EEG, thresh_matrix)
        
        % Log rejection count
        if isfield(EEG, 'reject') && isfield(EEG.reject, 'gcompreject')
            nRejected = sum(EEG.reject.gcompreject);
            log.info(sprintf('%d components flagged for rejection', nRejected));
        end

    catch ME
        % if something goes wrong log and rethrow error
        log.error(sprintf("Error during ICFlag execution: %s", ME.message));
    end

    %% Save
    if config.Save
        logParams = unpackStruct(logConfig);
        SPMA_saveData(EEG, "Name", config.SaveName, "Folder", module, "OutputFolder", config.OutputFolder, logParams{:});
    end
end




