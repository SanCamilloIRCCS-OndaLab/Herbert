function result = HRB_detectDegenerate(T, opt)
% HRB_detectDegenerate  Partition multiverse universes into equivalence
% classes by identical FC output (exact or within tolerance).
%
% Consumes the long-format connectivity table from HRB_collectFC and groups
% universes whose full set of from-to-band values coincide. Reports one
% representative per class = the non-redundant subset worth interpreting.
%
% Degeneracy is assessed PER SUBJECT (a universe's value vector is subject
% specific). Multi-subject T -> struct array, one element per subject.
%
% Usage:
%   result = HRB_detectDegenerate(T);
%   result = HRB_detectDegenerate(T, 'Tolerance', 1e-10);
%   result = HRB_detectDegenerate(T, 'Manifest', HRB_universeManifest(outFolder));
%
% Input:
%   T  - table from HRB_collectFC, columns in order:
%        [subject, universe_label, roi_from, roi_to, band, value]
%        (column ORDER is used, not names; override via opt.Cols)
%
% Options:
%   Tolerance (double>=0): same class if max abs diff over all values <=Tol.
%       0 = exact (structural degeneracy). Tol>0 uses single-linkage
%       (A~B,B~C => same class even if A,C exceed Tol; "close" isn't
%       transitive). Default 0.
%   Manifest (table): HRB_universeManifest output. If given, each class with
%       >1 member is annotated with which pipeline axis collapsed. Default [].
%   Cols (1x6 double): column indices [subj,uni,from,to,band,val].
%       Default [1 2 3 4 5 6].
%
% Output (scalar struct, or struct array if >1 subject):
%   .subject .universeLabels .groups .representative
%   .nUniverses .nDistinct .pairwiseMaxDiff .axisCollapse .criterion
%
% Authors: Ettore Napoli, University of Bologna, 2026
% See also: HRB_COLLECTFC, HRB_UNIVERSEMANIFEST

arguments
    T
    opt.Tolerance (1,1) double {mustBeNonnegative} = 0
    opt.Manifest = []
    opt.Cols (1,6) double = [1 2 3 4 5 6]
end

if iscell(T), T = cell2table(T); end

c    = opt.Cols;
subj = string(T{:, c(1)});
uni  = string(T{:, c(2)});
key  = string(T{:, c(3)}) + "|" + string(T{:, c(4)}) + "|" + string(T{:, c(5)});
val  = double(T{:, c(6)});

if isempty(subj)
    warning('HRB:EmptyTable', 'Empty connectivity table.');
    result = local_empty_result(); return;
end

subjList = unique(subj, 'stable');
nS = numel(subjList);
result = repmat(local_empty_result(), nS, 1);
for s = 1:nS
    m = subj == subjList(s);
    result(s) = local_group_one_subject(subjList(s), uni(m), key(m), val(m), opt);
end
if nS == 1, result = result(1); end
end


%% ---- per-subject grouping ----------------------------------------------
function r = local_group_one_subject(subjLabel, uni, key, val, opt)

universeLabels = unique(uni, 'stable');
nU = numel(universeLabels);
masterKeys = unique(key, 'stable');
[~, keyIdx] = ismember(key, masterKeys);

V       = nan(nU, numel(masterKeys));
present = false(nU, numel(masterKeys));
for u = 1:nU
    rows = uni == universeLabels(u);
    ki = keyIdx(rows); vv = val(rows);
    if numel(unique(ki)) ~= numel(ki)
        warning('HRB:DupKey', 'Universe "%s" has duplicate from-to-band rows.', ...
            universeLabels(u));
    end
    V(u, ki) = vv;  present(u, ki) = true;
end

D = zeros(nU);
for a = 1:nU
    for b = a+1:nU
        d = local_pair_diff(V(a,:), V(b,:), present(a,:), present(b,:));
        D(a,b) = d; D(b,a) = d;
    end
end

groups = local_components(D <= opt.Tolerance);
rep    = cellfun(@(g) g(1), groups);

r = struct( ...
    'subject',         subjLabel, ...
    'universeLabels',  universeLabels, ...
    'groups',          {groups}, ...
    'representative',  rep, ...
    'nUniverses',      nU, ...
    'nDistinct',       numel(groups), ...
    'pairwiseMaxDiff', D, ...
    'axisCollapse',    {{}}, ...
    'criterion',       struct('Tolerance', opt.Tolerance));

if ~isempty(opt.Manifest)
    r.axisCollapse = local_axis_collapse(groups, universeLabels, opt.Manifest);
end
end


%% ---- helpers -----------------------------------------------------------
function d = local_pair_diff(va, vb, pa, pb)
% Max abs diff with presence + NaN semantics.
if ~isequal(pa, pb), d = Inf; return; end       % different keyset => distinct
va = va(pa); vb = vb(pb);
nanA = isnan(va); nanB = isnan(vb);
df = abs(va - vb);
df(nanA & nanB)     = 0;                          % both NaN => same output
df(xor(nanA, nanB)) = Inf;                         % one NaN => distinct
d = max(df);
if isempty(d), d = 0; end
end

function groups = local_components(adj)
n = size(adj,1); parent = 1:n;
for i = 1:n
    for j = i+1:n
        if adj(i,j)
            ri = local_find(parent,i); rj = local_find(parent,j);
            if ri ~= rj, parent(ri) = rj; end
        end
    end
end
roots = arrayfun(@(k) local_find(parent,k), 1:n);
[~,~,gid] = unique(roots, 'stable');
groups = arrayfun(@(g) find(gid==g)', 1:max(gid), 'UniformOutput', false);
end

function r = local_find(parent, i)
while parent(i) ~= i, i = parent(i); end
r = i;
end

function desc = local_axis_collapse(groups, universeLabels, manifest)
axisCols = setdiff(manifest.Properties.VariableNames, {'universe_label'}, 'stable');
desc = repmat("distinct", 1, numel(groups));
for g = 1:numel(groups)
    idx = groups{g};
    if numel(idx) < 2, continue; end
    [tf, loc] = ismember(universeLabels(idx), manifest.universe_label);
    if ~all(tf), desc(g) = "unmatched-in-manifest"; continue; end
    varying = strings(1,0);
    for a = 1:numel(axisCols)
        if numel(unique(string(manifest{loc, axisCols{a}}))) > 1
            varying(end+1) = string(axisCols{a}); %#ok<AGROW>
        end
    end
    if isempty(varying), desc(g) = "identical-label(?)";
    else, desc(g) = "collapsed axis: " + strjoin(varying, ", "); end
end
desc = cellstr(desc);
end

function r = local_empty_result()
r = struct('subject',"", 'universeLabels',strings(0,1), 'groups',{{}}, ...
    'representative',[], 'nUniverses',0, 'nDistinct',0, ...
    'pairwiseMaxDiff',[], 'axisCollapse',{{}}, 'criterion',struct('Tolerance',0));
end