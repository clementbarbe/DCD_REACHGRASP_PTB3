function [w, pa, ioObj, snd, cfg] = mp_initHardware(cfg)
%MP_INITHARDWARE  Initialize Psychtoolbox screen, audio, triggers, sounds
%
%   [w, pa, ioObj, snd, cfg] = mp_initHardware(cfg)
%
%   Sets up all hardware needed for the experiment:
%     1. PTB screen (with multi-monitor support via cfg.displayMode)
%     2. PsychPortAudio device (low-latency, with fallback)
%     3. io64 parallel port (for EEG triggers)
%     4. Sound stimuli (WAV files or fallback tones)
%
%   The cfg struct is updated with screen parameters (xc, yc, ifi, keys).
%
%   INPUTS:
%     cfg — Configuration struct from mp_config()
%
%   OUTPUTS:
%     w     — PTB window handle
%     pa    — PsychPortAudio device handle
%     ioObj — io64 object handle ([] if port disabled)
%     snd   — Struct with audio buffers: .grasp, .touch, .go (2×N stereo)
%     cfg   — Updated config with screen/audio parameters added
%
%   See also mp_config, motor_planning

    % ── Screen ────────────────────────────────────────────────────────
    PsychDefaultSetup(2);
    Screen('Preference', 'VisualDebugLevel', 3);
    KbName('UnifyKeyNames');
    cfg.keys.escape = KbName('ESCAPE');
    cfg.keys.q      = KbName('q');
    cfg.keys.space  = KbName('space');

    screenId  = max(Screen('Screens'));
    cfg.black = BlackIndex(screenId);
    cfg.white = WhiteIndex(screenId);

    [totalW, totalH] = Screen('WindowSize', screenId);
    fprintf('[INFO] Total resolution: %d x %d\n', totalW, totalH);

    % Compute display rectangle for multi-monitor setups
    switch cfg.displayMode
        case 'right'
            halfW = round(totalW / 2);
            screenRect = [halfW, 0, totalW, totalH];
        case 'left'
            halfW = round(totalW / 2);
            screenRect = [0, 0, halfW, totalH];
        case 'full'
            screenRect = [];
    end

    PsychImaging('PrepareConfiguration');
    PsychImaging('AddTask', 'General', 'UseVirtualFramebuffer');

    if isempty(screenRect)
        [w, wRect] = PsychImaging('OpenWindow', screenId, cfg.black, ...
            [], [], [], [], 4);
    else
        [w, wRect] = PsychImaging('OpenWindow', screenId, cfg.black, ...
            screenRect, [], [], [], 4);
    end

    [cfg.xc, cfg.yc] = RectCenter(wRect);
    cfg.ifi     = Screen('GetFlipInterval', w);
    cfg.halfIfi = cfg.ifi / 2;
    cfg.fps     = round(1 / cfg.ifi);

    Screen('TextSize', w, 32);
    Screen('TextFont', w, 'Arial');
    Screen('BlendFunction', w, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');
    HideCursor(screenId);

    fprintf('[OK] Window: %dx%d @ %d Hz (%.2f ms/frame) [%s]\n', ...
        wRect(3)-wRect(1), wRect(4)-wRect(2), ...
        cfg.fps, cfg.ifi*1000, cfg.displayMode);

    % ── Audio (PsychPortAudio) ────────────────────────────────────────
    InitializePsychSound(1);

    pa = openAudioDevice(cfg);

    s = PsychPortAudio('GetStatus', pa);
    cfg.actualFs = s.SampleRate;
    fprintf('[OK] Audio: %d Hz, predicted latency %.1f ms\n', ...
        s.SampleRate, s.PredictedLatency * 1000);

    % Warmup: play silence to prime the audio driver pipeline
    PsychPortAudio('FillBuffer', pa, zeros(2, round(cfg.audioFs * 0.01)));
    PsychPortAudio('Start', pa, 1, 0, 1);
    PsychPortAudio('Stop',  pa, 1);
    fprintf('[OK] Audio driver warmed up.\n');

    % ── Sounds ────────────────────────────────────────────────────────
    snd = loadSounds(cfg);

    % ── Parallel port ─────────────────────────────────────────────────
    ioObj = [];
    if cfg.parportActive
        try
            ioObj = io64;
            st = io64(ioObj);
            assert(st == 0, 'io64 returned status %d', st);
            io64(ioObj, cfg.parportAddr, 0);   % reset to zero
            fprintf('[OK] Parallel port @ 0x%04X\n', cfg.parportAddr);
        catch ME
            warning('Parallel port init failed: %s — simulation mode.', ...
                ME.message);
            ioObj = [];
            cfg.parportActive = false;
        end
    else
        fprintf('[INFO] Parallel port DISABLED (simulation mode).\n');
    end
end


% =====================================================================
%  LOCAL FUNCTIONS
% =====================================================================

function pa = openAudioDevice(cfg)
%OPENAUDIODEVICE  Open PsychPortAudio with progressive latency fallback
%   Tries latency classes 3→2→1→0. Class 3 uses WASAPI exclusive mode
%   on Windows for best timing; falls back gracefully if unavailable.
    for latClass = [3, 2, 1, 0]
        try
            pa = PsychPortAudio('Open', [], 1, latClass, ...
                cfg.audioFs, 2, [], []);
            fprintf('[OK] Audio opened (latencyClass = %d)\n', latClass);
            return;
        catch ME
            fprintf('[WARN] latencyClass %d failed: %s\n', ...
                latClass, ME.message);
            try PsychPortAudio('Close'); catch, end
        end
    end
    error('mp_initHardware:audioFailed', ...
        'Could not open audio device with any latency class.');
end


function snd = loadSounds(cfg)
%LOADSOUNDS  Load WAV files or generate fallback tones
%   Returns struct with fields .grasp, .touch, .go (2×N stereo matrices).
    snd.grasp = loadOrGenerate( ...
        fullfile(cfg.soundDir, 'grasp.wav'), cfg.audioFs, 400, 0.5);
    snd.touch = loadOrGenerate( ...
        fullfile(cfg.soundDir, 'touch.wav'), cfg.audioFs, 600, 0.5);
    snd.go    = loadOrGenerate( ...
        fullfile(cfg.soundDir, 'beep.wav'),  cfg.audioFs, ...
        cfg.goBeepFreq, cfg.goBeepDur);
    snd.go    = snd.go * cfg.goBeepVol;

    % Log durations
    names = fieldnames(snd);
    for i = 1:numel(names)
        dur = size(snd.(names{i}), 2) / cfg.audioFs;
        fprintf('[OK] Sound %-6s: %.3f s\n', names{i}, dur);
    end
end


function buf = loadOrGenerate(filepath, fs, fallbackFreq, fallbackDur)
%LOADORGENERATE  Load a WAV file; generate a pure tone if unavailable
%   Returns a 2×N stereo matrix normalized to [-0.95, 0.95].
    if exist(filepath, 'file')
        try
            [y, srcFs] = audioread(filepath);
            if srcFs ~= fs, y = resample(y, fs, srcFs); end
            if size(y, 2) == 1, y = [y, y]; end  % mono → stereo
            pk = max(abs(y(:)));
            if pk > 0, y = y / pk * 0.95; end
            buf = y';   % 2×N
            fprintf('[OK] Loaded: %s\n', filepath);
            return;
        catch ME
            warning('Failed to read %s: %s', filepath, ME.message);
        end
    end

    % Fallback: pure tone with cosine ramp
    buf = generateTone(fallbackFreq, fallbackDur, fs);
    fprintf('[WARN] Generated fallback tone (%.0f Hz) for %s\n', ...
        fallbackFreq, filepath);
end


function buf = generateTone(freq, dur, fs)
%GENERATETONE  Stereo sinusoidal tone with 10 ms cosine onset/offset ramps
    nSamp = round(fs * dur);
    t     = (0:nSamp-1) / fs;

    % Cosine ramp (10 ms)
    nRamp = round(fs * 0.010);
    ramp  = ones(1, nSamp);
    ramp(1:nRamp)         = 0.5 * (1 - cos(pi * (0:nRamp-1)   / nRamp));
    ramp(end-nRamp+1:end) = 0.5 * (1 - cos(pi * (nRamp-1:-1:0)/ nRamp));

    y   = sin(2*pi*freq*t) .* ramp * 0.9;
    buf = [y; y];   % stereo (2×N)
end