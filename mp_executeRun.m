function T = mp_executeRun(w, pa, ioObj, snd, T, t0, cfg)
%MP_EXECUTERUN  Execute all trials of one run with precise audio timing
%
%   T = mp_executeRun(w, pa, ioObj, snd, T, t0, cfg)
%
%   AUDIO SCHEDULING:
%     1. Buffer filled 200 ms before target onset
%     2. PsychPortAudio('Start', pa, 1, WHEN, 1) blocks until DAC onset
%     3. Trigger sent immediately after (< 0.2 ms coupling)
%     4. audioHwDelay compensates DAC-to-speaker latency
%
%   See also mp_buildDesign, motor_planning

    nTrials = numel(T);

    for ti = 1:nTrials
        tr = T(ti);

        checkQuit(cfg);

        % ── PREVIEW ──────────────────────────────────────────────
        mp_drawFixation(w, cfg);
        vbl = Screen('Flip', w, t0 + tr.previewOnset - cfg.halfIfi);
        tr.actualPreviewVbl = vbl - t0;
        trigSend(ioObj, cfg, cfg.codes.trial_start);

        % ── CUE AUDIO ───────────────────────────────────────────
        cueBuf    = snd.(tr.condition);
        targetCue = t0 + tr.cueOnset;

        spinWaitUntil(targetCue - cfg.fillAhead);
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
        tr.actualCueTriggerT = trigSendTimed(ioObj, cfg, tr.cueCode, t0);
        tr.actualCueDacOnset = actualCue - t0;
        tr.cueSchedErrorMs   = (actualCue - targetCue) * 1000;

        % ── PLAN PERIOD ──────────────────────────────────────────
        checkQuit(cfg);

        % ── GO BEEP ─────────────────────────────────────────────
        targetGo = t0 + tr.goOnset;

        spinWaitUntil(targetGo - cfg.fillAhead);
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
        tr.actualGoTriggerT = trigSendTimed(ioObj, cfg, tr.goCode, t0);
        tr.actualGoDacOnset = actualGo - t0;
        tr.goSchedErrorMs   = (actualGo - targetGo) * 1000;

        % ── ITI ──────────────────────────────────────────────────
        spinWaitUntil(t0 + tr.itiOnset);
        tr.actualItiTriggerT = trigSendTimed(ioObj, cfg, cfg.codes.iti_start, t0);

        mp_drawFixation(w, cfg);
        Screen('Flip', w);

        T(ti) = tr;
        fprintf('  Trial %2d/%d (%s) | cue %+.2f ms | go %+.2f ms\n', ...
            ti, nTrials, tr.condition, tr.cueSchedErrorMs, tr.goSchedErrorMs);
    end


% =====================================================================

function spinWaitUntil(targetSecs)
%SPINWAITUNTIL  Yield CPU then busy-wait for last 0.5 ms
    while (targetSecs - GetSecs) > 0.0005
        WaitSecs('YieldSecs', 0.00005);
    end
    while GetSecs < targetSecs
    end

function relT = trigSendTimed(ioObj, cfg, code, t0)
%TRIGSENDTIMED  Parallel port pulse, returns rising-edge time relative to t0
    if cfg.parportActive && ~isempty(ioObj) && code > 0
        io64(ioObj, cfg.parportAddr, code);
        absT = GetSecs;
        WaitSecs(cfg.trigPulseS);
        io64(ioObj, cfg.parportAddr, 0);
    else
        absT = GetSecs;
    end
    relT = absT - t0;

function trigSend(ioObj, cfg, code)
%TRIGSEND  Parallel port pulse, no timing return
    if cfg.parportActive && ~isempty(ioObj) && code > 0
        io64(ioObj, cfg.parportAddr, code);
        WaitSecs(cfg.trigPulseS);
        io64(ioObj, cfg.parportAddr, 0);
    end

function checkQuit(cfg)
%CHECKQUIT  Throw error on ESC/Q for clean exit
    [kd, ~, kc] = KbCheck(-1);
    if kd && (kc(cfg.keys.escape) || kc(cfg.keys.q))
        error('motor_planning:userQuit', 'User quit (Escape/Q).');
    end