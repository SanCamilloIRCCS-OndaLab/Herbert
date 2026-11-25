function HRB_checkBandsVsFilter(EEG, freqBands, maxFreq, log)
% HRB_CHECKBANDSVSFILTER - Warn when connectivity bands (or MaxFreq) extend
% above the low-pass applied upstream (EEG.etc.HRB.filter, set by HRB_filter).
% Warning only (multiverse: never block a user choice).
%
% Inputs:
%   EEG       - EEG struct; returns silently without EEG.etc.HRB.filter
%   freqBands - BST cell {name, 'lo, hi', fn; ...} or {}
%   maxFreq   - [Hz] or []
%   log       - logger object
%
% Authors: Ettore Napoli, University of Bologna, 2026
if ~isstruct(EEG) || ~isfield(EEG, 'etc') || ~isfield(EEG.etc, 'HRB') || ~isfield(EEG.etc.HRB, 'filter')
    return;
end
flt = EEG.etc.HRB.filter;
if ~ismember(string(flt.type), ["lowpass","bandpass"]) || isempty(flt.hicutoff) || flt.hicutoff <= 0
    return;
end
hi = flt.hicutoff;
for k = 1:size(freqBands, 1)
    lim = str2double(strsplit(char(freqBands{k,2}), ','));
    if numel(lim) == 2 && lim(2) > hi
        log.warning(sprintf("Band '%s' [%s] Hz extends above the upstream low-pass (%g Hz).", ...
            char(freqBands{k,1}), char(freqBands{k,2}), hi));
    end
end
if ~isempty(maxFreq) && maxFreq > hi
    log.warning(sprintf("MaxFreq = %g Hz is above the upstream low-pass (%g Hz).", maxFreq, hi));
end
end