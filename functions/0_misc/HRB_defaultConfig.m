% HRB_DEFAULTCONFIG - The default configurations used by all the
% functions.
%
% Usage:
%     >> [config] = HRB_defaultConfig;
%
% Outputs:
%    config = [struct] Nested structure with the default configurations
%
% The current configuration structure is:
% {
%   "general": {},
%   "preprocessing": {
%     "resampleFreq": 250
%     "filterType": 'bandpass'
%     "filterLowCutoff": 0.5
%     "filterHighCutoff": 48
%   },
%   "headModel": {},
%   "sourceEstimation": {},
%   "connectivity": {},
%   "network": {}
% }
%
% Authors: Alessandro Tonin, IRCCS San Camillo Hospital, 2024
% 
% See also: EEGLAB, POP_RESAMPLE


function config = HRB_defaultConfig()

config = struct();

%% GENERAL
general = struct();

% All the configurations
general.customConfig.FileDir = getCodeFolder();
general.customConfig.FileName = "HRB_config.json"; % Name of the custom configuration file to overwrite the values in this file

% Saving
nowstr = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
general.save.OutputFolder = fullfile(getCodeFolder(), "output", nowstr);

% Image
general.image.SaveDotFile = true;
general.image.ImageFormat = ["png","svg"];
general.image.ImageWidth = 0; %auto
general.image.ImageHeight = 0; %auto

% Logging
general.logging.LogEnabled = true;
general.logging.LogLevel = 2;
general.logging.LogToFile = false;
general.logging.LogFileDir = getCodeFolder();
general.logging.LogFileName = "HRB.log";

% Add to the main config struct
config.general = general;
%% PREPROCESSING
preproc = struct();

% All the configurations
preproc.chanedit.Method = "template";
preproc.chanedit.Template = "";
preproc.File = "";

preproc.resample.Frequency = 250;     % [Hz] Sample frequency for resampling
preproc.resample.EEGLAB = {};
preproc.resample.Save = false;        % 
preproc.resample.SaveName = "resample";        % 
preproc.resample.OutputFolder = "";

preproc.filter.Type = "bandpass";     % Type of the filter
preproc.filter.LowCutoff = 0.5;       % [Hz] Low cutoff frequency for the filter
preproc.filter.HighCutoff = 48;       % [Hz] High cutoff frequency for the filter
preproc.filter.EEGLAB = {};
preproc.filter.Save = false;
preproc.filter.SaveName = "filter";
preproc.filter.OutputFolder = "";

preproc.removeChannels.Channels = {};
preproc.removeChannels.EEGLAB = {};
preproc.removeChannels.Save = false;
preproc.removeChannels.SaveName = "removeChannels";
preproc.removeChannels.OutputFolder = "";

preproc.selectChannels.Channels = {};
preproc.selectChannels.EEGLAB = {};
preproc.selectChannels.Save = false;
preproc.selectChannels.SaveName = "selectChannels";
preproc.selectChannels.OutputFolder = "";

preproc.selectTime.AfterStart = 5;
preproc.selectTime.BeforeEnd = 5;
preproc.selectTime.EEGLAB = {};
preproc.selectTime.Save = false;
preproc.selectTime.SaveName = "selectTime";
preproc.selectTime.OutputFolder = "";

preproc.cleanData.Severity = "loose";
preproc.cleanData.SaveExcludedChannels = true;
preproc.cleanData.EEGLAB = {};
preproc.cleanData.Save = false;
preproc.cleanData.SaveName = "cleanData";
preproc.cleanData.OutputFolder = "";

preproc.runica.Extended = 1;
preproc.runica.Interrupt = true;
preproc.runica.EEGLAB = {};
preproc.runica.Seed = 42;
preproc.runica.SaveBefore = true;
preproc.runica.SaveNameBefore = "before_runica";
preproc.runica.Save = true;
preproc.runica.SaveName = "runica";
preproc.runica.OutputFolder = "";

% ICLabel
preproc.iclabel.Version = "default";
preproc.iclabel.Save = true;
preproc.iclabel.SaveName = "iclabel";
preproc.iclabel.OutputFolder = "";

% ICFlag
preproc.icflag.Brain = [NaN NaN];
preproc.icflag.Muscle = [0.9 1];
preproc.icflag.Eye = [0.9 1];
preproc.icflag.Heart = [NaN NaN];
preproc.icflag.LineNoise = [NaN NaN];
preproc.icflag.ChannelNoise = [NaN NaN];
preproc.icflag.Other = [NaN NaN];
preproc.icflag.Save = true;
preproc.icflag.SaveName = "icflag";
preproc.icflag.OutputFolder = "";

% SubComp
preproc.subcomp.Components = [];
preproc.subcomp.Keep = false;
preproc.subcomp.Visualize = false;
preproc.subcomp.Save = true;
preproc.subcomp.SaveName = "subcomp";
preproc.subcomp.OutputFolder = "";

%%
% ICA Macro
preproc.ica.Extended = 1;
preproc.ica.Seed = 42;
preproc.ica.Version = "default";
% Thresholds
preproc.ica.Brain = [0 0];
preproc.ica.Muscle = [0 0];
preproc.ica.Eye = [0 0];
preproc.ica.Heart = [0 0];
preproc.ica.LineNoise = [0 0];
preproc.ica.ChannelNoise = [0 0];
preproc.ica.Other = [0 0];
% Intermediate Save
preproc.ica.SaveWeights = true;             
preproc.ica.SaveWeightsName = "ICA_weights";
% Visualization & Final Save
preproc.ica.Visualize = false;
preproc.ica.Save = true;
preproc.ica.SaveName = "";
preproc.ica.OutputFolder = "";

% Epoching
preproc.epoch.Mode = "Event";
preproc.epoch.Events = [];
preproc.epoch.Recurrence = 1;
preproc.epoch.Limits = [-1 2];
preproc.epoch.Baseline = [];
preproc.epoch.Save = true;
preproc.epoch.SaveName = "epoched";
preproc.epoch.OutputFolder = "";

% Epoch Rejection
preproc.rejepochs.Threshold = 100;
preproc.rejepochs.Channels = [];
preproc.rejepochs.TimeLimits = [];
preproc.rejepochs.ConfirmRej = false;
preproc.rejepochs.Save = true;
preproc.rejepochs.SaveName = "epoch_rej";
preproc.rejepochs.OutputFolder = "";

% Logging
preproc.logging.LogEnabled = true;
preproc.logging.LogLevel = 2;
preproc.logging.LogToFile = false;
preproc.logging.LogFileDir = getCodeFolder();
preproc.logging.LogFileName = "HRB_preprocessing.log";

% Add to the main config struct
config.preprocessing = preproc;
%% HEAD MODEL
headmodel = struct();

% All the configurations

% bst_import
headmodel.bst_import.DataType        = "rs";   % "rs" | "task"
headmodel.bst_import.WindowLength    = 4;      % [s] RS only: fixed segment length
headmodel.bst_import.ProtocolName    = "HRB_Protocol";
headmodel.bst_import.SubjectName     = "";    
headmodel.bst_import.UseDefaultAnat  = true;
headmodel.bst_import.MRIFile = "";
headmodel.bst_import.FreeSurferDir = "";
headmodel.bst_import.BrainstormDbDir = "";
headmodel.bst.import.CondtionName = "";
headmodel.bst_import.OutputFolder    = "";    
headmodel.bst_import.Save            = false; 
headmodel.bst_import.SaveName        = ""; 

% bst_headmodel
headmodel.bst_headmodel.Method              = "OpenMEEG";
headmodel.bst_headmodel.SourceSpace         = "cortex";
headmodel.bst_headmodel.ChanLocs            = "";
headmodel.bst_headmodel.ChanLocsTemplate    = "";
headmodel.bst_headmodel.SelectTemplate      = false;
headmodel.bst_headmodel.ProtocolName        = "HRB_Protocol";
headmodel.bst_headmodel.BrainstormDbDir     = "";
headmodel.bst_headmodel.BemConductivities   = [1, 0.0125, 1];
headmodel.bst_headmodel.DUNeuroFemType      = "fitted";
headmodel.bst_headmodel.DUNeuroSolverType   = "cg";
headmodel.bst_headmodel.DUNeuroSrcModel     = "venant";
headmodel.bst_headmodel.DUNeuroIsotropic    = true;
headmodel.bst_headmodel.Save                = false;
headmodel.bst_headmodel.SaveName            = "";
headmodel.bst_headmodel.OutputFolder        = "";
% Save
headmodel.bst_headmodel.Save                 = false;
headmodel.bst_headmodel.SaveName             = "";
headmodel.bst_headmodel.OutputFolder         = "";

% bst_noisecov
headmodel.bst_noisecov.NoiseCovBaseline    = [];       % [] = full window | [t1,t2] seconds
headmodel.bst_noisecov.NoiseCovSensorTypes = "EEG";
headmodel.bst_noisecov.Target              = "noise";  % "noise" (all methods) | "data" (LCMV only)
headmodel.bst_noisecov.ProtocolName        = "HRB_Protocol";
headmodel.bst_noisecov.BrainstormDbDir     = "";
headmodel.bst_noisecov.Save                = false;
headmodel.bst_noisecov.SaveName            = "";
headmodel.bst_noisecov.OutputFolder        = "";

% Logging
headmodel.logging.LogEnabled = true;
headmodel.logging.LogLevel = 2;
headmodel.logging.LogToFile = false;
headmodel.logging.LogFileDir = getCodeFolder();
headmodel.logging.LogFileName = "HRB_headmodel.log";

% Add to the main config struct
config.headmodel = headmodel;


%% SOURCE ESTIMATION
source = struct();

% bst_inverse
source.bst_inverse.Method           = "mne";         % "mne" | "lcmv" | "dipole"
source.bst_inverse.ProcessOption    = "kernel_shared"; % "kernel_shared" | "kernel_perfile" | "full"
source.bst_inverse.DipolOrientation = "constrained";  % "constrained" | "loose" | "unconstrained"
source.bst_inverse.SourceSpace      = "cortex";       % "cortex" | "volume"
source.bst_inverse.ProtocolName     = "HRB_Protocol";
source.bst_inverse.BrainstormDbDir  = "";

% MNE specific
source.bst_inverse.MNEMeasure        = "dspm";   % "current" | "dspm" | "sloreta"
source.bst_inverse.MNEDepthWeighting = true;
source.bst_inverse.MNEDepthOrder     = 0.5;
source.bst_inverse.MNEDepthMax       = 10;
source.bst_inverse.MNENoiseCovReg    = "auto";   % "regularize"|"median"|"diagonal"|"none"|"auto"
source.bst_inverse.MNESnr            = 3;

% LCMV specific
source.bst_inverse.LCMVDataCovReg   = "auto";   % "regularize"|"median"|"diagonal"|"none"|"auto"
source.bst.inverse.DataCovBaseline = [];
source.bst_inverse.DataCovSensorTypes = "EEG";

% Dipole specific
source.bst_inverse.DipoleNoiseCovReg = "auto";  % "regularize"|"median"|"diagonal"|"none"|"auto"

% Save
source.bst_inverse.Save         = false;
source.bst_inverse.SaveName     = "";
source.bst_inverse.OutputFolder = "";

% Logging
source.logging.LogEnabled  = true;
source.logging.LogLevel    = 2;
source.logging.LogToFile   = false;
source.logging.LogFileDir  = getCodeFolder();
source.logging.LogFileName = "HRB_sourceEstimation.log";

% Add to the main config struct
config.sourceEstimation = source;


%% CONNECTIVITY
connectivity = struct();

% Common params (omni + all subs)
connectivity.bst_connectivity.Topology      = "NxN";      % "NxN"|"1xN"
connectivity.bst_connectivity.TimeWindow    = [];
connectivity.bst_connectivity.SelectScouts  = true;
connectivity.bst_connectivity.Atlas         = "";
connectivity.bst_connectivity.Scouts        = "";
connectivity.bst_connectivity.FlattenPCA    = false;
connectivity.bst_connectivity.ScoutFunction = "mean";     % "mean"|"max"|"std"|"pca"
connectivity.bst_connectivity.ScoutTime     = "after";    % "before"|"after"
connectivity.bst_connectivity.FreqBands     = {};         % {} = default 5-band (delta/theta/alpha/beta/gamma)
connectivity.bst_connectivity.SaveMode      = "separately"; % "separately"|"average"|"concatenate"
connectivity.bst_connectivity.AvgWinLength  = 1;
connectivity.bst_connectivity.AvgWinOverlap = 50;
connectivity.bst_connectivity.ProtocolName  = "HRB_Protocol";
connectivity.bst_connectivity.BrainstormDbDir = "";
 
% Omni-only param (ignored by sub-functions which fix the metric in their name)
connectivity.bst_connectivity.Metric = "coh"; % "corr"|"coh"|"gc"|"gc_spectral"|"plv"|"envelope"|"pte"
 
% Coherence params (omni + HRB_bst_connectivity_coh)
connectivity.bst_connectivity.CohMetric = "mscohere"; % "mscohere"|"icoh"|"lcohere2019"
connectivity.bst_connectivity.TFMethod  = "hilbert";  % "hilbert"|"morlet"|"stft"
connectivity.bst_connectivity.TimeRes   = "full";     % "full"|"windowed"|"none"
 
% Correlation params (omni + HRB_bst_connectivity_corr)
connectivity.bst_connectivity.ScalarProduct = false;
 
% Granger causality params (omni + HRB_bst_connectivity_gc)
connectivity.bst_connectivity.GCMethod    = "bst";   % "bst"|"mvgc"
connectivity.bst_connectivity.GCDirection = "both";  % "both"|"in"|"out"  [1xN only]
connectivity.bst_connectivity.GCOrder     = 10;
 
% Spectral GC params (omni + HRB_bst_connectivity_gc_spectral)
connectivity.bst_connectivity.MaxFreqRes = 2;        % [Hz]
connectivity.bst_connectivity.MaxFreq    = 100;      % [Hz]
 
% Phase params (omni + HRB_bst_connectivity_phase)
connectivity.bst_connectivity.PLVMetric = "wpli";    % "wpli"|"plv"|"ciplv"
                                                     % wpli: VC-robust (recommended default)
                                                     % plv: sensitive to volume conduction
                                                     % ciplv: also VC-robust
 
% Envelope params (omni + HRB_bst_connectivity_envelope)
connectivity.bst_connectivity.EnvMetric = "penv";   % "penv"|"oenv"
                                                     % oenv: orthogonalized (Hipp 2012), VC-robust
 
% PTE params (omni + HRB_bst_connectivity_pte)
connectivity.bst_connectivity.PTENormalized = true;  % NxN only in Brainstorm
 
% Save
connectivity.bst_connectivity.Save         = false;
connectivity.bst_connectivity.SaveName     = "";
connectivity.bst_connectivity.OutputFolder = "";
 
% Logging
connectivity.logging.LogEnabled  = true;
connectivity.logging.LogLevel    = 2;
connectivity.logging.LogToFile   = false;
connectivity.logging.LogFileDir  = fullfile(pwd, "HRB_logs"); % *** FIX Q1 ***
connectivity.logging.LogFileName = "HRB_connectivity.log";
 
config.connectivity = connectivity;

%% NETWORK ANALYSIS
network = struct();

% All the configurations

% Logging
network.logging.LogEnabled = true;
network.logging.LogLevel = 2;
network.logging.LogToFile = false;
network.logging.LogFileDir = getCodeFolder();
network.logging.LogFileName = "HRB_network.log";

% Add to the main config struct
config.network = network;

end

function mainFolder = getCodeFolder()
% retrieve the folder where lies the code
functionFolder = mfilename("fullpath");
% mainFolderParent = extractBefore(functionFolder, "Herbert");
% mainFolder = fullfile(mainFolderParent, "Herbert");
mainFolder = fileparts(fileparts(fileparts(functionFolder)));
end
