% HRB_LOADDEPENDENCIES - Check if the dependencies required by Super Pipeline
% are already in the Matlab path. If not add to the path the missing ones.
% The full list of dependencies is:
%   EEGlab  v.2024.0
%
% Usage:
%     >> HRB_loadDependencies;
%     >> [oldPath newPath] = HRB_loadDependencies;
%
% Outputs:
%    errors = [string] List of errors
%
% Authors: Alessandro Tonin, IRCCS San Camillo Hospital, 2024

function errors = HRB_loadDependencies()

errors = [];

% DEPENDECIES_FOLDER = 'dependencies';
% if ~exist(DEPENDECIES_FOLDER, 'file')
%     mkdir(DEPENDECIES_FOLDER)
% end

% %% EEGLAB v2024.0
% EEGLAB_REQUIRED_VERSION = '2024.0';
% EEGLAB_DOWNLOAD_URL = 'https://github.com/sccn/eeglab/archive/refs/tags/2024.0.zip';

% % Check if it is already in the path
% [EEGLAB_OK, errors] = checkEEGLAB(EEGLAB_REQUIRED_VERSION);

% % Otherwise download it and add it to the path
% if ~EEGLAB_OK
%     [EEGLAB_folder, errors] = downloadEEGLAB(EEGLAB_DOWNLOAD_URL, DEPENDECIES_FOLDER);
%     if isempty(EEGLAB_folder)
%         warning("Error while downloading EEGlab")
%     else
%         addpath(EEGLAB_folder)
%     end
    
% end

%% EEGLAB
EEGLAB_folder = fullfile('external', 'EEGLAB');
addpath(EEGLAB_folder);
eeglab('nogui');

end


% function [existEEGLAB, errors] = checkEEGLAB(EEGLAB_version)
% % Check if EEGLAB (specified version) is in the path

% errors = [];
% existEEGLAB = false;

% try
%     if exist('eeglab', 'file')
%         % Find EEGlab folder
%         eeglab_path = which('eeglab');
%         eeglab_folder = fileparts(eeglab_path);
%         % Get the version using the internal function eeg_getversion
%         eeglab_func_getversion = fullfile(eeglab_folder, 'adminfunc', 'eeg_getversion.m');
%         if exist(eeglab_func_getversion, 'file')
%             eeglab_version = run(eeglab_func_getversion);
%             if eeglab_version == EEGLAB_version
%                 existEEGLAB = true;
%             end
%         end
%     end
% catch ME
%     errors = [errors; ME];
% end

% end

% function [EEGlabFolder, errors] = downloadEEGLAB(url, folder)
% % Download EEGLAB in the required folder

% errors = [];
% EEGlabFolder = '';
% try
%     filename = fullfile(folder, 'eeglab.zip');
%     zipfile = websave(filename, url);
%     filenames=unzip(zipfile, folder);
%     delete(zipfile)
%     EEGlabFolder = filenames{1};
% catch ME
%     errors = [errors; ME];
% end

% end
