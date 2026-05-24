function EEG = HRB_bst_headmodel_openmeeg(InputData, opt)
% HRB_BST_HEADMODEL_OPENMEEG - Compute head model with OpenMEEG BEM.
% Method-specific sub-function of HRB_bst_headmodel. Computes a 3-layer
% Boundary Element Model (scalp / skull / brain). Most accurate option
% for EEG with realistic head geometry. Requires OpenMEEG installed.
%
% Noise covariance is NOT computed here. Use HRB_bst_noisecov after filter.
%
% Usage:
%   >>> EEG = HRB_bst_headmodel_openmeeg(EEG, 'SelectTemplate', true);
%   >>> EEG = HRB_bst_headmodel_openmeeg('Sub01', 'ChanLocsTemplate', "path.mat");
%
% Parameters:
%   InputData: EEGLAB struct with EEG.etc.brainstorm, or subject name string.
%
% Other Parameters:
%   BemConductivities (1x3 double): [scalp, skull, brain]. Default [1, 0.0125, 1].
%   SourceSpace (string): "cortex" (default) | "volume"
%   ChanLocs / ChanLocsTemplate / SelectTemplate
%   ProtocolName (string): default "HRB_Protocol"
%   BrainstormDbDir (string): default '<pwd>/brainstorm_db'
%   Save / SaveName / OutputFolder, Log*
%
% Authors: Ettore Napoli, University of Bologna, 2026
% See also: HRB_BST_HEADMODEL, HRB_BST_HEADMODEL_SPHERE, HRB_BST_HEADMODEL_DUNEURO

arguments(Input)
    InputData
    opt.BemConductivities double = [1, 0.0125, 1]
    opt.SourceSpace string {mustBeMember(opt.SourceSpace, ["cortex","volume"])} = "cortex"
    opt.ChanLocs string = ""
    opt.ChanLocsTemplate string = ""
    opt.SelectTemplate logical = false
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
if ~exist(dbDir, 'dir'), mkdir(dbDir); end
log.info(sprintf("Brainstorm DB: %s", dbDir));

%% 4. Start Brainstorm
if ~brainstorm('status')
    log.info("Starting Brainstorm (nogui)...");
    brainstorm nogui;
    timeout = 60; t = tic;
    while toc(t) < timeout
        try, bst_get('BrainstormDbDir'); break; catch, pause(1); end
    end
    if toc(t) >= timeout
        error("HRB:BrainstormTimeout", "Brainstorm failed to initialize within %d seconds.", timeout);
    end
    log.info("Brainstorm initialized successfully.");
end

%% 5. Switch DB if needed
currentDbDir = bst_get('BrainstormDbDir');
if ~strcmpi(strip(currentDbDir, 'right', filesep), strip(dbDir, 'right', filesep))
    bst_set('BrainstormDbDir', dbDir);
    gui_brainstorm('UpdateProtocolsList');
end

%% 6. Activate protocol
iProtocol = bst_get('Protocol', protocolName);
if isempty(iProtocol)
    error("HRB:ProtocolNotFound", "Protocol '%s' not found. Run HRB_bst_import first.", protocolName);
end
gui_brainstorm('SetCurrentProtocol', iProtocol);
log.info(sprintf("Protocol '%s' set as current.", protocolName));

%% 7. Select recordings
recordings = bst_process('CallProcess', 'process_select_files_data', [], [], ...
    'subjectname', subjName, 'condition', '', 'tag', '', ...
    'includebad', 1, 'includeintra', 1, 'includecommon', 1);
if isempty(recordings)
    error("HRB:NoRecordings", "No recordings found for subject '%s'.", subjName);
end

%% 8. Channel location
if ~config.SelectTemplate && strlength(config.ChanLocsTemplate) == 0 && strlength(config.ChanLocs) == 0
    error("HRB:NoChanLocs", "Provide ChanLocsTemplate, ChanLocs, or set SelectTemplate=true.");
end

try
    if config.SelectTemplate
        [sSubject, ~] = bst_get('Subject', char(subjName));
        anatFile = sSubject.Anatomy(sSubject.iAnatomy).FileName;
        if contains(anatFile, '@default_subject'), anatName = 'ICBM152';
        elseif contains(anatFile, '@colin27'),     anatName = 'Colin27';
        else,                                      anatName = 'NotAligned'; end
        EEGDefaults = bst_get('EegDefaults');
        iGroup = find(strcmpi({EEGDefaults.name}, anatName));
        templateNames = {EEGDefaults(iGroup).contents.name};
        templatePaths = {EEGDefaults(iGroup).contents.fullpath};
        [iSel, ok] = listdlg('ListString', templateNames, 'SelectionMode', 'single', ...
            'Name', 'Select EEG Template', 'PromptString', 'Select channel location template.', ...
            'ListSize', [400 400]);
        if ~ok, error("HRB:NoTemplateSelected", "No template selected. Aborted."); end
        config.ChanLocsTemplate = string(templatePaths{iSel});
        log.info(sprintf("Template selected: %s", config.ChanLocsTemplate));
    end

    if strlength(config.ChanLocsTemplate) > 0
        log.info(sprintf("Adding channel locations from BST template: %s", config.ChanLocsTemplate));
        recordings = bst_process('CallProcess', 'process_channel_addloc', recordings, [], ...
            'channelfile', {char(config.ChanLocsTemplate), 'BST'}, ...
            'usedefault', '', 'fixunits', 1, 'vox2ras', 1, 'mrifile', {'', ''}, 'fiducials', []);
    elseif strlength(config.ChanLocs) > 0
        log.info(sprintf("Adding channel locations from file: %s", config.ChanLocs));
        recordings = bst_process('CallProcess', 'process_channel_addloc', recordings, [], ...
            'channelfile', char(config.ChanLocs), ...
            'usedefault', '', 'fixunits', 1, 'vox2ras', 1, 'mrifile', {'', ''}, 'fiducials', []);
    end
    if isempty(recordings)
        error("HRB:ChanLocFailed", "Failed to add channel locations for subject '%s'.", subjName);
    end
    log.info("Channel locations added successfully.");

    %% 9. Compute head model — OpenMEEG BEM (eeg = 3)
    
    % Check existence of headmodel and skip computation if found
    if local_headmodelExist(subjName, 'BEM')
        local.info("Skip: HeadModel BEM already exists. Skipping recomputation")
    else
    
    switch config.SourceSpace
        case "cortex", spaceValue = 1;
        case "volume", spaceValue = 2;
    end

    openmeegStruct = struct(...
        'BemFiles', {{}}, 'BemNames', {{'Scalp', 'Skull', 'Brain'}}, ...
        'BemCond', config.BemConductivities, 'BemSelect', [1, 1, 1], ...
        'isAdjoint', 0, 'isAdaptative', 1, 'isSplit', 0, 'SplitLength', 4000);

    nirstormStruct = struct(...
        'FluenceFolder', 'https://neuroimage.usc.edu/resources/nst_data/fluence/', ...
        'smoothing_method', 'geodesic_dist', 'smoothing_fwhm', 10);

    log.info(sprintf("Computing head model (OpenMEEG BEM, space: %s)...", config.SourceSpace));
    recordings = bst_process('CallProcess', 'process_headmodel', recordings, [], ...
        'Comment', 'BEM', 'sourcespace', spaceValue, ...
        'meg', 1, 'eeg', 3, 'ecog', 2, 'seeg', 2, 'nirs', 1, ...
        'openmeeg', openmeegStruct, 'nirstorm', nirstormStruct, 'channelfile', '');

    if isempty(recordings)
        error("HRB:HeadModelFailed", "OpenMEEG head model failed for subject '%s'.", subjName);
    end
    log.info("Head model computed successfully (OpenMEEG BEM).");

catch ME
    log.error(sprintf("HRB_bst_headmodel_openmeeg failed: %s", ME.message));
    rethrow(ME);
end

%% 10. Build output EEG struct
if isSubjName
    EEG = struct();
    EEG.etc.brainstorm = struct();
else
    EEG = InputData;
end

EEG.etc.brainstorm.headmodel_method = 'OpenMEEG';
EEG.etc.brainstorm.headmodel_space  = char(config.SourceSpace);
EEG.etc.brainstorm.protocol         = protocolName;
EEG.etc.brainstorm.subject          = subjName;
EEG.etc.brainstorm.db_path          = dbDir;

log.info(sprintf("Output EEG struct ready (subject: %s, method: OpenMEEG).", subjName));

%% 11. Save
if config.Save
    logParams = unpackStruct(logConfig);
    HRB_saveData(EEG, "Name", config.SaveName, "Folder", module, ...
        "OutputFolder", config.OutputFolder, logParams{:});
end

end

%% Helper - check if headmodel already exists
function found = local_headmodelExists(subjName, comment)
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
        found = false;
    end
end