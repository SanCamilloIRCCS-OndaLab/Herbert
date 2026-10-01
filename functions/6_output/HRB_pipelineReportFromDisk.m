function R = HRB_pipelineReportFromDisk(runRoot, manifest, opt)
%HRB_pipelineReportFromDisk  Reconstruct HRB_pipelineReport(Format="long") from DISK.
%
%  For when the in-memory `results` was lost (e.g. a MATLAB segfault) but the
%  run's output tree and per-node HRB_preprocessing.log files survive. Produces
%  the SAME long schema as HRB_pipelineReport, so it feeds HRB_universePaths
%  unchanged:
%      rep = HRB_pipelineReportFromDisk(runRoot, manifest);
%      P   = HRB_universePaths(runRoot, manifest, rep);
%      R   = HRB_reorgByUniverse(runRoot, P);
%
%  CLASSIFICATION (per subject x universe)
%    terminal <subjFolder>_<uid>.set present -> "ok".
%    otherwise: WALK THE BRANCH leaf->root (rejepochs, flag, badchan, line,
%    shared), read each HRB_preprocessing.log, and take the DEEPEST one that
%    carries a failure signature. This catches degeneration at ANY step, not
%    just rejepochs: if a universe empties at badChannels/ICA/epoch, the
%    rejepochs/flag folders never exist, so the walk falls back to the log of
%    the step that actually failed.
%      - degenerate signature ("degenerate universe" / "empty dataset" /
%        "0 retained" / "no data" / "All N epochs rejected") -> "universe_failed"
%        with an error_msg containing "empty" so HRB_universePaths derives
%        "degenerate". For rejepochs the message is reconstructed IDENTICAL to
%        the thrown error (VERIFIED, HRB_rejepochs L190). failed_step_fn names
%        the culprit step.
%      - any other [ERROR] line -> "universe_failed" (real crash), error_msg =
%        logged text (no "empty" -> HRB_universePaths -> "failed").
%      - no signature on the whole branch -> "universe_failed", incomplete
%        upstream (also what a still-running subject looks like).
%
%  HONESTY / LIMITS
%    - Only the rejepochs degenerate signature is VERIFIED from source. Other
%      steps' emptying messages are matched on a best-effort phrase set; a
%      degenerate whose log lacks a known phrase but throws an [ERROR] is
%      labelled "failed" (visible, with failed_step_fn) rather than silently
%      mislabelled. For exact non-rejepochs degenerate wording, supply those
%      steps' sources and the phrase set can be tightened.
%    - A degenerate detected by phrase whose message lacks "empty" gets a
%      normalizing marker appended so downstream derivation stays consistent.
%    - "skipped"/"dataset_failed" and the numeric `step` index are in-memory
%      only: not recoverable. `step` is NaN; failed_step_fn carries the step.
%
%  INPUT
%    runRoot   string   timestamped run root
%    manifest  table    HRB_universeManifest output (universe_label + axis cols
%                       in DAG/folder-nesting order)
%
%  NAME-VALUE
%    Subjects    string   subjects to account for (raw or clean); empty => discover
%    OutputFile  string   if non-empty, write R to this CSV
%
%  OUTPUT  long table (HRB_pipelineReport schema + two extras):
%    subj_id, universe_label(slash), status, step(NaN), error_msg,
%    universe_id(underscore)[extra], failed_step_fn[extra]
%
% Author: Ettore Napoli - University of Bologna, 2026

arguments (Input)
    runRoot        (1,1) string
    manifest       table
    opt.Subjects   (1,:) string = strings(1,0)
    opt.OutputFile (1,1) string  = ""
end

runRootC = char(runRoot);

% --- Axis columns (order == folder nesting == JSON order) ---
axisCols = string(manifest.Properties.VariableNames);
axisCols = cellstr(axisCols(axisCols ~= "universe_label"));
uidU     = string(manifest.universe_label);
nU       = height(manifest);
uidS     = strings(nU,1);
axisVals = cell(nU,1);
for u = 1:nU
    vals        = string(manifest{u, axisCols});
    axisVals{u} = cellstr(vals);
    uidS(u)     = strjoin(vals, "/");
end

% --- Subjects: discover or clean ---
if isempty(opt.Subjects)
    d = dir(runRootC);
    d = d([d.isdir] & ~startsWith({d.name}, '.'));
    subjFolders = string({d.name});
    subjFolders = subjFolders(subjFolders ~= "shared");
else
    subjFolders = replace(opt.Subjects, ["_"," "], "-");
end
subjFolders = subjFolders(:)';
if isempty(subjFolders)
    error("HRB:NoSubjects", "No subject folders found under %s.", runRootC);
end

% --- Scan ---
nRows          = numel(subjFolders) * nU;
subj_id        = strings(nRows,1);
universe_label = strings(nRows,1);
status         = strings(nRows,1);
stepCol        = nan(nRows,1);
error_msg      = strings(nRows,1);
universe_id    = strings(nRows,1);
failed_step_fn = strings(nRows,1);

r = 0;
for s = 1:numel(subjFolders)
    subjF   = subjFolders(s);
    subjDir = fullfile(runRootC, char(subjF));
    allSet   = dir(fullfile(subjDir, "**", "*.set"));
    setNames = string({allSet.name});

    for u = 1:nU
        r = r + 1;
        subj_id(r)        = subjF;
        universe_label(r) = uidS(u);
        universe_id(r)    = uidU(u);

        if any(setNames == subjF + "_" + uidU(u) + ".set")
            status(r) = "ok";  error_msg(r) = "";
            continue
        end

        % Candidate logs on this universe's branch, DEEPEST first, + shared.
        av  = axisVals{u};
        nAx = numel(av);
        logPaths = cell(1, nAx + 1);
        for k = nAx:-1:1
            parts = [{runRootC}, {char(subjF)}, av(1:k), {'preprocessing','HRB_preprocessing.log'}];
            logPaths{nAx - k + 1} = fullfile(parts{:});
        end
        logPaths{end} = fullfile(runRootC, char(subjF), 'shared', 'preprocessing', 'HRB_preprocessing.log');

        [status(r), error_msg(r), failed_step_fn(r)] = local_classify(logPaths);
    end
end

R = table(subj_id, universe_label, status, stepCol, error_msg, universe_id, failed_step_fn, ...
    'VariableNames', {'subj_id','universe_label','status','step','error_msg', ...
                      'universe_id','failed_step_fn'});

fprintf(['[HRB_pipelineReportFromDisk] %d subjects x %d universes = %d rows\n' ...
         '  ok %d | universe_failed %d  (of which degenerate ~%d)\n'], ...
    numel(subjFolders), nU, height(R), ...
    sum(R.status=="ok"), sum(R.status=="universe_failed"), ...
    sum(contains(R.error_msg, "empty", "IgnoreCase", true)));

if strlength(opt.OutputFile) > 0
    writetable(R, char(opt.OutputFile));
    fprintf("[HRB_pipelineReportFromDisk] Written to %s\n", opt.OutputFile);
end
end


%% ------------------------------------------------------------------ helpers
function [status, emsg, stepfn] = local_classify(logPaths)
% Walk candidate logs (deepest first); first with a signature wins.
status = "universe_failed";  emsg = "";  stepfn = "";

degPat = ['[^\n]*(degenerate universe|empty dataset|0 retained|' ...
          'no data retained|all\s+\d+\s+epochs rejected)[^\n]*'];

for i = 1:numel(logPaths)
    lf = logPaths{i};
    if ~isfile(lf), continue; end
    txt = fileread(lf);

    % (a) degenerate at ANY step
    degLine = regexp(txt, degPat, 'match', 'once', 'ignorecase');
    if ~isempty(degLine)
        stepfn = local_fn_of(degLine);
        tok = regexp(txt, 'All\s+(\d+)\s+epochs rejected', 'tokens', 'once', 'ignorecase');
        if ~isempty(tok)   % rejepochs: reconstruct the exact thrown message
            emsg = "All " + string(tok{1}) + ...
                   " epochs rejected: degenerate universe, empty dataset, no data retained.";
        else               % other step: keep logged text, ensure "empty" for downstream
            emsg = local_msg_of(degLine);
            if ~contains(emsg, "empty", "IgnoreCase", true)
                emsg = emsg + " (empty dataset: degenerate universe)";
            end
        end
        return
    end

    % (b) real crash
    errLine = regexp(txt, '[^\n]*\[ERROR[^\n]*', 'match', 'once');
    if ~isempty(errLine)
        emsg   = local_msg_of(errLine);
        stepfn = local_fn_of(errLine);
        return
    end
end

emsg = "no degenerate/error signature on branch — incomplete upstream (subject may still be running)";
end

function fn = local_fn_of(line)
fn = "";
t  = regexp(string(line), '\[([A-Za-z_]\w*)\.m\]', 'tokens', 'once');
if ~isempty(t), fn = string(t{1}); end
end

function m = local_msg_of(line)
line = string(line);
if contains(line, " : "), m = strtrim(extractAfter(line, " : ")); else, m = strtrim(line); end
end