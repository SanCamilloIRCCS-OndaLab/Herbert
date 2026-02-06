function HRB_saveData(data, opt)
% HRB_SAVEDATA - Save a data object. The saved data can be in different
% format depending on the module where it is saved.
%
% Example:
%     >>> HRB_saveData(data)
%     >>> HRB_saveData(data, opt.Name)
%     >>> HRB_saveData(data, opt.Name, opt.Folder)
%
% Parameters:
%    data (any): A set of data
%
% Other Parameters:
%    Name (string): The name of the saved file (default: the name
%           of the calling function)
%    Folder (string): The folder where to save the file (default: the
%           name of the module of the calling function)
%    OutputFolder (string): The main folder for all output files. (default: 'output/date')
%
% See also: 
%   SAVE, POP_SAVESET

% Authors: Alessandro Tonin, IRCCS San Camillo Hospital, 2024
% 

    arguments (Input)
        data
        % Optional
        opt.Name string = ""
        opt.Folder string = ""
        opt.OutputFolder string = ""
        % Log options
        opt.LogEnabled logical
        opt.LogLevel double {mustBeInteger,mustBeInRange(opt.LogLevel,0,6)}
        opt.LogToFile logical
        opt.LogFileDir string
        opt.LogFileName string
    end

    %% Get module and callingFunction
    [module, functionName] = HRB_getModuleAndName(2);

    %% Logger
    logConfig = HRB_loadConfig(module, "logging", opt);
    log = HRB_loggerSetUp(module,logConfig);

    %% Get folder and name automatically from the calling function
    if opt.Folder == "" || opt.Name == ""
        if opt.Folder == ""
            opt.Folder = module;
        end
        if opt.Name == ""
            opt.Name = functionName;
        end
    end

    %% Get the main output folder
    if opt.OutputFolder == ""
        nowstr = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
        opt.OutputFolder = fullfile("output", nowstr);
    end

    %% Save

    saveFolder = fullfile(opt.OutputFolder, opt.Folder);
    
    % Check folder and create it if does not exist
    if ~exist(saveFolder, "dir")
        [success, message, ~] = mkdir(saveFolder);
        if ~success
            error(message)
        end
    end

    % clean save name removing extensions
    [~, opt.Name, ~] = fileparts(opt.Name);

    % Check data type
    dataType = HRB_checkDataType(data);

    unknownType = false;

    switch dataType
        case "EEGLAB"
            saveExt = 'set';
            filename = sprintf("%s.%s", opt.Name, saveExt);
            % Save with EEGLAB function
            log.info(sprintf("Save EEGLAB dataset: %s", fullfile(saveFolder,filename)))
            try
                pop_saveset(data,...
                    'filename', char(filename),...
                    'filepath', char(saveFolder),...
                    'savemode', 'onefile', ...
                    'version', '7.3')
            catch ME
                log.error("EEGLAB saveset not working.")
                unknownType = true;
            end
        case "CellArray"
            saveExt = 'csv';
            filename = sprintf("%s.%s", opt.Name, saveExt);
            savePath = fullfile(saveFolder,filename);
            % Save with writecell function
            log.info(sprintf("Save csv data: %s", savePath))
            try
                writecell(data, savePath,"Delimiter",",");
            catch ME
                log.error("Function writecell not working.")
                unknownType = true;
            end
        otherwise
            unknownType = true;
    end
    if unknownType
        % Unknown type. Save a mat file
        log.warning("Unknown type of data. Saving as Matlab variable.")
        saveExt = 'mat';
        opt.Name = sprintf("%s.%s", opt.Name, saveExt);
        
        saveFullPath = fullfile(saveFolder, opt.Name);
        log.info(sprintf("Save matlab dataset: %s", saveFullPath))
        
        save(saveFullPath, "data", "-v7.3")
    end
end

