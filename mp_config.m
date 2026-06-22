function cfg = mp_config()
%MP_CONFIG  Configure the motor planning experiment
%
%   cfg = mp_config()
%
%   Shows a GUI dialog, validates parameters, builds the run sequence.
%   Returns a complete configuration struct used by all other mp_* functions.
%
%   See also motor_planning, mp_initHardware, mp_buildDesign

    cfg = getDefaults();
    cfg = showDialog(cfg);
    cfg = finalizeConfig(cfg);


function cfg = getDefaults()
%GETDEFAULTS  All default parameters in one place

    cfg.participant      = 'P01';
    cfg.session          = '01';
    cfg.screenId         = 1;

    cfg.conditions       = {'grasp', 'touch'};
    cfg.nTrialsPerCond   = 10;
    cfg.nTrialsTotal     = 20;
    cfg.maxConsec        = 3;

    cfg.effectorFirst    = 'hand';
    cfg.nRunsPerEffector = 4;
    cfg.nRuns            = 8;

    cfg.previewDur       = 2.0;
    cfg.planDur          = 5.5;
    cfg.planJitter       = 0.5;
    cfg.execDur          = 2.0;
    cfg.itiDur           = 8.0;
    cfg.baselineInit     = 10.0;
    cfg.baselineFinal    = 10.0;
    cfg.interRunPause    = 20.0;

    cfg.audioFs          = 44100;
    cfg.audioHwDelay     = 0.000;
    cfg.fillAhead        = 0.200;
    cfg.goBeepFreq       = 1000;
    cfg.goBeepDur        = 0.500;
    cfg.goBeepVol        = 0.70;
    cfg.soundDir         = fullfile(fileparts(mfilename('fullpath')), 'sounds');

    cfg.codes.run_start  = 2;
    cfg.codes.run_end    = 6;
    cfg.codes.trial_start=  10;
    cfg.codes.cue_grasp  =  18;
    cfg.codes.cue_touch  =  34;
    cfg.codes.go_grasp   =  66;
    cfg.codes.go_touch   =  130;
    cfg.codes.iti_start  =  255;

    cfg.parportActive    = true;
    cfg.parportAddr      = hex2dec('3FF8');
    cfg.trigPulseS       = 0.005;

    cfg.randomSeed       = round(mod(now * 1e6, 2^32));

    cfg.dataDir          = fullfile(fileparts(mfilename('fullpath')), ...
                                   'data', 'motor_planning');


function cfg = showDialog(cfg)
%SHOWDIALOG  GUI dialog for user-configurable parameters

    screens = Screen('Screens');
    screenList = '';
    for si = 1:numel(screens)
        [sw, sh] = Screen('WindowSize', screens(si));
        screenList = [screenList, sprintf('  %d: %dx%d', screens(si), sw, sh)]; %#ok<AGROW>
        if si < numel(screens), screenList = [screenList, '  |']; end %#ok<AGROW>
    end

    prompt = { ...
        'Participant ID:', ...
        'Session:', ...
        sprintf('Screen index [available: %s ]:', screenList), ...
        'First effector (hand / tool):', ...
        'Parallel port active (1/0):', ...
        'Port address (hex):', ...
        'Audio HW delay (s):', ...
        'Random seed:', ...
        'Inter-run pause (s):'};
    defaults = { ...
        cfg.participant, ...
        cfg.session, ...
        num2str(cfg.screenId), ...
        cfg.effectorFirst, ...
        num2str(cfg.parportActive), ...
        dec2hex(cfg.parportAddr), ...
        num2str(cfg.audioHwDelay), ...
        num2str(cfg.randomSeed), ...
        num2str(cfg.interRunPause)};

    answers = inputdlg(prompt, 'Motor Planning — Configuration', 1, defaults);
    if isempty(answers)
        error('motor_planning:cancelled', 'Configuration cancelled.');
    end

    cfg.participant   = strtrim(answers{1});
    cfg.session       = strtrim(answers{2});
    cfg.screenId      = str2double(answers{3});
    cfg.effectorFirst = lower(strtrim(answers{4}));
    cfg.parportActive = str2double(answers{5}) == 1;
    cfg.parportAddr   = hex2dec(strtrim(answers{6}));
    cfg.audioHwDelay  = str2double(answers{7});
    cfg.randomSeed    = round(str2double(answers{8}));
    cfg.interRunPause = str2double(answers{9});


function cfg = finalizeConfig(cfg)
%FINALIZECONFIG  Validate parameters and build derived fields

    screens = Screen('Screens');
    if ~ismember(cfg.screenId, screens)
        error('Screen %d not found. Available: %s', cfg.screenId, num2str(screens));
    end

    assert(ismember(cfg.effectorFirst, {'hand','tool'}), ...
        'Invalid effectorFirst: "%s".', cfg.effectorFirst);

    if strcmp(cfg.effectorFirst, 'hand'), second = 'tool';
    else,                                 second = 'hand';
    end
    cfg.runSequence = [ ...
        repmat({cfg.effectorFirst}, 1, cfg.nRunsPerEffector), ...
        repmat({second},            1, cfg.nRunsPerEffector)];
    cfg.nRuns = numel(cfg.runSequence);

    cfg.nTrialsTotal = numel(cfg.conditions) * cfg.nTrialsPerCond;

    if cfg.parportActive && ~ispc
        warning('Parallel port requires Windows — disabled.');
        cfg.parportActive = false;
    end

    flds = fieldnames(cfg.codes);
    vals = cellfun(@(f) cfg.codes.(f), flds);
    assert(numel(vals) == numel(unique(vals)), 'Duplicate trigger codes!');

    fprintf('[OK] Config validated: screen %d | %d runs | %d trials/run | %d triggers\n', ...
        cfg.screenId, cfg.nRuns, cfg.nTrialsTotal, numel(vals));