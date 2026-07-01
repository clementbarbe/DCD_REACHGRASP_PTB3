function mp_drawFixation(w, cfg)
%MP_DRAWFIXATION  Draw a white fixation cross at screen center
%   Bigger cross (60x60 px, 4 px width) for better visibility.
%   Does NOT flip.

    sz     = 30;
    coords = [-sz sz 0 0; 0 0 -sz sz];
    Screen('DrawLines', w, coords, 4, [1 1 1], [cfg.xc cfg.yc], 2);