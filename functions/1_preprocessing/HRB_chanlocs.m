function EEG = HRB_chanlocs(EEG, opt)
% HRB_CHANLOCS - Assign channel locations from a standard template.
%
%  In 'auto' mode (default), detects the EEG system from channel name
%  patterns and selects the best-matching template by channel count.
%  Supports Brain Products / 10-20 / 10-5, EGI HydroCel, and BioSemi.
%
% Examples:
%     >>> EEG = HRB_chanlocs(EEG)
%     >>> EEG = HRB_chanlocs(EEG, 'Template', 'standard_1005.elc')
%     >>> EEG = HRB_chanlocs(EEG, Template='auto', MinMatchRate=0.9)
%
% Parameters:
%    EEG (struct): EEG struct using EEGLAB structure system
%
% Other Parameters:
%    Template (string): 'auto' or filename/fullpath of a channel locations
%                       file. 'auto' detects system from channel names.
%                       Accepts any format supported by EEGLAB readlocs
%                       (.elc, .sfp, .ced, .xyz, .locs, ...)
%    MinMatchRate (double): minimum fraction of channels that must match
%                           the template. Error if below threshold.
%
% Returns:
%    EEG (struct): EEG struct with channel locations assigned
%
% See also:
%    EEGLAB, POP_CHANEDIT, READLOCS
%
% Authors: IRCCS San Camillo Hospital, 2024

arguments (Input)
    EEG struct
    % Channel locations
    opt.Template      string
    opt.MinMatchRate  double
    % Save options
    opt.Save          logical
    opt.SaveName      string
    opt.OutputFolder  string
    % Log options
    opt.LogEnabled    logical
    opt.LogLevel      double {mustBeInteger, mustBeInRange(opt.LogLevel, 0, 6)}
    opt.LogToFile     logical
    opt.LogFileDir    string
    opt.LogFileName   string
end

%% Constants
module = "preprocessing";

%% Parsing arguments
config    = HRB_loadConfig(module, "chanlocs", opt);
logConfig = HRB_loadConfig(module, "logging",  opt);
log       = HRB_loggerSetUp(module, logConfig);

%% Resolve template
if strcmpi(config.Template, 'auto')
    log.info("Template = 'auto': detecting EEG system from channel names...");
    [templatePath, matchRate, systemName] = local_autodetect(EEG, log);
    log.info(sprintf("Selected: %s (match rate: %.0f%%)", systemName, matchRate*100));
else
    templatePath = local_find_template(char(config.Template));
    matchRate    = local_match_rate(lower({EEG.chanlocs.labels}), templatePath);
    log.info(sprintf("Template: %s (match rate: %.0f%%)", templatePath, matchRate*100));
end

%% Match rate check
if matchRate < config.MinMatchRate
    error("HRB:PoorChannelMatch", ...
        "Match rate %.0f%% is below threshold %.0f%%.\n" + ...
        "The wrong template may have been selected.\n" + ...
        "Use an explicit Template parameter to override.", ...
        matchRate*100, config.MinMatchRate*100);
end

%% Assign locations
log.info("Assigning channel locations...");
EEG = pop_chanedit(EEG, 'lookup', templatePath);
EEG = eeg_checkset(EEG);

% Report matched vs unmatched channels
hasCoords = arrayfun(@(c) ~isempty(c.X) && ~isnan(c.X), EEG.chanlocs);
nMatched  = sum(hasCoords);
nMissing  = EEG.nbchan - nMatched;
log.info(sprintf("Coordinates assigned: %d / %d channels", nMatched, EEG.nbchan));
if nMissing > 0
    log.warning(sprintf("No coordinates found for: %s", ...
        strjoin({EEG.chanlocs(~hasCoords).labels}, ', ')));
end

%% Save
if config.Save
    logParams = unpackStruct(logConfig);
    HRB_saveData(EEG, "Name", config.SaveName, "Folder", module, ...
        "OutputFolder", config.OutputFolder, logParams{:});
end

end


% =========================================================================
function [templatePath, matchRate, systemName] = local_autodetect(EEG, log)
%local_autodetect  Detect EEG system and select best-matching template.

labels = lower({EEG.chanlocs.labels});
n      = EEG.nbchan;

% Classify system from channel name patterns
pEGI     = mean(~cellfun(@isempty, regexp(labels, '^e\d+$',     'match')));
pBioSemi = mean(~cellfun(@isempty, regexp(labels, '^[a-h]\d+$', 'match')));

if pEGI > 0.5
    log.info(sprintf("System: EGI (%.0f%% channels match E+number)", pEGI*100));
    [fname, systemName] = local_pick_egi(n);
elseif pBioSemi > 0.5
    log.info(sprintf("System: BioSemi (%.0f%% channels match [A-H]+number)", pBioSemi*100));
    [fname, systemName] = local_pick_biosemi(n);
else
    log.info("System: standard 10-20/10-5 (Brain Products, ANT Neuro, ...)");
    [fname, systemName] = local_pick_standard(n);
end

% Resolve filename to full path — searches EEGLAB tree if not on MATLAB path
templatePath = local_find_template(fname);
matchRate    = local_match_rate(labels, templatePath);
end


% =========================================================================
function fpath = local_find_template(fname)
%local_find_template  Resolve a template filename to a full path.
%
%  Resolution order:
%    1. Already a full path that exists on disk      -> use as-is
%    2. MATLAB path (which)                          -> fast, works if folder is on path
%    3. Recursive search inside EEGLAB root folder   -> works even if DipFit not on path
%
%  This ensures template files inside EEGLAB plugins (e.g. standard_1005.elc
%  inside DipFit) are found regardless of how the MATLAB path is configured.

% 1. Already a full/absolute path
if isfile(fname)
    fpath = fname;
    return;
end

% 2. MATLAB path lookup
fpath = which(fname);
if ~isempty(fpath)
    return;
end

% 3. Recursive search inside EEGLAB directory tree
eeglabRoot = fileparts(which('eeglab'));
if ~isempty(eeglabRoot)
    found = dir(fullfile(eeglabRoot, '**', fname));
    if ~isempty(found)
        fpath = fullfile(found(1).folder, found(1).name);
        return;
    end
end

% Not found anywhere
error("HRB:TemplateNotFound", ...
    "Template '%s' not found on disk, MATLAB path, or inside EEGLAB directory.\n" + ...
    "Provide a full absolute path via the Template parameter.", fname);
end


% =========================================================================
function [fname, name] = local_pick_egi(n)
%local_pick_egi  Select EGI HydroCel template by channel count.
candidates = {
     32, 'GSN-HydroCel-32.sfp',     'EGI HydroCel 32';
     64, 'GSN-HydroCel-64_1.0.sfp', 'EGI HydroCel 64';
     65, 'GSN-HydroCel-65_1.0.sfp', 'EGI HydroCel 64 (+ref)';
    128, 'GSN-HydroCel-128.sfp',     'EGI HydroCel 128';
    129, 'GSN-HydroCel-129.sfp',     'EGI HydroCel 128 (+ref)';
    256, 'GSN-HydroCel-256.sfp',     'EGI HydroCel 256';
    257, 'GSN-HydroCel-257.sfp',     'EGI HydroCel 256 (+ref)';
};
counts = cell2mat(candidates(:,1));
[~, idx] = min(abs(counts - n));
fname = candidates{idx, 2};
name  = candidates{idx, 3};
end


% =========================================================================
function [fname, name] = local_pick_standard(n)
%local_pick_standard  Select 10-20/10-10/10-5 template by channel count.
% standard_1005.elc (DipFit plugin) covers Brain Products extended labels
% (AFF1h, FFC1h, etc.) and all other 10-5 system names.
if n <= 19
    fname = 'Standard-10-20-Cap19.ced'; name = '10-20 (19ch)';
elseif n <= 25
    fname = 'Standard-10-20-Cap25.ced'; name = '10-20 (25ch)';
elseif n <= 33
    fname = 'Standard-10-10-Cap33.ced'; name = '10-10 (33ch)';
elseif n <= 47
    fname = 'Standard-10-10-Cap47.ced'; name = '10-10 (47ch)';
elseif n <= 81
    fname = 'Standard-10-20-Cap81.ced'; name = '10-20 (81ch)';
else
    fname = 'standard_1005.elc';        name = '10-5 full (standard_1005)';
end
end


% =========================================================================
function [fname, name] = local_pick_biosemi(n)
%local_pick_biosemi  Select BioSemi ActiveTwo template by channel count.
% BioSemi templates may require manual installation (not always in DipFit).
candidates = {
     32, 'biosemi32.sfp',  'BioSemi 32';
     64, 'biosemi64.sfp',  'BioSemi 64';
    128, 'biosemi128.sfp', 'BioSemi 128';
    256, 'biosemi256.sfp', 'BioSemi 256';
};
counts = cell2mat(candidates(:,1));
[~, idx] = min(abs(counts - n));
fname = candidates{idx, 2};
name  = candidates{idx, 3};
end


% =========================================================================
function rate = local_match_rate(channelLabels, templatePath)
%local_match_rate  Fraction of channel names found in the template file.
try
    tmpl       = readlocs(templatePath);
    tmplLabels = lower({tmpl.labels});
    rate       = sum(ismember(channelLabels, tmplLabels)) / length(channelLabels);
catch
    rate = 0;
end
end