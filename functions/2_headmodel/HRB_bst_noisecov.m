function EEG = HRB_bst_noisecov(InputData, opt)
% HRB_BST_NOISECOV - Compute noise or data covariance matrix in Brainstorm.
%
% Separated from HRB_bst_headmodel so it can run once per filtered dataset
% in the multiverse (after the filter step), while HRB_bst_headmodel runs
% once per subject before the multiverse branches.
%
% Typical pipeline order:
%   HRB_bst_import    (1x per subject)
%   HRB_bst_headmodel (1x per subject)
%   HRB_bst_noisecov  (1x per filtered universe)
%   HRB_bst_inverse   (1x per filtered universe)
%
% For LCMV beamformer, run twice: once with Target="noise", once with
% Target="data". HRB_bst_inverse_lcmv also computes data cov internally
% so in most cases a single Target="noise" call suffices.
%
% Usage:
%   >>> EEG = HRB_bst_noisecov(EEG);
%   >>> EEG = HRB_bst_noisecov(EEG, 'Target', 'data');
%   >>> EEG = HRB_bst_noisecov(EEG, 'NoiseCovBaseline', [-0.2, 0]);
%
% Parameters:
%   InputData: EEGLAB struct with EEG.etc.brainstorm (from HRB_bst_import),
%              or subject name string.
%
% Other Parameters:
%   Target (string): Which covariance to compute. Default: "noise"
%       - "noise" : Noise covariance (required by all inverse methods)
%       - "data"  : Data covariance  (required by LCMV beamformer)
%
%   NoiseCovBaseline (double): Time window [t1, t2] in seconds.
%                              Default: [] = full epoch window.
%
%   NoiseCovSensorTypes (string): Sensor types. Default: "EEG".
%
%   ProtocolName (string): Brainstorm protocol name. Default: "HRB_Protocol".
%   BrainstormDbDir (string): Path to BST DB. Default: '<pwd>/brainstorm_db'.
%
% Outputs:
%   EEG: EEGLAB struct (pass-through, with covariance metadata added):
%       - noisecov_target  : "noise" or "data"
%       - noisecov_baseline: baseline used
%
% Authors: Ettore Napoli, University of Bologna, 2026
%
% See also: HRB_BST_HEADMODEL, HRB_BST_INVERSE, HRB_BST_INVERSE_LCMV

arguments(Input)
    InputData
    opt.Target string {mustBeMember(opt.Target, ["noise","data"])} = "noise"
    opt.NoiseCovBaseline double = []
    opt.NoiseCovSensorTypes string = "EEG"
    opt.ProtocolName string = "HRB_Protocol"
    opt.BrainstormDbDir string = ""
    % Pipeline Output Options
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
module = "headmodel";

%% Parsing Arguments
config = HRB_loadConfig(module, "bst_noisecov", opt);

%% Logger
logConfig = HRB_loadConfig(module, "logging", opt);
log = HRB_loggerSetUp(module, logConfig);

%% 1. Input type detection
isSubjName = isstring(InputData) || ischar(InputData);

if isSubjName
    subjName     = char(InputData);
    protocolName = char(config.ProtocolName);
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
            "EEG.etc.brainstorm not found. Run HRB_bst_import first.");
    end
    subjName     = InputData.etc.brainstorm.subject;
    protocolName = InputData.etc.brainstorm.protocol;
    log.info(sprintf("Input mode: EEG struct (subject: %s)", subjName));
end

% Extract bst condition name from metadata
if ~isSubjName && isfield(InputData.etc.brainstorm, 'condition')
    bstCondition = InputData.etc.brainstorm.condition
else
    bstCondition = '';
end

%% 2. Output folder
if config.OutputFolder == ""
    timestamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
    config.OutputFolder = fullfile("output", timestamp);
end
if ~exist(config.OutputFolder, 'dir')
    mkdir(config.OutputFolder);
end

%% 3. Brainstorm database location
if strlength(config.BrainstormDbDir) > 0
    dbDir = char(config.BrainstormDbDir);
else
    dbDir = fullfile(pwd, "brainstorm_db");
end
if ~exist(dbDir, 'dir')
    mkdir(dbDir);
end
log.info(sprintf("Brainstorm DB: %s", dbDir));

%% 4. Start Brainstorm
if ~brainstorm('status')
    log.info("Starting Brainstorm (nogui)...");
    brainstorm nogui;
    timeout = 60;
    t = tic;
    while toc(t) < timeout
        try
            bst_get('BrainstormDbDir');
            break;
        catch
            pause(1);
        end
    end
    if toc(t) >= timeout
        error("HRB:BrainstormTimeout", ...
            "Brainstorm failed to initialize within %d seconds.", timeout);
    end
    log.info("Brainstorm initialized successfully.");
end

%% 5. Switch DB if needed
currentDbDir = bst_get('BrainstormDbDir');
if ~strcmpi(strip(currentDbDir, 'right', filesep), strip(dbDir, 'right', filesep))
    log.info(sprintf("Switching BST DB: '%s' to '%s'", currentDbDir, dbDir));
    bst_set('BrainstormDbDir', dbDir);
    gui_brainstorm('UpdateProtocolsList');
end

%% 6. Activate protocol
iProtocol = bst_get('Protocol', protocolName);
if isempty(iProtocol)
    error("HRB:ProtocolNotFound", ...
        "Protocol '%s' not found. Run HRB_bst_import first.", protocolName);
end
gui_brainstorm('SetCurrentProtocol', iProtocol);
log.info(sprintf("Protocol '%s' set as current.", protocolName));

%% 7. Select recordings
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
log.info(sprintf("Found %d recording(s) for '%s'.", length(recordings), subjName));

%% 8. Compute covariance
targetVal = mapTarget(config.Target);

log.info(sprintf("Computing %s covariance (sensors: %s)...", ...
    config.Target, config.NoiseCovSensorTypes));

try
    recordings = bst_process('CallProcess', 'process_noisecov', recordings, [], ...
        'baseline',       config.NoiseCovBaseline, ...
        'datatimewindow', [], ...
        'sensortypes',    char(config.NoiseCovSensorTypes), ...
        'target',         targetVal, ...
        'dcoffset',       1, ...
        'identity',       0, ...
        'copycond',       0, ...
        'copysubj',       0, ...
        'copymatch',      0, ...
        'replacefile',    1);

    if isempty(recordings)
        error("HRB:CovFailed", ...
            "%s covariance failed for subject '%s'.", config.Target, subjName);
    end
    log.info(sprintf("%s covariance computed successfully.", config.Target));

catch ME
    log.error(sprintf("HRB_bst_noisecov failed: %s", ME.message));
    rethrow(ME);
end

%% 9. Build output EEG struct
if isSubjName
    EEG = struct();
    EEG.etc.brainstorm = struct();
else
    EEG = InputData;
end

EEG.etc.brainstorm.noisecov_target   = char(config.Target);
EEG.etc.brainstorm.noisecov_baseline = config.NoiseCovBaseline;
EEG.etc.brainstorm.protocol          = protocolName;
EEG.etc.brainstorm.subject           = subjName;
EEG.etc.brainstorm.db_path           = dbDir;

log.info(sprintf("Output EEG struct ready (subject: %s, target: %s).", ...
    subjName, config.Target));

%% 10. Save
if config.Save
    logParams = unpackStruct(logConfig);
    HRB_saveData(EEG, "Name", config.SaveName, "Folder", module, ...
        "OutputFolder", config.OutputFolder, logParams{:});
end

end


%% Helper
function v = mapTarget(t)
    switch t
        case "noise", v = 1;
        case "data",  v = 2;
    end
end