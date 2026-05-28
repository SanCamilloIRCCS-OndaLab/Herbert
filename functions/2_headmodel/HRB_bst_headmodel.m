function EEG = HRB_bst_headmodel(InputData, opt)
% HRB_bst_headmodel - Computes the forward head model in Brainstorm.
% Supports OpenMEEG BEM, 3-Shell Sphere, and DUNeuro FEM methods.
% Noise/data covariance is NOT computed here — use HRB_bst_noisecov instead.
% This separation allows the headmodel to run once per subject regardless
% of how many preprocessing universes exist in the multiverse.
%
% Usage:
%   >>> EEG = HRB_bst_headmodel(EEG);
%   >>> EEG = HRB_bst_headmodel(EEG, 'Method', 'OpenMEEG');
%   >>> EEG = HRB_bst_headmodel('Sub01', 'ProtocolName', 'HRB_Protocol');
%
% Parameters:
%   InputData: EEGLAB struct (RAM) with EEG.etc.brainstorm populated by
%              HRB_bst_import, or string with the subject name in Brainstorm.
%
% Other Parameters:
%   Method (string): Head model computation method. Default: "OpenMEEG"
%       - "OpenMEEG"     : OpenMEEG BEM (3-layer Boundary Element Model).
%                          Most accurate. Requires OpenMEEG installed.
%       - "3-ShellSphere": 3-shell sphere approximation. No dependencies.
%       - "DUNeuro"      : DUNeuro Finite Element Model. Most accurate for
%                          complex geometries. Requires DUNeuro installed.
%
%   SourceSpace (string): Source space for dipole placement. Default: "cortex"
%       - "cortex" : Sources on the cortical surface (recommended for EEG).
%       - "volume" : Sources in a regular 3D grid inside the brain volume.
%
%   ChanLocs (string): Path to a custom channel location file (.sfp, .els,
%                      .xyz). Use when the cap is not in the BST templates.
%
%   ChanLocsTemplate (string): Full path to a BST channel template file
%                              (.mat). Use when the cap template is known.
%                              Example: ".../ICBM152/channel_GSN_HydroCel_256_E001.mat"
%
%   SelectTemplate (logical): If true, opens an interactive GUI to select
%                             the channel template from the BST database.
%                             The list is automatically filtered based on
%                             the anatomy used for the subject. Default: false.
%
%   ProtocolName (string): Name of the Brainstorm protocol. Used in
%                          standalone mode (InputData is a string).
%                          Default: "HRB_Protocol".
%
%   BrainstormDbDir (string): Path to the Brainstorm database directory.
%                             Default: '<pwd>/brainstorm_db'.
%
%   BemConductivities (double): [OpenMEEG only] Conductivity values for
%                               the 3 BEM layers [scalp, skull, brain].
%                               Default: [1, 0.0125, 1].
%
%   DUNeuroFemType (string): [DUNeuro only] FEM mesh type.
%                            "fitted" | "hexahedral". Default: "fitted".
%
%   DUNeuroSolverType (string): [DUNeuro only] Linear solver type.
%                               "cg" | "dg". Default: "cg".
%
%   DUNeuroSrcModel (string): [DUNeuro only] Source model type.
%                             "venant" | "subtraction" | "partial_integration".
%                             Default: "venant".
%
%   DUNeuroIsotropic (logical): [DUNeuro only] Use isotropic conductivity.
%                               Default: true.
%
%   OutputFolder (string): Folder for output files. Default: 'output/<timestamp>'.
%
% Outputs:
%   EEG: EEGLAB struct with Brainstorm metadata injected in EEG.etc.brainstorm:
%       - headmodel_method : method used for head model computation
%       - headmodel_space  : source space used
%       - protocol         : Brainstorm protocol name
%       - subject          : subject name in Brainstorm
%       - db_path          : path to the Brainstorm database
%
% Notes:
%   - Brainstorm must be installed and accessible in the MATLAB path.
%   - The protocol must already exist in the Brainstorm database.
%     Run HRB_bst_import before this function.
%   - Channel locations must be provided via ChanLocs, ChanLocsTemplate,
%     or SelectTemplate=true. The head model cannot be computed without
%     valid electrode positions.
%   - OpenMEEG and DUNeuro require external software installations.
%     Use 3-ShellSphere for a dependency-free alternative.
%
% Authors: Ettore Napoli, University of Bologna, 2026
%
% See also: HRB_BST_IMPORT, HRB_BST_INVERSE

arguments(Input)
    InputData % struct (RAM) or string/char (filepath)
    opt.ChanLocs string = "" % Path to custom chan loc file
    opt.ChanLocsTemplate string = "" % Template BST
    opt.SelectTemplate logical = false % Show available BST template to choose from
    opt.Method string {mustBeMember(opt.Method, ["OpenMEEG", "3-ShellSphere", "DUNeuro"])} = "OpenMEEG"
    opt.SourceSpace string {mustBeMember(opt.SourceSpace, ["cortex","volume"])} = "cortex"
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

    % *** NEW: extract BST condition name from metadata ***
    if ~isSubjName && isfield(InputData.etc.brainstorm, 'condition')
        bstCondition = InputData.etc.brainstorm.condition;
    else
        bstCondition = '';
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
    brainstorm server;

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
    protocolDir = fullfile(dbDir, protocolName);
    if exist(protocolDir, 'dir')
        log.info(sprintf("Protocol '%s' found on disk. Reloading DB...", protocolName));
        db_reload_database('current');
        iProtocol = bst_get('Protocol', protocolName);
    end
end
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
    'condition', bstCondition,  % *** FIX: was '' *** ...
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
        [sSubject, ~] = bst_get('Subject', char(subjName));
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

    % *** NEW: skip headmodel if already computed for this subject/method ***
    % The headmodel depends only on anatomy + electrode positions, NOT on the
    % EEG data content (filter, ICA, etc.). In a multiverse pipeline where the
    % filter branches before this step, every branch would recompute the same
    % headmodel. This check detects an existing headmodel with the same BST
    % comment string and skips recomputation, saving significant time.
    if local_headmodelExists(subjName, comment)
        log.info(sprintf( ...
            "*** SKIP: Headmodel ''%s'' already exists for subject ''%s''. Skipping recomputation. ***", ...
            comment, subjName));
    else

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
    end % *** NEW: end of skip-if-exists else block ***

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

% *** NEW: local helper — check if headmodel already computed ***
function found = local_headmodelExists(subjName, comment)
% Returns true if a headmodel with the given BST comment string already
% exists for this subject in the current protocol. Used to avoid redundant
% headmodel computation in multiverse pipelines where a filter (or other
% data-independent) step branches before the headmodel step.
    found = false;
    try
        [sSubject, ~] = bst_get('Subject', char(subjName));
        if isempty(sSubject), return; end
        [sStudies, ~] = bst_get('StudyWithSubject', sSubject.FileName);
        for i = 1:length(sStudies)
            if ~isempty(sStudies(i).HeadModel)
                if any(strcmpi({sStudies(i).HeadModel.Comment}, comment))
                    found = true;
                    return;
                end
            end
        end
    catch
        found = false; % If check fails, compute normally
    end
end
