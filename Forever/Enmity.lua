-- Enmity list (as FFXIV's): the enemies engaged with you, in a small movable
-- list, and D-pad left / right (no trigger held) to target the previous /
-- next one in it. D-pad up / down stay CrossHotbar's party navigation.
--
-- The list (insecure, every 0.2 s): enemies from the nameplates
-- (nameplate1..40) and the units the game names (target, focus, soft target,
-- mouseover, the party's targets), alive, attackable, and targeting you or
-- on your threat list; most threat first. Each row: a threat colour, name,
-- health; the current target marked. In a fight, a diagnostic line to the
-- debug log every 3 s.
--
-- Targeting (secure): two buttons, Next and Prev, bound to the D-pad by
-- CrossHotbar ("CLICK CHBEnmityNext:LeftButton"...). Their snippet reads the
-- list's order from a plain (unprotected) data frame's attributes, which the
-- list keeps up to date even in combat, finds the current target in it, and
-- targets the next / previous unit token with the "target" action. A trace
-- goes to CrossHotbar_DB.ForeverLog.
--
-- Needs enemy nameplates (the list is made from them): turned on with it.
-- /xhb enmity  shows / hides the list;  /xhb enmity lock  locks / unlocks it.
local ADDON, addon = ...

local MAX_ROWS = 8
local ROW_W, ROW_H = 200, 18

local E = {}
addon.Enmity = E

local function Settings()
   local s = addon.ForeverSettings and addon:ForeverSettings()
   if not s then return nil end
   if s.enmity == nil then s.enmity = true end
   return s
end

---------------------------------------------------------------------------
-- The data frame the secure buttons read (plain frame: writable in combat)
---------------------------------------------------------------------------
local data = CreateFrame("Frame", "CHBEnmityData", UIParent)
data:Hide()
data:SetAttribute("count", 0)

local units, list = {}, {}

-- (why each candidate was kept or not: for the diagnostics)
local function Check(unit)
   if not UnitExists(unit) then return nil, "none" end
   if not UnitCanAttack("player", unit) then return nil, "friendly" end
   if UnitIsDead(unit) then return nil, "dead" end
   local targetsMe = UnitIsUnit(unit .. "target", "player")
   local tanking, status, pct
   if UnitDetailedThreatSituation then
      tanking, status, pct = UnitDetailedThreatSituation("player", unit)
   end
   if not status and UnitThreatSituation then status = UnitThreatSituation("player", unit) end
   if not (targetsMe or status) then
      return nil, "not engaged (combat=" .. tostring(UnitAffectingCombat(unit)) .. ")"
   end
   return { unit = unit, targetsMe = targetsMe, tanking = tanking, status = status or 0, pct = pct or 0 }, "kept"
end

-- Where enemies can come from: nameplates, then the units the game names
-- (target, focus, soft target, mouseover, the party's targets)
local OTHER = { "target", "focus", "softenemy", "mouseover", "targettarget",
                "party1target", "party2target", "party3target", "party4target" }

local diagAt = 0
local function Scan()
   wipe(list)
   local seen, plates, why = {}, 0, {}
   local function consider(unit)
      local guid = UnitGUID(unit)
      if not guid or seen[guid] then return end
      seen[guid] = true
      if unit:find("^nameplate") then plates = plates + 1 end
      local e, reason = Check(unit)
      if e then list[#list + 1] = e end
      if #why < 4 then why[#why + 1] = unit .. "=" .. (UnitName(unit) or "?") .. ":" .. reason end
   end
   for i = 1, 40 do consider("nameplate" .. i) end
   for _, unit in ipairs(OTHER) do consider(unit) end
   table.sort(list, function(a, b)
      if (a.targetsMe or a.tanking) ~= (b.targetsMe or b.tanking) then return (a.targetsMe or a.tanking) and true or false end
      if a.status ~= b.status then return a.status > b.status end
      return a.pct > b.pct
   end)
   data:SetAttribute("count", #list)
   for i = 1, 40 do data:SetAttribute("u" .. i, list[i] and list[i].unit or nil) end
   -- (diagnostics: in a fight, every 3 s, to the debug log)
   if UnitAffectingCombat("player") and GetTime() - diagAt > 3 and addon.ForeverLog then
      diagAt = GetTime()
      local platesAPI = C_NamePlate and C_NamePlate.GetNamePlates and #C_NamePlate.GetNamePlates() or -1
      addon:ForeverLog(("enmity scan: plates %d (C_NamePlate %d), listed %d, cvar %s | %s"):format(plates, platesAPI, #list,
         tostring(C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("nameplateShowEnemies")), table.concat(why, "; ")))
   end
end

---------------------------------------------------------------------------
-- The list on screen
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "CHBEnmityFrame", UIParent, "BackdropTemplate")
frame:SetSize(ROW_W + 8, 22 + MAX_ROWS * (ROW_H + 2))
frame:SetPoint("RIGHT", UIParent, "RIGHT", -260, 80)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
if frame.SetBackdrop then
   frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
   frame:SetBackdropColor(0, 0, 0, 0.35)
end
local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOPLEFT", 6, -5)
local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("TOPRIGHT", -6, -5)

local rows = {}
for i = 1, MAX_ROWS do
   local r = CreateFrame("Frame", nil, frame)
   r:SetSize(ROW_W, ROW_H)
   r:SetPoint("TOPLEFT", 4, -20 - (i - 1) * (ROW_H + 2))
   r.bar = CreateFrame("StatusBar", nil, r)
   r.bar:SetPoint("TOPLEFT", 12, 0); r.bar:SetPoint("BOTTOMRIGHT")
   r.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
   r.bar:SetStatusBarColor(0.55, 0.1, 0.1, 0.9)
   r.bar:SetMinMaxValues(0, 1)
   local bg = r.bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.6)
   r.threat = r:CreateTexture(nil, "ARTWORK"); r.threat:SetSize(8, ROW_H); r.threat:SetPoint("LEFT")
   r.name = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   r.name:SetPoint("LEFT", 4, 0); r.name:SetPoint("RIGHT", -30, 0); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
   r.pct = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.pct:SetPoint("RIGHT", -3, 0)
   r.mark = r:CreateTexture(nil, "OVERLAY"); r.mark:SetPoint("TOPLEFT", -2, 2); r.mark:SetPoint("BOTTOMRIGHT", 2, -2)
   r.mark:SetColorTexture(1, 0.82, 0, 0.35)
   rows[i] = r
end

local THREAT_COLORS = { [0] = { 0.3, 0.8, 0.3 }, [1] = { 1, 1, 0.2 }, [2] = { 1, 0.55, 0 }, [3] = { 1, 0.15, 0.1 } }

local function Draw()
   local s = Settings()
   local unlocked = s and not s.enmityLocked
   if not (s and s.enmity) or (#list == 0 and not unlocked) then frame:Hide() return end
   frame:Show()
   title:SetText("Enmity")
   hint:SetText(unlocked and "drag to move" or "")
   for i, r in ipairs(rows) do
      local e = list[i]
      if e then
         local hp, max = UnitHealth(e.unit), UnitHealthMax(e.unit)
         r.bar:SetValue(max and max > 0 and hp / max or 0)
         r.name:SetText(UnitName(e.unit) or "?")
         r.pct:SetText(max and max > 0 and (math.floor(hp / max * 100 + 0.5) .. "%") or "")
         local c = THREAT_COLORS[e.targetsMe and 3 or e.status] or THREAT_COLORS[0]
         r.threat:SetColorTexture(c[1], c[2], c[3], 1)
         r.mark:SetShown(UnitIsUnit(e.unit, "target"))
         r:Show()
      else
         r:Hide()
      end
   end
   local shown = math.max(1, math.min(#list, MAX_ROWS))
   frame:SetHeight(22 + shown * (ROW_H + 2))
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
-- The secure Next / Prev buttons
---------------------------------------------------------------------------
local function TargetButton(name, step)
   local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
   b:SetSize(1, 1)
   b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -20, 20)
   b:RegisterForClicks("AnyDown")
   b:SetAttribute("step", step)
   function b:EnmityLog(msg) if addon.ForeverLog then addon:ForeverLog("enmity: " .. msg) end end
   SecureHandlerSetFrameRef(b, "data", data)
   SecureHandlerWrapScript(b, "OnClick", b, [[
      self:SetAttribute("type", nil)
      local data = self:GetFrameRef("data")
      local count = data and data:GetAttribute("count") or 0
      if count == 0 then
         self:CallMethod("EnmityLog", "press: list empty")
         return false
      end
      local step = self:GetAttribute("step")
      -- (where the current target is in the list; none: start at the top / bottom)
      local at = 0
      for i = 1, count do
         local u = data:GetAttribute("u" .. i)
         if u and UnitIsUnit(u, "target") then at = i end
      end
      local nextAt
      if at == 0 then nextAt = (step > 0) and 1 or count
      else nextAt = ((at - 1 + step) % count) + 1 end
      local unit = data:GetAttribute("u" .. nextAt)
      self:CallMethod("EnmityLog", "press: " .. tostring(at) .. " -> " .. tostring(nextAt) .. " " .. tostring(unit) .. " of " .. count)
      if not unit then return false end
      self:SetAttribute("unit", unit)
      self:SetAttribute("type", "target")
   ]])
   return b
end

TargetButton("CHBEnmityNext", 1)
TargetButton("CHBEnmityPrev", -1)

---------------------------------------------------------------------------
-- Setting up: enemy nameplates on; the list's place; D-pad left / right
---------------------------------------------------------------------------
function E.Apply()
   local s = Settings()
   if not s then return end
   if s.enmityPos then
      frame:ClearAllPoints()
      frame:SetPoint(s.enmityPos[1], UIParent, s.enmityPos[2], s.enmityPos[3], s.enmityPos[4])
   end
   if s.enmity and not InCombatLockdown() and C_CVar and C_CVar.SetCVar then
      if C_CVar.GetCVar("nameplateShowEnemies") ~= "1" then C_CVar.SetCVar("nameplateShowEnemies", "1") end
   end
   if s.enmity and not s.enmityDpad and _G.CrossHotbar_SetPadAction and not InCombatLockdown() then
      local r = _G.CrossHotbar_SetPadAction("DPADR", "CLICK CHBEnmityNext:LeftButton")
      local l = _G.CrossHotbar_SetPadAction("DPADL", "CLICK CHBEnmityPrev:LeftButton")
      if r and l then
         s.enmityDpad = true
         print("|cff66ccffCrossHotbar|r: D-pad left / right now target through the enmity list (up / down: your party).")
      end
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
