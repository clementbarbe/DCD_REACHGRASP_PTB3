function cfg = mp_config()
%MP_CONFIG  Configuration avec dialogue simplifie
%
%   Mode 1 = 4 runs, effecteur unique
%   Mode 2 = 8 runs (4+4), deux effecteurs
%   maxConsec = 2 (jamais 3 identiques d'affilee)

    cfg = getDefaults();
    cfg = showDialog(cfg);
    cfg = buildSession(cfg);


function cfg = getDefaults()

    cfg.participant      = 'P01';
    cfg.session          = '01';
    cfg.screenId         = max(Screen('Screens'));

    cfg.protocolMode     = 2;        % 1=4 runs, 2=8 runs
    cfg.effector         = 'hand';   % mode1: lequel / mode2: premier

    cfg.conditions       = {'grasp', 'touch'};
    cfg.nTrialsPerCond   = 10;
    cfg.maxConsec        = 2;        % jamais plus de 2 identiques

    cfg.nRunsPerEffector = 4;

    cfg.previewDur       = 2.0;
    cfg.planDur          = 5.5;
    cfg.planJitter       = 0.5;
    cfg.execDur          = 2.0;
    cfg.itiDur           = 8.0;
    cfg.baselineInit     = 5.0;
    cfg.baselineFinal    = 5.0;
    cfg.interRunPause    = 20.0;

    cfg.audioFs          = 44100;
    cfg.audioHwDelay     = 0.000;
    cfg.fillAhead        = 0.200;
    cfg.goBeepFreq       = 1000;
    cfg.goBeepDur        = 0.500;
    cfg.goBeepVol        = 0.70;
    cfg.soundDir         = fullfile(fileparts(mfilename('fullpath')), 'sounds');

    cfg.codes.trial_start =   2;
    cfg.codes.cue_grasp   =   6;
    cfg.codes.cue_touch   =  10;
    cfg.codes.go_grasp    =  18;
    cfg.codes.go_touch    =  34;
    cfg.codes.iti_start   =  66;
    cfg.codes.run_start   = 130;
    cfg.codes.run_end     = 134;

    cfg.triggerActive    = true;
    cfg.serialPortName   = 'COM4';
    cfg.serialBaudRate   = 115200;
    cfg.trigPulseS       = 0.005;

    cfg.randomSeed       = round(mod(now * 1e6, 2^32));
    cfg.dataDir          = fullfile(fileparts(mfilename('fullpath')), ...
                                   'data', 'motor_planning');


function cfg = showDialog(cfg)

    prompt = { ...
        'Participant ID :', ...
        'Mode (1 = 4 runs effecteur unique, 2 = 8 runs complet) :', ...
        'Effecteur (hand / tool) :', ...
        'Duree plan (s) :', ...
        'Jitter +/- (s) :', ...
        'Duree execution apres Go (s) :', ...
        'ITI (s) :', ...
        'Pause inter-run (s) :'};
    defaults = { ...
        cfg.participant, ...
        num2str(cfg.protocolMode), ...
        cfg.effector, ...
        num2str(cfg.planDur), ...
        num2str(cfg.planJitter), ...
        num2str(cfg.execDur), ...
        num2str(cfg.itiDur), ...
        num2str(cfg.interRunPause)};

    answers = inputdlg(prompt, 'Motor Planning', 1, defaults);
    if isempty(answers)
        error('motor_planning:cancelled', 'Annule.');
    end

    cfg.participant   = strtrim(answers{1});
    cfg.protocolMode  = str2double(answers{2});
    cfg.effector      = lower(strtrim(answers{3}));
    cfg.planDur       = str2double(answers{4});
    cfg.planJitter    = str2double(answers{5});
    cfg.execDur       = str2double(answers{6});
    cfg.itiDur        = str2double(answers{7});
    cfg.interRunPause = str2double(answers{8});


function cfg = buildSession(cfg)

    assert(ismember(cfg.protocolMode, [1 2]), 'Mode doit etre 1 ou 2.');
    assert(ismember(cfg.effector, {'hand','tool'}), 'Effecteur: hand ou tool.');

    cfg.nTrialsTotal = numel(cfg.conditions) * cfg.nTrialsPerCond;

    if cfg.protocolMode == 1
        cfg.runSequence = repmat({cfg.effector}, 1, cfg.nRunsPerEffector);
    else
        if strcmp(cfg.effector, 'hand'), second = 'tool';
        else,                            second = 'hand';
        end
        cfg.runSequence = [repmat({cfg.effector}, 1, cfg.nRunsPerEffector), ...
                           repmat({second}, 1, cfg.nRunsPerEffector)];
    end
    cfg.nRuns = numel(cfg.runSequence);

    fprintf('[OK] Mode %d | %s | %d runs | %d essais/run | maxConsec=%d\n', ...
        cfg.protocolMode, cfg.effector, cfg.nRuns, cfg.nTrialsTotal, cfg.maxConsec);
    fprintf('[OK] Plan=%.1f+/-%.1fs | Exec=%.1fs | ITI=%.1fs | Pause=%.0fs\n', ...
        cfg.planDur, cfg.planJitter, cfg.execDur, cfg.itiDur, cfg.interRunPause);