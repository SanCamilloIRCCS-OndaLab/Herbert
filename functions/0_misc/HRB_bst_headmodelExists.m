function found = HRB_bst_headmodelExists(subjName, comment)
% HRB_BST_HEADMODELEXISTS - True if the subject already has a headmodel with
% this Comment in one of ITS studies. No try/catch: BST errors must surface
% (the old local copies masked a missing-argument bug in DUNeuro).
%
% Inputs:
%   subjName - BST subject name (EEG.etc.brainstorm.subject)
%   comment  - headmodel Comment to look for (case-insensitive)
% Output:
%   found - logical
%
% Authors: Ettore Napoli, University of Bologna, 2026
found = false;
[sSubject, ~] = bst_get('Subject', char(subjName), 1);   % isRaw: own file, not @default_subject
if isempty(sSubject), return; end
sStudies = bst_get('StudyWithSubject', sSubject.FileName);
for i = 1:numel(sStudies)
    if ~HRB_bst_isSubjectStudy(sStudies(i).FileName, sSubject.FileName), continue; end
    if ~isempty(sStudies(i).HeadModel) && any(strcmpi({sStudies(i).HeadModel.Comment}, comment))
        found = true;
        return;
    end
end
end