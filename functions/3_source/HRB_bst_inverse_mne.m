function EEG = HRB_bst_inverse_mne(InputData, opt)
% HRB_BST_INVERSE_MNE - Compute MNE inverse solution (current/dSPM/sLORETA).
% Method-specific sub-function of HRB_bst_inverse.
%
% Fix vs HRB_bst_inverse (B2): SourceOrient is correctly passed from
% DipolOrientation — was hardcoded to 'fixed' in the omni function.
%
% Usage:
%   >>> EEG = HRB_bst_inverse_mne(EEG);
%   >>> EEG = HRB_bst_inverse_mne(EEG, 'MNEMeasure','sloreta', 'DipolOrientation','loose');
%
% Method-specific parameters:
%   MNEMeasure (string):      "dspm" (default) | "current" | "sloreta"
%   MNEDepthWeighting (logical): default true
%   MNEDepthOrder (double):   [0,1], default 0.5
%   MNEDepthMax (double):     default 10
%   MNENoiseCovReg (string):  "auto"|"regularize"|"median"|"diagonal"|"none"
%   MNESnr (double):          default 3
%   DipolOrientation (string): "constrained"|"loose"|"unconstrained"
%                              (MNE is the only method that supports "loose")
%
% Authors: Ettore Napoli, University of Bologna, 2026
% See also: HRB_BST_INVERSE, HRB_BST_INVERSE_LCMV, HRB_BST_INVERSE_DIPOLE

arguments(Input)
    InputData
    opt.MNEMeasure string {mustBeMember(opt.MNEMeasure, ["current","dspm","sloreta"])} = "dspm"
    opt.MNEDepthWeighting logical = true
    opt.MNEDepthOrder double {mustBeInRange(opt.MNEDepthOrder, 0, 1)} = 0.5
    opt.MNEDepthMax double = 10
    opt.MNENoiseCovReg string {mustBeMember(opt.MNENoiseCovReg, ["regularize","median","diagonal","none","auto"])} = "auto"
    opt.MNESnr double = 3
    opt.DipolOrientation string {mustBeMember(opt.DipolOrientation, ["constrained","loose","unconstrained"])} = "constrained"
    opt.ProcessOption string {mustBeMember(opt.ProcessOption, ["kernel_shared","kernel_perfile","full"])} = "kernel_shared"
    opt.ProtocolName string = "HRB_Protocol"
    opt.BrainstormDbDir string = ""
    opt.Save logical
    opt.SaveName string
    opt.OutputFolder string
    opt.LogEnabled logical
    opt.LogLevel double {mustBeInteger, mustBeInRange(opt.LogLevel, 0,6)}
    opt.LogToFile logical
    opt.LogFileDir string
    opt.LogFileName string
end

module = "source";
config    = HRB_loadConfig(module, "bst_inverse", opt);
logConfig = HRB_loadConfig(module, "logging", opt);
log = HRB_loggerSetUp(module, logConfig);

%% 1. Input type detection
isSubjName = isstring(InputData) || ischar(InputData);

if isSubjName
    subjName = char(InputData); protocolName = char(config.ProtocolName);
    if isempty(subjName), error("HRB:BadInput","InputData is empty."); end
    log.info(sprintf("Input mode: subject name (%s)", subjName));
else
    if ~isstruct(InputData), error("HRB:BadInput","InputData must be a struct or string."); end
    if ~isfield(InputData,'etc') || ~isfield(InputData.etc,'brainstorm')
        error("HRB:MissingMetadata","EEG.etc.brainstorm not found. Run HRB_bst_import first.");
    end
    if ~isfield(InputData.etc.brainstorm,'headmodel_method')
        error("HRB:MissingHeadmodel","No headmodel in EEG.etc.brainstorm. Run HRB_bst_headmodel first.");
    end
    subjName = InputData.etc.brainstorm.subject;
    protocolName = InputData.etc.brainstorm.protocol;
    log.info(sprintf("Input mode: EEG struct (subject: %s)", subjName));
end

    % =========================================================================
    %% Resolve BST condition name
    % Each pipeline universe imports into a unique BST condition (named after
    % the universe, set by HRB_bst_import via SaveName). Reading it here
    % ensures we query only this universe's recordings — not recordings from
    % other filter branches or universes sharing the same subject/protocol.
    % If no condition is stored (subject-name input mode), bstCondition = ''
    % selects all recordings for the subject (safe for single-universe use).
    % =========================================================================
    % *** condition name (set by HRB_bst_import = universe SaveName) ***
    if ~isSubjName && isfield(InputData.etc.brainstorm, 'condition')
        bstCondition = InputData.etc.brainstorm.condition;
    else
        bstCondition = '';
    end

%% 2. Output folder
if config.OutputFolder == ""
    config.OutputFolder = fullfile("output", string(datetime("now","Format","yyyyMMdd_HHmmss")));
end
if ~exist(config.OutputFolder,'dir'), mkdir(config.OutputFolder); end

%% 3. Brainstorm database location
if strlength(config.BrainstormDbDir) > 0
    dbDir = char(config.BrainstormDbDir);
else
    dbDir = fullfile(pwd, "brainstorm_db");
end
if ~exist(dbDir,'dir'), mkdir(dbDir); end

%% 4. Start Brainstorm
if ~brainstorm('status')
    % Use 'server' mode: fully headless, no Java/X11 required.
    % 'nogui' mode still needs an X display on headless Linux servers.
    brainstorm server;
    t = tic;
    while toc(t) < 60
        try, bst_get('BrainstormDbDir'); break; catch, pause(1); end
    end
end

%% 5. Switch DB if needed
currentDbDir = bst_get('BrainstormDbDir');
if ~strcmpi(strip(currentDbDir,'right',filesep), strip(dbDir,'right',filesep))
    bst_set('BrainstormDbDir', dbDir); gui_brainstorm('UpdateProtocolsList');
end

%% 6. Activate protocol
iProtocol = bst_get('Protocol', protocolName);
if isempty(iProtocol)
    protocolDir = fullfile(dbDir, protocolName);
    if exist(protocolDir, 'dir')
        log.info(sprintf("Protocol '%s' found on disk. Reloading DB...", protocolName));
        db_reload_database('current');
        iProtocol = bst_get('Protocol', protocolName);
    end
end
if isempty(iProtocol)
    error("HRB:ProtocolNotFound","Protocol '%s' not found. Run HRB_bst_import first.", protocolName);
end
gui_brainstorm('SetCurrentProtocol', iProtocol);

%% 7. Select recordings
recordings = bst_process('CallProcess','process_select_files_data',[],[], ...
    'subjectname',subjName,'condition', bstCondition,  % *** FIX: was '' ***'tag','', ...
    'includebad',1,'includeintra',1,'includecommon',1);
if isempty(recordings)
    error("HRB:NoRecordings","No recordings for subject '%s'.", subjName);
end

%% 8. Map options
switch config.ProcessOption
    case "kernel_shared",  processOption = 1;
    case "kernel_perfile", processOption = 2;
    case "full",           processOption = 3;
end

switch config.MNEMeasure
    case "current", measureStr = 'amplitude';
    case "dspm",    measureStr = 'dspm2018';
    case "sloreta", measureStr = 'sloreta';
end

switch config.DipolOrientation
    case "constrained",   orientStr = 'fixed';
    case "loose",         orientStr = 'loose';
    case "unconstrained", orientStr = 'free';
end

noiseCovReg = mapCovReg(config.MNENoiseCovReg);

looseVal = [];
if strcmp(config.DipolOrientation,'loose'), looseVal = 0.2; end

%% 9. Compute MNE inverse
try
    log.info(sprintf("Computing MNE inverse (measure=%s, orient=%s)...", ...
        config.MNEMeasure, config.DipolOrientation));

    sFilesInverse = bst_process('CallProcess','process_inverse_2018', recordings, [], ...
        'output',  processOption, ...
        'inverse', struct( ...
            'Comment',        'MNE', ...
            'InverseMethod',  'minnorm', ...
            'InverseMeasure', measureStr, ...
            'SourceOrient',   {{orientStr}}, ...   % FIX B2: was hardcoded {{'fixed'}}
            'Loose',          looseVal, ...
            'UseDepth',       double(config.MNEDepthWeighting), ...
            'WeightExp',      config.MNEDepthOrder, ...
            'WeightLimit',    config.MNEDepthMax, ...
            'NoiseMethod',    noiseCovReg, ...
            'NoiseReg',       0.1, ...
            'SnrMethod',      'rms', ...
            'SnrRms',         1e-06, ...
            'SnrFixed',       config.MNESnr, ...
            'ComputeKernel',  processOption < 3, ...
            'DataTypes',      {{'EEG'}}));

    if isempty(sFilesInverse)
        error("HRB:InverseFailed","MNE inverse failed for subject '%s'.", subjName);
    end
    log.info(sprintf("MNE inverse computed. %d result file(s).", length(sFilesInverse)));

catch ME
    log.error(sprintf("HRB_bst_inverse_mne failed: %s", ME.message));
    rethrow(ME);
end

%% 10. Build output EEG struct
if isSubjName
    EEG = struct(); EEG.etc.brainstorm = struct();
else
    EEG = InputData;
end

EEG.etc.brainstorm.inverse_method      = 'mne';
EEG.etc.brainstorm.inverse_measure     = char(config.MNEMeasure);
EEG.etc.brainstorm.inverse_orientation = char(config.DipolOrientation);
EEG.etc.brainstorm.inverse_files       = {sFilesInverse.FileName};
EEG.etc.brainstorm.protocol            = protocolName;
EEG.etc.brainstorm.subject             = subjName;
EEG.etc.brainstorm.db_path             = dbDir;

%% 11. Save
if config.Save
    logParams = unpackStruct(logConfig);
    HRB_saveData(EEG,"Name",config.SaveName,"Folder",module, ...
        "OutputFolder",config.OutputFolder,logParams{:});
end

end

%% Local helpers
function v = mapCovReg(r)
    switch r
        case "regularize", v = 'reg';
        case "median",     v = 'median';
        case "diagonal",   v = 'diag';
        case "none",       v = 'none';
        case "auto",       v = 'shrink';
    end
end
