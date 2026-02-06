function pipeline = HRB_createPipeline(pipelineHandlers, opt)
% HRB_CREATEPIPELINE - Create a pipeline from a cellarray of function
% handlers
%
% Examples:
%     >>> HRB_createPipeline(pipelineHandlers)
%     >>> HRB_createPipeline(pipelineHandlers, 'key', 'val')
%
% Parameters:
%    pipelineHandlers (cell): A cell array of function handlers
%
% Other Parameters:
%    OutputFolder (string): The output folder where to save the logs
%
% Returns:
%   pipeline (struct): The pipeline converted to matlab struct
%
% See also: 
%   JSONDECODE
% 
% Authors: Alessandro Tonin, IRCCS San Camillo Hospital, 2024

    arguments (Input)
        pipelineHandlers (1,:) cell {mustBeHandle}
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

    %% Create the pipeline structure from the cellarray
    % Each cell of the cell array is one step, if there is a cellarray it
    % is a multiverse
    % Let's create a structure like the one created from the json file
    pipeline = struct();
    for n_steps = 1:length(pipelineHandlers)
        stepHandler = pipelineHandlers{n_steps};
        step_name = sprintf("step%d", n_steps);
        if isa(stepHandler,"function_handle")
            pipeline.(step_name) = handler2struct(stepHandler);
        else
            step_array = {};
            for n_universe = 1:length(stepHandler)
                step_universe = stepHandler{n_universe};
                step_array{n_universe} = handler2struct(step_universe);
                
            end
            pipeline.(step_name) = step_array;
        end
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
                errmsg = sprintf("Pipeline error - The step %s must be a struct or a cellarray (a multiverse)", steps(s));
                log.error(errmsg);
                error(errmsg);
            end

            universe_fields = fieldnames(universe);

            % Each step must contain only predefined fields
            wrongFields = setdiff(universe_fields, STEPFIELDS);
        
            if ~isempty(wrongFields)
                errmsg = sprintf("Pipeline error - In step %s the following fields are not allowed: %s. Only fields allowed: %s", ...
                    strjoin(steps(s), ', '), strjoin(wrongFields, ', '), strjoin(STEPFIELDS, ', '));
                log.error(errmsg);
                error(errmsg);
            end

            % Each step must contain field "function"
            if ~ismember('function', universe_fields)
                errmsg = sprintf("Pipeline error - All universes of step %s MUST contain the field 'function'!", ...
                    steps(s));
                log.error(errmsg);
                error(errmsg);
            end
            
            % Not mandatory for a valide pipeline, but let's check if the
            % function is in the path
            if ~exist(universe.function)
                warnmsg = sprintf("Pipeline contains function %s, but the function is not in the path", universe.function);
                log.warning(warnmsg);
            end

            % If it is a multiverse also name is mandatory!
            if l_multiverse > 1 && ~ismember('function', universe_fields)
                errmsg = sprintf("Pipeline error - All universes of multiverse step %s MUST contain the field 'name'!", ...
                    steps(s));
                log.error(errmsg);
                error(errmsg);
            end

        end

    end

    end
end


function mustBeHandle(c)
for idx_1 = 1:length(c)
    c_i = c{idx_1};
    if iscell(c_i)
        isfhandle = cellfun(@(x) isa(x,'function_handle'),c_i);
        isfhandle = all(isfhandle);
    elseif isa(c_i,'function_handle')
        isfhandle = 1;
    else
        isfhandle = 0;
    end
    if ~isfhandle
        eidType = 'mustBeHandle:notFunctionHandle';
        msgType = 'Input must be a cell array of function handles';
        error(eidType,msgType)
    end
end
end

function s  = handler2struct(fh)
s = struct();
% Extract name of the function and parameters from the handler
fstr = func2str(fh);
% Regular expression of a handler @(x)func(x,parm=val)
pattern_handle = '^@\(\w+\)(?<func>\w+)\(\w+(?<param>.)*\)$';
r = regexp(fstr, pattern_handle, 'names');
s.function = r.func;
param = r.param;
% Now we have to extract key-val from param
pattern_key = "['"+'"]?'+"\w+"+'["'+"']?";
pattern_val = "\w+";
pattern_val_array = "[\[{].*[\]}]";
pattern_param = sprintf("(?<key>%s) ?[=,] ?(?<val>%s|%s)",pattern_key, pattern_val, pattern_val_array);
keyvals = regexp(param, pattern_param,'match');
s.params = struct();
for ii = 1:length(keyvals)
    keyval = regexp(keyvals{ii}, pattern_param,'names');
    key = cleanCharString(keyval.key);
    val = cleanCharString(keyval.val);
    s.params.(key) = eval(val);
end

end


function c = cleanCharString(c)
    if startsWith(c,'"') && endsWith(c,'"')
        c = c(2:end-1);
    elseif startsWith(c,"'") && endsWith(c,"'")
        c = c(2:end-1);
    end
end