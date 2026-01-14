function [EEG] = SPMA_iclabel(EEG, opt)
% SPMA_iclabel labels independnt components using ICLabel
%
% Examples:
%   >>> EEG = SPMA_iclabel(EEG)
%   >>> EEG = SPMA_iclabel(EEG, 'key', val)
%   >>> EEG = SPMA_iclabel(EEG, key = val)
%
% Parameters:
%       EEG (struct): EEG struct using EEGLAB struct system. ICs weights must
%       have been computed
% 
% Other parameters:
%       Version (string): 'default', 'lite', 'beta'
%       Save (logical): whether to save or not the dataset with labeled
%       components
%
% See also: EEGLAB, pop_iclabel
%
% Authors: Ettore Napoli, University of Bologna, 2026