function R = HRB_reorgByUniverse(runRoot, universePaths, opt)
%HRB_reorgByUniverse  Gather/reorganize a run's outputs into per-universe folders.
%
%  Consumes HRB_universePaths as the backbone (one row per universe x subject)
%  and copies each universe's files into a fresh, per-universe root, leaving
%  the original subject-first DAG untouched. Non-destructive, idempotent.
%
%  LAYOUTS (opt.Mode)
%    "terminals" (default) : flat per-universe collection. Copies the terminal
%                            <subj>_<uid>.set (+ sibling .fdt) and, if CopyQC,
%                            the QC artifacts resolved by walking the terminal's
%                            ancestors (ExcludedChannels, rejectedComps, epoch
%                            .set) into <root>/<uid>/qc/. This is what the mMSE
%                            measure actually consumes.
%    "full"                : self-contained per-universe mirror. Copies every
%                            file on the universe's ancestor chain (each fork
%                            dir + its preprocessing/ child) under
%                            <root>/<uid>/<subjFolder>/... . Shared ancestors
%                            are duplicated into each descendant universe
%                            (N-fold: badchan-level x6, flag-level x3), by
%                            design (self-contained folders).
%
%  Degenerate/failed/missing universes (status ~= "ok", no terminal on disk)
%  are NOT skipped silently: they get a row in the index with their status and
%  error_msg, so the per-universe view mirrors the run, empty cells included.
%  ("degenerate is a result, not a bug" — consistent with HRB_universePaths.)
%
%  USAGE
%    manifest = HRB_universeManifest(runRoot);
%    report   = HRB_pipelineReport(..., Format="long");
%    P        = HRB_universePaths(runRoot, manifest, report);
%    R        = HRB_reorgByUniverse(runRoot, P);                       % terminals
%    R        = HRB_reorgByUniverse(runRoot, P, Mode="full");          % mirror
%    R        = HRB_reorgByUniverse(runRoot, P, Manifest=manifest);    % + axes in index
%
%  INPUT
%    runRoot        string   timestamped run root (e.g. 'output/20260923_223524')
%    universePaths  table    output of HRB_universePaths, columns:
%                            universe_id, subject, status, path, error_msg
%
%  NAME-VALUE
%    OutputRoot   string   destination root. Default: <runRoot>_by-universe
%    Mode         string   "terminals" (default) | "full"
%    CopyQC       logical  terminals mode: also copy resolved QC (default true)
%    Overwrite    logical  false (default) = skip-if-exists (idempotent re-run)
%    Manifest     table    optional; joined into the index for readable axes
%    IndexFile    string   index CSV name under OutputRoot (default universe_index.csv)
%    QCPatterns   string   glob patterns for QC artifacts to resolve/copy
%
%  OUTPUT
%    R   table (also written to <OutputRoot>/<IndexFile>):
%          universe_id, subject, status, src_path, dest_path,
%          n_files_copied, error_msg  (+ manifest axis columns if Manifest given)
%
%  ASSUMPTIONS (verify against a real run tree before a definitive pass):
%    - EEGLAB .set datasets may carry a sibling .fdt; copied in lockstep, and
%      the .set is kept under its ORIGINAL basename so its internal .fdt
%      pointer stays valid.
%    - QC artifacts live in the terminal's ancestor directories (or a
%      'preprocessing/' child there); nearest-to-leaf match wins per pattern.
%      Naming taken from HRB_collectQC conventions; epoch file matched as both
%      '*clean-epochs.set' and '*_epoch.set' pending confirmation.
%
% Author: Ettore Napoli - University of Bologna, 2026

arguments (Input)
    runRoot        (1,1) string
    universePaths  table
    opt.OutputRoot (1,1) string  = ""
    opt.Mode       (1,1) string {mustBeMember(opt.Mode,["terminals","full"])} = "terminals"
    opt.CopyQC     (1,1) logical = true
    opt.Overwrite  (1,1) logical = false
    opt.Manifest   table         = table()
    opt.IndexFile  (1,1) string  = "universe_index.csv"
    opt.QCPatterns (1,:) string  = ["*ExcludedChannels*","*rejectedComps*","*clean-epochs.set","*_epoch.set"]
end

% --- Validate the backbone columns up front (fail loud, not silent) ---
needed  = ["universe_id","subject","status","path"];
haveCol = string(universePaths.Properties.VariableNames);
missCol = needed(~ismember(needed, haveCol));
if ~isempty(missCol)
    error("HRB:BadSpina", ...
        "universePaths missing column(s): %s. Pass the table from HRB_universePaths.", ...
        strjoin(missCol, ", "));
end
if ~ismember("error_msg", haveCol)
    universePaths.error_msg = strings(height(universePaths),1);
end

runRoot = char(runRoot);

% --- Resolve destination root (default: <runRoot>_by-universe) ---
if strlength(opt.OutputRoot) == 0
    outRoot = char(regexprep(string(runRoot), "[\\/]+$", "") + "_by-universe");
else
    outRoot = char(opt.OutputRoot);
end
if ~isfolder(outRoot), mkdir(outRoot); end

% --- Accumulators for the index ---
n       = height(universePaths);
srcCol  = strings(n,1);
destCol = strings(n,1);
nFiles  = zeros(n,1);

fprintf("[HRB_reorgByUniverse] Mode=%s | dest=%s\n", opt.Mode, outRoot);

for i = 1:n
    uid    = string(universePaths.universe_id(i));
    sid    = string(universePaths.subject(i));
    status = string(universePaths.status(i));
    rel    = string(universePaths.path(i));
    srcCol(i) = rel;

    % Non-ok universes: record the row, copy nothing (empty cell preserved).
    if status ~= "ok" || strlength(rel) == 0
        continue
    end

    srcSet = fullfile(runRoot, char(rel));
    if ~isfile(srcSet)
        % report=ok but the file vanished at copy time — reclassify, don't crash
        universePaths.status(i)    = "missing";
        universePaths.error_msg(i) = "terminal .set not found at copy time";
        continue
    end

    switch opt.Mode
        case "terminals"
            [c, dst] = local_copy_terminals(runRoot, srcSet, ...
                          fullfile(outRoot, char(uid)), opt);
        case "full"
            [c, dst] = local_copy_full(runRoot, srcSet, outRoot, uid, opt);
    end
    nFiles(i)  = c;
    destCol(i) = erase(string(dst), string(outRoot) + filesep);
end

% --- Assemble index ---
R = table( ...
    string(universePaths.universe_id), string(universePaths.subject), ...
    string(universePaths.status), srcCol, destCol, nFiles, ...
    string(universePaths.error_msg), ...
    'VariableNames', {'universe_id','subject','status','src_path', ...
                      'dest_path','n_files_copied','error_msg'});

% Optional manifest enrichment (readable axis columns via left join)
if ~isempty(opt.Manifest) && ...
        ismember("universe_label", string(opt.Manifest.Properties.VariableNames))
    M = opt.Manifest;
    M.Properties.VariableNames{strcmp(M.Properties.VariableNames,'universe_label')} = 'universe_id';
    R = outerjoin(R, M, 'Keys','universe_id', 'MergeKeys',true, 'Type','left');
end

writetable(R, fullfile(outRoot, char(opt.IndexFile)));

% --- Console summary ---
fprintf(['[HRB_reorgByUniverse] %d rows | ok %d | degenerate %d | ' ...
         'failed %d | missing %d | %d files copied\n'], ...
    height(R), sum(R.status=="ok"), sum(R.status=="degenerate"), ...
    sum(R.status=="failed"), sum(R.status=="missing"), sum(R.n_files_copied));
fprintf("[HRB_reorgByUniverse] Index -> %s\n", fullfile(outRoot, char(opt.IndexFile)));
end


%% ------------------------------------------------------------------ helpers

function [nCopied, uniDir] = local_copy_terminals(runRoot, srcSet, uniDir, opt)
% Flat collection: terminal (+ .fdt) under uniDir; resolved QC under uniDir/qc.
if ~isfolder(uniDir), mkdir(uniDir); end
nCopied = 0;

% Terminal: keep ORIGINAL basename so the .set -> .fdt pointer stays valid.
dstSet  = fullfile(uniDir, local_basename(srcSet));
nCopied = nCopied + local_copy_set(srcSet, dstSet, opt.Overwrite);

if opt.CopyQC
    subjRoot = local_subject_root(runRoot, srcSet);
    hits     = local_resolve_qc(fileparts(srcSet), subjRoot, opt.QCPatterns);
    if ~isempty(hits)
        qcDir = fullfile(uniDir, "qc");
        if ~isfolder(qcDir), mkdir(qcDir); end
        for h = 1:numel(hits)
            src = hits{h};
            dst = fullfile(qcDir, local_basename(src));
            if endsWith(src, ".set", "IgnoreCase", true)
                nCopied = nCopied + local_copy_set(src, dst, opt.Overwrite);
            else
                nCopied = nCopied + local_copy_one(src, dst, opt.Overwrite);
            end
        end
    end
end
end


function [nCopied, uniRoot] = local_copy_full(runRoot, srcSet, outRoot, uid, opt)
% Self-contained mirror: copy every file on this universe's ancestor chain
% (each fork dir + its preprocessing/ child) under <outRoot>/<uid>/.
subjRoot = local_subject_root(runRoot, srcSet);
uniRoot  = fullfile(outRoot, char(uid));
nCopied  = 0;

% Leaf fork dir = parent of the terminal's preprocessing/ folder.
leafFork = fileparts(fileparts(srcSet));
chain    = local_ancestor_chain(subjRoot, leafFork);   % root-first fork dirs

for k = 1:numel(chain)
    d = chain{k};
    % this fork dir's own files, then its preprocessing/ child (if present)
    nCopied = nCopied + local_copy_dir_files(d, subjRoot, uniRoot, opt);
    prep = fullfile(d, "preprocessing");
    if isfolder(prep)
        nCopied = nCopied + local_copy_dir_files(prep, subjRoot, uniRoot, opt);
    end
end
end


function c = local_copy_dir_files(dirPath, subjRoot, uniRoot, opt)
% Copy the (non-dir) files directly in dirPath into uniRoot, preserving the
% path RELATIVE to subjRoot. .fdt handled in lockstep with its .set (skipped
% here to avoid a double copy).
c = 0;
relDir = erase(string(dirPath), string(subjRoot) + filesep);   % "" for subjRoot
dstDir = fullfile(uniRoot, char(relDir));

f = dir(fullfile(dirPath, '*'));
f = f(~[f.isdir]);
for j = 1:numel(f)
    src = fullfile(f(j).folder, f(j).name);
    if endsWith(src, ".fdt", "IgnoreCase", true), continue; end   % via its .set
    dst = fullfile(dstDir, f(j).name);
    if endsWith(src, ".set", "IgnoreCase", true)
        c = c + local_copy_set(src, dst, opt.Overwrite);
    else
        c = c + local_copy_one(src, dst, opt.Overwrite);
    end
end
end


function hits = local_resolve_qc(startDir, subjRoot, patterns)
% From startDir (terminal's preprocessing/ folder) walk UP to subjRoot; for
% each pattern take the nearest-to-leaf match, searched in each ancestor dir
% and its preprocessing/ child.
chain = flip(local_ancestor_chain(subjRoot, startDir));   % leaf-first
hits  = {};
for p = 1:numel(patterns)
    found = '';
    for k = 1:numel(chain)
        d    = chain{k};
        cand = local_find_file(d, char(patterns(p)));
        if isempty(cand)
            cand = local_find_file(fullfile(d,'preprocessing'), char(patterns(p)));
        end
        if ~isempty(cand), found = cand; break; end
    end
    if ~isempty(found), hits{end+1} = found; end %#ok<AGROW>
end
hits = unique(hits, 'stable');
end


function chain = local_ancestor_chain(rootDir, leafDir)
% Cell array of directories from rootDir down to leafDir, inclusive, root-first.
% leafDir is expected to be under rootDir; a safety stop prevents runaway.
rootDir = char(rootDir); leafDir = char(leafDir);
chain = {}; cur = leafDir;
while true
    chain{end+1} = cur; %#ok<AGROW>
    if strcmp(cur, rootDir), break; end
    parent = fileparts(cur);
    if isempty(parent) || strcmp(parent, cur), break; end   % not under rootDir
    cur = parent;
end
chain = flip(chain);
end


function sroot = local_subject_root(runRoot, srcSet)
% Subject folder = immediate child of runRoot on the path to srcSet.
runRoot = char(runRoot);
rel     = erase(char(srcSet), [runRoot filesep]);
parts   = strsplit(rel, filesep);
sroot   = fullfile(runRoot, parts{1});
end


function c = local_copy_set(src, dst, overwrite)
% Copy a .set together with its sibling .fdt (if any), in lockstep.
c = local_copy_one(src, dst, overwrite);
srcFdt = regexprep(src, '\.set$', '.fdt', 'ignorecase');
if isfile(srcFdt)
    dstFdt = regexprep(dst, '\.set$', '.fdt', 'ignorecase');
    c = c + local_copy_one(srcFdt, dstFdt, overwrite);
end
end


function c = local_copy_one(src, dst, overwrite)
% Single-file copy with idempotent skip-if-exists.
c = 0;
if isfile(dst) && ~overwrite, return; end
d = fileparts(dst);
if ~isfolder(d), mkdir(d); end
[ok, msg] = copyfile(src, dst);
if ~ok
    warning("HRB:CopyFailed", "copy failed: %s -> %s (%s)", src, dst, msg);
    return
end
c = 1;
end


function filepath = local_find_file(folder, pattern)
% Full path of the first file matching pattern in folder, or '' if none.
d = dir(fullfile(folder, pattern));
d = d(~[d.isdir]);
if isempty(d), filepath = ''; else, filepath = fullfile(d(1).folder, d(1).name); end
end


function b = local_basename(p)
[~, nm, ext] = fileparts(char(p));
b = [nm ext];
end