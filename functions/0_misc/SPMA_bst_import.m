function [EEG] = SPMA_bst_import(EEG, opt)
% SPMA_bst_import initializes Brainstorm and creating a Protocol and importing
% the EEGLAB dataset.
% This function acts as a bridge between EEGLAB and Brainstorm.
% It ensures Brainstorm is running, sets the database directory to a 
% persistent location (to allow group analysis later), creates/selects 
% the protocol, and imports the current EEG data.
%
% Usage:
%   >>> EEG = SPMA_bst_import(EEG, 'ProtocolName', 'MyStudy'
% 
% Parameters:
%   EEG (struct): EEGLAB-derived dataset
%
% Other Parameters:
%   ProtocolName (string): Name of Brainstorm protocol to create or use
%   SubjectName (string): Name of the subject. If empty, uses EEG.subject or EEG.setname
%   UseDefaultAnat (logical): Use ICBM152 template anatomy. Default is true
%   BrainstormDbDir (string): Path to the persistent Brainstorm Database.
%                             If empty (""), it defaults to creating a 
%                             'brainstorm_db' folder in the project root.
%
%   OutputFolder (string): Folder where the updated .set file will be saved.
%
% Authors: Ettore Napoli, University of Bologna, 2026

    arguments(Input)
        EEG struct
        % Optional Parameters
        opt.ProtocolName string = "SPMA_Protocol"
        opt.SubjectName string = ""
        opt.UseDefaultAnat logical = true
        opt.BrainstormDbDir = ""
        % Pipeline Output Options (The .set file)
        opt.Save logical
        opt.SaveName string
        opt.OutputFolder string
        % Log Options
        opt.LogEnabled logical
        opt.LogLevel double {mustBeInteger, mustBeInRange(opt.LogLevel, 0,6)}
        opt.LogToFile logical
        opt.LogFileDir string
        opt.LogFileName string
    end

    %% Constants
    module = "head_model";
    
    %% Parsing Arguments
    config = SPMA_loadConfig(module, "bst_import", opt);

    %% Logger
    logConfig = SPMA_loadConfig(module, "logging", opt);
    log = SPMA_loggerSetUp(module, logConfig);

    %% 1. Handle output folder for the .set results
    if config.OutputFolder == ""
        timestamp = string(datetime("now", "Format","yyyyMMdd_HHmmss"));
        config.OutputFolder = fullfile("output", timestamp);
    end
    
    % Create folder
    if ~exist(config.OutputFolder, 'dir')
        mkdir(config.OutputFolder); 
    end

    %% Set Brainstorm database location
    if config.BrainstormDbDir ~= ""
        dbDir = config.BrainstormDbDir;
    else
        dbDir = fullfile(pwd, 'brainstorm_db');
    end
    
    % Create folder
    if ~exist(dbDir, 'dir')
        mkdir(dbDir);
        log.info(sprintf("Using persistent Brainstorm DB folder: %s", dbDir));
    end

    %% 3. Start Brainstorm
    if ~exist('brainstorm', 'file')
        error("SPMA:BrainstormNotFound", "Brainstorm is not in MATLAB path. Check external folder.");
    end
    
    if ~brainstorm('status')
        log.info("Starting Brainstorm (nogui)...");
        brainstorm nogui;
    end

    % Set Database
    currentDbDir = bst_get('BrainstormDbDir');

    % Update Brainstorm DB location only if it differs from the current one (avoids redundant reloading)
    if ~strcmpi(strip(currentDbDir, 'right', filesep), strip(char(dbDir), 'right', filesep))
        log.info(sprintf("Switching Brainstorm DB from '%s' to '%s'...", currentDbDir, dbDir));
        bst_set('BrainstormDbDir', char(dbDir));
        
        gui_brainstorm('UpdateProtocolsList');
    else
        log.info("Brainstorm DB path is already correct.");
    end

    %% 4. Manage Protocol
    iProtocol = bst_get('Protocol', char(config.ProtocolName));
    
    if isempty(iPrtocol)
        log.info(sprintf("Creating new Protocol: %s", config.ProtocolName));
        gui_brainstorm('CreateProtocol', char(config.ProtocolName), double(config.UseDefaultAnat, 0));
    else
        log.info(sprintf("Using existing protocol: %s", config.ProtocolName));
        gui_brainstorm('SetCurrentProtocol', iProtocol);
    end

    %% 5. Prepare Subject Name
    if config.SubjectName == ""
        if isfield(EEG, 'subject') && ~isempty(EEG.subject)
            subjName = EEG.subject;
        else
            % Remove spaces from setname
            subjName = regexprep(EEG.setname, '\s+', '_');
        end
    else
        subjName = config.SubjectName;
    end
    subjName = char(subjName);

    %% Import Data
    









