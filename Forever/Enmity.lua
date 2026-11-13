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
local ROW_W = 170
local ROW_H = 24          -- (bevel, name strip, gold line, bar, bevel)
local BAR_H = 4          -- (inside the bevel: ROW_H - 8 - NAME_H - 1)
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

-- The default UI's metal trim, drawn in layers (outer to inner), each 1px:
-- a dark outline; a gold bevel lit top / left and shaded bottom / right;
-- a deeper gold; an inner shadow. (As the target frame's border.)
local BEVEL = {
   { light = { 0.16, 0.10, 0.02, 1 },    dark = { 0.08, 0.05, 0.01, 1 } },
   { light = { 1.00, 0.90, 0.50, 1 },    dark = { 0.62, 0.43, 0.10, 1 } },
   { light = { 0.85, 0.64, 0.20, 1 },    dark = { 0.45, 0.30, 0.06, 1 } },
   { light = { 0.05, 0.03, 0.00, 0.85 }, dark = { 0.05, 0.03, 0.00, 0.85 } },
}

local function Edge(parent, layer, colour)
   local t = parent:CreateTexture(nil, "BORDER", nil, layer)
   t:SetColorTexture(colour[1], colour[2], colour[3], colour[4])
   return t
end

-- A bevelled frame round `box` (its edges drawn just inside it)
local function Bevel(box)
   for n, c in ipairs(BEVEL) do
      local i = n - 1
      local top, left = Edge(box, n, c.light), Edge(box, n, c.light)
      local bottom, right = Edge(box, n, c.dark), Edge(box, n, c.dark)
      top:SetPoint("TOPLEFT", i, -i); top:SetPoint("TOPRIGHT", -i, -i); top:SetHeight(1)
      bottom:SetPoint("BOTTOMLEFT", i, i); bottom:SetPoint("BOTTOMRIGHT", -i, i); bottom:SetHeight(1)
      left:SetPoint("TOPLEFT", i, -i); left:SetPoint("BOTTOMLEFT", i, i); left:SetWidth(1)
      right:SetPoint("TOPRIGHT", -i, -i); right:SetPoint("BOTTOMRIGHT", -i, i); right:SetWidth(1)
   end
   return #BEVEL
end

local NAME_H = 12
local rows = {}
for i = 1, MAX_ROWS do
   local r = CreateFrame("Frame", nil, frame)
   r:SetSize(ROW_W, ROW_H)
   r:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + 3))
   -- (the aggro marker: a coloured diamond set in a gold one, a dark ring between)
   r.markerGold = r:CreateTexture(nil, "ARTWORK", nil, 1)
   r.markerGold:SetSize(12, 12)
   r.markerGold:SetPoint("CENTER", r, "LEFT", 6, 0)
   r.markerGold:SetTexture("Interface\\Buttons\\WHITE8x8")
   r.markerGold:SetGradient("VERTICAL", CreateColor(0.62, 0.43, 0.10, 1), CreateColor(1.0, 0.90, 0.50, 1))
   r.markerGold:SetRotation(math.rad(45))
   r.markerRing = r:CreateTexture(nil, "ARTWORK", nil, 2)
   r.markerRing:SetSize(9, 9)
   r.markerRing:SetPoint("CENTER", r.markerGold)
   r.markerRing:SetTexture("Interface\\Buttons\\WHITE8x8")
   r.markerRing:SetVertexColor(0.08, 0.05, 0.01, 1)
   r.markerRing:SetRotation(math.rad(45))
   r.marker = r:CreateTexture(nil, "ARTWORK", nil, 3)
   r.marker:SetSize(7, 7)
   r.marker:SetPoint("CENTER", r.markerGold)
   r.marker:SetTexture("Interface\\Buttons\\WHITE8x8")
   r.marker:SetRotation(math.rad(45))
   -- (the box: a bevelled gold frame round a name strip and a health bar)
   local box = CreateFrame("Frame", nil, r)
   box:SetPoint("TOPLEFT", 15, 0)
   box:SetPoint("BOTTOMRIGHT", 0, 0)
   local inset = Bevel(box)
   local strip = box:CreateTexture(nil, "BACKGROUND")
   strip:SetPoint("TOPLEFT", inset, -inset)
   strip:SetPoint("TOPRIGHT", -inset, -inset)
   strip:SetHeight(NAME_H)
   strip:SetTexture("Interface\\Buttons\\WHITE8x8")
   strip:SetGradient("HORIZONTAL", CreateColor(0.55, 0.06, 0.05, 0.95), CreateColor(0.18, 0.02, 0.02, 0.95))
   -- (the gold line between name and bar)
   local line = box:CreateTexture(nil, "BORDER", nil, 2)
   line:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, 0)
   line:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 0, 0)
   line:SetHeight(1)
   line:SetColorTexture(0.85, 0.64, 0.20, 1)
   r.name = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   r.name:SetPoint("LEFT", strip, "LEFT", 3, 0)
   r.name:SetPoint("RIGHT", strip, "RIGHT", -3, 0)
   r.name:SetJustifyH("CENTER")
   r.name:SetWordWrap(false)
   r.name:SetShadowOffset(1, -1)
   r.name:SetShadowColor(0, 0, 0, 1)
   r.bar = CreateFrame("StatusBar", nil, box)
   r.bar:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, 0)
   r.bar:SetPoint("BOTTOMRIGHT", -inset, inset)
   r.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
   r.bar:SetStatusBarColor(0.12, 0.72, 0.1, 1)
   local bg = r.bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.03, 0.03, 0.03, 0.9)
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
         if targeted then r.name:SetTextColor(1, 1, 1) else r.name:SetTextColor(1, 0.82, 0) end
         -- (health may be secret: straight into the bar)
         r.bar:SetMinMaxValues(0, UnitHealthMax(e.unit) or 1)
         r.bar:SetValue(UnitHealth(e.unit) or 0)
         Colour(r, e)
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

local ticker = CreateFrame("Frame")
local since = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
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
