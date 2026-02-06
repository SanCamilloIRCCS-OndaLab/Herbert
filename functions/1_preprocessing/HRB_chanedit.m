function [EEG] = HRB_chanedit(EEG, opt)
% HRB_CHANEDIT - edit channel file
%
% Usage:
%     >> [EEG] = HRB_chanedit(chan_file)
%     >> [EEG] = HRB_chanedit(chan_file, 'key', val) 
%     >> [EEG] = HRB_chanedit(chan_file, key=val) 
%
% Inputs:
%    EEG = [struct] EEG struct using EEGLAB structure system
%    chan_file = [string] channel file path OR template
%    filetype = 
%     
% Outputs:
%    EEG = [struct] EEG struct using EEGLAB structure system
%
% Authors: Sara Lago, IRCCS San Camillo Hospital, 2024
% 
% See also: EEGLAB, POP_CHANEDIT

    arguments (Input)
        EEG struct
        opt.Method string {mustBeMember(opt.Method, ["template", "coregistration"])}
        opt.Template string {mustBeMember(opt.Template, ["","besa_egi/32ch_quikcap.sfp","besa_egi/EGI129.elp","besa_egi/EGI65.elp",...
            "besa_egi/GSN129.sfp","besa_egi/bti148.elp","besa_egi/msep.elp",...
            "eeglab/EGI-sensorplacement2.xyz","eeglab/Standard-10-10-Cap33.ced","eeglab/Standard-10-10-Cap47.ced",...
            "eeglab/Standard-10-20-Cap19.ced","eeglab/Standard-10-20-Cap25.ced","eeglab/Standard-10-20-Cap81.ced",...
            "eeglab/chan14_layout.locs","eeglab/chan31_layout.loc","eeglab/chan32_layout.locs","eeglab/chan61fms11_layout.loc",...
            "eeglab/dummy_electrocap71_layout.locs","eeglab/dummy_quikcap32_layout.locs","eeglab/easycap_montage11_layout.loc",...
            "neuroscan/NuAmps40.DAT","neuroscan/cap128.asc","neuroscan/cap128.dat","neuroscan/quik128.DAT","neuroscan/xyz129.dat",...
            "others/galvaniNSL.DAT",...
            "philips_neuro/0_2AverageNet128_v1.sfp","philips_neuro/0_2AverageNet32_v1.sfp","philips_neuro/0_2AverageNet64_v1.sfp",...
            "philips_neuro/2_9AverageNet128_v1.sfp","philips_neuro/2_9AverageNet32_v1.sfp","philips_neuro/2_9AverageNet64_v1.sfp",...
            "philips_neuro/9_18AverageNet128_v1.sfp","philips_neuro/9_18AverageNet256_v1.sfp","philips_neuro/9_18AverageNet32_v1.sfp",...
            "philips_neuro/9_18AverageNet64_v1.sfp","philips_neuro/AdultAverageNet128_v1.sfp","philips_neuro/AdultAverageNet256_v1.sfp",...
            "philips_neuro/AdultAverageNet32_v1.sfp","philips_neuro/AdultAverageNet64_v1.sfp","philips_neuro/GSN-HydroCel-128.sfp",...
            "philips_neuro/GSN-HydroCel-129.sfp","philips_neuro/GSN-HydroCel-256.sfp","philips_neuro/GSN-HydroCel-257.sfp",...
            "philips_neuro/GSN-HydroCel-32.sfp","philips_neuro/GSN-HydroCel-64_1.0.sfp","philips_neuro/GSN-HydroCel-65_1.0.sfp",...
            "philips_neuro/GSN128.sfp","philips_neuro/GSN129.sfp","philips_neuro/GSN256.sfp","philips_neuro/GSN257.sfp",...
            "philips_neuro/GSN64v2_0.sfp","philips_neuro/GSN65v2_0.sfp","philips_neuro/egi128_GSN.sfp","philips_neuro/egi128_GSN_HydroCel.sfp",...
            "philips_neuro/egi256_GSN.sfp","philips_neuro/egi256_GSN_HydroCel.sfp","philips_neuro/egi64_GSN_HydroCel_v1_0.sfp",...
            "philips_neuro/egi64_GSN_v1_0.sfp","philips_neuro/egi64_GSN_v2_0.sfp",...
            "polhemus/eetrak124.elc","polhemus/electrocap72.elp"])}
        opt.File string
        opt.EEGLAB (1,:) cell
        % Save options
        opt.Save logical
        opt.SaveName string
        opt.OutputFolder string
        % Log options
        opt.LogEnabled logical
        opt.LogLevel double {mustBeInteger,mustBeInRange(opt.LogLevel,0,6)}
        opt.LogToFile logical
        opt.LogFileDir string
        opt.LogFileName string
    end

    %% Constants
    module = "preprocessing";

    %% Parsing arguments
    config = HRB_loadConfig(module, "chanedit", opt);

    %% Logger
    logConfig = HRB_loadConfig(module, "logging", opt);
    log = HRB_loggerSetUp(module, logConfig);

    %% Editing channel file
    log.info(sprintf("Editing channel file: %s", opt.chan_file))

    switch opt.method

        case "template"
            
            eeglabp = fileparts(which('eeglab.m'));
            channel_file_path = fullfile(eeglabp, 'functions', 'supportfiles', 'channel_location_files', opt.template);
            EEG=pop_chanedit(EEG, 'lookup', channel_file_path);

        case "coregistration"

            [~,~,file_ext] = fileparts(opt.chan_file);
            EEG=pop_chanedit(EEG, 'load',{opt.chan_file,'filetype',file_ext});

        otherwise

    end

    %% Save
    if config.Save
        logParams = unpackStruct(logConfig);
        HRB_saveData(EEG, "Name", config.SaveName, "Folder", module, "OutputFolder", config.OutputFolder, logParams{:});
    end

end