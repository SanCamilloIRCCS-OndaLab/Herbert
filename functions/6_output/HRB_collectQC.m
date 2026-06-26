function QC = HRB_collectQC(outputFolder, subjectList, opt)
%HRB_collectQC  Collect preprocessing QC metrics for each subject/branch.
%
%  Reads three file types produced by the preprocessing steps:
%    *_ExcludedChannels.csv   — channels removed by HRB_removeChannels/cleanData
%    *_rejectedComps.txt      — ICA components removed by HRB_icflag/subcomp
%    *_clean-epochs.set       — final epoched data (trials field = epoch count)
%
%  All files are expected in:
%    <outputFolder>/<subjId>/<filterBranch>/preprocessing/
%
%  USAGE
%    QC = HRB_collectQC(outputFolder, subjectList)
%    QC = HRB_collectQC(outputFolder, subjectList, OutputFile="qc.csv")
%
%  INPUT
%    outputFolder   string   timestamped output root (e.g. 'output/20260622_091632')
%    subjectList    string   vector of subject IDs as stored in EEG.subject
%                            (e.g. ["Y01_resting","Y02_resting"])
%                            Note: folder names use cleanName convention
%                            (underscores → hyphens), this function handles
%                            the conversion internally.
%
%  OUTPUT
%    QC   table with columns:
%           subj_id              string   subject identifier (raw, with underscores)
%           filter_branch        string   e.g. 'bandpass-1-48'
%           n_channels_removed   double   channels in ExcludedChannels file (0 if missing)
%           n_epochs_retained    double   EEG.trials from clean-epochs.set (NaN if missing)
%           n_ica_removed        double   ICA components removed (0 if missing)
%           notes                string   warnings / missing file flags
%
%  OPTIONAL NAME-VALUE
%    OutputFile   string   if non-empty, write QC to this CSV path
%
%  FILE FORMAT ASSUMPTIONS
%    ExcludedChannels.csv : row 1 = comma-separated channel names; subsequent
%                           rows contain -1 (artefact of HRB_removeChannels
%                           logger) — ignored.
%    rejectedComps.txt    : row 1 = comma-separated integer component indices;
%                           subsequent rows contain -1 — ignored.
%    clean-epochs.set     : EEGLAB .set saved as top-level struct; field
%                           'trials' is directly accessible via load('-mat').
%                           Data array is NOT loaded (avoids reading .fdt).
%
% Author: Ettore Napoli - University of Bologna, 2026

arguments (Input)
    outputFolder  string
    subjectList   string
    opt.OutputFile  string = ""
end

outputFolder = char(outputFolder);

%% Discover filter branches from folder structure
% A filter branch is any direct subfolder of <outputFolder>/<subjId>/
% that is NOT 'shared' — shared/ contains pre-multiverse steps.

rows = {};  % accumulate as cell of structs, convert to table at end

for iSubj = 1:numel(subjectList)
    rawId   = char(subjectList(iSubj));
    folderId = local_clean_name(rawId);   % Y01_resting → Y01-resting

    subjFolder = fullfile(outputFolder, folderId);
    if ~isfolder(subjFolder)
        warning('[HRB_collectQC] Folder not found for subject %s: %s', rawId, subjFolder);
        continue
    end

    % List immediate subfolders,  each is a filter branch (or 'shared')
    entries = dir(subjFolder);
    branches = {entries([entries.isdir] & ~startsWith({entries.name}, '.')).name};
    branches = branches(~strcmp(branches, 'shared'));

    if isempty(branches)
        warning('[HRB_collectQC] No filter branches found for subject %s', rawId);
        continue
    end

    for iBranch = 1:numel(branches)
        branch       = branches{iBranch};
        branchFolder = fullfile(subjFolder, branch);

        % Find all preprocessing/ folders recursively under this branch
        prepFolders = local_find_prep_folders(branchFolder);

        if isempty(prepFolders)
            r.subj_id            = rawId;
            r.filter_branch      = branch;
            r.n_channels_removed = 0;
            r.n_epochs_retained  = NaN;
            r.n_ica_removed      = 0;
            r.notes              = 'preprocessing folder missing';
            rows{end+1}          = r; %#ok<AGROW>
            continue
        end

        for iPrep = 1:numel(prepFolders)
            prepFolder = prepFolders{iPrep};

            % Build branch label from relative path
            relPath     = strrep(prepFolder, [subjFolder filesep], '');
            relPath     = strrep(relPath, [filesep 'preprocessing'], '');
            branchLabel = strrep(relPath, filesep, '/');

            r.subj_id            = rawId;
            r.filter_branch      = branchLabel;
            r.n_channels_removed = 0;
            r.n_epochs_retained  = NaN;
            r.n_ica_removed      = 0;
            r.notes              = '';

            notesList = {};

            % Skip preprocessing/ folders that contain none of the QC files
            hasQC = ~isempty(local_find_file(prepFolder, '*ExcludedChannels*')) || ...
                ~isempty(local_find_file(prepFolder, '*rejectedComps*'))    || ...
                ~isempty(local_find_file(prepFolder, '*clean-epochs.set'));
            if ~hasQC
                continue
            end

            % 1. Excluded channels
            chanFile = local_find_file(prepFolder, '*ExcludedChannels*');
            if ~isempty(chanFile)
                r.n_channels_removed = local_count_csv_items(chanFile);
            else
                notesList{end+1} = 'ExcludedChannels file missing';
            end

            % 2. Rejected ICA components
            compFile = local_find_file(prepFolder, '*rejectedComps*');
            if ~isempty(compFile)
                r.n_ica_removed = local_count_csv_items(compFile);
            else
                notesList{end+1} = 'rejectedComps file missing';
            end

            % 3. Epoch count from clean-epochs.set
            epochFile = local_find_file(prepFolder, '*clean-epochs.set');
            if ~isempty(epochFile)
                try
                    tmp = load('-mat', epochFile);
                    if isfield(tmp, 'trials')
                        r.n_epochs_retained = tmp.trials;
                    elseif isfield(tmp, 'EEG') && isfield(tmp.EEG, 'trials')
                        r.n_epochs_retained = tmp.EEG.trials;
                    else
                        notesList{end+1} = 'trials field not found in .set';
                    end
                catch ME
                    notesList{end+1} = sprintf('failed to read .set: %s', ME.message);
                end
            else
                notesList{end+1} = 'clean-epochs.set missing';
            end

            r.notes     = strjoin(notesList, '; ');
            rows{end+1} = r; %#ok<AGROW>
        end
    end
end

%%  Build output table
if isempty(rows)
    warning('[HRB_collectQC] No data collected — returning empty table.');
    QC = table('Size', [0 6], ...
        'VariableTypes', {'string','string','double','double','double','string'}, ...
        'VariableNames', {'subj_id','filter_branch','n_channels_removed', ...
        'n_epochs_retained','n_ica_removed','notes'});
    return
end

subj_id            = string(cellfun(@(r) r.subj_id,            rows, 'UniformOutput', false))';
filter_branch      = string(cellfun(@(r) r.filter_branch,      rows, 'UniformOutput', false))';
n_channels_removed = cellfun(@(r) r.n_channels_removed, rows)';
n_epochs_retained  = cellfun(@(r) r.n_epochs_retained,  rows)';
n_ica_removed      = cellfun(@(r) r.n_ica_removed,      rows)';
notes              = string(cellfun(@(r) r.notes,        rows, 'UniformOutput', false))';

QC = table(subj_id, filter_branch, n_channels_removed, ...
    n_epochs_retained, n_ica_removed, notes);

%%  Optional CSV export
if strlength(opt.OutputFile) > 0
    writetable(QC, char(opt.OutputFile));
    fprintf('[HRB_collectQC] QC table written to %s\n', opt.OutputFile);
end

%%  Console summary
fprintf('[HRB_collectQC] %d rows collected (%d subjects × branches)\n', height(QC), height(QC));
disp(QC)

end

%% Helpers
function n = local_count_csv_items(filepath)
%local_count_csv_items  Count comma-separated items on the first line only.
%
%  Both ExcludedChannels.csv and rejectedComps.txt store their payload on
%  line 1 as a comma-separated list.  Subsequent lines contain -1 (logger
%  artefact) and are ignored.
%
%  Returns 0 for an empty first line.

n = 0;
fid = fopen(filepath, 'r');
if fid == -1, return; end
line = fgetl(fid);
fclose(fid);

if ~ischar(line) || isempty(strtrim(line))
    return
end

parts = strsplit(strtrim(line), ',');
% Filter out empty tokens and sentinel -1 entries
parts = parts(~strcmp(strtrim(parts), '') & ~strcmp(strtrim(parts), '-1'));
n = numel(parts);
end

function filepath = local_find_file(folder, pattern)
%local_find_file  Return full path of first file matching pattern, or ''.

d = dir(fullfile(folder, pattern));
if isempty(d)
    filepath = '';
else
    filepath = fullfile(d(1).folder, d(1).name);
end
end


% Mirror of HRB_runPipeline cleanName: spaces and underscores become hyphens.
function name = local_clean_name(name)
name = replace(name, {' ', '_'}, '-');
end
function prepFolders = local_find_prep_folders(branchFolder)
% Recursively find all preprocessing/ subfolders under branchFolder.
% Does NOT stop at the first match — collects all occurrences at any depth.
prepFolders = {};
d = dir(branchFolder);
subs = {d([d.isdir] & ~startsWith({d.name}, '.')).name};
for k = 1:numel(subs)
    if strcmp(subs{k}, 'preprocessing')
        % Found a preprocessing/ — add it but don't recurse into it
        prepFolders{end+1} = fullfile(branchFolder, 'preprocessing'); 
    else
        % Recurse into other subfolders
        nested = local_find_prep_folders(fullfile(branchFolder, subs{k}));
        prepFolders = [prepFolders, nested]; 
    end
end
end