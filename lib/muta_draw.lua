-- MUTA draw runtime helper module
-- V10.1 PHASE 7 DRAW
local M = {}
function M.page_header(title,right_text) screen.level(15); screen.move(2,9); screen.text(title or ""); screen.level(4); screen.move(126,9); screen.text_right(right_text or ""); screen.level(2); screen.move(0,13); screen.line(128,13); screen.stroke() end
function M.step_header(track,step,title,page_text) screen.level(15); screen.move(2,9); screen.text("T"..tostring(track).." > STEP "..tostring(step).." > "..tostring(title or "")); screen.level(4); screen.move(126,9); screen.text_right(page_text or ""); screen.level(2); screen.move(0,13); screen.line(128,13); screen.stroke() end
function M.footer(text) screen.level(2); screen.move(0,55); screen.line(128,55); screen.stroke(); screen.level(4); screen.move(64,62); screen.text_center(text or "") end
return M
