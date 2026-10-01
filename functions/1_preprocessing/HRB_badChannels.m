function [EEG] = HRB_badChannels(EEG, opt)
% HRB_BADCHANNELS - Automatic bad-channel detection & removal.
%   Single source of channel rejection for the multiverse. Three methods:
%   "corr" (clean_rawdata correlation), "kurt" / "spec" (pop_rejchan).
%
% Other Parameters:
%   Method (string): "corr" | "kurt" | "spec"
%   Threshold (double): pop_rejchan threshold (in SD if Norm=true). kurt/spec only.
%   Norm (logical): pop_rejchan 'norm' on/off. kurt/spec only.
%   FreqRange (1x2 double): [Hz] spectrum range. "spec" only.
%   CorrChannelCrit / CorrLineNoiseCrit / CorrFlatlineCrit: clean_rawdata channel criteria. "corr" only.
%   SaveExcludedChannels (logical): save the excluded-channel list.
%
% Authors: Ettore Napoli, University of Bologna, 2026
arguments (Input)
    EEG struct
    opt.Method string {mustBeMember(opt.Method, ["corr","kurt","spec"])}
    opt.Threshold double
    opt.Norm logical
    opt.FreqRange (1,:) double
    opt.CorrChannelCrit double
    opt.CorrLineNoiseCrit double
    opt.CorrFlatlineCrit double
    opt.SaveExcludedChannels logical
    opt.EEGLAB (1,:) cell
    opt.Save logical
    opt.SaveName string
    opt.OutputFolder string
    opt.LogEnabled logical
    opt.LogLevel double {mustBeInteger, mustBeInRange(opt.LogLevel,0,6)}
    opt.LogToFile logical
    opt.LogFileDir string
    opt.LogFileName string
end
    module = "preprocessing";
    config = HRB_loadConfig(module, "badChannels", opt);
    logConfig = HRB_loadConfig(module, "logging", opt);
    log = HRB_loggerSetUp(module, logConfig);

    log.info(sprintf("Bad-channel detection, method: %s", config.Method))
    chans_before = {EEG.chanlocs.labels};

    if ~isfield(EEG.etc, "HRB") || ~isfield(EEG.etc.HRB, "refChanlocs")
        EEG.etc.HRB.refChanlocs = EEG.chanlocs;
    end


    switch config.Method
        case "corr"   % clean_rawdata, channel-only (burst/window OFF)
            EEG = pop_clean_rawdata(EEG, ...
                'FlatlineCriterion',  config.CorrFlatlineCrit, ...
                'ChannelCriterion',   config.CorrChannelCrit, ...
                'LineNoiseCriterion', config.CorrLineNoiseCrit, ...
                'Highpass','off', 'BurstCriterion','off', ...
                'WindowCriterion','off', 'BurstRejection','off', ...
                'Distance','Euclidian', ...
                config.EEGLAB{:});
        case "kurt"
            normStr = "off";
            if config.Norm
                normStr = "on";
            end
            EEG = pop_rejchan(EEG, 'elec', 1:EEG.nbchan, ...
                'threshold', config.Threshold, 'norm', char(normStr), ...
                'measure', 'kurt', config.EEGLAB{:});
        case "spec"
            normStr = "off";
            if config.Norm
                normStr = "on";
            end
            EEG = pop_rejchan(EEG, 'elec', 1:EEG.nbchan, ...
                'threshold', config.Threshold, 'norm', char(normStr), ...
                'measure', 'spec', 'freqrange', config.FreqRange, ...
                config.EEGLAB{:});
    end

    chans_after = {EEG.chanlocs.labels};
    chans_excluded = setdiff(chans_before, chans_after);
    log.info("Excluded channels: " + strjoin(chans_excluded))

    if config.SaveExcludedChannels
        nameExcl = sprintf("%s_%s", config.SaveName, "ExcludedChannels");
        logParams = unpackStruct(logConfig);
        HRB_saveData(chans_excluded, "Name", nameExcl, "Folder", module, "OutputFolder", config.OutputFolder, logParams{:});
    end
    if config.Save
        logParams = unpackStruct(logConfig);
        HRB_saveData(EEG, "Name", config.SaveName, "Folder", module, "OutputFolder", config.OutputFolder, logParams{:});
    end
end