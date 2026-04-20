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
preproc.rejepochs.ConfirmRej = false
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
headmodel.bst_import.BrainstormDbDir = "";
headmodel.bst_import.OutputFolder    = "";    
headmodel.bst_import.Save            = false; 
headmodel.bst_import.SaveName        = ""; 

% bst_headmodel
headmodel.bst_headmodel.Method              = "OpenMEEG";
headmodel.bst_headmodel.SourceSpace         = "cortex";
headmodel.bst_headmodel.ChanLocs            = "";
headmodel.bst_headmodel.ChanLocsTemplate    = "";
headmodel.bst_headmodel.SelectTemplate      = false;
headmodel.bst_headmodel.NoiseCovBaseline    = [];
headmodel.bst_headmodel.NoiseCovSensorTypes = "EEG";
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

% All the configurations

% Logging
source.logging.LogEnabled = true;
source.logging.LogLevel = 2;
source.logging.LogToFile = false;
source.logging.LogFileDir = getCodeFolder();
source.logging.LogFileName = "HRB_sourceEstimation.log";

% Add to the main config struct
config.sourceEstimation = source;
%% CONNECTIVITY
connectivity = struct();

% All the configurations

% Logging
connectivity.logging.LogEnabled = true;
connectivity.logging.LogLevel = 2;
connectivity.logging.LogToFile = false;
connectivity.logging.LogFileDir = getCodeFolder();
connectivity.logging.LogFileName = "HRB_connectivity.log";

% Add to the main config struct
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
