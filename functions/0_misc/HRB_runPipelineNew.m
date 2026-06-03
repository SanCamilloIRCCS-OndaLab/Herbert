% % HRB_RUNPIPELINENEW - Run a multiverse pipeline over a set of data.
%
% Usage:
%     >> HRB_runPipelineNew(pipelineJSON, data)
%     >> HRB_runPipelineNew(pipelineJSON, data, "OutputFolder", output)
%
% Inputs:
%    data         = [struct] EEG data struct
%    pipelineFile = [string] Pipeline file (.json or .yaml)
%    OutputFolder = [string] Folder where to save outputs
%
% Changes vs original:
%   FIX: Adaptive for/parfor  BST functions use sequential for (global state
%        + shared DB files make parfor unsafe); non-BST preprocessing
%        functions (filter, ICA, epoch, etc.) use parfor as before.
%   FIX M3: try/catch around run_step  a single universe failure no longer
%        crashes the whole pipeline. Failed universes are marked with a
%        sentinel struct and skipped downstream. A summary is printed at end.
%
% Authors: Alessandro Tonin, IRCCS San Camillo Hospital, 2024
%          Ettore Napoli, University of Bologna, 2026
%
% See also: HRB_VALIDATEPIPELINE, HRB_DRAWPIPELINE

function data = HRB_runPipelineNew(data, pipelineFile, opt)
    arguments (Input)
        data
    end
    arguments (Repeating)
        pipelineFile string {mustBeFile}
    end
    arguments (Input)
        opt.OutputFolder string
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
        pipeline = HRB_validatePipeline(currPipelineFile);
        log.info("...Pipeline is valid!")
        log.info("\n"+jsonencode(pipeline, "PrettyPrint", true));
        allPipelines{n_pipeline} = pipeline;
    end
    log.info("Merging all pipelines")
    pipeline = mergeStruct(allPipelines{:}, "addMissingFields", true);
    log.info("Final merged pipeline:")
    log.info("\n"+jsonencode(pipeline, "PrettyPrint", true));

    logParams = unpackStruct(logOptions);
    HRB_drawPipeline(pipeline, "OutputFolder", config.OutputFolder, logParams{:})

    % Save pipeline to disk
    pipelineSaveFullPath = fullfile(config.OutputFolder, 'pipeline.json');
    log.info(sprintf("Saving pipeline to %s", pipelineSaveFullPath))
    fid = fopen(pipelineSaveFullPath, "w");
    fprintf(fid, jsonencode(pipeline, "PrettyPrint", true));
    fclose(fid);

    %% Main loop
    steps = fieldnames(pipeline);
    log.info(sprintf("There are %d steps", length(steps)))

    data  = {data};
    names = {''};

    for n_steps = 1:length(steps)
        step = pipeline.(steps{n_steps});
        log.info(sprintf("> Step: %d", n_steps))

        l_multiverse = length(step);
        log.info(sprintf("There are %d multiverses", l_multiverse))

        l_data = length(data);

        new_data  = cell(l_data * l_multiverse, 1);
        new_names = cell(l_data * l_multiverse, 1);

        % *** FIX: adaptive for/parfor.
        % Only HRB_bst_headmodel steps are forced sequential  they write to
        % the shared @intra subject folder which is not condition-isolated.
        % All other BST steps (import, noisecov, inverse, connectivity) write
        % to per-condition folders, fully isolated by the conditionName fix in
        % HRB_bst_import, and are safe to run in parallel with parfor.
        isHeadmodelStep = false;
        for iCheck = 1:l_multiverse
            if isstruct(step)
                u = step(iCheck);
            else
                u = step{iCheck};
            end
            if isfield(u, 'function') && startsWith(string(u.function), "HRB_bst_headmodel")
                isHeadmodelStep = true;
                break;
            end
        end

        if isHeadmodelStep
            % Sequential: headmodel writes to shared @intra subject folder
            log.info(sprintf("Step %d is headmodel  running sequentially.", n_steps))
            for idx = 1:(l_data * l_multiverse)
                [new_data{idx}, new_names{idx}] = process_universe( ...
                    idx, data, names, step, l_data, config, n_steps);
            end
        else
            % Parallel: safe for preprocessing AND for BST steps other than headmodel
            % NOTE: the log object is NOT used inside parfor  not serializable.
            parfor idx = 1:(l_data * l_multiverse)
                [new_data{idx}, new_names{idx}] = process_universe( ...
                    idx, data, names, step, l_data, config, n_steps);
            end
        end

        data  = new_data;
        names = new_names;

    end % n_steps

    %% END
    % *** FIX M3: report failed universes ***
    failedIdx = find(cellfun( ...
        @(d) isstruct(d) && isfield(d, 'HRB_failed') && d.HRB_failed, data));
    if ~isempty(failedIdx)
        log.warning(sprintf("!!! %d universe(s) FAILED during the multiverse analysis:", ...
            numel(failedIdx)));
        for fi = 1:numel(failedIdx)
            d = data{failedIdx(fi)};
            log.warning(sprintf("    - Step %d, Universe %d: %s", ...
                d.HRB_step, d.HRB_universe, d.HRB_error));
        end
    else
        log.info("All universes completed successfully.");
    end

    log.info(">>> END MULTIVERSE ANALYSIS <<<")

end

% =========================================================================
% LOCAL FUNCTIONS
% =========================================================================

function [out_data, out_name] = process_universe(idx, data, names, step, l_data, config, n_steps)
% Process a single universe. Called by both for (BST steps) and parfor
% (preprocessing steps). Encapsulating the body here avoids code duplication
% between the two loop types.

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

    % *** FIX M3: skip universes that already failed in a previous step ***
    % If upstream produced a sentinel (HRB_failed=true), propagate it
    % downstream without attempting to process it.
    if isstruct(current_data) && isfield(current_data, 'HRB_failed') && current_data.HRB_failed
        out_data = current_data;
        out_name = current_name;
        return;
    end

    % *** FIX M3: wrap run_step in try/catch ***
    % A failure in one universe (e.g. ICA non-convergence, corrupted epoch)
    % no longer crashes the whole multiverse. The universe is marked as
    % failed and all downstream steps skip it. A full report is printed
    % at the end of the pipeline (see END section above).
    try
        out_data = run_step(current_data, universe, config.OutputFolder, current_name);
    catch ME
        warning("HRB:UniverseFailed", ...
            "Step %d Universe %d failed: %s", n_steps, n_universe, ME.message);
        out_data = struct( ...
            'HRB_failed',   true, ...
            'HRB_error',    ME.message, ...
            'HRB_step',     n_steps, ...
            'HRB_universe', n_universe);
    end

    % Update universe name
    if l_multiverse > 1
        if isempty(current_name)
            out_name = getStepName(universe);
        else
            out_name = sprintf("%s_%s", current_name, getStepName(universe));
        end
    else
        out_name = current_name;
    end

end

% -------------------------------------------------------------------------

function dataOut = run_step(dataIn, step, output, prevName)

    if isfield(step, "params")
        params = step.params;
    else
        params = struct();
    end

    name = getStepName(step);

    if isempty(prevName)
        params.SaveName = name;
    else
        params.SaveName = sprintf("%s_%s", prevName, name);
    end

    if isfield(step, "save")
        params.Save = step.save;
    end

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

    params.OutputFolder = output;

    fun = str2func(step.function);
    cellParams = unpackStruct(params);
    dataOut = fun(dataIn, cellParams{:});

    % Debug print
    if isstruct(dataOut) && isfield(dataOut, 'trials')
        fprintf('>>> %s | IN: %d trials | OUT: %d trials\n', ...
            step.function, dataIn.trials, dataOut.trials);
    end

end

% -------------------------------------------------------------------------

function name = getStepName(step)
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