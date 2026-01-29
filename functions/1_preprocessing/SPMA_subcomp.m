function [EEG] = SPMA_subcomp(EEG, opt)
% SPMA_subcomp removes independent components from EEG data. 
%
% Usage:
%   >>> EEG = SPMA_subcomp(EEG) %Removes flagged components
%   >>> EEG = SPMA_subcomp(EEG, 'Components', [8 13 21]) %Removes specific components
%   >>> EEG = SPMA_subcomp(EEG, 'Visualize', true) % Plots diff before removing components
%
% Parameters:
%   EEG (struct): EEG struct using EEGLAB struct system.
%
% Other Parameters:
%   Components (1xN vector): Vector listing the components to be removed.
%       If empty (default) it removes the flagged components
%       (EEG.reject.gcompreject). 
%
%   Keep (logical): If true, it keeps the listed components.Default is
%       false. 
%
%   Visualize (logical): If true, opens a GUI (pop_subcomp) to compare
%       data before and after removal. You must click "Accept" to proceed.
%       Default: false.
%
%   Save (logical): Whether to save the pruned datase
%
% See also: EEGLAB, pop_subcomp
%
% Authors: Ettore Napoli, University of Bologna, 2026

    arguments(Input)
        EEG struct
        % Optional
        opt.Components double {mustBeNumeric} = []
        opt.Keep logical = false
        opt.Visualize logical = false
        % Save Options
        opt.Save logical
        opt.SaveName string
        opt.OutputFolder string
        % Log options
        opt.LogEnabled logical
        opt.LogLevel double {mustBeInteger, mustBeInRange(opt.LogLevel, 0,6)}
        opt.LogToFile logical
        opt.LogFileDir string
        opt.LogFileName string
    end

    %% Constants
    module = "preprocessing";

    %% Parsing Arguments
    config = SPMA_loadConfig(module, "subcomp", opt);
    
    %% Logger
    logConfig = SPMA_loadConfig(module, "logging", opt);
    log = SPMA_loggerSetUp(module, logConfig);

    %% Check prerequisites
    if isempty(EEG.icaweights)
        error("SPMA: No ICA", "No ICs weight found for the current EEG structure. Cannot remove components.");
    end

    %% Find components to be removed
    comps_to_remove = [];

    if ~isempty(config.Components)
        if config.Keep
            all_comps = 1:size(EEG.icaweights, 1);
            comps_to_remove = setdiff(all_comps, config.Components);
        else
            comps_to_remove = config.Components;
        end
    else
        if isfield(EEG, 'reject') && isfield(EEG.reject, 'gcompreject') && any(EEG.reject.gcompreject)
           comps_to_remove = find(EEG.reject.gcompreject);
        else
            log.warning("No flagged components found. No components will be removed")
        end
    end

    %% Sync output path and Write .txt file containing the rejected 
    %   components' indices
    if ~isempty(comps_to_remove)
        try
            % Make sure output folder is consistent 
            if config.OutputFolder == ""
                nowstr = string(datetime("now", "Format","yyyyMMdd_HHmmss"));
                config.OutputFolder = fullfile("output", nowstr);
            end

            saveFolder = fullfile(config.OutputFolder, module);
            
            % Create folder
            if ~exist(saveFolder, 'dir')
                mkdir(saveFolder);
            end

            txtFileName = config.SaveName + "_rejectedComps.txt";
            txtFullPath = fullfile(saveFolder, txtFileName);
            
            writematrix(comps_to_remove(:)', txtFullPath, "Delimiter",',');

            log.info(sprintf("Saved list of %d components to %s", length(comps_to_remove), txtFileName));

        catch ME
            log.warn(sprintf("Could not save rejected components text file: %S", ME.message));
        end
    end

   %% Run pop_subcomp
   log.info(sprintf("Removing %d components from data", length(comps_to_remove)));

   try
       plot_flag = double(config.Visualize);

       if plot_flag
           log.info("Visual comparison requested. Waiting for user input in GUI");
       end

       EEG = pop_subcomp(EEG, config.Components, plot_flag, config.Keep );

       log.info("Components removed successfully");

   catch ME
       log.error(sprintf("Error during pop_subcomp execution: %S", ME.message));
       rethrow(ME);
   end

   %% Save dataset
    if config.Save
        logParams = unpackStruct(logConfig);
        % Important: We pass the 'config.OutputFolder' that we might have updated above
        SPMA_saveData(EEG, "Name", config.SaveName, "Folder", module, "OutputFolder", config.OutputFolder, logParams{:});
    end
end







            



