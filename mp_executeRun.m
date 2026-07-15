function [T, events] = mp_executeRun(w, pa, serialObj, snd, T, t0, cfg)
%MP_EXECUTERUN  Execute all trials, return event log
%
%   Returns:
%     T      — timeline struct with actual times filled in
%     events — struct array: run, trial, event, code, time_s,
%              condition, effector, error_ms

    nTrials = numel(T);

    % Pre-allocate events (4 per trial: trial_start, cue, go, iti)
    events = repmat(emptyEvt(), 1, nTrials * 4);
    ei = 0;

    for ti = 1:nTrials
        tr = T(ti);
        checkQuit(cfg);

        % ── PREVIEW ──────────────────────────────────────────────
        drawTrialScreen(w, cfg, ti, nTrials);
        vbl = Screen('Flip', w, t0 + tr.previewOnset - cfg.halfIfi);
        tr.actualPreviewVbl = vbl - t0;
        trigSend(serialObj, cfg, cfg.codes.trial_start);

        ei = ei + 1;
        events(ei) = makeEvt(tr.runNumber, ti, 'trial_start', ...
            cfg.codes.trial_start, vbl - t0, tr.condition, tr.effector, NaN);

        spinWait(t0 + tr.cueOnset - cfg.fillAhead, cfg);

        % ── CUE ──────────────────────────────────────────────────
        PsychPortAudio('Stop', pa, 0);
        PsychPortAudio('FillBuffer', pa, snd.(tr.condition));
        checkQuit(cfg);

        targetCue = t0 + tr.cueOnset;
        nowT = GetSecs;
        if nowT > targetCue - 0.010
            actualCue = PsychPortAudio('Start', pa, 1, 0, 1);
        else
            actualCue = PsychPortAudio('Start', pa, 1, targetCue, 1);
        end

        if cfg.audioHwDelay > 0, spinWait(actualCue + cfg.audioHwDelay, cfg); end
        tr.actualCueTriggerT = trigTimed(serialObj, cfg, tr.cueCode, t0);
        tr.actualCueDacOnset = actualCue - t0;
        tr.cueSchedErrorMs   = (actualCue - targetCue) * 1000;

        ei = ei + 1;
        events(ei) = makeEvt(tr.runNumber, ti, 'cue', tr.cueCode, ...
            actualCue - t0, tr.condition, tr.effector, tr.cueSchedErrorMs);

        % ── PLAN ─────────────────────────────────────────────────
        spinWait(t0 + tr.goOnset - cfg.fillAhead, cfg);

        % ── GO ───────────────────────────────────────────────────
        PsychPortAudio('Stop', pa, 0);
        PsychPortAudio('FillBuffer', pa, snd.go);
        checkQuit(cfg);

        targetGo = t0 + tr.goOnset;
        nowT = GetSecs;
        if nowT > targetGo - 0.010
            actualGo = PsychPortAudio('Start', pa, 1, 0, 1);
        else
            actualGo = PsychPortAudio('Start', pa, 1, targetGo, 1);
        end

        if cfg.audioHwDelay > 0, spinWait(actualGo + cfg.audioHwDelay, cfg); end
        tr.actualGoTriggerT = trigTimed(serialObj, cfg, tr.goCode, t0);
        tr.actualGoDacOnset = actualGo - t0;
        tr.goSchedErrorMs   = (actualGo - targetGo) * 1000;

        ei = ei + 1;
        events(ei) = makeEvt(tr.runNumber, ti, 'go', tr.goCode, ...
            actualGo - t0, tr.condition, tr.effector, tr.goSchedErrorMs);

        % ── ITI ──────────────────────────────────────────────────
        spinWait(t0 + tr.itiOnset, cfg);
        itiTime = trigTimed(serialObj, cfg, cfg.codes.iti_start, t0);
        tr.actualItiTriggerT = itiTime;

        ei = ei + 1;
        events(ei) = makeEvt(tr.runNumber, ti, 'iti', cfg.codes.iti_start, ...
            itiTime, tr.condition, tr.effector, NaN);

        drawTrialScreen(w, cfg, ti, nTrials);
        Screen('Flip', w);

        if ti < nTrials
            spinWait(t0 + tr.trialEnd, cfg);
        end

        T(ti) = tr;
        fprintf('  Trial %2d/%d (%s) | cue %+.2f ms | go %+.2f ms\n', ...
            ti, nTrials, tr.condition, tr.cueSchedErrorMs, tr.goSchedErrorMs);
    end

    events = events(1:ei);


% =====================================================================

function e = emptyEvt()
    e = struct('run',0,'trial',0,'event','','code',0,'time_s',0,...
               'condition','','effector','','error_ms',NaN);

function e = makeEvt(run, trial, event, code, time_s, cond, eff, err_ms)
    e = struct('run',run, 'trial',trial, 'event',event, 'code',code, ...
               'time_s',round(time_s,4), 'condition',cond, ...
               'effector',eff, 'error_ms',round(err_ms,3));

function drawTrialScreen(w, cfg, ti, nTrials)
    Screen('FillRect', w, cfg.black);
    mp_drawFixation(w, cfg);
    txt = sprintf('Examen en cours  -  Essai %d / %d', ti, nTrials);
    Screen('TextSize', w, 20);
    bounds = Screen('TextBounds', w, txt);
    Screen('DrawText', w, txt, cfg.xc-(bounds(3)-bounds(1))/2, cfg.winH-50, cfg.grey);
    Screen('TextSize', w, 36);

function spinWait(targetSecs, cfg)
    if nargin < 2
        while (targetSecs - GetSecs) > 0.0005
            WaitSecs('YieldSecs', 0.00005);
        end
        while GetSecs < targetSecs, end
        return;
    end
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

function relT = trigTimed(serialObj, cfg, code, t0)
    if cfg.triggerActive && ~isempty(serialObj) && code > 0
        write(serialObj, uint8(code), 'uint8');
        absT = GetSecs;
        WaitSecs(cfg.trigPulseS);
        write(serialObj, uint8(0), 'uint8');
    else
        absT = GetSecs;
    end
    relT = absT - t0;

function trigSend(serialObj, cfg, code)
    if cfg.triggerActive && ~isempty(serialObj) && code > 0
        write(serialObj, uint8(code), 'uint8');
        WaitSecs(cfg.trigPulseS);
        write(serialObj, uint8(0), 'uint8');
    end

function checkQuit(cfg)
    [kd, ~, kc] = KbCheck(-1);
    if kd && (kc(cfg.keys.escape) || kc(cfg.keys.q))
        error('motor_planning:userQuit', 'Quit.');
    end