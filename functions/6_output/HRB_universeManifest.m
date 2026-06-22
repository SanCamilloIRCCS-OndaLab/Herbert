function manifest = HRB_universeManifest(outputFolder)
% HRB_universeManifest  Map every universe label to its parameter combination.
%
% Reads pipeline.json from the output folder, finds all multiverse steps
% (steps defined as JSON arrays), and enumerates all combinations via
% cartesian product. Does NOT require Brainstorm or EEGLAB.
%
% Usage:
%   manifest = HRB_universeManifest(outputFolder)
%
% Input:
%   outputFolder  - path to output/{timestamp}/ folder containing pipeline.json
%
% Output:
%   manifest  - table [nUniverses x (1 + nMultiverseSteps)]
%               - universe_label  : full label matching BST Comment
%                                   (after stripping the subjId prefix)
%               - one column per multiverse step, named after the step key
%                 with the 'step{N}_' prefix stripped
%                 (e.g. 'step2_filter' → 'filter')
%
% Example output for a 2×2×2×2 multiverse:
%   universe_label                              filter        headmodel  inverse   connectivity
%   "bandpass-1-48_openmeeg_mne-dspm_wpli-NxN" "bandpass-1-48" "openmeeg" "mne-dspm" "wpli-NxN"
%   "bandpass-1-48_openmeeg_mne-dspm_coh-NxN"  "bandpass-1-48" "openmeeg" "mne-dspm" "coh-NxN"
%  
% Authors: Ettore Napoli, University of Bologna, 2026

arguments
    outputFolder (1,1) string
end

% Load pipeline.json
jsonPath = fullfile(outputFolder, 'pipeline.json');
if ~isfile(jsonPath)
    error('HRB:FileNotFound', 'pipeline.json not found in: %s', outputFolder);
end
pipeline = jsondecode(fileread(jsonPath));
stepKeys = fieldnames(pipeline);  % Preserves JSON insertion order

% Identify multiverse steps and collect branch names 
mvKeys  = {};   % step key names, in JSON order
mvNames = {};   % cell of string row vectors, one per multiverse step

for k = 1:numel(stepKeys)
    step = pipeline.(stepKeys{k});

    if iscell(step)
        % Non-uniform JSON array
        names = cellfun(@(s) string(s.name), step, 'UniformOutput', true);
        mvKeys{end+1}  = stepKeys{k};    
        mvNames{end+1} = names(:)';      

    elseif isstruct(step) && numel(step) > 1
        % Uniform JSON array
        names = string({step.name});
        mvKeys{end+1}  = stepKeys{k};    
        mvNames{end+1} = names(:)';     
    end
    % Scalar struct → sequential step, skip
end

if isempty(mvKeys)
    warning('HRB:NoMultiverse', 'No multiverse steps found in pipeline.json.');
    manifest = table();
    return;
end

% Cartesian product of all branch name sets
% combinations: [nUniverses × nMultiverseSteps] string array
combinations = local_cartprod(mvNames{:});
nU = size(combinations, 1);

% Build universe_label: join each row with 
universeLabelCol = strings(nU, 1);
for i = 1:nU
    universeLabelCol(i) = strjoin(combinations(i, :), '_');
end

% Strip 'step{N}_' or 'step{N}[a-z]_' prefix from column names
% Examples: 'step2_filter' → 'filter', 'step12_headmodel' → 'headmodel'
colNames = regexprep(mvKeys, '^step\d+[a-z]?_', '');

% Assemble output table
varNames = [{'universe_label'}, colNames];
T_data   = [cellstr(universeLabelCol), cellstr(combinations)];
manifest = cell2table(T_data, 'VariableNames', varNames);

% Convert all columns to string type for consistent downstream use
for c = 1:width(manifest)
    manifest.(varNames{c}) = string(manifest.(varNames{c}));
end

end


%% Helper

function C = local_cartprod(varargin)
% Cartesian product of string arrays.
%
% C = local_cartprod(v1, v2, ..., vN)
%
% Returns a [prod(n_i) × N] string array.
% v1 (first input) varies slowest; vN (last input) varies fastest.
%
% Algorithm: for column k, each element repeats (repEach) times, and the
% entire block repeats (repBlock) times to fill nC rows.

n     = nargin;
sizes = cellfun(@numel, varargin);
nC    = prod(sizes);
C     = strings(nC, n);

repEach  = nC;  % shrinks by n_k at each step
repBlock = 1;   % grows by n_k at each step

for k = 1:n
    v        = varargin{k}(:)';        % enforce row vector
    repEach  = repEach / numel(v);
    col      = repmat(repelem(v, repEach), 1, repBlock)';
    C(:, k)  = col;
    repBlock = repBlock * numel(v);
end

end