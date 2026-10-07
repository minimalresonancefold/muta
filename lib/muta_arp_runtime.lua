-- MUTA ARP runtime helper module
-- V10.1 PHASE 8 ARP
local M = {}
local function clamp(x,lo,hi) x=tonumber(x) or 0; if x<lo then return lo end; if x>hi then return hi end; return x end
function M.mode_name(mode) local names={"UP","DOWN","UP/DN","RND","WALK","DNA"}; return names[clamp(math.floor((tonumber(mode) or 1)+0.5),1,#names)] or "UP" end
function M.ensure(arp,max_rate)
  if type(arp)~="table" then arp={} end; arp.enabled=arp.enabled==true; arp.mode=clamp(math.floor((tonumber(arp.mode) or 1)+0.5),1,6); arp.octaves=clamp(math.floor((tonumber(arp.octaves) or 1)+0.5),1,4); arp.rate=clamp(math.floor((tonumber(arp.rate) or 1)+0.5),1,max_rate or 4); arp.gate=clamp(tonumber(arp.gate) or 0.78,0.05,1); arp.index=math.max(1,math.floor((tonumber(arp.index) or 1)+0.5))
  local old=tonumber(arp.muta) or 0; local folded=math.max(old,tonumber(arp.energy) or 0,tonumber(arp.gravity) or 0,tonumber(arp.phrase) or 0); arp.muta=clamp(folded,0,1); arp.mem=clamp(tonumber(arp.mem) or tonumber(arp.memory) or tonumber(arp.dna) or 0.45,0,1); arp.chaos=clamp(tonumber(arp.chaos) or tonumber(arp.mix) or 0.12,0,1)
  arp.muta_pos=math.max(1,math.floor((tonumber(arp.muta_pos) or 1)+0.5)); arp.muta_dir=(tonumber(arp.muta_dir) or 1)>=0 and 1 or -1; arp.motif_pos=math.max(1,math.floor((tonumber(arp.motif_pos) or 1)+0.5)); arp.motif_id=clamp(math.floor((tonumber(arp.motif_id) or 1)+0.5),1,5); arp.last_role=clamp(math.floor((tonumber(arp.last_role) or 1)+0.5),1,7); arp.micro=clamp(tonumber(arp.micro) or 0,-0.35,0.35)
  arp.walk=nil; arp.dna=nil; arp.mix=nil; arp.energy=nil; arp.memory=nil; arp.gravity=nil; arp.phrase=nil; return arp
end
function M.weighted_choice(items) local total=0; for _,it in ipairs(items) do total=total+math.max(0,it[2] or 0) end; if total<=0 then return items[1][1] end; local r=math.random()*total; local acc=0; for _,it in ipairs(items) do acc=acc+math.max(0,it[2] or 0); if r<=acc then return it[1] end end; return items[#items][1] end
function M.micro_offset_for_role(role,arp) local chaos=arp.chaos or 0; if chaos<=0.15 then return 0 end; local cents={0,4,-14,7,2,-6,14}; local amt=((cents[role] or 0)/100)*chaos; if math.random()<chaos*0.25 then amt=amt+(math.random(-8,8)/100)*chaos end; return clamp(amt,-0.30,0.30) end
return M
