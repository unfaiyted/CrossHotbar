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
local ROW_H = 16          -- (name line + thin bar)
local BAR_H = 3

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

local rows = {}
for i = 1, MAX_ROWS do
   local r = CreateFrame("Frame", nil, frame)
   r:SetSize(ROW_W, ROW_H)
   r:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + 3))
   -- (the aggro marker: a small diamond)
   r.marker = r:CreateTexture(nil, "ARTWORK")
   r.marker:SetSize(8, 8)
   r.marker:SetPoint("TOPLEFT", 1, -2)
   r.marker:SetTexture("Interface\\Buttons\\WHITE8x8")
   r.marker:SetRotation(math.rad(45))
   r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   r.name:SetPoint("TOPLEFT", 14, 0)
   r.name:SetPoint("RIGHT", 0, 0)
   r.name:SetJustifyH("LEFT")
   r.name:SetWordWrap(false)
   r.name:SetShadowOffset(1, -1)
   r.name:SetShadowColor(0, 0, 0, 1)
   r.bar = CreateFrame("StatusBar", nil, r)
   r.bar:SetPoint("BOTTOMLEFT", 14, 0)
   r.bar:SetPoint("BOTTOMRIGHT", 0, 0)
   r.bar:SetHeight(BAR_H)
   r.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
   r.bar:SetStatusBarColor(0.85, 0.2, 0.15, 1)
   local bg = r.bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
   rows[i] = r
end

local RED, ORANGE, GREEN = { 1, 0.2, 0.15 }, { 1, 0.6, 0.1 }, { 0.3, 0.85, 0.35 }

-- The marker's colour: the game's threat colour of your status (secret is
-- fine: it goes straight to the texture); else on you / on the party
local function Colour(r, e)
   if type(e.status) == "number" and GetThreatStatusColor then
      local ok, cr, cg, cb = pcall(GetThreatStatusColor, e.status)
      if ok and type(cr) == "number" then
         -- (status 0, low threat: the game's grey; when it can be read, ours green)
         if not Secret(e.status) and e.status == 0 then cr, cg, cb = GREEN[1], GREEN[2], GREEN[3] end
         if pcall(r.marker.SetVertexColor, r.marker, cr, cg, cb, 1) then return end
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
         r.name:SetTextColor(1, targeted and 0.85 or 1, targeted and 0.3 or 1)
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
