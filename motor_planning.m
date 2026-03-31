function motor_planning()
%MOTOR_PLANNING  Motor Planning EEG Task — Psychtoolbox-3 natif
%
%  Grasp / Touch × Hand / Tool — Multi-run séquentiel
%
%  ARCHITECTURE TEMPORELLE
%  ───────────────────────
%  1. Timeline pré-calculée AVANT chaque run (zéro calcul pendant acquisition)
%  2. PsychPortAudio('Start', pa, reps, WHEN, waitForStart=1)
%     → scheduling sub-ms, retourne l'onset réel hardware
%  3. Trigger port parallèle envoyé immédiatement après le retour
%     (couplage audio-trigger < 0.1 ms)
%  4. audioHwDelay compense la latence DAC→haut-parleur (à calibrer)
%
%  STRUCTURE D'UN ESSAI
%  ────────────────────
%  Preview 2 s (fixation + trig 30)
%  → Cue audio "Grasp"/"Touch" (trig 11/12)
%  → Plan 5.5 ± 0.5 s
%  → Go beep (trig 21/22)
%  → Execute 2 s
%  → ITI 8 s (trig 40)
%
%  TRIGGER CODES
%  ─────────────
%  100 run_start │ 200 run_end │ 30 trial_start
%   11 cue_grasp │  12 cue_touch
%   21 go_grasp  │  22 go_touch
%   40 iti_start
%
%  PRÉREQUIS
%  ─────────
%  - Psychtoolbox-3 ≥ 3.0.17
%  - io64.mex (Windows, pour le port parallèle)
%  - Fichiers sons dans ./sounds/ (fallback tons générés sinon)

% =====================================================================
%  CONFIGURATION
% =====================================================================

    cfg = getDefaultConfig();
    cfg = showConfigDialog(cfg);

    % Seed PRNG — logué pour reproductibilité
    rng(cfg.randomSeed, 'twister');
    fprintf('[INIT] Random seed : %d\n', cfg.randomSeed);
    fprintf('[INIT] Runs        : %s\n', strjoin(cfg.runSequence, ', '));

    % Répertoire de données
    if ~exist(cfg.dataDir, 'dir'), mkdir(cfg.dataDir); end

% =====================================================================
%  INITIALISATION PSYCHTOOLBOX
% =====================================================================

    PsychDefaultSetup(2);
    Screen('Preference', 'VisualDebugLevel', 3);
    KbName('UnifyKeyNames');
    cfg.keys.escape = KbName('ESCAPE');
    cfg.keys.q      = KbName('q');
    cfg.keys.space  = KbName('space');

    pa     = [];      % handle audio
    ioObj  = [];      % handle port parallèle
    allRec = {};      % données toutes runs

    try

    % --- Ecran --------------------------------------------------------
    screenId = max(Screen('Screens'));
    cfg.black = BlackIndex(screenId);
    cfg.white = WhiteIndex(screenId);

    % Detecter la resolution totale du X-Screen
    [totalW, totalH] = Screen('WindowSize', screenId);
    fprintf('[INFO] Resolution totale : %d x %d\n', totalW, totalH);

    % Calculer le rect selon le mode d'affichage
    switch cfg.displayMode
        case 'right'
            halfW = round(totalW / 2);
            screenRect = [halfW, 0, totalW, totalH];
            fprintf('[INFO] Mode RIGHT : [%d %d %d %d] (%d x %d)\n', ...
                screenRect, totalW - halfW, totalH);
        case 'left'
            halfW = round(totalW / 2);
            screenRect = [0, 0, halfW, totalH];
            fprintf('[INFO] Mode LEFT : [%d %d %d %d] (%d x %d)\n', ...
                screenRect, halfW, totalH);
        case 'full'
            screenRect = [];
            fprintf('[INFO] Mode FULL : %d x %d\n', totalW, totalH);
        otherwise
            error('displayMode inconnu : %s', cfg.displayMode);
    end

    PsychImaging('PrepareConfiguration');
    PsychImaging('AddTask', 'General', 'UseVirtualFramebuffer');

    if isempty(screenRect)
        [w, wRect] = PsychImaging('OpenWindow', screenId, cfg.black, [], [], [], [], 4);
    else
        [w, wRect] = PsychImaging('OpenWindow', screenId, cfg.black, screenRect, [], [], [], 4);
    end

    % Centre relatif a la fenetre ouverte
    [cfg.xc, cfg.yc] = RectCenter(wRect);
    cfg.ifi     = Screen('GetFlipInterval', w);
    cfg.halfIfi = cfg.ifi / 2;
    cfg.fps     = round(1 / cfg.ifi);

    Screen('TextSize', w, 32);
    Screen('TextFont', w, 'Arial');
    Screen('BlendFunction', w, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');
    HideCursor(screenId);

    winW = wRect(3) - wRect(1);
    winH = wRect(4) - wRect(2);
    fprintf('[OK] Fenetre : %d x %d @ %d Hz (%.2f ms/frame) [mode=%s]\n', ...
        winW, winH, cfg.fps, cfg.ifi * 1000, cfg.displayMode);

    % --- Audio (PsychPortAudio) ----------------------------------------
    InitializePsychSound(1);

    pa = PsychPortAudio('Open', [], 1, 4, cfg.audioFs, 2, [], []);
    s  = PsychPortAudio('GetStatus', pa);
    cfg.actualFs = s.SampleRate;
    fprintf('[OK] Audio : %d Hz, classe 4, latence prédite %.1f ms\n', ...
        s.SampleRate, s.PredictedLatency * 1000);

    % Warmup : jouer du silence pour amorcer le driver
    PsychPortAudio('FillBuffer', pa, zeros(2, round(cfg.audioFs * 0.01)));
    PsychPortAudio('Start', pa, 1, 0, 1);
    PsychPortAudio('Stop',  pa, 1);
    fprintf('[OK] Audio driver amorcé.\n');

    % --- Chargement des sons -------------------------------------------
    snd = loadSounds(cfg);

    % --- Port parallèle ------------------------------------------------
    if cfg.parportActive
        try
            ioObj = io64;
            st = io64(ioObj);
            if st ~= 0
                warning('io64 status = %d', st);
            end
            io64(ioObj, cfg.parportAddr, 0);           % reset
            fprintf('[OK] Port parallèle @ 0x%04X\n', cfg.parportAddr);
        catch ME
            warning('Port parallèle KO : %s → mode simulation.', ME.message);
            ioObj = []; cfg.parportActive = false;
        end
    else
        fprintf('[INFO] Port parallèle DÉSACTIVÉ.\n');
    end

    % --- Validation codes trigger uniques ------------------------------
    validateTriggerCodes(cfg);

    % --- Durée estimée -------------------------------------------------
    trialDur = cfg.previewDur + cfg.planDur + cfg.execDur + cfg.itiDur;
    runDur   = cfg.baselineInit + cfg.nTrialsTotal * trialDur + cfg.baselineFinal;
    fprintf('[INFO] ~%.1f min/run | ~%.0f min total (%d runs)\n', ...
        runDur/60, runDur*cfg.nRuns/60, cfg.nRuns);

% =====================================================================
%  BOUCLE SESSION
% =====================================================================

    showSessionInstructions(w, cfg);

    for ri = 1 : cfg.nRuns

        eff = cfg.runSequence{ri};
        fprintf('\n══════ RUN %d/%d — %s ══════\n', ri, cfg.nRuns, upper(eff));

        % 1. Ordre pseudo-aléatoire
        trialOrder = buildTrialOrder(cfg);

        % 2. Timeline pré-calculée
        T = buildTimeline(trialOrder, eff, ri, cfg);

        % 3. Sauvegarder timeline planifiée
        saveCSV(T, 'planned', ri, eff, cfg);

        % 4. Instructions run
        showRunInstructions(w, ri, eff, cfg);

        % 5. Priorité temps-réel
        Priority(MaxPriority(w));

        % 6. Démarrage (reset horloge)
        drawFixation(w, cfg);
        Screen('Flip', w);
        t0 = GetSecs;                                    % EPOCH DU RUN
        trigSend(ioObj, cfg, cfg.codes.run_start, t0);
        fprintf('[OK] Run %d démarré (t0 = %.6f)\n', ri, t0);

        % 7. Baseline initiale (fixation déjà affichée)
        spinWaitUntil(t0 + cfg.baselineInit);

        % 8. Exécution des essais
        T = executeTrials(w, pa, ioObj, t0, T, snd, cfg);

        % 9. Baseline finale
        drawFixation(w, cfg);
        Screen('Flip', w);
        spinWaitUntil(t0 + T(end).trialEnd + cfg.baselineFinal);
        trigSend(ioObj, cfg, cfg.codes.run_end, t0);

        % 10. Baisser priorité
        Priority(0);

        % 11. Résumé timing
        logTimingSummary(T, ri, eff);

        % 12. Sauvegarde
        saveCSV(T, 'actual', ri, eff, cfg);
        allRec{end+1} = T; %#ok<AGROW>

        fprintf('[OK] Run %d/%d (%s) terminé.\n', ri, cfg.nRuns, eff);

        % 13. Pause inter-run
        if ri < cfg.nRuns
            showInterRunPause(w, ri, cfg);
        end

    end % for ri

    % --- Fin de session -------------------------------------------------
    showSessionEnd(w, cfg);
    saveAllRuns(allRec, cfg);
    fprintf('\n[OK] Session complète : %d runs.\n', cfg.nRuns);

    % =====================================================================
    %  CLEANUP
    % =====================================================================

    catch ME
        Priority(0);
        fprintf('\n[ERREUR] %s\n', ME.message);

        % Sauvegarde d'urgence
        if ~isempty(allRec)
            try saveAllRuns(allRec, cfg); catch, end
        end

        % Afficher stack trace complet
        disp(getReport(ME, 'extended'));
    end

    % Nettoyage garanti (try/catch autour de chaque opération)
    Priority(0);
    ShowCursor;
    try PsychPortAudio('Close', pa); catch, end
    try Screen('CloseAll'); catch, end
    if cfg.parportActive && ~isempty(ioObj)
        try io64(ioObj, cfg.parportAddr, 0); catch, end
    end
    fprintf('[OK] Nettoyage terminé.\n');

end % motor_planning


% #####################################################################
%                       FONCTIONS LOCALES
% #####################################################################

% =====================================================================
%  CONFIGURATION
% =====================================================================

function cfg = getDefaultConfig()
    cfg.participant     = 'P01';
    cfg.session         = '01';

    % --- Affichage ---
    %  'right' = moniteur droit uniquement
    %  'left'  = moniteur gauche uniquement
    %  'full'  = les deux (plein ecran etendu)
    cfg.displayMode     = 'right';

    % --- Sequence de runs ---
    cfg.runSequence     = {'hand','tool','hand','tool','hand','tool','hand','tool'};
    cfg.nRuns           = numel(cfg.runSequence);

    % --- Design ---
    cfg.conditions          = {'grasp','touch'};
    cfg.nTrialsPerCond      = 20;
    cfg.nTrialsTotal        = numel(cfg.conditions) * cfg.nTrialsPerCond;
    cfg.maxConsec           = 3;

    % --- Timing (secondes) ---
    cfg.previewDur    = 2.0;
    cfg.planDur       = 5.5;
    cfg.planJitter    = 0.5;
    cfg.execDur       = 2.0;
    cfg.itiDur        = 8.0;
    cfg.baselineInit  = 10.0;
    cfg.baselineFinal = 10.0;

    % --- Audio ---
    cfg.audioFs       = 44100;
    cfg.audioHwDelay  = 0.000;
    cfg.fillAhead     = 0.200;
    cfg.goBeepFreq    = 1000;
    cfg.goBeepDur     = 0.500;
    cfg.goBeepVol     = 0.70;
    cfg.soundDir      = fullfile(fileparts(mfilename('fullpath')), 'sounds');

    % --- Trigger codes ---
    cfg.codes.run_start   = 100;
    cfg.codes.run_end     = 200;
    cfg.codes.trial_start =  30;
    cfg.codes.cue_grasp   =  11;
    cfg.codes.cue_touch   =  12;
    cfg.codes.go_grasp    =  21;
    cfg.codes.go_touch    =  22;
    cfg.codes.iti_start   =  40;

    % --- Port parallele ---
    cfg.parportActive = true;
    cfg.parportAddr   = hex2dec('D010');
    cfg.trigPulseS    = 0.005;

    % --- Reproductibilite ---
    cfg.randomSeed = round(mod(now * 1e6, 2^32));

    % --- Donnees ---
    cfg.dataDir = fullfile(fileparts(mfilename('fullpath')), ...
                           'data', 'motor_planning');
end

function cfg = showConfigDialog(cfg)
    prompt  = {'Participant ID :', ...
               'Session :', ...
               'Affichage (right / left / full) :', ...
               'Port parallele actif (1/0) :', ...
               'Adresse port (hex) :', ...
               'Delai audio HW (s) :', ...
               'Seed aleatoire :'};
    def     = {cfg.participant, ...
               cfg.session, ...
               cfg.displayMode, ...
               num2str(cfg.parportActive), ...
               dec2hex(cfg.parportAddr), ...
               num2str(cfg.audioHwDelay), ...
               num2str(cfg.randomSeed)};
    ans_    = inputdlg(prompt, 'Motor Planning -- Config', 1, def);
    if isempty(ans_), error('Configuration annulee.'); end

    cfg.participant   = ans_{1};
    cfg.session       = ans_{2};
    cfg.displayMode   = lower(strtrim(ans_{3}));
    cfg.parportActive = str2double(ans_{4}) == 1;
    cfg.parportAddr   = hex2dec(ans_{5});
    cfg.audioHwDelay  = str2double(ans_{6});
    cfg.randomSeed    = round(str2double(ans_{7}));

    % Validation du mode d'affichage
    validModes = {'right', 'left', 'full'};
    if ~ismember(cfg.displayMode, validModes)
        error('displayMode invalide : "%s". Valides : %s', ...
              cfg.displayMode, strjoin(validModes, ', '));
    end

    if cfg.parportActive && ~ispc
        warning('Port parallele Windows uniquement -> desactive.');
        cfg.parportActive = false;
    end
end

function validateTriggerCodes(cfg)
%VALIDATETRIGGERCODES  Verifie que tous les codes trigger sont uniques
    flds = fieldnames(cfg.codes);
    vals = zeros(1, numel(flds));
    for i = 1 : numel(flds)
        vals(i) = cfg.codes.(flds{i});
    end
    if numel(vals) ~= numel(unique(vals))
        dupes = vals(histc(vals, unique(vals)) > 1); %#ok<HISTC>
        error('Codes trigger dupliques detectes : %s', num2str(unique(dupes)));
    end
    fprintf('[OK] %d codes trigger uniques valides.\n', numel(vals));
end          

% =====================================================================
%  CHARGEMENT DES SONS
% =====================================================================

function snd = loadSounds(cfg)
%LOADSOUNDS  Charge ou génère tous les stimuli audio
%   snd.grasp, snd.touch, snd.go : matrices 2 × N (stereo, -1..+1)

    snd = struct();

    % Cue Grasp
    snd.grasp = tryLoadWav(fullfile(cfg.soundDir, 'grasp.wav'), ...
                           cfg.audioFs, 400, 0.5);

    % Cue Touch
    snd.touch = tryLoadWav(fullfile(cfg.soundDir, 'touch.wav'), ...
                           cfg.audioFs, 600, 0.5);

    % Go beep
    snd.go    = tryLoadWav(fullfile(cfg.soundDir, 'beep.wav'), ...
                           cfg.audioFs, cfg.goBeepFreq, cfg.goBeepDur);

    % Appliquer volume au go beep
    snd.go = snd.go * cfg.goBeepVol;

    % Log durées
    names = fieldnames(snd);
    for i = 1:numel(names)
        d = size(snd.(names{i}), 2) / cfg.audioFs;
        fprintf('[OK] Son %-6s : %.3f s\n', names{i}, d);
        if d > 2.0
            warning('Son "%s" dure %.2f s — risque de chevauchement.', names{i}, d);
        end
    end
end

function audioMat = tryLoadWav(filepath, targetFs, fallbackFreq, fallbackDur)
%TRYLOADWAV  Charge un WAV ou génère un ton de remplacement
%   Retourne une matrice 2 × N (stereo, normalisée)

    if exist(filepath, 'file')
        try
            [y, fs] = audioread(filepath);
            % Resample si nécessaire
            if fs ~= targetFs
                y = resample(y, targetFs, fs);
            end
            % Mono → stereo
            if size(y, 2) == 1
                y = [y, y];
            end
            % Normaliser peak à 0.95
            pk = max(abs(y(:)));
            if pk > 0, y = y / pk * 0.95; end
            audioMat = y';    % 2 × N
            fprintf('[OK] Chargé : %s\n', filepath);
            return;
        catch ME
            warning('Échec lecture %s : %s', filepath, ME.message);
        end
    else
        fprintf('[WARN] Introuvable : %s\n', filepath);
    end

    % Fallback : ton pur avec rampe cosinus
    audioMat = generateTone(fallbackFreq, fallbackDur, targetFs, 0.9);
    fprintf('[WARN] Fallback ton %.0f Hz pour %s\n', fallbackFreq, filepath);
end

function audioMat = generateTone(freq, dur, fs, vol)
%GENERATETONE  Ton sinusoïdal stéréo avec rampe anti-clic
%   audioMat : 2 × N

    nSamp = round(fs * dur);
    t     = (0 : nSamp-1) / fs;

    % Rampe cosinus 10 ms
    nRamp = round(fs * 0.010);
    ramp  = ones(1, nSamp);
    ramp(1:nRamp)         = 0.5 * (1 - cos(pi * (0:nRamp-1) / nRamp));
    ramp(end-nRamp+1:end) = 0.5 * (1 - cos(pi * (nRamp-1:-1:0) / nRamp));

    y = sin(2 * pi * freq * t) .* ramp * vol;
    audioMat = [y; y];   % stereo
end

% =====================================================================
%  PSEUDO-RANDOMISATION
% =====================================================================

function order = buildTrialOrder(cfg)
%BUILDTRIALORDER  Pseudo-aléatoire : jamais > maxConsec identiques consécutifs

    items  = cfg.conditions;
    reps   = cfg.nTrialsPerCond;
    maxC   = cfg.maxConsec;
    nTotal = numel(items) * reps;

    % Phase 1 : shuffle-and-check
    pool = repmat(items, 1, reps);
    for attempt = 1 : 10000
        order = pool(randperm(nTotal));
        if checkMaxConsec(order, maxC)
            return;
        end
    end

    % Phase 2 : construction incrémentale (garantie)
    remaining = containers.Map(items, repmat({reps}, 1, numel(items)));
    order = cell(1, nTotal);
    for i = 1 : nTotal
        avail = {};
        for ci = 1 : numel(items)
            it = items{ci};
            if remaining(it) <= 0, continue; end
            if i > maxC && all(strcmp(order(i-maxC:i-1), it))
                continue;
            end
            avail{end+1} = it; %#ok<AGROW>
        end
        if isempty(avail)
            avail = items(cellfun(@(x) remaining(x) > 0, items));
        end
        chosen = avail{randi(numel(avail))};
        order{i} = chosen;
        remaining(chosen) = remaining(chosen) - 1;
    end

    if ~checkMaxConsec(order, maxC)
        error('Pseudo-randomisation échouée (contrainte max consécutifs).');
    end
end

function ok = checkMaxConsec(seq, maxC)
    ok = true;
    run = 1;
    for i = 2 : numel(seq)
        if strcmp(seq{i}, seq{i-1})
            run = run + 1;
            if run > maxC, ok = false; return; end
        else
            run = 1;
        end
    end
end

% =====================================================================
%  CONSTRUCTION DE LA TIMELINE
% =====================================================================

function T = buildTimeline(trialOrder, effector, runIdx, cfg)
%BUILDTIMELINE  Pré-calcule tous les onsets pour un run
%   T : struct array (1 × nTrials)

    n = numel(trialOrder);
    T = repmat(getTrialTemplate(), 1, n);

    t = cfg.baselineInit;     % premier essai commence après baseline

    for i = 1 : n
        cond = trialOrder{i};
        jit  = (rand * 2 - 1) * cfg.planJitter;
        planD = max(2.0, cfg.planDur + jit);

        T(i).trialIndex    = i;
        T(i).condition     = cond;
        T(i).effector      = effector;
        T(i).runNumber     = runIdx;
        T(i).randomSeed    = cfg.randomSeed;
        T(i).jitter        = round(jit, 4);
        T(i).planDuration  = round(planD, 4);

        % Codes trigger
        if strcmp(cond, 'grasp')
            T(i).cueCode = cfg.codes.cue_grasp;
            T(i).goCode  = cfg.codes.go_grasp;
        else
            T(i).cueCode = cfg.codes.cue_touch;
            T(i).goCode  = cfg.codes.go_touch;
        end

        % Onsets planifiés (relatifs à t0)
        T(i).previewOnset = round(t, 6);
        T(i).cueOnset     = round(t + cfg.previewDur, 6);
        T(i).goOnset      = round(t + cfg.previewDur + planD, 6);
        T(i).executeOnset  = round(t + cfg.previewDur + planD, 6);
        T(i).itiOnset     = round(t + cfg.previewDur + planD + cfg.execDur, 6);
        T(i).trialEnd     = round(t + cfg.previewDur + planD + cfg.execDur + cfg.itiDur, 6);

        t = T(i).trialEnd;
    end

    fprintf('[OK] Timeline : %d essais | %.1f s (%.1f min)\n', ...
        n, T(end).trialEnd + cfg.baselineFinal, ...
        (T(end).trialEnd + cfg.baselineFinal) / 60);
end

function tr = getTrialTemplate()
    tr.trialIndex           = 0;
    tr.condition            = '';
    tr.effector             = '';
    tr.runNumber            = 0;
    tr.randomSeed           = 0;
    tr.jitter               = 0;
    tr.planDuration         = 0;
    tr.cueCode              = 0;
    tr.goCode               = 0;
    % Planned onsets
    tr.previewOnset         = 0;
    tr.cueOnset             = 0;
    tr.goOnset              = 0;
    tr.executeOnset         = 0;
    tr.itiOnset             = 0;
    tr.trialEnd             = 0;
    % Actual onsets (remplis à l'exécution)
    tr.actualPreviewVbl     = NaN;
    tr.actualCueDacOnset    = NaN;
    tr.actualCueTriggerT    = NaN;
    tr.actualGoDacOnset     = NaN;
    tr.actualGoTriggerT     = NaN;
    tr.actualItiTriggerT    = NaN;
    % Erreurs scheduling
    tr.cueSchedErrorMs      = NaN;
    tr.goSchedErrorMs       = NaN;
end

% =====================================================================
%  EXÉCUTION DES ESSAIS
% =====================================================================

function T = executeTrials(w, pa, ioObj, t0, T, snd, cfg)
%EXECUTETRIALS  Exécute séquentiellement chaque essai du run

    nTrials = numel(T);

    for ti = 1 : nTrials

        tr = T(ti);

        % ─── QUIT CHECK ────────────────────────────────────
        checkQuit(cfg);

        % ─── PREVIEW : fixation + trigger trial_start ──────
        drawFixation(w, cfg);
        vbl = Screen('Flip', w, t0 + tr.previewOnset - cfg.halfIfi);
        tr.actualPreviewVbl = vbl - t0;
        trigSend(ioObj, cfg, cfg.codes.trial_start, t0);

        % ─── CUE AUDIO ─────────────────────────────────────
        %
        %  1. Remplir le buffer 200 ms avant l'onset cible
        %  2. PsychPortAudio('Start', ..., when, 1) bloque
        %     jusqu'à l'onset hardware et retourne le temps exact
        %  3. Trigger envoyé immédiatement après (+ hw delay)
        %
        cueBuf = snd.(tr.condition);   % 'grasp' ou 'touch'
        targetCue = t0 + tr.cueOnset;

        spinWaitUntil(targetCue - cfg.fillAhead);
        PsychPortAudio('Stop', pa, 0);
        PsychPortAudio('FillBuffer', pa, cueBuf);

        checkQuit(cfg);

        % Vérifier qu'on n'est pas en retard
        nowT = GetSecs;
        if nowT > targetCue - 0.010
            warning('CUE LATE trial %d : %.1f ms', ti, (nowT - targetCue)*1000);
            actualCue = PsychPortAudio('Start', pa, 1, 0, 1);
        else
            actualCue = PsychPortAudio('Start', pa, 1, targetCue, 1);
        end

        % Compensation DAC → haut-parleur
        if cfg.audioHwDelay > 0
            spinWaitUntil(actualCue + cfg.audioHwDelay);
        end
        tr.actualCueTriggerT = trigSend(ioObj, cfg, tr.cueCode, t0);
        tr.actualCueDacOnset = actualCue - t0;
        tr.cueSchedErrorMs   = (actualCue - targetCue) * 1000;

        % ─── PLAN PERIOD (attente passive) ──────────────────
        checkQuit(cfg);

        % ─── GO BEEP ───────────────────────────────────────
        targetGo = t0 + tr.goOnset;

        spinWaitUntil(targetGo - cfg.fillAhead);
        PsychPortAudio('Stop', pa, 0);
        PsychPortAudio('FillBuffer', pa, snd.go);

        checkQuit(cfg);

        nowT = GetSecs;
        if nowT > targetGo - 0.010
            warning('GO LATE trial %d : %.1f ms', ti, (nowT - targetGo)*1000);
            actualGo = PsychPortAudio('Start', pa, 1, 0, 1);
        else
            actualGo = PsychPortAudio('Start', pa, 1, targetGo, 1);
        end

        if cfg.audioHwDelay > 0
            spinWaitUntil(actualGo + cfg.audioHwDelay);
        end
        tr.actualGoTriggerT = trigSend(ioObj, cfg, tr.goCode, t0);
        tr.actualGoDacOnset = actualGo - t0;
        tr.goSchedErrorMs   = (actualGo - targetGo) * 1000;

        % ─── ITI ───────────────────────────────────────────
        spinWaitUntil(t0 + tr.itiOnset);
        tr.actualItiTriggerT = trigSend(ioObj, cfg, cfg.codes.iti_start, t0);

        drawFixation(w, cfg);
        Screen('Flip', w);

        % ─── Sauvegarder & log ─────────────────────────────
        T(ti) = tr;

        fprintf('  Trial %2d/%d (%s) | cue %+.2f ms | go %+.2f ms\n', ...
            ti, nTrials, tr.condition, tr.cueSchedErrorMs, tr.goSchedErrorMs);

    end % for ti
end

% =====================================================================
%  TIMING UTILITAIRES
% =====================================================================

function spinWaitUntil(targetSecs)
%SPINWAITUNTIL  Attente haute précision (yield + busy-wait)
%   - Yield CPU jusqu'à 0.5 ms avant la cible
%   - Busy-wait pur pour les dernières 0.5 ms
    while (targetSecs - GetSecs) > 0.0005
        WaitSecs('YieldSecs', 0.00005);
    end
    while GetSecs < targetSecs
        % spin
    end
end

function relT = trigSend(ioObj, cfg, code, t0)
%TRIGSEND  Envoie un trigger port parallèle (pulse 5 ms)
%   Retourne le temps relatif à t0 du front montant.
%   Si le port est inactif, retourne le temps courant.
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

function checkQuit(cfg)
%CHECKQUIT  Vérifie Escape / Q — lève une erreur pour déclencher le cleanup
    [kd, ~, kc] = KbCheck(-1);
    if kd && (kc(cfg.keys.escape) || kc(cfg.keys.q))
        error('motor_planning:userQuit', ...
              'Arrêt demandé par l''utilisateur (Escape/Q).');
    end
end

% =====================================================================
%  AFFICHAGE
% =====================================================================

function drawFixation(w, cfg)
    sz = 20;
    coords = [-sz sz 0 0 ; 0 0 -sz sz];
    Screen('DrawLines', w, coords, 3, cfg.white, [cfg.xc cfg.yc], 2);
end

function showText(w, cfg, txt)
    DrawFormattedText(w, txt, 'center', 'center', cfg.white, 60);
    Screen('Flip', w);
    WaitSecs(0.5);
    KbReleaseWait(-1);
    while true
        [kd, ~, kc] = KbCheck(-1);
        if kd
            if kc(cfg.keys.escape) || kc(cfg.keys.q)
                error('motor_planning:userQuit', 'Quit.');
            end
            if kc(cfg.keys.space), break; end
        end
        WaitSecs('YieldSecs', 0.005);
    end
    KbReleaseWait(-1);
end

% =====================================================================
%  ECRANS INSTRUCTIONS / PAUSES 
% =====================================================================

function showSessionInstructions(w, cfg)
    txt = sprintf([ ...
        '===================================\n' ...
        '      PLANIFICATION MOTRICE\n' ...
        '===================================\n\n' ...
        'Participant : %s\n' ...
        'Session     : %s\n' ...
        'Runs        : %d\n' ...
        'Audio PTB   : OUI (sub-ms)\n\n' ...
        'A chaque essai :\n' ...
        '  1. Fixez la croix\n' ...
        '  2. Ecoutez l''instruction (Grasp / Touch)\n' ...
        '  3. Attendez le BIP pour executer\n' ...
        '  4. Revenez en position de depart\n\n' ...
        '  >> ESPACE pour continuer'], ...
        cfg.participant, cfg.session, cfg.nRuns);
    showText(w, cfg, txt);
end

function showRunInstructions(w, ri, eff, cfg)
    if strcmp(eff, 'hand'), lab = 'la MAIN';
    else,                   lab = 'l''OUTIL'; end
    txt = sprintf([ ...
        '---- Run %d / %d ----\n\n' ...
        'Effecteur : %s\n' ...
        '%d essais (%d grasp + %d touch)\n\n' ...
        'Preparez-vous.\n\n' ...
        '  >> ESPACE quand pret'], ...
        ri, cfg.nRuns, lab, ...
        cfg.nTrialsTotal, cfg.nTrialsPerCond, cfg.nTrialsPerCond);
    showText(w, cfg, txt);
end

function showInterRunPause(w, ri, cfg)
    nextEff = cfg.runSequence{ri + 1};
    if strcmp(nextEff, 'hand'), lab = 'la MAIN';
    else,                      lab = 'l''OUTIL'; end
    txt = sprintf([ ...
        '=== Run %d/%d termine ===\n\n' ...
        'Prochain : run %d / %d\n' ...
        'Effecteur : %s\n\n' ...
        'Prenez une pause.\n\n' ...
        '  >> ESPACE quand pret'], ...
        ri, cfg.nRuns, ri+1, cfg.nRuns, lab);
    showText(w, cfg, txt);
end

function showSessionEnd(w, cfg)
    txt = sprintf([ ...
        '===================================\n' ...
        '      SESSION TERMINEE\n' ...
        '===================================\n\n' ...
        'Les %d runs sont completes.\n\n' ...
        'Merci pour votre participation !'], ...
        cfg.nRuns);
    DrawFormattedText(w, txt, 'center', 'center', cfg.white, 60);
    Screen('Flip', w);
    WaitSecs(5.0);
end

% =====================================================================
%  LOG TIMING
% =====================================================================

function logTimingSummary(T, ri, eff)
%LOGTIMINGSUMMARY  Résumé statistique du jitter audio pour un run

    cueErr = abs([T.cueSchedErrorMs]);
    goErr  = abs([T.goSchedErrorMs]);
    allErr = [cueErr, goErr];

    cueErr(isnan(cueErr)) = [];
    goErr(isnan(goErr))   = [];
    allErr(isnan(allErr)) = [];

    if isempty(allErr), return; end

    n = numel(allErr);
    s = sort(allErr);

    fprintf('\n── Timing Run %d (%s) ── %d events audio\n', ri, eff, n);
    fprintf('  Mean   : %.3f ms\n', mean(allErr));
    fprintf('  Median : %.3f ms\n', s(ceil(n/2)));
    fprintf('  p95    : %.3f ms\n', s(min(n, ceil(n*0.95))));
    fprintf('  Max    : %.3f ms\n', max(allErr));
    fprintf('  >1 ms  : %d   |   >2 ms : %d\n', ...
        sum(allErr > 1), sum(allErr > 2));

    if ~isempty(cueErr)
        fprintf('  Cue  — mean %.3f ms | max %.3f ms\n', mean(cueErr), max(cueErr));
    end
    if ~isempty(goErr)
        fprintf('  Go   — mean %.3f ms | max %.3f ms\n', mean(goErr), max(goErr));
    end
    fprintf('\n');
end

% =====================================================================
%  SAUVEGARDE CSV
% =====================================================================

function saveCSV(T, tag, ri, eff, cfg)
%SAVECSV  Sauvegarde un struct array en CSV
    ts    = datestr(now, 'yyyymmdd_HHMMSS');
    fname = sprintf('%s_MotorPlanning_%s_run%02d_%s_%s.csv', ...
                    cfg.participant, eff, ri, ts, tag);
    fpath = fullfile(cfg.dataDir, fname);

    try
        tbl = struct2table(T);
        writetable(tbl, fpath);
        fprintf('[OK] Sauvegardé : %s\n', fpath);
    catch ME
        warning('Sauvegarde CSV échouée : %s', ME.message);
        % Fallback : sauvegarde .mat
        matpath = [fpath '.mat'];
        save(matpath, 'T', 'cfg');
        fprintf('[WARN] Fallback .mat : %s\n', matpath);
    end
end

function saveAllRuns(allRec, cfg)
%SAVEALLRUNS  Concatène et sauvegarde toutes les runs
    if isempty(allRec), return; end
    allT = [allRec{:}];
    ts   = datestr(now, 'yyyymmdd_HHMMSS');
    fname = sprintf('%s_MotorPlanning_allruns_%s.csv', cfg.participant, ts);
    fpath = fullfile(cfg.dataDir, fname);
    try
        writetable(struct2table(allT), fpath);
        fprintf('[OK] Toutes runs : %s\n', fpath);
    catch ME
        warning('Sauvegarde all-runs échouée : %s', ME.message);
        save([fpath '.mat'], 'allT', 'cfg');
    end

    % Sauvegarde .mat complète pour reproductibilité
    matpath = fullfile(cfg.dataDir, ...
        sprintf('%s_MotorPlanning_allruns_%s.mat', cfg.participant, ts));
    save(matpath, 'allT', 'cfg');
    fprintf('[OK] Backup .mat : %s\n', matpath);
end

% =====================================================================
%  UTILITAIRE STRUCT
% =====================================================================

function a = struct2array(s)
%STRUCT2ARRAY  Extrait toutes les valeurs numériques d'un struct plat
    flds = fieldnames(s);
    a = zeros(1, numel(flds));
    for i = 1:numel(flds)
        a(i) = s.(flds{i});
    end
end