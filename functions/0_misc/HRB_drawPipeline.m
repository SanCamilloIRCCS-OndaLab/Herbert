% HRB_DRAWPIPELINE - Draw the pipeline in a block diagram using graphviz
% library. Library must be installed in the system, or it will use the
% online service https://quickchart.io.
%
% Usage:
%     >> HRB_drawPipeline(pipeline);
%     >> HRB_drawPipeline(pipeline, saveName);
%     >> HRB_drawPipeline(pipeline, saveName, 'key', val);
%
% Inputs:
%    pipeline = [struct] The pipeline already loaded as struct
%    saveName = [string] The saving name (default: pipeline)
%
% Optional inputs:
%    SaveDotFile = [logical] Whether to save or not the .dot file (graphviz
%           language)
%    ImageFormat = [list(string)] One or more formats. Allowed values "svg"
%           and "png".
%    ImageWidth = [int] The width of the image (used only if format is png)
%    ImageHeight = [int] The height of the image (used only if format is png)
%
% Authors: Alessandro Tonin, IRCCS San Camillo Hospital, 2024
% 
% See also:

function HRB_drawPipeline(pipeline, saveName, opt)
    arguments
        pipeline struct
        saveName string = "pipeline"
        % Optional
        opt.SaveDotFile logical
        opt.ImageFormat string {mustBeMember(opt.ImageFormat, ["svg", "png"])}
        opt.ImageWidth double {mustBeInteger, mustBePositive}
        opt.ImageHeight double {mustBeInteger, mustBePositive}
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
    imgOptions = HRB_loadConfig("general", "image", opt);

    %% Logger
    logOptions = struct( ...
        "LogFileDir", config.OutputFolder);
    log = HRB_loggerSetUp("general", logOptions);

    %% Generate graph
    log.info("Generating diagram of pipeline using graphviz language")
    graphDot = sprintf("digraph G {\n");
    graphDot = graphDot + sprintf("node [shape=box];\n");

    nodes = "";
    edges = "";

    steps = fieldnames(pipeline);
    prev_universes = {};
    for n_step = 1:length(steps)
        step = pipeline.(steps{n_step});
        curr_universes = {};
        for n_universe = 1:length(step)
            if isstruct(step)
                universe = getName(step(n_universe), "HRB_");
            else %is a cell array
                universe = getName(step{n_universe}, "HRB_");
            end
            curr_universes{n_universe} = universe;
            node = sprintf('%s [label="%s"];\n', universe, universe);
            nodes = nodes + node;
        end

        for pu = 1:length(prev_universes)
            for cu = 1:length(curr_universes)
                edge = sprintf("%s -> %s;\n", prev_universes{pu}, curr_universes{cu});
                edges = edges + edge;
            end
        end

        prev_universes = curr_universes;
    end

    graphDot = graphDot + nodes + edges + "}";
    
    log.debug(sprintf("Diagram:\n%s", graphDot))

    if imgOptions.SaveDotFile
        saveNameExt = sprintf("%s.dot", saveName);
        imgFullPath = fullfile(config.OutputFolder,saveNameExt);
        
        fileID = fopen(imgFullPath, "w");
        fprintf(fileID, graphDot);
        fclose(fileID);
        
        log.info(sprintf("Graph saved in: %s", imgFullPath))
    end

    %% Query
    % Before we should try locally

    if haveInet()
        endpoint = "https://quickchart.io/graphviz";
    
        for n_format = 1:length(imgOptions.ImageFormat)
            format = imgOptions.ImageFormat(n_format);
            query = sprintf("%s?format=%s", endpoint, format);
            if imgOptions.ImageWidth > 0
                query = query + sprintf("&width=%d",imgOptions.ImageWidth);
            end
            if imgOptions.ImageHeight > 0
                query = query + sprintf("&height=%d",imgOptions.ImageHeight);
            end
        
            query = query + sprintf("&graph=%s", graphDot);
        
            log.info(sprintf("Making the query: %s", query))
    
            saveNameExt = sprintf("%s.%s", saveName, format);
            imgFullPath = fullfile(config.OutputFolder,saveNameExt);
            
            websave(imgFullPath, query);
            log.info(sprintf("Graph saved in: %s", imgFullPath))
        end
    else
        log.error("No internet connection")
        if ~imgOptions.SaveDotFile
            log.warning("We save the pipeline in .dot file, you can generate the image locally by installing GraphViz, or you can use an online (free and open source) service, for example https://dreampuf.github.io/GraphvizOnline ")
    
            saveNameExt = sprintf("%s.dot", saveName);
            imgFullPath = fullfile(config.OutputFolder,saveNameExt);
            
            fileID = fopen(imgFullPath, "w");
            fprintf(fileID, graphDot);
            fclose(fileID);
            
            log.info(sprintf("Graph saved in: %s", imgFullPath))
        end
    end

end

function name = getName(s, removePrefix)
    arguments (Input)
        s struct
        removePrefix string = ""
    end
    arguments (Output)
        name string
    end
    if isfield(s, "name")
        name = s.name;
    else
        name = s.function;
        if startsWith(name, removePrefix)
            name = extractAfter(name, removePrefix);
        end
    end
end

function tf = haveInet()
  tf = false;
  try
    address = java.net.InetAddress.getByName('8.8.8.8');
    tf = true;
  end
end
