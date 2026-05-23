function EEG = HRB_bst_inverse(InputData, opt)
% HRB_bst_inverse - Computes the inverse solution (source estimation) in
% Brainstorm for a given subject. Supports Minimum Norm Imaging (MNE),
% LCMV Beamformer, and Dipole Modeling.
%
% Usage:
%   >>> EEG = HRB_bst_inverse(EEG);
%   >>> EEG = HRB_bst_inverse(EEG, 'Method', 'mne', 'MNEMeasure', 'sloreta');
%   >>> EEG = HRB_bst_inverse('Sub01', 'Method', 'lcmv', 'ProtocolName', 'HRB_Protocol');
%
% Parameters:
%   InputData: EEGLAB struct (RAM) with EEG.etc.brainstorm populated by
%              HRB_bst_import and HRB_bst_headmodel, or string with the
%              subject name in Brainstorm.
%
% Other Parameters:
%
%   Method (string): Inverse method. Default: "mne"
%       - "mne"    : Minimum Norm Imaging
%       - "lcmv"   : LCMV Beamformer
%       - "dipole" : Dipole Modeling
%
%   ProcessOption (string): How results are stored. Default: "kernel_shared"
%       - "kernel_shared"  : One kernel shared across all trials (fastest,
%                            recommended for RS with many trials)
%       - "kernel_perfile" : One kernel per trial
%       - "full"           : Full source results per trial (slow, large disk usage)
%
%   DipolOrientation (string): Dipole orientation constraint. Default: "constrained"
%       - "constrained"  : Normal to cortex (recommended for EEG)
%       - "loose"        : Loose constraint (MNE only)
%       - "unconstrained": Free orientation
%
%   SourceSpace (string): Source space. Default: read from EEG.etc.brainstorm.
%       - "cortex"  : Cortical surface
%       - "volume"  : Volume grid
%
%   ProtocolName (string): Brainstorm protocol name. Default: "HRB_Protocol"
%   BrainstormDbDir (string): Path to BST database. Default: '<pwd>/brainstorm_db'
%
%   --- MNE specific ---
%   MNEMeasure (string): Output measure. Default: "dspm"
%       - "current" : Current density map
%       - "dspm"    : dSPM (normalized)
%       - "sloreta" : sLORETA
%
%   MNEDepthWeighting (logical): Apply depth weighting. Default: true
%   MNEDepthOrder (double): Depth weighting order [0,1]. Default: 0.5
%   MNEDepthMax (double): Maximal amount of depth weighting. Default: 10
%
%   MNENoiseCovReg (string): Noise covariance regularization. Default: "auto"
%       - "regularize" : Regularize noise covariance
%       - "median"     : Median eigenvalue
%       - "diagonal"   : Diagonal noise covariance
%       - "none"       : No regularization
%       - "auto"       : Automatic shrinkage
%
%   MNESnr (double): Signal-to-noise ratio for regularization. Default: 3
%
%   --- LCMV specific ---
%   LCMVDataCovReg (string): Data covariance regularization. Default: "auto"
%       - "regularize" : Regularize data covariance
%       - "median"     : Median eigenvalue
%       - "diagonal"   : Diagonal data covariance
%       - "none"       : No regularization
%       - "auto"       : Automatic shrinkage
%
%   --- Dipole Modeling specific ---
%   DipoleNoiseCovReg (string): Noise covariance regularization. Default: "auto"
%       - "regularize" : Regularize noise covariance
%       - "median"     : Median eigenvalue
%       - "diagonal"   : Diagonal noise covariance
%       - "none"       : No regularization
%       - "auto"       : Automatic shrinkage
%
% Outputs:
%   EEG: EEGLAB struct with Brainstorm metadata injected in EEG.etc.brainstorm:
%       - inverse_method      : method used
%       - inverse_measure     : measure used (MNE only)
%       - inverse_orientation : dipole orientation used
%       - inverse_files       : cell array of result file paths in BST DB
%       - protocol            : Brainstorm protocol name
%       - subject             : subject name in Brainstorm
%       - db_path             : path to the Brainstorm database
%
% Notes:
%   - Run HRB_bst_import and HRB_bst_headmodel before this function.
%   - "loose" orientation is only valid for MNE. An error is raised if
%     used with LCMV or Dipole Modeling.
%   - For RS with many trials, use ProcessOption="kernel_shared" (default).
%
% Authors: Ettore Napoli, University of Bologna, 2026
%
% See also: HRB_BST_IMPORT, HRB_BST_HEADMODEL, HRB_BST_CONNECTIVITY

arguments(Input)
    InputData  % EEG struct (RAM) or string (subject name)

    % --- Common ---
    opt.Method string {mustBeMember(opt.Method, ["mne","lcmv","dipole"])} = "mne"
    opt.ProcessOption string {mustBeMember(opt.ProcessOption, ["kernel_shared","kernel_perfile","full"])} = "kernel_shared"
    opt.DipolOrientation string {mustBeMember(opt.DipolOrientation, ["constrained","loose","unconstrained"])} = "constrained"
    opt.SourceSpace string {mustBeMember(opt.SourceSpace, ["cortex","volume"])} = "cortex"
    opt.ProtocolName string = "HRB_Protocol"
    opt.BrainstormDbDir string = ""

    % --- MNE specific ---
    opt.MNEMeasure string {mustBeMember(opt.MNEMeasure, ["current","dspm","sloreta"])} = "dspm"
    opt.MNEDepthWeighting logical = true
    opt.MNEDepthOrder double {mustBeInRange(opt.MNEDepthOrder, 0, 1)} = 0.5
    opt.MNEDepthMax double = 10
    opt.MNENoiseCovReg string {mustBeMember(opt.MNENoiseCovReg, ["regularize","median","diagonal","none","auto"])} = "auto"
    opt.MNESnr double = 3

    % --- LCMV specific ---
    opt.LCMVDataCovReg string {mustBeMember(opt.LCMVDataCovReg, ["regularize","median","diagonal","none","auto"])} = "auto"

    % --- Dipole Modeling specific ---
    opt.DipoleNoiseCovReg string {mustBeMember(opt.DipoleNoiseCovReg, ["regularize","median","diagonal","none","auto"])} = "auto"

    % --- Pipeline Output Options ---
    opt.Save logical
    opt.SaveName string
    opt.OutputFolder string

    % --- Log Options ---
    opt.LogEnabled logical
    opt.LogLevel double {mustBeInteger, mustBeInRange(opt.LogLevel, 0,6)}
    opt.LogToFile logical
    opt.LogFileDir string
    opt.LogFileName string
end

%% Constants
module = "source";

%% Parsing Arguments
config = HRB_loadConfig(module, "bst_inverse", opt);

%% Logger
logConfig = HRB_loadConfig(module, "logging", opt);
log = HRB_loggerSetUp(module, logConfig);


%% 1. Input type detection

isSubjName = isstring(InputData) || ischar(InputData);

if isSubjName
    subjName     = char(InputData);
    protocolName = char(config.ProtocolName);
    sourceSpace  = char(config.SourceSpace);
    if isempty(subjName)
        error("HRB:BadInput", "InputData is empty. Provide a valid subject name.");
    end
    log.info(sprintf("Input mode: subject name (%s)", subjName));
else
    if ~isstruct(InputData)
        error("HRB:BadInput", "InputData must be an EEG struct or a subject name string.");
    end
    if ~isfield(InputData, 'etc') || ~isfield(InputData.etc, 'brainstorm')
        error("HRB:MissingMetadata", ...
            "EEG.etc.brainstorm not found. Run HRB_bst_import and HRB_bst_headmodel first.");
    end
    if ~isfield(InputData.etc.brainstorm, 'headmodel_method')
        error("HRB:MissingHeadmodel", ...
            "No headmodel found in EEG.etc.brainstorm. Run HRB_bst_headmodel first.");
    end
    subjName     = InputData.etc.brainstorm.subject;
    protocolName = InputData.etc.brainstorm.protocol;
   
    log.info(sprintf("Input mode: EEG struct (subject: %s)", subjName));
end


%% 2. Validate method-specific constraints

if strcmp(config.DipolOrientation, 'loose') && ~strcmp(config.Method, 'mne')
    error("HRB:InvalidOrientation", ...
        "'loose' orientation is only valid for MNE. Method '%s' does not support it.", config.Method);
end


%% 3. Output folder

if config.OutputFolder == ""
    timestamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
    config.OutputFolder = fullfile("output", timestamp);
end
if ~exist(config.OutputFolder, 'dir')
    mkdir(config.OutputFolder);
end


%% 4. Brainstorm database location

if strlength(config.BrainstormDbDir) > 0
    dbDir = char(config.BrainstormDbDir);
else
    dbDir = fullfile(pwd, 'brainstorm_db');
end
if ~exist(dbDir, 'dir')
    mkdir(dbDir);
end
log.info(sprintf("Brainstorm DB: %s", dbDir));


%% 5. Start Brainstorm

if ~brainstorm('status')
    log.info("Starting Brainstorm (nogui)...");
    brainstorm nogui;
end

% Update DB path only if different
currentDbDir = bst_get('BrainstormDbDir');
if ~strcmpi(strip(currentDbDir, 'right', filesep), strip(dbDir, 'right', filesep))
    log.info(sprintf("Switching BST DB: '%s' to '%s'", currentDbDir, dbDir));
    bst_set('BrainstormDbDir', dbDir);
    gui_brainstorm('UpdateProtocolsList');
else
    log.info("Brainstorm DB path is already correct.");
end


%% 6. Manage Protocol

iProtocol = bst_get('Protocol', protocolName);
if isempty(iProtocol)
    error("HRB:ProtocolNotFound", ...
        "Protocol '%s' not found. Run HRB_bst_import first.", protocolName);
end
log.info(sprintf("Setting current protocol: %s", protocolName));
gui_brainstorm('SetCurrentProtocol', iProtocol);
log.info(sprintf("Protocol '%s' set as current.", protocolName));


%% 7. Select recordings from DB

recordings = bst_process('CallProcess', 'process_select_files_data', [], [], ...
    'subjectname',   subjName, ...
    'condition',     '', ...
    'tag',           '', ...
    'includebad',    1, ...
    'includeintra',  1, ...
    'includecommon', 1);

if isempty(recordings)
    error("HRB:NoRecordings", "No recordings found for subject '%s'.", subjName);
end
log.info(sprintf("Found %d recording(s) for subject '%s'.", length(recordings), subjName));


%% 8. Map options to BST values


% Process option
switch config.ProcessOption
    case "kernel_shared"
        processOption = 1;  % Kernel only: shared
    case "kernel_perfile"
        processOption = 2;  % Kernel only: one per file
    case "full"
        processOption = 3;  % Full results: one per file
end

% Dipole orientation
switch config.DipolOrientation
    case "constrained"
        orientationOption = 1;
    case "loose"
        orientationOption = 2;  % MNE only
    case "unconstrained"
        orientationOption = 3;
end


%% 9. Compute Inverse Solution

try
    log.info(sprintf("Computing inverse solution (method: %s)...", config.Method));

    switch config.Method

        % -----------------------------------------------------------------
        case "mne"
        % -----------------------------------------------------------------
            % Measure mapping
            switch config.MNEMeasure
                case "current"
                    measureStr = 'amplitude';
                case "dspm"
                    measureStr = 'dspm2018';
                case "sloreta"
                    measureStr = 'sloreta';
            end

            switch config.DipolOrientation
                case "constrained",   orientStr = 'fixed';
                case "loose",         orientStr = 'loose';
                case "unconstrained", orientStr = 'free';
            end

            % Noise cov regularization mapping
            noiseCovReg = mapCovReg(config.MNENoiseCovReg);

            % Depth weighting
            if config.MNEDepthWeighting
                depthOption = 1;
            else
                depthOption = 0;
            end

            if strcmp(config.DipolOrientation, 'loose')
                looseVal = 0.2;
            else
                looseVal = [];
            end

            sFilesInverse = bst_process('CallProcess', 'process_inverse_2018', recordings, [], ...
                'output',        processOption, ...
                'inverse',       struct(...
                    'Comment',         'MNE', ...
                    'InverseMethod',   'minnorm', ...
                    'InverseMeasure',  measureStr, ...
                    'SourceOrient',    {{orientStr}}, ...
                    'Loose',           looseVal, ...
                    'UseDepth',        depthOption, ...
                    'WeightExp',       config.MNEDepthOrder, ...
                    'WeightLimit',     config.MNEDepthMax, ...
                    'NoiseMethod',     noiseCovReg, ...
                    'NoiseReg',        0.1, ...
                    'SnrMethod',       'rms', ...
                    'SnrRms',          1e-06, ...
                    'SnrFixed',        config.MNESnr, ...
                    'ComputeKernel',   processOption < 3, ...
                    'DataTypes',       {{'EEG'}}));

        % -----------------------------------------------------------------
        case "lcmv"
        % -----------------------------------------------------------------

            switch config.DipolOrientation
                case "constrained",   orientStr = 'fixed';
                case "unconstrained", orientStr = 'free';
            end

        
            dataCovReg = mapCovReg(config.LCMVDataCovReg);

            sFilesInverse = bst_process('CallProcess', 'process_inverse_2018', recordings, [], ...
                'output',        processOption, ...
                'inverse',       struct(...
                    'Comment',         'LCMV', ...
                    'InverseMethod',   'lcmv', ...
                    'InverseMeasure',  1, ...  % Current density map only
                    'SourceOrient',    {{orientStr}}, ...
                    'Loose',           [], ...
                    'UseDepth',        0, ...
                    'WeightExp',       0.5, ...
                    'WeightLimit',     10, ...
                    'NoiseMethod',     dataCovReg, ...
                    'NoiseReg',        0.1, ...
                    'SnrMethod',       'rms', ...
                    'SnrRms',          1e-06, ...
                    'SnrFixed',        3, ...
                    'ComputeKernel',   processOption < 3, ...
                    'DataTypes',       {{'EEG'}}));

        % -----------------------------------------------------------------
        case "dipole"
        % -----------------------------------------------------------------

            switch config.DipolOrientation
                case "constrained",   orientStr = 'fixed';
                case "unconstrained", orientStr = 'free';
            end
        
            noiseCovReg = mapCovReg(config.DipoleNoiseCovReg);

            sFilesInverse = bst_process('CallProcess', 'process_inverse_2018', recordings, [], ...
                'output',        processOption, ...
                'inverse',       struct(...
                    'Comment',         'Dipole', ...
                    'InverseMethod',   'gls', ...
                    'InverseMeasure',  1, ...
                    'SourceOrient',    {{orientStr}}, ...
                    'Loose',           [], ...
                    'UseDepth',        0, ...
                    'WeightExp',       0.5, ...
                    'WeightLimit',     10, ...
                    'NoiseMethod',     noiseCovReg, ...
                    'NoiseReg',        0.1, ...
                    'SnrMethod',       'rms', ...
                    'SnrRms',          1e-06, ...
                    'SnrFixed',        3, ...
                    'ComputeKernel',   processOption < 3, ...
                    'DataTypes',       {{'EEG'}}));
    end

    if isempty(sFilesInverse)
        error("HRB:InverseFailed", ...
            "Inverse solution failed for subject '%s' with method '%s'.", ...
            subjName, config.Method);
    end

    log.info(sprintf("Inverse solution computed. %d result file(s) created.", length(sFilesInverse)));

catch ME
    log.error(sprintf("HRB_bst_inverse failed: %s", ME.message));
    rethrow(ME);
end


%% 10. Build output EEG struct

if isSubjName
    EEG = struct();
    EEG.etc.brainstorm = struct();
else
    EEG = InputData;
end

EEG.etc.brainstorm.inverse_method      = char(config.Method);
EEG.etc.brainstorm.inverse_orientation = char(config.DipolOrientation);
EEG.etc.brainstorm.inverse_files       = {sFilesInverse.FileName};
EEG.etc.brainstorm.protocol            = protocolName;
EEG.etc.brainstorm.subject             = subjName;
EEG.etc.brainstorm.db_path             = dbDir;

% Add measure only for MNE
if strcmp(config.Method, 'mne')
    EEG.etc.brainstorm.inverse_measure = char(config.MNEMeasure);
end

log.info(sprintf("Output EEG struct ready (subject: %s, method: %s).", subjName, config.Method));


%% 11. Save

if config.Save
    logParams = unpackStruct(logConfig);
    HRB_saveData(EEG, "Name", config.SaveName, "Folder", module, ...
        "OutputFolder", config.OutputFolder, logParams{:});
end

end


%% Helper: map covariance regularization string to BST integer
function val = mapCovReg(regStr)
    switch regStr
        case "regularize"
            val = 'reg';
        case "median"
            val = 'median';
        case "diagonal"
            val = 'diag';
        case "none"
            val = 'none';
        case "auto"
            val = 'shrink';
    end
end