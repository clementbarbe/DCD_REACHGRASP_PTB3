function mp_drawFixation(w, cfg)
%MP_DRAWFIXATION  Draw a white fixation cross at screen center
%
%   mp_drawFixation(w, cfg)
%
%   Draws a '+' cross (40×40 px, 3 px line width) in white at the center
%   of the PTB window. Does NOT call Screen('Flip') — the caller must
%   flip when ready.
%
%   INPUTS:
%     w   — PTB window handle
%     cfg — Config struct (must contain .white, .xc, .yc)
%
%   See also motor_planning, mp_executeRun

    sz     = 20;  % half-length in pixels
    coords = [-sz sz 0 0; 0 0 -sz sz];
    Screen('DrawLines', w, coords, 3, cfg.white, [cfg.xc cfg.yc], 2);
end