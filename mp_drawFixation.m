function mp_drawFixation(w, cfg)
%MP_DRAWFIXATION  White fixation cross at center. Does NOT flip.
%   No smoothing (smooth=0) to avoid BlendFunction requirement.

    sz     = 30;
    coords = [-sz sz 0 0; 0 0 -sz sz];
    Screen('DrawLines', w, coords, 4, cfg.white, [cfg.xc cfg.yc], 0);