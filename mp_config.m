function cfg = mp_config()
%MP_CONFIG  Hardcoded configuration — only asks participant name
%
%   cfg = mp_config()

    % ── Participant (seul champ demandé) ──
    cfg.participant      = 'P01';
    cfg.session          = '01';

    answer = inputdlg('Participant ID :', 'Motor Planning', 1, {cfg.participant});
    if isempty(answer)
        error('motor_planning:cancelled', 'Cancelled.');
    end
    cfg.participant = strtrim(answer{1});

    % ── Screen (auto-detect last screen) ──
    cfg.screenId         = max(Screen('Screens'));

    % ── Design ──
    cfg.conditions       = {'grasp', 'touch'};
    cfg.nTrialsPerCond   = 10;
    cfg.maxConsec        = 3;
    cfg.effectorFirst    = 'hand';
    cfg.nRunsPerEffector = 4;

    % ── Timing (seconds) ──
    cfg.previewDur       = 2.0;
    cfg.planDur          = 5.5;
    cfg.planJitter       = 0.5;
    cfg.execDur          = 2.0;
    cfg.itiDur           = 8.0;
    cfg.baselineInit     = 10.0;
    cfg.baselineFinal    = 10.0;
    cfg.interRunPause    = 20.0;

    % ── Audio ──
    cfg.audioFs          = 44100;
    cfg.audioHwDelay     = 0.000;
    cfg.fillAhead        = 0.200;
    cfg.goBeepFreq       = 1000;
    cfg.goBeepDur        = 0.500;
    cfg.goBeepVol        = 0.70;
    cfg.soundDir         = fullfile(fileparts(mfilename('fullpath')), 'sounds');

    % ── Trigger codes (all have bit 1 = value 2 set) ──
    cfg.codes.trial_start =   2;
    cfg.codes.cue_grasp   =   6;
    cfg.codes.cue_touch   =  10;
    cfg.codes.go_grasp    =  18;
    cfg.codes.go_touch    =  34;
    cfg.codes.iti_start   =  66;
    cfg.codes.run_start   = 130;
    cfg.codes.run_end     = 134;

    % ── Serial port ──
    cfg.triggerActive    = true;
    cfg.serialPortName   = 'COM4';
    cfg.serialBaudRate   = 115200;
    cfg.trigPulseS       = 0.005;

    % ── Misc ──
    cfg.randomSeed       = round(mod(now * 1e6, 2^32));
    cfg.dataDir          = fullfile(fileparts(mfilename('fullpath')), ...
                                   'data', 'motor_planning');

    % ── Derived fields ──
    if strcmp(cfg.effectorFirst, 'hand'), second = 'tool';
    else,                                 second = 'hand';
    end
    cfg.runSequence = [repmat({cfg.effectorFirst}, 1, cfg.nRunsPerEffector), ...
                       repmat({second}, 1, cfg.nRunsPerEffector)];
    cfg.nRuns        = numel(cfg.runSequence);
    cfg.nTrialsTotal = numel(cfg.conditions) * cfg.nTrialsPerCond;

    fprintf('[OK] Config: %s | screen %d | %d runs | %d trials/run\n', ...
        cfg.participant, cfg.screenId, cfg.nRuns, cfg.nTrialsTotal);