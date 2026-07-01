function T = mp_executeRun(w, pa, serialObj, snd, T, t0, cfg)
%MP_EXECUTERUN  Execute all trials with precise audio timing
%
%   During trials: fixation cross centered + small status text at bottom.
%   ESCAPE can be pressed at any time to quit cleanly.
%
%   See also mp_buildDesign, motor_planning

    nTrials = numel(T);

    for ti = 1:nTrials
        tr = T(ti);

        checkQuit(cfg);

        % ── PREVIEW: fixation + status ───────────────────────────
        drawTrialScreen(w, cfg, ti, nTrials);
        vbl = Screen('Flip', w, t0 + tr.previewOnset - cfg.halfIfi);
        tr.actualPreviewVbl = vbl - t0;
        trigSend(serialObj, cfg, cfg.codes.trial_start);

        % Wait through preview with ESC check
        spinWaitUntil(t0 + tr.cueOnset - cfg.fillAhead, cfg);

        % ── CUE AUDIO ───────────────────────────────────────────
        cueBuf    = snd.(tr.condition);
        targetCue = t0 + tr.cueOnset;

        PsychPortAudio('Stop', pa, 0);
        PsychPortAudio('FillBuffer', pa, cueBuf);

        checkQuit(cfg);

        nowT = GetSecs;
        if nowT > targetCue - 0.010
            warning('CUE LATE trial %d: %.1f ms', ti, (nowT-targetCue)*1000);
            actualCue = PsychPortAudio('Start', pa, 1, 0, 1);
        else
            actualCue = PsychPortAudio('Start', pa, 1, targetCue, 1);
        end

        if cfg.audioHwDelay > 0
            spinWaitUntil(actualCue + cfg.audioHwDelay);
        end
        tr.actualCueTriggerT = trigSendTimed(serialObj, cfg, tr.cueCode, t0);
        tr.actualCueDacOnset = actualCue - t0;
        tr.cueSchedErrorMs   = (actualCue - targetCue) * 1000;

        % ── PLAN PERIOD — ESC checked every 100 ms ──────────────
        spinWaitUntil(t0 + tr.goOnset - cfg.fillAhead, cfg);

        % ── GO BEEP ─────────────────────────────────────────────
        targetGo = t0 + tr.goOnset;

        PsychPortAudio('Stop', pa, 0);
        PsychPortAudio('FillBuffer', pa, snd.go);

        checkQuit(cfg);

        nowT = GetSecs;
        if nowT > targetGo - 0.010
            warning('GO LATE trial %d: %.1f ms', ti, (nowT-targetGo)*1000);
            actualGo = PsychPortAudio('Start', pa, 1, 0, 1);
        else
            actualGo = PsychPortAudio('Start', pa, 1, targetGo, 1);
        end

        if cfg.audioHwDelay > 0
            spinWaitUntil(actualGo + cfg.audioHwDelay);
        end
        tr.actualGoTriggerT = trigSendTimed(serialObj, cfg, tr.goCode, t0);
        tr.actualGoDacOnset = actualGo - t0;
        tr.goSchedErrorMs   = (actualGo - targetGo) * 1000;

        % ── EXECUTE + ITI ────────────────────────────────────────
        spinWaitUntil(t0 + tr.itiOnset, cfg);
        tr.actualItiTriggerT = trigSendTimed(serialObj, cfg, cfg.codes.iti_start, t0);

        % Show fixation during ITI
        drawTrialScreen(w, cfg, ti, nTrials);
        Screen('Flip', w);

        if ti < nTrials
            spinWaitUntil(t0 + tr.trialEnd, cfg);
        end

        T(ti) = tr;
        fprintf('  Trial %2d/%d (%s) | cue %+.2f ms | go %+.2f ms\n', ...
            ti, nTrials, tr.condition, tr.cueSchedErrorMs, tr.goSchedErrorMs);
    end


% =====================================================================

function drawTrialScreen(w, cfg, trialNum, nTrials)
%DRAWTRIALSCREEN  Fixation cross + small status text at bottom
    Screen('FillRect', w, cfg.black);

    % Fixation cross
    mp_drawFixation(w, cfg);

    % Small status text at bottom (grey, unobtrusive)
    grey = cfg.white * 0.35;
    statusTxt = sprintf('Trial %d / %d', trialNum, nTrials);
    Screen('TextSize', w, 18);
    DrawFormattedText(w, statusTxt, 'center', cfg.winH - 40, grey);
    Screen('TextSize', w, 32);   % restore default

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

function relT = trigSendTimed(serialObj, cfg, code, t0)
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
        error('motor_planning:userQuit', 'User quit (Escape).');
    end