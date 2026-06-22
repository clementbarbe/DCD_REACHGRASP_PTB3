function mp_drawFixation(w, cfg)
%MP_DRAWFIXATION  Draw a white fixation cross at screen center
%
%   mp_drawFixation(w, cfg)
%
%   Draws a '+' cross (40x40 px, 3 px line width). Does NOT flip —
%   the caller must call Screen('Flip', w) when ready.
%
%   INPUTS:
%     w   — PTB window handle
%     cfg — Config struct (needs .white, .xc, .yc)
%
%   See also motor_planning, mp_executeRun

    sz     = 20;
    coords = [-sz sz 0 0; 0 0 -sz sz];
    Screen('DrawLines', w, coords, 3, cfg.white, [cfg.xc cfg.yc], 2);