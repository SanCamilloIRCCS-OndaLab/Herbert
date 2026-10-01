function [EEG] = HRB_rejepochs(EEG, opt)
% HRB_rejepochs reject epochs based on amplitudes threshold
%
% Usage:
%   >>> EEG = HRB_rejepochs(EEG, 'Threshold', 100, 'Channels', [1:32]) %Rejects >+100 and <-100 uV
%   >>> EEG = HRB_rejepochs(EEG, 'Threshold', [min max], 'Channels', [1:32])
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
    opt.Method string {mustBeMember(opt.Method, ["threshold", "jointprob"])}
    opt.Threshold double % uV. Default +/-100uV
    opt.SD double
    opt.Channels double % Empty = All channels
    opt.TimeLimits double  % Empty = Whole epoch
    % Interactive Mode (Human in the Loop)
    opt.ConfirmRej logical
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
config = HRB_loadConfig(module, "rejepochs", opt);

%% Logger
logConfig = HRB_loadConfig(module, "logging", opt);
log = HRB_loggerSetUp(module, logConfig);

%% Check prerequisites
if EEG.trials == 1
    error("HRB:Continuous data.", "Dataset seems continous (1 trial). Run HRB_epoch first.");
end

%% Set up Parameters
% Channels
if isempty(config.Channels)
    channels_to_check = 1:EEG.nbchan;
else
    channels_to_check = config.Channels;
end

% Time Limits
if isempty(config.TimeLimits)
    t_start = EEG.xmin;
    t_end = EEG.xmax;
else
    t_start = config.TimeLimits(1);
    t_end = config.TimeLimits(2);
end

%% Detect artifacts (method-dependent)
switch config.Method
    case "threshold"                       % amplitude threshold in µV
        if isscalar(config.Threshold)
            lower_lim = -abs(config.Threshold);
            upper_lim =  abs(config.Threshold);
        elseif numel(config.Threshold) == 2
            lower_lim = config.Threshold(1);
            upper_lim = config.Threshold(2);
        else
            error("HRB:BadThreshold", "Threshold must be scalar or 1x2 vector.");
        end
        log.info(sprintf("Method threshold: [%.1f %.1f] uV", lower_lim, upper_lim));
        EEG = pop_eegthresh(EEG, 1, channels_to_check, lower_lim, upper_lim, t_start, t_end, 0, 0);
        bad_trials = find(EEG.reject.rejthresh);

    case "jointprob"                       % joint probability, threshold in SD
        if isscalar(config.SD)
            local_sd = config.SD; global_sd = config.SD;
        elseif numel(config.SD) == 2
            local_sd = config.SD(1); global_sd = config.SD(2);
        else
            error("HRB:BadSD", "SD must be scalar or 1x2 vector [local global].");
        end
        log.info(sprintf("Method jointprob: local=%.1f SD, global=%.1f SD", local_sd, global_sd));
        EEG = pop_jointprob(EEG, 1, channels_to_check, local_sd, global_sd, 0, 0);
        bad_trials = find(EEG.reject.rejjp);
end

n_bad = numel(bad_trials);
log.info(sprintf("Found %d bad trials out of %d (%.2f%%).", n_bad, EEG.trials, 100*n_bad/EEG.trials));





%% Human in the Loop Verification
if config.ConfirmRej
    log.info("Opening interactive GUI. Please review rejections. CLICK 'UPDATE MARKS' BEFORE CLOSING to save changes.");

    % 1. Build rejection matrix for eegplot
    % FIXED: Format must be [start end R G B E1 E2 ... En] where E are channel flags
    rej_matrix = [];
    if ~isempty(bad_trials)
        for i = 1:length(bad_trials)
            t_idx = bad_trials(i);
            % Convert epoch index to sample indices (continuous view)
            start_pnt = (t_idx-1) * EEG.pnts;
            end_pnt   = t_idx * EEG.pnts;

            % CORREZIONE CRITICA: Aggiunti zeros(1, EEG.nbchan) per matchare le dimensioni di eegplot
            rej_matrix = [rej_matrix; start_pnt end_pnt 1 0.8 0.8 zeros(1, EEG.nbchan)];
        end
    end

    % 2. Clear temp variable to avoid ghost data
    evalin('base', 'clear HRB_TEMP_REJ');

    % 3. Define callback: eegplot puts 'TMPREJ' in workspace when you click update
    command_str = 'assignin(''base'', ''HRB_TEMP_REJ'', TMPREJ); disp(''HRB: Rejections updated.'');';

    % 4. Open eegplot
    eegplot(EEG.data, ...
        'srate', EEG.srate, ...
        'winrej', rej_matrix, ...
        'command', command_str, ...
        'eloc_file', EEG.chanlocs, ...
        'events', EEG.event, ...
        'butlabel', 'UPDATE MARKS', ...
        'title', 'Review Epochs: Click to Mark/Unmark -> Click UPDATE MARKS -> Close');

    % 5. Pause script until figure is closed
    uiwait(gcf);

    % 6. Retrieve User modifications
    if evalin('base', 'exist(''HRB_TEMP_REJ'', ''var'')')
        updated_rej_matrix = evalin('base', 'HRB_TEMP_REJ');
        evalin('base', 'clear HRB_TEMP_REJ');

        if ~isempty(updated_rej_matrix)
            % Convert samples back to epoch indices
            % Using median point of the marked region to find which epoch it belongs to
            center_pnts = (updated_rej_matrix(:,1) + updated_rej_matrix(:,2)) / 2;
            bad_trials = floor(center_pnts / EEG.pnts) + 1;
            bad_trials = unique(bad_trials)'; % Ensure row vector

            % Safety check for out of bounds
            bad_trials(bad_trials > EEG.trials) = [];
            bad_trials(bad_trials < 1) = []; % Safety for index 0
        else
            bad_trials = [];
        end
        log.info("User manual review applied.");
    else
        log.warning("Window closed without clicking 'UPDATE MARKS'. Using original auto-detections.");
    end
end

%% Reject artifactual epochs (pop_rejepoch)

% Update n_bad after manual review
n_bad = length(bad_trials);

if n_bad >= EEG.trials
    % Degenerate universe: every epoch exceeds the criterion. Removing them all
    % would empty the dataset (pop_rejepoch -> pop_select errors "is empty").
    % This is a RESULT, not a crash: signal it with a typed identifier so the
    % report classifies it as degenerate, not failed.
    log.info(sprintf("[WARNING] All %d epochs rejected — degenerate universe (0 retained).", EEG.trials));
     error("HRB:AllEpochsRejected", ...
        "All %d epochs rejected: degenerate universe, empty dataset, no data retained.", EEG.trials);

elseif n_bad > 0
    log.info("Removing marked trials...");

    try
        EEG = pop_rejepoch(EEG, bad_trials, 0);

        % Update setname
        if strlength(string(config.SaveName)) > 0
            EEG.setname = char(config.SaveName);
        else
            EEG.setname = char(string(EEG.setname) + "_epoch_rej");
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
    HRB_saveData(EEG, "Name", config.SaveName, "Folder", module, "OutputFolder", config.OutputFolder, logParams{:});
end
end








