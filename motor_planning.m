function motor_planning()
%MOTOR_PLANNING  Motor planning EEG task — Psychtoolbox-3
%
%   Press ESCAPE at any time to quit.

    cfg = mp_config();
    rng(cfg.randomSeed, 'twister');
    fprintf('[INIT] %s | seed %d | %s\n', cfg.participant, cfg.randomSeed, ...
        strjoin(cfg.runSequence, ', '));

    if ~exist(cfg.dataDir, 'dir'), mkdir(cfg.dataDir); end

    w = []; pa = []; serialObj = []; allRec = {};

    try
        [w, pa, serialObj, snd, cfg] = mp_initHardware(cfg);

        % ── Welcome ──────────────────────────────────────────────
        drawMsg(w, cfg, sprintf([ ...
            'MOTOR PLANNING\n\n' ...
            'Participant: %s\n' ...
            '%d runs  |  %d trials per run\n\n' ...
            'Fixez la croix.\n' ...
            'Ecoutez les instructions audio.\n' ...
            'Attendez le BIP pour agir.\n\n' ...
            'Appuyez pour demarrer'], ...
            cfg.participant, cfg.nRuns, cfg.nTrialsTotal));
        waitKey(cfg);

        % ── Run loop ─────────────────────────────────────────────
        for ri = 1:cfg.nRuns
            eff = cfg.runSequence{ri};
            fprintf('\n====== RUN %d/%d  %s ======\n', ri, cfg.nRuns, upper(eff));

            T = mp_buildDesign(cfg, eff, ri);
            mp_saveData(T, 'planned', ri, eff, cfg);

            % Pre-run screen
            if strcmp(eff, 'hand'), lab = 'MAIN';
            else,                   lab = 'OUTIL (pince)';
            end
            drawMsg(w, cfg, sprintf([ ...
                'Run %d / %d\n\n' ...
                'Effecteur: %s\n' ...
                '%d essais\n\n' ...
                'Appuyez quand pret'], ri, cfg.nRuns, lab, cfg.nTrialsTotal));
            waitKey(cfg);

            % "Exam in progress"
            drawMsg(w, cfg, sprintf('Examen en cours...\n\nRun %d / %d', ri, cfg.nRuns));
            WaitSecs(1.5);

            % Start run
            Priority(MaxPriority(w));
            mp_drawFixation(w, cfg);
            Screen('Flip', w);
            t0 = GetSecs;
            sendTrig(serialObj, cfg, cfg.codes.run_start);

            spinWait(t0 + cfg.baselineInit, cfg);

            T = mp_executeRun(w, pa, serialObj, snd, T, t0, cfg);

            mp_drawFixation(w, cfg);
            Screen('Flip', w);
            spinWait(t0 + T(end).trialEnd + cfg.baselineFinal, cfg);
            sendTrig(serialObj, cfg, cfg.codes.run_end);

            Priority(0);

            logTiming(T, ri, eff);
            mp_saveData(T, 'actual', ri, eff, cfg);
            allRec{end+1} = T; %#ok<AGROW>

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
        drawMsg(w, cfg, sprintf([ ...
            'EXAMEN TERMINE\n\n' ...
            '%d runs completes.\n\n' ...
            'Merci pour votre participation !'], cfg.nRuns));
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

    cleanup(w, pa, serialObj, cfg);


% #####################################################################
%  Display
% #####################################################################

function drawMsg(w, cfg, msg)
%DRAWMSG  White text centered on black, then flip. Returns immediately.
    Screen('FillRect', w, 0);
    Screen('TextSize', w, 36);
    DrawFormattedText(w, msg, 'center', 'center', [1 1 1]);
    Screen('Flip', w);

function showPause(w, cfg, ri)
%SHOWPAUSE  Timed rest (countdown) then wait for key
    tStart = GetSecs;
    dur    = cfg.interRunPause;

    while (GetSecs - tStart) < dur
        remaining = ceil(dur - (GetSecs - tStart));
        msg = sprintf([ ...
            'PAUSE\n\n' ...
            'Run %d / %d termine\n\n' ...
            'Repos: %d s\n\n' ...
            'Restez immobile...'], ri, cfg.nRuns, remaining);
        Screen('FillRect', w, 0);
        Screen('TextSize', w, 36);
        DrawFormattedText(w, msg, 'center', 'center', [1 1 1]);
        Screen('Flip', w);

        [kd, ~, kc] = KbCheck(-1);
        if kd && (kc(cfg.keys.escape) || kc(cfg.keys.q))
            error('motor_planning:userQuit', 'Quit.');
        end
        WaitSecs(0.5);
    end

    drawMsg(w, cfg, sprintf([ ...
        'PAUSE\n\n' ...
        'Run %d / %d termine\n\n' ...
        'Appuyez pour continuer'], ri, cfg.nRuns));
    waitKey(cfg);

function showEffectorChange(w, cfg, ri, nextEff)
%SHOWEFFECTORCHANGE  Manual pause for setup
    if strcmp(nextEff, 'hand'), lab = 'MAIN';
    else,                       lab = 'OUTIL (pince)';
    end
    drawMsg(w, cfg, sprintf([ ...
        'PAUSE — CHANGEMENT\n\n' ...
        'Run %d / %d termine\n\n' ...
        'Prochain effecteur: %s\n\n' ...
        '- Changer objet / outil\n' ...
        '- Ajuster la position\n' ...
        '- Prenez votre temps\n\n' ...
        'Appuyez quand pret'], ri, cfg.nRuns, lab));
    waitKey(cfg);

function waitKey(cfg)
%WAITKEY  Block until SPACE / ENTER / numpad Enter. ESCAPE quits.
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
    while GetSecs < targetSecs
    end

function sendTrig(serialObj, cfg, code)
    if cfg.triggerActive && ~isempty(serialObj) && code > 0
        write(serialObj, uint8(code), 'uint8');
        WaitSecs(cfg.trigPulseS);
        write(serialObj, uint8(0), 'uint8');
    end

function logTiming(T, ri, eff)
    cueErr = abs([T.cueSchedErrorMs]);
    goErr  = abs([T.goSchedErrorMs]);
    allErr = [cueErr(~isnan(cueErr)), goErr(~isnan(goErr))];
    if isempty(allErr), return; end
    fprintf('\n-- Timing Run %d (%s) --\n', ri, eff);
    fprintf('  Mean %.3f ms | Max %.3f ms | >1ms: %d | >2ms: %d\n', ...
        mean(allErr), max(allErr), sum(allErr>1), sum(allErr>2));

function saveAll(allRec, cfg)
    if isempty(allRec), return; end
    allT = [allRec{:}];
    ts   = datestr(now, 'yyyymmdd_HHMMSS');
    base = sprintf('%s_%s_MotorPlanning_allruns_%s', cfg.participant, cfg.session, ts);
    try
        writetable(struct2table(allT), fullfile(cfg.dataDir, [base '.csv']));
        fprintf('[OK] CSV saved.\n');
    catch, end
    save(fullfile(cfg.dataDir, [base '.mat']), 'allT', 'cfg');
    fprintf('[OK] MAT saved.\n');

function cleanup(w, pa, serialObj, cfg)
    Priority(0);
    ShowCursor;
    try if ~isempty(pa), PsychPortAudio('Close', pa); end; catch, end
    try if ~isempty(w),  Screen('CloseAll');            end; catch, end
    if ~isempty(serialObj)
        try write(serialObj, uint8(0), 'uint8'); delete(serialObj); catch, end
    end
    fprintf('[OK] Cleanup.\n');