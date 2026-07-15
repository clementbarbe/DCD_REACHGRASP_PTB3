function mp_saveData(events, ri, eff, cfg)
%MP_SAVEDATA  Save event log for one run as CSV
%
%   events = struct array with fields:
%     run, trial, event, code, time_s, condition, effector, error_ms
%
%   Filename: {participant}_{session}_run{ri}_{eff}_{timestamp}.csv

    if ~exist(cfg.dataDir, 'dir'), mkdir(cfg.dataDir); end

    ts    = datestr(now, 'yyyymmdd_HHMMSS');
    fname = sprintf('%s_%s_run%02d_%s_%s.csv', ...
                    cfg.participant, cfg.session, ri, eff, ts);
    fpath = fullfile(cfg.dataDir, fname);

    try
        writetable(struct2table(events), fpath);
        fprintf('[OK] Saved: %s (%d events)\n', fname, numel(events));
    catch ME
        warning('CSV failed: %s', ME.message);
        save(strrep(fpath, '.csv', '.mat'), 'events', 'cfg');
    end