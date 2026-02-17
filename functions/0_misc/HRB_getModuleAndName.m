% HRB_GETMODULEANDNAME - Retrieve the name of a function and the module to
% which the function belongs. This function is intended to be called
% directly from a HRB function.
%
% Usage:
%     >> [module, name] = HRB_getModuleAndName()
%
% Inputs:
%    module  = [string] The module of the function
%    name    = [string] The name of the function
%
%
% Authors: Alessandro Tonin, IRCCS San Camillo Hospital, 2024
% 
% See also: DBSTACK

function [module,name] = HRB_getModuleAndName(stackFrame)
    arguments (Input)
        stackFrame int8 = 1
    end
    FUNC_PREFIX = "HRB_";

    % check who is the calling function from the stack
    st = dbstack(1,"-completenames");
    callingFunction = st(stackFrame).file;

    % split the path of the function
    func_filefolders = split(callingFunction, filesep);

    % get the name of the function
    name = func_filefolders{end};
    name = extractBetween(name,FUNC_PREFIX,".m");
    name = name{1};

    % get the name of the folder, i.e. the module
    module = func_filefolders{end-1};
    module = extractAfter(module, "_");

end

