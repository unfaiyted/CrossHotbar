-- Enmity list (as FFXIV's): the enemies in a fight with you or your party, in
-- a small, clean list: an aggro marker, the name, a thin health bar.
--
--   marker colour   red     you have aggro (it's on you)
--                   orange  you're about to lose it / about to pull it
--                   green   someone else in the party has it
-- Forever hands addons enemy threat and health as "secret" values: they can
-- go into the game's widgets and colour functions, not be compared or summed.
-- So the colour comes from the game's own threat colour of your threat
-- status (the secret passed straight through); if that's refused, from what
-- can be told plainly: on you (red), on a party member (green).
--
-- Who's listed: enemy nameplates, alive, whose target is you, your pet or a
-- party / raid member, or with you on their threat list. Nameplate order;
-- the current target's name lit gold. Needs enemy nameplates (turned on).
-- Locked: no background, no title. /xhb enmity  on / off;
-- /xhb enmity lock  locks / unlocks it (unlocked: drag it).
local ADDON, addon = ...

local MAX_ROWS = 8
local ROW_W = 200
local NAME_W = 80         -- (names cut to one width, so the icons line up)
local ICON = 11
local MAX_AURAS = 7
local CAST_H = 2
local ROW_H = 26          -- (name line + auras, thin trimmed bar, tiny cast bar)
local BAR_H = 4
local GOLD = { 1, 0.82, 0.25 }          -- (the default UI's gold trim)

local E = {}
addon.Enmity = E

local function Settings()
   local s = addon.ForeverSettings and addon:ForeverSettings()
   if not s then return nil end
   if s.enmity == nil then s.enmity = true end
   return s
end

local function Secret(v)
   return issecretvalue ~= nil and issecretvalue(v)
end

-- A plain true / false from something that may be secret (secret: false)
local function Plain(v)
   if Secret(v) then return false end
   return v and true or false
end

---------------------------------------------------------------------------
-- Who's in a fight with the party
---------------------------------------------------------------------------
local list = {}

local function OnParty(unit)
   if not UnitExists(unit) then return nil end
   if Plain(UnitIsUnit(unit, "player")) then return "me" end
   if Plain(UnitIsUnit(unit, "pet")) then return "party" end
   if Plain(UnitInParty(unit)) or Plain(UnitInRaid(unit)) then return "party" end
   return nil
end

local function Scan()
   wipe(list)
   for i = 1, 40 do
      local unit = "nameplate" .. i
      if UnitExists(unit) and Plain(UnitCanAttack("player", unit)) and not Plain(UnitIsDead(unit)) then
         local on = OnParty(unit .. "target")
         local status = UnitThreatSituation and UnitThreatSituation("player", unit)
         local onMyList = type(status) == "number"
         if on or onMyList then
            list[#list + 1] = { unit = unit, on = on, status = status }
         end
      end
   end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "CHBEnmityFrame", UIParent, "BackdropTemplate")
frame:SetSize(ROW_W, MAX_ROWS * (ROW_H + 3))
frame:SetPoint("RIGHT", UIParent, "RIGHT", -260, 80)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
if frame.SetBackdrop then frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" }) end
local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
title:SetText("Enmity  |cff999999(drag to move; /xhb enmity lock)|r")

-- Trim, as the default UI's (muted brass, not bright gold), drawn in 1px
-- layers outer to inner: a dark outline, then brass a touch lighter on the
-- top / left edges than on the bottom / right.
-- (sampled from the default UI's bar trim: near-black outline, a tan-bronze
-- edge, a dark brown body)
local BRASS_LIGHT, BRASS_DARK = { 0.54, 0.46, 0.32, 1 }, { 0.27, 0.21, 0.13, 1 }
local BEVEL = {
   { light = { 0.02, 0.016, 0.012, 1 }, dark = { 0.02, 0.016, 0.012, 1 } },
   { light = BRASS_LIGHT, dark = BRASS_DARK },
   { light = { 0.14, 0.11, 0.07, 1 }, dark = { 0.07, 0.05, 0.03, 1 } },
}

local function Edge(parent, layer, colour)
   local t = parent:CreateTexture(nil, "BORDER", nil, layer)
   t:SetColorTexture(colour[1], colour[2], colour[3], colour[4])
   return t
end

-- A bevelled trim round `box` (its edges drawn just inside it); the inset.
-- Rounded corners, the pixel way: the outline skips each corner pixel and
-- steps in one, diagonally (a pixel of it drawn over the next layer).
local function Bevel(box)
   for n, c in ipairs(BEVEL) do
      local i = n - 1
      local cut = (n == 1) and 1 or 0
      local top, left = Edge(box, n, c.light), Edge(box, n, c.light)
      local bottom, right = Edge(box, n, c.dark), Edge(box, n, c.dark)
      top:SetPoint("TOPLEFT", i + cut, -i); top:SetPoint("TOPRIGHT", -i - cut, -i); top:SetHeight(1)
      bottom:SetPoint("BOTTOMLEFT", i + cut, i); bottom:SetPoint("BOTTOMRIGHT", -i - cut, i); bottom:SetHeight(1)
      left:SetPoint("TOPLEFT", i, -i - cut); left:SetPoint("BOTTOMLEFT", i, i + cut); left:SetWidth(1)
      right:SetPoint("TOPRIGHT", -i, -i - cut); right:SetPoint("BOTTOMRIGHT", -i, i + cut); right:SetWidth(1)
   end
   local outline = BEVEL[1].light
   for _, corner in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 }, { "BOTTOMLEFT", 1, 1 }, { "BOTTOMRIGHT", -1, 1 } }) do
      local px = box:CreateTexture(nil, "BORDER", nil, 7)
      px:SetColorTexture(outline[1], outline[2], outline[3], outline[4])
      px:SetSize(1, 1)
      px:SetPoint(corner[1], corner[2], corner[3])
   end
   return #BEVEL
end

local rows = {}
for i = 1, MAX_ROWS do
   local r = CreateFrame("Frame", nil, frame)
   r:SetSize(ROW_W, ROW_H)
   r:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + 3))
   -- (the aggro marker: a coloured diamond in a brass setting, a dark ring between)
   r.markerGold = r:CreateTexture(nil, "ARTWORK", nil, 1)
   r.markerGold:SetSize(11, 11)
   r.markerGold:SetPoint("CENTER", r, "LEFT", 6, 0)
   r.markerGold:SetTexture("Interface\\Buttons\\WHITE8x8")
   r.markerGold:SetGradient("VERTICAL", CreateColor(BRASS_DARK[1], BRASS_DARK[2], BRASS_DARK[3], 1),
      CreateColor(BRASS_LIGHT[1], BRASS_LIGHT[2], BRASS_LIGHT[3], 1))
   r.markerGold:SetRotation(math.rad(45))
   r.markerRing = r:CreateTexture(nil, "ARTWORK", nil, 2)
   r.markerRing:SetSize(9, 9)
   r.markerRing:SetPoint("CENTER", r.markerGold)
   r.markerRing:SetTexture("Interface\\Buttons\\WHITE8x8")
   r.markerRing:SetVertexColor(0.03, 0.02, 0.0, 1)
   r.markerRing:SetRotation(math.rad(45))
   r.marker = r:CreateTexture(nil, "ARTWORK", nil, 3)
   r.marker:SetSize(7, 7)
   r.marker:SetPoint("CENTER", r.markerGold)
   r.marker:SetTexture("Interface\\Buttons\\WHITE8x8")
   r.marker:SetRotation(math.rad(45))
   -- (the name, above the bar)
   r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   r.name:SetPoint("TOPLEFT", 16, 0)
   r.name:SetWidth(NAME_W)
   r.name:SetJustifyH("LEFT")
   r.name:SetWordWrap(false)
   r.name:SetShadowOffset(1, -1)
   r.name:SetShadowColor(0, 0, 0, 1)
   -- (the thin health bar, in its trim)
   local box = CreateFrame("Frame", nil, r)
   box:SetPoint("BOTTOMLEFT", 15, CAST_H + 2)
   box:SetPoint("BOTTOMRIGHT", 0, CAST_H + 2)
   box:SetHeight(BAR_H + 6)
   local inset = Bevel(box)
   r.bar = CreateFrame("StatusBar", nil, box)
   r.bar:SetPoint("TOPLEFT", inset, -inset)
   r.bar:SetPoint("BOTTOMRIGHT", -inset, inset)
   r.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
   r.bar:SetStatusBarColor(0.75, 0.16, 0.12, 1)
   local bg = r.bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.137, 0.11, 0.075, 1)
   -- (auras, right of the name: tiny icons, each on a 1px coloured border)
   r.auras = {}
   for k = 1, MAX_AURAS do
      local a = CreateFrame("Frame", nil, r)
      a:SetSize(ICON, ICON)
      a:SetPoint("TOPLEFT", r.name, "TOPRIGHT", 3 + (k - 1) * (ICON + 2), 1)
      a.border = a:CreateTexture(nil, "BACKGROUND"); a.border:SetAllPoints()
      a.icon = a:CreateTexture(nil, "ARTWORK"); a.icon:SetPoint("TOPLEFT", 1, -1); a.icon:SetPoint("BOTTOMRIGHT", -1, 1)
      a.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      a.cd = CreateFrame("Cooldown", nil, a, "CooldownFrameTemplate")
      a.cd:SetAllPoints(a.icon)
      a.cd:SetDrawEdge(false)
      a.cd:SetHideCountdownNumbers(true)
      a.cd:SetReverse(true)
      a.count = a:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
      a.count:SetPoint("BOTTOMRIGHT", 3, -2)
      a.count:SetScale(0.7)
      a:Hide()
      r.auras[k] = a
   end
   -- (the tiny cast bar, under the health bar; a soft glow pulses round it
   -- while the cast can be interrupted)
   r.castGate = CreateFrame("Frame", nil, r)
   r.castGate:SetPoint("BOTTOMLEFT", 15, -1)
   r.castGate:SetPoint("BOTTOMRIGHT", 1, -1)
   r.castGate:SetHeight(CAST_H + 4)
   local glow = r.castGate:CreateTexture(nil, "BACKGROUND")
   glow:SetAllPoints()
   glow:SetColorTexture(1, 0.85, 0.3, 0.9)
   local pulse = glow:CreateAnimationGroup()
   pulse:SetLooping("BOUNCE")
   local fade = pulse:CreateAnimation("Alpha")
   fade:SetFromAlpha(0.15); fade:SetToAlpha(1); fade:SetDuration(0.35)
   pulse:Play()
   r.castGate:Hide()
   r.cast = CreateFrame("StatusBar", nil, r)
   r.cast:SetPoint("BOTTOMLEFT", 16, 0)
   r.cast:SetPoint("BOTTOMRIGHT", 0, 0)
   r.cast:SetHeight(CAST_H)
   r.cast:SetFrameLevel(r.castGate:GetFrameLevel() + 2)
   r.cast:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
   r.cast:SetStatusBarColor(1, 0.7, 0.1, 1)
   local cbg = r.cast:CreateTexture(nil, "BACKGROUND"); cbg:SetAllPoints(); cbg:SetColorTexture(0.05, 0.04, 0.02, 1)
   r.cast:Hide()
   rows[i] = r
end

local RED, ORANGE, GREEN = { 1, 0.2, 0.15 }, { 1, 0.6, 0.1 }, { 0.3, 0.85, 0.35 }

-- The marker's colour, from the game's threat status of you on that enemy
-- (the same source ForeverThreat reads): 3 you have it, solidly; 2 you're
-- tanking but someone's ahead (about to lose it); 1 you're ahead of the
-- tank (about to pull it); 0 low, someone else has it. Readable: our
-- colours. Secret (Forever hides it at times): the game's own threat colour,
-- the secret passed straight to the texture. Neither: what can be told
-- plainly, on you (red) or on the party (green).
local STATUS_COLOUR = { [3] = RED, [2] = ORANGE, [1] = ORANGE, [0] = GREEN }

local function Colour(r, e)
   local status = e.status
   if type(status) == "number" then
      if not Secret(status) then
         local c = STATUS_COLOUR[status] or GREEN
         r.marker:SetVertexColor(c[1], c[2], c[3], 1)
         return
      end
      if GetThreatStatusColor then
         local ok, cr, cg, cb = pcall(GetThreatStatusColor, status)
         if ok and type(cr) == "number" and pcall(r.marker.SetVertexColor, r.marker, cr, cg, cb, 1) then return end
      end
   end
   local c = (e.on == "me") and RED or (e.on == "party") and GREEN or ORANGE
   r.marker:SetVertexColor(c[1], c[2], c[3], 1)
end

---------------------------------------------------------------------------
-- Auras and casts (secret values go straight into textures / bars)
---------------------------------------------------------------------------
local BORDER_MINE, BORDER_DEBUFF, BORDER_BUFF = { 0.54, 0.46, 0.32 }, { 0.6, 0.12, 0.1 }, { 0.2, 0.55, 0.2 }

-- Enemy auras aren't available to addons on Forever: reading them in a fight
-- is refused ("Auras cannot be accessed when secret"), and the combat log
-- is forbidden. So your own warrior debuffs are followed from your casts
-- (UNIT_SPELLCAST_SUCCEEDED for you): the spell, on your target (or, for the
-- shouts and Thunder Clap, on every enemy in the list), for its known
-- duration, with the game's cooldown sweep. A dodge / parry still counts:
-- the client says the cast went off, not that it landed.
-- [spellID] = { seconds, aoe, stacks (most) }  (Classic ranks)
local DEBUFFS = {
   -- Rend
   [772] = { 9 }, [6546] = { 12 }, [6547] = { 15 }, [6548] = { 18 }, [11572] = { 21 }, [11573] = { 21 }, [11574] = { 21 },
   -- Hamstring
   [1715] = { 15 }, [7372] = { 15 }, [7373] = { 15 },
   -- Sunder Armor (stacks to 5)
   [7386] = { 30, false, 5 }, [7405] = { 30, false, 5 }, [8380] = { 30, false, 5 }, [11596] = { 30, false, 5 }, [11597] = { 30, false, 5 },
   -- Thunder Clap (around you)
   [6343] = { 10, true }, [8198] = { 14, true }, [8204] = { 18, true }, [8205] = { 22, true }, [11580] = { 26, true }, [11581] = { 30, true },
   -- Demoralizing Shout (around you)
   [1160] = { 30, true }, [6190] = { 30, true }, [11554] = { 30, true }, [11555] = { 30, true }, [11556] = { 30, true },
   -- Piercing Howl (around you)
   [12323] = { 6, true },
   -- Disarm, Mocking Blow, Concussion Blow
   [676] = { 10 },
   [694] = { 6 }, [7400] = { 6 }, [7402] = { 6 }, [20559] = { 6 }, [20560] = { 6 },
   [12809] = { 5 },
}

local mine = {}   -- [enemy GUID] = { [spellID] = { icon, start, duration, stacks } }

local function SpellIcon(spellID)
   if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spellID) end
   return GetSpellTexture and GetSpellTexture(spellID)
end

-- The value itself, or nil when it's secret (GUIDs to use as keys)
local function PlainValue(v)
   if issecretvalue and issecretvalue(v) then return nil end
   return v
end

local function Apply(guid, spellID, info, now)
   if not guid then return end
   local list = mine[guid] or {}
   mine[guid] = list
   local old = list[spellID]
   local stacks = 1
   if info[3] and old and now < old.start + old.duration then stacks = math.min(info[3], (old.stacks or 1) + 1) end
   list[spellID] = { icon = SpellIcon(spellID), start = now, duration = info[1], stacks = stacks }
end

local casts = CreateFrame("Frame")
casts:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
casts:SetScript("OnEvent", function(_, _, _, _, spellID)
   local info = spellID and not (issecretvalue and issecretvalue(spellID)) and DEBUFFS[spellID]
   if not info then return end
   local now = GetTime()
   if info[2] then
      for _, e in ipairs(list) do Apply(PlainValue(UnitGUID(e.unit)), spellID, info, now) end
   elseif UnitExists("target") and UnitCanAttack("player", "target") then
      Apply(PlainValue(UnitGUID("target")), spellID, info, now)
   end
end)

local function Auras(r, unit)
   local guid = PlainValue(UnitGUID(unit))
   local list = guid and mine[guid]
   local now = GetTime()
   local items = {}
   if list then
      for spellID, d in pairs(list) do
         if now < d.start + d.duration then items[#items + 1] = d else list[spellID] = nil end
      end
   end
   table.sort(items, function(x, y) return x.start < y.start end)
   for k = 1, MAX_AURAS do
      local a, d = r.auras[k], items[k]
      if d then
         a.icon:SetTexture(d.icon)
         a.border:SetColorTexture(BORDER_MINE[1], BORDER_MINE[2], BORDER_MINE[3], 1)
         a.cd:SetCooldown(d.start, d.duration)
         a.count:SetText((d.stacks and d.stacks > 1) and d.stacks or "")
         a:Show()
      else
         a:Hide()
      end
   end
end

-- The cast (or channel): its times into the bar (secret is fine); the glow
-- shown while it can be interrupted (a secret answer gates it too, through
-- SetAlphaFromBoolean)
local function Cast(r, unit)
   local name, _, _, startMS, endMS, _, _, notInterruptible = UnitCastingInfo(unit)
   if type(name) == "nil" and UnitChannelInfo then
      name, _, _, startMS, endMS, _, notInterruptible = UnitChannelInfo(unit)
   end
   if type(name) == "nil" or type(startMS) == "nil" then
      r.casting = nil
      r.cast:Hide(); r.castGate:Hide()
      return
   end
   r.casting = true
   r.cast:SetMinMaxValues(startMS, endMS)
   r.cast:SetValue(GetTime() * 1000)
   r.cast:Show()
   r.castGate:Show()
   if Secret(notInterruptible) and r.castGate.SetAlphaFromBoolean then
      r.castGate:SetAlphaFromBoolean(notInterruptible, 0, 1)
      r.cast:SetStatusBarColor(1, 0.7, 0.1, 1)
   else
      local shielded = notInterruptible and true or false
      r.castGate:SetAlpha(shielded and 0 or 1)
      if shielded then r.cast:SetStatusBarColor(0.6, 0.6, 0.6, 1) else r.cast:SetStatusBarColor(1, 0.7, 0.1, 1) end
   end
end

local function Draw()
   local s = Settings()
   local unlocked = s and not s.enmityLocked
   if not (s and s.enmity) or (#list == 0 and not unlocked) then frame:Hide() return end
   frame:Show()
   frame:EnableMouse(unlocked and true or false)
   if frame.SetBackdropColor then frame:SetBackdropColor(0, 0, 0, unlocked and 0.35 or 0) end
   title:SetShown(unlocked and true or false)
   for i, r in ipairs(rows) do
      local e = list[i]
      if e then
         r.name:SetText(UnitName(e.unit) or "?")
         local targeted = Plain(UnitIsUnit(e.unit, "target"))
         if targeted then r.name:SetTextColor(1, 0.85, 0.35) else r.name:SetTextColor(0.92, 0.92, 0.92) end
         -- (health may be secret: straight into the bar)
         r.bar:SetMinMaxValues(0, UnitHealthMax(e.unit) or 1)
         r.bar:SetValue(UnitHealth(e.unit) or 0)
         Colour(r, e)
         r.unit = e.unit
         Auras(r, e.unit)
         if not pcall(Cast, r, e.unit) then r.casting = nil; r.cast:Hide(); r.castGate:Hide() end
         r:Show()
      else
         r:Hide()
      end
   end
   frame:SetHeight(math.max(1, math.min(#list, MAX_ROWS)) * (ROW_H + 3))
end

frame:SetScript("OnDragStart", function(self)
   local s = Settings()
   if s and not s.enmityLocked then self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self)
   self:StopMovingOrSizing()
   local s = Settings()
   if s then
      local point, _, rel, x, y = self:GetPoint(1)
      s.enmityPos = { point, rel, x, y }
   end
end)

local tidy = CreateFrame("Frame")
tidy:RegisterEvent("PLAYER_REGEN_ENABLED")
tidy:SetScript("OnEvent", function()
   local now = GetTime()
   for guid, list in pairs(mine) do
      local any = false
      for spellID, d in pairs(list) do
         if now < d.start + d.duration then any = true else list[spellID] = nil end
      end
      if not any then mine[guid] = nil end
   end
end)

local ticker = CreateFrame("Frame")
local since = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
   for _, r in ipairs(rows) do
      if r.casting and r:IsShown() then r.cast:SetValue(GetTime() * 1000) end
   end
   since = since + elapsed
   if since < 0.2 then return end
   since = 0
   Scan()
   Draw()
end)

---------------------------------------------------------------------------
-- Setting up: enemy nameplates on; the list's place. (An earlier version put
-- D-pad left / right on targeting through the list: the restricted
-- environment can't do it well, so they go back to CrossHotbar's own.)
---------------------------------------------------------------------------
function E.Apply()
   local s = Settings()
   if not s then return end
   if s.enmityPos then
      frame:ClearAllPoints()
      frame:SetPoint(s.enmityPos[1], UIParent, s.enmityPos[2], s.enmityPos[3], s.enmityPos[4])
   end
   if InCombatLockdown() then return end
   if s.enmity and C_CVar and C_CVar.SetCVar and C_CVar.GetCVar("nameplateShowEnemies") ~= "1" then
      C_CVar.SetCVar("nameplateShowEnemies", "1")
   end
   if s.enmityDpad and _G.CrossHotbar_SetPadAction then
      local r = _G.CrossHotbar_GetPadAction("DPADR")
      if r == "CLICK CHBEnmityNext:LeftButton" then _G.CrossHotbar_SetPadAction("DPADR", "UNITNAVRIGHT") end
      local l = _G.CrossHotbar_GetPadAction("DPADL")
      if l == "CLICK CHBEnmityPrev:LeftButton" then _G.CrossHotbar_SetPadAction("DPADL", "UNITNAVLEFT") end
      s.enmityDpad = nil
      print("|cff66ccffCrossHotbar|r: D-pad left / right are CrossHotbar's again; the enmity list is display only.")
   end
end

local setup = CreateFrame("Frame")
setup:RegisterEvent("PLAYER_ENTERING_WORLD")
setup:SetScript("OnEvent", function() C_Timer.After(1.5, E.Apply) end)

function addon:EnmityCommand(value)
   local s = Settings()
   if not s then return end
   if value == "lock" then
      s.enmityLocked = not s.enmityLocked
      print("|cff66ccffCrossHotbar|r: enmity list " .. (s.enmityLocked and "locked." or "unlocked: drag it where you want it."))
   else
      s.enmity = not s.enmity
      print("|cff66ccffCrossHotbar|r: enmity list " .. (s.enmity and "on." or "off."))
   end
   Draw()
end
