function P = HRB_universePaths(runRoot, manifest, report, opt)
%HRB_universePaths  Map every universe×subject to its terminal .set and status.
%
%  Joins three sources into one long table for downstream stages (e.g. mMSE):
%    - manifest : HRB_universeManifest(runRoot) — the 36 expected universes
%    - report   : HRB_pipelineReport(...,Format="long") — per subject×universe outcome
%    - disk      : the actual terminal .set files under runRoot
%
%  STATUS (four values, distinct on purpose):
%    "ok"          report=ok  AND terminal .set exists on disk
%    "degenerate"  report=universe_failed with an error id in DegenerateIds
%                  (default HRB:AllEpochsRejected) or, when error_id is absent
%                  or empty, a message containing EmptyPattern a RESULT, not
%                  a bug; an empty cell in the universe×subject matrix, expected
%    "failed"      report=universe_failed with any other error a real crash
%    "missing"     report=ok but the .set is not on disk (should not happen;
%                  flags a save/report inconsistency worth investigating)
%
%  USAGE
%    P = HRB_universePaths(runRoot, manifest, report)
%    P = HRB_universePaths(runRoot, manifest, report, OutputFile="universe_paths.csv")
%
%  OUTPUT  long table:
%    universe_id  string   prevNameFlat (underscore form, matches filenames)
%    subject      string   subject id (as in report / EEG.subject)
%    status       string   ok | degenerate | failed | missing
%    path         string   terminal .set path RELATIVE to runRoot ("" if none)
%    error_msg    string   passthrough from report ("" if ok)
%
% Author: Ettore Napoli — University of Bologna, 2026

arguments
    runRoot          (1,1) string
    manifest         table
    report           table
    opt.OutputFile   (1,1) string = ""
    opt.EmptyPattern (1,1) string = "empty"   % fallback: substring flagging a degenerate empty-dataset error
    opt.DegenerateIds (1,:) string = "HRB:AllEpochsRejected" % error identifiers of degenerate results
end

% --- Normalize report labels: branchName "/" -> prevNameFlat "_" ---
rep = report;
rep.universe_id = replace(rep.universe_label, "/", "_");

% --- Iterate expected universes × subjects present in the report ---
subjects = unique(rep.subj_id, "stable");
uids     = manifest.universe_label;                 % full label = terminal file / BST Comment form
% Report rows carry the branch name (multiverse names only); the manifest label
% also carries the name of a final single-universe step (B3). Join the report on
% the branch part, look up files with the full label.
axisCols = setdiff(manifest.Properties.VariableNames, {'universe_label'}, 'stable');
mfBranch = strings(numel(uids), 1);
for u = 1:numel(uids)
    mfBranch(u) = strjoin(string(manifest{u, axisCols}), "_");
end

nRows = numel(uids) * numel(subjects);
universe_id = strings(nRows,1);
subject     = strings(nRows,1);
status      = strings(nRows,1);
relpath     = strings(nRows,1);
error_msg   = strings(nRows,1);

r = 0;
setIndex = containers.Map('KeyType', 'char', 'ValueType', 'any'); % one recursive dir per subj
for u = 1:numel(uids)
    uid = uids(u);
    for s = 1:numel(subjects)
        sid = subjects(s);
        r = r + 1;
        universe_id(r) = uid;
        subject(r)     = sid;

        % report row for this (subject, universe)
        mask = rep.subj_id == sid & rep.universe_id == mfBranch(u);   % report = branch name
        if ~any(mask)
            % universe not in report for this subject — shouldn't happen if
            % manifest and report come from the same run; flag it
            status(r)    = "missing";
            error_msg(r) = "not in report";
            relpath(r)   = "";
            continue
        end

        row = rep(find(mask,1), :);
        emsg = string(row.error_msg);

        if row.status == "ok"
            % locate the terminal .set: <subj>_<uid>.set, indexed once per subject
            fname = sid + "_" + uid + ".set";
            if ~isKey(setIndex, char(sid))
                d = dir(fullfile(runRoot, sid, "**", "*.set"));
                setIndex(char(sid)) = struct('name', {string({d.name})}, 'folder', {string({d.folder})});
            end
            idxS = setIndex(char(sid));
            k = find(idxS.name == fname, 1);
            if isempty(k)
                status(r) = "missing";
                error_msg(r) = "report=ok but .set not found";
                relpath(r) = "";
            else
                status(r) = "ok";
                relpath(r) = erase(fullfile(idxS.folder(k), fname), runRoot + filesep);
            end

        elseif row.status == "universe_failed"
            isDegen = contains(emsg, opt.EmptyPattern, IgnoreCase=true);
            if ismember("error_id", string(rep.Properties.VariableNames)) && strlength(string(row.error_id))>0
                isDegen = ismember(string(row.error_id), opt.DegenerateIds); %Identifier
            end
            if isDegen
                status(r) = "degenerate"; % empty dataset is a legitimate result
            else
                status(r) = "failed"; % real crash
            end
            
            error_msg(r) = emsg;
            relpath(r)   = "";

        else
            % dataset_failed / skipped — carry through
            status(r)    = row.status;
            error_msg(r) = emsg;
            relpath(r)   = "";
        end
    end
end

P = table(universe_id, subject, status, relpath, error_msg, ...
    'VariableNames', {'universe_id','subject','status','path','error_msg'});

% --- Console summary ---
fprintf('[HRB_universePaths] %d ok | %d degenerate | %d failed | %d missing (of %d)\n', ...
    sum(P.status=="ok"), sum(P.status=="degenerate"), ...
    sum(P.status=="failed"), sum(P.status=="missing"), height(P));

if strlength(opt.OutputFile) > 0
    writetable(P, char(opt.OutputFile));
    fprintf('[HRB_universePaths] Written to %s\n', opt.OutputFile);
end
end