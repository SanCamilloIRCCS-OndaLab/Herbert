function EEG = HRB_bst_connectivity(InputData, opt)
% HRB_bst_connectivity - Computes functional connectivity in Brainstorm
% between brain regions (scouts/ROIs) using source-level data.
% One metric per call — use multiple calls or pipeline steps for multiverse.
%
% Usage:
%   >>> EEG = HRB_bst_connectivity(EEG, 'Metric', 'coh', 'Topology', 'NxN');
%   >>> EEG = HRB_bst_connectivity('Sub01', 'Metric', 'plv', 'Topology', '1xN');
%
% Parameters:
%   InputData: EEGLAB struct (RAM) with EEG.etc.brainstorm populated by
%              previous HRB_bst_* functions, or string with subject name.
%
% Other Parameters:
%
%   Metric (string): Connectivity metric. Default: "coh"
%       - "corr"        : Pearson Correlation
%       - "coh"         : Coherence
%       - "gc"          : Bivariate Granger Causality
%       - "gc_spectral" : Bivariate Spectral Granger Causality
%       - "plv"         : Phase Locking Value / wPLI / Lagged PS
%       - "envelope"    : Envelope Correlation
%       - "pte"         : Phase Transfer Entropy
%
%   Topology (string): Connectivity topology. Default: "NxN"
%       - "NxN" : All ROIs vs all ROIs (full matrix)
%       - "1xN" : One seed ROI vs all others
%
%   TimeWindow (double): [t_start, t_end] in seconds. Default: [] (all)
%
%   SelectScouts (logical): Open interactive GUI to select atlas and ROIs.
%                           Default: true
%
%   Atlas (string): Atlas name (e.g. "Destrieux"). Used if SelectScouts=false.
%   Scouts (string): ROI names. Used if SelectScouts=false.
%
%   FlattenPCA (logical): Flatten unconstrained sources with PCA. Default: false
%
%   ScoutFunction (string): Scout aggregation function. Default: "mean"
%       - "mean" | "max" | "std" | "pca"
%
%   ScoutTime (string): When to apply scout function. Default: "after"
%       - "before" | "after"
%
%   FreqBands (cell): Frequency bands as {name, freqs, method} rows.
%                     Default: standard bands (delta to gamma)
%                     Example: {{'alpha','8,12','mean'},{'beta','13,30','mean'}}
%
%   SaveMode (string): How to save results. Default: "separately"
%       - "separately" : One file per input file
%       - "average"    : Average across files
%       - "concatenate": Concatenate input before computing
%
%   ProtocolName (string): Brainstorm protocol name. Default: "HRB_Protocol"
%   BrainstormDbDir (string): Path to BST database. Default: '<pwd>/brainstorm_db'
%
%   --- Coherence specific ---
%   CohMetric (string): Coherence measure. Default: "mscohere"
%       - "mscohere"   : Magnitude-squared coherence
%       - "icoh"       : Imaginary coherence
%       - "lcohere2019": Lagged coherence
%
%   TFMethod (string): Time-frequency decomposition. Default: "hilbert"
%       - "hilbert" | "morlet" | "stft"
%
%   TimeRes (string): Time resolution. Default: "full"
%       - "full" | "windowed" | "none"
%
%   AvgWinLength (double): Window length in seconds (windowed mode). Default: 1
%   AvgWinOverlap (double): Window overlap in %. Default: 50
%
%   --- Correlation specific ---
%   TimeRes (string): Time resolution. Default: "none"
%       - "windowed" | "none"
%   ScalarProduct (logical): Compute scalar product. Default: false
%
%   --- Granger Causality specific ---
%   GCMethod (string): GC method. Default: "bst"
%       - "bst"  : Unconditional GC
%       - "mvgc" : Conditional GC (MVGC toolbox)
%
%   GCDirection (string): [1xN only] Direction. Default: "both"
%       - "in" | "out" | "both"
%
%   GCOrder (double): Max Granger model order. Default: 10
%
%   --- Spectral GC specific ---
%   MaxFreqRes (double): Max frequency resolution in Hz. Default: 2
%   MaxFreq (double): Highest frequency of interest in Hz. Default: 100
%
%   --- PLV specific ---
%   PLVMetric (string): PLV measure. Default: "wpli"
%       - "plv"   : Phase Locking Value
%       - "ciplv" : Lagged phase synchronization / Corrected imaginary PLV
%       - "wpli"  : Weighted Phase Lag Index
%
%   --- Envelope specific ---
%   EnvMetric (string): Envelope correlation type. Default: "penv"
%       - "penv"  : Non-orthogonalized envelope correlation
%       - "oenv"  : Orthogonalized envelope correlation
%
%   --- PTE specific ---
%   PTENormalized (logical): Return normalized PTE. Default: true
%
% Authors: Ettore Napoli, University of Bologna, 2026
%
% See also: HRB_BST_IMPORT, HRB_BST_HEADMODEL, HRB_BST_INVERSE

arguments(Input)
    InputData  % EEG struct (RAM) or string (subject name)

    % --- Common ---
    opt.Metric string {mustBeMember(opt.Metric, ["corr","coh","gc","gc_spectral","plv","envelope","pte"])} = "coh"
    opt.Topology string {mustBeMember(opt.Topology, ["1xN","NxN"])} = "NxN"
    opt.TimeWindow double = []
    opt.SelectScouts logical = true
    opt.Atlas string = ""
    opt.Scouts string = ""
    opt.FlattenPCA logical = false
    opt.ScoutFunction string {mustBeMember(opt.ScoutFunction, ["mean","max","std","pca"])} = "mean"
    opt.ScoutTime string {mustBeMember(opt.ScoutTime, ["before","after"])} = "after"
    opt.FreqBands cell = {}
    opt.SaveMode string {mustBeMember(opt.SaveMode, ["separately","average","concatenate"])} = "separately"
    opt.AvgWinLength double = 1
    opt.AvgWinOverlap double = 50
    opt.ProtocolName string = "HRB_Protocol"
    opt.BrainstormDbDir string = ""

    % --- Coherence specific ---
    opt.CohMetric string {mustBeMember(opt.CohMetric, ["mscohere","icoh","lcohere2019"])} = "mscohere"
    opt.TFMethod string {mustBeMember(opt.TFMethod, ["hilbert","morlet","stft"])} = "hilbert"
    opt.TimeRes string {mustBeMember(opt.TimeRes, ["full","windowed","none"])} = "full"

    % --- Correlation specific ---
    opt.ScalarProduct logical = false

    % --- Granger Causality specific ---
    opt.GCMethod string {mustBeMember(opt.GCMethod, ["bst","mvgc"])} = "bst"
    opt.GCDirection string {mustBeMember(opt.GCDirection, ["in","out","both"])} = "both"
    opt.GCOrder double = 10

    % --- Spectral GC specific ---
    opt.MaxFreqRes double = 2
    opt.MaxFreq double = 100

    % --- PLV specific ---
    opt.PLVMetric string {mustBeMember(opt.PLVMetric, ["plv","ciplv","wpli"])} = "wpli"

    % --- Envelope specific ---
    opt.EnvMetric string {mustBeMember(opt.EnvMetric, ["penv","oenv"])} = "penv"

    % --- PTE specific ---
    opt.PTENormalized logical = true

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
module = "connectivity";

%% Parsing Arguments
config = HRB_loadConfig(module, "bst_connectivity", opt);

%% Logger
logConfig = HRB_loadConfig(module, "logging", opt);
log = HRB_loggerSetUp(module, logConfig);

% =========================================================================
%% 1. Input type detection
% =========================================================================
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
            "EEG.etc.brainstorm not found. Run HRB_bst_inverse before HRB_bst_connectivity.");
    end
    if ~isfield(InputData.etc.brainstorm, 'inverse_method')
        error("HRB:MissingInverse", ...
            "No inverse solution found. Run HRB_bst_inverse first.");
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

% =========================================================================
%% 2. Output folder
% =========================================================================
if config.OutputFolder == ""
    timestamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
    config.OutputFolder = fullfile("output", timestamp);
end
if ~exist(config.OutputFolder, 'dir')
    mkdir(config.OutputFolder);
end

% =========================================================================
%% 3. Brainstorm database location
% =========================================================================
if strlength(config.BrainstormDbDir) > 0
    dbDir = char(config.BrainstormDbDir);
else
    dbDir = fullfile(pwd, 'brainstorm_db');
end
if ~exist(dbDir, 'dir')
    mkdir(dbDir);
end
log.info(sprintf("Brainstorm DB: %s", dbDir));

% =========================================================================
%% 4. Start Brainstorm
% =========================================================================
bst_working = false;
if brainstorm('status')
    try
        bst_get('BrainstormDbDir');
        bst_working = true;
    catch
        bst_working = false;
    end
end

if ~bst_working
    log.info("Starting Brainstorm (nogui)...");
    brainstorm nogui;
    timeout = 120;
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

% =========================================================================
%% 5. Manage Protocol
% =========================================================================
% Rescan DB directory to discover protocols created by other BST instances.
gui_brainstorm('UpdateProtocolsList');
iProtocol = bst_get('Protocol', protocolName);  % ← era "Protocol =" (typo)
if isempty(iProtocol)
    error("HRB:ProtocolNotFound", ...
        "Protocol '%s' not found. Run HRB_bst_import first.", protocolName);
end
log.info(sprintf("Setting current protocol: %s", protocolName));
gui_brainstorm('SetCurrentProtocol', iProtocol);

% Wait for BST to finish loading protocol
pause(2);
t = tic;
while toc(t) < 30
    try
        bst_get('BrainstormDbDir');
        break;
    catch
        pause(0.5);
    end
end

% Get subject info BEFORE any bst_process call (which resets BST state)
if config.SelectScouts
    [sSubject, ~] = bst_get('Subject', char(subjName));
    if isempty(sSubject) || isempty(sSubject.Surface)
        error("HRB:NoSurface", "No surfaces found for subject '%s'.", subjName);
    end
    iCortex = sSubject.iCortex;
    if isempty(iCortex)
        error("HRB:NoCortex", "No cortex surface found for subject '%s'.", subjName);
    end
    cortexFile = sSubject.Surface(iCortex).FileName;
    SurfaceMat = in_tess_bst(cortexFile);
    if isempty(SurfaceMat.Atlas)
        error("HRB:NoAtlas", "No atlases found on cortex surface for subject '%s'.", subjName);
    end
    atlasNames = {SurfaceMat.Atlas.Name};
end

% =========================================================================
%% 6. Select source result files from DB
% =========================================================================
sFiles = bst_process('CallProcess', 'process_select_files_results', [], [], ...
    'subjectname',   subjName, ...
    'condition',     '', ...
    'tag',           '', ...
    'includebad',    0, ...
    'includeintra',  1, ...
    'includecommon', 0);

if isempty(sFiles)
    error("HRB:NoSourceFiles", ...
        "No source result files found for subject '%s'. Run HRB_bst_inverse first.", subjName);
end
log.info(sprintf("Found %d source file(s) for subject '%s'.", length(sFiles), subjName));

% =========================================================================
%% 7. Scout selection
% =========================================================================

% Default frequency bands
defaultFreqBands = {
    'delta', '2, 4',   'mean';
    'theta', '5, 7',   'mean';
    'alpha', '8, 12',  'mean';
    'beta',  '13, 30', 'mean';
    'gamma', '31, 80', 'mean'
    };

if isempty(config.FreqBands)
    freqBands = defaultFreqBands;
else
    freqBands = config.FreqBands;
end

% Scout selection
if config.SelectScouts

    % Select atlas
    [iAtlas, ok] = listdlg(...
        'ListString',   atlasNames, ...
        'SelectionMode','single', ...
        'Name',         'Select Atlas', ...
        'PromptString', 'Select the atlas for connectivity analysis:', ...
        'ListSize',     [400 300]);
    if ~ok
        error("HRB:NoAtlasSelected", "No atlas selected. Aborted.");
    end
    selectedAtlas = atlasNames{iAtlas};
    log.info(sprintf("Atlas selected: %s", selectedAtlas));

    % Select ROIs from atlas
    scoutNames = {SurfaceMat.Atlas(iAtlas).Scouts.Label};
    [iScouts, ok] = listdlg(...
        'ListString',   scoutNames, ...
        'SelectionMode','multiple', ...
        'Name',         sprintf('Select ROIs (%s)', selectedAtlas), ...
        'PromptString', 'Select ROIs for connectivity analysis:', ...
        'ListSize',     [500 400]);
    if ~ok
        error("HRB:NoScoutsSelected", "No ROIs selected. Aborted.");
    end
    selectedScouts = scoutNames(iScouts);
    log.info(sprintf("Selected %d ROI(s): %s", length(selectedScouts), strjoin(selectedScouts, ', ')));

    % For 1xN: select seed ROI
    if strcmp(config.Topology, '1xN')
        [iSeed, ok] = listdlg(...
            'ListString',   selectedScouts, ...
            'SelectionMode','single', ...
            'Name',         'Select Seed ROI', ...
            'PromptString', 'Select the seed ROI for 1xN connectivity:', ...
            'ListSize',     [500 300]);
        if ~ok
            error("HRB:NoSeedSelected", "No seed ROI selected. Aborted.");
        end
        seedROI = selectedScouts{iSeed};
        log.info(sprintf("Seed ROI: %s", seedROI));
    end

else
    % Use parameters from config
    if strlength(config.Atlas) == 0 || strlength(config.Scouts) == 0
        error("HRB:NoScouts", ...
            "Provide 'Atlas' and 'Scouts', or set 'SelectScouts=true'.");
    end
    selectedAtlas  = char(config.Atlas);
    selectedScouts = cellstr(config.Scouts);
    if strcmp(config.Topology, '1xN')
        seedROI = selectedScouts{1};
        log.info(sprintf("Seed ROI (first in list): %s", seedROI));
    end
end

% Build scouts cell for BST
scoutsCell = {selectedAtlas, selectedScouts};

% Scout function mapping
switch config.ScoutFunction
    case "mean",  scoutFuncStr = 'mean';
    case "max",   scoutFuncStr = 'max';
    case "std",   scoutFuncStr = 'std';
    case "pca",   scoutFuncStr = 'pca';
end

% Scout time mapping
switch config.ScoutTime
    case "before", scoutTimeStr = 'before';
    case "after",  scoutTimeStr = 'after';
end

% Save mode mapping
switch config.SaveMode
    case "separately",  outputMode = 'input';
    case "average",     outputMode = 'avg';
    case "concatenate", outputMode = 'concat';
end

% =========================================================================
%% 6b. Detect kernel-shared results and extract scout time series if needed
% =========================================================================
% Kernel-shared results (ImagingKernel not empty) need scout extraction
% before connectivity computation, otherwise BST ignores the scouts
% parameter and computes on all cortical vertices.
try
    ResultsMat = in_bst_results(sFiles(1).FileName, 0);
    isKernelShared = isfield(ResultsMat, 'ImagingKernel') && ~isempty(ResultsMat.ImagingKernel);
catch
    isKernelShared = false;
end

if isKernelShared
    log.info("Kernel-shared results detected. Extracting scout time series first...");
    sFilesInput = bst_process('CallProcess', 'process_extract_scout', sFiles, [], ...
        'timewindow',    config.TimeWindow, ...
        'scouts',        scoutsCell, ...
        'scoutfunc',     scoutFuncStr, ...
        'isflip',        1, ...
        'isnorm',        0, ...
        'concatenate',   0, ...
        'save',          1, ...
        'addrowcomment', 1, ...
        'addfilecomment', 1);
    if isempty(sFilesInput)
        error("HRB:ExtractScoutsFailed", ...
            "Scout extraction failed for subject '%s'.", subjName);
    end
    log.info(sprintf("Extracted %d scout time series file(s).", length(sFilesInput)));
    % After extraction, scouts are already ROI time series — no need to
    % pass scouts parameter to connectivity processes
    scoutsCellConn = {};
else
    log.info("Full results detected. Using source files directly with scout parameter.");
    sFilesInput  = sFiles;
    scoutsCellConn = scoutsCell;
end

% =========================================================================
%% 8. Compute Connectivity
% =========================================================================
try
    log.info(sprintf("Computing connectivity (metric: %s, topology: %s)...", ...
        config.Metric, config.Topology));

    % PCA options struct
    pcaEdit = struct(...
        'Method',         'pca', ...
        'Baseline',       [-0.1, 0], ...
        'DataTimeWindow', [0, 1], ...
        'RemoveDcOffset', 'file');

    % TF options struct for freq-based methods
    tfEdit = struct(...
        'Comment',         'Complex', ...
        'TimeBands',       [], ...
        'Freqs',           {freqBands}, ...
        'ClusterFuncTime', 'none', ...
        'Measure',         'none', ...
        'Output',          'all', ...
        'SaveKernel',      0);

    % Helper: build scouts argument — empty cell means no scouts param needed
    % (already extracted). Non-empty means pass to BST process.
    useScouts = ~isempty(scoutsCellConn);

    switch config.Metric

        % -----------------------------------------------------------------
        case "corr"
        % -----------------------------------------------------------------
            switch config.TimeRes
                case "windowed", timeResStr = 'windowed';
                case "none",     timeResStr = 'none';
                otherwise,       timeResStr = 'none';
            end

            if strcmp(config.Topology, 'NxN')
                processName = 'process_corr1n';
            else
                processName = 'process_corr1';
            end

            if useScouts
                sFilesConn = bst_process('CallProcess', processName, sFilesInput, [], ...
                    'timewindow',    config.TimeWindow, ...
                    'scouts',        scoutsCellConn, ...
                    'flatten',       double(config.FlattenPCA), ...
                    'scouttime',     scoutTimeStr, ...
                    'scoutfunc',     scoutFuncStr, ...
                    'scoutfuncaft',  scoutFuncStr, ...
                    'pcaedit',       pcaEdit, ...
                    'timeres',       timeResStr, ...
                    'avgwinlength',  config.AvgWinLength, ...
                    'avgwinoverlap', config.AvgWinOverlap, ...
                    'scalarprod',    double(config.ScalarProduct), ...
                    'outputmode',    outputMode);
            else
                sFilesConn = bst_process('CallProcess', processName, sFilesInput, [], ...
                    'timewindow',    config.TimeWindow, ...
                    'flatten',       double(config.FlattenPCA), ...
                    'timeres',       timeResStr, ...
                    'avgwinlength',  config.AvgWinLength, ...
                    'avgwinoverlap', config.AvgWinOverlap, ...
                    'scalarprod',    double(config.ScalarProduct), ...
                    'outputmode',    outputMode);
            end

        % -----------------------------------------------------------------
        case "coh"
        % -----------------------------------------------------------------
            if strcmp(config.Topology, 'NxN')
                processName = 'process_cohere1n';
            else
                processName = 'process_cohere1';
            end

            if useScouts
                sFilesConn = bst_process('CallProcess', processName, sFilesInput, [], ...
                    'timewindow',    config.TimeWindow, ...
                    'scouts',        scoutsCellConn, ...
                    'flatten',       double(config.FlattenPCA), ...
                    'scouttime',     scoutTimeStr, ...
                    'scoutfunc',     scoutFuncStr, ...
                    'scoutfuncaft',  scoutFuncStr, ...
                    'pcaedit',       pcaEdit, ...
                    'removeevoked',  0, ...
                    'cohmeasure',    char(config.CohMetric), ...
                    'tfmeasure',     char(config.TFMethod), ...
                    'tfedit',        tfEdit, ...
                    'timeres',       char(config.TimeRes), ...
                    'avgwinlength',  config.AvgWinLength, ...
                    'avgwinoverlap', config.AvgWinOverlap, ...
                    'outputmode',    outputMode, ...
                    'source_abs',    -1);
            else
                sFilesConn = bst_process('CallProcess', processName, sFilesInput, [], ...
                    'timewindow',    config.TimeWindow, ...
                    'flatten',       double(config.FlattenPCA), ...
                    'removeevoked',  0, ...
                    'cohmeasure',    char(config.CohMetric), ...
                    'tfmeasure',     char(config.TFMethod), ...
                    'tfedit',        tfEdit, ...
                    'timeres',       char(config.TimeRes), ...
                    'avgwinlength',  config.AvgWinLength, ...
                    'avgwinoverlap', config.AvgWinOverlap, ...
                    'outputmode',    outputMode, ...
                    'source_abs',    -1);
            end

        % -----------------------------------------------------------------
        case "gc"
        % -----------------------------------------------------------------
            switch config.GCDirection
                case "in",   dirVal = 1;
                case "out",  dirVal = 2;
                case "both", dirVal = 3;
            end

            if strcmp(config.Topology, 'NxN')
                if useScouts
                    sFilesConn = bst_process('CallProcess', 'process_granger1n', sFilesInput, [], ...
                        'timewindow',    config.TimeWindow, ...
                        'scouts',        scoutsCellConn, ...
                        'flatten',       double(config.FlattenPCA), ...
                        'scouttime',     scoutTimeStr, ...
                        'scoutfunc',     scoutFuncStr, ...
                        'removeevoked',  0, ...
                        'grangermethod', char(config.GCMethod), ...
                        'grangerorder',  config.GCOrder, ...
                        'outputmode',    1, ...
                        'source_abs',    -1);
                else
                    sFilesConn = bst_process('CallProcess', 'process_granger1n', sFilesInput, [], ...
                        'timewindow',    config.TimeWindow, ...
                        'flatten',       double(config.FlattenPCA), ...
                        'removeevoked',  0, ...
                        'grangermethod', char(config.GCMethod), ...
                        'grangerorder',  config.GCOrder, ...
                        'outputmode',    1, ...
                        'source_abs',    -1);
                end
            else
                if useScouts
                    sFilesConn = bst_process('CallProcess', 'process_granger1', sFilesInput, [], ...
                        'timewindow',    config.TimeWindow, ...
                        'scouts',        scoutsCellConn, ...
                        'flatten',       double(config.FlattenPCA), ...
                        'scouttime',     scoutTimeStr, ...
                        'scoutfunc',     scoutFuncStr, ...
                        'removeevoked',  0, ...
                        'grangermethod', char(config.GCMethod), ...
                        'direction',     dirVal, ...
                        'grangerorder',  config.GCOrder, ...
                        'outputmode',    1, ...
                        'source_abs',    -1);
                else
                    sFilesConn = bst_process('CallProcess', 'process_granger1', sFilesInput, [], ...
                        'timewindow',    config.TimeWindow, ...
                        'flatten',       double(config.FlattenPCA), ...
                        'removeevoked',  0, ...
                        'grangermethod', char(config.GCMethod), ...
                        'direction',     dirVal, ...
                        'grangerorder',  config.GCOrder, ...
                        'outputmode',    1, ...
                        'source_abs',    -1);
                end
            end

        % -----------------------------------------------------------------
        case "gc_spectral"
        % -----------------------------------------------------------------
            switch config.GCDirection
                case "in",   dirVal = 1;
                case "out",  dirVal = 2;
                case "both", dirVal = 3;
            end

            if strcmp(config.Topology, 'NxN')
                if useScouts
                    sFilesConn = bst_process('CallProcess', 'process_spgranger1n', sFilesInput, [], ...
                        'timewindow',    config.TimeWindow, ...
                        'scouts',        scoutsCellConn, ...
                        'flatten',       double(config.FlattenPCA), ...
                        'scouttime',     scoutTimeStr, ...
                        'scoutfunc',     scoutFuncStr, ...
                        'removeevoked',  0, ...
                        'grangermethod', char(config.GCMethod), ...
                        'grangerorder',  config.GCOrder, ...
                        'maxfreqres',    config.MaxFreqRes, ...
                        'maxfreq',       config.MaxFreq, ...
                        'outputmode',    1, ...
                        'source_abs',    -1);
                else
                    sFilesConn = bst_process('CallProcess', 'process_spgranger1n', sFilesInput, [], ...
                        'timewindow',    config.TimeWindow, ...
                        'flatten',       double(config.FlattenPCA), ...
                        'removeevoked',  0, ...
                        'grangermethod', char(config.GCMethod), ...
                        'grangerorder',  config.GCOrder, ...
                        'maxfreqres',    config.MaxFreqRes, ...
                        'maxfreq',       config.MaxFreq, ...
                        'outputmode',    1, ...
                        'source_abs',    -1);
                end
            else
                if useScouts
                    sFilesConn = bst_process('CallProcess', 'process_spgranger1', sFilesInput, [], ...
                        'timewindow',    config.TimeWindow, ...
                        'scouts',        scoutsCellConn, ...
                        'flatten',       double(config.FlattenPCA), ...
                        'scouttime',     scoutTimeStr, ...
                        'scoutfunc',     scoutFuncStr, ...
                        'removeevoked',  0, ...
                        'grangermethod', char(config.GCMethod), ...
                        'direction',     dirVal, ...
                        'grangerorder',  config.GCOrder, ...
                        'maxfreqres',    config.MaxFreqRes, ...
                        'maxfreq',       config.MaxFreq, ...
                        'outputmode',    1, ...
                        'source_abs',    -1);
                else
                    sFilesConn = bst_process('CallProcess', 'process_spgranger1', sFilesInput, [], ...
                        'timewindow',    config.TimeWindow, ...
                        'flatten',       double(config.FlattenPCA), ...
                        'removeevoked',  0, ...
                        'grangermethod', char(config.GCMethod), ...
                        'direction',     dirVal, ...
                        'grangerorder',  config.GCOrder, ...
                        'maxfreqres',    config.MaxFreqRes, ...
                        'maxfreq',       config.MaxFreq, ...
                        'outputmode',    1, ...
                        'source_abs',    -1);
                end
            end

        % -----------------------------------------------------------------
        case "plv"
        % -----------------------------------------------------------------
            if strcmp(config.Topology, 'NxN')
                processName = 'process_plv1n';
            else
                processName = 'process_plv1';
            end

            if useScouts
                sFilesConn = bst_process('CallProcess', processName, sFilesInput, [], ...
                    'timewindow',    config.TimeWindow, ...
                    'scouts',        scoutsCellConn, ...
                    'flatten',       double(config.FlattenPCA), ...
                    'scouttime',     scoutTimeStr, ...
                    'scoutfunc',     scoutFuncStr, ...
                    'scoutfuncaft',  scoutFuncStr, ...
                    'pcaedit',       pcaEdit, ...
                    'plvmethod',     char(config.PLVMetric), ...
                    'plvmeasure',    2, ...
                    'tfmeasure',     char(config.TFMethod), ...
                    'tfedit',        tfEdit, ...
                    'timeres',       char(config.TimeRes), ...
                    'avgwinlength',  config.AvgWinLength, ...
                    'avgwinoverlap', config.AvgWinOverlap, ...
                    'outputmode',    outputMode);
            else
                sFilesConn = bst_process('CallProcess', processName, sFilesInput, [], ...
                    'timewindow',    config.TimeWindow, ...
                    'flatten',       double(config.FlattenPCA), ...
                    'plvmethod',     char(config.PLVMetric), ...
                    'plvmeasure',    2, ...
                    'tfmeasure',     char(config.TFMethod), ...
                    'tfedit',        tfEdit, ...
                    'timeres',       char(config.TimeRes), ...
                    'avgwinlength',  config.AvgWinLength, ...
                    'avgwinoverlap', config.AvgWinOverlap, ...
                    'outputmode',    outputMode);
            end

        % -----------------------------------------------------------------
        case "envelope"
        % -----------------------------------------------------------------
            if strcmp(config.Topology, 'NxN')
                processName = 'process_henv1n';
            else
                processName = 'process_henv1';
            end

            if useScouts
                sFilesConn = bst_process('CallProcess', processName, sFilesInput, [], ...
                    'timewindow',    config.TimeWindow, ...
                    'scouts',        scoutsCellConn, ...
                    'flatten',       double(config.FlattenPCA), ...
                    'scouttime',     scoutTimeStr, ...
                    'scoutfunc',     scoutFuncStr, ...
                    'scoutfuncaft',  scoutFuncStr, ...
                    'pcaedit',       pcaEdit, ...
                    'removeevoked',  0, ...
                    'cohmeasure',    char(config.EnvMetric), ...
                    'tfmeasure',     char(config.TFMethod), ...
                    'tfedit',        tfEdit, ...
                    'timeres',       char(config.TimeRes), ...
                    'avgwinlength',  config.AvgWinLength, ...
                    'avgwinoverlap', config.AvgWinOverlap, ...
                    'parallel',      0, ...
                    'outputmode',    outputMode, ...
                    'source_abs',    -1);
            else
                sFilesConn = bst_process('CallProcess', processName, sFilesInput, [], ...
                    'timewindow',    config.TimeWindow, ...
                    'flatten',       double(config.FlattenPCA), ...
                    'removeevoked',  0, ...
                    'cohmeasure',    char(config.EnvMetric), ...
                    'tfmeasure',     char(config.TFMethod), ...
                    'tfedit',        tfEdit, ...
                    'timeres',       char(config.TimeRes), ...
                    'avgwinlength',  config.AvgWinLength, ...
                    'avgwinoverlap', config.AvgWinOverlap, ...
                    'parallel',      0, ...
                    'outputmode',    outputMode, ...
                    'source_abs',    -1);
            end

        % -----------------------------------------------------------------
        case "pte"
        % -----------------------------------------------------------------
            if useScouts
                sFilesConn = bst_process('CallProcess', 'process_pte1n', sFilesInput, [], ...
                    'timewindow',    config.TimeWindow, ...
                    'scouts',        scoutsCellConn, ...
                    'flatten',       double(config.FlattenPCA), ...
                    'scouttime',     scoutTimeStr, ...
                    'scoutfunc',     scoutFuncStr, ...
                    'freqbands',     freqBands, ...
                    'normalized',    double(config.PTENormalized), ...
                    'outputmode',    1, ...
                    'source_abs',    -1);
            else
                sFilesConn = bst_process('CallProcess', 'process_pte1n', sFilesInput, [], ...
                    'timewindow',    config.TimeWindow, ...
                    'flatten',       double(config.FlattenPCA), ...
                    'freqbands',     freqBands, ...
                    'normalized',    double(config.PTENormalized), ...
                    'outputmode',    1, ...
                    'source_abs',    -1);
            end
    end

    % Safety check
    if isempty(sFilesConn)
        error("HRB:ConnectivityFailed", ...
            "Connectivity computation failed for subject '%s' metric '%s'.", ...
            subjName, config.Metric);
    end
    log.info(sprintf("Connectivity computed. %d result file(s) created.", length(sFilesConn)));

catch ME
    log.error(sprintf("HRB_bst_connectivity failed: %s", ME.message));
    rethrow(ME);
end

% =========================================================================
%% 9. Build output EEG struct
% =========================================================================
if isSubjName
    EEG = struct();
    EEG.etc.brainstorm = struct();
else
    EEG = InputData;
end

EEG.etc.brainstorm.connectivity_metric       = char(config.Metric);
EEG.etc.brainstorm.connectivity_topology     = char(config.Topology);
EEG.etc.brainstorm.connectivity_files        = {sFilesConn.FileName};
EEG.etc.brainstorm.connectivity_kernel_shared = isKernelShared;
EEG.etc.brainstorm.protocol                  = protocolName;
EEG.etc.brainstorm.subject                   = subjName;
EEG.etc.brainstorm.db_path                   = dbDir;

log.info(sprintf("Output EEG struct ready (subject: %s, metric: %s).", subjName, config.Metric));

% =========================================================================
%% 10. Save
% =========================================================================
if config.Save
    logParams = unpackStruct(logConfig);
    HRB_saveData(EEG, "Name", config.SaveName, "Folder", module, ...
        "OutputFolder", config.OutputFolder, logParams{:});
end

end