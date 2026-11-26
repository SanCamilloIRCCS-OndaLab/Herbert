function T = HRB_collectFC(protocolName, subjectList, opt)
% HRB_collectFC  Collect FC matrices from Brainstorm into a long-format table.
%
% For each (subject, universe), loads the BST timefreq file, optionally
% averages over time, and appends one row per (ROI pair × frequency band).
%
% Usage:
%   T = HRB_collectFC(protocolName, subjectList)
%   T = HRB_collectFC(protocolName, subjectList, AverageTime=true, IncludeDiag=false)
%   T = HRB_collectFC(protocolName, subjectList, OutputFile="results/fc.csv")
%
% Inputs:
%   protocolName  - BST protocol name (string)
%   subjectList   - string array of BST subject IDs (with '_', matching EEG.subject
%                   set by HRB_runDataset from the CSV subject_id column)
%
% Options:
%   AverageTime   - (default true)  average TF over the time axis.
%                   false = keep 1000 time points per row; slow, ~2M rows for
%                   4 subjects × 16 universes × 6 pairs × 5 bands × 1000 t.
%   IncludeDiag   - (default false) false = drop the diagonal (self-connectivity); true = keep the diagonal
%                   wPLI self-connectivity is trivially NaN; MSC is trivially 1.
%   OutputFile    - (default "")    if non-empty, write table to this CSV path.
%
% Output table columns (AverageTime=true):
%   subj_id        string   BST subject ID (with '_', from subjectList)
%   universe_label string   matches HRB_universeManifest universe_label column
%   roi_from       string   source ROI (from RefRowNames)
%   roi_to         string   target ROI (from RowNames)
%   freq_band      string   frequency band name from Freqs (e.g. "alpha")
%   fc_value       double   connectivity value (time-averaged if AverageTime=true)
%   [time_s]       double   time in seconds — present only if AverageTime=false
%
% PREREQUISITES:
%   - Brainstorm server must be running before calling this function.
%   - Universe labels in BST Comments must follow the format produced by
%     HRB_runPipeline: '{subjIdClean}_{filter}_{headmodel}_{inverse}_{connectivity}'
%     where subjIdClean = strrep(subjId, '_', '-').
%     Comments without that prefix are skipped (warning HRB:NoSubjPrefix)
% Authors: Ettore Napoli, University of Bologna, 2026

arguments
    protocolName  (1,1) string
    subjectList
    opt.AverageTime  (1,1) logical = true
    opt.IncludeDiag  (1,1) logical = false
    opt.OutputFile   (1,1) string  = ""
    opt.UniverseFilter (1,1) string = ""
end

subjectList = subjectList(:);  % enforce column vector

% If results cell array passed instead of subject list, extract BST subject
% names from EEG.etc.brainstorm.subject (set by HRB_bst_import after
% sanitization — underscores, matching BST internal naming).
if iscell(subjectList)
    results_in = subjectList;
    bstNames = {};
    for iR = 1:numel(results_in)
        entry = results_in{iR};
        if ~iscell(entry), continue; end
        for jR = 1:numel(entry)
            u = entry{jR};
            if isstruct(u) && isfield(u,'etc') && isfield(u.etc,'brainstorm') && ...
                    isfield(u.etc.brainstorm,'subject') && ~isempty(u.etc.brainstorm.subject)
                bstNames{end+1} = char(u.etc.brainstorm.subject); %#ok<AGROW>
                break  % one valid EEG per subject is enough
            end
        end
    end
    subjectList = string(unique(bstNames, 'stable'))';
end


% Column structure depends on AverageTime
if opt.AverageTime
    nCols    = 6;
    varNames = {'subj_id','universe_label','roi_from','roi_to','freq_band','fc_value'};
else
    nCols    = 7;
    varNames = {'subj_id','universe_label','roi_from','roi_to','freq_band','time_s','fc_value'};
end
C = cell(0, nCols);  % accumulate rows here

% Set BST protocol
iProtocol = bst_get('Protocol', char(protocolName));
if isempty(iProtocol)
    gui_brainstorm('UpdateProtocolsList');
    iProtocol = bst_get('Protocol', char(protocolName));
end
if isempty(iProtocol)
    error('HRB:ProtocolNotFound', 'Protocol ''%s'' not found.', protocolName);
end
bst_set('iProtocol', iProtocol);

% Process each subject
nSubj = numel(subjectList);
for iSubj = 1:nSubj
    subjId      = subjectList(iSubj);
    subjIdClean = strrep(subjId, '_', '-');  % BST Comments use '-' (from HRB cleanName)

    fprintf('[%d/%d] %s\n', iSubj, nSubj, subjId);

    [sSubject, ~] = bst_get('Subject', char(subjId), 1); % isRaw=1: own file not default subj
    if isempty(sSubject)
        warning('HRB:SubjectNotFound', 'Subject ''%s'' not found in protocol. Skipping.', subjId);
        continue;
    end

    % sSubject is the subject's own file (isRaw=1): with the default
    % anatomy file, StudyWithSubject would return the studies of ALL
    % default-anatomy subjects. The folder guard below stays as a second
    % safety net
    sStudies = bst_get('StudyWithSubject', sSubject.FileName);

    for iSt = 1:numel(sStudies)
        sStudy = sStudies(iSt);

        % Cross-contamination guard (folder match)
        if ~HRB_bst_isSubjectStudy(sStudy.FileName, sSubject.FileName)
            continue;
        end
        if isempty(sStudy.Timefreq)
            continue;
        end

        for iTF = 1:numel(sStudy.Timefreq)
            comment = string(sStudy.Timefreq(iTF).Comment);

            % Extract universe_label: strip '{subjIdClean}_' prefix
            prefix = subjIdClean + "_";
            if startsWith(comment, prefix)
                universeLabel = extractAfter(comment, prefix);
            else
                % not attributable to this run (old run or another subj): skip
                warning('HRB:NoSubjPrefix', ...
                    'Comment "%s" lacks the expected prefix "%s": skipped.', comment, prefix);
                continue;
            end

            % Filter by universe, if present
            if strlength(opt.UniverseFilter) > 0 && ~contains(universeLabel, opt.UniverseFilter)
                continue;
            end

            % Load BST timefreq file (path is relative to protocol folder)
            tf = in_bst_timefreq(sStudy.Timefreq(iTF).FileName);
            fprintf('  iTF=%d/%d\n', iTF, numel(sStudy.Timefreq));

            % Detect storage format (symmetric, directed, cross-connectivity, etc.)
            [pairMap, ~] = local_detect_storage(tf);
            if isempty(pairMap)
                warning('HRB:UnknownStorageFormat', ...
                    'TF dim1=%d, nRef=%d, nRow=%d: unrecognised pair storage. Skipping: "%s".', ...
                    size(tf.TF,1), numel(tf.RefRowNames), numel(tf.RowNames), comment);
                continue;
            end
            nPairsAll = size(pairMap, 1);

            % Select pairs based on IncludeDiag
            % (cross-connectivity and excl-diag formats have no diagonal rows)
            isSquare = (numel(tf.RefRowNames) == numel(tf.RowNames));
            hasDiag  = isSquare && any(pairMap(:,1) == pairMap(:,2));
            if hasDiag && ~opt.IncludeDiag
                selMask = pairMap(:,1) ~= pairMap(:,2);
            else
                selMask = true(nPairsAll, 1);
            end
            pairSel  = pairMap(selMask, :);
            tfIdxSel = find(selMask);
            nSel     = size(pairSel, 1);

            % Frequency band names
            freqNames = local_get_freqnames(tf);
            nFreq     = numel(freqNames);

            % Average over time (dim 2):
            %   [nPairsAll × nTime × nFreq] → [nPairsAll × nFreq]
            if opt.AverageTime
                TF_proc = reshape(mean(tf.TF, 2), nPairsAll, nFreq);
            else
                TF_proc = tf.TF;  % keep full [nPairsAll × nTime × nFreq]
                nTimePts = size(TF_proc, 2);
                timeVec  = local_time_vector(tf, nTimePts);
            end


            % Unpack into table rows
            for p = 1:nSel
                r       = pairSel(p, 1);
                c       = pairSel(p, 2);
                iTFrow  = tfIdxSel(p);
                roiFrom = string(tf.RefRowNames{r});
                roiTo   = string(tf.RowNames{c});

                for f = 1:nFreq
                    if opt.AverageTime
                        fc_val = TF_proc(iTFrow, f);
                        C(end+1, :) = {subjId, universeLabel, roiFrom, roiTo, freqNames(f), fc_val}; %#ok<AGROW>
                    else
                        fcVec = squeeze(TF_proc(iTFrow, :, f))';   % [nTimePts × 1] column
                        chunk = [repmat({subjId, universeLabel, roiFrom, roiTo, freqNames(f)}, nTimePts, 1), ...
                            num2cell(timeVec), ...
                            num2cell(fcVec)];
                        C = [C; chunk];
                    end
                end
            end

        end  % iTF
    end  % iSt
end  % iSubj

% Assemble output table
if isempty(C)
    warning('HRB:NoData', 'No FC data collected. Check protocol name, subject IDs, and BST study structure.');
    T = table();
    return;
end

T = cell2table(C, 'VariableNames', varNames);

% Ensure correct types (cell2table may leave string columns as cell-of-char)
strCols = {'subj_id','universe_label','roi_from','roi_to','freq_band'};
for k = 1:numel(strCols)
    if iscell(T.(strCols{k}))
        T.(strCols{k}) = string(T.(strCols{k}));
    end
end
if iscell(T.fc_value)
    T.fc_value = cell2mat(T.fc_value);
end
if ~opt.AverageTime && ismember('time_s', T.Properties.VariableNames)
    if iscell(T.time_s)
        T.time_s = cell2mat(T.time_s);
    end
end

%  Optional CSV export
if strlength(opt.OutputFile) > 0
    writetable(T, opt.OutputFile);
    fprintf('HRB_collectFC: table saved → %s\n', opt.OutputFile);
end

end


%% Helpers
function [pairMap, storageMode] = local_detect_storage(tf)
% Detect how BST stored NxN pairs in tf.TF dim 1 and return the pair index map.
%
% BST packs pairs COLUMN-MAJOR within each format (first matrix index fastest,
% i.e. M(:) order).
nRef = numel(tf.RefRowNames);
nRow = numel(tf.RowNames);
nTF  = size(tf.TF, 1);
pairMap     = [];
storageMode = '';

if nRef == nRow
    N = nRef;

    if nTF == N*(N+1)/2
        storageMode = 'sym_upper_incl_diag';
        pairMap = zeros(nTF, 2); p = 0;
        for c = 1:N;   for r = 1:c;   p=p+1; pairMap(p,:) = [r,c]; end; end

    elseif nTF == N*(N-1)/2
        storageMode = 'sym_upper_excl_diag';
        pairMap = zeros(nTF, 2); p = 0;
        for c = 1:N;   for r = 1:c-1; p=p+1; pairMap(p,:) = [r,c]; end; end

    elseif nTF == N^2
        storageMode = 'full_NxN';
        pairMap = zeros(nTF, 2); p = 0;
        for c = 1:N;   for r = 1:N;   p=p+1; pairMap(p,:) = [r,c]; end; end

    elseif nTF == N*(N-1)
        storageMode = 'full_NxN_excl_diag';
        pairMap = zeros(nTF, 2); p = 0;
        for c = 1:N
            for r = 1:N
                if r ~= c; p=p+1; pairMap(p,:) = [r,c]; end
            end
        end
    end
    % else: unrecognised — pairMap stays []

else
    % Cross-connectivity: RefRowNames ≠ RowNames (e.g. seed-to-whole-brain)
    if nTF == nRef * nRow
        storageMode = 'cross_NrefxNrow';
        pairMap = zeros(nTF, 2); p = 0;
        for c = 1:nRow; for r = 1:nRef; p=p+1; pairMap(p,:) = [r,c]; end; end
    end
end

if ~isempty(pairMap)
    assert(p == nTF && all(pairMap(:) > 0), ...
        'HRB:collectFC:pairMapFill', ...
        'pairMap incomplete for %s: p=%d, nTF=%d', storageMode, p, nTF);
end

end

%% Helpers

function names = local_get_freqnames(tf)
% Extract frequency band names from BST tf.Freqs field.
%
% Handles the two formats BST uses:
%   - Nx3 cell {band_name, freq_range, aggregate_fn}  (frequency-band connectivity)
%   - numeric vector of frequency values               (spectral connectivity)
if iscell(tf.Freqs) && ~isempty(tf.Freqs)
    names = string(tf.Freqs(:, 1));           % "delta", "theta", "alpha", etc.
elseif isnumeric(tf.Freqs) && ~isempty(tf.Freqs)
    names = "f" + string(tf.Freqs(:)) + "Hz"; % "f8Hz", "f10Hz", etc.
else
    nFreq = size(tf.TF, 3);
    names = "band" + string((1:nFreq)');       % fallback: "band1", "band2", etc.
end
end

function tv = local_time_vector(tf, nTimePts)
% Return a [nTimePts × 1] time vector aligned to size(tf.TF,2).
% BST band/window-collapsed connectivity stores size(TF,2)=1 while tf.Time is
% a [start end] 2-vector (cf. bst_connectivity Finalize: Time = sInputB.Time([1,end])).
% Time-resolved results have numel(tf.Time)==size(TF,2). Never assume they match.
t = tf.Time(:);
if isempty(t)
    tv = (1:nTimePts).';
elseif numel(t) == nTimePts
    tv = t;                                 % time-resolved: exact match
elseif nTimePts == 1
    tv = mean(t);                           % collapsed: window midpoint
elseif numel(t) == 2
    tv = linspace(t(1), t(2), nTimePts).';  % [start end] -> samples
else
    tv = (1:nTimePts).';                    % fallback: sample index
end
end