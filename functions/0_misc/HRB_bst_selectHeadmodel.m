function HRB_bst_selectHeadmodel(subjName, bstInfo, log)
% HRB_BST_SELECTHEADMODEL - Make THIS universe's headmodel the selected one
% (iHeadModel) in EVERY study of the subject, before an inverse step.
%
% process_inverse_2018 on a condition whose study has no
% local headmodel falls back to an arbitrary BST default; propagating the
% entry to all the subject's studies prevents branches with different
% headmodels from producing identical kernels.
%
% Headmodel identity: bstInfo.headmodel_comment (written by the headmodel
% modules). Legacy EEG structs without it use the old method->comment map.
% A missing subject/headmodel is an ERROR: a silent BST default would create
% artefactual degenerate universes.
%
% Inputs:
%   subjName - BST subject name (EEG.etc.brainstorm.subject)
%   bstInfo  - EEG.etc.brainstorm
%   log      - logger object
%
% Authors: Ettore Napoli, University of Bologna, 2026

if isfield(bstInfo, 'headmodel_comment') && ~isempty(bstInfo.headmodel_comment)
    bstComment = char(bstInfo.headmodel_comment);
else
    switch char(bstInfo.headmodel_method)   % legacy runs
        case '3-ShellSphere', bstComment = '3_Shell';
        case 'OpenMEEG',      bstComment = 'BEM';
        case 'DUNeuro',       bstComment = 'FEM';
        otherwise,            bstComment = char(bstInfo.headmodel_method);
    end
end

[sSubject, ~] = bst_get('Subject', char(subjName), 1);   % isRaw: own file, not @default_subject
if isempty(sSubject)
    error("HRB:SubjectNotFound", "HRB_bst_selectHeadmodel: subject '%s' not found.", subjName);
end
[sStudies, iStudies] = bst_get('StudyWithSubject', sSubject.FileName);

% Step 1: find the HeadModel entry in the study that owns it
hmEntry = [];
for iS = 1:numel(sStudies)
    if ~HRB_bst_isSubjectStudy(sStudies(iS).FileName, sSubject.FileName), continue; end
    if isempty(sStudies(iS).HeadModel), continue; end
    iHM = find(strcmpi({sStudies(iS).HeadModel.Comment}, bstComment), 1);
    if ~isempty(iHM)
        hmEntry = sStudies(iS).HeadModel(iHM);
        break;
    end
end
if isempty(hmEntry)
    error("HRB:HeadmodelNotFound", "Headmodel '%s' not found for subject '%s'.", ...
        bstComment, subjName);
end

% Step 2: propagate iHeadModel to ALL studies of the subject
nSet = 0;
for iS = 1:numel(sStudies)
    if ~HRB_bst_isSubjectStudy(sStudies(iS).FileName, sSubject.FileName), continue; end
    if isempty(sStudies(iS).HeadModel)
        sStudies(iS).HeadModel  = hmEntry;
        sStudies(iS).iHeadModel = 1;
    else
        iHM = find(strcmpi({sStudies(iS).HeadModel.Comment}, bstComment), 1);
        if ~isempty(iHM)
            sStudies(iS).iHeadModel = iHM;
        else
            sStudies(iS).HeadModel(end+1) = hmEntry;
            sStudies(iS).iHeadModel = numel(sStudies(iS).HeadModel);
        end
    end
    bst_set('Study', iStudies(iS), sStudies(iS));
    nSet = nSet + 1;
end
db_save();
log.info(sprintf("Headmodel '%s' propagated to %d studies for '%s'.", ...
    bstComment, nSet, subjName));
end