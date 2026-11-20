% HRB_RUNPIPELINE - Run a multiverse pipeline over one dataset.
%
% Usage:
%     >> [data, names] = HRB_runPipeline(EEG, "pipeline.json")
%     >> [data, names] = HRB_runPipeline(EEG, "p1.json", "p2.json", OutputFolder=out)
%     >> [data, names] = HRB_runPipeline(EEG, "pipeline.json", OutputFolder=out, Resume=true)
%
% Inputs:
%    data         = [struct] EEGLAB dataset (EEG.subject is the subject ID)
%    pipelineFile = [string, Repeating] pipeline file(s), .json or .yaml (merged)
%
% Name-value:
%    OutputFolder = [string] run root (default: general.save.OutputFolder)
%    Resume       = [logical] reuse saved outputs of non-BST steps with
%                   "save": true when the exact file already exists (default false)
%
% Outputs:
%    data  = cell, one element per universe (EEG struct or HRB_failed struct)
%    names = cell, branch name (hierarchical, filesep-separated) per universe
%
% Authors: Alessandro Tonin, IRCCS San Camillo Hospital, 2024
%
% See also: HRB_RUNDATASET, HRB_VALIDATEPIPELINE

function [data, names] = HRB_runPipeline(data, pipelineFile, opt)
arguments (Input)
    data
end
arguments (Repeating)
    pipelineFile string {mustBeFile}
end
arguments (Input)
    opt.OutputFolder string
    opt.Resume logical
end

%% Parsing arguments
config = HRB_loadConfig("general", "save", opt);

%% Logger
logOptions = struct( ...
    "LogFileDir", config.OutputFolder, ...
    "LogToFile", true);
log = HRB_loggerSetUp("general", logOptions);

%% START
log.info(">>> START MULTIVERSE ANALYSIS <<<")

%% Load pipeline
allPipelines = cell(size(pipelineFile));
for n_pipeline = 1:length(pipelineFile)
    currPipelineFile = pipelineFile{n_pipeline};
    log.info(sprintf("Validate pipeline %s...", currPipelineFile))
    pipeline = HRB_validatePipeline(currPipelineFile,"OutputFolder",config.OutputFolder);
    log.info("...Pipeline is valid!")
    log.info("\n"+jsonencode(pipeline, "PrettyPrint", true));
    allPipelines{n_pipeline} = pipeline;
end
log.info("Merging all pipelines")
pipeline = mergeStruct(allPipelines{:},"addMissingFields",true);
% Reorder fields
%     pipeline = orderfields(pipeline);
log.info("Final merged pipeline is:")
log.info("\n"+jsonencode(pipeline, "PrettyPrint", true));

logParams = unpackStruct(logOptions);
HRB_drawPipeline(pipeline, "OutputFolder", config.OutputFolder, logParams{:})

% Save pipeline
pipelineSaveName = 'pipeline.json';
pipelineSaveFullPath = fullfile(config.OutputFolder, pipelineSaveName);
log.info(sprintf("Saving final pipeline in %s",pipelineSaveFullPath))
fid = fopen(pipelineSaveFullPath, "w");
fprintf(fid,'%s', jsonencode(pipeline, "PrettyPrint", true));
fclose(fid);

%% Starts the loop
steps = fieldnames(pipeline);
log.info(sprintf("There are %d steps", length(steps)))

% Launch-time warnings (multiverse: warn, never block a valid choice)
for iS = 1:numel(steps)
    st = pipeline.(steps{iS});
    if isstruct(st), us = num2cell(st); else, us = st; end
    for iU = 1:numel(us)
        u = us{iU};
        if isfield(u, 'params') && isfield(u.params, 'ProcessOption') && ...
                strcmpi(string(u.params.ProcessOption), "full")
            log.warning(sprintf(['Step %s: ProcessOption="full" bypasses kernel-based scout ' ...
                'reduction; connectivity on full source results can allocate ~100 GB and OOM.'], steps{iS}));
        end
    end
end

data = {data};
names = {''};

% Loop over the steps
for n_steps = 1:length(steps)
    step = pipeline.(steps{n_steps});
    log.info(sprintf("> Step: %d", n_steps))

    l_multiverse = length(step);
    log.info(sprintf("There are %d multiverses", l_multiverse))

    l_data = length(data);

    % The plain loop would be
    % for n_data = 1:l_data
    %   for n_universe = 1:l_multiverse
    %   end
    % end
    % However it is better to flatten the loops in order to get full
    % parallelization

    new_data  = cell(l_data * l_multiverse, 1);
    new_names = cell(l_data * l_multiverse, 1);

    isBstStep = false;
    for iCheck = 1:l_multiverse
        if isstruct(step)
            u = step(iCheck);
        else
            u = step{iCheck};
        end

        if isfield(u, 'function') && startsWith(string(u.function), "HRB_bst_")
            isBstStep = true;
            break;
        end
    end


    if isBstStep
        log.info(sprintf("Step %d uses BST  running sequentially.", n_steps))
        for idx = 1:(l_data * l_multiverse)
            [new_data{idx}, new_names{idx}] = process_universe( ...
                idx, data, names, step, l_data, config, n_steps);
        end
    else
        parfor idx = 1:(l_data * l_multiverse)
            [new_data{idx}, new_names{idx}] = process_universe( ...
                idx, data, names, step, l_data, config, n_steps);
        end
    end

    % Update data and names
    data  = new_data;
    names = new_names;

end % n_steps

%% END
log.info(">>> END MULTIVERSE ANALYSIS <<<")

end

function dataOut = run_step(dataIn, step, output, prevName, resume)

% Check if there are custom params
if isfield(step, "params")
    params = step.params;
else
    params = struct();
end

% Check if there is a custom name
name = getStepName(step);

% Make SaveName unique per subject.
% This ensures BST condition names don't collide across subjects
subjId = '';
if isstruct(dataIn) && isfield(dataIn, 'subject') && ~isempty(dataIn.subject)
    subjId = cleanName(char(dataIn.subject));
end

if isempty(subjId)
    if isempty(prevName)
        params.SaveName = name;
    else
        params.SaveName = sprintf("%s_%s", prevName, name);
    end
else
    if isempty(prevName)
        params.SaveName = sprintf("%s_%s", subjId, name);
    else
        params.SaveName = sprintf("%s_%s_%s", subjId, prevName, name);
    end
end

% Check if must be saved
if isfield(step, "save")
    params.Save = step.save;
end

% Check if there are custom log params
if isfield(step, "log")
    params = catStruct(params, step.log);
    if ~isfield(step.log, "LogFileDir")
        params.LogFileDir = output;
    end
    if ~isfield(step.log, "LogToFile")
        params.LogToFile = true;
    end
else
    params.LogFileDir = output;
    params.LogToFile = true;
end

% Update output folder
params.OutputFolder = output;

% Resume: reuse this step's saved output if the exact file already exists.
% Only non-BST steps with an explicit "save": true (BST state lives in the DB).
dataOut = [];
resumed = false;
if resume && isfield(step, "save") && step.save && ~startsWith(string(step.function), "HRB_bst_")
    saveDir  = fullfile(output, local_step_module(step.function));
    saveFile = char(string(params.SaveName) + ".set");
    if isfile(fullfile(saveDir, saveFile))
        try
            dataOut = pop_loadset('filename', saveFile, 'filepath', char(saveDir));
            resumed = true;
            fprintf('[HRB_runPipeline] RESUME %s: reused %s\n', step.function, fullfile(saveDir, saveFile));
        catch MEload
            fprintf(2, '[HRB_runPipeline] RESUME %s: %s unreadable (%s) -> recomputing\n', ...
                step.function, saveFile, MEload.message);
        end
    end
end

if ~resumed
    % Create function handle
    fun = str2func(step.function);
    % Convert params to a cell array
    cellParams = unpackStruct(params);
    % Execute the step
    dataOut = fun(dataIn, cellParams{:});
end

% Uniform setname + provenance (EEG structs only)
if isstruct(dataOut) && isfield(dataOut, 'setname')
    dataOut.setname = char(params.SaveName);
    logFields = {'LogEnabled','LogLevel','LogToFile','LogFileDir','LogFileName','OutputFolder'};
    prov  = rmfield(params, intersect(fieldnames(params), logFields));
    entry = struct('function', char(step.function), 'saveName', char(params.SaveName), ...
                   'params', prov, 'resumed', resumed, ...
                   'time', char(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss")));
    if ~isfield(dataOut, 'etc') || ~isstruct(dataOut.etc), dataOut.etc = struct(); end
    if ~isfield(dataOut.etc, 'HRB') || ~isfield(dataOut.etc.HRB, 'history')
        dataOut.etc.HRB.history = {entry};
    else
        dataOut.etc.HRB.history{end+1} = entry;
    end
end

end

function m = local_step_module(fn)
% Module folder used by HRB_saveData: '1_preprocessing' -> 'preprocessing'
[~, folder] = fileparts(fileparts(which(char(fn))));
m = extractAfter(folder, "_");
end

function name = getStepName(step)
% Check if there is a custom name
if isfield(step, "name")
    name = step.name;
else
    name = step.function;
end
name = cleanName(name);
end

function name = cleanName(name)
notAllowedChars = {' ', '_'};
cleanChar = '-';
name = replace(name, notAllowedChars, cleanChar);
end

function [out_data, out_name] = process_universe(idx, data, names, step, l_data, config, n_steps)

n_data     = mod(idx-1, l_data) + 1;
n_universe = floor((idx-1) / l_data) + 1;

current_data = data{n_data};
current_name = names{n_data};
l_multiverse = length(step);

if isstruct(step)
    universe = step(n_universe);
else
    universe = step{n_universe};
end

if isstruct(current_data) && isfield(current_data, 'HRB_failed') && current_data.HRB_failed
    out_data = current_data;
    out_name = current_name;
    return;
end

% Extract subject ID for folder structure
subjId = '';
if isstruct(current_data) && isfield(current_data, 'subject') && ~isempty(current_data.subject)
    subjId = cleanName(char(current_data.subject));
end

% Build branch name: current accumulated name + this universe's name (if multiverse)
if l_multiverse > 1
    universeName = getStepName(universe);
    if isempty(current_name)
        branchName = universeName;
    else
        branchName = fullfile(current_name, universeName);
    end
else
    branchName = current_name;
end

% Build output folder
if isempty(subjId) && isempty(branchName)
    universeFolder = fullfile(config.OutputFolder, "shared");  % subject-less shared steps
elseif isempty(branchName)
    universeFolder = fullfile(config.OutputFolder, subjId, "shared");  % pre-multiverse steps of a subject
elseif isempty(subjId)
    universeFolder = fullfile(config.OutputFolder, branchName);
else
    universeFolder = fullfile(config.OutputFolder, subjId, branchName);
end

if ~exist(universeFolder, 'dir')
    mkdir(universeFolder);
end

prevNameFlat = strrep(current_name, filesep, '_');

try
    out_data = run_step(current_data, universe, universeFolder, prevNameFlat, config.Resume);
catch ME
    report = getReport(ME, 'extended', 'hyperlinks', 'off'); %full stack (file and line)
    fprintf(2, '%s\n', report);
    warning("HRB:UniverseFailed", ...
        "Step %d Universe %d failed: %s", n_steps, n_universe, ME.message);
    subjOut = '';
    if isstruct(current_data) && isfield(current_data, 'subject')
        subjOut = char(current_data.subject);
    end
    out_data = struct('HRB_failed', true, 'HRB_error', ME.message, ...
        'HRB_errorId', ME.identifier, 'HRB_report', report, ...
        'HRB_function', char(universe.function), ...
        'HRB_step', n_steps, 'HRB_universe', n_universe, 'subject', subjOut);
end

if l_multiverse > 1
    if isempty(current_name)
        out_name = getStepName(universe);
    else
        out_name = fullfile(current_name, getStepName(universe));
    end
else
    out_name = current_name;
end

end