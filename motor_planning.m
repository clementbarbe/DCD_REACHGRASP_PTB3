function motor_planning()
%MOTOR_PLANNING  Motor planning EEG task — Psychtoolbox-3
%
%   Entry point. Session loop: config -> hardware -> runs -> cleanup.
%   Press ESCAPE at any time to quit cleanly.
%
%   DISPLAY:
%     - "Press SPACE to start" before session
%     - Fixation cross during trials
%     - "PAUSE — Run X/Y complete" between runs
%     - "EFFECTOR CHANGE" when switching hand/tool
%     - "EXAM COMPLETE" at the end
%
%   See also mp_config, mp_initHardware, mp_buildDesign, mp_executeRun

    cfg = mp_config();

    rng(cfg.randomSeed, 'twister');
    fprintf('[INIT] Participant : %s | Session : %s\n', cfg.participant, cfg.session);
    fprintf('[INIT] Random seed : %d\n', cfg.randomSeed);
    fprintf('[INIT] Triggers    : %s @ %d baud\n', cfg.serialPortName, cfg.serialBaudRate);
    fprintf('[INIT] Runs        : %s\n', strjoin(cfg.runSequence, ', '));
    fprintf('[INIT] Press ESCAPE at any time to quit.\n');

    if ~exist(cfg.dataDir, 'dir'), mkdir(cfg.dataDir); end

    w = []; pa = []; serialObj = []; allRec = {};

    try
        [w, pa, serialObj, snd, cfg] = mp_initHardware(cfg);

        trialDur = cfg.previewDur + cfg.planDur + cfg.execDur + cfg.itiDur;
        runDur   = cfg.baselineInit + cfg.nTrialsTotal * trialDur + cfg.baselineFinal;
        fprintf('[INFO] ~%.1f min/run | ~%.0f min total (%d runs)\n', ...
            runDur/60, runDur * cfg.nRuns / 60, cfg.nRuns);

        % ── Welcome screen ────────────────────────────────────────
        showCentered(w, cfg, [ ...
            'MOTOR PLANNING TASK\n\n' ...
            'Fixate the cross during the exam.\n' ...
            'Listen and follow the audio instructions.\n\n' ...
            'Press SPACE to start']);
        waitForKey(w, cfg);

        for ri = 1:cfg.nRuns
            eff = cfg.runSequence{ri};
            fprintf('\n====== RUN %d/%d — %s ======\n', ri, cfg.nRuns, upper(eff));

            T = mp_buildDesign(cfg, eff, ri);
            mp_saveData(T, 'planned', ri, eff, cfg);

            % ── Pre-run: show effector + ready prompt ─────────────
            if strcmp(eff, 'hand'), lab = 'HAND';
            else,                   lab = 'TOOL (forceps)';
            end
            showCentered(w, cfg, sprintf([ ...
                'Run %d / %d  —  %s\n\n' ...
                '%d trials\n\n' ...
                'Press SPACE when ready'], ...
                ri, cfg.nRuns, lab, cfg.nTrialsTotal));
            waitForKey(w, cfg);

            % ── "Exam in progress" then fixation ──────────────────
            showCentered(w, cfg, 'Exam in progress...');
            WaitSecs(1.5);

            Priority(MaxPriority(w));

            mp_drawFixation(w, cfg);
            Screen('Flip', w);
            t0 = GetSecs;
            sendTrigger(serialObj, cfg, cfg.codes.run_start);
            fprintf('[OK] Run %d started (t0 = %.6f)\n', ri, t0);

            spinWaitUntil(t0 + cfg.baselineInit, cfg);

            T = mp_executeRun(w, pa, serialObj, snd, T, t0, cfg);

            mp_drawFixation(w, cfg);
            Screen('Flip', w);
            spinWaitUntil(t0 + T(end).trialEnd + cfg.baselineFinal, cfg);
            sendTrigger(serialObj, cfg, cfg.codes.run_end);

            Priority(0);

            logTimingSummary(T, ri, eff);
            mp_saveData(T, 'actual', ri, eff, cfg);
            allRec{end+1} = T; %#ok<AGROW>

            fprintf('[OK] Run %d/%d (%s) complete.\n', ri, cfg.nRuns, eff);

            % ── Inter-run screens ─────────────────────────────────
            if ri < cfg.nRuns
                nextEff = cfg.runSequence{ri + 1};
                if ~strcmp(eff, nextEff)
                    % EFFECTOR CHANGE — manual pause
                    showEffectorChange(w, ri, nextEff, cfg);
                else
                    % SAME EFFECTOR — timed pause
                    showPause(w, ri, cfg);
                end
            end
        end

        % ── Session end ───────────────────────────────────────────
        showCentered(w, cfg, [ ...
            'EXAM COMPLETE\n\n' ...
            sprintf('All %d runs finished.\n\n', cfg.nRuns) ...
            'Thank you for your participation!']);
        WaitSecs(5.0);

        saveAllRuns(allRec, cfg);
        fprintf('\n[OK] Session complete: %d runs.\n', cfg.nRuns);

    catch ME
        Priority(0);
        if strcmp(ME.identifier, 'motor_planning:userQuit')
            fprintf('\n[INFO] Session stopped by user (ESCAPE).\n');
        else
            fprintf('\n[ERROR] %s\n', ME.message);
            disp(getReport(ME, 'extended'));
        end
        if ~isempty(allRec)
            try saveAllRuns(allRec, cfg); catch, end
        end
    end

    cleanupHardware(w, pa, serialObj, cfg);


% #####################################################################
%  LOCAL — Display helpers
% #####################################################################

function showCentered(w, cfg, txt)
%SHOWCENTERED  Draw white text centered on black background, then flip.
%   Does NOT wait — returns immediately after flip.
    Screen('FillRect', w, cfg.black);
    DrawFormattedText(w, txt, 'center', 'center', cfg.white, 60);
    Screen('Flip', w);

function showPause(w, ri, cfg)
%SHOWPAUSE  Timed mandatory rest, then SPACE to continue.
    pauseDur = cfg.interRunPause;
    tStart   = GetSecs;

    % Countdown
    while (GetSecs - tStart) < pauseDur
        remaining = ceil(pauseDur - (GetSecs - tStart));
        txt = sprintf([ ...
            'PAUSE\n\n' ...
            'Run %d / %d complete\n\n' ...
            'Rest: %d s remaining\n\n' ...
            'Stay still, relax...'], ri, cfg.nRuns, remaining);
        Screen('FillRect', w, cfg.black);
        DrawFormattedText(w, txt, 'center', 'center', cfg.white, 60);
        Screen('Flip', w);

        [kd, ~, kc] = KbCheck(-1);
        if kd && (kc(cfg.keys.escape) || kc(cfg.keys.q))
            error('motor_planning:userQuit', 'User quit during pause.');
        end
        WaitSecs(0.5);
    end

    showCentered(w, cfg, sprintf([ ...
        'PAUSE\n\n' ...
        'Run %d / %d complete\n\n' ...
        'Press SPACE when ready for run %d'], ...
        ri, cfg.nRuns, ri+1));
    waitForKey(w, cfg);

function showEffectorChange(w, ri, nextEff, cfg)
%SHOWEFFECTORCHANGE  Manual pause for switching effector (hand <-> tool).
    if strcmp(nextEff, 'hand'), lab = 'HAND';
    else,                       lab = 'TOOL (forceps)';
    end

    showCentered(w, cfg, sprintf([ ...
        'PAUSE — EFFECTOR CHANGE\n\n' ...
        'Run %d / %d complete\n\n' ...
        'Next: %s\n\n' ...
        '- Change the object / tool\n' ...
        '- Adjust position\n' ...
        '- Take your time\n\n' ...
        'Press SPACE when ready to continue'], ...
        ri, cfg.nRuns, lab));
    waitForKey(w, cfg);

function waitForKey(w, cfg) %#ok<INUSL>
%WAITFORKEY  Block until SPACE/ENTER. ESCAPE quits.
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
%  LOCAL — Timing, triggers, logging, cleanup
% #####################################################################

function spinWaitUntil(targetSecs, cfg)
%SPINWAITUNTIL  High-precision wait with ESCAPE check every ~100 ms
    if nargin < 2
        while (targetSecs - GetSecs) > 0.0005
            WaitSecs('YieldSecs', 0.00005);
        end
        while GetSecs < targetSecs
        end
        return;
    end

    nextCheck = GetSecs + 0.1;
    while (targetSecs - GetSecs) > 0.0005
        now_ = GetSecs;
        if now_ >= nextCheck
            [kd, ~, kc] = KbCheck(-1);
            if kd && (kc(cfg.keys.escape) || kc(cfg.keys.q))
                error('motor_planning:userQuit', 'User quit (Escape).');
            end
            nextCheck = now_ + 0.1;
        end
        WaitSecs('YieldSecs', 0.00005);
    end
    while GetSecs < targetSecs
    end

function sendTrigger(serialObj, cfg, code)
    if cfg.triggerActive && ~isempty(serialObj) && code > 0
        write(serialObj, uint8(code), 'uint8');
        WaitSecs(cfg.trigPulseS);
        write(serialObj, uint8(0), 'uint8');
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

function cleanupHardware(w, pa, serialObj, cfg)
    Priority(0);
    ShowCursor;
    try if ~isempty(pa), PsychPortAudio('Close', pa); end; catch, end
    try if ~isempty(w),  Screen('CloseAll');            end; catch, end
    if ~isempty(serialObj)
        try
            write(serialObj, uint8(0), 'uint8');
            delete(serialObj);
        catch
        end
    end
    fprintf('[OK] Cleanup complete.\n');