  function motor_planning()
%MOTOR_PLANNING  Motor planning EEG task
%
%   Mode 1 = 4 runs, effecteur unique
%   Mode 2 = 8 runs (4+4), deux effecteurs
%   ESCAPE pour quitter a tout moment.
%
%   CSV: run, trial, event, code, time_s, condition, effector, error_ms

    cfg = mp_config();
    rng(cfg.randomSeed, 'twister');
    fprintf('[INIT] %s | mode %d | seed %d\n', ...
        cfg.participant, cfg.protocolMode, cfg.randomSeed);

    if ~exist(cfg.dataDir, 'dir'), mkdir(cfg.dataDir); end

    w = []; pa = []; serialObj = []; allRec = {};

    try
        [w, pa, serialObj, snd, cfg] = mp_initHardware(cfg);

        % ── Welcome ──────────────────────────────────────────────
        if cfg.protocolMode == 1
            modeStr = sprintf('Mode 1 : %d runs, effecteur unique', cfg.nRuns);
        else
            modeStr = sprintf('Mode 2 : %d runs (4+4)', cfg.nRuns);
        end
        drawText(w, cfg, { ...
            'PLANIFICATION MOTRICE', ...
            '', ...
            ['Participant: ' cfg.participant], ...
            modeStr, ...
            sprintf('%d essais par run', cfg.nTrialsTotal), ...
            '', ...
            'Fixez la croix.', ...
            'Ecoutez les instructions audio.', ...
            'Attendez le BIP pour agir.', ...
            '', ...
            'Appuyez pour demarrer'});
        waitKey(cfg);

        % ── Run loop ─────────────────────────────────────────────
        for ri = 1:cfg.nRuns
            eff = cfg.runSequence{ri};
            fprintf('\n====== RUN %d/%d  %s ======\n', ri, cfg.nRuns, upper(eff));

            T = mp_buildDesign(cfg, eff, ri);

            % Pre-run screen
            if strcmp(eff, 'hand'), lab = 'MAIN';
            else,                   lab = 'OUTIL (pince)';
            end
            drawText(w, cfg, { ...
                sprintf('Run %d / %d', ri, cfg.nRuns), ...
                '', ...
                ['Effecteur: ' lab], ...
                sprintf('%d essais', cfg.nTrialsTotal), ...
                '', ...
                'Appuyez quand pret'});
            waitKey(cfg);

            % Start run: fixation + baseline (5 s)
            Priority(MaxPriority(w));

            drawBaseline(w, cfg, ri);
            Screen('Flip', w);
            t0 = GetSecs;
            sendTrig(serialObj, cfg, cfg.codes.run_start);
            fprintf('[OK] Run %d started | baseline %.0fs\n', ri, cfg.baselineInit);

            spinWait(t0 + cfg.baselineInit, cfg);

            % Execute trials
            [T, trialEvents] = mp_executeRun(w, pa, serialObj, snd, T, t0, cfg);

            % Final baseline
            drawBaseline(w, cfg, ri);
            Screen('Flip', w);
            spinWait(t0 + T(end).trialEnd + cfg.baselineFinal, cfg);

            runEndTime = GetSecs - t0;
            sendTrig(serialObj, cfg, cfg.codes.run_end);

            Priority(0);

            % Build full event log for this run
            runStart = makeEvt(ri, 0, 'run_start', cfg.codes.run_start, ...
                0, '', eff, NaN);
            runEnd = makeEvt(ri, 0, 'run_end', cfg.codes.run_end, ...
                runEndTime, '', eff, NaN);
            runEvents = [runStart, trialEvents, runEnd];

            % Save and log
            mp_saveData(runEvents, ri, eff, cfg);
            allRec{end+1} = runEvents; %#ok<AGROW>
            logTiming(trialEvents, ri, eff);

            fprintf('[OK] Run %d/%d (%s) complete.\n', ri, cfg.nRuns, eff);

            % Inter-run
            if ri < cfg.nRuns
                nextEff = cfg.runSequence{ri + 1};
                if ~strcmp(eff, nextEff)
                    showEffectorChange(w, cfg, ri, nextEff);
                else
                    showPause(w, cfg, ri);
                end
            end
        end

        % ── End ──────────────────────────────────────────────────
        drawText(w, cfg, { ...
            'EXAMEN TERMINE', ...
            '', ...
            sprintf('%d runs completes.', cfg.nRuns), ...
            '', ...
            'Merci pour votre participation !'});
        WaitSecs(5.0);

        saveAll(allRec, cfg);

    catch ME
        Priority(0);
        if strcmp(ME.identifier, 'motor_planning:userQuit')
            fprintf('\n[INFO] Arret par utilisateur.\n');
        else
            fprintf('\n[ERROR] %s\n', ME.message);
            disp(getReport(ME, 'extended'));
        end
        if ~isempty(allRec)
            try saveAll(allRec, cfg); catch, end
        end
    end

    cleanup(w, pa, serialObj);


% #####################################################################
%  Display
% #####################################################################

function drawText(w, cfg, lines)
%DRAWTEXT  Cell array of strings centered line by line, then flip.
    Screen('FillRect', w, cfg.black);
    Screen('TextSize', w, 36);
    lineH  = 50;
    totalH = numel(lines) * lineH;
    startY = cfg.yc - totalH/2;
    for i = 1:numel(lines)
        txt = lines{i};
        if isempty(txt), continue; end
        bounds = Screen('TextBounds', w, txt);
        x = cfg.xc - (bounds(3)-bounds(1))/2;
        y = startY + (i-1) * lineH;
        Screen('DrawText', w, txt, x, y, cfg.white);
    end
    Screen('Flip', w);

function drawBaseline(w, cfg, ri)
%DRAWBASELINE  Fixation cross + "Examen en cours - Run X/Y" (no flip)
    Screen('FillRect', w, cfg.black);
    mp_drawFixation(w, cfg);
    txt = sprintf('Examen en cours  -  Run %d / %d', ri, cfg.nRuns);
    Screen('TextSize', w, 20);
    bounds = Screen('TextBounds', w, txt);
    Screen('DrawText', w, txt, cfg.xc-(bounds(3)-bounds(1))/2, cfg.winH-50, cfg.grey);
    Screen('TextSize', w, 36);

function showPause(w, cfg, ri)
    dur    = cfg.interRunPause;
    tStart = GetSecs;
    while (GetSecs - tStart) < dur
        remaining = ceil(dur - (GetSecs - tStart));
        drawText(w, cfg, { ...
            'PAUSE', ...
            '', ...
            sprintf('Run %d / %d termine', ri, cfg.nRuns), ...
            sprintf('Repos: %d s', remaining), ...
            '', ...
            'Restez immobile...'});
        [kd, ~, kc] = KbCheck(-1);
        if kd && (kc(cfg.keys.escape) || kc(cfg.keys.q))
            error('motor_planning:userQuit', 'Quit.');
        end
        WaitSecs(0.5);
    end
    drawText(w, cfg, { ...
        'PAUSE', ...
        '', ...
        sprintf('Run %d / %d termine', ri, cfg.nRuns), ...
        '', ...
        'Appuyez pour continuer'});
    waitKey(cfg);

function showEffectorChange(w, cfg, ri, nextEff)
    if strcmp(nextEff, 'tool')
        msg = 'Prendre en main le forceps puis';
    else
        msg = 'Poser le forceps puis';
    end
    drawText(w, cfg, { ...
        'PAUSE - CHANGEMENT', ...
        '', ...
        sprintf('Run %d / %d termine', ri, cfg.nRuns), ...
        '', ...
        msg, ...
        'appuyer sur la touche Espace', ...
        'pour continuer.'});
    waitKey(cfg);

function waitKey(cfg)
    WaitSecs(0.3);
    KbReleaseWait(-1);
    while true
        [kd, ~, kc] = KbCheck(-1);
        if kd
            if kc(cfg.keys.escape) || kc(cfg.keys.q)
                error('motor_planning:userQuit', 'Quit.');
            end
            if kc(cfg.keys.space) || kc(cfg.keys.enter) || kc(cfg.keys.numEnter)
                break;
            end
        end
        WaitSecs('YieldSecs', 0.005);
    end
    KbReleaseWait(-1);


% #####################################################################
%  Event helper
% #####################################################################

function e = makeEvt(run, trial, event, code, time_s, cond, eff, err_ms)
    e = struct('run',run, 'trial',trial, 'event',event, 'code',code, ...
               'time_s',round(time_s,4), 'condition',cond, ...
               'effector',eff, 'error_ms',round(err_ms,3));


% #####################################################################
%  Timing / Triggers / Save / Cleanup
% #####################################################################

function spinWait(targetSecs, cfg)
    nextChk = GetSecs + 0.1;
    while (targetSecs - GetSecs) > 0.0005
        now_ = GetSecs;
        if now_ >= nextChk
            [kd, ~, kc] = KbCheck(-1);
            if kd && (kc(cfg.keys.escape) || kc(cfg.keys.q))
                error('motor_planning:userQuit', 'Quit.');
            end
            nextChk = now_ + 0.1;
        end
        WaitSecs('YieldSecs', 0.00005);
    end
    while GetSecs < targetSecs, end

function sendTrig(serialObj, cfg, code)
    if cfg.triggerActive && ~isempty(serialObj) && code > 0
        write(serialObj, uint8(code), 'uint8');
        WaitSecs(cfg.trigPulseS);
        write(serialObj, uint8(0), 'uint8');
    end

function logTiming(events, ri, eff)
    errs = [events.error_ms];
    errs = abs(errs(~isnan(errs)));
    if isempty(errs), return; end
    fprintf('-- Run %d (%s) -- Mean %.3f ms | Max %.3f ms | >1ms: %d\n', ...
        ri, eff, mean(errs), max(errs), sum(errs > 1));

function saveAll(allRec, cfg)
    if isempty(allRec), return; end
    allEvents = [allRec{:}];
    ts   = datestr(now, 'yyyymmdd_HHMMSS');
    base = sprintf('%s_%s_allruns_%s', cfg.participant, cfg.session, ts);
    try
        writetable(struct2table(allEvents), fullfile(cfg.dataDir, [base '.csv']));
        fprintf('[OK] All-runs CSV: %d events.\n', numel(allEvents));
    catch, end
    save(fullfile(cfg.dataDir, [base '.mat']), 'allEvents', 'cfg');
    fprintf('[OK] MAT saved.\n');

function cleanup(w, pa, serialObj)
    Priority(0);
    ShowCursor;
    try if ~isempty(pa), PsychPortAudio('Close', pa); end; catch, end
    try Screen('CloseAll'); catch, end
    if ~isempty(serialObj)
        try write(serialObj, uint8(0), 'uint8'); delete(serialObj); catch, end
    end
    fprintf('[OK] Cleanup.\n');