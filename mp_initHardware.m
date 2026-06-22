function [w, pa, ioObj, snd, cfg] = mp_initHardware(cfg)
%MP_INITHARDWARE  Initialize audio, screen, parallel port, and sounds
%
%   [w, pa, ioObj, snd, cfg] = mp_initHardware(cfg)
%
%   INIT ORDER (important for Win11 stability):
%     1. Clean stale PTB state
%     2. Audio (before screen — so audio fallback can't kill window)
%     3. Sounds
%     4. Fullscreen window on cfg.screenId
%     5. Parallel port
%
%   See also mp_config, motor_planning

    % ── Step 0: Clean stale PTB state ─────────────────────────────────
    try PsychPortAudio('Close'); catch, end
    try Screen('CloseAll');      catch, end
    WaitSecs(0.1);

    % ── Step 1: PTB preferences ───────────────────────────────────────
    PsychDefaultSetup(2);
    KbName('UnifyKeyNames');
    cfg.keys.escape  = KbName('ESCAPE');
    cfg.keys.q       = KbName('q');
    cfg.keys.space   = KbName('space');
    cfg.keys.enter   = KbName('Return');
    cfg.keys.numEnter = KbName('b');   % numpad enter (different keycode)

    Screen('Preference', 'SkipSyncTests',    2);
    Screen('Preference', 'VisualDebugLevel', 1);
    Screen('Preference', 'Verbosity',        3);
    fprintf('[OK] PTB preferences set (SkipSyncTests=2 for Win11/DWM).\n');

    % ── Step 2: Audio BEFORE screen ───────────────────────────────────
    fprintf('[INFO] Initializing audio...\n');
    InitializePsychSound(1);
    pa = openAudioDevice(cfg);

    s = PsychPortAudio('GetStatus', pa);
    cfg.actualFs = s.SampleRate;
    if s.SampleRate ~= cfg.audioFs
        fprintf('[INFO] Sample rate adapted: %d -> %d Hz\n', ...
            cfg.audioFs, round(s.SampleRate));
        cfg.audioFs = s.SampleRate;
    end
    fprintf('[OK] Audio: %d Hz | output latency %.1f ms\n', ...
        round(s.SampleRate), s.PredictedLatency * 1000);

    PsychPortAudio('FillBuffer', pa, zeros(2, round(cfg.audioFs * 0.01)));
    PsychPortAudio('Start', pa, 1, 0, 1);
    PsychPortAudio('Stop',  pa, 1);
    fprintf('[OK] Audio driver warmed up.\n');

    % ── Step 3: Sounds ────────────────────────────────────────────────
    snd = loadSounds(cfg);

    % ── Step 4: Screen AFTER audio ────────────────────────────────────
    screenId = cfg.screenId;

    screens = Screen('Screens');
    fprintf('[INFO] Screens:');
    for si = 1:numel(screens)
        [sw, sh] = Screen('WindowSize', screens(si));
        tag = ''; if screens(si) == screenId, tag = ' <<<'; end
        fprintf('  %d:%dx%d%s', screens(si), sw, sh, tag);
    end
    fprintf('\n');

    assert(ismember(screenId, screens), ...
        'Screen %d not found! Available: %s', screenId, num2str(screens));

    cfg.black = BlackIndex(screenId);
    cfg.white = WhiteIndex(screenId);

    fprintf('[INFO] Opening fullscreen on screen %d...\n', screenId);
    [w, wRect] = Screen('OpenWindow', screenId, cfg.black);
    fprintf('[INFO] Window handle = %d | rect = [%d %d %d %d]\n', ...
        w, wRect(1), wRect(2), wRect(3), wRect(4));

    % Validate immediately
    try
        Screen('Flip', w);
        Screen('TextSize', w, 32);
        Screen('TextFont', w, 'Arial');
        Screen('BlendFunction', w, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');
    catch ME
        try PsychPortAudio('Close', pa); catch, end
        error('mp_initHardware:windowInvalid', ...
            'Window validation failed on screen %d: %s', screenId, ME.message);
    end
    fprintf('[OK] Window validated.\n');

    HideCursor(screenId);

    [cfg.xc, cfg.yc] = RectCenter(wRect);
    cfg.ifi = Screen('GetFlipInterval', w);
    if cfg.ifi <= 0 || cfg.ifi > 0.1
        warning('Unusual flip interval %.4f s — using OS-reported rate.', cfg.ifi);
        cfg.ifi = 1/120;
    end
    cfg.halfIfi = cfg.ifi / 2;
    cfg.fps     = round(1 / cfg.ifi);
    cfg.winW    = wRect(3) - wRect(1);
    cfg.winH    = wRect(4) - wRect(2);

    fprintf('[OK] Window: %d x %d @ %d Hz (%.2f ms/frame) on screen %d\n', ...
        cfg.winW, cfg.winH, cfg.fps, cfg.ifi*1000, screenId);

    % ── Step 5: Parallel port ─────────────────────────────────────────
    ioObj = [];
    if cfg.parportActive
        try
            ioObj = io64;
            st = io64(ioObj);
            assert(st == 0, 'io64 returned status %d', st);
            io64(ioObj, cfg.parportAddr, 0);
            fprintf('[OK] Parallel port @ 0x%04X\n', cfg.parportAddr);
        catch ME
            warning('Parallel port failed: %s — simulation mode.', ME.message);
            ioObj = [];
            cfg.parportActive = false;
        end
    else
        fprintf('[INFO] Parallel port DISABLED.\n');
    end

    % ── Step 6: Final end-to-end test ─────────────────────────────────
    DrawFormattedText(w, 'Initializing...', 'center', 'center', cfg.white);
    Screen('Flip', w);
    WaitSecs(0.5);

    fprintf('[OK] === Hardware initialization complete ===\n');


% =====================================================================
%  LOCAL FUNCTIONS
% =====================================================================

function pa = openAudioDevice(cfg)
%OPENAUDIODEVICE  Open PsychPortAudio with latency class fallback 3->2->1->0
    for latClass = [3, 2, 1, 0]
        try
            pa = PsychPortAudio('Open', [], 1, latClass, cfg.audioFs, 2, [], []);
            fprintf('[OK] Audio opened (latencyClass = %d)\n', latClass);
            return;
        catch ME
            fprintf('[WARN] latencyClass %d: %s\n', latClass, ME.message);
        end
    end

    fprintf('[INFO] Retrying with device native sample rate...\n');
    try
        pa = PsychPortAudio('Open', [], 1, 1, [], 2);
        fprintf('[OK] Audio opened (native rate, latencyClass 1)\n');
        return;
    catch ME2
        error('mp_initHardware:audioFailed', ...
            'Could not open audio device: %s', ME2.message);
    end


function snd = loadSounds(cfg)
%LOADSOUNDS  Load WAV files or generate fallback tones
    snd.grasp = loadOrGenerate(fullfile(cfg.soundDir, 'grasp.wav'), cfg.audioFs, 400, 0.5);
    snd.touch = loadOrGenerate(fullfile(cfg.soundDir, 'touch.wav'), cfg.audioFs, 600, 0.5);
    snd.go    = loadOrGenerate(fullfile(cfg.soundDir, 'beep.wav'),  cfg.audioFs, cfg.goBeepFreq, cfg.goBeepDur);
    snd.go    = snd.go * cfg.goBeepVol;

    names = fieldnames(snd);
    for i = 1:numel(names)
        dur = size(snd.(names{i}), 2) / cfg.audioFs;
        fprintf('[OK] Sound %-6s: %.3f s (%d samples @ %d Hz)\n', ...
            names{i}, dur, size(snd.(names{i}), 2), round(cfg.audioFs));
    end


function buf = loadOrGenerate(filepath, fs, fallbackFreq, fallbackDur)
%LOADORGENERATE  Load WAV or generate fallback pure tone (2xN stereo)
    if exist(filepath, 'file')
        try
            [y, srcFs] = audioread(filepath);
            if srcFs ~= fs, y = resample(y, round(fs), srcFs); end
            if size(y, 2) == 1, y = [y, y]; end
            pk = max(abs(y(:)));
            if pk > 0, y = y / pk * 0.95; end
            buf = y';
            fprintf('[OK] Loaded: %s\n', filepath);
            return;
        catch ME
            warning('Failed to read %s: %s', filepath, ME.message);
        end
    end
    buf = generateTone(fallbackFreq, fallbackDur, fs);
    fprintf('[WARN] Fallback tone (%.0f Hz) for %s\n', fallbackFreq, filepath);


function buf = generateTone(freq, dur, fs)
%GENERATETONE  Stereo sine tone with 10 ms cosine ramps
    nSamp = round(fs * dur);
    t     = (0:nSamp-1) / fs;
    nRamp = round(fs * 0.010);
    ramp  = ones(1, nSamp);
    ramp(1:nRamp)         = 0.5 * (1 - cos(pi * (0:nRamp-1)   / nRamp));
    ramp(end-nRamp+1:end) = 0.5 * (1 - cos(pi * (nRamp-1:-1:0)/ nRamp));
    y   = sin(2*pi*freq*t) .* ramp * 0.9;
    buf = [y; y];