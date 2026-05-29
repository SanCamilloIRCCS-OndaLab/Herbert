%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Herbert: an EEG Reproducible Brain Exploration Research Toolbox %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% This is the main script for the multiverse analysis of EEG resting state.
% The script can be used as-is or can be used as template/example for
% developing personalized scripts.
% The pipeline is developed for internal use of IRCCS San Camillo Hospital,
% but the project is open to contributions.
%
% Organization: IRCCS San Camillo Hospital (Venice, Italy)
% 
% Authors:  Giorgio Arcara
%           Sara Lago
%           Ettore Napoli
%           Silvia Saccani
%           Alessandro Tonin
%
% License: GPLv3
%
% Last update: 29.05.2024

%% Add internal functions to path
%%% Uncomment this if you run the whole file
% folder = fileparts(which(mfilename));

% functions_folder = fullfile(folder, "functions");
%%% uncomment this if you run the code line by line
functions_folder = "functions";

addpath(genpath(functions_folder));

%% Add external dependencies to path
HRB_loadDependencies();


%% Variables
data_path = '/mnt/raid/Ettore/SuperPipelineMultiverseAnalysis/data/';
file_name = 'MMCI_01_RESTING.vhdr'
pipeline = "pipeline_example.json";
% pipeline = "pipeline_test.json";

%% Import
EEG = pop_loadbv(data_path, file_name);
% data_test = '';

%% PROVA BST ONLY
pipeline = "pipeline_bst_only.json"
EEG_bp = pop_loadset('filename', 'bandpass-1-48_clean-epochs.set', 'filepath', '/mnt/raid/Ettore/SuperPipelineMultiverseAnalysis/output/20260528_103602/preprocessing')
EEG_lp = pop_loadset('filename', 'lowpass-48_clean-epochs.set', 'filepath', '/mnt/raid/Ettore/SuperPipelineMultiverseAnalysis/output/20260528_103602/preprocessing')

data_bandpass = HRB_runPipeline(EEG_bp, pipeline)
data_lowpass = HRB_runPipeline(EEG_lp, pipeline)

%% Run pipeline
data = HRB_runPipeline(EEG, pipeline) %, "pipeline_example.json");
% data = HRB_runPipeline(pipeline, data_test);

%% Run old pipeline (not in parallel)
EEG = pop_loadbv(data_path, file_name);
data = HRB_runPipelineOld(EEG, pipeline) % Not parallel pipeline!


%% Create pipeline
step1 = @(eeg) HRB_resample(eeg,Frequency=250, Save=true);
step2 = {
    @(eeg) HRB_filter(eeg, SaveName="bandpass", Save=true, Type="bandpass", LowCutoff=0.5,HighCutoff=48),
    @(eeg) HRB_filter(eeg, SaveName="lowpass", Type="lowpass",HighCutoff=48)
    };
step3 = @(eeg) HRB_removeChannels(eeg,"Channels",["E67","E73","E82","E91","E92","E102","E111","E120","E133","E145","E165","E174","E187","E199","E208","E209","E216","E217","E218","E219","E225","E226","E227","E228","E229","E230","E231","E232","E233","E234","E235","E236","E237","E238","E239","E240","E241","E242","E243","E244","E245","E246","E247","E248","E249","E250","E251","E252","E253","E254","E255","E256"]);
step4 = @(eeg) HRB_selectTime(eeg, "AfterStart",5,BeforeEnd=5);
step5 = @(eeg) HRB_runica(eeg, "Interrupt",1,"Extended",EEG);

pipeline = {step1, step2, step3, step4, step5};



























