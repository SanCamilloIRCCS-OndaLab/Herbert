function pipeline = HRB_validatePipeline(pipelineFile, opt)
% HRB_VALIDATEPIPELINE - Validate a pipeline by checking that all the
% required fields are filled and that the overall structure is compatible
% with HRB.
%
% Examples:
%     >>> HRB_validatePipeline(pipelineFile)
%     >>> HRB_validatePipeline(pipelineFile, 'key', 'val')
%
% Parameters:
%    pipelineFile (string): A file with the pipeline. Allowed formats are json or yaml.
%
% Other Parameters:
%    OutputFolder (string): The output folder where to save the logs
%
% Returns:
%   pipeline (struct): The validated pipeline (decoded JSON / YAML)
%
% See also: 
%   JSONDECODE
% 
% Authors: Alessandro Tonin, IRCCS San Camillo Hospital, 2024

    arguments (Input)
        pipelineFile string {mustBeFile}
        % Save options
        opt.OutputFolder string
        % Log options
        opt.LogEnabled logical
        opt.LogLevel double {mustBeInteger,mustBeInRange(opt.LogLevel,0,6)}
        opt.LogToFile logical
        opt.LogFileDir string
        opt.LogFileName string
    end

    %% Parsing arguments
    config = HRB_loadConfig("general", "save", opt);

    %% Logger
    logOptions = struct( ...
        "LogFileDir", config.OutputFolder);
    log = HRB_loggerSetUp("general", logOptions);

    %% Load pipeline file
    if pipelineFile.endsWith('.json')
        % it's json format, let's use jsondecode
        pipeline_str = fileread(pipelineFile);
        pipeline = jsondecode(pipeline_str);
    elseif pipelineFile.endsWith('.yaml')
        % it's yaml format, let's use yaml utils from https://github.com/MartinKoch123/yaml
        pipeline = yaml.loadFile(pipelineFile);
        pipeline = replaceFieldxFunction(pipeline);
    else
        errmsg = sprintf("Pipeline error - The pipeline file %s must be .json or .yaml", pipelineFile);
        log.error(errmsg);
        error("HRB:InvalidPipeline", "%s", errmsg);
    end

    
    %% Validate pipeline

    STEPFIELDS = {
        'function';
        'name';
        'save';
        'log';
        'params'
    };

    % All the step fields must be structures or cell array of struct
    steps = fieldnames(pipeline);

    % Check each step
    for s = 1:length(steps)
        step = pipeline.(steps{s});

        l_multiverse = length(step);

        for n_universe = 1:l_multiverse
            if isstruct(step)
                universe = step(n_universe);
            elseif iscell(step)
                universe = step{n_universe};
            else
                errmsg = sprintf("Pipeline error - The step %s must be a struct or a cellarray (a multiverse)", steps{s});
                log.error(errmsg);
                error("HRB:InvalidPipeline", "%s", errmsg);
            end

            universe_fields = fieldnames(universe);

            % Each step must contain only predefined fields
            wrongFields = setdiff(universe_fields, STEPFIELDS);
        
            if ~isempty(wrongFields)
                errmsg = sprintf("Pipeline error - In step %s the following fields are not allowed: %s. Only fields allowed: %s", ...
                     steps{s}, strjoin(wrongFields, ', '), strjoin(STEPFIELDS, ', '));
                log.error(errmsg);
                error("HRB:InvalidPipeline", "%s", errmsg);
            end

            % Each step must contain field "function"
            if ~ismember('function', universe_fields)
                errmsg = sprintf("Pipeline error - All universes of step %s MUST contain the field 'function'!", ...
                    steps{s});
                log.error(errmsg);
                error("HRB:InvalidPipeline", "%s", errmsg);;
            end
            
            % Not mandatory for a valide pipeline, but let's check if the
            % function is in the path
            if ~exist(universe.function, 'file')
                errmsg = sprintf("Pipeline error - Function %s (step %s) is not on the MATLAB path.", ...
                    universe.function, steps{s});
                log.error(errmsg);
                error("HRB:FunctionNotFound", "%s", errmsg);
            end

            % If it is a multiverse also name is mandatory!
            if l_multiverse > 1 && ~ismember('name', universe_fields)
                errmsg = sprintf("Pipeline error - All universes of multiverse step %s MUST contain the field 'name'!", ...
                    steps{s});
                log.error(errmsg);
                error("HRB:InvalidPipeline", "%s", errmsg);
            end

        end


        % Names become folder names, SaveName parts and BST Comments:
        % they must be unique (after cleanName) and contain only [A-Za-z0-9-].
        if isstruct(step), us = num2cell(step); else, us = step; end
        hasName = cellfun(@(u) isfield(u,'name'), us);
        nm = strings(1,0);
        if any(hasName)
            nm = string(cellfun(@(u) char(u.name), us(hasName), 'UniformOutput', false));
        end
        nmClean = replace(nm, [" ","_"], "-");
        badName = nmClean(cellfun(@isempty, regexp(cellstr(nmClean), '^[A-Za-z0-9\-]+$', 'once')));
        if ~isempty(badName)
            errmsg = sprintf("Pipeline error - Step %s: names may contain only letters, digits, '-', '_' or ' ': %s", ...
                steps{s}, strjoin(badName, ", "));
            log.error(errmsg); error("HRB:InvalidUniverseName", "%s", errmsg);
        end
        if l_multiverse > 1 && numel(unique(nmClean)) < numel(nmClean)
            [~, ia] = unique(nmClean, 'stable');
            dup = unique(nmClean(setdiff(1:numel(nmClean), ia)));
            errmsg = sprintf("Pipeline error - Step %s has duplicate universe names (after '_'/' ' -> '-'): %s", ...
                steps{s}, strjoin(dup, ", "));
            log.error(errmsg); error("HRB:DuplicateUniverseName", "%s", errmsg);
        end

    end

end


function s = replaceFieldxFunction(s)
% loop all steps
steps = fieldnames(s);
for sn = 1:length(steps)
    step = s.(steps{sn});
    if isstruct(step)
        step = RenameField(step,'xFunction','function');
    else % it's multiuniverse
        for l = 1:length(step)
            step{l} = RenameField(step{l},'xFunction','function');
        end
    end
    s.(steps{sn}) = step;
end
end
