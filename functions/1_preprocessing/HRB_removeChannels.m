function [EEG] = HRB_removeChannels(EEG, opt)
% HRB_REMOVECHANNELS - Remove a list of channels from an EEG dataset.
%
% Examples:
%     >>> [EEG] = HRB_removeChannels(EEG)
%     >>> [EEG] = HRB_removeChannels(EEG, 'key', val) 
%     >>> [EEG] = HRB_removeChannels(EEG, key=val) 
%
% Parameters:
%    EEG (struct): EEG struct using EEGLAB structure system
%
% Other Parameters:
%    Channels ({str}): Cell array with channel names
%
% Returns:
%    EEG (struct): EEG struct using EEGLAB structure system
% 
% See also: 
%    EEGLAB, POP_SELECT

% Authors: Alessandro Tonin, IRCCS San Camillo Hospital, 2024

    arguments (Input)
        EEG struct
        % Optional
        opt.Channels (1,:) string
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
    config = HRB_loadConfig(module, "removeChannels", opt);

    %% Logger
    logConfig = HRB_loadConfig(module, "logging", opt);
    log = HRB_loggerSetUp(module);
    
    %% Removing channels
    log.info("Removing channels")

    log.info(sprintf("Removed channels %s", config.Channels))

    EEG = pop_select(EEG, 'rmchannel', cellstr(config.Channels), config.EEGLAB{:});

    %% Save
    if config.Save
        logParams = unpackStruct(logConfig);
        HRB_saveData(EEG, "Name", config.SaveName, "Folder", module, "OutputFolder", config.OutputFolder, logParams{:});
    end

end

