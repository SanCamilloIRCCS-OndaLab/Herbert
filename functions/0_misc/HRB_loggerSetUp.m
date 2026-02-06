% HRB_LOGGERSETUP - Set up a logger for the pipeline
%
% Usage:
%     >> [log] = HRB_loggerSetUp();
%
%
% Optional inputs:
%    Name
%    ShowDate
%    ShowTime
%    ShowFile
%    LogFile
%
% Outputs:
%    log = [logger] Logger object
%
% Authors: Alessandro Tonin, IRCCS San Camillo Hospital, 2024
% 
% See also: LOGGER

function log = HRB_loggerSetUp(module, logOptions)
    arguments (Input)
        module (1,1) string {mustBeMember(module, ["general", "preprocessing", "headmodel", "source", "sourceestimation", "connectivity", "network"])}
        logOptions struct = struct()
    end
    arguments (Output)
        log logger
    end

    %% Parsing arguments
    config = HRB_loadConfig(module, "logging", logOptions);
    
    loggerName = sprintf("HRB_%s", module);

    log = logger(loggerName);
    log.enabled = config.LogEnabled;
    log.default_level = config.LogLevel;
    log.show_date = true;
    log.show_time = true;
    log.show_ms = true;
    log.show_logging_filename = true;
    log.log_to_command_window = true;
    log.log_to_file = true;
    if module == "general"
        log.log_directory = config.LogFileDir;
    else
        log.log_directory = fullfile(config.LogFileDir, module);
    end
    log.log_filename = config.LogFileName;

end

