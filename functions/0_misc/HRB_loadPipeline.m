function pipeline = HRB_loadPipeline(pipelineFile, opt)
% HRB_LOADPIPELINE - Load a pipeline from one or multiple files. Allowed
% formats are json and yaml.
%
% Examples:
%     >>> HRB_loadPipeline(pipelineFile)
%     >>> HRB_loadPipeline(pipelineFile1, pipelineFile2, pipelineFile3)
%     >>> HRB_loadPipeline(pipelineFile, 'key', 'val')
%
% Parameters:
%    pipelineFile (string): A file with the pipeline. Allowed formats are
%    json or yaml. This parameter can be repeated multiple times.
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
        error(errmsg);
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