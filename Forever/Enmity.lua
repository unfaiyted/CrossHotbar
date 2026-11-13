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
-- CrossHotbar ("CLICK CHBEnmityNext:LeftButton"...). On each press their
-- snippet builds the same list from the nameplates (a plain frame can't be
-- read by secure code in a fight: "Invalid frame handle"), finds the current
-- target in it, and targets the next / previous one with the "target"
-- action. A trace goes to CrossHotbar_DB.ForeverLog.
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

local list = {}

local function Secret(v)
   return issecretvalue ~= nil and issecretvalue(v)
end

-- A plain true / false from something that may be secret (secret: unknown, false)
local function Plain(v)
   if Secret(v) then return false end
   return v and true or false
end

-- The rules, the same as the secure buttons' (below), so the list on screen
-- and D-pad left / right agree: enemy nameplates, alive and attackable,
-- fighting someone (their target exists), in nameplate order. Red: it's on
-- you (the list can tell; the secure buttons can't, so it doesn't reorder).
-- (Threat isn't used: secure code can't read it, and it's secret anyway.)
local function Hostile(unit)
   return UnitExists(unit) and Plain(UnitCanAttack("player", unit)) and not Plain(UnitIsDead(unit))
end

local diagAt = 0
local function Scan()
   wipe(list)
   local plates, onMe = 0, 0
   for i = 1, 40 do
      local unit = "nameplate" .. i
      if UnitExists(unit) then plates = plates + 1 end
      if Hostile(unit) and UnitExists(unit .. "target") then
         local targetsMe = Plain(UnitIsUnit(unit .. "target", "player"))
         if targetsMe then onMe = onMe + 1 end
         list[#list + 1] = { unit = unit, targetsMe = targetsMe }
      end
   end
   if UnitAffectingCombat("player") and GetTime() - diagAt > 3 and addon.ForeverLog then
      diagAt = GetTime()
      local parts = {}
      for i = 1, math.min(#list, 4) do parts[i] = list[i].unit .. (list[i].targetsMe and "*" or "") end
      addon:ForeverLog(("enmity scan: plates %d, listed %d (%d on you) %s"):format(plates, #list, onMe, table.concat(parts, " ")))
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
         -- (health may be secret: straight into the bar, which takes it)
         r.bar:SetMinMaxValues(0, UnitHealthMax(e.unit) or 1)
         r.bar:SetValue(UnitHealth(e.unit) or 0)
         r.name:SetText(UnitName(e.unit) or "?")
         r.pct:SetText("")
         local c = THREAT_COLORS[e.targetsMe and 3 or 2]
         r.threat:SetColorTexture(c[1], c[2], c[3], 1)
         r.mark:SetShown(Plain(UnitIsUnit(e.unit, "target")))
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
   SecureHandlerWrapScript(b, "OnClick", b, [[
      self:SetAttribute("type", nil)
      -- (the list, as the one on screen: enemy nameplates fighting someone
      -- (their target exists), alive and attackable where the restricted
      -- environment has those checks; nameplate order. It has UnitExists, not
      -- UnitIsUnit, and macro conditions don't take nameplate units.)
      local canAttack, isDead = PlayerCanAttack, UnitIsDead
      if not self:GetAttribute("told") then
         self:SetAttribute("told", true)
         self:CallMethod("EnmityLog", "secure checks: PlayerCanAttack=" .. (canAttack and "y" or "n")
            .. " UnitIsDead=" .. (isDead and "y" or "n"))
      end
      local units, count = newtable(), 0
      for i = 1, 40 do
         local u = "nameplate" .. i
         if UnitExists(u) and UnitExists(u .. "target")
            and (not canAttack or canAttack(u)) and (not isDead or not isDead(u)) then
            count = count + 1
            units[count] = i
         end
      end
      if count == 0 then
         self:CallMethod("EnmityLog", "press: list empty")
         return false
      end
      -- (where we are: the nameplate targeted last by these buttons; the next
      -- one after it in the list, or the previous one)
      local step = self:GetAttribute("step")
      local shared = self:GetFrameRef("shared")
      local last = shared and shared:GetAttribute("last") or 0
      local at = 0
      for i = 1, count do if units[i] == last then at = i end end
      local nextAt
      if at == 0 then nextAt = (step > 0) and 1 or count
      else nextAt = ((at - 1 + step) % count) + 1 end
      local index = units[nextAt]
      if shared then shared:SetAttribute("last", index) end
      self:CallMethod("EnmityLog", "press: " .. at .. " -> " .. nextAt .. " nameplate" .. index .. " of " .. count)
      self:SetAttribute("unit", "nameplate" .. index)
      self:SetAttribute("type", "target")
   ]])
   return b
end

local nextButton = TargetButton("CHBEnmityNext", 1)
local prevButton = TargetButton("CHBEnmityPrev", -1)
-- (the position both share: a secure frame of ours)
local shared = CreateFrame("Frame", "CHBEnmityState", UIParent, "SecureHandlerBaseTemplate")
shared:SetAttribute("last", 0)
SecureHandlerSetFrameRef(nextButton, "shared", shared)
SecureHandlerSetFrameRef(prevButton, "shared", shared)

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
