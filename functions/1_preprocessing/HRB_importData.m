% HRB_IMPORTDATA - EEG data import.
%
% Usage:
%     >> [EEG] = HRB_importData(eeg_file)
%     >> [EEG] = HRB_importData(eeg_file, 'key', val) 
%     >> [EEG] = HRB_importData(eeg_file, key=val) 
%
% Inputs:
%    eeg_file = [string] original EEG raw data file path
%     
% Outputs:
%    EEG = [struct] EEG struct using EEGLAB structure system
%
% Authors: Sara Lago, IRCCS San Camillo Hospital, 2024
% 
% See also: EEGLAB, POP_FILEIO, POP_MFFIMPORT, POP_MUSEDIRECT, POP_IMPORTDATA

function [EEG] = HRB_importData(eeg_file, opt)
    arguments (Input)
        eeg_file string
        % Optional
        opt.EEGLAB (1,:) cell
        % Save options
        opt.Save logical
        opt.SaveName string
        opt.OutputFolder string
        % Log options
        opt.LogEnabled logical
        opt.LogLevel double {mustBeInteger,mustBeInRange(opt.LogLevel,0,6)}
        opt.LogToFile logical
        opt.LogFileDir string
        opt.LogFileName string
    end

    %% Constants
    module = "preprocessing";
    
    %% Parsing arguments
    config = HRB_loadConfig(module, "import", opt);

    %% Logger
    logConfig = HRB_loadConfig(module, "logging", opt);
    log = HRB_loggerSetUp(module, logConfig);

    %% Importing data
    log.info(sprintf("Importing file %s", eeg_file))

    if contains(eeg_file, '.mff')
        EEG = pop_mffimport({eeg_file}); % from MFFMatlabIO5.0
    elseif contains(eeg_file, '.csv')
        EEG = pop_musedirect(eeg_file);
    elseif contains(eeg_file, '.mat')
        % case Brainstorm data
        mydata = load('-mat', eeg_file);
        if isfield(mydata, 'F') % case Brainstorm data 
        % extract data
        sampling_rate = mydata.F.header.EEG.srate;
        myeeg = mydata.F.header.EEG.data; 
        % import
        EEG = pop_importdata('dataformat','array','nbchan',0,'data',myeeg,'srate', ...
            sampling_rate,'pnts',0,'xmin',0);
        % case Net data
        elseif isfield(mydata, 'D') % case net .mat data
            % load spm
            % addpath('dependencies/spm12')
            D=spm_eeg_load(eeg_file);
            EEG = pop_fileio([path(D) filesep fname(D)]);
        end
    else % .trc; .edf, .set, .eeg, .vhdr NOTE: EDF and BDF files can be imported with both biosig and fileio
        EEG = pop_fileio(eeg_file);
    end

    %% Save
    if config.Save
        logParams = unpackStruct(logConfig);
        HRB_saveData(EEG, "Name", config.SaveName, "Folder", module, "OutputFolder", config.OutputFolder, logParams{:});
    end

end
