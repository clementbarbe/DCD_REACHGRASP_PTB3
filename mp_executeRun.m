function T = mp_executeRun(w, pa, ioObj, snd, T, t0, cfg)
%MP_EXECUTERUN  Execute all trials of one run with precise audio timing
%
%   T = mp_executeRun(w, pa, ioObj, snd, T, t0, cfg)
%
%   Sequentially executes each trial of the pre-computed timeline:
%
%     PREVIEW  — Fixation cross + trial_start trigger
%     CUE      — Scheduled audio playback + cue trigger
%     PLAN     — Passive waiting (5.5 ± 0.5 s)
%     GO       — Scheduled go beep + go trigger
%     EXECUTE  — Participant performs movement (2 s)
%     ITI      — Inter-trial interval + iti trigger (8 s)
%
%   AUDIO SCHEDULING STRATEGY:
%     1. Buffer is filled 200 ms before target onset
%     2. PsychPortAudio('Start', pa, 1, WHEN, 1) schedules playback
%        at a precise future time and blocks until DAC onset
%     3. Trigger is sent immediately after confirmed onset (< 0.2 ms delay)
%     4. audioHwDelay compensates DAC→speaker latency (optional)
%
%   INPUTS:
%     w     — PTB window handle
%     pa    — PsychPortAudio device handle
%     ioObj — io64 object ([] if simulation mode)
%     snd   — Struct with .grasp, .touch, .go audio buffers (2×N)
%     T     — Pre-computed timeline from mp_buildDesign (struct array)
%     t0    — Run epoch time (GetSecs value at run start)
%     cfg   — Configuration struct
%
%   OUTPUTS:
%     T — Timeline with actual onset times and scheduling errors filled in
%
%   See also mp_buildDesign, motor_planning

    nTrials = numel(T);

    for ti = 1:nTrials
        tr = T(ti);

        checkQuit(cfg);

        % ── PREVIEW ──────────────────────────────────────────────────
        mp_drawFixation(w, cfg);
        vbl = Screen('Flip', w, t0 + tr.previewOnset - cfg.halfIfi);
        tr.actualPreviewVbl = vbl - t0;
        trigSend(ioObj, cfg, cfg.codes.trial_start);

        % ── CUE AUDIO ───────────────────────────────────────────────
        cueBuf    = snd.(tr.condition);    % dynamic field: 'grasp' or 'touch'
        targetCue = t0 + tr.cueOnset;

        spinWaitUntil(targetCue - cfg.fillAhead);
        PsychPortAudio('Stop', pa, 0);
        PsychPortAudio('FillBuffer', pa, cueBuf);

        checkQuit(cfg);

        % Schedule playback (or start immediately if late)
        nowT = GetSecs;
        if nowT > targetCue - 0.010
            warning('CUE LATE trial %d: %.1f ms', ti, (nowT-targetCue)*1000);
            actualCue = PsychPortAudio('Start', pa, 1, 0, 1);
        else
            actualCue = PsychPortAudio('Start', pa, 1, targetCue, 1);
        end

        % Wait for DAC→speaker delay, then send trigger
        if cfg.audioHwDelay > 0
            spinWaitUntil(actualCue + cfg.audioHwDelay);
        end
        tr.actualCueTriggerT = trigSendTimed(ioObj, cfg, tr.cueCode, t0);
        tr.actualCueDacOnset = actualCue - t0;
        tr.cueSchedErrorMs   = (actualCue - targetCue) * 1000;

        % ── PLAN PERIOD (passive) ────────────────────────────────────
        checkQuit(cfg);

        % ── GO BEEP ─────────────────────────────────────────────────
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

        % ── ITI ──────────────────────────────────────────────────────
        spinWaitUntil(t0 + tr.itiOnset);
        tr.actualItiTriggerT = trigSendTimed(ioObj, cfg, cfg.codes.iti_start, t0);

        mp_drawFixation(w, cfg);
        Screen('Flip', w);

        % ── Store and log ────────────────────────────────────────────
        T(ti) = tr;
        fprintf('  Trial %2d/%d (%s) | cue %+.2f ms | go %+.2f ms\n', ...
            ti, nTrials, tr.condition, tr.cueSchedErrorMs, tr.goSchedErrorMs);
    end
end


% =====================================================================
%  LOCAL FUNCTIONS — Timing & trigger utilities
% =====================================================================

function spinWaitUntil(targetSecs)
%SPINWAITUNTIL  High-precision blocking wait
%   Yields CPU until 0.5 ms before target, then busy-waits the remainder.
%   Total precision: < 0.05 ms overshoot typical.
    while (targetSecs - GetSecs) > 0.0005
        WaitSecs('YieldSecs', 0.00005);
    end
    while GetSecs < targetSecs, end
end


function relT = trigSendTimed(ioObj, cfg, code, t0)
%TRIGSENDTIMED  Send parallel port trigger pulse and return onset time
%   Returns the time of the rising edge relative to t0.
%   Pulse width: cfg.trigPulseS (default 5 ms).
    if cfg.parportActive && ~isempty(ioObj) && code > 0
        io64(ioObj, cfg.parportAddr, code);
        absT = GetSecs;
        WaitSecs(cfg.trigPulseS);
        io64(ioObj, cfg.parportAddr, 0);
    else
        absT = GetSecs;
    end
    relT = absT - t0;
end


function trigSend(ioObj, cfg, code)
%TRIGSEND  Send parallel port trigger pulse (no timing return)
    if cfg.parportActive && ~isempty(ioObj) && code > 0
        io64(ioObj, cfg.parportAddr, code);
        WaitSecs(cfg.trigPulseS);
        io64(ioObj, cfg.parportAddr, 0);
    end
end


function checkQuit(cfg)
%CHECKQUIT  Check for Escape or Q keypress — throws error for clean exit
    [kd, ~, kc] = KbCheck(-1);
    if kd && (kc(cfg.keys.escape) || kc(cfg.keys.q))
        error('motor_planning:userQuit', 'User quit (Escape/Q).');
    end
end