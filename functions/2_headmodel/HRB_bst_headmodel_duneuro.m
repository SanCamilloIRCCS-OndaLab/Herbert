function EEG = HRB_bst_headmodel_duneuro(InputData, opt)
% HRB_BST_HEADMODEL_DUNEURO - Compute head model with DUNeuro FEM.
% Method-specific sub-function of HRB_bst_headmodel. Most accurate for
% complex geometries. Requires DUNeuro installed in Brainstorm.
% Reference: Vorwerk et al. (2018) BioMed Eng Online.
% Noise covariance is NOT computed here. Use HRB_bst_noisecov after filter.
%
% Usage:
%   >>> EEG = HRB_bst_headmodel_duneuro(EEG, 'DUNeuroFemType','hexahedral');
%
% Method-specific parameters:
%   DUNeuroFemType (string):    "fitted" (default) | "hexahedral"
%   DUNeuroSolverType (string): "cg" (default) | "dg"
%   DUNeuroSrcModel (string):   "venant" (default) | "subtraction" | "partial_integration"
%   DUNeuroIsotropic (logical): default true
%
% Authors: Ettore Napoli, University of Bologna, 2026
% See also: HRB_BST_HEADMODEL, HRB_BST_HEADMODEL_OPENMEEG, HRB_BST_HEADMODEL_SPHERE

arguments(Input)
    InputData
    opt.DUNeuroFemType string {mustBeMember(opt.DUNeuroFemType, ["fitted","hexahedral"])} = "fitted"
    opt.DUNeuroSolverType string {mustBeMember(opt.DUNeuroSolverType, ["cg","dg"])} = "cg"
    opt.DUNeuroSrcModel string {mustBeMember(opt.DUNeuroSrcModel, ["venant","subtraction","partial_integration"])} = "venant"
    opt.DUNeuroIsotropic logical = true
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
    brainstorm nogui;
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
    error("HRB:ProtocolNotFound","Protocol '%s' not found.", protocolName);
end
gui_brainstorm('SetCurrentProtocol', iProtocol);

recordings = bst_process('CallProcess','process_select_files_data',[],[], ...
    'subjectname',subjName,'condition','','tag','', ...
    'includebad',1,'includeintra',1,'includecommon',1);
if isempty(recordings)
    error("HRB:NoRecordings","No recordings for subject '%s'.", subjName);
end

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

    openmeegStruct = struct('BemFiles',{{}},'BemNames',{{'Scalp','Skull','Brain'}}, ...
        'BemCond',[1,0.0125,1],'BemSelect',[1,1,1], ...
        'isAdjoint',0,'isAdaptative',1,'isSplit',0,'SplitLength',4000);
    nirstormStruct = struct('FluenceFolder', ...
        'https://neuroimage.usc.edu/resources/nst_data/fluence/', ...
        'smoothing_method','geodesic_dist','smoothing_fwhm',10);

    duneuroStruct = struct(...
        'FemCond',[],'FemSelect',[],'UseTensor',0, ...
        'Isotropic',double(config.DUNeuroIsotropic),'SrcShrink',0,'SrcForceInGM',0, ...
        'FemType',char(config.DUNeuroFemType), ...
        'SolverType',char(config.DUNeuroSolverType), ...
        'GeometryAdapted',0,'Tolerance',1e-08,'ElecType','normal', ...
        'MegIntorderadd',0,'MegType','physical', ...
        'SolvSolverType',char(config.DUNeuroSolverType), ...
        'SolvPrecond','amg','SolvSmootherType','ssor','SolvIntorderadd',0, ...
        'DgSmootherType','ssor','DgScheme','sipg','DgPenalty',20, ...
        'DgEdgeNormType','houston','DgWeights',1,'DgReduction',1, ...
        'SolPostProcess',1,'SolSubstractMean',0,'SolSolverReduction',1e-10, ...
        'SrcModel',char(config.DUNeuroSrcModel), ...
        'SrcIntorderadd',0,'SrcIntorderadd_lb',2,'SrcNbMoments',3, ...
        'SrcRefLen',20,'SrcWeightExp',1,'SrcRelaxFactor',6, ...
        'SrcMixedMoments',1,'SrcRestrict',1,'SrcInit','closest_vertex', ...
        'BstSaveTransfer',0,'BstEegTransferFile','eeg_transfer.dat', ...
        'BstMegTransferFile','meg_transfer.dat', ...
        'BstEegLfFile','eeg_lf.dat','BstMegLfFile','meg_lf.dat', ...
        'UseIntegrationPoint',1,'EnableCacheMemory',0,'MegPerBlockOfSensor',0);

    if local_headmodelExists
        log.info("Skip: headmodel 'FEM' already exists. Skipping recomputation");
    else
    log.info(sprintf("Computing head model (DUNeuro FEM, type=%s, space: %s)...", ...
        config.DUNeuroFemType, config.SourceSpace));

    recordings = bst_process('CallProcess','process_headmodel',recordings,[], ...
        'Comment','FEM','sourcespace',spaceValue, ...
        'meg',1,'eeg',4,'ecog',2,'seeg',2,'nirs',1, ...
        'openmeeg',openmeegStruct,'nirstorm',nirstormStruct, ...
        'duneuro',duneuroStruct,'channelfile','');

    if isempty(recordings)
        error("HRB:HeadModelFailed","DUNeuro head model failed for subject '%s'.", subjName);
    end
    log.info("Head model computed successfully (DUNeuro FEM).");

catch ME
    log.error(sprintf("HRB_bst_headmodel_duneuro failed: %s", ME.message));
    rethrow(ME);
end

if isSubjName
    EEG = struct(); EEG.etc.brainstorm = struct();
else
    EEG = InputData;
end

EEG.etc.brainstorm.headmodel_method = 'DUNeuro';
EEG.etc.brainstorm.headmodel_space  = char(config.SourceSpace);
EEG.etc.brainstorm.protocol         = protocolName;
EEG.etc.brainstorm.subject          = subjName;
EEG.etc.brainstorm.db_path          = dbDir;

if config.Save
    logParams = unpackStruct(logConfig);
    HRB_saveData(EEG,"Name",config.SaveName,"Folder",module, ...
        "OutputFolder",config.OutputFolder,logParams{:});
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