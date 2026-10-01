function QC = HRB_collectQC(runRoot, universePaths, manifest, opt)
%HRB_collectQC  Per-universe preprocessing QC, SPINED on HRB_universePaths.
%
%  This function does NOT discover universes from disk shape. It consumes the
%  universe×subject spine produced by HRB_universePaths (itself a join of the
%  manifest, the pipeline report, and disk). Universe existence and status come
%  from config (pipeline.json) + report — never from "a folder has no children".
%  A branch that crashed before forking its rejepochs children is a 'failed'
%  row in the report, so it can never masquerade as a valid universe here.
%  This is the property the disk-only walker could not provide.
%
%  For each universe×subject row it adds QC metrics by decoding the leaf folder
%  from the manifest axis columns, then walking UP the ancestor chain to gather
%  artefacts that live at different depths (verified against the run tree):
%    ExcludedChannels.csv  -> badChannels (chRej) ancestor       [channels]
%    *_rejectedComps.txt   -> icflag (flag) ancestor             [ICA comps]
%    *_epoch.set           -> icflag (flag) ancestor             [epochs BEFORE rejection]
%    terminal <subj>_<uid>.set -> the leaf (from universePaths.path) [epochs RETAINED]
%
%  Metrics are collected ONLY for status ok|degenerate. 'failed'/'missing' rows
%  are carried through with NaN metrics + error_msg, so a crashed universe's
%  absent artefacts are never read as a real "0".
%
%  USAGE
%    manifest = HRB_universeManifest(runRoot);
%    report   = HRB_pipelineReport(runRoot, Format="long");   % caller builds this
%    P        = HRB_universePaths(runRoot, manifest, report);
%    QC       = HRB_collectQC(runRoot, P, manifest, OutputFile="qc.csv");
%
%  INPUT
%    runRoot        string   timestamped output root (same passed to universePaths)
%    universePaths  table    output of HRB_universePaths:
%                            universe_id, subject, status, path, error_msg
%    manifest       table    output of HRB_universeManifest:
%                            universe_label + one column per multiverse axis
%
%  OUTPUT  long table, one row per universe×subject:
%    subj_id, universe, status,
%    n_channels_removed, removed_channels, n_ica_removed, removed_comps,
%    n_epochs_before, n_epochs_retained, n_epochs_rejected,
%    error_msg, notes, + one column per multiverse axis (for pivoting in R)
%
%  OPTIONAL NAME-VALUE
%    OutputFile   string   if non-empty, write QC to this CSV path
%
% Author: Ettore Napoli - University of Bologna, 2026

arguments (Input)
    runRoot        (1,1) string
    universePaths  table
    manifest       table
    opt.OutputFile (1,1) string = ""
end

runRootc = char(runRoot);

% Ordered axis columns (everything except the label) — used to rebuild the
% folder path deterministically and to append axis columns downstream.
axisCols = setdiff(manifest.Properties.VariableNames, {'universe_label'}, 'stable');
mfLabels = string(manifest.universe_label);

P  = universePaths;
nR = height(P);

subj_id            = strings(nR,1);
universe           = strings(nR,1);
statusCol          = strings(nR,1);
n_channels_removed = nan(nR,1);
removed_channels   = strings(nR,1);
n_ica_removed      = nan(nR,1);
removed_comps      = strings(nR,1);
n_epochs_before    = nan(nR,1);
n_epochs_retained  = nan(nR,1);
n_epochs_rejected  = nan(nR,1);
error_msg          = strings(nR,1);
notes              = strings(nR,1);

for i = 1:nR
    uid = string(P.universe_id(i));
    sid = string(P.subject(i));
    st  = string(P.status(i));

    subj_id(i)   = sid;
    universe(i)  = uid;
    statusCol(i) = st;
    error_msg(i) = string(P.error_msg(i));

    % --- decode leaf folder from manifest (robust to '_' inside branch names) ---
    mrow = find(mfLabels == uid, 1);
    if isempty(mrow)
        notes(i) = "universe not in manifest — cannot locate on disk";
        continue
    end
    vals      = string(manifest{mrow, axisCols});   % axis values, JSON order
    branchRel = strjoin(vals, filesep);             % e.g. notch/chRej-corr/flagloose/rejAmpLoose

    subjFolder = fullfile(runRootc, char(sid));
    if ~isfolder(subjFolder)
        alt = fullfile(runRootc, local_clean_name(char(sid)));  % underscore->hyphen fallback
        if isfolder(alt)
            subjFolder = alt;
        else
            notes(i) = "subject folder not found on disk";
            continue
        end
    end
    leafNode = fullfile(subjFolder, char(branchRel));

    % --- collect metrics only for measurable statuses ---
    switch st
        case {"ok","degenerate"}
            noteList = {};

            % channels: ExcludedChannels at the chRej ancestor
            chanFile = local_find_up(leafNode, subjFolder, '*ExcludedChannels*');
            if ~isempty(chanFile)
                [n_channels_removed(i), chNames] = local_count_csv_items(chanFile);
                removed_channels(i) = strjoin(chNames, ',');
            else
                n_channels_removed(i) = 0;
                noteList{end+1} = 'ExcludedChannels not found'; %#ok<AGROW>
            end

            % ICA comps: rejectedComps at the flag ancestor
            compFile = local_find_up(leafNode, subjFolder, '*rejectedComps*');
            if ~isempty(compFile)
                [n_ica_removed(i), icIdx] = local_count_csv_items(compFile);
                removed_comps(i) = strjoin(icIdx, ',');
            else
                n_ica_removed(i) = 0;
                noteList{end+1} = 'rejectedComps not found'; %#ok<AGROW>
            end

            % epochs before rejection: *_epoch.set at the flag ancestor
            beforeSet = local_find_up(leafNode, subjFolder, '*_epoch.set');
            n_epochs_before(i) = local_read_trials(beforeSet);
            if isnan(n_epochs_before(i))
                noteList{end+1} = 'pre-rejection epoch.set not found/unreadable'; %#ok<AGROW>
            end

            % epochs retained: terminal .set (authoritative path from the spine)
            if st == "ok"
                setPath = string(P.path(i));
                n_epochs_retained(i) = local_read_trials(fullfile(runRootc, char(setPath)));
                if isnan(n_epochs_retained(i))
                    noteList{end+1} = 'terminal .set unreadable'; %#ok<AGROW>
                end
            else   % degenerate: no terminal .set because all epochs were rejected
                n_epochs_retained(i) = 0;
            end

            n_epochs_rejected(i) = n_epochs_before(i) - n_epochs_retained(i);  % NaN-propagating
            notes(i) = strjoin(noteList, '; ');

        otherwise   % failed | missing | any other report status
            notes(i) = "status=" + st + " — metrics not collected";
    end
end

QC = table(subj_id, universe, statusCol, ...
    n_channels_removed, removed_channels, n_ica_removed, removed_comps, ...
    n_epochs_before, n_epochs_retained, n_epochs_rejected, error_msg, notes, ...
    'VariableNames', {'subj_id','universe','status', ...
    'n_channels_removed','removed_channels','n_ica_removed','removed_comps', ...
    'n_epochs_before','n_epochs_retained','n_epochs_rejected','error_msg','notes'});

% --- append multiverse axis columns from the manifest (handy for R pivots) ---
mm = manifest;
mm.Properties.VariableNames{strcmp(mm.Properties.VariableNames,'universe_label')} = 'universe';
QC = outerjoin(QC, mm, 'Keys','universe', 'MergeKeys',true, 'Type','left');
QC = sortrows(QC, {'subj_id','universe'});

% --- CSV export ---
if strlength(opt.OutputFile) > 0
    writetable(QC, char(opt.OutputFile));
    fprintf('[HRB_collectQC] QC written to %s\n', opt.OutputFile);
end

% --- console summary ---
fprintf('[HRB_collectQC] %d rows | %d ok | %d degenerate | %d failed | %d missing\n', ...
    height(QC), sum(QC.status=="ok"), sum(QC.status=="degenerate"), ...
    sum(QC.status=="failed"), sum(QC.status=="missing"));
disp(QC)

end

%% ===== Helpers =====

function f = local_find_up(leafNode, subjFolder, pattern)
% First <ancestor>/preprocessing/<pattern>, walking up from the leaf's PARENT
% to subjFolder inclusive. Nearest ancestor wins (flag before chRej before line).
f   = '';
cur = fileparts(leafNode);          % leaf's parent = flag ancestor
while true
    hit = local_find_file(fullfile(cur, 'preprocessing'), pattern);
    if ~isempty(hit), f = hit; return; end
    if strcmp(cur, subjFolder), break; end
    parent = fileparts(cur);
    if strcmp(parent, cur) || ~startsWith(cur, subjFolder), break; end
    cur = parent;
end
end

function n = local_read_trials(setFile)
% EEG.trials from a .set header via load('-mat') — does NOT touch .fdt data.
n = NaN;
if isempty(setFile) || ~isfile(setFile), return; end
try
    tmp = load('-mat', setFile);
    if isfield(tmp, 'trials')
        n = tmp.trials;
    elseif isfield(tmp, 'EEG') && isfield(tmp.EEG, 'trials')
        n = tmp.EEG.trials;
    end
catch
    % leave NaN
end
end

function [n, items] = local_count_csv_items(filepath)
% First-line comma list -> count AND identity (channel names / comp indices),
% in file order. '' and sentinel '-1' tokens are dropped.
items = string.empty(1,0);
n = 0;
fid = fopen(filepath, 'r');
if fid == -1, return; end
line = fgetl(fid);
fclose(fid);
if ~ischar(line) || isempty(strtrim(line))
    return
end
parts = strsplit(strtrim(line), ',');
parts = parts(~strcmp(strtrim(parts), '') & ~strcmp(strtrim(parts), '-1'));
items = string(strtrim(parts));
n     = numel(parts);
end

function filepath = local_find_file(folder, pattern)
d = dir(fullfile(folder, pattern));
if isempty(d)
    filepath = '';
else
    filepath = fullfile(d(1).folder, d(1).name);
end
end

function name = local_clean_name(name)
% Mirror of HRB_runPipeline cleanName: spaces and underscores become hyphens.
name = replace(name, {' ', '_'}, '-');
end