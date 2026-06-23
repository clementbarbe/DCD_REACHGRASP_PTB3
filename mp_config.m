function cfg = mp_config()
%MP_CONFIG  Configure the motor planning experiment
%
%   cfg = mp_config()
%
%   TRIGGER CODES — all have bit 1 (value 2) set:
%     trial_start =   2  (00000010)  bit1
%     cue_grasp   =   6  (00000110)  bit1 + bit2
%     cue_touch   =  10  (00001010)  bit1 + bit3
%     go_grasp    =  18  (00010010)  bit1 + bit4
%     go_touch    =  34  (00100010)  bit1 + bit5
%     iti_start   =  66  (01000010)  bit1 + bit6
%     run_start   = 130  (10000010)  bit1 + bit7
%     run_end     = 134  (10000110)  bit1 + bit2 + bit7
%
%   See also motor_planning, mp_initHardware, mp_buildDesign

    cfg = getDefaults();
    cfg = showDialog(cfg);
    cfg = finalizeConfig(cfg);


function cfg = getDefaults()

    cfg.participant      = 'P01';
    cfg.session          = '01';
    cfg.screenId         = 0;

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

    % ── Trigger codes — ALL have bit 1 (value 2) set ──
    %   This allows the EEG system to detect any event by monitoring
    %   bit 1 alone, while individual bits identify the event type.
    %
    %   Code  Binary     Bits set      Event
    %   ────  ─────────  ──────────    ─────────────
    %     2   00000010   1             trial_start
    %     6   00000110   1,2           cue_grasp
    %    10   00001010   1,3           cue_touch
    %    18   00010010   1,4           go_grasp
    %    34   00100010   1,5           go_touch
    %    66   01000010   1,6           iti_start
    %   130   10000010   1,7           run_start
    %   134   10000110   1,2,7         run_end
    cfg.codes.trial_start =   2;    % 00000010
    cfg.codes.cue_grasp   =   14;    % 00000110
    cfg.codes.cue_touch   =  10;    % 00001010
    cfg.codes.go_grasp    =  18;    % 00010010
    cfg.codes.go_touch    =  34;    % 00100010
    cfg.codes.iti_start   =  66;    % 01000010
    cfg.codes.run_start   = 3;    % 10000010
    cfg.codes.run_end     = 7;    % 10000110

    % ── Serial port for EEG triggers ──
    cfg.triggerActive    = true;
    cfg.serialPortName   = 'COM4';
    cfg.serialBaudRate   = 115200;
    cfg.trigPulseS       = 0.005;

    cfg.randomSeed       = round(mod(now * 1e6, 2^32));

    cfg.dataDir          = fullfile(fileparts(mfilename('fullpath')), ...
                                   'data', 'motor_planning');


function cfg = showDialog(cfg)

    screens = Screen('Screens');
    screenList = '';
    for si = 1:numel(screens)
        [sw, sh] = Screen('WindowSize', screens(si));
        screenList = [screenList, sprintf('  %d: %dx%d', screens(si), sw, sh)]; %#ok<AGROW>
        if si < numel(screens), screenList = [screenList, '  |']; end %#ok<AGROW>
    end

    try
        ports = serialportlist("available");
        if isempty(ports), portStr = '(none detected)';
        else,              portStr = strjoin(ports, ', ');
        end
    catch
        portStr = '(detection failed)';
    end

    prompt = { ...
        'Participant ID:', ...
        'Session:', ...
        sprintf('Screen index [available: %s ]:', screenList), ...
        'First effector (hand / tool):', ...
        'Triggers active (1/0):', ...
        sprintf('Serial port [available: %s ]:', portStr), ...
        'Serial baud rate:', ...
        'Audio HW delay (s):', ...
        'Random seed:', ...
        'Inter-run pause (s):'};
    defaults = { ...
        cfg.participant, ...
        cfg.session, ...
        num2str(cfg.screenId), ...
        cfg.effectorFirst, ...
        num2str(cfg.triggerActive), ...
        cfg.serialPortName, ...
        num2str(cfg.serialBaudRate), ...
        num2str(cfg.audioHwDelay), ...
        num2str(cfg.randomSeed), ...
        num2str(cfg.interRunPause)};

    answers = inputdlg(prompt, 'Motor Planning — Configuration', 1, defaults);
    if isempty(answers)
        error('motor_planning:cancelled', 'Configuration cancelled.');
    end

    cfg.participant    = strtrim(answers{1});
    cfg.session        = strtrim(answers{2});
    cfg.screenId       = str2double(answers{3});
    cfg.effectorFirst  = lower(strtrim(answers{4}));
    cfg.triggerActive  = str2double(answers{5}) == 1;
    cfg.serialPortName = upper(strtrim(answers{6}));
    cfg.serialBaudRate = str2double(answers{7});
    cfg.audioHwDelay   = str2double(answers{8});
    cfg.randomSeed     = round(str2double(answers{9}));
    cfg.interRunPause  = str2double(answers{10});


function cfg = finalizeConfig(cfg)

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

    % Validate: all trigger codes must have bit 1 (value 2) set
    flds = fieldnames(cfg.codes);
    vals = cellfun(@(f) cfg.codes.(f), flds);
    assert(numel(vals) == numel(unique(vals)), 'Duplicate trigger codes!');
    for i = 1:numel(vals)
        assert(bitand(vals(i), 2) == 2, ...
            'Trigger code %s = %d does not have bit 1 (value 2) set!', ...
            flds{i}, vals(i));
    end

    fprintf('[OK] Config validated: screen %d | %s @ %d baud | %d runs | %d trials/run\n', ...
        cfg.screenId, cfg.serialPortName, cfg.serialBaudRate, ...
        cfg.nRuns, cfg.nTrialsTotal);

    % Print trigger table
    fprintf('[OK] Trigger codes (all have bit 1 set):\n');
    for i = 1:numel(flds)
        fprintf('       %-13s = %3d  (%s)\n', flds{i}, vals(i), dec2bin(vals(i), 8));
    end