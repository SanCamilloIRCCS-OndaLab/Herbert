function R = HRB_pipelineReport(results, allNames, opt)
%HRB_pipelineReport  Aggregate pipeline run results into a status table.
%
%  Reads the cell arrays returned by HRB_runDataset and produces a table
%  describing the outcome for each subject/universe combination.
%
%  USAGE
%    R = HRB_pipelineReport(results, allNames)
%    R = HRB_pipelineReport(results, allNames, Format="long")
%    R = HRB_pipelineReport(results, allNames, Format="summary")
%    R = HRB_pipelineReport(results, allNames, OutputFile="report.csv")
%
%  INPUT
%    results    cell(nSubjects,1)   output of HRB_runDataset
%    allNames   cell(nSubjects,1)   output of HRB_runDataset (second arg)
%                                   allNames{i}{j} = universe label for
%                                   results{i}{j}
%
%  OUTPUT — Format="long" (default)
%    R   table, one row per subject×universe:
%          subj_id         string   subject identifier
%          universe_label  string   e.g. 'bandpass-1-48/openmeeg/mne-dspm/wpli-NxN'
%          status          string   'ok' | 'universe_failed' | 'dataset_failed' | 'skipped'
%          step            double   HRB_step index at crash (NaN if not a failure)
%          error_msg       string   error message ('' if ok/skipped)
%
%  OUTPUT — Format="summary"
%    R   table, one row per subject:
%          subj_id          string   subject identifier
%          n_ok             double   number of completed universes
%          n_failed         double   number of failed universes
%          n_skipped        double   1 if subject was excluded, else 0
%          failed_universes string   semicolon-separated list of failed
%                                   universe labels ('' if none)
%
%  OPTIONAL NAME-VALUE
%    Format      string   'long' (default) | 'summary'
%    OutputFile  string   if non-empty, write R to this CSV path
%
% Author: Ettore Napoli - University of Bologna, 2026

arguments (Input)
    results     cell
    allNames    cell
    opt.Format     string = "long"
    opt.OutputFile string = ""
end

if ~ismember(opt.Format, ["long", "summary"])
    error("HRB:InvalidFormat", "Format must be 'long' or 'summary', got '%s'.", opt.Format);
end

nSubj = numel(results);

%% Parse results into a flat struct array 
% Each element of 'rows' represents one subject×universe event.
rows = struct( ...
    'subj_id',        {{}}, ...
    'universe_label', {{}}, ...
    'status',         {{}}, ...
    'step',           {{}}, ...
    'error_msg',      {{}});
nRows = 0;

for i = 1:nSubj
    entry = results{i};
    names = allNames{i};

    % Case 1: excluded subject 
    if isstruct(entry) && isfield(entry, 'HRB_skipped') && entry.HRB_skipped
        nRows = nRows + 1;
        rows(nRows).subj_id        = char(entry.subject);
        rows(nRows).universe_label = '';
        rows(nRows).status         = 'skipped';
        rows(nRows).step           = NaN;
        rows(nRows).error_msg      = '';
        continue
    end

    % Case 2: dataset-level failure (crash in HRB_runDataset try/catch)
    if isstruct(entry) && isfield(entry, 'HRB_failed') && entry.HRB_failed
        nRows = nRows + 1;
        rows(nRows).subj_id        = char(entry.subject);
        rows(nRows).universe_label = '';
        rows(nRows).status         = 'dataset_failed';
        rows(nRows).step           = NaN;
        rows(nRows).error_msg      = char(entry.error);
        continue
    end

    %  Case 3: HRB_runPipeline returned a cell of universe results 
    if ~iscell(entry)
        nRows = nRows + 1;
        rows(nRows).subj_id        = sprintf('subject_%d', i);
        rows(nRows).universe_label = '';
        rows(nRows).status         = 'dataset_failed';
        rows(nRows).step           = NaN;
        rows(nRows).error_msg      = sprintf('Unexpected results type: %s', class(entry));
        continue
    end

    subjId = local_extract_subjid(entry, i);
    nUniverses = numel(entry);

    for j = 1:nUniverses
        u = entry{j};

        % Universe label from allNames — fall back to index if missing
        if j <= numel(names) && ~isempty(names{j})
            uLabel = char(names{j});
        else
            uLabel = sprintf('universe_%d', j);
        end

        nRows = nRows + 1;
        rows(nRows).subj_id        = subjId;
        rows(nRows).universe_label = uLabel;

        if isstruct(u) && isfield(u, 'HRB_failed') && u.HRB_failed
            rows(nRows).status    = 'universe_failed';
            rows(nRows).step      = local_get_field(u, 'HRB_step', NaN);
            rows(nRows).error_msg = local_get_field(u, 'HRB_error', '');
        else
            rows(nRows).status    = 'ok';
            rows(nRows).step      = NaN;
            rows(nRows).error_msg = '';
        end
    end
end

%% Build output table 
if nRows == 0
    warning('[HRB_pipelineReport] No data collected — returning empty table.');
    R = local_empty_table(opt.Format);
    return
end

if opt.Format == "long"
    R = local_build_long(rows, nRows);
else
    R = local_build_summary(rows, nRows);
end

%%  Optional CSV export 
if strlength(opt.OutputFile) > 0
    writetable(R, char(opt.OutputFile));
    fprintf('[HRB_pipelineReport] Report written to %s\n', opt.OutputFile);
end

%%  Console summary 
nOk     = sum(strcmp({rows.status}, 'ok'));
nFail   = sum(strcmp({rows.status}, 'universe_failed'));
nDsFail = sum(strcmp({rows.status}, 'dataset_failed'));
nSkip   = sum(strcmp({rows.status}, 'skipped'));
fprintf('[HRB_pipelineReport] %d ok | %d universe_failed | %d dataset_failed | %d skipped\n', ...
    nOk, nFail, nDsFail, nSkip);

end

%% Helpers

function R = local_build_long(rows, nRows)
R = table( ...
    string({rows(1:nRows).subj_id})',        ...
    string({rows(1:nRows).universe_label})', ...
    string({rows(1:nRows).status})',         ...
    [rows(1:nRows).step]',                   ...
    string({rows(1:nRows).error_msg})',      ...
    'VariableNames', {'subj_id','universe_label','status','step','error_msg'});
end

function R = local_build_summary(rows, nRows)
% One row per subject — aggregate universe-level events.
allSubjs = unique({rows(1:nRows).subj_id}, 'stable');
nSubjs   = numel(allSubjs);

subj_id          = strings(nSubjs, 1);
n_ok             = zeros(nSubjs, 1);
n_failed         = zeros(nSubjs, 1);
n_skipped        = zeros(nSubjs, 1);
failed_universes = strings(nSubjs, 1);

for k = 1:nSubjs
    sid  = allSubjs{k};
    mask = strcmp({rows(1:nRows).subj_id}, sid);
    sub  = rows(mask);

    subj_id(k)   = sid;
    n_ok(k)      = sum(strcmp({sub.status}, 'ok'));
    n_failed(k)  = sum(strcmp({sub.status}, 'universe_failed')) + ...
                   sum(strcmp({sub.status}, 'dataset_failed'));
    n_skipped(k) = sum(strcmp({sub.status}, 'skipped'));

    failedLabels = {sub(strcmp({sub.status}, 'universe_failed')).universe_label};
    if ~isempty(failedLabels)
        failed_universes(k) = strjoin(failedLabels, '; ');
    end
end

R = table(subj_id, n_ok, n_failed, n_skipped, failed_universes);
end

function R = local_empty_table(fmt)
if fmt == "long"
    R = table('Size',[0 5], ...
        'VariableTypes', {'string','string','string','double','string'}, ...
        'VariableNames', {'subj_id','universe_label','status','step','error_msg'});
else
    R = table('Size',[0 5], ...
        'VariableTypes', {'string','double','double','double','string'}, ...
        'VariableNames', {'subj_id','n_ok','n_failed','n_skipped','failed_universes'});
end
end

function subjId = local_extract_subjid(universeCell, fallbackIdx)
% Extract subject ID from the first valid EEG struct in the universe cell.
subjId = sprintf('subject_%d', fallbackIdx);
for j = 1:numel(universeCell)
    u = universeCell{j};
    if isstruct(u) && isfield(u, 'subject') && ~isempty(u.subject)
        subjId = replace(char(u.subject), {'_',' '}, '-');
        return
    end
end
end

function val = local_get_field(s, fname, default)
% Safely read a field from a struct, returning default if absent.
if isfield(s, fname)
    val = s.(fname);
else
    val = default;
end
end