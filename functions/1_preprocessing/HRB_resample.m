function [EEG] = HRB_resample(EEG, opt)
% HRB_RESAMPLE - Resample an EEG dataset. Based on EEGLAB functions.
%
% Examples:
%     >>> [EEG] = HRB_resample(EEG)
%     >>> [EEG] = HRB_resample(EEG, 'key', val) 
%     >>> [EEG] = HRB_resample(EEG, key=val) 
%
% Parameters:
%    EEG (struct): EEG struct using EEGLAB structure system
%
% Other Parameters:
%    Frequency (double): The new resampled frequency
%    Save (logical): Whether to save or not the resampled EEG.
%
% Returns:
%    EEG (struct): resampled EEG struct using EEGLAB structure system
% 
% See also: 
%    EEGLAB, POP_RESAMPLE

% Authors: Alessandro Tonin, IRCCS San Camillo Hospital, 2024

    arguments (Input)
        EEG struct
        % Optional
        opt.Frequency double
        opt.EEGLAB (1,:) cell
        % Save options
        opt.Save logical
        opt.SaveName string
        opt.OutputFolder string
        % Log options
        opt.LogEnabled logical
        opt.LogLevel double {mustBeInteger,mustBeInRange(opt.LogLevel,0,6)}
        opt.LogToFile logical
        opt.LogFileDir string
        opt.LogFileName string
    end

    %% Constants
    module = "preprocessing";
    
    %% Parsing arguments
    config = HRB_loadConfig(module, "resample", opt);

    %% Logger
    logConfig = HRB_loadConfig(module, "logging", opt);
    log = HRB_loggerSetUp(module, logConfig);
    
    %% Resampling
    log.info("Resampling")

    fs_old = EEG.srate;
    log.info(sprintf("Old sampling rate: %.1f", fs_old))

    EEG = pop_resample( EEG, config.Frequency, config.EEGLAB{:});
    log.info(sprintf("New sampling rate: %.1f", config.Frequency))

    %% Save
    if config.Save
        logParams = unpackStruct(logConfig);
        HRB_saveData(EEG, "Name", config.SaveName, "Folder", module, "OutputFolder", config.OutputFolder, logParams{:});
    end

end

