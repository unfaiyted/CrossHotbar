-- Party list: a clean replacement for the game's party frames, in the
-- enmity list's style (bronze trim, thin bars), that keeps the controller's
-- party navigation (CrossHotbar's GroupNavigator, D-pad up / down) working.
--
--   one row per member (you first, then party1-4): a class-coloured name, the
--   leader's crown, a health bar in a bronze trim, a thin power bar; dead /
--   ghost / offline in place of the health; faded when out of range; a gold
--   rim on your target, a red rim when something's attacking them.
--   Each row is a secure unit button (CHBPartyUnitButton1-5): left click
--   targets, right click opens the unit's menu, and GroupNavigator finds
--   them by that name (GroupNavigator.lua's party prefixes), so D-pad up /
--   down move through them and its highlight sits on them.
-- The game's party frames are faded out (an alpha animation of ours aimed at
-- them, as Improved Forever's Focus.Fade: their own properties untouched, so
-- nothing of the game's is tainted).
-- /xhb party  on / off;  /xhb party lock  locks / unlocks (unlocked: drag it).
local ADDON, addon = ...

local ROW_W, ROW_H = 180, 30
local GAP = 4
local UNITS = { "player", "party1", "party2", "party3", "party4" }

local P = {}
addon.Party = P

local function Settings()
   local s = addon.ForeverSettings and addon:ForeverSettings()
   if not s then return nil end
   if s.party == nil then s.party = true end
   return s
end

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function Plain(v)
   if Secret(v) then return false end
   return v and true or false
end

---------------------------------------------------------------------------
-- Style (as the enmity list's)
---------------------------------------------------------------------------
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
   local o = BEVEL[1].light
   for _, c in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 }, { "BOTTOMLEFT", 1, 1 }, { "BOTTOMRIGHT", -1, 1 } }) do
      local px = box:CreateTexture(nil, "BORDER", nil, 7)
      px:SetColorTexture(o[1], o[2], o[3], o[4]); px:SetSize(1, 1); px:SetPoint(c[1], c[2], c[3])
   end
   return #BEVEL
end

-- A 2px rim round a row (target: gold; under attack: red)
local function Rim(parent, r, g, b)
   local rim = CreateFrame("Frame", nil, parent, "BackdropTemplate")
   rim:SetPoint("TOPLEFT", -2, 2); rim:SetPoint("BOTTOMRIGHT", 2, -2)
   if rim.SetBackdrop then
      rim:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
      rim:SetBackdropBorderColor(r, g, b, 0.9)
   end
   rim:Hide()
   return rim
end

---------------------------------------------------------------------------
-- The rows
---------------------------------------------------------------------------
local holder = CreateFrame("Frame", "CHBPartyFrame", UIParent, "BackdropTemplate")
holder:SetSize(ROW_W, #UNITS * (ROW_H + GAP))
holder:SetPoint("LEFT", UIParent, "LEFT", 30, 120)
holder:SetMovable(true)
holder:SetClampedToScreen(true)
holder:RegisterForDrag("LeftButton")
if holder.SetBackdrop then holder:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" }) end
local title = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, 2)
title:SetText("Party  |cff999999(drag to move; /xhb party lock)|r")

local rows = {}
for i, unit in ipairs(UNITS) do
   local b = CreateFrame("Button", "CHBPartyUnitButton" .. i, holder, "SecureUnitButtonTemplate")
   b:SetSize(ROW_W, ROW_H)
   b:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + GAP))
   b:SetAttribute("unit", unit)
   b:SetAttribute("type1", "target")
   b:SetAttribute("type2", "togglemenu")
   b:RegisterForClicks("AnyUp")
   b.unit = unit
   if unit ~= "player" then RegisterUnitWatch(b) end

   b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   b.name:SetPoint("TOPLEFT", 2, 0)
   b.name:SetPoint("RIGHT", -24, 0)
   b.name:SetJustifyH("LEFT")
   b.name:SetWordWrap(false)
   b.name:SetShadowOffset(1, -1); b.name:SetShadowColor(0, 0, 0, 1)
   b.state = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
   b.state:SetPoint("TOPRIGHT", -2, 0)
   b.leader = b:CreateTexture(nil, "OVERLAY")
   b.leader:SetSize(12, 12)
   b.leader:SetPoint("RIGHT", b.state, "LEFT", -2, 0)
   b.leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
   b.leader:Hide()

   local box = CreateFrame("Frame", nil, b)
   box:SetPoint("BOTTOMLEFT", 0, 0)
   box:SetPoint("BOTTOMRIGHT", 0, 0)
   box:SetHeight(6 + 8)
   local inset = Bevel(box)
   b.hp = CreateFrame("StatusBar", nil, box)
   b.hp:SetPoint("TOPLEFT", inset, -inset)
   b.hp:SetPoint("BOTTOMRIGHT", -inset, inset + 3)
   b.hp:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
   local hbg = b.hp:CreateTexture(nil, "BACKGROUND"); hbg:SetAllPoints(); hbg:SetColorTexture(0.137, 0.11, 0.075, 1)
   b.pw = CreateFrame("StatusBar", nil, box)
   b.pw:SetPoint("TOPLEFT", b.hp, "BOTTOMLEFT", 0, -1)
   b.pw:SetPoint("BOTTOMRIGHT", -inset, inset)
   b.pw:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
   local pbg = b.pw:CreateTexture(nil, "BACKGROUND"); pbg:SetAllPoints(); pbg:SetColorTexture(0.05, 0.04, 0.03, 1)

   b.targetRim = Rim(b, 1, 0.82, 0.3)
   b.aggroRim = Rim(b, 0.9, 0.15, 0.1)
   rows[i] = b
end

local function Update(b)
   local unit = b.unit
   if not UnitExists(unit) then return end
   local name = UnitName(unit)
   b.name:SetText(name or "?")
   local _, class = UnitClass(unit)
   local cc = class and (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
      or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
   if cc then b.name:SetTextColor(cc.r, cc.g, cc.b) else b.name:SetTextColor(1, 1, 1) end
   -- (health / power may be secret: straight into the bars)
   b.hp:SetMinMaxValues(0, UnitHealthMax(unit) or 1)
   b.hp:SetValue(UnitHealth(unit) or 0)
   if cc then b.hp:SetStatusBarColor(cc.r * 0.85, cc.g * 0.85, cc.b * 0.85, 1) else b.hp:SetStatusBarColor(0.2, 0.7, 0.2, 1) end
   local ptype, ptoken = UnitPowerType(unit)
   local pc = PowerBarColor and (PowerBarColor[ptoken] or PowerBarColor[ptype])
   if pc then b.pw:SetStatusBarColor(pc.r, pc.g, pc.b, 1) else b.pw:SetStatusBarColor(0.2, 0.4, 1, 1) end
   b.pw:SetMinMaxValues(0, UnitPowerMax(unit) or 1)
   b.pw:SetValue(UnitPower(unit) or 0)
   -- (states)
   local state = ""
   if not Plain(UnitIsConnected(unit)) and unit ~= "player" then state = "Offline"
   elseif Plain(UnitIsGhost(unit)) then state = "Ghost"
   elseif Plain(UnitIsDead(unit)) then state = "Dead" end
   b.state:SetText(state)
   b.leader:SetShown(Plain(UnitIsGroupLeader(unit)))
   -- (out of range: faded)
   local inRange = true
   if unit ~= "player" and UnitInRange then
      local r, checked = UnitInRange(unit)
      if Plain(checked) then inRange = Plain(r) end
   end
   b:SetAlpha((state ~= "" or not inRange) and 0.45 or 1)
   b.targetRim:SetShown(Plain(UnitIsUnit(unit, "target")))
   local threat = UnitThreatSituation and UnitThreatSituation(unit)
   b.aggroRim:SetShown(not Secret(threat) and type(threat) == "number" and threat >= 2)
end

---------------------------------------------------------------------------
-- The game's party frames out of sight (an alpha animation of ours aimed at
-- them; Improved Forever's Focus.Fade when it's there)
---------------------------------------------------------------------------
local fader = CreateFrame("Frame")
local fades = {}
local function Fade(region, hide)
   if not (region and region.GetObjectType) then return end
   local IF = _G.ImprovedForever
   if IF and IF.Focus and IF.Focus.Fade then return IF.Focus.Fade(region, hide) end
   local group = fades[region]
   if not group then
      if not hide then return end
      group = fader:CreateAnimationGroup()
      local a = group:CreateAnimation("Alpha")
      a:SetTarget(region)
      a:SetDuration(3600); a:SetFromAlpha(0); a:SetToAlpha(0)
      group:SetLooping("REPEAT")
      fades[region] = group
   end
   if hide and not group:IsPlaying() then group:Play()
   elseif not hide and group:IsPlaying() then group:Stop() end
end

local function GameFrames(hide)
   Fade(_G.PartyFrame, hide)
   Fade(_G.CompactPartyFrame, hide)
   for i = 1, 4 do Fade(_G["PartyMemberFrame" .. i], hide) end
end

---------------------------------------------------------------------------
-- Showing, placing, updating
---------------------------------------------------------------------------
local function Apply()
   local s = Settings()
   if not s then return end
   if s.partyPos then
      holder:ClearAllPoints()
      holder:SetPoint(s.partyPos[1], UIParent, s.partyPos[2], s.partyPos[3], s.partyPos[4])
   end
   local inGroup = IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid())
   local show = s.party and (inGroup or not s.partyLocked)
   if not InCombatLockdown() then holder:SetShown(show and true or false) end
   GameFrames(s.party and inGroup)
   local unlocked = not s.partyLocked
   holder:EnableMouse(unlocked)
   if holder.SetBackdropColor then holder:SetBackdropColor(0, 0, 0, unlocked and 0.35 or 0) end
   title:SetShown(unlocked)
   -- (GroupNavigator re-reads the frames it navigates)
   if addon.GroupNavigator and addon.GroupNavigator.AddUnitFrameRefs and not InCombatLockdown() then
      addon.GroupNavigator:AddUnitFrameRefs()
   end
end
P.Apply = Apply

holder:SetScript("OnDragStart", function(self)
   local s = Settings()
   if s and not s.partyLocked then self:StartMoving() end
end)
holder:SetScript("OnDragStop", function(self)
   self:StopMovingOrSizing()
   local s = Settings()
   if s then
      local point, _, rel, x, y = self:GetPoint(1)
      s.partyPos = { point, rel, x, y }
   end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function() C_Timer.After(0.3, Apply) end)

local since = 0
holder:SetScript("OnUpdate", function(_, elapsed)
   since = since + elapsed
   if since < 0.15 then return end
   since = 0
   for _, b in ipairs(rows) do
      if b:IsShown() then pcall(Update, b) end
   end
end)

function addon:PartyCommand(value)
   local s = Settings()
   if not s then return end
   if value == "lock" then
      s.partyLocked = not s.partyLocked
      print("|cff66ccffCrossHotbar|r: party list " .. (s.partyLocked and "locked." or "unlocked: drag it where you want it."))
   else
      s.party = not s.party
      print("|cff66ccffCrossHotbar|r: party list " .. (s.party and "on (the game's party frames hidden)." or "off (the game's party frames back)."))
   end
   Apply()
end
