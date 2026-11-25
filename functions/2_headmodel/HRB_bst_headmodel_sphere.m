function EEG = HRB_bst_headmodel_sphere(InputData, opt)
% HRB_BST_HEADMODEL_SPHERE - Compute head model with 3-Shell Sphere.
% Method-specific sub-function of HRB_bst_headmodel. Fast, no external
% dependencies. Use as fallback or sensitivity check in multiverse.
% Noise covariance is NOT computed here. Use HRB_bst_noisecov after filter.
%
% Usage:
%   >>> EEG = HRB_bst_headmodel_sphere(EEG, 'SelectTemplate', true);
%
% Authors: Ettore Napoli, University of Bologna, 2026
% See also: HRB_BST_HEADMODEL, HRB_BST_HEADMODEL_OPENMEEG, HRB_BST_HEADMODEL_DUNEURO

arguments(Input)
    InputData
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

module = "headmodel";
config    = HRB_loadConfig(module, "bst_headmodel", opt);
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
    subjName = InputData.etc.brainstorm.subject;
    protocolName = InputData.etc.brainstorm.protocol;
    log.info(sprintf("Input mode: EEG struct (subject: %s)", subjName));
end

%% Extract BST condition name from metadata
if ~isSubjName && isfield(InputData.etc.brainstorm, 'condition')
    bstCondition = InputData.etc.brainstorm.condition;
else
    bstCondition = '';
end

%% 2. Output folder
if config.OutputFolder == ""
    gcfg = HRB_loadConfig("general", "save");
    config.OutputFolder = gcfg.OutputFolder;
end
if ~exist(config.OutputFolder,'dir'), mkdir(config.OutputFolder); end

%% 3. Brainstorm: start (server mode), DB, protocol
dbDir = HRB_bst_connect(config.BrainstormDbDir, protocolName, log);

%% 7. Select recordings
recordings = bst_process('CallProcess','process_select_files_data',[],[], ...
    'subjectname', subjName, 'condition', '', 'tag', '', ...
    'includebad',1,'includeintra',1,'includecommon',1);
if isempty(recordings)
    error("HRB:NoRecordings","No recordings for subject '%s'.", subjName);
end

%% 8. Channel location + headmodel
if ~config.SelectTemplate && strlength(config.ChanLocsTemplate)==0 && strlength(config.ChanLocs)==0
    error("HRB:NoChanLocs","Provide ChanLocsTemplate, ChanLocs, or SelectTemplate=true.");
end

try
    if config.SelectTemplate
        [sSubject,~] = bst_get('Subject', char(subjName));
        anatFile = sSubject.Anatomy(sSubject.iAnatomy).FileName;
        if contains(anatFile,'@default_subject'), anatName='ICBM152';
        elseif contains(anatFile,'@colin27'),     anatName='Colin27';
        else,                                     anatName='NotAligned'; end
        EEGDefaults = bst_get('EegDefaults');
        iGroup = find(strcmpi({EEGDefaults.name}, anatName));
        templateNames = {EEGDefaults(iGroup).contents.name};
        templatePaths = {EEGDefaults(iGroup).contents.fullpath};
        [iSel,ok] = listdlg('ListString',templateNames,'SelectionMode','single', ...
            'Name','Select EEG Template','PromptString','Select template.','ListSize',[400 400]);
        if ~ok, error("HRB:NoTemplateSelected","No template selected."); end
        config.ChanLocsTemplate = string(templatePaths{iSel});
    end

    if strlength(config.ChanLocsTemplate) > 0
        recordings = bst_process('CallProcess','process_channel_addloc',recordings,[], ...
            'channelfile',{char(config.ChanLocsTemplate),'BST'}, ...
            'usedefault','','fixunits',1,'vox2ras',1,'mrifile',{'',''},'fiducials',[]);
    elseif strlength(config.ChanLocs) > 0
        recordings = bst_process('CallProcess','process_channel_addloc',recordings,[], ...
            'channelfile',char(config.ChanLocs), ...
            'usedefault','','fixunits',1,'vox2ras',1,'mrifile',{'',''},'fiducials',[]);
    end
    if isempty(recordings)
        error("HRB:ChanLocFailed","Channel location failed for '%s'.", subjName);
    end

    switch config.SourceSpace
        case "cortex", spaceValue = 1;
        case "volume", spaceValue = 2;
    end

    % BST requires these structs even when unused
    openmeegStruct = struct('BemFiles',{{}},'BemNames',{{'Scalp','Skull','Brain'}}, ...
        'BemCond',[1,0.0125,1],'BemSelect',[1,1,1], ...
        'isAdjoint',0,'isAdaptative',1,'isSplit',0,'SplitLength',4000);
    nirstormStruct = struct('FluenceFolder', ...
        'https://neuroimage.usc.edu/resources/nst_data/fluence/', ...
        'smoothing_method','geodesic_dist','smoothing_fwhm',10);

    % Headmodel identity = method + forward model parameters
    hmComment = sprintf('3_Shell_%s', char(config.SourceSpace));
    
    % Skip if headmodel already computed for this subject/method
    if HRB_bst_headmodelExists(subjName, hmComment)
        log.info(sprintf("Skip: headmodel '%s' already exists. Skipping recomputation.", hmComment));

    else
        log.info(sprintf("Computing head model (3-Shell Sphere, space: %s)...", config.SourceSpace));
        recordings = bst_process('CallProcess','process_headmodel',recordings,[], ...
            'Comment',hmComment,'sourcespace',spaceValue, ...
            'meg',1,'eeg',2,'ecog',2,'seeg',2,'nirs',1, ...
            'openmeeg',openmeegStruct,'nirstorm',nirstormStruct,'channelfile','');

        if isempty(recordings)
            error("HRB:HeadModelFailed","3-Shell Sphere failed for subject '%s'.", subjName);
        end
        log.info("Head model computed successfully (3-Shell Sphere).");
    end  % end skip check

catch ME
    log.error(sprintf("HRB_bst_headmodel_sphere failed: %s", ME.message));
    rethrow(ME);
end

%% 9. Build output EEG struct
if isSubjName
    EEG = struct(); EEG.etc.brainstorm = struct();
else
    EEG = InputData;
end

EEG.etc.brainstorm.headmodel_method = '3-ShellSphere';
EEG.etc.brainstorm.headmodel_comment = hmComment;
EEG.etc.brainstorm.headmodel_space  = char(config.SourceSpace);
EEG.etc.brainstorm.protocol         = protocolName;
EEG.etc.brainstorm.subject          = subjName;
EEG.etc.brainstorm.db_path          = dbDir;

%% 10. Save
if config.Save
    logParams = unpackStruct(logConfig);
    HRB_saveData(EEG,"Name",config.SaveName,"Folder",module, ...
        "OutputFolder",config.OutputFolder,logParams{:});
end

end