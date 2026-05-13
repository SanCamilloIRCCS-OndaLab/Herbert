function exportFunctionDefs(outputFile)
% EXPORTFUNCTIONDEFS  Export function definitions from HRB_defaultConfig
% and the arguments blocks of each function file to a JSON file.
%
% Usage:
%   exportFunctionDefs()                    % writes to gui/function_definitions.json
%   exportFunctionDefs("myfile.json")       % writes to custom path
%
% This script merges two sources:
%   1. HRB_defaultConfig.m  → module, function, parameter names + default values
%   2. Each function's arguments(Input) block → types, constraints (enum), dimensions

if nargin < 1
    outputFile = fullfile(fileparts(mfilename('fullpath')), 'function_definitions.json');
end

% Get toolbox root
toolboxRoot = fileparts(fileparts(mfilename('fullpath')));

%% 1. Load default config
config = HRB_defaultConfig();

%% 2. Define module-to-function mappings from the config struct
% The config struct is nested: config.<module>.<funcKey>.<paramName>
% We need to know which funcKey maps to which HRB_ function file.

% Manually define the mapping between config keys and function file names
% (this is needed because the config key doesn't always match the function name,
%  e.g. HRB_importData uses config key "import")
moduleFuncMap = containers.Map();
moduleFuncMap('preprocessing') = {
    'chanedit',     'HRB_chanedit'
    'resample',     'HRB_resample'
    'filter',       'HRB_filter'
    'removeChannels','HRB_removeChannels'
    'selectChannels','HRB_selectChannels'
    'selectTime',   'HRB_selectTime'
    'cleanData',    'HRB_cleanData'
    'runica',       'HRB_runica'
    'iclabel',      'HRB_iclabel'
    'icflag',       'HRB_icflag'
    'subcomp',      'HRB_subcomp'
    'epoch',        'HRB_epoch'
    'rejepochs',    'HRB_rejepochs'
    'import',       'HRB_importData'
    };
% Modules without functions yet
moduleFuncMap('headModel') = {};
moduleFuncMap('sourceEstimation') = {};
moduleFuncMap('connectivity') = {};
moduleFuncMap('network') = {};

% Other modules may be in config but not in HRB_defaultConfig (e.g. general)
% We skip those

%% 3. Build output structure by parsing each function
defs = struct();

modules = fieldnames(config);
for mIdx = 1:length(modules)
    modName = modules{mIdx};
    
    % Skip general and logging (no pipeline functions)
    if any(strcmp(modName, {'general'}))
        continue;
    end
    
    funcList = moduleFuncMap(modName);
    if isempty(funcList)
        % No functions for this module yet - add empty entry
        if ~isfield(defs, modName)
            defs.(modName) = struct();
        end
        continue;
    end
    
    if ~isfield(defs, modName)
        defs.(modName) = struct();
    end
    
    % Get the config substruct for this module
    if ~isfield(config, modName)
        continue;
    end
    modConfig = config.(modName);
    
    % Iterate over (configKey, funcName) pairs
    for fIdx = 1:size(funcList, 1)
        configKey = funcList{fIdx, 1};
        funcName  = funcList{fIdx, 2};
        
        % Get default params from config
        if isfield(modConfig, configKey)
            configParams = modConfig.(configKey);
        else
            configParams = struct();
        end
        
        % Get argument types by parsing the function file
        funcFile = fullfile(toolboxRoot, 'functions', ...
            sprintf('%d_%s', findModuleFolder(modName)), ...
            [funcName, '.m']);
        
        [argTypes, argEnums, argSizes, argHasDefault, argDefaults] = parseArgumentsBlock(funcFile);
        
        % Build params structure for this function
        funcDef = struct();
        funcDef.module = modName;
        funcDef.label = funcName; % will be overridden with nicer label
        
        % Collect function-specific parameters (exclude boilerplate: EEGLAB, Save, SaveName, OutputFolder, Log*)
        boilerplate = {'EEGLAB', 'Save', 'SaveName', 'OutputFolder', ...
                       'LogEnabled', 'LogLevel', 'LogToFile', 'LogFileDir', 'LogFileName'};
        
        paramFields = fieldnames(configParams);
        params = struct();
        
        for pIdx = 1:length(paramFields)
            pName = paramFields{pIdx};
            
            % Skip boilerplate (they are implied by the save checkbox and module)
            if any(strcmp(pName, boilerplate))
                continue;
            end
            
            pDef = struct();
            
            % Get default value (from config, this is the authoritative source)
            rawDefault = configParams.(pName);
            pDef.default = matlabValueToJson(rawDefault);
            
            % Get type and constraints from args block
            if isKey(argTypes, pName)
                pDef.type = argTypes(pName);
            else
                % Infer type from the default value
                pDef.type = inferType(rawDefault);
            end
            
            if isKey(argEnums, pName)
                pDef.enum = argEnums(pName);
            end
            
            if isKey(argSizes, pName)
                sz = argSizes(pName);
                if any(sz > 1) || length(sz) > 1
                    pDef.size = sz;
                end
            end
            
            params.(pName) = pDef;
        end
        
        % Also add Save parameter explicitly (common to all, but useful to expose)
        % Not needed: it's in the boilerplate and handled by checkbox in GUI
        
        funcDef.params = params;
        defs.(modName).(configKey) = funcDef;
    end
end

%% 4. Write to JSON
jsonStr = structToJson(defs);
fid = fopen(outputFile, 'w');
fprintf(fid, '%s', jsonStr);
fclose(fid);
fprintf('Function definitions written to: %s\n', outputFile);

end

%% Helper functions

function folderNum = findModuleFolder(modName)
    switch modName
        case 'preprocessing', folderNum = 1;
        case 'headModel', folderNum = 2;
        case 'sourceEstimation', folderNum = 3;
        case 'connectivity', folderNum = 4;
        case 'network', folderNum = 5;
        otherwise, folderNum = 0;
    end
end

function [types, enums, sizes, hasDefault, defaults] = parseArgumentsBlock(funcFile)
% Parse the arguments(Input) block from a MATLAB function file
% Returns containers.Map for each property

types = containers.Map();
enums = containers.Map();
sizes = containers.Map();
hasDefault = containers.Map();
defaults = containers.Map();

if ~exist(funcFile, 'file')
    return;
end

text = fileread(funcFile);

% Find the arguments(Input) block
startIdx = strfind(text, 'arguments (Input)');
if isempty(startIdx)
    startIdx = strfind(text, 'arguments(Input)');
end
if isempty(startIdx)
    return;
end

% Find the matching 'end' for this arguments block
% Use '\n    end' as anchor to avoid matching 'end' inside 'extended'
endIdx = strfind(text(startIdx(1):end), sprintf('\n    end\n'));
if isempty(endIdx)
    endIdx = strfind(text(startIdx(1):end), sprintf('\nend\n'));
end
if isempty(endIdx)
    % Try end-of-file or end-of-line variants
    endIdx = strfind(text(startIdx(1):end), sprintf('\n    end'));
    if isempty(endIdx)
        endIdx = strfind(text(startIdx(1):end), sprintf('\nend'));
    end
end
if isempty(endIdx)
    return;
end
blockText = text(startIdx(1):startIdx(1)+endIdx(1)+4);

% Split into lines
lines = splitlines(blockText);

for i = 1:length(lines)
    line = strtrim(lines{i});
    
    % Match: opt.ParamName type {mustBeMember(...)} = value
    % Match: opt.ParamName (dim1,dim2) type = value
    % Match: opt.ParamName type = value
    % Match: opt.ParamName (dim1,dim2) type {mustBeMember(...)} = value
    
    tok = regexp(line, '^opt\.(\w+)\s*(?:\(([^)]*)\))?\s*(\w+(?:\s*\{[^}]*\})?)\s*(?:(=\s*(.*)))?$', 'tokens');
    if isempty(tok)
        continue;
    end
    
    paramName = tok{1}{1};
    
    % Dimensions
    if ~isempty(tok{1}{2})
        dimStr = strtrim(tok{1}{2});
        dims = str2num(dimStr); %#ok<ST2NM>
        if ~isempty(dims)
            sizes(paramName) = dims;
        end
    end
    
    % Type + constraints
    typeConstraint = strtrim(tok{1}{3});
    
    % Check for mustBeMember
    memTok = regexp(typeConstraint, '\w+\s*\{\s*mustBeMember\s*\(\s*\w+\s*,\s*\[([^\]]*)\]\s*\)\s*\}', 'tokens');
    if isempty(memTok)
        memTok = regexp(typeConstraint, '\w+\s*\{\s*mustBeMember\s*\(\s*\w+\s*,\s*\["([^"]*)"(?:\s*,\s*"([^"]*)")*\]\s*\)\s*\}', 'tokens');
        % Try with cellstr syntax: mustBeMember(opt.ParamName, ["a","b","c"])
        memTok2 = regexp(typeConstraint, '\w+\s*\{\s*mustBeMember\s*\(\s*\w+\s*,\s*\[([^\]]*)\]\)\s*\}', 'tokens');
        if ~isempty(memTok2)
            memTok = memTok2;
        end
        % Try: mustBeMember(opt.ParamName, ["val1","val2",...])
        memTok3 = regexp(typeConstraint, '\w+\s*\{\s*mustBeMember\s*\(\s*\w+\s*,\s*\[(.*?)\]\)\s*\}', 'tokens');
        if ~isempty(memTok3)
            memTok = memTok3;
        end
    end
    
    if ~isempty(memTok)
        strVal = memTok{1}{1};
        % Extract string values - they can be "value" or value (without quotes if numeric-like)
        vals = regexp(strVal, '"([^"]*)"', 'tokens');
        enumVals = {};
        for v = 1:length(vals)
            enumVals{end+1} = vals{v}{1}; %#ok<AGROW>
        end
        if ~isempty(enumVals)
            enums(paramName) = enumVals;
        end
        
        % Determine base type from constraint/type string
        baseTypeTok = regexp(typeConstraint, '^(\w+)', 'tokens');
        if ~isempty(baseTypeTok)
            types(paramName) = baseTypeTok{1}{1};
        else
            types(paramName) = 'string';
        end
    else
        % Simple type
        baseTypeTok = regexp(typeConstraint, '^(\w+)', 'tokens');
        if ~isempty(baseTypeTok)
            types(paramName) = baseTypeTok{1}{1};
        end
    end
    
    % Default value
    if length(tok{1}) >= 5 && ~isempty(tok{1}{4})
        hasDefault(paramName) = true;
        defaults(paramName) = strtrim(tok{1}{4});
    end
end
end

function jsonVal = matlabValueToJson(val)
% Convert a MATLAB value to its JSON-compatible representation
    if isstring(val) && isscalar(val)
        jsonVal = char(val);
    elseif ischar(val)
        jsonVal = val;
    elseif isnumeric(val) && isscalar(val)
        jsonVal = val;
    elseif isnumeric(val)
        jsonVal = val;
    elseif islogical(val)
        jsonVal = val;
    elseif iscellstr(val) || isstring(val)
        jsonVal = val;
    elseif isempty(val)
        jsonVal = [];
    elseif isstruct(val)
        jsonVal = '[complex]';
    else
        jsonVal = '';
    end
end

function typeStr = inferType(val)
    if islogical(val)
        typeStr = 'logical';
    elseif isnumeric(val) && isscalar(val)
        typeStr = 'double';
    elseif isnumeric(val)
        typeStr = 'double';
    elseif ischar(val) || isstring(val)
        typeStr = 'string';
    elseif iscell(val)
        typeStr = 'cell';
    else
        typeStr = 'string';
    end
end

function jsonStr = structToJson(S)
% Custom MATLAB struct to JSON serialization (preserves arrays correctly)
% Uses built-in if available, otherwise manual
    jsonStr = jsonencode(S, 'PrettyPrint', true);
end
