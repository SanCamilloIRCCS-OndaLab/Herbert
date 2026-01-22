function [EEG] = SPMA_iclabel(EEG, opt)
% SPMA_iclabel labels independnt components using ICLabel
%
% Examples:
%   >>> EEG = SPMA_iclabel(EEG)
%   >>> EEG = SPMA_iclabel(EEG, 'key', val)
%   >>> EEG = SPMA_iclabel(EEG, key = val)
%
% Parameters:
%       EEG (struct): EEG struct using EEGLAB struct system. ICs weights must
%       have been computed
%
% Other parameters:
%       Version (string): 'default', 'lite', 'beta'
%       Save (logical): whether to save or not the dataset with labeled
%       components
%
% See also: EEGLAB, pop_iclabel
%
% Authors: Ettore Napoli, University of Bologna, 2026

    arguments (Input)
        EEG struct
        % Optional
        opt.Version string {mustBeMember(opt.Version, ["default", "lite", "beta"])}
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
    
    %% Parsing arguments
    config = SPMA_loadConfig(module, "iclabel", opt);
    
    %% Logger
    logConfig = SPMA_loadConfig(module, "logging", opt);
    log = SPMA_loggerSetUp(module, logConfig);
    
    %% Check prerequisites
    if isempty(EEG.icaweights)
        error('SPMA: No ICA', 'No ICs weights found for the current EEG structure.')
    end
    
    %% Run ICLabel
    log.info(sprintf("Starting ICLabel classification with versino %s", config.Version));

    %% Check prerequisites
    if isempty(EEG.icaweights)
        msg = 'SPMA Error: EEG structure does not contain ICA weights. Run SPMA_runica first.';
        log.error(msg);
        error('SPMA:NoICA', msg);
    end
    
    try
        EEG = pop_iclabel(EEG, char(config.Version));
    
    catch ME
        % If something goes wrong, log it and rethrow the error
        log.error(sprintf("Error during IClabel classification: %s", ME.message));
    end
    
    %% Save
    if config.Save
        logParams = unpackStruct(logConfig);
        SPMA_saveData(EEG, "Name", config.SaveName, "Folder", module,"OutputFolder", config.OutputFolder, logParams{:});
    end
end


