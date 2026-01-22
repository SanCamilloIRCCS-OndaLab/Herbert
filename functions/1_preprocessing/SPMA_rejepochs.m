function [EEG] = SPMA_rejepochs(EEG, opt)
% SPMA_rejepochs reject epochs based on amplitudes threshold
%
% Usage:
%   >>> EEG = SPMA_rejepochs(EEG, 'Threshold', 100, 'Channels', [1:32]) %Rejects >+100 and <-100 uV
%   >>> EEG = SPMA_rejepochs(EEG, 'Threshold', [min max], 'Channels', [1:32])
%
% Parameters:
%   EEG (struct): EEG struct using EEGLAB struct system.Epochs must have
%   been extracted. 
%
% Other Parameters:
%   Threshold (double): Amplitude limit in uV.
%       - If scalar (e.g., 100): Limits are set to [-100 100]
%       - If vector (e.g. [-50 150]): Limits are specific
%
%   Channels (vector): List of channel indices to check. Default is [] = ALL
%
%   TimeLimits (1x2 double): Time window to check in seconds [min max].Default is [] = whole epoch
%
%   Save (logical): Save the cleaned dataset
% 
% See also: EEGLAB, pop_eegthresh, pop_rejepoch
%
% Authors: Ettore Napoli, University of Bologna, 2026

    arguments(Input)
        EEG struct
        % Optional 
        opt.Threshold double = 100 % uV. Default +/-100uV
        opt.Channels double = [] % Empty = All channels
        opt.TimeLimits double = [] % Empty = Whole epoch
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
    config = SPMA_loadConfig(module, "rejepochs", opt);

    %% Logger
    logConfig = SPMA_loadConfig(module, "logging", opt);
    log = SPMA_loggerSetUp(module, logConfig);

    %% Check prerequisites
    if EEG.trials == 1
        error("SPMA:Continuous data.", "Dataset seems continous (1 trial). Run SPMA_epoch first.");
    end

    %% Set up Parameters
    % 1. Threshold
    if isscalar(config.Threshold)
        % If user gives 100 as input, we assume range [-100 100]
        lower_lim = -abs(config.Threshold);
        upper_lim = abs(config.Threshold);
    elseif length(config.Threshold) == 2
        lower_lim = config.Threshold(1);
        upper_lim = config.Threshold(2);
    else
        error("SPMA: Bad Threshold", "Threshold must be a scalar (e.g., 100) or a 1x2 vector (e.g., [-100 100])");
    end

    % 2. Channels
    if isempty(config.Channels)
        channels_to_check = 1:EEG.nbchan;
    else
        channels_to_check = config.Channels;
    end

    % 3. Time Limits
    if isempty(config.TimeLimits)
        t_start = EEG.xmin;
        t_end = EEG.xmax;
    else
        t_start = config.TimeLimits(1);
        t_end = config.TimeLimits(2);
    end

    %% Detect artifacts (pop_eegthresh)
    log.info(sprintf("Scanning for artifacts. Threshold: [%.1f %.1f]", lower_lim, upper_lim));

    try
        % pop_eegthresh syntax:
        % (EEG, type_rej, elec_comp, low_thresh, up_thresh, start_t, end_t, superpose, reject)
        % type_rej = 1 (Electrodes/Raw Data)
        % reject = 0 (Do NOT reject yet, just give me the indices)

        [~, bad_trials] = pop_eegthresh(EEG, 1, channels_to_check, lower_lim, upper_lim, t_start, t_end, 0, 0);

        n_bad = length(bad_trials);
        n_total = EEG.trials;
        perc_bad = (n_bad/n_total)*100;
        
        log.info(sprintf("Found %d bad trials out of %d (%.2f%%).", n_bad, n_total, perc_bad));

    catch ME
        log.error(sprintf("Error during artifact detection: %s", ME.message));
        rethrow(ME);
    end

    %% Reject artifactual epochs (pop_rejepoch)
    if n_bad >0
        log.info("Removing marked trials...");

        try
            EEG = pop_rejepoch(EEG, bad_trials, 0);

            % Update setname
            if config.SaveName ~= ""
                EEG.setname = config.SaveName;
            else
                EEG.setname = EEG.setname + "_epoch_rej";
            end

            log.info("Trials removed successfully.");

        catch ME
            log.error(sprintf("Error during epoch rejection: %s", ME.message));
            rethrow(ME);
        end
    else
        log.info("No trials marked for rejection. Dataset remains unchanged.");
    end

    %% Save
    if config.Save
        logParams = unpackStruct(logConfig);
        SPMA_saveData(EEG, "Name", config.SaveName, "Folder", module, "OutputFolder", config.OutputFolder, logParams{:});
    end
end








