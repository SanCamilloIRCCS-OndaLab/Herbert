function EEG = HRB_bst_inverse_lcmv(InputData, opt)
% HRB_BST_INVERSE_LCMV - Compute LCMV beamformer inverse solution.
% Method-specific sub-function of HRB_bst_inverse.
%
% Fixes vs HRB_bst_inverse:
%   B2: SourceOrient correctly passed from DipolOrientation.
%   B5: DATA covariance computed HERE (not in headmodel), since it is
%       only needed for LCMV. LCMV does NOT support "loose" orientation.
%
% Usage:
%   >>> EEG = HRB_bst_inverse_lcmv(EEG);
%   >>> EEG = HRB_bst_inverse_lcmv(EEG, 'DipolOrientation','unconstrained');
%
% Method-specific parameters:
%   LCMVDataCovReg (string):     "auto"|"regularize"|"median"|"diagonal"|"none"
%   DataCovBaseline (double):    [t1,t2] seconds. Default [] = full window.
%   DataCovSensorTypes (string): default "EEG"
%   DipolOrientation (string):   "constrained" (default) | "unconstrained"
%
% Authors: Ettore Napoli, University of Bologna, 2026
% See also: HRB_BST_INVERSE, HRB_BST_INVERSE_MNE, HRB_BST_INVERSE_DIPOLE

arguments(Input)
    InputData
    opt.LCMVDataCovReg string {mustBeMember(opt.LCMVDataCovReg, ["regularize","median","diagonal","none","auto"])} = "auto"
    opt.DataCovBaseline double = []
    opt.DataCovSensorTypes string = "EEG"
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
    % Protocol not found in memory — rescan DB to discover it
    gui_brainstorm('UpdateProtocolsList');
    iProtocol = bst_get('Protocol', protocolName);
end
if isempty(iProtocol)
    error("HRB:ProtocolNotFound", ...
        "Protocol '%s' not found. Run HRB_bst_import first.", protocolName);
end
gui_brainstorm('SetCurrentProtocol', iProtocol);

recordings = bst_process('CallProcess','process_select_files_data',[],[], ...
    'subjectname',subjName,'condition', bstCondition, ...  % *** FIX: was '' ***'tag',''
    'includebad',1,'includeintra',1,'includecommon',1);
if isempty(recordings)
    error("HRB:NoRecordings","No recordings for subject '%s'.", subjName);
end

%% Data covariance (FIX B5: only here, not in headmodel)
log.info(sprintf("Computing data covariance for LCMV (sensors: %s)...", config.DataCovSensorTypes));

recordings = bst_process('CallProcess','process_noisecov', recordings, [], ...
    'baseline',       config.DataCovBaseline, ...
    'datatimewindow', [], ...
    'sensortypes',    char(config.DataCovSensorTypes), ...
    'target',         2, ...   % 2 = Data covariance
    'dcoffset',       1, ...
    'identity',       0, ...
    'copycond',       0, ...
    'copysubj',       0, ...
    'copymatch',      0, ...
    'replacefile',    1);

if isempty(recordings)
    error("HRB:DataCovFailed","Data covariance failed for subject '%s'.", subjName);
end
log.info("Data covariance computed.");

%% Map options
switch config.ProcessOption
    case "kernel_shared",  processOption = 1;
    case "kernel_perfile", processOption = 2;
    case "full",           processOption = 3;
end

switch config.DipolOrientation
    case "constrained",   orientStr = 'fixed';
    case "unconstrained", orientStr = 'free';
end

dataCovReg = mapCovReg(config.LCMVDataCovReg);

%% Compute LCMV
try
    log.info(sprintf("Computing LCMV beamformer (orient=%s)...", config.DipolOrientation));

    sFilesInverse = bst_process('CallProcess','process_inverse_2018', recordings, [], ...
        'output',  processOption, ...
        'inverse', struct( ...
            'Comment',        'LCMV', ...
            'InverseMethod',  'lcmv', ...
            'InverseMeasure', 1, ...
            'SourceOrient',   {{orientStr}}, ...   % FIX B2
            'Loose',          [], ...
            'UseDepth',       0, ...
            'WeightExp',      0.5, ...
            'WeightLimit',    10, ...
            'NoiseMethod',    dataCovReg, ...
            'NoiseReg',       0.1, ...
            'SnrMethod',      'rms', ...
            'SnrRms',         1e-06, ...
            'SnrFixed',       3, ...
            'ComputeKernel',  processOption < 3, ...
            'DataTypes',      {{'EEG'}}));

    if isempty(sFilesInverse)
        error("HRB:InverseFailed","LCMV inverse failed for subject '%s'.", subjName);
    end
    log.info(sprintf("LCMV computed. %d result file(s).", length(sFilesInverse)));

catch ME
    log.error(sprintf("HRB_bst_inverse_lcmv failed: %s", ME.message));
    rethrow(ME);
end

if isSubjName
    EEG = struct(); EEG.etc.brainstorm = struct();
else
    EEG = InputData;
end

EEG.etc.brainstorm.inverse_method      = 'lcmv';
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
