function [EEG] = SPMA_epoch(EEG, opt)
% SPMA_epoch performs epoching and baseline correction
% on either task-based or resting state EEG data
%
% Usage:
%   >>> EEG = SPMA_epoch(EEG, 'Mode', 'Event', 'Events', {'S1'}, 'Limits',[-1 2])
%   >>> EEG = SPMA_epoch(EEG, 'Mode', 'Time', 'Recurrence', 2, 'Limits', [0 2])
%
% Parameters:
%   EEG (struct): EEG struct using EEGLAB struct system.
%
% Other Parameters:
%   Mode (string): 'Event' (default) or 'Time'
%       - 'Event': Extracts epochs locked to a specific Event (task)
%       - 'Time': Cuts data into regular intervals (Resting state)
%
% --- Mode 'Event' specific parameters ---
%       Events (string / cell): Event types to time-lock to. If [] uses all Events
%
%--- Mode 'Time' specific parameters ---
%       Recurrence (double): Interval in seconds between epochs (default 1)
%
% --- Common parameters ---
%       Limits (1x2 double): Epoch lantecy limits [start end] in seconds
%           - For "Event": relative to a marker (e.g. [-1 2])
%           - For "Time": duration of the chunk (e.g. [0 2])
%   
%       Baseline (1x2 double): Baseline correction [start end] in seconds. 
%       If empty (e.g. []), no baseline correction is applied
%
%       Save (logical): Save the epoched dataset
%
% See also: EEGLAB, pop_epoch, eeg_regepochs, pop_rmbase
%
% Authors: Ettore Napoli, University of Bologna, 2026

    arguments(Input)
        EEG struct
        % Optional
        opt.Mode string {mustBeMember(opt.Mode, ["Event", "Time"])} = "Event"
        opt.Events = []
        opt.Recurrence double = 1 %seconds
        opt.Limits (1,2) double = [-1 2]
        opt.Baseline double = []
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
    config = SPMA_loadConfig(module, "epoch", opt);

    %% Logger
    logConfig = SPMA_loadConfig(module, "logging", opt);
    log = SPMA_loggerSetUp(module, logConfig);

    %% Prepare SaveName
    if config.SaveName ~= ""
        newName = config.SaveName;
    else
        newName = EEG.setname + "_epochs";
    end

    %% Decode Mode option
    % Task-based option
    if config.Mode == "Event"
        log.info(sprintf("Epoching mode: EVENT LOCKED. Limits: [%.2f %.2f].", config.Limits(1), config.Limits(2)));

        if isempty(EEG.event)
            error("SPMA:NoEvents, Dataset has no events. Cannot run Event-Mode epoching.");
        end

        % Manage event format
        if isstring(config.Events) && ~isscalar(config.Events)
            targetEvents = cellstr(config.Events);

        elseif isstring(config.Events) && isscalar(config.Events) && config.Events == ""
            targetEvents = {};

        else targetEvents = config.Events;
        end

        % Run pop_epochs
        try
            EEG = pop_epoch(EEG, targetEvents, config.Limits, ...
                'newname', char(newName), ...
                'epochinfo', 'yes');
        catch ME
            log.error(sprintf("Error during pop_epoch: %s.", ME.message));
            rethrow(ME);
        end
    
    % Resting state option
    elseif config.Mode == "Time"
        log.info(sprintf("Epoching Mode: REGULAR TIME INTERVALS. Recurrence: %.2fs, Limits: [%.2f %.2f]s", config.Recurrence, config.Limits(1), config.Limits(2)));

        % Run eeg_regepochs
        try
            EEG = eeg_regepochs(EEG,'recurrence', config.Recurrence, ...
                'limits', config.Limits, ...
                'rmbase', NaN);
            EEG.setname = char(newName);
        catch ME
            log.error(sprintf("Error during eeg_regepochs: %s", ME.message));
            rethrow(ME)
        end
    end

    %% Run baseline correction
    if ~isempty(config.Baseline)
        log.info(sprintf("Applying baseline correction: [%.2f %.2f]", config.Baseline(1), config.Baseline(2)));

        % Run pop_rmbase
        baseline_ms = config.Baseline *1000 % Convert in ms

        actual_start_ms = EEG.xmin * 1000;
        actual_end_ms   = EEG.xmax * 1000;
        
        % Check Start
        if baseline_ms(1) < actual_start_ms
            log.warn(sprintf("Baseline start (%.1f ms) is before data start (%.1f ms). Adjusting to data start.", baseline_ms(1), actual_start_ms));
            baseline_ms(1) = actual_start_ms;
        end
        
        % Check End
        if baseline_ms(2) > actual_end_ms
            % Allow a small tolerance (e.g. 20ms) for rounding errors, then clamp
            if (baseline_ms(2) - actual_end_ms) < 20 
                 log.warning(sprintf("Baseline end (%.1f ms) is slighty beyond data end (%.1f ms). Adjusting to data end.", baseline_ms(2), actual_end_ms));
                 baseline_ms(2) = actual_end_ms;
            else
                 % If the difference is huge, it's a logic error, let pop_rmbase fail or handle it
                 log.warning("Baseline end is significantly beyond data limits. This might cause an error.");
            end
        end


        try
            EEG = pop_rmbase(EEG, baseline_ms);
            log.info("Baseline removed.");
        catch ME
            log.error(sprintf("Error during baseline correction: %s", ME.message));
            rethrow(ME);
        end
    end
    
    %% Save Dataset
    if config.Save
        logParams = unpackStruct(logConfig);
        SPMA_saveData(EEG, "Name", config.SaveName, "Folder", module, "OutputFolder", config.OutputFolder, logParams{:});
    end
end


