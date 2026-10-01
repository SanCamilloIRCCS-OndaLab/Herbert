function P = HRB_universePaths(runRoot, manifest, report, opt)
%HRB_universePaths  Map every universe×subject to its terminal .set and status.
%
%  Joins three sources into one long table for downstream stages (e.g. mMSE):
%    - manifest : HRB_universeManifest(runRoot) — the 36 expected universes
%    - report   : HRB_pipelineReport(...,Format="long") — per subject×universe outcome
%    - disk      : the actual terminal .set files under runRoot
%
%  STATUS (three values, distinct on purpose):
%    "ok"          report=ok  AND terminal .set exists on disk
%    "degenerate"  report=universe_failed with an empty-dataset error
%                  (all epochs rejected / no epochs) — a RESULT, not a bug;
%                  an empty cell in the universe×subject matrix, expected
%    "failed"      report=universe_failed with any other error — a real crash
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
    opt.EmptyPattern (1,1) string = "empty"   % substring flagging a degenerate empty-dataset error
end

% --- Normalize report labels: branchName "/" -> prevNameFlat "_" ---
rep = report;
rep.universe_id = replace(rep.universe_label, "/", "_");

% --- Iterate expected universes × subjects present in the report ---
subjects = unique(rep.subj_id, "stable");
uids     = manifest.universe_label;                 % already underscore form

nRows = numel(uids) * numel(subjects);
universe_id = strings(nRows,1);
subject     = strings(nRows,1);
status      = strings(nRows,1);
relpath     = strings(nRows,1);
error_msg   = strings(nRows,1);

r = 0;
for u = 1:numel(uids)
    uid = uids(u);
    for s = 1:numel(subjects)
        sid = subjects(s);
        r = r + 1;
        universe_id(r) = uid;
        subject(r)     = sid;

        % report row for this (subject, universe)
        mask = rep.subj_id == sid & rep.universe_id == uid;

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
            % locate the terminal .set on disk: <subj>_<uid>.set
            fname = sid + "_" + uid + ".set";
            hit   = dir(fullfile(runRoot, "**", fname));
            if isempty(hit)
                status(r)    = "missing";
                error_msg(r) = "report=ok but .set not found";
                relpath(r)   = "";
            else
                status(r)  = "ok";
                relpath(r) = erase(string(fullfile(hit(1).folder, hit(1).name)), ...
                                   runRoot + filesep);
            end

        elseif row.status == "universe_failed"
            if contains(emsg, opt.EmptyPattern, IgnoreCase=true)
                status(r) = "degenerate";       % empty dataset → legitimate result
            else
                status(r) = "failed";           % real crash
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