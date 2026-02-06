function [EEG] = HRB_selectTime(EEG, opt)
% HRB_SELECTTIME - Select a time window from an EEG dataset.
%
% Examples:
%     >>> [EEG] = HRB_selectTime(EEG)
%     >>> [EEG] = HRB_selectTime(EEG, 'key', val) 
%     >>> [EEG] = HRB_selectTime(EEG, key=val) 
%
% Parameters:
%    EEG (struct): EEG struct using EEGLAB structure system
%
% Other Parameters:
%    AfterStart (double): Seconds to select after the start of the
%                   recording
%    BeforeEnd (double): Seconds to select before the end of the
%                   recording
%
% Returns:
%    EEG (struct): EEG struct using EEGLAB structure system
% 
% See also: 
%    EEGLAB, POP_SELECT

% Authors: Alessandro Tonin, IRCCS San Camillo Hospital, 2024

    arguments (Input)
        EEG struct
        % Optional
        opt.AfterStart (1,1) double
        opt.BeforeEnd (1,1) double
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
    config = HRB_loadConfig(module, "selectTime", opt);

    %% Logger
    logConfig = HRB_loadConfig(module, "logging", opt);
    log = HRB_loggerSetUp(module, logConfig);
    
    %% Removing channels
    log.info("Select time")

    % Check if the selected times are reasonable
    EEG_duration = EEG.xmax - EEG.xmin;

    if EEG_duration < config.AfterStart 
        log.error(sprintf("The recording is %.3fs, you cannot select %.3f seconds after the start.", EEG_duration, config.AfterStart))
    elseif EEG_duration - config.AfterStart < config.BeforeEnd
        log.error(sprintf("The recording is %.3fs, you requested %.3fs after start, you cannot select %.3f seconds before the end.", EEG_duration, config.AfterStart, config.BeforeEnd))
    end

    time_from = EEG.xmin + config.AfterStart;
    time_to = EEG.xmax - config.BeforeEnd;

    log.info(sprintf("Selected time [%.3f, %.3f] (%.3f after start, %.3f before end)", time_from, time_to, config.AfterStart, config.BeforeEnd))

    EEG = pop_select(EEG, 'time', [time_from, time_to], config.EEGLAB{:});

    %% Save
    if config.Save
        logParams = unpackStruct(logConfig);
        HRB_saveData(EEG, "Name", config.SaveName, "Folder", module, "OutputFolder", config.OutputFolder, logParams{:});
    end

end

