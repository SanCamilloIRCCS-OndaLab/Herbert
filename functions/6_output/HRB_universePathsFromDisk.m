function P = HRB_universePathsFromDisk(runRoot, manifest, opt)
%HRB_universePathsFromDisk  Rebuild the universe x subject spina from DISK.
%
%  Drop-in alternative to HRB_universePaths for when the in-memory `results`
%  (and therefore the long report) is incomplete — e.g. a run that crashed and
%  was restarted mid-way. Disk is the ground truth.
%
%  Aligned to the VERIFIED on-disk layout (M01 tree, June 2026):
%    <subjFolder>/<line>/<badchan>/<flag>/<rejepochs>/preprocessing/
%        <subjFolder>_<uid>.set                       (terminal)
%    <subjFolder>/<line>/<badchan>/<flag>/preprocessing/
%        <subjFolder>_<line>_<badchan>_<flag>_epoch.set   (epoch marker)
%  where uid == manifest.universe_label == <line>_<badchan>_<flag>_<rejepochs>,
%  and subjFolder is the cleanName of EEG.subject ('_'/' ' -> '-').
%  (No .fdt on disk: datasets are single-file .set.)
%
%  STATUS (from disk topology; overridden by opt.Report where it covers a cell)
%    "ok"        terminal .set present (path filled)
%    "degenerate" no terminal, but the flag-level *_epoch.set IS present:
%                reached epoching, produced no terminal => epochs rejected.
%                TOPOLOGICAL inference — cannot on its own separate a genuine
%                degenerate from a crash IN the rejepochs step; the per-node
%                HRB_preprocessing.log disambiguates. error_msg flags this.
%    "failed"    no terminal AND no epoch file: died upstream / incomplete
%    (report labels, when supplied, replace these with the exact recorded one)
%
%  USAGE
%    manifest = HRB_universeManifest(runRoot);
%    P = HRB_universePathsFromDisk(runRoot, manifest);                 % all subjects on disk
%    P = HRB_universePathsFromDisk(runRoot, manifest, Subjects=["M09_resting", ...]);
%    P = HRB_universePathsFromDisk(runRoot, manifest, Report=report9N);% layer 9..N labels
%    R = HRB_reorgByUniverse(runRoot, P);                              % feed the reorg
%
%  INPUT
%    runRoot   string   timestamped run root
%    manifest  table    HRB_universeManifest output (universe_label column)
%
%  NAME-VALUE
%    Subjects     string   subject ids to account for (raw EEG.subject form or
%                          clean folder form — both accepted). Empty (default)
%                          => discover every subject folder under runRoot.
%    Report       table    optional long report to layer exact labels; needs
%                          subj_id, status, error_msg and universe_id|label
%    EmptyPattern string   substring in report error_msg flagging a degenerate
%                          empty dataset (default "empty") — matches HRB_universePaths
%    OutputFile   string   if non-empty, write P to this CSV
%
%  OUTPUT  long table, SAME schema as HRB_universePaths (drop-in downstream):
%    universe_id, subject, status, path, error_msg
%    (subject reported as the clean folder name, e.g. "M01-resting")
%
% Author: Ettore Napoli - University of Bologna, 2026

arguments (Input)
    runRoot          (1,1) string
    manifest         table
    opt.Subjects     (1,:) string  = strings(1,0)
    opt.Report       table         = table()
    opt.EmptyPattern (1,1) string   = "empty"
    opt.OutputFile   (1,1) string   = ""
end

runRootC = char(runRoot);
uids     = string(manifest.universe_label);

% --- Subject folders: discover from disk, or clean the supplied list ---
if isempty(opt.Subjects)
    d     = dir(runRootC);
    d     = d([d.isdir] & ~startsWith({d.name}, '.'));
    names = string({d.name});
    subjFolders = names(~ismember(names, "shared"));    % subject dirs only
else
    subjFolders = replace(opt.Subjects, ["_"," "], "-"); % raw -> folder convention
end
subjFolders = subjFolders(:)';
if isempty(subjFolders)
    error("HRB:NoSubjects", "No subject folders found under %s.", runRootC);
end

% --- Optional report: normalize join keys (universe_id + cleaned subject) ---
haveRep = ~isempty(opt.Report);
if haveRep
    rep     = opt.Report;
    rv      = string(rep.Properties.VariableNames);
    if ~ismember("universe_id", rv) && ismember("universe_label", rv)
        rep.universe_id = replace(string(rep.universe_label), "/", "_");
    end
    haveRep = all(ismember(["subj_id","status","error_msg","universe_id"], ...
                           string(rep.Properties.VariableNames)));
    if haveRep
        rep.subj_clean = replace(string(rep.subj_id), ["_"," "], "-");
    else
        warning("HRB:ReportIgnored", "opt.Report lacks required columns — disk only.");
    end
end

% --- Scan ---
nRows       = numel(uids) * numel(subjFolders);
universe_id = strings(nRows,1);
subject     = strings(nRows,1);
status      = strings(nRows,1);
relpath     = strings(nRows,1);
error_msg   = strings(nRows,1);

r = 0;
for s = 1:numel(subjFolders)
    subjF   = subjFolders(s);
    subjDir = fullfile(runRootC, char(subjF));

    % One walk per subject: index every .set once (fast, avoids 36x globbing).
    allSet     = dir(fullfile(subjDir, "**", "*.set"));
    setNames   = string({allSet.name});
    setFolders = string({allSet.folder});

    for u = 1:numel(uids)
        uid = uids(u);
        r   = r + 1;
        universe_id(r) = uid;
        subject(r)     = subjF;

        % Terminal: <subjF>_<uid>.set
        termName = subjF + "_" + uid + ".set";
        idxT     = find(setNames == termName, 1);

        if ~isempty(idxT)
            status(r)  = "ok";
            relpath(r) = erase(fullfile(setFolders(idxT), termName), ...
                               string(runRootC) + filesep);
            error_msg(r) = "";
        else
            % Epoch marker at flag level: <subjF>_<uid minus rejepochs>_epoch.set
            flagPref  = regexprep(uid, "_[^_]+$", "");   % drop trailing _<rejepochs>
            epochName = subjF + "_" + flagPref + "_epoch.set";
            if any(setNames == epochName)
                status(r)    = "degenerate";
                error_msg(r) = "topological: epoched, no terminal " + ...
                               "(verify vs HRB_preprocessing.log: degenerate vs rejepochs crash)";
            else
                status(r)    = "failed";
                error_msg(r) = "topological: no epoch file — failed/incomplete upstream";
            end
            relpath(r) = "";
        end

        % Layer exact report label where available (disk 'ok' always wins).
        if haveRep && status(r) ~= "ok"
            m = rep.subj_clean == subjF & rep.universe_id == uid;
            if any(m)
                row  = rep(find(m,1), :);
                emsg = string(row.error_msg);
                switch string(row.status)
                    case "ok"
                        status(r)    = "missing";
                        error_msg(r) = "report=ok but .set not found on disk";
                    case "universe_failed"
                        if contains(emsg, opt.EmptyPattern, IgnoreCase=true)
                            status(r) = "degenerate";
                        else
                            status(r) = "failed";
                        end
                        error_msg(r) = emsg;
                    otherwise
                        status(r)    = string(row.status);
                        error_msg(r) = emsg;
                end
            end
        end
    end
end

P = table(universe_id, subject, status, relpath, error_msg, ...
    'VariableNames', {'universe_id','subject','status','path','error_msg'});

% --- Console summary ---
fprintf(['[HRB_universePathsFromDisk] %d subjects x %d universes = %d rows\n' ...
         '  ok %d | degenerate %d | failed %d | missing %d\n'], ...
    numel(subjFolders), numel(uids), height(P), ...
    sum(P.status=="ok"), sum(P.status=="degenerate"), ...
    sum(P.status=="failed"), sum(P.status=="missing"));

if strlength(opt.OutputFile) > 0
    writetable(P, char(opt.OutputFile));
    fprintf("[HRB_universePathsFromDisk] Written to %s\n", opt.OutputFile);
end
end