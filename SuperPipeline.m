%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Super Pipeline Multiverse Analysis %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
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
SPMA_loadDependencies();

%% Variables
data_path = '/mnt/raid/Ettore/SuperPipelineMultiverseAnalysis/data/ses-20191120/EEG_ORIG/PATHS_101_Resting_20191120_022103.mff';
pipeline = "pipeline_example.json";
% pipeline = "pipeline_test.json";

%% Import
EEG = pop_mffimport({data_path},'',0,0);
data_test = '';

%% Run pipeline
data = SPMA_runPipeline(EEG, pipeline) %, "pipeline_example.json");
% data = SPMA_runPipeline(pipeline, data_test);


%% Create pipeline
step1 = @(eeg) SPMA_resample(eeg,Frequency=250, Save=true);
step2 = {
    @(eeg) SPMA_filter(eeg, SaveName="bandpass", Save=true, Type="bandpass", LowCutoff=0.5,HighCutoff=48),
    @(eeg) SPMA_filter(eeg, SaveName="lowpass", Type="lowpass",HighCutoff=48)
    };
step3 = @(eeg) SPMA_removeChannels(eeg,"Channels",["E67","E73","E82","E91","E92","E102","E111","E120","E133","E145","E165","E174","E187","E199","E208","E209","E216","E217","E218","E219","E225","E226","E227","E228","E229","E230","E231","E232","E233","E234","E235","E236","E237","E238","E239","E240","E241","E242","E243","E244","E245","E246","E247","E248","E249","E250","E251","E252","E253","E254","E255","E256"]);
step4 = @(eeg) SPMA_selectTime(eeg, "AfterStart",5,BeforeEnd=5);
step5 = @(eeg) SPMA_runica(eeg, "Interrupt",1,"Extended",EEG);

pipeline = {step1, step2, step3, step4, step5};



























