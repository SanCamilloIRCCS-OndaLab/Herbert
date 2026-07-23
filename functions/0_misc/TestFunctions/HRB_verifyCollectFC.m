function report = HRB_verifyCollectFC(T, protocolName, subjectList, options)
% HRB_VERIFYCOLLECTFC  Exhaustively verify a HRB_collectFC table against Brainstorm.
%
% PURPOSE
%   HRB_collectFC flattens Brainstorm connectivity matrices into a long-format
%   table. Every value in that table is addressed by a (subject, universe,
%   roi_from, roi_to, freq_band) key. This function re-derives each value
%   independently from the BST source files and compares them, so that a
%   pair-mapping bug cannot pass unnoticed
%
% WHY THIS TEST IS NOT CIRCULAR
%   The oracle never calls HRB_collectFC and never reuses its pairMap. It
%   rebuilds the full N-by-N matrix with reshape()/process_compress_sym and
%   then indexes it with EXPLICIT (i,j) subscripts derived from ROI *names*.
%   If collectFC's mapping were wrong, the names would point at different
%   matrix cells and the comparison would fail.
%
% DIRECTION CONVENTION (directed metrics: PTE, Granger, spectral Granger)
%   Brainstorm stores R as [nA x nB] and saves
%       FileMat.RefRowNames = sInputA.RowNames   -> matrix ROWS
%       FileMat.RowNames    = sInputB.RowNames   -> matrix COLUMNS
%   bst_connectivity.m explicitly permutes Granger output "to Brainstorm
%   expected orientation: [From, To]". Hence ROW = source (from),
%   COLUMN = target (to). Because MATLAB reshape() is column-major, the
%   flattened TF vector maps back with reshape(v,N,N) preserving M(i,j).
%   This function therefore treats roi_from as the row index and roi_to as
%   the column index, and additionally reports how many rows would only match
%   the TRANSPOSE, which would indicate an inverted causal direction.
%   Ref: brainstorm3/toolbox/connectivity/bst_connectivity.m
%
% USAGE
%   report = HRB_verifyCollectFC(T, "HRB_Test_Extended", "P02_ON_RESTING_post")
%   report = HRB_verifyCollectFC(T, protocol, subjects, Tolerance=1e-9)
%
% INPUTS
%   T            - table returned by HRB_collectFC with AverageTime=true
%   protocolName - BST protocol name (string)
%   subjectList  - string array of BST subject IDs (same ones passed to collectFC)
%
% OPTIONS
%   Tolerance    - (default 1e-9) absolute difference below which two values
%                  are considered equal. Values are doubles that went through
%                  a mean() and a save/load round-trip, so exact equality is
%                  not guaranteed; 1e-9 is far below any meaningful FC change.
%   Verbose      - (default true) print a per-universe line while scanning.
%
% OUTPUT
%   report - struct with fields:
%       .nRows       total rows in T
%       .nVerified   rows that were matched to a BST cell and compared
%       .nUnverified rows with no corresponding BST cell (see NOTES)
%       .nMismatch   rows whose value matches neither M(i,j) nor M(j,i)
%       .nTransposed rows matching M(j,i) but not M(i,j)  -> direction bug
%       .maxDiff     largest absolute difference observed
%       .badRows     indices into T of mismatching rows (for inspection)
%
% NOTES / EXPECTED BEHAVIOUR
%   - Symmetric metrics (corr, cohere, wpli, aec/henv) are stored COMPRESSED
%     by Brainstorm: only the upper triangle including the diagonal, i.e.
%     N*(N+1)/2 rows in TF dim 1. They are expanded here with the official
%     BST routine. Note that process_compress_sym('Expand',...) returns a
%     FLAT [N^2 x 1] vector, not an N-by-N matrix, hence the reshape below.
%   - Directed metrics (pte, granger, spgranger) are NOT compressed:
%     TF dim 1 is N^2. Ref: bst_connectivity.m, OPTIONS.isSymmetric list.
%   - Frequency labels must be generated with the SAME rule collectFC uses,
%     otherwise nothing matches. Granger is broadband (Freqs = 0 -> "f0Hz")
%     and spectral Granger has numeric frequencies ("f2Hz", "f4Hz", ...),
%     not the five named bands. See local_freqnames().
%   - nUnverified > 0 is not automatically a bug, but it must be explained:
%     it means T contains rows whose ROI or band names do not appear in the
%     corresponding BST file.
%
% Authors: Ettore Napoli, University of Bologna, 2026

arguments
    T                        table
    protocolName      (1,1)  string
    subjectList              string
    options.Tolerance (1,1)  double  = 1e-9
    options.Verbose   (1,1)  logical = true
end


% Guard: this test assumes the time-averaged table.
% With AverageTime=false each pair has one row per time sample and the
% comparison would need a time index, which is not implemented here.
% Failing loudly is better than silently comparing the wrong things.

if ismember('time_s', T.Properties.VariableNames)
    error("HRB:verifyCollectFC:TimeResolved", ...
        "T was built with AverageTime=false. This verifier expects the time-averaged table.");
end


% Select the BST protocol.

iProtocol = bst_get('Protocol', char(protocolName));
if isempty(iProtocol)
    gui_brainstorm('UpdateProtocolsList');            % rescan DB, protocol may be on disk only
    iProtocol = bst_get('Protocol', char(protocolName));
end
if isempty(iProtocol)
    error("HRB:verifyCollectFC:ProtocolNotFound", "Protocol '%s' not found.", protocolName);
end
bst_set('iProtocol', iProtocol);


% Accumulators.
% 'verified' is a logical mask over T: it is the core of the completeness
% claim. At the end, sum(verified) must equal height(T), otherwise some rows
% of T were never backed by any BST cell.

verified    = false(height(T), 1);
nMismatch   = 0;
nTransposed = 0;
maxDiff     = 0;
badRows     = [];

subjectList = subjectList(:);

for iSubj = 1:numel(subjectList)
    subjId = subjectList(iSubj);

    % BST Comments are prefixed with the subject id in "clean" form, where
    % underscores were replaced by dashes by HRB cleanName. We need the clean
    % form to strip the prefix and recover universe_label exactly as
    % collectFC stored it.
    subjIdClean = strrep(subjId, '_', '-');

    [sSubject, ~] = bst_get('Subject', char(subjId));
    if isempty(sSubject)
        warning("HRB:verifyCollectFC:SubjectNotFound", "Subject '%s' not found.", subjId);
        continue
    end

    % bst_get('StudyWithSubject') can return studies belonging to OTHER
    % subjects that share the same default anatomy template. The FileName
    % guard below keeps only this subject's studies (same guard collectFC uses).
    sStudies = bst_get('StudyWithSubject', sSubject.FileName);

    for iSt = 1:numel(sStudies)
        s = sStudies(iSt);
        if ~contains(s.FileName, char(subjId)), continue; end     % cross-contamination guard
        if isempty(s.Timefreq),                 continue; end     % no connectivity here

        for iTF = 1:numel(s.Timefreq)

            % recover universe_label exactly as collectFC wrote it 
            comment = string(s.Timefreq(iTF).Comment);
            prefix  = subjIdClean + "_";
            if startsWith(comment, prefix)
                uni = extractAfter(comment, prefix);
            else
                uni = comment;                                   % legacy files without prefix
            end

            tf  = in_bst_timefreq(s.Timefreq(iTF).FileName);
            N   = numel(tf.RowNames);                            % number of ROIs
            nTF = size(tf.TF, 1);                                % packed pairs in dim 1

            % Frequency labels, generated with collectFC's own rule so that
            % the string comparison against T.freq_band can succeed.
            bands = local_freqnames(tf);
            nF    = numel(bands);

           
            % BUILD THE ORACLE: one full N-by-N matrix per frequency.
            %
            % Two storage layouts are handled:
            %   nTF == N^2         -> directed, already the full matrix, flat
            %   nTF == N*(N+1)/2   -> symmetric, compressed upper triangle
            %
            % In both cases we end up with a flat [N^2 x 1] vector that is
            % reshaped column-major. This mirrors how Brainstorm flattened it
            % (FileMat.TF = reshape(R, [], nTime, nFreq)) and is the ONLY
            % assumption in this oracle - one that reshape() itself defines.
            
            M     = nan(N, N, nF);
            known = true;
            for f = 1:nF
                % Frequency index into TF dim 3. Some metrics (broadband
                % Granger) have a single plane; min() keeps that case safe.
                iSrc = min(f, size(tf.TF, 3));

                % Average over dim 2 (time). collectFC does exactly
                % mean(tf.TF,2); the oracle must match that reduction or
                % every comparison would fail for time-resolved metrics
                % (e.g. wPLI with TimeRes='full' has 1000 time samples).
                v = mean(tf.TF(:, :, iSrc), 2);

                if nTF == N^2
                    M(:, :, f) = reshape(v, N, N);
                elseif nTF == N*(N+1)/2
                    % Official BST expander: single source of truth for the
                    % triangle packing order. It returns a FLAT vector.
                    M(:, :, f) = reshape(process_compress_sym('Expand', v, N), N, N);
                else
                    known = false;                               % unsupported layout
                    break
                end
            end
            if ~known
                warning("HRB:verifyCollectFC:UnknownLayout", ...
                    "Skipping '%s': dim1=%d with N=%d is not a handled layout.", uni, nTF, N);
                continue
            end

            % ROI name -> matrix index lookup 
            % Rows are indexed by RefRowNames (side A), columns by RowNames
            % (side B). For symmetric metrics some BST versions leave
            % RefRowNames empty or equal to RowNames; fall back safely.
            if numel(tf.RefRowNames) == N
                rowNames = string(tf.RefRowNames);
            else
                rowNames = string(tf.RowNames);
            end
            colNames = string(tf.RowNames);

            
            % COMPARE EVERY ROW OF T FOR THIS (subject, universe).
            %
            % We iterate over T rather than over matrix cells. This matters:
            % symmetric metrics are emitted by collectFC in ONE direction
            % only (upper triangle), so iterating over all (i,j) cells would
            % report spurious "missing" rows for the mirrored orientation.
            % Driving the loop from T also gives the completeness guarantee.
            
            idx = find(T.subj_id == subjId & T.universe_label == uni);

            for k = idx(:)'
                i = find(rowNames == T.roi_from(k),  1);
                j = find(colNames == T.roi_to(k),    1);
                f = find(bands    == T.freq_band(k), 1);

                % No corresponding cell: leave the row unverified and move on.
                % These are counted and reported, never silently ignored.
                if isempty(i) || isempty(j) || isempty(f)
                    continue
                end

                verified(k) = true;

                dDirect = abs(T.fc_value(k) - M(i, j, f));       % expected orientation
                dTransp = abs(T.fc_value(k) - M(j, i, f));       % transposed orientation

                if dDirect > options.Tolerance
                    if dTransp <= options.Tolerance
                        % Value is real but on the mirrored cell: for a
                        % directed metric this means from/to are swapped.
                        nTransposed = nTransposed + 1;
                    else
                        nMismatch = nMismatch + 1;
                        badRows(end+1) = k; %#ok<AGROW>
                    end
                end
                maxDiff = max(maxDiff, dDirect);
            end

            if options.Verbose
                fprintf('  checked %-70s (%d rows)\n', uni, numel(idx));
            end
        end
    end
end


% Report

report = struct( ...
    'nRows',       height(T), ...
    'nVerified',   sum(verified), ...
    'nUnverified', sum(~verified), ...
    'nMismatch',   nMismatch, ...
    'nTransposed', nTransposed, ...
    'maxDiff',     maxDiff, ...
    'badRows',     badRows);

fprintf('\n===== HRB_collectFC verification =====\n');
fprintf('rows in T        : %d\n', report.nRows);
fprintf('rows verified    : %d\n', report.nVerified);
fprintf('rows unverified  : %d\n', report.nUnverified);
fprintf('mismatches       : %d\n', report.nMismatch);
fprintf('TRANSPOSED       : %d\n', report.nTransposed);
fprintf('max |difference| : %.3e\n', report.maxDiff);

if report.nUnverified == 0 && report.nMismatch == 0 && report.nTransposed == 0
    fprintf('RESULT: PASS - every row of T matches its Brainstorm source cell.\n');
else
    fprintf('RESULT: REVIEW NEEDED - see badRows / unverified count above.\n');
end

if ~isempty(badRows)
    fprintf('\nFirst mismatching rows:\n');
    disp(T(badRows(1:min(10, numel(badRows))), :));
end

end


%% Helpers
function names = local_freqnames(tf)
% LOCAL_FREQNAMES  Reproduce HRB_collectFC's frequency-label rule.
%
% This MUST stay in sync with local_get_freqnames() in HRB_collectFC.m.
% If the two diverge, the string comparison T.freq_band == bands(f) never
% matches and the verifier silently checks nothing (it would report
% nUnverified instead of a mismatch, which is why that counter exists).
%
% Brainstorm uses two Freqs formats:
%   Nx3 cell  {band_name, 'lo, hi', aggregate_fn}  -> named bands
%   numeric vector of frequency values             -> spectral output
if iscell(tf.Freqs) && ~isempty(tf.Freqs)
    names = string(tf.Freqs(:, 1));                      % "delta", "alpha", ...
elseif isnumeric(tf.Freqs) && ~isempty(tf.Freqs)
    names = "f" + string(tf.Freqs(:)) + "Hz";            % "f0Hz" (broadband GC), "f8Hz", ...
else
    names = "band" + string((1:size(tf.TF, 3))');        % fallback
end
end