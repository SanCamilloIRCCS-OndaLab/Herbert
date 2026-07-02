function HRB_generateSubjectMap(filePath, opt)
%HRB_generateSubjectMap  Scan a folder and write a subject mapping CSV.
%
%  The CSV is the single source of truth for HRB_runDataset:
%  it defines which files to process, their subject IDs, and
%  which subjects to exclude.
%
%  USAGE
%    HRB_generateSubjectMap('/path/to/data/')
%    HRB_generateSubjectMap('/path/to/data/', FilePattern="*.set")
%
%  CSV COLUMNS
%    filename    — file to load (relative to dataPath)
%    subject_id  — pre-filled with filename stem; edit as needed
%    exclude     — set to 1 to skip a subject; default 0
%
% Author: Ettore Napoli, University of Bologna, 2026

arguments
    filePath string
    opt.fileExtension string = '*.vhdr'
end

files = dir(fullfile(filePath, opt.fileExtension));

if isempty(files)
    error("HRB:NoFiles", "No files matching '%s' in: %s", opts.FilePattern, dataPath);
end

fnames     = {files.name}';

% Extract SubjID
stems      = cellfun(@(f) local_stem(f), fnames, UniformOutput=false);
excludes   = zeros(length(fnames), 1);  % all included by default

% Create Table
T = table(fnames, stems, excludes, VariableNames=["filename","subject_id","exclude"]);

outPath = fullfile(filePath, 'subject_map.csv');
writetable(T, outPath);
fprintf('Subject map written to: %s\n', outPath);
fprintf('Edit subject_id and set exclude=1 to skip subjects.\n');
end

function s = local_stem(fname)
    [~, s, ~] = fileparts(fname);
end
