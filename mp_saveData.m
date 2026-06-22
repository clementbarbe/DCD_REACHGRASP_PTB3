function mp_saveData(T, tag, ri, eff, cfg)
%MP_SAVEDATA  Save trial data for one run to CSV (with MAT fallback)
%
%   mp_saveData(T, tag, ri, eff, cfg)
%
%   OUTPUT FILENAME:
%     {participant}_{session}_MotorPlanning_{eff}_run{ri}_{timestamp}_{tag}.csv
%
%   INPUTS:
%     T    — Struct array (1 x nTrials)
%     tag  — 'planned' (before run) or 'actual' (after run)
%     ri   — Run index (1-based)
%     eff  — Effector name ('hand' or 'tool')
%     cfg  — Config struct (needs .participant, .session, .dataDir)
%
%   See also motor_planning, mp_buildDesign, mp_executeRun

if ~exist(cfg.dataDir, 'dir'), mkdir(cfg.dataDir); end

ts    = datestr(now, 'yyyymmdd_HHMMSS');
fname = sprintf('%s_%s_MotorPlanning_%s_run%02d_%s_%s.csv', ...
    cfg.participant, cfg.session, eff, ri, ts, tag);
fpath = fullfile(cfg.dataDir, fname);

try
    writetable(struct2table(T), fpath);
    fprintf('[OK] Saved: %s\n', fname);
catch ME
    warning('CSV save failed: %s', ME.message);
    matpath = strrep(fpath, '.csv', '.mat');
    save(matpath, 'T', 'cfg');
    fprintf('[WARN] MAT fallback: %s\n', matpath);
end