  function motor_planning()
%MOTOR_PLANNING  Motor planning EEG task — Psychtoolbox-3
%
%   Entry point for the experiment. Manages the session loop:
%   configuration → hardware init → run loop → cleanup.
%
%   TRIAL STRUCTURE:
%     Preview 2 s → Cue audio → Plan 5.5±0.5 s → Go beep → Execute 2 s → ITI 8 s
%
%   SESSION STRUCTURE:
%     4 runs with first effector → manual pause → 4 runs with second effector
%     20 trials per run (10 grasp + 10 touch, pseudo-randomized)
%
%   TRIGGER CODES:
%     100 run_start  | 200 run_end   | 30 trial_start
%      11 cue_grasp  |  12 cue_touch
%      21 go_grasp   |  22 go_touch  | 40 iti_start
%
%   See also mp_config, mp_initHardware, mp_buildDesign, mp_executeRun

    % ── 1. Configuration ──────────────────────────────────────────────
    cfg = mp_config();

    rng(cfg.randomSeed, 'twister');
    fprintf('[INIT] Participant : %s | Session : %s\n', cfg.participant, cfg.session);
    fprintf('[INIT] Random seed : %d\n', cfg.randomSeed);
    fprintf('[INIT] Screen ID   : %d\n', cfg.screenId);
    fprintf('[INIT] Runs        : %s\n', strjoin(cfg.runSequence, ', '));

    if ~exist(cfg.dataDir, 'dir'), mkdir(cfg.dataDir); end

    % ── 2. Hardware initialization ────────────────────────────────────
    w = []; pa = []; ioObj = []; allRec = {};

    try
        [w, pa, ioObj, snd, cfg] = mp_initHardware(cfg);

        trialDur = cfg.previewDur + cfg.planDur + cfg.execDur + cfg.itiDur;
        runDur   = cfg.baselineInit + cfg.nTrialsTotal * trialDur + cfg.baselineFinal;
        fprintf('[INFO] ~%.1f min/run | ~%.0f min total (%d runs)\n', ...
            runDur/60, runDur * cfg.nRuns / 60, cfg.nRuns);

        % ── 3. Session instructions ───────────────────────────────────
        showSessionInstructions(w, cfg);

        % ── 4. Run loop ───────────────────────────────────────────────
        for ri = 1:cfg.nRuns
            eff = cfg.runSequence{ri};
            fprintf('\n====== RUN %d/%d — %s ======\n', ri, cfg.nRuns, upper(eff));

            T = mp_buildDesign(cfg, eff, ri);
            mp_saveData(T, 'planned', ri, eff, cfg);

            showRunInstructions(w, ri, eff, cfg);

            Priority(MaxPriority(w));

            mp_drawFixation(w, cfg);
            Screen('Flip', w);
            t0 = GetSecs;
            sendTrigger(ioObj, cfg, cfg.codes.run_start);
            fprintf('[OK] Run %d started (t0 = %.6f)\n', ri, t0);

            spinWaitUntil(t0 + cfg.baselineInit);

            T = mp_executeRun(w, pa, ioObj, snd, T, t0, cfg);

            mp_drawFixation(w, cfg);
            Screen('Flip', w);
            spinWaitUntil(t0 + T(end).trialEnd + cfg.baselineFinal);
            sendTrigger(ioObj, cfg, cfg.codes.run_end);

            Priority(0);

            logTimingSummary(T, ri, eff);
            mp_saveData(T, 'actual', ri, eff, cfg);
            allRec{end+1} = T; %#ok<AGROW>

            fprintf('[OK] Run %d/%d (%s) complete.\n', ri, cfg.nRuns, eff);

            if ri < cfg.nRuns
                nextEff = cfg.runSequence{ri + 1};
                if ~strcmp(eff, nextEff)
                    showEffectorChangePause(w, ri, nextEff, cfg);
                else
                    showInterRunPause(w, ri, cfg);
                end
            end
        end

        showSessionEnd(w, cfg);
        saveAllRuns(allRec, cfg);
        fprintf('\n[OK] Session complete: %d runs.\n', cfg.nRuns);

    catch ME
        Priority(0);
        if strcmp(ME.identifier, 'motor_planning:userQuit')
            fprintf('\n[INFO] Session stopped by user.\n');
        else
            fprintf('\n[ERROR] %s\n', ME.message);
            disp(getReport(ME, 'extended'));
        end
        if ~isempty(allRec)
            try saveAllRuns(allRec, cfg); catch, end
        end
    end

    cleanupHardware(w, pa, ioObj, cfg);


% #####################################################################
%  LOCAL FUNCTIONS — Instruction screens
% #####################################################################

function showSessionInstructions(w, cfg)
    txt = sprintf([ ...
        '===================================\n' ...
        '      MOTOR PLANNING TASK\n' ...
        '===================================\n\n' ...
        'Participant : %s\n' ...
        'Session     : %s\n' ...
        'Runs        : %d (%d %s + %d %s)\n' ...
        'Screen      : %d (%d x %d @ %d Hz)\n\n' ...
        'Each trial:\n' ...
        '  1. Fixate the cross\n' ...
        '  2. Listen to the instruction (Grasp / Touch)\n' ...
        '  3. WAIT for the beep to execute\n' ...
        '  4. Return to starting position\n\n' ...
        '  >> SPACE or ENTER to continue'], ...
        cfg.participant, cfg.session, cfg.nRuns, ...
        cfg.nRunsPerEffector, cfg.runSequence{1}, ...
        cfg.nRunsPerEffector, cfg.runSequence{end}, ...
        cfg.screenId, cfg.winW, cfg.winH, cfg.fps);
    waitForKey(w, cfg, txt);

function showRunInstructions(w, ri, eff, cfg)
    if strcmp(eff, 'hand'), lab = 'HAND';
    else,                   lab = 'TOOL (forceps)';
    end
    txt = sprintf([ ...
        '---- Run %d / %d ----\n\n' ...
        'Effector : %s\n' ...
        '%d trials (%d grasp + %d touch)\n\n' ...
        'Get ready.\n\n' ...
        '  >> SPACE or ENTER when ready'], ...
        ri, cfg.nRuns, lab, ...
        cfg.nTrialsTotal, cfg.nTrialsPerCond, cfg.nTrialsPerCond);
    waitForKey(w, cfg, txt);

function showInterRunPause(w, ri, cfg)
    pauseDur = cfg.interRunPause;
    tStart   = GetSecs;

    while (GetSecs - tStart) < pauseDur
        remaining = ceil(pauseDur - (GetSecs - tStart));
        txt = sprintf([ ...
            '=== Run %d/%d complete ===\n\n' ...
            'Mandatory rest: %d s remaining\n\n' ...
            'Please wait...'], ri, cfg.nRuns, remaining);
        DrawFormattedText(w, txt, 'center', 'center', cfg.white, 60);
        Screen('Flip', w);

        [kd, ~, kc] = KbCheck(-1);
        if kd && (kc(cfg.keys.escape) || kc(cfg.keys.q))
            error('motor_planning:userQuit', 'User quit during pause.');
        end
        WaitSecs(0.5);
    end

    txt = sprintf([ ...
        '=== Run %d/%d complete ===\n\n' ...
        'Rest complete.\n\n' ...
        '  >> SPACE or ENTER when ready for run %d'], ...
        ri, cfg.nRuns, ri+1);
    waitForKey(w, cfg, txt);

function showEffectorChangePause(w, ri, nextEff, cfg)
    if strcmp(nextEff, 'hand'), lab = 'HAND';
    else,                       lab = 'TOOL (forceps)';
    end
    txt = sprintf([ ...
        '========================================\n' ...
        '       EFFECTOR CHANGE\n' ...
        '========================================\n\n' ...
        'Run %d/%d complete.\n\n' ...
        'Next effector: %s\n\n' ...
        '  - Give/remove forceps\n' ...
        '  - Reposition object on table\n' ...
        '  - Recalibrate distance\n\n' ...
        'Take your time.\n\n' ...
        '  >> SPACE or ENTER when participant is ready'], ...
        ri, cfg.nRuns, lab);
    waitForKey(w, cfg, txt);

function showSessionEnd(w, cfg)
    txt = sprintf([ ...
        '===================================\n' ...
        '       SESSION COMPLETE\n' ...
        '===================================\n\n' ...
        'All %d runs finished.\n\n' ...
        'Thank you for your participation!'], cfg.nRuns);
    DrawFormattedText(w, txt, 'center', 'center', cfg.white, 60);
    Screen('Flip', w);
    WaitSecs(5.0);

function waitForKey(w, cfg, txt)
%WAITFORKEY  Show text, wait for SPACE / ENTER / numpad-ENTER. Quit on ESC/Q.
    DrawFormattedText(w, txt, 'center', 'center', cfg.white, 60);
    Screen('Flip', w);
    WaitSecs(0.3);
    KbReleaseWait(-1);
    while true
        [kd, ~, kc] = KbCheck(-1);
        if kd
            if kc(cfg.keys.escape) || kc(cfg.keys.q)
                error('motor_planning:userQuit', 'User quit.');
            end
            if kc(cfg.keys.space) || kc(cfg.keys.enter) || kc(cfg.keys.numEnter)
                break;
            end
        end
        WaitSecs('YieldSecs', 0.005);
    end
    KbReleaseWait(-1);


% #####################################################################
%  LOCAL FUNCTIONS — Timing, triggers, logging, cleanup
% #####################################################################

function spinWaitUntil(targetSecs)
    while (targetSecs - GetSecs) > 0.0005
        WaitSecs('YieldSecs', 0.00005);
    end
    while GetSecs < targetSecs
    end

function sendTrigger(ioObj, cfg, code)
    if cfg.parportActive && ~isempty(ioObj) && code > 0
        io64(ioObj, cfg.parportAddr, code);
        WaitSecs(cfg.trigPulseS);
        io64(ioObj, cfg.parportAddr, 0);
    end

function logTimingSummary(T, ri, eff)
    cueErr = abs([T.cueSchedErrorMs]);
    goErr  = abs([T.goSchedErrorMs]);
    allErr = [cueErr(~isnan(cueErr)), goErr(~isnan(goErr))];
    if isempty(allErr), return; end

    fprintf('\n-- Timing Run %d (%s) -- %d audio events\n', ri, eff, numel(allErr));
    fprintf('  Mean   : %.3f ms\n', mean(allErr));
    fprintf('  Median : %.3f ms\n', median(allErr));
    fprintf('  p95    : %.3f ms\n', prctile(allErr, 95));
    fprintf('  Max    : %.3f ms\n', max(allErr));
    fprintf('  >1 ms  : %d   |   >2 ms : %d\n', sum(allErr > 1), sum(allErr > 2));
    fprintf('\n');

function saveAllRuns(allRec, cfg)
    if isempty(allRec), return; end
    allT = [allRec{:}];
    ts   = datestr(now, 'yyyymmdd_HHMMSS');
    base = sprintf('%s_%s_MotorPlanning_allruns_%s', cfg.participant, cfg.session, ts);
    try
        writetable(struct2table(allT), fullfile(cfg.dataDir, [base '.csv']));
        fprintf('[OK] All-runs CSV saved.\n');
    catch ME
        warning('All-runs CSV failed: %s', ME.message);
    end
    save(fullfile(cfg.dataDir, [base '.mat']), 'allT', 'cfg');
    fprintf('[OK] All-runs MAT saved.\n');

function cleanupHardware(w, pa, ioObj, cfg)
    Priority(0);
    ShowCursor;
    try if ~isempty(pa), PsychPortAudio('Close', pa); end; catch, end
    try if ~isempty(w),  Screen('CloseAll');            end; catch, end
    if cfg.parportActive && ~isempty(ioObj)
        try io64(ioObj, cfg.parportAddr, 0); catch, end
    end
    fprintf('[OK] Cleanup complete.\n');