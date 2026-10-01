function files = HRB_writeQCPerUniverse(QC, opt)
%HRB_writeQCPerUniverse  Split a long QC table into one CSV per universe.
%
%  Takes the long QC table from HRB_collectQCFromDisk (or HRB_collectQC_new)
%  — one row per universe x subject — and writes ONE summary CSV per universe,
%  with all subjects as rows. Does NOT re-read disk: it only splits and writes
%  what QC already holds, so the numbers match the full table exactly and it is
%  fast (no /mnt/raid access, just the CSV writes).
%
%  The universe key column is auto-detected: "universe_id" (collectQCFromDisk)
%  or "universe" (collectQC_new). The subject column ("subject" or "subj_id")
%  is auto-detected for sorting. Every column is written through as-is.
%
%  USAGE
%    P = HRB_universePathsFromDisk(runRoot, manifest, Report=reportDisk);
%    Q = HRB_collectQCFromDisk(runRoot, P);
%    % one CSV per universe, into the reorg's universe folders:
%    HRB_writeQCPerUniverse(Q, IntoReorg="/path/PreprocOld_by-universe");
%    % or into a standalone folder:
%    HRB_writeQCPerUniverse(Q, OutputDir="/path/qc_by_universe");
%
%  NAME-VALUE (give at least one destination)
%    OutputDir   string   write <OutputDir>/<universe>.csv (folder created)
%    IntoReorg   string   write <IntoReorg>/<universe>/qc_<universe>.csv,
%                         only where the universe folder already exists there
%                         (produced by HRB_reorgByUniverse); missing ones are
%                         skipped with a warning
%    UniverseCol string   force the universe key column (default: auto-detect)
%    SortBy      string   row sort column (default: auto-detect subject col)
%
%  OUTPUT  files  string array of CSV paths written
%
% Author: Ettore Napoli - University of Bologna, 2026

arguments (Input)
    QC              table
    opt.OutputDir   (1,1) string = ""
    opt.IntoReorg   (1,1) string = ""
    opt.UniverseCol (1,1) string = ""
    opt.SortBy      (1,1) string = ""
end

if strlength(opt.OutputDir) == 0 && strlength(opt.IntoReorg) == 0
    error("HRB:NoDestination", "Give at least one of OutputDir or IntoReorg.");
end

vars = string(QC.Properties.VariableNames);

% --- auto-detect the universe key column ---
if strlength(opt.UniverseCol) > 0
    uCol = opt.UniverseCol;
else
    cand = ["universe_id","universe"];
    uCol = cand(find(ismember(cand, vars), 1));
    if isempty(uCol)
        error("HRB:NoUniverseCol", ...
            "No 'universe_id' or 'universe' column in QC; pass UniverseCol.");
    end
end

% --- auto-detect the subject column for sorting ---
if strlength(opt.SortBy) > 0
    sCol = opt.SortBy;
else
    cand = ["subject","subj_id"];
    hit  = cand(ismember(cand, vars));
    if isempty(hit), sCol = ""; else, sCol = hit(1); end
end

if strlength(opt.OutputDir) > 0 && ~isfolder(opt.OutputDir)
    mkdir(opt.OutputDir);
end

uids  = unique(string(QC.(uCol)), "stable");
files = strings(0,1);

for u = 1:numel(uids)
    uid = uids(u);
    sub = QC(string(QC.(uCol)) == uid, :);

    if strlength(sCol) > 0 && ismember(sCol, string(sub.Properties.VariableNames))
        sub = sortrows(sub, char(sCol));
    end

    if strlength(opt.OutputDir) > 0
        f = fullfile(char(opt.OutputDir), char(uid) + ".csv");
        writetable(sub, f);
        files(end+1,1) = string(f); %#ok<AGROW>
    end

    if strlength(opt.IntoReorg) > 0
        uniDir = fullfile(char(opt.IntoReorg), char(uid));
        if isfolder(uniDir)
            f = fullfile(uniDir, "qc_" + uid + ".csv");
            writetable(sub, char(f));
            files(end+1,1) = string(f); %#ok<AGROW>
        else
            warning("HRB:UniverseFolderMissing", ...
                "no folder for %s under %s — skipped", uid, opt.IntoReorg);
        end
    end
end

fprintf("[HRB_writeQCPerUniverse] %d universes -> %d files written\n", ...
    numel(uids), numel(files));
end