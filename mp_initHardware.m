function [w, pa, serialObj, snd, cfg] = mp_initHardware(cfg)
%MP_INITHARDWARE  Initialize audio, screen, serial port, sounds
%
%   Includes a visible rendering test at the end to confirm display works.

    % ── Clean stale PTB state ─────────────────────────────────────────
    try InitializePsychSound(0); PsychPortAudio('Close'); catch, end
    try Screen('CloseAll'); catch, end
    WaitSecs(0.1);

    % ── PTB preferences ──────────────────────────────────────────────
    PsychDefaultSetup(2);
    KbName('UnifyKeyNames');
    cfg.keys.escape = KbName('ESCAPE');
    cfg.keys.q      = KbName('q');
    cfg.keys.space  = KbName('space');
    cfg.keys.enter  = KbName('Return');
    try
        cfg.keys.numEnter = KbName('Enter');
    catch
        cfg.keys.numEnter = cfg.keys.enter;
    end

    Screen('Preference', 'SkipSyncTests',    2);
    Screen('Preference', 'VisualDebugLevel', 1);
    Screen('Preference', 'Verbosity',        3);

    % ── Audio BEFORE screen ───────────────────────────────────────────
    fprintf('[INFO] Initializing audio...\n');
    InitializePsychSound(1);
    pa = openAudioDevice(cfg);

    s = PsychPortAudio('GetStatus', pa);
    cfg.actualFs = s.SampleRate;
    if s.SampleRate ~= cfg.audioFs
        fprintf('[INFO] Sample rate: %d -> %d Hz\n', cfg.audioFs, round(s.SampleRate));
        cfg.audioFs = s.SampleRate;
    end
    fprintf('[OK] Audio: %d Hz | latency %.1f ms\n', ...
        round(s.SampleRate), s.PredictedLatency * 1000);

    PsychPortAudio('FillBuffer', pa, zeros(2, round(cfg.audioFs * 0.01)));
    PsychPortAudio('Start', pa, 1, 0, 1);
    PsychPortAudio('Stop',  pa, 1);
    fprintf('[OK] Audio warmed up.\n');

    % ── Sounds ────────────────────────────────────────────────────────
    snd = loadSounds(cfg);

    % ── Screen ────────────────────────────────────────────────────────
    screenId = cfg.screenId;
    fprintf('[INFO] Opening fullscreen on screen %d...\n', screenId);

    cfg.black = BlackIndex(screenId);
    cfg.white = WhiteIndex(screenId);

    [w, wRect] = Screen('OpenWindow', screenId, 0);

    % Immediate validation
    try
        Screen('Flip', w);
        Screen('TextSize', w, 36);
        Screen('TextFont', w, 'Arial');
        Screen('BlendFunction', w, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');
    catch ME
        try PsychPortAudio('Close', pa); catch, end
        error('mp_initHardware:windowFailed', ...
            'Window validation failed: %s', ME.message);
    end

    HideCursor(screenId);

    [cfg.xc, cfg.yc] = RectCenter(wRect);
    cfg.ifi = Screen('GetFlipInterval', w);
    if cfg.ifi <= 0 || cfg.ifi > 0.1, cfg.ifi = 1/60; end
    cfg.halfIfi = cfg.ifi / 2;
    cfg.fps     = round(1 / cfg.ifi);
    cfg.winW    = wRect(3) - wRect(1);
    cfg.winH    = wRect(4) - wRect(2);

    fprintf('[OK] Window: %d x %d @ %d Hz on screen %d\n', ...
        cfg.winW, cfg.winH, cfg.fps, screenId);

    % ── Rendering test (visible proof that display works) ─────────────
    %   Shows a white rectangle + text for 2 seconds.
    %   If you see the rectangle but not the text: font issue.
    %   If you see nothing: window on wrong display.
    Screen('FillRect', w, [1 1 1], CenterRect([0 0 120 120], wRect));
    Screen('TextSize', w, 48);
    DrawFormattedText(w, sprintf('Display OK'), ...
        'center', cfg.yc + 100, [1 1 1]);
    Screen('Flip', w);
    WaitSecs(2.0);
    fprintf('[OK] Rendering test shown 2 seconds.\n');

    % ── Serial port ───────────────────────────────────────────────────
    serialObj = [];
    if cfg.triggerActive
        serialObj = openSerialPort(cfg);
    else
        fprintf('[INFO] Triggers DISABLED.\n');
    end

    fprintf('[OK] === Hardware ready ===\n');


% =====================================================================

function pa = openAudioDevice(cfg)
    for latClass = [3, 2, 1, 0]
        try
            pa = PsychPortAudio('Open', [], 1, latClass, cfg.audioFs, 2, [], []);
            fprintf('[OK] Audio latencyClass = %d\n', latClass);
            return;
        catch ME
            fprintf('[WARN] latencyClass %d: %s\n', latClass, ME.message);
        end
    end
    try
        pa = PsychPortAudio('Open', [], 1, 1, [], 2);
        fprintf('[OK] Audio (native rate)\n');
        return;
    catch ME2
        error('Audio failed: %s', ME2.message);
    end

function serialObj = openSerialPort(cfg)
    try
        avail = serialportlist("available");
        fprintf('[INFO] Serial ports: %s\n', strjoin(avail, ', '));
    catch
        avail = {};
    end
    try
        serialObj = serialport(cfg.serialPortName, cfg.serialBaudRate);
        serialObj.Timeout = 1;
        write(serialObj, uint8(0), 'uint8');
        WaitSecs(0.01);
        write(serialObj, uint8(255), 'uint8');
        WaitSecs(cfg.trigPulseS);
        write(serialObj, uint8(0), 'uint8');
        fprintf('[OK] Serial %s @ %d baud\n', cfg.serialPortName, cfg.serialBaudRate);
    catch ME
        warning('Serial failed: %s — simulation.', ME.message);
        serialObj = [];
        cfg.triggerActive = false;
    end

function snd = loadSounds(cfg)
    snd.grasp = loadOrGen(fullfile(cfg.soundDir, 'grasp.wav'), cfg.audioFs, 400, 0.5);
    snd.touch = loadOrGen(fullfile(cfg.soundDir, 'touch.wav'), cfg.audioFs, 600, 0.5);
    snd.go    = loadOrGen(fullfile(cfg.soundDir, 'beep.wav'),  cfg.audioFs, cfg.goBeepFreq, cfg.goBeepDur);
    snd.go    = snd.go * cfg.goBeepVol;
    names = fieldnames(snd);
    for i = 1:numel(names)
        fprintf('[OK] Sound %-6s: %.3f s\n', names{i}, size(snd.(names{i}),2)/cfg.audioFs);
    end

function buf = loadOrGen(filepath, fs, freq, dur)
    if exist(filepath, 'file')
        try
            [y, srcFs] = audioread(filepath);
            if srcFs ~= fs, y = resample(y, round(fs), srcFs); end
            if size(y,2) == 1, y = [y, y]; end
            pk = max(abs(y(:))); if pk > 0, y = y/pk*0.95; end
            buf = y';
            fprintf('[OK] Loaded: %s\n', filepath);
            return;
        catch, end
    end
    nSamp = round(fs * dur); t = (0:nSamp-1)/fs;
    nR = round(fs*0.01); ramp = ones(1,nSamp);
    ramp(1:nR) = 0.5*(1-cos(pi*(0:nR-1)/nR));
    ramp(end-nR+1:end) = 0.5*(1-cos(pi*(nR-1:-1:0)/nR));
    y = sin(2*pi*freq*t).*ramp*0.9;
    buf = [y; y];
    fprintf('[WARN] Generated tone %.0f Hz\n', freq);