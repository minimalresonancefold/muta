local M = {}
function M.top_header(title, page_text) screen.level(15); screen.move(2,9); screen.text(title or ""); screen.level(4); screen.move(126,9); screen.text_right(page_text or "") end
function M.divider(y) screen.level(2); screen.move(0,y); screen.line(128,y); screen.stroke() end
function M.footer(text) M.divider(55); screen.level(4); screen.move(64,62); screen.text_center(text or "") end
function M.led_bar(x,y,value,selected,cells) cells=cells or 12; value=math.max(0,math.min(1,tonumber(value) or 0)); local filled=math.floor(value*cells+0.5); for c=1,cells do screen.level(c<=filled and (selected and 15 or 8) or 2); screen.rect(x+(c-1)*6,y,4,4); screen.fill() end end
function M.percent(v) return math.floor((tonumber(v) or 0)*100+0.5).."%" end
return M
