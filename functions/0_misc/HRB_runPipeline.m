% HRB_RUNPIPELINE - Run a multiverse pipeline over a set of data.
%
% Usage:
%     >> HRB_runPipeline(pipelineJSON, data)
%     >> HRB_runPipeline(pipelineJSON, data, "OutputFolder", output)
%
% Inputs:
%    data    = [struct] The name of the saved file (default: the name
%           of the calling function)
%    pipelineFile = [string] The pipeline file. Allowed formats are json and yaml
%    saveFolder  = [string] The folder where to save the file (default: the
%           name of the module of the calling function)
%
%
% Authors: Alessandro Tonin, IRCCS San Camillo Hospital, 2024
% 
% See also: SAVE, POP_SAVESET

function data = HRB_runPipeline(data, pipelineFile, opt)
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
    fprintf(fid,jsonencode(pipeline, "PrettyPrint", true));
    fclose(fid);

    %% Starts the loop
    steps = fieldnames(pipeline);
    log.info(sprintf("There are %d steps", length(steps)))

    data = {data};
    names = {''};

    % Loop over the steps
    for n_steps = 1:length(steps)
        step = pipeline.(steps{n_steps});
        log.info(sprintf("> Step: %d", n_steps))
        
        l_multiverse = length(step);
        log.info(sprintf("There are %d multiverses", l_multiverse))

        l_data = length(data);

        % Loop over the data
        for n_data = 1:l_data

            % Extract current data
            current_data = data{n_data};
            current_name = names{n_data};

            % Loop over the universes
            for n_universe = 1:l_multiverse
                if isstruct(step)
                    universe = step(n_universe);
                else %iscell
                    universe = step{n_universe};
                end
                log.info(sprintf(">> Universe: %d", n_universe))
    
                % Run the step
                out = run_step(current_data, universe, config.OutputFolder, current_name);
    
                % Save the output in our data array
                idx = n_data + (n_universe-1)*l_data;
                data{idx} = out;
                % If multiverse add name to identify dataset
                if l_multiverse > 1
                    if isempty(current_name)
                        names{idx} = getStepName(universe);
                    else
                        names{idx} = sprintf("%s_%s", current_name, getStepName(universe));
                    end
                end
                log.warning(sprintf("****** %s", getStepName(universe)))
            end % n_universe
        end % n_data
    end % n_steps

    %% END
    log.info(">>> END MULTIVERSE ANALYSIS <<<")

end

function dataOut = run_step(dataIn, step, output, prevName)

    % Check if there are custom params
    if isfield(step, "params")
        params = step.params;
    else
        params = struct();
    end
    
    % Check if there is a custom name
    name = getStepName(step);

    if isempty(prevName)
        params.SaveName = name;
    else
        params.SaveName = sprintf("%s_%s", prevName, name);
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
    
    % Create function handle
    fun = str2func(step.function);
    
    % Convert params to a cell array
    cellParams = unpackStruct(params);
    
    % Execute the step
    dataOut = fun(dataIn, cellParams{:});
%     dataOut = sprintf("%s_%s", dataIn, params.SaveName);

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