function HRB_bst_setComment(sFiles, fieldName, newComment)
% HRB_BST_SETCOMMENT - Set Comment on BST files AND in the DB index.
% bst_set + db_save alone does not persist across db_reload_database: the
% physical .mat is updated with bst_save first (see learnings).
%
% Inputs:
%   sFiles     - struct array returned by bst_process (uses .iStudy, .iItem)
%   fieldName  - study field holding the files: "Matrix" | "Timefreq" | "Result"
%   newComment - new Comment (connectivity modules: config.SaveName)
%
% Authors: Ettore Napoli, University of Bologna, 2026
arguments
    sFiles struct
    fieldName (1,1) string {mustBeMember(fieldName, ["Matrix","Timefreq","Result"])}
    newComment (1,1) string
end
newComment = char(newComment);
for iF = 1:numel(sFiles)
    [sStudy, iStudy] = bst_get('Study', sFiles(iF).iStudy);
    iItem = sFiles(iF).iItem;
    fullFilePath = file_fullpath(sStudy.(fieldName)(iItem).FileName);
    S = load(fullFilePath, '-mat');
    S.Comment = newComment;
    bst_save(fullFilePath, S, 'v6');
    sStudy.(fieldName)(iItem).Comment = newComment;
    bst_set('Study', iStudy, sStudy);
end
db_save();
end