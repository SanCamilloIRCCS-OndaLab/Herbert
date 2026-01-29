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
        % Interactive Mode (Human in the Loop)
        opt.ConfirmRej logical = false  
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
        evalin('base', 'clear SPMA_TEMP_REJ'); 
        
        % 3. Define callback: eegplot puts 'TMPREJ' in workspace when you click update
        command_str = 'assignin(''base'', ''SPMA_TEMP_REJ'', TMPREJ); disp(''SPMA: Rejections updated.'');';
        
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
        if evalin('base', 'exist(''SPMA_TEMP_REJ'', ''var'')')
            updated_rej_matrix = evalin('base', 'SPMA_TEMP_REJ');
            evalin('base', 'clear SPMA_TEMP_REJ'); 
            
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








