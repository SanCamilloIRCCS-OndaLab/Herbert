function [EEG] = HRB_interpChannels(EEG, opt)
% HRB_INTERPCHANNELS - Interpolate previously rejected channels back to a
%   common montage, so universes with different bad-channel sets share the
%   same sensor space before source analysis.
%
%   Reference montage: EEG.etc.HRB.refChanlocs (stashed by HRB_badChannels).
%   Optionally overridden by RefFile.
%
% Other Parameters:
%   Method (string): "spherical" (default) | "invdist" | "spacetime"
%   RefFile (string): optional .set whose chanlocs is the reference montage.
%
% Authors: Ettore Napoli, University of Bologna, 2026
arguments (Input)
    EEG struct
    opt.Method string {mustBeMember(opt.Method, ["spherical","invdist","spacetime"])}
    opt.RefFile string
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
    config = HRB_loadConfig(module, "interpChannels", opt);
    logConfig = HRB_loadConfig(module, "logging", opt);
    log = HRB_loggerSetUp(module, logConfig);

    % Resolve reference montage
    if config.RefFile ~= ""
        log.info("Loading reference montage from " + config.RefFile);
        refEEG = pop_loadset('filename', char(config.RefFile));
        refChanlocs = refEEG.chanlocs;
    elseif isfield(EEG.etc, "HRB") && isfield(EEG.etc.HRB, "refChanlocs")
        refChanlocs = EEG.etc.HRB.refChanlocs;
    else
        error("HRB:interpChannels:NoReference", ...
            "No reference montage: run HRB_badChannels first (stashes EEG.etc.HRB.refChanlocs), or set RefFile.");
    end

    nBefore = EEG.nbchan;
    log.info(sprintf("Interpolating to common montage: %d -> %d channels (method: %s)", ...
        nBefore, numel(refChanlocs), config.Method));

    EEG = pop_interp(EEG, refChanlocs, char(config.Method));
    EEG = eeg_checkset(EEG);

    log.info(sprintf("Interpolated %d channel(s)", EEG.nbchan - nBefore));

    if config.Save
        logParams = unpackStruct(logConfig);
        HRB_saveData(EEG, "Name", config.SaveName, "Folder", module, "OutputFolder", config.OutputFolder, logParams{:});
    end
end