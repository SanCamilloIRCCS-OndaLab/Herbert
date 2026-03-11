function [EEG] = HRB_bst_import(InputData, opt)
% HRB_bst_import initializes Brainstorm, creates/selects a Protocol and
% imports an EEGLAB dataset (from RAM or disk).
% This function acts as a bridge between EEGLAB and Brainstorm.
% It supports both continuous and epoched datasets, and both Resting State
% and Task-based paradigms.
%
% Usage:
%   >>> EEG = HRB_bst_import(EEG, 'DataType', 'task');
%   >>> EEG = HRB_bst_import(EEG, 'DataType', 'rs', 'WindowLength', 4);
%   >>> EEG = HRB_bst_import("output/Sub01.set", 'DataType', 'task');
%
% Parameters:
%   InputData: EEGLAB struct (RAM) or string/char path to a .set file.
%
% Other Parameters:
%   DataType (string): Paradigm type. Either "task" or "rs". Default: "rs"
%       - "task" : Event-locked paradigm. Epochs are defined by triggers.
%       - "rs"   : Resting State. No triggers. If continuous, Brainstorm
%                  will segment into fixed-length windows.
%
%   WindowLength (double): [RS + continuous only] Length of fixed segments
%                          in seconds. Default: 4 (seconds).
%
%   ProtocolName (string): Name of Brainstorm protocol to create or reuse.
%                          Default: "HRB_Protocol"
%
%   SubjectName (string): Subject name in Brainstorm. If empty, inferred
%                         from EEG.subject, EEG.setname, or filename.
%
%   UseDefaultAnat (logical): Use ICBM152 template anatomy. Default: true.
%
%   BrainstormDbDir (string): Path to the persistent Brainstorm database.
%                             Default: '<pwd>/brainstorm_db'.
%
%   OutputFolder (string): Folder for temporary files and .set output.
%
% Authors: Ettore Napoli, University of Bologna, 2026

    arguments(Input)
        InputData  % struct (RAM) or string/char (filepath)
        % Paradigm
        opt.DataType string {mustBeMember(opt.DataType, ["task", "rs"])} = "rs"
        opt.WindowLength double = 4  % seconds, RS + continuous only
        % Brainstorm
        opt.ProtocolName string = "HRB_Protocol"
        opt.SubjectName string = ""
        opt.UseDefaultAnat logical = true
        opt.MRIFile
        opt.BrainstormDbDir string = ""
        % Pipeline Output Options
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
    module = "headmodel";

    %% Parsing Arguments
    config = HRB_loadConfig(module, "bst_import", opt);

    %% Logger
    logConfig = HRB_loadConfig(module, "logging", opt);
    log = HRB_loggerSetUp(module, logConfig);

    % =========================================================================
    %% 1. Input type detection
    % =========================================================================
    isFilePath = isstring(InputData) || ischar(InputData);

    if isFilePath
        filePath = char(InputData);
        if ~exist(filePath, 'file')
            error("HRB:FileNotFound", "File not found: %s", filePath);
        end
        log.info(sprintf("Input mode: file on disk (%s)", filePath));
    else
        if ~isstruct(InputData)
            error("HRB:BadInput", "InputData must be an EEG struct or a file path string.");
        end
        log.info("Input mode: RAM EEG struct");
    end

    % =========================================================================
    %% 2. Detect continuous vs epoched
    % =========================================================================
    if isFilePath
        log.info("Loading dataset header to detect type...");
        EEG_info = pop_loadset('filename', filePath, 'loadmode', 'info');
        isEpoched = EEG_info.trials > 1;
        pnts  = EEG_info.pnts;
        srate = EEG_info.srate;
    else
        isEpoched = InputData.trials > 1;
        pnts  = InputData.pnts;
        srate = InputData.srate;
    end

    % Epoch duration in seconds — used for RS epoched segmentation (Case 2)
    epochDuration = pnts / srate;

    dataTypeStr = config.DataType;
    epochStr    = "continuous";
    if isEpoched, epochStr = "epoched"; end
    log.info(sprintf("Dataset type detected: %s | Paradigm: %s", epochStr, dataTypeStr));

    % =========================================================================
    %% 3. Output folder
    % =========================================================================
    if config.OutputFolder == ""
        timestamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
        config.OutputFolder = fullfile("output", timestamp);
    end
    if ~exist(config.OutputFolder, 'dir')
        mkdir(config.OutputFolder);
    end

    % =========================================================================
    %% 4. Brainstorm database location
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
    %% 5. Start Brainstorm
    % =========================================================================
    if ~brainstorm('status')
        log.info("Starting Brainstorm (nogui)...");
        brainstorm nogui;
        timeout = 60;
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

    % Update DB path only if different
    currentDbDir = bst_get('BrainstormDbDir');
    if ~strcmpi(strip(currentDbDir, 'right', filesep), strip(dbDir, 'right', filesep))
        log.info(sprintf("Switching BST DB: '%s' to '%s'", currentDbDir, dbDir));
        bst_set('BrainstormDbDir', dbDir);
        gui_brainstorm('UpdateProtocolsList');
    else
        log.info("Brainstorm DB path is already correct.");
    end

    % =========================================================================
    %% 6. Manage Protocol
    % =========================================================================
    iProtocol = bst_get('Protocol', char(config.ProtocolName));
    if isempty(iProtocol)
        log.info(sprintf("Creating new protocol: %s", config.ProtocolName));
        gui_brainstorm('CreateProtocol', char(config.ProtocolName), double(config.UseDefaultAnat), 0);
    else
        log.info(sprintf("Using existing protocol: %s", config.ProtocolName));
        gui_brainstorm('SetCurrentProtocol', iProtocol);
    end

    % =========================================================================
    %% 7. Subject name
    % =========================================================================
    if config.SubjectName == ""
        if isFilePath
            [~, fname, ~] = fileparts(filePath);
            subjName = fname;
        else
            if isfield(InputData, 'subject') && ~isempty(InputData.subject)
                subjName = InputData.subject;
            else
                subjName = regexprep(InputData.setname, '\s+', '_');
            end
        end
    else
        subjName = char(config.SubjectName);
    end
    log.info(sprintf("Subject name: %s", subjName));

    % =========================================================================
    %% 8. Prepare input files (save to temp if struct in RAM)
    % =========================================================================
    tempFolder = "";

    if isFilePath
        InputFiles = {filePath};
    else
        tempFolder = fullfile(config.OutputFolder, 'temp_bst_import');
        if ~exist(tempFolder, 'dir')
            mkdir(tempFolder);
        end
        tempFile = fullfile(tempFolder, 'temp_import.set');
        log.info(sprintf("Saving temp .set file to: %s", tempFolder));
        InputData.filename = 'temp_import.set';
        InputData.filepath = char(tempFolder);
        pop_saveset(InputData, 'filename', 'temp_import.set', 'filepath', char(tempFolder), 'savemode', 'onefile');
        InputFiles = {tempFile};
    end

    % =========================================================================
    %% 9. Brainstorm import — 4-way branch
    %
    %   Case 1: RS   + continuous → raw link + fixed-length segmentation
    %                               (uses config.WindowLength)
    %   Case 2: RS   + epoched    → raw link + segmentation matching epoch duration
    %                               (uses epochDuration = pnts/srate)
    %   Case 3: Task + continuous → raw link + epoch from triggers
    %   Case 4: Task + epoched    → direct import of event-locked epochs
    % =========================================================================
    try
        if strcmp(dataTypeStr, 'rs') && ~isEpoched
            % -----------------------------------------------------------------
            %  Case 1: RS Continuous
            %  Strategy: raw link + fixed-length segmentation (WindowLength)
            % -----------------------------------------------------------------
            log.info(sprintf("Case 1 — RS continuous: raw link + %.1f s segmentation", config.WindowLength));

            sFilesRaw = bst_process('CallProcess', 'process_import_data_raw', [], [], ...
                'subjectname',    subjName, ...
                'datafile',       {InputFiles{1}, 'EEG-EEGLAB'}, ...
                'channelreplace', 1, ...
                'channelalign',   1, ...
                'evtmode',        'value');

            if isempty(sFilesRaw)
                error("HRB:ImportFailed", "Failed to create raw link in Brainstorm.");
            end

            sFilesEpoch = bst_process('CallProcess', 'process_import_data_time', sFilesRaw, [], ...
                'subjectname',   subjName, ...
                'condition',     '', ...
                'timewindow',    [], ...
                'split',         config.WindowLength, ...
                'ignoreshort',   1, ...
                'usectfcomp',    1, ...
                'usessp',        1, ...
                'freq',          [], ...
                'baseline',      [], ...
                'blsensortypes', 'MEG, EEG');

        elseif strcmp(dataTypeStr, 'rs') && isEpoched
            % -----------------------------------------------------------------
            %  Case 2: RS epoched - Import each separate epoch
            % -----------------------------------------------------------------
            log.info(sprintf("Case 2 — RS epoched: %.1f s segmentation (epoch duration)", epochDuration));
           
            sFilesEpoch = bst_process('CallProcess', 'process_import_data_epoch', [], [], ...
                'subjectname',   subjName, ...
                'datafile',     {InputFiles{1}, 'EEG-EEGLAB'}, ...
                'condition', 'RS', ...
                'iepochs',       [],  ...
                'eventtypes',   '', ...
                'createcond',    1, ...
                'usectfcomp',    1, ...
                'usessp',        1, ...
                'freq',          [], ...
                'baseline',      [], ...
                'blsensortypes', 'MEG, EEG');

        elseif strcmp(dataTypeStr, 'task') && ~isEpoched
            % -----------------------------------------------------------------
            %  Case 3: Task Continuous
            %  Strategy: raw link + epoch from trigger events
            % -----------------------------------------------------------------
            log.info("Case 3 — Task continuous: raw link + epoch from triggers");

            sFilesRaw = bst_process('CallProcess', 'process_import_data_raw', [], [], ...
                'subjectname',    subjName, ...
                'datafile',       {InputFiles{1}, 'EEG-EEGLAB'}, ...
                'channelreplace', 1, ...
                'channelalign',   1, ...
                'evtmode',        'value');

            if isempty(sFilesRaw)
                error("HRB:ImportFailed", "Failed to create raw link in Brainstorm.");
            end

            sFilesEpoch = bst_process('CallProcess', 'process_import_data_epoch', sFilesRaw, [], ...
                'subjectname',   subjName, ...
                'condition',     '', ...
                'iepochs',       [], ...
                'eventtypes',    '', ...
                'createcond',    0, ...
                'usectfcomp',    1, ...
                'usessp',        1, ...
                'freq',          [], ...
                'baseline',      [], ...
                'blsensortypes', 'MEG, EEG');

        else
            % -----------------------------------------------------------------
            %  Case 4: Task Epoched (epochs already defined in EEGLAB)
            %  Strategy: direct import of event-locked epochs
            % -----------------------------------------------------------------
            log.info("Case 4 — Task epoched: direct import of event-locked epochs");

            sFilesEpoch = bst_process('CallProcess', 'process_import_data_event', [], [], ...
                'subjectname',    subjName, ...
                'datafile',       {InputFiles{1}, 'EEG-EEGLAB'}, ...
                'eventtypes',     '', ...
                'createcond',     1, ...
                'channelreplace', 1, ...
                'channelalign',   1);
        end

        % =====================================================================
        %% 10. Safety check
        % =====================================================================
        if isempty(sFilesEpoch)
            if strcmp(dataTypeStr, 'task') && ~isEpoched
                hint = " Ensure that trigger events exist in the continuous file.";
            elseif strcmp(dataTypeStr, 'rs') && ~isEpoched
                hint = " Check that the file is readable and WindowLength is valid.";
            else
                hint = "";
            end
            error("HRB:ImportFailed", "Brainstorm import returned no output files.%s", hint);
        end

        % =====================================================================
        %% 11. Cleanup temp folder
        % =====================================================================
        if strlength(tempFolder) > 0 && exist(tempFolder, 'dir')
            rmdir(tempFolder, 's');
            log.info("Temp folder removed.");
        end

        % =====================================================================
        %% 12. Build output EEG struct
        % =====================================================================
        if isFilePath
            EEG = pop_loadset('filename', filePath, 'loadmode', 'info');
        else
            EEG = InputData;
        end

        % Inject Brainstorm metadata
        EEG.etc.brainstorm.db_file   = {sFilesEpoch.FileName};
        EEG.etc.brainstorm.protocol  = char(config.ProtocolName);
        EEG.etc.brainstorm.subject   = subjName;
        EEG.etc.brainstorm.db_path   = dbDir;
        EEG.etc.brainstorm.data_type = dataTypeStr;
        EEG.etc.brainstorm.epoched   = isEpoched;

        % Update setname
        if isfield(config, 'SaveName') && strlength(config.SaveName) > 0
            EEG.setname = char(config.SaveName);
        else
            EEG.setname = strcat(subjName, "_bst_imported");
        end

        log.info(sprintf("Import completed. %d file(s) in Brainstorm DB.", length(sFilesEpoch)));

    catch ME
        if strlength(tempFolder) > 0 && exist(tempFolder, 'dir')
            rmdir(tempFolder, 's');
        end
        log.error(sprintf("Brainstorm import failed: %s", ME.message));
        rethrow(ME);
    end

    % =========================================================================
    %% 13. Save
    % =========================================================================
    if config.Save
        logParams = unpackStruct(logConfig);
        HRB_saveData(EEG, "Name", config.SaveName, "Folder", module, ...
                     "OutputFolder", config.OutputFolder, logParams{:});
    end

end