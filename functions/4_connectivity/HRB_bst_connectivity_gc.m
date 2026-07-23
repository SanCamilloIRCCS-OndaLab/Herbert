function EEG = HRB_bst_connectivity_gc(InputData, opt)
% HRB_BST_CONNECTIVITY_GC - Compute bivariate Granger causality.
% Reference: Granger (1969); Seth et al. (2015).
% See also: HRB_BST_CONNECTIVITY

arguments(Input)
    InputData
    opt.GCMethod string {mustBeMember(opt.GCMethod, ["bst","mvgc"])} = "bst"
    opt.GCDirection string {mustBeMember(opt.GCDirection, ["in","out","both"])} = "both"
    opt.GCOrder double = 10
    opt.Topology string {mustBeMember(opt.Topology, ["1xN","NxN"])} = "NxN"
    opt.TimeWindow double = []
    opt.SelectScouts logical = true
    opt.Atlas string = ""
    opt.Scouts string = ""
    opt.FlattenPCA logical = false
    opt.ScoutFunction string {mustBeMember(opt.ScoutFunction, ["mean","max","std","pca"])} = "mean"
    opt.ScoutTime string {mustBeMember(opt.ScoutTime, ["before","after"])} = "after"
    opt.FreqBands cell = {}
    opt.AvgWinLength double = 1
    opt.AvgWinOverlap double = 50
    opt.SaveMode string {mustBeMember(opt.SaveMode, ["separately","average","concatenate"])} = "separately"
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

module = "connectivity";
config    = HRB_loadConfig(module, "bst_connectivity", opt);
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
        error("HRB:MissingMetadata","EEG.etc.brainstorm not found.");
    end
    if ~isfield(InputData.etc.brainstorm,'inverse_method')
        error("HRB:MissingInverse","No inverse solution found. Run HRB_bst_inverse first.");
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
    dbDir = fullfile(pwd, 'brainstorm_db');
end
if ~exist(dbDir,'dir'), mkdir(dbDir); end

bst_working = false;
if brainstorm('status')
    try, bst_get('BrainstormDbDir'); bst_working = true; catch, end
end
if ~bst_working
    % Use 'server' mode: fully headless, no Java/X11 required.
    % 'nogui' mode still needs an X display on headless Linux servers.
    brainstorm server;
    timeout = 120; t = tic;
    while toc(t) < timeout
        try, bst_get('BrainstormDbDir'); break; catch, pause(1); end
    end
    if toc(t) >= timeout
        error("HRB:BrainstormTimeout","Brainstorm failed to initialize within %d seconds.", timeout);
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
pause(2);
t = tic; while toc(t) < 30; try, bst_get('BrainstormDbDir'); break; catch, pause(0.5); end; end

hasExplicitScouts = strlength(config.Atlas) > 0 && ~all(strlength(config.Scouts)==0);
if config.SelectScouts && ~hasExplicitScouts
    [sSubject, ~] = bst_get('Subject', char(subjName));
    if isempty(sSubject) || isempty(sSubject.Surface)
        error("HRB:NoSurface","No surfaces for subject '%s'.", subjName);
    end
    cortexFile = sSubject.Surface(sSubject.iCortex).FileName;
    SurfaceMat = in_tess_bst(cortexFile);
    if isempty(SurfaceMat.Atlas)
        error("HRB:NoAtlas","No atlases on cortex for subject '%s'.", subjName);
    end
    atlasNames = {SurfaceMat.Atlas.Name};
end

log.info(sprintf("bstCondition: '%s'", bstCondition));
log.info(sprintf("SaveName: '%s'", config.SaveName));

inverseComment = '';
if ~isSubjName && isfield(InputData.etc.brainstorm, 'inverse_comment')
    inverseComment = char(InputData.etc.brainstorm.inverse_comment);
end

sFiles = bst_process('CallProcess','process_select_files_results',[],[], ...
    'subjectname', subjName, 'condition', bstCondition, ...
    'tag', inverseComment, ...
    'includebad',0,'includeintra',1,'includecommon',0);
if isempty(sFiles)
    error("HRB:NoSourceFiles","No source files for '%s'.", subjName);
end
log.info(sprintf("Found %d source file(s).", length(sFiles)));

if isempty(config.FreqBands)
    freqBands = {'delta','2, 4','mean'; 'theta','5, 7','mean'; 'alpha','8, 12','mean'; ...
        'beta','13, 30','mean'; 'gamma','31, 80','mean'};
else
    freqBands = config.FreqBands;
end

% Use Atlas/Scouts from config when provided; only fall back to the
% interactive listdlg picker when SelectScouts=true AND no explicit
% Atlas/Scouts were given (e.g. ad-hoc single-universe runs).
hasExplicitScouts = strlength(config.Atlas) > 0 && ~all(strlength(config.Scouts)==0);

if config.SelectScouts && ~hasExplicitScouts
    [iAtlas, ok] = listdlg('ListString',atlasNames,'SelectionMode','single', ...
        'Name','Select Atlas','PromptString','Select atlas:','ListSize',[400 300]);
    if ~ok, error("HRB:NoAtlasSelected","No atlas selected."); end
    selectedAtlas = atlasNames{iAtlas};
    scoutNames = {SurfaceMat.Atlas(iAtlas).Scouts.Label};
    [iScouts, ok] = listdlg('ListString',scoutNames,'SelectionMode','multiple', ...
        'Name',sprintf('Select ROIs (%s)',selectedAtlas), ...
        'PromptString','Select ROIs:','ListSize',[500 400]);
    if ~ok, error("HRB:NoScoutsSelected","No ROIs selected."); end
    selectedScouts = scoutNames(iScouts);
elseif hasExplicitScouts
    selectedAtlas  = char(config.Atlas);
    selectedScouts = cellstr(config.Scouts);
else
    error("HRB:NoScouts","Provide Atlas and Scouts, or set SelectScouts=true.");
end

scoutsCell = {selectedAtlas, selectedScouts};

switch config.ScoutFunction
    case "mean", scoutFuncStr = 'mean'; case "max", scoutFuncStr = 'max';
    case "std",  scoutFuncStr = 'std';  case "pca", scoutFuncStr = 'pca';
end
switch config.ScoutTime
    case "before", scoutTimeStr = 'before'; case "after", scoutTimeStr = 'after';
end
switch config.SaveMode
    case "separately", outputMode = 1;
    case "concatenate",outputMode = 2;
    case "average",outputMode = 3;
end

try
    ResultsMat = in_bst_results(sFiles(1).FileName, 0);
    isKernelShared = isfield(ResultsMat,'ImagingKernel') && ~isempty(ResultsMat.ImagingKernel);
catch
    isKernelShared = false;
end

if isKernelShared
    log.info("Kernel-shared results. Extracting scout time series first...");
    sFilesInput = bst_process('CallProcess','process_extract_scout',sFiles,[], ...
        'timewindow',config.TimeWindow,'scouts',scoutsCell,'scoutfunc',scoutFuncStr, ...
        'isflip',1,'isnorm',0,'concatenate',0,'save',1, ...
        'addrowcomment',1,'addfilecomment',1);
    if isempty(sFilesInput)
        error("HRB:ExtractScoutsFailed","Scout extraction failed for '%s'.", subjName);
    end
    % Rename scouts in bst GUI
    newComment = char(config.SaveName);
    for iF = 1:length(sFilesInput)
        [sStudy, iStudy] = bst_get('Study', sFilesInput(iF).iStudy);
        iItem = sFilesInput(iF).iItem;

        fullFilePath = file_fullpath(sStudy.Matrix(iItem).FileName);
        matMat = load(fullFilePath, '-mat');
        matMat.Comment = newComment;
        bst_save(fullFilePath, matMat, 'v6');

        sStudy.Matrix(iItem).Comment = newComment;
        bst_set('Study', iStudy, sStudy);
    end
    db_save();

    scoutsCellConn = {};
else
    sFilesInput    = sFiles;
    scoutsCellConn = scoutsCell;
end
useScouts = ~isempty(scoutsCellConn);

pcaEdit = struct('Method','pca','Baseline',[-0.1,0],'DataTimeWindow',[0,1],'RemoveDcOffset','file');
tfEdit  = struct('Comment','Complex','TimeBands',[],'Freqs',{freqBands}, ...
    'ClusterFuncTime','none','Measure','none','Output','all','SaveKernel',0);

try
    switch config.GCDirection
        case "in",   dirVal = 1; case "out", dirVal = 2; case "both", dirVal = 3;
    end
    if strcmp(config.Topology,'NxN')
        if useScouts
            sFilesConn = bst_process('CallProcess','process_granger1n',sFilesInput,[], ...
                'timewindow',config.TimeWindow,'scouts',scoutsCellConn, ...
                'flatten',double(config.FlattenPCA),'scouttime',scoutTimeStr, ...
                'scoutfunc',scoutFuncStr,'removeevoked',0, ...
                'grangermethod',char(config.GCMethod),'grangerorder',config.GCOrder, ...
                'outputmode',outputMode,'source_abs',-1);
        else
            sFilesConn = bst_process('CallProcess','process_granger1n',sFilesInput,[], ...
                'timewindow',config.TimeWindow,'flatten',double(config.FlattenPCA), ...
                'removeevoked',0,'grangermethod',char(config.GCMethod), ...
                'grangerorder',config.GCOrder,'outputmode',outputMode,'source_abs',-1);
        end
    else
        if useScouts
            sFilesConn = bst_process('CallProcess','process_granger1',sFilesInput,[], ...
                'timewindow',config.TimeWindow,'scouts',scoutsCellConn, ...
                'flatten',double(config.FlattenPCA),'scouttime',scoutTimeStr, ...
                'scoutfunc',scoutFuncStr,'removeevoked',0, ...
                'grangermethod',char(config.GCMethod),'direction',dirVal, ...
                'grangerorder',config.GCOrder,'outputmode',outputMode,'source_abs',-1);
        else
            sFilesConn = bst_process('CallProcess','process_granger1',sFilesInput,[], ...
                'timewindow',config.TimeWindow,'flatten',double(config.FlattenPCA), ...
                'removeevoked',0,'grangermethod',char(config.GCMethod),'direction',dirVal, ...
                'grangerorder',config.GCOrder,'outputmode',outputMode,'source_abs',-1);
        end
    end
    if isempty(sFilesConn)
        error("HRB:ConnectivityFailed","Connectivity failed for subject '%s'.", subjName);
    end
    log.info(sprintf("Connectivity computed. %d file(s).", length(sFilesConn)));
catch ME
    log.error(sprintf("HRB_bst_connectivity_gc failed: %s", ME.message));
    rethrow(ME);
end

% Rename connectivity files
newComment = char(config.SaveName);
for iF = 1:length(sFilesConn)
    [sStudy, iStudy] = bst_get('Study', sFilesConn(iF).iStudy);
    iItem = sFilesConn(iF).iItem;

    fullFilePath = file_fullpath(sStudy.Timefreq(iItem).FileName);
    tfMat = load(fullFilePath, '-mat');
    tfMat.Comment = newComment;
    bst_save(fullFilePath, tfMat, 'v6');

    sStudy.Timefreq(iItem).Comment = newComment;
    bst_set('Study', iStudy, sStudy);
end
db_save();

if isSubjName
    EEG = struct(); EEG.etc.brainstorm = struct();
else
    EEG = InputData;
end

EEG.etc.brainstorm.connectivity_metric        = 'gc';
EEG.etc.brainstorm.connectivity_topology      = char(config.Topology);
EEG.etc.brainstorm.connectivity_files         = {sFilesConn.FileName};
EEG.etc.brainstorm.connectivity_kernel_shared = isKernelShared;
EEG.etc.brainstorm.protocol                   = protocolName;
EEG.etc.brainstorm.subject                    = subjName;
EEG.etc.brainstorm.db_path                    = dbDir;

if config.Save
    logParams = unpackStruct(logConfig);
    HRB_saveData(EEG,"Name",config.SaveName,"Folder",module, ...
        "OutputFolder",config.OutputFolder,logParams{:});
end

end
