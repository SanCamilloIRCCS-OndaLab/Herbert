function EEG = HRB_bst_headmodel(InputData, opt)

arguments(Input)
    InputData % struct (RAM) or string/char (filepath)
    opt.ChanLocs string = "" % Path to custom chan loc file
    opt.ChanLocsTemplate string = "" % Template BST
    opt.SelectTemplate logical = false % Show available BST template to choose from
    opt.Method string {mustBeMember(opt.Method, ["OpenMEEG", "3-ShellSphere", "DUNeuro"])} = "OpenMEEG"
    opt.SourceSpace string {mustBeMember(opt.SourceSpace, ["cortex","volume"])} = "cortex"
    opt.NoiseCovBaseline double = [] % [] whole window | [t1, t2] specific window
    opt.NoiseCovSensorTypes string  = "EEG"
    opt.ProtocolName string = "HRB_Protocol"
    opt.BrainstormDbDir string = ""
    % OpenMEEG BEM options
    opt.BemConductivities double = [1, 0.0125, 1]  % [scalp, skull, brain]

    % DUNeuro FEM options
    opt.DUNeuroFemType string {mustBeMember(opt.DUNeuroFemType, ["fitted","hexahedral"])} = "fitted"
    opt.DUNeuroSolverType string {mustBeMember(opt.DUNeuroSolverType, ["cg","dg"])} = "cg"
    opt.DUNeuroSrcModel string {mustBeMember(opt.DUNeuroSrcModel, ["venant","subtraction","partial_integration"])} = "venant"
    opt.DUNeuroIsotropic logical = true
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
config = HRB_loadConfig(module, "bst_headmodel", opt);

%% Logger
logConfig = HRB_loadConfig(module, "logging", opt);
log = HRB_loggerSetUp(module, logConfig);

%% 1. Input type detection
isSubjName = isstring(InputData) || ischar(InputData);

if isSubjName
    subjName = char(InputData);
    protocolName = char(config.ProtocolName);

    if isempty(subjName)
        error("HRB:BadInput", "InputData is empty. Provide a valid subject name.");
    end

    log.info(sprintf("Input Mode: subject name (%s)", subjName));
else
    if ~isstruct(InputData)
        error("HRB:BadInput", "InputData must be an EEG struct or a file path string.");
    end

    if ~isfield(InputData, 'etc') || ~isfield(InputData.etc, 'brainstorm')
        error("HRB:MissingMetadata", ...
            "EEG.etc.brainstorm not found. Run HRB_bst_import before HRB_bst_headmodel.");
    end

    subjName = InputData.etc.brainstorm.subject;
    protocolName = InputData.etc.brainstorm.protocol;

    log.info(sprintf("Input mode: EEG struct (subject: %s)", subjName));
end

%% 2. Set Output Folder

if config.OutputFolder == ""
    timestamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
    config.OutputFolder = fullfile("output", timestamp);
end

if ~exist(config.OutputFolder, 'dir')
    mkdir(config.OutputFolder);
end

%% 3. Brainstorm Database Location

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

    % Wait for Brainstorm to fully start before continuing
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
        error("HRB:BrainstormTimeout", "Brainstorm failed to initialize within %d seconds.", timeout);
    end
    log.info("Brainstorm initialized successfully.");
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

%% 5. Manage Protocol

iProtocol = bst_get('Protocol', protocolName);

if isempty(iProtocol)
    error("HRB:ProtocolNotFound", "Protocol '%s' not found. Run HRB_bst_import first", protocolName);
else
    log.info(sprintf("Setting current protocol: %s", protocolName));
    gui_brainstorm('SetCurrentProtocol', iProtocol);
    log.info(sprintf("Protocol '%s' set as current.", protocolName));
end

%% 6. Select recordings from DB

recordings = bst_process('CallProcess', 'process_select_files_data', [], [], ...
    'subjectname', subjName, ...
    'condition', '', ...
    'tag', '', ...
    'includebad', 1, ...
    'includeintra', 1, ...
    'includecommon', 1);

if isempty(recordings)
    error("HRB:NoRecordings", "No recordings found for subject '%s'.", subjName);
end

%% 7. Channel Location

if ~config.SelectTemplate && strlength(config.ChanLocsTemplate) == 0 && strlength(config.ChanLocs) == 0
    error("HRB:NoChanLocs", ...
        "Provide 'ChanLocsTemplate', 'ChanLocs', or set 'SelectTemplate=true'.");
end

try
    % Interactive Template Selection
    % a. Find subj anatomy
    if config.SelectTemplate
        [sSubject, ~] = bst_get('Subject', subjName);
        anatFile = sSubject.Anatomy(sSubject.iAnatomy).FileName;

        if contains(anatFile, '@default_subject')
            anatName = 'ICBM152';
        elseif contains(anatFile,'@colin27')
            anatName = 'Colin27';
        else 
            anatName = 'NotAligned';
        end

        log.info(sprintf("Anatomy detected: %s", anatName));
        
        % b. Find list of all the channel locations corresponding to a
        % specific anatomy template
        EEGDefaults = bst_get('EegDefaults');
        iGroup = find(strcmpi({EEGDefaults.name}, anatName));
        templateNames = {EEGDefaults(iGroup).contents.name};
        templatePaths = {EEGDefaults(iGroup).contents.fullpath};

        [iSel, ok] = listdlg( ...
            'ListString', templateNames, ...
            'SelectionMode','single', ...
            'Name', sprintf("Select EEG Template", anatName), ...
            'PromptString', 'Select the channel location template.', ...
            'ListSize',[400 400]);
        if ~ok
            error("HRB:NoTemplateSelected. No channel location template selected. Aborted.");
        end
        config.ChanLocsTemplate = string(templatePaths{iSel});
        log.info(sprintf("Template selected: %s", config.ChanLocsTemplate));
    end

    % Apply channel location
    if strlength(config.ChanLocsTemplate) > 0
        log.info(sprintf("Adding channel locations from Bst Template: %s", config.ChanLocsTemplate));
        recordings = bst_process('CallProcess', 'process_channel_addloc', recordings, [], ...
            'channelfile', {char(config.ChanLocsTemplate), 'BST'}, ...
            'usedefault',  '', ...
            'fixunits',    1, ...
            'vox2ras',     1, ...
            'mrifile',     {'', ''}, ...
            'fiducials',   []);
    elseif strlength(config.ChanLocs) > 0
        log.info(sprintf("Adding channel location from file: %s", config.ChanLocs));
        recordings = bst_process('CallProcess', 'process_channel_addloc', recordings, [], ...
            'channelfile', char(config.ChanLocs), ...
            'usedefault', '', ...
            'fixunits', 1, ...
            'vox2ras', 1, ...
            'mrifile', {'', ''}, ...
            'fiducials', []);
    end

    if isempty(recordings)
        error("HRB:ChanLocFailed", "Failed to add channel locations for subject '%s'.", subjName);
    end
    log.info("Channel locations added successfully.");



    %% 8. Compute Head Model

    switch config.Method
        case "3-ShellSphere"
            methodValue = 2;
            comment = "3_Shell";
        case "OpenMEEG"
            methodValue = 3;
            comment = "BEM";
        case "DUNeuro"
            methodValue = 4;
            comment = "FEM";
    end

    switch config.SourceSpace
        case "cortex"
            spaceValue = 1;
        case "volume"
            spaceValue = 2;
    end

    % OpenMEEG struct (always required by BST)
    openmeegStruct = struct(...
        'BemFiles',     {{}}, ...
        'BemNames',     {{'Scalp', 'Skull', 'Brain'}}, ...
        'BemCond',      config.BemConductivities, ...
        'BemSelect',    [1, 1, 1], ...
        'isAdjoint',    0, ...
        'isAdaptative', 1, ...
        'isSplit',      0, ...
        'SplitLength',  4000);

    % nirstorm struct (always required by BST)
    nirstormStruct = struct(...
        'FluenceFolder',    'https://neuroimage.usc.edu/resources/nst_data/fluence/', ...
        'smoothing_method', 'geodesic_dist', ...
        'smoothing_fwhm',   10);

    % Base parameters (common to all methods)
    headmodelParams = { ...
        'Comment',     comment, ...
        'sourcespace', spaceValue, ...
        'meg',         1, ...
        'eeg',         methodValue, ...
        'ecog',        2, ...
        'seeg',        2, ...
        'nirs',        1, ...
        'openmeeg',    openmeegStruct, ...
        'nirstorm',    nirstormStruct, ...
        'channelfile', ''};

    % DUNeuro struct (only if FEM selected)
    if strcmp(config.Method, "DUNeuro")
        duneuroStruct = struct(...
            'FemCond',             [], ...
            'FemSelect',           [], ...
            'UseTensor',           0, ...
            'Isotropic',           double(config.DUNeuroIsotropic), ...
            'SrcShrink',           0, ...
            'SrcForceInGM',        0, ...
            'FemType',             char(config.DUNeuroFemType), ...
            'SolverType',          char(config.DUNeuroSolverType), ...
            'GeometryAdapted',     0, ...
            'Tolerance',           1e-08, ...
            'ElecType',            'normal', ...
            'MegIntorderadd',      0, ...
            'MegType',             'physical', ...
            'SolvSolverType',      char(config.DUNeuroSolverType), ...
            'SolvPrecond',         'amg', ...
            'SolvSmootherType',    'ssor', ...
            'SolvIntorderadd',     0, ...
            'DgSmootherType',      'ssor', ...
            'DgScheme',            'sipg', ...
            'DgPenalty',           20, ...
            'DgEdgeNormType',      'houston', ...
            'DgWeights',           1, ...
            'DgReduction',         1, ...
            'SolPostProcess',      1, ...
            'SolSubstractMean',    0, ...
            'SolSolverReduction',  1e-10, ...
            'SrcModel',            char(config.DUNeuroSrcModel), ...
            'SrcIntorderadd',      0, ...
            'SrcIntorderadd_lb',   2, ...
            'SrcNbMoments',        3, ...
            'SrcRefLen',           20, ...
            'SrcWeightExp',        1, ...
            'SrcRelaxFactor',      6, ...
            'SrcMixedMoments',     1, ...
            'SrcRestrict',         1, ...
            'SrcInit',             'closest_vertex', ...
            'BstSaveTransfer',     0, ...
            'BstEegTransferFile',  'eeg_transfer.dat', ...
            'BstMegTransferFile',  'meg_transfer.dat', ...
            'BstEegLfFile',        'eeg_lf.dat', ...
            'BstMegLfFile',        'meg_lf.dat', ...
            'UseIntegrationPoint', 1, ...
            'EnableCacheMemory',   0, ...
            'MegPerBlockOfSensor', 0);

        headmodelParams = [headmodelParams, {'duneuro', duneuroStruct}];
    end

    % Call process
    log.info(sprintf("Computing head model (method: %s, space: %s)...", config.Method, config.SourceSpace));
    recordings = bst_process('CallProcess', 'process_headmodel', recordings, [], headmodelParams{:});

    % Safety check
    if isempty(recordings)
        error("HRB:HeadModelFailed", ...
            "Head model computation failed for subject '%s' with method '%s'.", ...
            subjName, config.Method);
    end
    log.info(sprintf("Head model computed successfully (method: %s).", config.Method));

    %% 9. Noise Covariance
    log.info(sprintf("Computing noise covariance (sensors: %s)...", config.NoiseCovSensorTypes));

    recordings = bst_process('CallProcess', 'process_noisecov', recordings, [], ...
        'baseline',       config.NoiseCovBaseline, ...
        'datatimewindow', [], ...
        'sensortypes',    char(config.NoiseCovSensorTypes), ...
        'target',         1, ...
        'dcoffset',       1, ...
        'identity',       0, ...
        'copycond',       0, ...
        'copysubj',       0, ...
        'copymatch',      0, ...
        'replacefile',    1);

    if isempty(recordings)
        error("HRB:NoiseCovFailed", ...
            "Noise covariance computation failed for subject '%s'.", subjName);
    end
    log.info("Noise covariance computed successfully.");
catch ME
    log.error(sprintf("HRB_bst_headmodel failed: %s", ME.message));
    rethrow(ME);
end

%% 10. Build output EEG struct
if isSubjName
    % Initialize EEG struct
    EEG = struct();
    EEG.etc.brainstorm = struct();
else
    % Input was already a struct
    EEG = InputData;
end

% Inject headmodel metadata
EEG.etc.brainstorm.headmodel_method  = char(config.Method);
EEG.etc.brainstorm.headmodel_space   = char(config.SourceSpace);
EEG.etc.brainstorm.protocol          = protocolName;
EEG.etc.brainstorm.subject           = subjName;
EEG.etc.brainstorm.db_path           = dbDir;

log.info(sprintf("Output EEG struct ready (subject: %s, method: %s).", subjName, config.Method));

%% 11. Save
if config.Save
    logParams = unpackStruct(logConfig);
    HRB_saveData(EEG, "Name", config.SaveName, "Folder", module, ...
        "OutputFolder", config.OutputFolder, logParams{:});
end
end
