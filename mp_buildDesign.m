function T = mp_buildDesign(cfg, effector, runIdx)
%MP_BUILDDESIGN  Build pseudo-random trial order and pre-compute timeline
%
%   T = mp_buildDesign(cfg, effector, runIdx)
%
%   Creates a struct array (1×nTrials) with all onset times pre-computed
%   before the run starts. This ensures ZERO scheduling computation
%   during real-time execution.
%
%   Each trial contains:
%     - Condition ('grasp'/'touch') and effector ('hand'/'tool')
%     - Jittered plan duration (5.5 ± 0.5 s, uniform)
%     - Trigger codes for cue and go events
%     - Planned onset times (relative to run epoch t0)
%     - Placeholders for actual onsets (filled by mp_executeRun)
%
%   PSEUDO-RANDOMIZATION:
%     - Equal count of each condition (10 grasp + 10 touch)
%     - No more than cfg.maxConsec (default 3) consecutive same condition
%     - Shuffle-and-check with incremental fallback (guaranteed)
%
%   INPUTS:
%     cfg      — Configuration struct from mp_config()
%     effector — 'hand' or 'tool'
%     runIdx   — Run number (1-based)
%
%   OUTPUTS:
%     T — Struct array (1 × nTrials) with planned timeline
%
%   See also mp_config, mp_executeRun, motor_planning

    trialOrder = buildTrialOrder(cfg);
    n = numel(trialOrder);
    T = repmat(trialTemplate(), 1, n);

    t = cfg.baselineInit;   % first trial starts after initial baseline

    for i = 1:n
        cond = trialOrder{i};
        jit  = (rand * 2 - 1) * cfg.planJitter;   % uniform [-0.5, +0.5]
        planD = max(2.0, cfg.planDur + jit);       % floor at 2 s

        T(i).trialIndex   = i;
        T(i).condition    = cond;
        T(i).effector     = effector;
        T(i).runNumber    = runIdx;
        T(i).randomSeed   = cfg.randomSeed;
        T(i).jitter       = round(jit, 4);
        T(i).planDuration = round(planD, 4);

        % Trigger codes
        if strcmp(cond, 'grasp')
            T(i).cueCode = cfg.codes.cue_grasp;
            T(i).goCode  = cfg.codes.go_grasp;
        else
            T(i).cueCode = cfg.codes.cue_touch;
            T(i).goCode  = cfg.codes.go_touch;
        end

        % Planned onsets relative to t0
        T(i).previewOnset = round(t, 6);
        T(i).cueOnset     = round(t + cfg.previewDur, 6);
        T(i).goOnset      = round(t + cfg.previewDur + planD, 6);
        T(i).executeOnset = round(t + cfg.previewDur + planD, 6);
        T(i).itiOnset     = round(t + cfg.previewDur + planD + cfg.execDur, 6);
        T(i).trialEnd     = round(t + cfg.previewDur + planD + cfg.execDur + cfg.itiDur, 6);

        t = T(i).trialEnd;
    end

    fprintf('[OK] Timeline: %d trials | %.1f s (%.1f min)\n', ...
        n, T(end).trialEnd + cfg.baselineFinal, ...
        (T(end).trialEnd + cfg.baselineFinal) / 60);
end


% =====================================================================
%  LOCAL FUNCTIONS
% =====================================================================

function order = buildTrialOrder(cfg)
%BUILDTRIALORDER  Pseudo-random with max-consecutive constraint
%   Phase 1: shuffle-and-check (fast, usually succeeds within 100 attempts)
%   Phase 2: incremental construction (guaranteed, slower)
    items  = cfg.conditions;
    reps   = cfg.nTrialsPerCond;
    maxC   = cfg.maxConsec;
    nTotal = numel(items) * reps;
    pool   = repmat(items, 1, reps);

    % Phase 1
    for attempt = 1:10000
        order = pool(randperm(nTotal));
        if isValidOrder(order, maxC), return; end
    end

    % Phase 2 (fallback)
    remaining = containers.Map(items, num2cell(repmat(reps, 1, numel(items))));
    order = cell(1, nTotal);
    for i = 1:nTotal
        avail = {};
        for ci = 1:numel(items)
            it = items{ci};
            if remaining(it) <= 0, continue; end
            if i > maxC && all(strcmp(order(i-maxC:i-1), it)), continue; end
            avail{end+1} = it; %#ok<AGROW>
        end
        if isempty(avail)
            avail = items(cellfun(@(x) remaining(x) > 0, items));
        end
        chosen = avail{randi(numel(avail))};
        order{i} = chosen;
        remaining(chosen) = remaining(chosen) - 1;
    end
end


function ok = isValidOrder(seq, maxC)
%ISVALIDORDER  True if no condition appears more than maxC times in a row
    ok = true;
    runLen = 1;
    for i = 2:numel(seq)
        if strcmp(seq{i}, seq{i-1})
            runLen = runLen + 1;
            if runLen > maxC, ok = false; return; end
        else
            runLen = 1;
        end
    end
end


function tr = trialTemplate()
%TRIALTEMPLATE  Empty struct with all trial fields initialized
    tr.trialIndex        = 0;
    tr.condition         = '';
    tr.effector          = '';
    tr.runNumber         = 0;
    tr.randomSeed        = 0;
    tr.jitter            = 0;
    tr.planDuration      = 0;
    tr.cueCode           = 0;
    tr.goCode            = 0;
    % Planned onsets (filled at design time)
    tr.previewOnset      = 0;
    tr.cueOnset          = 0;
    tr.goOnset           = 0;
    tr.executeOnset      = 0;
    tr.itiOnset          = 0;
    tr.trialEnd          = 0;
    % Actual onsets (filled at execution time)
    tr.actualPreviewVbl  = NaN;
    tr.actualCueDacOnset = NaN;
    tr.actualCueTriggerT = NaN;
    tr.actualGoDacOnset  = NaN;
    tr.actualGoTriggerT  = NaN;
    tr.actualItiTriggerT = NaN;
    % Scheduling errors (ms)
    tr.cueSchedErrorMs   = NaN;
    tr.goSchedErrorMs    = NaN;
ends