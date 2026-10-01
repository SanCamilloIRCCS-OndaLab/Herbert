function agg = HRB_aggregateDegenerate(result, opt)
% HRB_aggregateDegenerate  Cross-subject consensus on degenerate universe pairs.
%
% Consumes the per-subject struct array from HRB_detectDegenerate and reports,
% for every universe pair, in what fraction of subjects the two universes fell
% in the SAME equivalence class. A pair is "robust" (structurally degenerate)
% only if it degenerates in every subject where BOTH universes are present.
%
% Failure handling: a subject missing one of the two universes (failed run)
% counts as NOT-APPLICABLE for that pair, never as non-degenerate. Denominator
% = subjects where both are present (coverage). This prevents a failed universe
% from silently deflating consensus.
%
% Robustness is asserted on EXACT within-subject grouping only. If any input
% element was grouped with Tolerance>0, the consensus is data-driven (weaker
% claim), and the function warns unless RequireExact=false.
%
% Usage:
%   result = HRB_detectDegenerate(T);            % T multi-subject
%   agg    = HRB_aggregateDegenerate(result);
%   agg.robustPairs                              % the publishable degeneracies
%
% Options:
%   Threshold (double in [0,1]): min consensus among present subjects to call
%       a pair robust. Default 1 (all present subjects agree).
%   MinCoverage (double in [0,1]): min fraction of subjects where both are
%       present. Default 1 (pair must exist in every subject). Lower to allow
%       partial-dataset claims.
%   RequireExact (logical): if true, warn when any input used Tolerance>0.
%       Default true.
%
% Output (scalar struct):
%   .universes     master universe list (union over subjects)
%   .subjects      subject labels
%   .nSubjects
%   .consensus     [nU x nU] degenerate-fraction among present subjects (NaN diag / never-co-present)
%   .coverage      [nU x nU] fraction of subjects where both present
%   .presentCount  [nU x nU] #subjects where both present
%   .degenCount    [nU x nU] #subjects where same class
%   .robustPairs   table: uni_a, uni_b, consensus, coverage
%   .criterion     struct(Threshold, MinCoverage, RequireExact, anyToleranced)
%
% Authors: Ettore Napoli, University of Bologna, 2026
% See also: HRB_DETECTDEGENERATE

arguments
    result
    opt.Threshold   (1,1) double {mustBeInRange(opt.Threshold,0,1)}   = 1
    opt.MinCoverage (1,1) double {mustBeInRange(opt.MinCoverage,0,1)} = 1
    opt.RequireExact (1,1) logical = true
end

if isempty(result)
    warning('HRB:EmptyResult','Empty detectDegenerate result.');
    agg = local_empty_agg(); return;
end
if numel(result) < 2
    warning('HRB:SingleSubject', ...
        'Only one subject: cross-subject consensus is trivial. Need >1 subject for a robustness claim.');
end

% Exact-only guard for the robustness claim
anyTol = any(arrayfun(@(r) r.criterion.Tolerance > 0, result));
if anyTol && opt.RequireExact
    warning('HRB:NonExactAggregation', ...
        ['Some subjects were grouped with Tolerance>0. Cross-subject consensus ', ...
         'is data-driven, not structural. Set RequireExact=false to silence.']);
end

subjects = arrayfun(@(r) r.subject, result);
nS = numel(result);

% Master universe list = union over subjects (stable)
universes = strings(0,1);
for s = 1:nS
    universes = [universes; result(s).universeLabels(:)]; %#ok<AGROW>
end
universes = unique(universes, 'stable');
nU = numel(universes);

% Per-subject group-id vector aligned to master indices (NaN = absent)
G = nan(nU, nS);
for s = 1:nS
    labels = result(s).universeLabels;
    groups = result(s).groups;
    [tf, loc] = ismember(labels, universes);   % local -> master
    for gi = 1:numel(groups)
        localIdx  = groups{gi};
        masterIdx = loc(localIdx(tf(localIdx)));
        G(masterIdx, s) = gi;
    end
end

presentCount = zeros(nU);
degenCount   = zeros(nU);
for s = 1:nS
    g = G(:, s);
    present = ~isnan(g);
    bothPresent = present & present';           % nU x nU
    sameGroup   = (g == g') & bothPresent;
    presentCount = presentCount + double(bothPresent);
    degenCount   = degenCount   + double(sameGroup);
end

consensus = degenCount ./ presentCount;         % NaN where never co-present
coverage  = presentCount ./ nS;
consensus(1:nU+1:end) = NaN;                     % blank diagonal

% Robust pairs: consensus >= Threshold AND coverage >= MinCoverage, upper tri
robustMask = (consensus >= opt.Threshold) & (coverage >= opt.MinCoverage);
robustMask = triu(robustMask, 1);
[ia, ib] = find(robustMask);
robustPairs = table(universes(ia), universes(ib), ...
    consensus(sub2ind([nU nU], ia, ib)), coverage(sub2ind([nU nU], ia, ib)), ...
    'VariableNames', {'uni_a','uni_b','consensus','coverage'});

agg = struct( ...
    'universes',     universes, ...
    'subjects',      subjects(:), ...
    'nSubjects',     nS, ...
    'consensus',     consensus, ...
    'coverage',      coverage, ...
    'presentCount',  presentCount, ...
    'degenCount',    degenCount, ...
    'robustPairs',   robustPairs, ...
    'criterion',     struct('Threshold',opt.Threshold, 'MinCoverage',opt.MinCoverage, ...
                            'RequireExact',opt.RequireExact, 'anyToleranced',anyTol));
end

%% ----
function agg = local_empty_agg()
agg = struct('universes',strings(0,1), 'subjects',strings(0,1), 'nSubjects',0, ...
    'consensus',[], 'coverage',[], 'presentCount',[], 'degenCount',[], ...
    'robustPairs',table(), 'criterion',struct('Threshold',1,'MinCoverage',1, ...
    'RequireExact',true,'anyToleranced',false));
end