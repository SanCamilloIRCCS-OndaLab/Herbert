function EEG = HRB_bst_inverse_dipole(InputData, opt)
% HRB_BST_INVERSE_DIPOLE - Compute dipole modeling inverse solution.
% Method-specific sub-function of HRB_bst_inverse.
% Fix vs HRB_bst_inverse (B2): SourceOrient correctly passed from
% DipolOrientation. "loose" NOT supported (MNE-only).
%
% Usage:
%   >>> EEG = HRB_bst_inverse_dipole(EEG);
%
% Method-specific parameters:
%   DipoleNoiseCovReg (string): "auto"|"regularize"|"median"|"diagonal"|"none"
%   DipolOrientation (string):  "constrained" (default) | "unconstrained"
%
% Authors: Ettore Napoli, University of Bologna, 2026
% See also: HRB_BST_INVERSE, HRB_BST_INVERSE_MNE, HRB_BST_INVERSE_LCMV

arguments(Input)
    InputData
    opt.DipoleNoiseCovReg string {mustBeMember(opt.DipoleNoiseCovReg, ["regularize","median","diagonal","none","auto"])} = "auto"
    opt.DipolOrientation string {mustBeMember(opt.DipolOrientation, ["constrained","unconstrained"])} = "constrained"
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

if config.OutputFolder == ""
    config.OutputFolder = fullfile("output", string(datetime("now","Format","yyyyMMdd_HHmmss")));
end
if ~exist(config.OutputFolder,'dir'), mkdir(config.OutputFolder); end

if strlength(config.BrainstormDbDir) > 0
    dbDir = char(config.BrainstormDbDir);
else
    dbDir = fullfile(pwd, "brainstorm_db");
end
if ~exist(dbDir,'dir'), mkdir(dbDir); end

if ~brainstorm('status')
    % Use 'server' mode: fully headless, no Java/X11 required.
    % 'nogui' mode still needs an X display on headless Linux servers.
    brainstorm server;
    t = tic;
    while toc(t) < 60
        try, bst_get('BrainstormDbDir'); break; catch, pause(1); end
    end
end

currentDbDir = bst_get('BrainstormDbDir');
if ~strcmpi(strip(currentDbDir,'right',filesep), strip(dbDir,'right',filesep))
    bst_set('BrainstormDbDir', dbDir); gui_brainstorm('UpdateProtocolsList');
end

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

recordings = bst_process('CallProcess','process_select_files_data',[],[], ...
    'subjectname',subjName,'condition', bstCondition,  % *** FIX: was '' ***'tag','', ...
    'includebad',1,'includeintra',1,'includecommon',1);
if isempty(recordings)
    error("HRB:NoRecordings","No recordings for subject '%s'.", subjName);
end

switch config.ProcessOption
    case "kernel_shared",  processOption = 1;
    case "kernel_perfile", processOption = 2;
    case "full",           processOption = 3;
end

switch config.DipolOrientation
    case "constrained",   orientStr = 'fixed';
    case "unconstrained", orientStr = 'free';
end

noiseCovReg = mapCovReg(config.DipoleNoiseCovReg);

try
    log.info(sprintf("Computing dipole modeling (orient=%s)...", config.DipolOrientation));

    sFilesInverse = bst_process('CallProcess','process_inverse_2018', recordings, [], ...
        'output',  processOption, ...
        'inverse', struct( ...
            'Comment',        'Dipole', ...
            'InverseMethod',  'gls', ...
            'InverseMeasure', 1, ...
            'SourceOrient',   {{orientStr}}, ...   % FIX B2
            'Loose',          [], ...
            'UseDepth',       0, ...
            'WeightExp',      0.5, ...
            'WeightLimit',    10, ...
            'NoiseMethod',    noiseCovReg, ...
            'NoiseReg',       0.1, ...
            'SnrMethod',      'rms', ...
            'SnrRms',         1e-06, ...
            'SnrFixed',       3, ...
            'ComputeKernel',  processOption < 3, ...
            'DataTypes',      {{'EEG'}}));

    if isempty(sFilesInverse)
        error("HRB:InverseFailed","Dipole modeling failed for subject '%s'.", subjName);
    end
    log.info(sprintf("Dipole modeling computed. %d result file(s).", length(sFilesInverse)));

catch ME
    log.error(sprintf("HRB_bst_inverse_dipole failed: %s", ME.message));
    rethrow(ME);
end

if isSubjName
    EEG = struct(); EEG.etc.brainstorm = struct();
else
    EEG = InputData;
end

EEG.etc.brainstorm.inverse_method      = 'dipole';
EEG.etc.brainstorm.inverse_orientation = char(config.DipolOrientation);
EEG.etc.brainstorm.inverse_files       = {sFilesInverse.FileName};
EEG.etc.brainstorm.protocol            = protocolName;
EEG.etc.brainstorm.subject             = subjName;
EEG.etc.brainstorm.db_path             = dbDir;

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
