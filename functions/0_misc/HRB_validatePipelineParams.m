function R = HRB_validatePipelineParams(pipelineJsonPath)
%HRB_validatePipelineParams  Statically validate a pipeline JSON against the
%MATLAB `arguments` block of each step's function, before running it.
%
%  Catches mismatches that would otherwise only surface as a silent
%  per-universe failure deep inside HRB_runPipeline (e.g. a parameter name
%  that doesn't exist for a given function, or a value outside the set
%  allowed by mustBeMember/mustBeInRange/mustBeInteger).
%
%  This is a STATIC check: it parses the `arguments(Input) ... end` block
%  of each function's .m source file with regular expressions. It does not
%  call the function, so it cannot catch errors that depend on runtime
%  state (e.g. "Atlas not found for this subject"). It only catches what
%  is mechanically derivable from the function signature.
%
%  USAGE
%    R = HRB_validatePipelineParams('pipeline_extended_PROVA2.json')
%
%  INPUT
%    pipelineJsonPath   string   path to the pipeline JSON file
%
%  OUTPUT
%    R   table, one row per problem found:
%          step_name    string   step name from JSON (e.g. 'corr-NxN')
%          step_path    string   JSON path (e.g. 'step15_connectivity[3]')
%          function     string   function name (e.g. 'HRB_bst_connectivity_corr')
%          param        string   the offending parameter name
%          issue_type   string   'unknown_param' | 'invalid_value' | 'wrong_type'
%          detail       string   human-readable explanation
%
%  An empty table (height 0) means no problems were found.
%
%  WHAT IS CHECKED
%    - Every key in a step's "params" object exists in that function's
%      `arguments(Input)` block (issue_type = 'unknown_param')
%    - If the parameter has `mustBeMember(opt.X, [...])`, the JSON value is
%      checked against that list (issue_type = 'invalid_value')
%    - If the parameter has `mustBeInRange(opt.X, a, b)`, the JSON value is
%      checked to be numeric and within [a, b] (issue_type = 'invalid_value')
%    - If the parameter has `mustBeInteger`, the JSON value is checked to be
%      a whole number (issue_type = 'invalid_value')
%    - If the parameter's declared base type is string/double/logical/cell
%      and the JSON value's type is incompatible, flagged as 'wrong_type'
%
%  WHAT IS NOT CHECKED
%    - Validators other than mustBeMember/mustBeInRange/mustBeInteger
%      (e.g. custom validation functions) are silently skipped — this
%      function only validates what it can mechanically parse
%    - Runtime-only constraints (e.g. "Scouts must exist in this subject's
%      atlas") are out of scope by design
%
% Author: Ettore Napoli - University of Bologna, 2026

arguments (Input)
    pipelineJsonPath string {mustBeFile}
end

%% Load and parse the pipeline JSON
jsonText = fileread(char(pipelineJsonPath));
pipeline = jsondecode(jsonText);

stepNames = fieldnames(pipeline);

%% Accumulate problems as a flat struct array 
rows = struct('step_name', {{}}, 'step_path', {{}}, 'function', {{}}, ...
              'param', {{}}, 'issue_type', {{}}, 'detail', {{}});
nRows = 0;

% Cache parsed function signatures so we don't re-parse the same file
% multiple times across universes that share a function (e.g. two
% "HRB_filter" branches).
sigCache = containers.Map('KeyType', 'char', 'ValueType', 'any');

%% Walk every step, including multiverse arrays 
for iStep = 1:numel(stepNames)
    stepKey  = stepNames{iStep};
    stepVal  = pipeline.(stepKey);

    % A step is either a single struct (one universe) or a struct array /
    % cell array (multiverse branch). Normalize to a cell array of structs
    % so the loop below is uniform.
    universes = local_normalize_universes(stepVal);

    for iU = 1:numel(universes)
        universe = universes{iU};

        if ~isfield(universe, 'function')
            continue  % malformed step — not this function's job to flag
        end
        funcName = char(universe.function);

        if isfield(universe, 'name')
            uName = char(universe.name);
        else
            uName = funcName;
        end

        if numel(universes) > 1
            stepPath = sprintf('%s[%d]', stepKey, iU);
        else
            stepPath = stepKey;
        end

        % Get (or parse+cache) the function's parameter signature 
        if isKey(sigCache, funcName)
            sig = sigCache(funcName);
        else
            sig = local_parse_arguments_block(funcName);
            sigCache(funcName) = sig; %#ok<NASGU>
        end

        if isempty(sig)
            % Function not found on path, or no arguments(Input) block
            % parsable — flag once and move on, nothing else to check.
            nRows = nRows + 1;
            rows(nRows).step_name  = uName;
            rows(nRows).step_path  = stepPath;
            rows(nRows).function   = funcName;
            rows(nRows).param      = '';
            rows(nRows).issue_type = 'function_not_found';
            rows(nRows).detail     = sprintf( ...
                'Could not locate or parse arguments(Input) block for "%s" (which(...) failed or no opt.* fields found).', ...
                funcName);
            continue
        end

        % Validate each param in this universe's "params" 
        if ~isfield(universe, 'params') || isempty(universe.params)
            continue  % no params to validate
        end
        userParams = universe.params;
        paramNames = fieldnames(userParams);

        for iP = 1:numel(paramNames)
            pName = paramNames{iP};
            pVal  = userParams.(pName);

            if ~isKey(sig, pName)
                nRows = nRows + 1;
                rows(nRows).step_name  = uName;
                rows(nRows).step_path  = stepPath;
                rows(nRows).function   = funcName;
                rows(nRows).param      = pName;
                rows(nRows).issue_type = 'unknown_param';
                rows(nRows).detail     = sprintf( ...
                    '"%s" is not a valid parameter for %s.', pName, funcName);
                continue
            end

            spec = sig(pName);
            [ok, issueType, detail] = local_check_value(pVal, spec);
            if ~ok
                nRows = nRows + 1;
                rows(nRows).step_name  = uName;
                rows(nRows).step_path  = stepPath;
                rows(nRows).function   = funcName;
                rows(nRows).param      = pName;
                rows(nRows).issue_type = issueType;
                rows(nRows).detail     = detail;
            end
        end
    end
end

%% Build output table
if nRows == 0
    R = table('Size', [0 6], ...
        'VariableTypes', {'string','string','string','string','string','string'}, ...
        'VariableNames', {'step_name','step_path','function','param','issue_type','detail'});
    fprintf('[HRB_validatePipelineParams] No problems found.\n');
    return
end

R = table( ...
    string({rows(1:nRows).step_name})',  ...
    string({rows(1:nRows).step_path})',  ...
    string({rows(1:nRows).function})',   ...
    string({rows(1:nRows).param})',      ...
    string({rows(1:nRows).issue_type})', ...
    string({rows(1:nRows).detail})',     ...
    'VariableNames', {'step_name','step_path','function','param','issue_type','detail'});

fprintf('[HRB_validatePipelineParams] %d problem(s) found:\n', nRows);
disp(R)

end

%% Helpers

function universes = local_normalize_universes(stepVal)
% Normalize a JSON step value into a cell array of structs, one per
% universe. Handles three shapes produced by jsondecode:
%   - single struct (1x1)             → {struct}
%   - struct array (Nx1, uniform JSON) → {struct, struct, ...}
%   - cell array (non-uniform JSON)    → {struct, struct, ...}
if iscell(stepVal)
    universes = stepVal(:)';
elseif isstruct(stepVal) && numel(stepVal) > 1
    universes = arrayfun(@(s) s, stepVal, 'UniformOutput', false);
else
    universes = {stepVal};
end
end

function sig = local_parse_arguments_block(funcName)
%local_parse_arguments_block  Parse a function's arguments(Input) block.
%
%  Returns a containers.Map keyed by parameter name (without the "opt."
%  prefix), valued by a struct:
%    .type        char    base MATLAB type token ('string','double','logical','cell','')
%    .memberList  cell    values from mustBeMember, or {} if not present
%    .rangeMin    double  min from mustBeInRange, or [] if not present
%    .rangeMax    double  max from mustBeInRange, or [] if not present
%    .mustBeInt   logical true if mustBeInteger present
%
%  Returns [] if the function cannot be located or no opt.* lines are found.

fpath = which(funcName);
if isempty(fpath)
    sig = [];
    return
end

txt = fileread(fpath);

% Extract the arguments(Input) ... end block. HERBERT functions also use
% arguments(Repeating) in some places (e.g. HRB_runPipeline) — we only
% care about the (Input) block since that's where opt.* params live.
blockMatch = regexp(txt, 'arguments\s*\(Input\)(.*?)\nend', 'tokens', 'once');
if isempty(blockMatch)
    % Some functions use plain "arguments ... end" without (Input) —
    % fall back to the first arguments...end block in the file.
    blockMatch = regexp(txt, 'arguments\b(.*?)\nend', 'tokens', 'once');
end
if isempty(blockMatch)
    sig = [];
    return
end
block = blockMatch{1};

% Match each "opt.Name <type> {validators} = default" line. The pattern is
% intentionally permissive: type, validators, and default are all optional
% on a per-line basis (e.g. "InputData" with no opt. prefix, or
% "opt.Save logical" with no validators/default).
lines = regexp(block, 'opt\.(\w+)([^\n]*)', 'tokens');

if isempty(lines)
    sig = [];
    return
end

sig = containers.Map('KeyType', 'char', 'ValueType', 'any');

for iL = 1:numel(lines)
    pName = lines{iL}{1};
    rest  = lines{iL}{2};

    spec = struct('type', '', 'memberList', {{}}, ...
                   'rangeMin', [], 'rangeMax', [], 'mustBeInt', false);

    % Base type: first bareword token after the param name (string, double,
    % logical, cell). Stop at '{' or '=' or end of line.
    typeMatch = regexp(rest, '^\s*(string|double|logical|cell)\b', 'tokens', 'once');
    if ~isempty(typeMatch)
        spec.type = typeMatch{1};
    end

    % mustBeMember(opt.X, ["a","b","c"]) or (opt.X, {'a','b'})
    memberMatch = regexp(rest, 'mustBeMember\([^,]+,\s*(\[[^\]]*\]|\{[^\}]*\})\)', 'tokens', 'once');
    if ~isempty(memberMatch)
        listStr = memberMatch{1};
        % Extract quoted strings (single or double) inside the list
        items = regexp(listStr, '["'']([^"'']*)["'']', 'tokens');
        spec.memberList = cellfun(@(c) c{1}, items, 'UniformOutput', false);
    end

    % mustBeInRange(opt.X, min, max)
    rangeMatch = regexp(rest, 'mustBeInRange\([^,]+,\s*([\-\d\.]+)\s*,\s*([\-\d\.]+)\)', 'tokens', 'once');
    if ~isempty(rangeMatch)
        spec.rangeMin = str2double(rangeMatch{1});
        spec.rangeMax = str2double(rangeMatch{2});
    end

    % mustBeInteger (no arguments)
    if ~isempty(regexp(rest, 'mustBeInteger', 'once'))
        spec.mustBeInt = true;
    end

    sig(pName) = spec; %#ok<NASGU>
end

end

function [ok, issueType, detail] = local_check_value(jsonVal, spec)
%local_check_value  Check a JSON-decoded value against a parsed param spec.
%
%  jsonVal can be: char/string, numeric scalar, numeric array, logical,
%  or cell array of strings (jsondecode produces different shapes
%  depending on the JSON literal).

ok = true; issueType = ''; detail = '';

% mustBeMember check (only applies to scalar-ish string/char values) 
if ~isempty(spec.memberList)
    valStr = local_to_char_if_scalar(jsonVal);
    if ~isempty(valStr)
        if ~ismember(valStr, spec.memberList)
            ok = false;
            issueType = 'invalid_value';
            detail = sprintf('"%s" is not a valid value. Allowed: %s.', ...
                valStr, strjoin(spec.memberList, ', '));
            return
        end
    end
    % If jsonVal is an array/cell (e.g. Scouts = list of ROI names),
    % mustBeMember on the whole array doesn't map to a simple per-element
    % check here — skip rather than produce false positives.
end

% mustBeInRange check (numeric only) 
if ~isempty(spec.rangeMin)
    if isnumeric(jsonVal) && isscalar(jsonVal)
        if jsonVal < spec.rangeMin || jsonVal > spec.rangeMax
            ok = false;
            issueType = 'invalid_value';
            detail = sprintf('Value %g is outside allowed range [%g, %g].', ...
                jsonVal, spec.rangeMin, spec.rangeMax);
            return
        end
    end
end

% mustBeInteger check 
if spec.mustBeInt
    if isnumeric(jsonVal) && isscalar(jsonVal)
        if jsonVal ~= floor(jsonVal)
            ok = false;
            issueType = 'invalid_value';
            detail = sprintf('Value %g must be an integer.', jsonVal);
            return
        end
    end
end

% Base type check (best-effort; skip cell/array params like Scouts) 
if ~isempty(spec.type) && ~iscell(jsonVal) && ~(isnumeric(jsonVal) && numel(jsonVal) > 1)
    switch spec.type
        case 'string'
            if ~(ischar(jsonVal) || isstring(jsonVal))
                ok = false;
                issueType = 'wrong_type';
                detail = sprintf('Expected string, got %s.', class(jsonVal));
                return
            end
        case 'double'
            if ~isnumeric(jsonVal)
                ok = false;
                issueType = 'wrong_type';
                detail = sprintf('Expected double, got %s.', class(jsonVal));
                return
            end
        case 'logical'
            if ~(islogical(jsonVal) || (isnumeric(jsonVal) && isscalar(jsonVal) && (jsonVal==0 || jsonVal==1)))
                ok = false;
                issueType = 'wrong_type';
                detail = sprintf('Expected logical, got %s.', class(jsonVal));
                return
            end
    end
end

end

function s = local_to_char_if_scalar(jsonVal)
% Return jsonVal as char if it is a scalar string/char, else ''.
if ischar(jsonVal)
    s = jsonVal;
elseif isstring(jsonVal) && isscalar(jsonVal)
    s = char(jsonVal);
else
    s = '';
end
end