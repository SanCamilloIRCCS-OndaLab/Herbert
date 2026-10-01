function Q = HRB_collectQCFromDisk(runRoot, P, opt)
%HRB_collectQCFromDisk  Per-universe QC (excluded channels, rejected comps,
%                       rejected epochs) read from DISK — current 4-fork layout.
%
%  Replaces the old-layout HRB_collectQC. Reads only lightweight text artifacts
%  (no .set loading, so it's cheap on network storage):
%    excluded channels  <subj>/<line>/<badchan>/preprocessing/*_ExcludedChannels.csv  (row 1)
%    rejected comps     <subj>/<line>/<badchan>/<flag>/preprocessing/*_rejectedComps.txt (row 1)
%    rejected epochs    <...>/<rejepochs>/preprocessing/HRB_preprocessing.log
%                       line "Found N bad trials out of M"
%
%  Keys on the spina P (from HRB_universePaths / HRB_universePathsFromDisk):
%  columns universe_id (underscore), subject (clean folder form), status.
%  Channels are shared by the 6 universes under a badchan; comps by the 3 under
%  a flag — the same values repeat across sibling rows, correctly.
%
%  USAGE
%    P = HRB_universePathsFromDisk(runRoot, manifest, Report=reportDisk);
%    Q = HRB_collectQCFromDisk(runRoot, P, OutputFile="qc.csv");
%    % worst channel loss / most epochs rejected:
%    sortrows(Q, "pct_epochs_rejected", "descend")
%
%  OUTPUT  table, one row per universe x subject:
%    subject, universe_id, status,
%    n_channels_excluded, channels_excluded,
%    n_comps_rejected,    comps_rejected,
%    n_epochs_total, n_epochs_rejected, n_epochs_retained, pct_epochs_rejected
%
%  NOTE  assumes axis names contain no '_' (verified for this run: line/badchan/
%  flag/rejepochs). A subject still being written shows NaN/missing for its
%  incomplete universes — run after the pipeline finishes for a complete table.
%
% Author: Ettore Napoli - University of Bologna, 2026

arguments (Input)
    runRoot        (1,1) string
    P              table
    opt.OutputFile (1,1) string = ""
end

runRootC = char(runRoot);
n = height(P);

subject             = strings(n,1);
universe_id         = strings(n,1);
statusCol           = strings(n,1);
n_channels_excluded = nan(n,1);
channels_excluded   = strings(n,1);
n_comps_rejected    = nan(n,1);
comps_rejected      = strings(n,1);
n_epochs_total      = nan(n,1);
n_epochs_rejected   = nan(n,1);
n_epochs_retained   = nan(n,1);
pct_epochs_rejected = nan(n,1);

for i = 1:n
    subjF = string(P.subject(i));
    uid   = string(P.universe_id(i));
    subject(i)     = subjF;
    universe_id(i) = uid;
    statusCol(i)   = string(P.status(i));

    parts = split(uid, "_");
    if numel(parts) < 4, continue; end          % unexpected uid shape — skip QC
    line = parts(1); badchan = parts(2); flag = parts(3); rej = parts(4);

    bcDir  = fullfile(runRootC, char(subjF), char(line), char(badchan), 'preprocessing');
    flDir  = fullfile(bcDir, '..', char(flag), 'preprocessing');
    rejLog = fullfile(runRootC, char(subjF), char(line), char(badchan), char(flag), ...
                      char(rej), 'preprocessing', 'HRB_preprocessing.log');

    % --- excluded channels (row 1 of the CSV) ---
    csvF = fullfile(bcDir, char(subjF + "_" + line + "_" + badchan + "_ExcludedChannels.csv"));
    [n_channels_excluded(i), channels_excluded(i)] = local_read_list(csvF);

    % --- rejected components (row 1 of the txt) ---
    compF = fullfile(flDir, char(subjF + "_" + line + "_" + badchan + "_" + flag + ...
                                 "_ic-removal_rejectedComps.txt"));
    [n_comps_rejected(i), comps_rejected(i)] = local_read_list(compF);

    % --- rejected epochs (from the rejepochs leaf log) ---
    if isfile(rejLog)
        txt = fileread(rejLog);
        tok = regexp(txt, 'Found\s+(\d+)\s+bad trials out of\s+(\d+)', ...
                     'tokens', 'once', 'ignorecase');
        if ~isempty(tok)
            nRej = str2double(tok{1});
            nTot = str2double(tok{2});
            n_epochs_total(i)      = nTot;
            n_epochs_rejected(i)   = nRej;
            n_epochs_retained(i)   = nTot - nRej;
            if nTot > 0, pct_epochs_rejected(i) = 100 * nRej / nTot; end
        end
    end
end

Q = table(subject, universe_id, statusCol, ...
    n_channels_excluded, channels_excluded, ...
    n_comps_rejected, comps_rejected, ...
    n_epochs_total, n_epochs_rejected, n_epochs_retained, pct_epochs_rejected, ...
    'VariableNames', {'subject','universe_id','status', ...
        'n_channels_excluded','channels_excluded', ...
        'n_comps_rejected','comps_rejected', ...
        'n_epochs_total','n_epochs_rejected','n_epochs_retained','pct_epochs_rejected'});

fprintf(['[HRB_collectQCFromDisk] %d rows | channels read %d | comps read %d | ' ...
         'epochs read %d\n'], n, sum(~isnan(Q.n_channels_excluded)), ...
    sum(~isnan(Q.n_comps_rejected)), sum(~isnan(Q.n_epochs_total)));

if strlength(opt.OutputFile) > 0
    writetable(Q, char(opt.OutputFile));
    fprintf("[HRB_collectQCFromDisk] Written to %s\n", opt.OutputFile);
end
end


%% ------------------------------------------------------------------ helper
function [count, items] = local_read_list(f)
% Count comma-separated items on row 1 of a QC file, dropping '' and '-1'
% logger sentinels. Returns count and the items joined with ';'.
count = NaN; items = "";
if ~isfile(f), return; end
fid = fopen(f, 'r');
if fid < 0, return; end
line1 = fgetl(fid); fclose(fid);
if ~ischar(line1)                      % empty file -> nothing excluded
    count = 0; return
end
p = strtrim(string(strsplit(line1, ",")));
p = p(p ~= "" & p ~= "-1");
count = numel(p);
items = strjoin(p, ";");
end