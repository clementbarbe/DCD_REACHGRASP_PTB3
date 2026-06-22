function cfg = mp_config()
%MP_CONFIG  Configure the motor planning experiment
%
%   cfg = mp_config()
%
%   Displays a GUI dialog for experiment parameters and returns a
%   complete configuration struct. All timing, trigger, audio, and
%   design parameters are set here.
%
%   DESIGN (per run):
%     2 conditions (grasp, touch) × 10 repetitions = 20 trials
%     Pseudo-random order (max 3 consecutive same condition)
%
%   SESSION:
%     4 runs with effector 1 → manual pause → 4 runs with effector 2
%
%   The returned struct contains all fields needed by the other mp_*
%   functions. No other configuration is needed.
%
%   See also motor_planning, mp_initHardware, mp_buildDesign

    cfg = getDefaults();
    cfg = showDialog(cfg);
    cfg = finalizeConfig(cfg);
end


function cfg = getDefaults()
%GETDEFAULTS  All default parameters in one place

    % ── Identity ──
    cfg.participant      = 'P01';
    cfg.session          = '01';

    % ── Display ──
    %   'right' = right half of extended desktop
    %   'left'  = left half
    %   'full'  = entire screen
    cfg.displayMode      = 'right';

    % ── Experimental design ──
    cfg.conditions       = {'grasp', 'touch'};
    cfg.nTrialsPerCond   = 10;       % per condition per run
    cfg.nTrialsTotal     = 20;       % 2 × 10 (recomputed in finalizeConfig)
    cfg.maxConsec        = 3;        % max consecutive same condition

    % ── Run structure ──
    cfg.effectorFirst    = 'hand';   % 'hand' or 'tool'
    cfg.nRunsPerEffector = 4;
    cfg.nRuns            = 8;

    % ── Timing (seconds) ──
    cfg.previewDur       = 2.0;      % fixation before cue
    cfg.planDur          = 5.5;      % mean planning period
    cfg.planJitter       = 0.5;      % ± uniform jitter on plan duration
    cfg.execDur          = 2.0;      % execution window after go beep
    cfg.itiDur           = 8.0;      % inter-trial interval
    cfg.baselineInit     = 10.0;     % fixation before first trial
    cfg.baselineFinal    = 10.0;     % fixation after last trial
    cfg.interRunPause    = 20.0;     % minimum pause between same-effector runs

    % ── Audio ──
    cfg.audioFs          = 44100;    % target sample rate (Hz)
    cfg.audioHwDelay     = 0.000;    % DAC-to-speaker latency (s) — calibrate!
    cfg.fillAhead        = 0.200;    % fill audio buffer this far before onset (s)
    cfg.goBeepFreq       = 1000;     % go beep frequency (Hz)
    cfg.goBeepDur        = 0.500;    % go beep duration (s)
    cfg.goBeepVol        = 0.70;     % go beep volume (0–1)
    cfg.soundDir         = fullfile(fileparts(mfilename('fullpath')), 'sounds');

    % ── Trigger codes (must be unique, 1–255 for parallel port) ──
    cfg.codes.run_start  = 100;
    cfg.codes.run_end    = 200;
    cfg.codes.trial_start=  30;
    cfg.codes.cue_grasp  =  11;
    cfg.codes.cue_touch  =  12;
    cfg.codes.go_grasp   =  21;
    cfg.codes.go_touch   =  22;
    cfg.codes.iti_start  =  40;

    % ── Parallel port ──
    cfg.parportActive    = true;
    cfg.parportAddr      = hex2dec('D010');
    cfg.trigPulseS       = 0.005;    % 5 ms pulse width

    % ── Reproducibility ──
    cfg.randomSeed       = round(mod(now * 1e6, 2^32));

    % ── Output directory ──
    cfg.dataDir          = fullfile(fileparts(mfilename('fullpath')), ...
                                   'data', 'motor_planning');
end


function cfg = showDialog(cfg)
%SHOWDIALOG  GUI dialog for user-configurable parameters
    prompt = { ...
        'Participant ID:', ...
        'Session:', ...
        'Display mode (right / left / full):', ...
        'First effector (hand / tool):', ...
        'Parallel port active (1/0):', ...
        'Port address (hex):', ...
        'Audio HW delay (s):', ...
        'Random seed:', ...
        'Inter-run pause (s):'};
    defaults = { ...
        cfg.participant, ...
        cfg.session, ...
        cfg.displayMode, ...
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
    cfg.displayMode   = lower(strtrim(answers{3}));
    cfg.effectorFirst = lower(strtrim(answers{4}));
    cfg.parportActive = str2double(answers{5}) == 1;
    cfg.parportAddr   = hex2dec(strtrim(answers{6}));
    cfg.audioHwDelay  = str2double(answers{7});
    cfg.randomSeed    = round(str2double(answers{8}));
    cfg.interRunPause = str2double(answers{9});
end


function cfg = finalizeConfig(cfg)
%FINALIZECONFIG  Validate parameters and build derived fields

    % Display mode
    assert(ismember(cfg.displayMode, {'right','left','full'}), ...
        'Invalid displayMode: "%s". Use right/left/full.', cfg.displayMode);

    % Effector
    assert(ismember(cfg.effectorFirst, {'hand','tool'}), ...
        'Invalid effectorFirst: "%s". Use hand/tool.', cfg.effectorFirst);

    % Build run sequence: 4 of first effector, then 4 of second
    if strcmp(cfg.effectorFirst, 'hand')
        second = 'tool';
    else
        second = 'hand';
    end
    cfg.runSequence = [ ...
        repmat({cfg.effectorFirst}, 1, cfg.nRunsPerEffector), ...
        repmat({second},            1, cfg.nRunsPerEffector)];
    cfg.nRuns = numel(cfg.runSequence);

    % Recompute trial count
    cfg.nTrialsTotal = numel(cfg.conditions) * cfg.nTrialsPerCond;

    % Parallel port: Windows only
    if cfg.parportActive && ~ispc
        warning('Parallel port requires Windows — disabled.');
        cfg.parportActive = false;
    end

    % Trigger code uniqueness
    flds = fieldnames(cfg.codes);
    vals = cellfun(@(f) cfg.codes.(f), flds);
    assert(numel(vals) == numel(unique(vals)), ...
        'Duplicate trigger codes detected!');

    fprintf('[OK] Config validated: %d runs, %d trials/run, %d unique triggers.\n', ...
        cfg.nRuns, cfg.nTrialsTotal, numel(vals));
end