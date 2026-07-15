function [w, pa, serialObj, snd, cfg] = mp_initHardware(cfg)
%MP_INITHARDWARE  Initialize audio, screen, serial port, sounds
%   Colors are 0-255 integers (NOT 0.0-1.0 floats) for max compatibility.

    % ── Clean stale state ─────────────────────────────────────────────
    try InitializePsychSound(0); PsychPortAudio('Close'); catch, end
    try Screen('CloseAll'); catch, end
    WaitSecs(0.2);

    % ── PTB setup — level 1 (colors stay 0-255) ──────────────────────
    %   PsychDefaultSetup(1) = UnifyKeyNames only
    %   PsychDefaultSetup(2) = + normalize colors to 0-1 (UNRELIABLE on some Win11 systems)
    PsychDefaultSetup(1);
    KbName('UnifyKeyNames');
    cfg.keys.escape = KbName('ESCAPE');
    cfg.keys.q      = KbName('q');
    cfg.keys.space  = KbName('space');
    cfg.keys.enter  = KbName('Return');
    try cfg.keys.numEnter = KbName('Enter');
    catch, cfg.keys.numEnter = cfg.keys.enter;
    end

    Screen('Preference', 'SkipSyncTests',    2);
    Screen('Preference', 'VisualDebugLevel', 0);
    Screen('Preference', 'Verbosity',        3);

    % ── Colors: always 0-255 integers ─────────────────────────────────
    cfg.black = 0;
    cfg.white = 255;
    cfg.grey  = 80;

    % ── Audio BEFORE screen ───────────────────────────────────────────
    fprintf('[INFO] Audio...\n');
    InitializePsychSound(1);
    pa = openAudio(cfg);

    s = PsychPortAudio('GetStatus', pa);
    cfg.actualFs = s.SampleRate;
    if s.SampleRate ~= cfg.audioFs
        cfg.audioFs = s.SampleRate;
    end
    fprintf('[OK] Audio: %d Hz\n', round(s.SampleRate));

    PsychPortAudio('FillBuffer', pa, zeros(2, round(cfg.audioFs * 0.01)));
    PsychPortAudio('Start', pa, 1, 0, 1);
    PsychPortAudio('Stop',  pa, 1);

    % ── Sounds ────────────────────────────────────────────────────────
    snd = loadSounds(cfg);

    % ── Screen ────────────────────────────────────────────────────────
    screenId = cfg.screenId;
    fprintf('[INFO] Opening screen %d...\n', screenId);

    [w, wRect] = Screen('OpenWindow', screenId, cfg.black);

    % Validate: draw something visible immediately
    try
        Screen('TextSize', w, 48);
        Screen('TextFont', w, 'Arial');
        Screen('DrawText', w, 'Display OK', 100, 100, cfg.white);
        Screen('Flip', w);
        WaitSecs(1.0);
        fprintf('[OK] Display OK — text visible at (100,100).\n');
    catch ME
        try PsychPortAudio('Close', pa); catch, end
        error('Window failed: %s', ME.message);
    end

    HideCursor(screenId);

    [cfg.xc, cfg.yc] = RectCenter(wRect);
    cfg.ifi = Screen('GetFlipInterval', w);
    if cfg.ifi <= 0 || cfg.ifi > 0.1, cfg.ifi = 1/60; end
    cfg.halfIfi = cfg.ifi / 2;
    cfg.fps     = round(1 / cfg.ifi);
    cfg.winW    = wRect(3) - wRect(1);
    cfg.winH    = wRect(4) - wRect(2);

    fprintf('[OK] Window: %dx%d @ %d Hz on screen %d\n', ...
        cfg.winW, cfg.winH, cfg.fps, screenId);

    % ── Serial port ───────────────────────────────────────────────────
    serialObj = [];
    if cfg.triggerActive
        serialObj = openSerial(cfg);
    end

    fprintf('[OK] Hardware ready.\n');


% =====================================================================

function pa = openAudio(cfg)
    for lc = [3, 2, 1, 0]
        try
            pa = PsychPortAudio('Open', [], 1, lc, cfg.audioFs, 2, [], []);
            fprintf('[OK] Audio latencyClass=%d\n', lc);
            return;
        catch, end
    end
    try
        pa = PsychPortAudio('Open', [], 1, 1, [], 2);
        return;
    catch ME
        error('Audio failed: %s', ME.message);
    end

function serialObj = openSerial(cfg)
    try
        serialObj = serialport(cfg.serialPortName, cfg.serialBaudRate);
        serialObj.Timeout = 1;
        write(serialObj, uint8(0), 'uint8');
        WaitSecs(0.01);
        fprintf('[OK] Serial %s\n', cfg.serialPortName);
    catch ME
        warning('Serial failed: %s', ME.message);
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
            if size(y,2)==1, y=[y,y]; end
            pk = max(abs(y(:))); if pk>0, y=y/pk*0.95; end
            buf = y'; return;
        catch, end
    end
    nS = round(fs*dur); t = (0:nS-1)/fs;
    nR = round(fs*0.01); r = ones(1,nS);
    r(1:nR) = 0.5*(1-cos(pi*(0:nR-1)/nR));
    r(end-nR+1:end) = 0.5*(1-cos(pi*(nR-1:-1:0)/nR));
    y = sin(2*pi*freq*t).*r*0.9;
    buf = [y;y];