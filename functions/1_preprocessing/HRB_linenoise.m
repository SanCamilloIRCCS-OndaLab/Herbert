function [EEG] = HRB_linenoise(EEG, opt)
% HRB_LINENOISE - Performs Line-Noise Rejection using Zapline-Plus or FIR Notch filter
%
% Usage:
%   >>> EEG = HRB_linenoise(EEG, 'Method', "zapline", 'ZapChunkLength', 0, 'ZapAdaptiveNRemove', true);
%   >>> EEG = HRB_linenoise(EEG, 'Method', "notch", 'NotchFreq', 50, 'NotchHarmonics', [1 2 3]);
%
% Parameters:
%   EEG (struct): EEG struct using EEGLAB structure system
%
% Other Parameters:
%   Method (string): "zapline" or "notch"
%
%   -- Zapline-Plus Options --
%   ZapNoiseFreqs : "line" (50/60Hz), "auto" (search 17-99Hz), or numeric array (e.g. 50)
%   ZapDetectorThreshold (double): Auto noise detector threshold (default 4)
%   ZapChunkLength (double): Length of chunks in seconds. 0 = automatic detection (default 0)
%   ZapAdaptiveNRemove (logical): Automatic adaptation of number of removed components (default true)
%   ZapFixedNRemove (double): Minimum/fixed number of components to remove (default 1)
%   ZapAdaptiveSigma (logical): Automatic adaptation of noiseCompDetectSigma (default true)
%   ZapSigmaThresh (double): Initial sigma threshold for outlier detection (default 3)
%   ZapPlot (logical): Plot Zapline results (default false)
%
%   -- Notch Options --
%   NotchFreq (double): Base line frequency to remove (e.g., 50 or 60)
%   NotchWidth (double): Bandwidth of the notch filter (e.g., 2)
%   NotchHarmonics (double array): Multipliers for the base frequency (e.g. [1 2 3] for 50, 100, 150 Hz)
%   NotchFiltOrder (double): Optional manual FIR filter order (must be even).
%   NotchPlot (logical): Plot filter frequency response
%
% Authors: Ettore Napoli, University of Bologna, 2026

arguments(Input)
    EEG struct
    % Method selection
    opt.Method string {mustBeMember(opt.Method, ["zapline", "notch"])}

    % Zapline parameters
    opt.ZapNoiseFreqs = 'line'
    opt.ZapDetectorThreshold double
    opt.ZapChunkLength double
    opt.ZapAdaptiveNRemove logical
    opt.ZapFixedNRemove double
    opt.ZapAdaptiveSigma logical
    opt.ZapSigmaThresh double
    opt.ZapPlot logical

    % Notch parameters
    opt.NotchFreq double
    opt.NotchWidth double
    opt.NotchHarmonics double
    opt.NotchFiltOrder double
    opt.NotchPlot logical

    % Save options
    opt.Save logical
    opt.SaveName string
    opt.OutputFolder string

    % Log options
    opt.LogEnabled logical
    opt.LogLevel double {mustBeInteger, mustBeInRange(opt.LogLevel, 0, 6)}
    opt.LogToFile logical
    opt.LogFileDir string
    opt.LogFileName string
end

%% Constants
module = "preprocessing";

%% Parsing Arguments
config = HRB_loadConfig(module, "linenoise", opt);

%% Logger
logConfig = HRB_loadConfig(module, "logging", opt);
log = HRB_loggerSetUp(module, logConfig);

%% Output folder
if config.OutputFolder == "" && config.Save
    timestamp = string(datetime("now", "Format","yyyyMMdd_HHmmss"));
    config.OutputFolder = fullfile("output", timestamp);
end

if config.Save && ~exist(config.OutputFolder, 'dir')
    mkdir(config.OutputFolder);
end

%% Apply Method
log.info(sprintf("Initiating Line-Noise Rejection using Method: %s", config.Method));

% ZapLine
if config.Method == "zapline"
    log.info("Preparing ZapLine plus parameters");

    % Parse Arguments for ZapLine
    nf = config.ZapNoiseFreqs;
    if isnumeric(nf)
        parsedNoiseFreqs = nf; %Explicit frequencies (50, [50, 100])
    elseif strcmpi(nf, "auto")
        parsedNoiseFreqs = []; % Auto search
    else
        parsedNoiseFreqs = char(nf); % line
    end


        % Format frequencies for safe logging
        freqsForLog = strjoin(string(config.ZapNoiseFreqs), ',');

        log.info(sprintf("Running pop_zapline_plus (Freqs: %s, DetThresh: %g, ChunkLen: %g, AdaptNRem: %d, FixedNRem: %g, AdaptSigma: %d, SigmaThresh: %g)", ...
            freqsForLog, ...
            config.ZapDetectorThreshold, ...
            config.ZapChunkLength, ...
            config.ZapAdaptiveNRemove, ...
            config.ZapFixedNRemove, ...
            config.ZapAdaptiveSigma, ...
            config.ZapSigmaThresh));

        EEG = pop_zapline_plus(EEG, ...
            'noisefreqs', parsedNoiseFreqs, ...
            'coarseFreqDetectPowerDiff', config.ZapDetectorThreshold, ...
            'chunkLength', config.ZapChunkLength, ...
            'adaptiveNremove', double(config.ZapAdaptiveNRemove), ...
            'fixedNremove', config.ZapFixedNRemove, ...
            'adaptiveSigma', double(config.ZapAdaptiveSigma), ...
            'noiseCompDetectSigma', config.ZapSigmaThresh, ...
            'plotResults', double(config.ZapPlot));

        % Notch
    elseif config.Method == "notch"
        log.info("Running pop_eegfiltnew (Notch)");

        % Iterate through specified harmonics
        for h = config.NotchHarmonics(:).'
            centerFreq = config.NotchFreq*h;
            locutoff = centerFreq - (config.NotchWidth / 2);
            hicutoff = centerFreq + (config.NotchWidth / 2);

            nyquist = EEG.srate/2;
            if hicutoff >= nyquist
                log.warning(sprintf("Skipping notch @ %g Hz: upper edge %.1f >= Nyquist %.1f (srate=%g)", ...
                    centerFreq, hicutoff, nyquist, EEG.srate));
                continue;
            end

            log.info(sprintf("Applying notch filter around %d Hz (locutoff: %.1f, hicutoff: %.1f)", centerFreq, locutoff, hicutoff));

            % Set up filter order argument
            if isempty(config.NotchFiltOrder)
                filtOrderArg = {};
            else
                filtOrderArg = {'filtorder', config.NotchFiltOrder};
            end

            % Run notch
            EEG = pop_eegfiltnew(EEG, ...
                'locutoff', locutoff, ...
                'hicutoff', hicutoff, ...
                'revfilt', 1, ...
                'plotfreqz', config.NotchPlot, ...
                filtOrderArg{:});
        end
    end

%% Save
if config.Save
    log.info("Saving line noise rejected data");
    if config.SaveName == ""
        final_name = EEG.setname + "_linenoise";
    else
        final_name = config.SaveName;
    end

    logParams = unpackStruct(logConfig);
    HRB_saveData(EEG, "Name",final_name, "Folder", module, "OutputFolder", config.OutputFolder, logParams{:});
end

log.info("Line noise rejection completed")
end

