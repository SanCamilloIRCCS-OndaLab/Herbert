function [EEG] = HRB_reref(EEG, opt)
% HRB_reref re-reference EEG data (common average or explicit channels)
%
% Usage:
%   >>> EEG = HRB_reref(EEG, 'RefType', 'average')            % common average reference
%   >>> EEG = HRB_reref(EEG, 'RefType', 'channel', 'RefChannels', ["TP9","TP10"])
%
% Parameters:
%   EEG (struct): EEG struct using EEGLAB struct system.
%
% Other Parameters:
%   RefType (string): 'average' (common average reference, default) or
%       'channel' (re-reference to one or more explicit channels).
%
%   RefChannels (string): Channel labels used as reference when
%       RefType='channel'. Ignored for 'average'.
%
%   Exclude (string): Channel labels to leave OUT of the reference computation
%       (e.g. EOG/Ref). Default [] = none (trusts removeChannels upstream).
%
%   KeepRef (logical): Keep the reference channel(s) after re-referencing.
%       Default false.
%
%   Save (logical): Save the re-referenced dataset.
%
% 
% See also: EEGLAB, pop_reref
%
% Authors: Ettore Napoli, University of Bologna, 2026

    arguments(Input)
        EEG struct
        % Optional
        opt.RefType string {mustBeMember(opt.RefType, ["average","channel"])} = "average"
        opt.RefChannels string = string.empty(1,0) % Labels; used only for 'channel'
        opt.Exclude string = string.empty(1,0)     % Labels excluded from the reference
        opt.KeepRef logical = false                % Keep reference channel after reref
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
    config = HRB_loadConfig(module, "reref", opt);
    config = HRB_loadConfig(module, "reref", opt);
    disp("=== reref config fields ==="); disp(fieldnames(config))   % TEMP

    %% Logger
    logConfig = HRB_loadConfig(module, "logging", opt);
    log = HRB_loggerSetUp(module, logConfig);

    %% Resolve channel labels
    labels = string({EEG.chanlocs.labels});

    % Exclude labels -> indices
    excludeIdx = [];
    if ~isempty(config.Exclude)
        [tf, loc] = ismember(lower(config.Exclude), lower(labels));
        if ~all(tf)
            error("HRB:RefExcludeNotFound", "Exclude channel(s) not found in chanlocs: %s", ...
                strjoin(config.Exclude(~tf), ", "));
        end
        excludeIdx = loc(tf);
    end

    % keepref flag for pop_reref
    if config.KeepRef
        keepRef = 'on';
    else
        keepRef = 'off';
    end

    %% Re-reference (pop_reref)
    try
        switch config.RefType
            case "average"
                log.info(sprintf("Applying common average reference (%d channels, %d excluded).", ...
                    EEG.nbchan, numel(excludeIdx)));

                if isempty(excludeIdx)
                    EEG = pop_reref(EEG, [], 'keepref', keepRef);
                else
                    EEG = pop_reref(EEG, [], 'exclude', excludeIdx, 'keepref', keepRef);
                end

            case "channel"
                if isempty(config.RefChannels)
                    error("HRB:RefChannelsMissing", "RefType='channel' requires RefChannels.");
                end
                [tf, loc] = ismember(lower(config.RefChannels), lower(labels));
                if ~all(tf)
                    error("HRB:RefChannelNotFound", "Reference channel(s) not found in chanlocs: %s", ...
                        strjoin(config.RefChannels(~tf), ", "));
                end
                refIdx = loc(tf);

                log.info(sprintf("Re-referencing to channel(s): %s (keepref=%s).", ...
                    strjoin(config.RefChannels, ", "), keepRef));

                if isempty(excludeIdx)
                    EEG = pop_reref(EEG, refIdx, 'keepref', keepRef);
                else
                    EEG = pop_reref(EEG, refIdx, 'exclude', excludeIdx, 'keepref', keepRef);
                end
        end

        EEG = eeg_checkset(EEG);
        log.info("Re-referencing applied successfully.");

    catch ME
        log.error(sprintf("Error during re-referencing: %s", ME.message));
        rethrow(ME);
    end

    %% Rank note (not a fix): average reference removes 1 degree of freedom
    if config.RefType == "average" && ~config.KeepRef
        expEffRank = EEG.nbchan - 1;
        log.info(sprintf("[WARNING] Average reference reduces rank by 1 (expected effective rank ~%d). Set HRB_runica 'pca' to the true rank to avoid a ghost component.", ...
            expEffRank));
    end

    %% Provenance
    EEG.etc.HRB.reref = struct( ...
        'type',        config.RefType, ...
        'refChannels', {cellstr(config.RefChannels)}, ...
        'exclude',     {cellstr(config.Exclude)}, ...
        'keepref',     config.KeepRef);

    %% Update setname
    if config.SaveName ~= ""
        EEG.setname = config.SaveName;
    else
        EEG.setname = EEG.setname + "_reref";
    end

    %% Save
    if config.Save
        logParams = unpackStruct(logConfig);
        HRB_saveData(EEG, "Name", config.SaveName, "Folder", module, "OutputFolder", config.OutputFolder, logParams{:});
    end
end