function [EEG] = HRB_filter(EEG, opt)
% HRB_FILTER - Filter an EEG dataset. Based on EEGLAB functions.
%
% Examples:
%    >>> [EEG] = HRB_filter(EEG);
%    >>> [EEG] = HRB_filter(EEG, 'key', val);
%    >>> [EEG] = HRB_filter(EEG, key=val);
%
% Parameters:
%    EEG (struct): EEG struct using EEGLAB structure system
%
% Other Parameters:
%    Type (string): Type of the filter. Allowed values are: `bandpass`, `lowpass`, `highpass`, `bandstop`
%    LowCutoff (double): The low cutoff frequency
%    HighCutoff (double): The high cutoff frequency
%
% Returns:
%    EEG (struct): filtered EEG struct using EEGLAB structure system
% 
% See also: 
%    EEGLAB, POP_EEGFILTNEW

% Authors: Alessandro Tonin, IRCCS San Camillo Hospital, 2024

    arguments (Input)
        EEG struct
        % Optional
        opt.Type string {mustBeMember(opt.Type, ["lowpass", "highpass", "bandpass", "bandstop"])}
        opt.LowCutoff double 
        opt.HighCutoff double
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
    config = HRB_loadConfig(module, "filter", opt);

    %% Logger
    logConfig = HRB_loadConfig(module, "logging", opt);
    log = HRB_loggerSetUp(module, logConfig);

    %% Filter
    log.info("Filtering")
    switch config.Type
        case "lowpass"
            locutoff = 0;
            hicutoff = config.HighCutoff;
            revfilt = 0;
            log.info(sprintf("Lowpass filter - %d Hz", hicutoff));
        case "highpass"
            hicutoff = 0;
            locutoff = config.LowCutoff;
            revfilt = 0;
            log.info(sprintf("Highpass filter %d Hz", locutoff));
        case "bandpass"
            hicutoff = config.HighCutoff;
            locutoff = config.LowCutoff;
            revfilt = 0;
            log.info(sprintf("Bandpass filter %d - %d Hz", locutoff, hicutoff));
        case "bandstop"
            hicutoff = config.HighCutoff;
            locutoff = config.LowCutoff;
            revfilt = 1;
            log.info(sprintf("Bandstop filter %d - %d Hz", locutoff, hicutoff));
        otherwise
            % This should never happen since there is the argument
            % validation
            error("ERROR: Type %s not allowed. Only allowed filters are: 'lowpass', 'highpass', 'bandpass', bandstop'", config.Type)
    end
    
    EEG = pop_eegfiltnew(EEG,'locutoff',locutoff,'hicutoff',hicutoff,'revfilt',revfilt, config.EEGLAB{:});

    %% Save
    if config.Save
        logParams = unpackStruct(logConfig);
        HRB_saveData(EEG, "Name", config.SaveName, "Folder", module, "OutputFolder", config.OutputFolder, logParams{:});
    end
end

