function tf = HRB_bst_isSubjectStudy(studyFileName, subjectFileName)
% HRB_BST_ISSUBJECTSTUDY - True if a BST study belongs to the subject.
% Folder match, not substring: subject 'Y1' must not capture 'Y10/...'.
%
% subjectFileName must be the subject's OWN file:
%   [sSubject, ~] = bst_get('Subject', subjName, 1);   % isRaw = 1
% Without isRaw, a subject using the default anatomy returns
% '@default_subject/brainstormsubject.mat' (bst_get.m, case 'Subject'),
% which matches no study: that is an error here, not a silent false.
%
% Inputs:
%   studyFileName   - sStudy.FileName       (e.g. 'Y01/RS/brainstormstudy.mat')
%   subjectFileName - raw sSubject.FileName (e.g. 'Y01/brainstormsubject.mat')
% Output:
%   tf - logical, true if the study lives in the subject's folder
%
% Authors: Ettore Napoli, University of Bologna, 2026
subjDir = fileparts(strrep(char(subjectFileName), '\', '/'));
if strcmp(subjDir, '@default_subject')
    error("HRB:DefaultSubjectFile", ...
        "HRB_bst_isSubjectStudy: got the default-anatomy subject file. Use bst_get('Subject', name, 1) (isRaw).");
end
tf = startsWith(strrep(char(studyFileName), '\', '/'), [subjDir '/']);
end