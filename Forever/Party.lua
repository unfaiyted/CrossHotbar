-- Party list: a replacement for the game's party frames, laid out as FFXIV's
-- party list, drawn in WoW's colours and bronze trim; the controller's party
-- navigation (CrossHotbar's GroupNavigator, D-pad up / down) moves through it.
--
--   (class)  ① Lv60  Name                              [buffs...]
--            [===== health (green) =====]  [== power ==]
--             22307                          10416
--
--   the class icon round, in a bronze ring; the party slot in a small badge;
--   level in gold, the name white; health green, power in its colour (mana
--   blue, rage red, energy yellow), both in a rounded bronze trim, their
--   values under them; buffs on the right (when the game lets them be read).
--   Selected (the D-pad's, or your target): gold corner brackets (as
--   FFXIV's), the ring and name gold, a soft glow behind the icon
--   (CrossHotbar's white navigation box is hidden while the list is on).
--   Attacked: a red edge.
--   Dead / ghost / offline replace the values; out of range: faded.
-- Each row is a secure unit button (CHBPartyUnitButton1-5): left click
-- targets, right click opens the unit's menu. GroupNavigator, with this list
-- on, navigates only these rows (GroupNavigator.lua). The game's party frames
-- are faded out (an alpha animation of ours aimed at them, as Improved
-- Forever's Focus.Fade: nothing of the game's is tainted).
-- /xhb party  on / off;  /xhb party lock  locks / unlocks (unlocked: drag it).
local ADDON, addon = ...

local UNITS = { "player", "party1", "party2", "party3", "party4" }
local ICON = 28
local HP_W, PW_W, BAR_H = 140, 64, 6
local ROW_W = ICON + 8 + HP_W + 6 + PW_W + 8 + 5 * 17
local ROW_H = 36
local GAP = 4
local MAX_BUFFS = 5

local P = {}
addon.Party = P

local function Settings()
   local s = addon.ForeverSettings and addon:ForeverSettings()
   if not s then return nil end
   if s.party == nil then s.party = true end
   return s
end

function P.Active()
   local s = Settings()
   return s and s.party and true or false
end

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function Plain(v)
   if Secret(v) then return false end
   return v and true or false
end

---------------------------------------------------------------------------
-- Style: the bronze trim (as the enmity list's), rounded at the corners
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

-- A trimmed bar: its trim frame, and the StatusBar inside
local function Bar(parent, width, colour)
   local box = CreateFrame("Frame", nil, parent)
   box:SetSize(width, BAR_H + 6)
   local inset = Bevel(box)
   local bar = CreateFrame("StatusBar", nil, box)
   bar:SetPoint("TOPLEFT", inset, -inset)
   bar:SetPoint("BOTTOMRIGHT", -inset, inset)
   bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
   bar:SetStatusBarColor(colour[1], colour[2], colour[3], 1)
   local bg = bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.137, 0.11, 0.075, 1)
   return box, bar
end

local HEALTH = { 0.15, 0.75, 0.15 }

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
   b.unit, b.slot = unit, i
   if unit ~= "player" then RegisterUnitWatch(b) end

   -- (the class icon: the game's round one, in a bronze ring)
   local ring = b:CreateTexture(nil, "BACKGROUND", nil, 1)
   ring:SetSize(ICON + 4, ICON + 4)
   ring:SetPoint("LEFT", 0, 0)
   ring:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
   ring:SetVertexColor(BRASS_LIGHT[1], BRASS_LIGHT[2], BRASS_LIGHT[3], 1)
   b.ring = ring
   -- (selected: a soft gold glow behind the ring)
   b.glow = b:CreateTexture(nil, "BACKGROUND", nil, 0)
   b.glow:SetSize(ICON + 14, ICON + 14)
   b.glow:SetPoint("CENTER", ring)
   b.glow:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
   b.glow:SetVertexColor(1, 0.8, 0.3, 0.35)
   b.glow:Hide()
   local well = b:CreateTexture(nil, "BACKGROUND", nil, 2)
   well:SetSize(ICON + 1, ICON + 1)
   well:SetPoint("CENTER", ring)
   well:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
   well:SetVertexColor(0.05, 0.04, 0.02, 1)
   b.class = b:CreateTexture(nil, "ARTWORK")
   b.class:SetSize(ICON - 2, ICON - 2)
   b.class:SetPoint("CENTER", ring)
   b.class:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")

   local x = ICON + 8
   -- (the slot badge, level, name)
   b.badge = b:CreateTexture(nil, "ARTWORK")
   b.badge:SetSize(12, 12)
   b.badge:SetPoint("TOPLEFT", x, -1)
   b.badge:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
   b.badge:SetVertexColor(BRASS_DARK[1], BRASS_DARK[2], BRASS_DARK[3], 1)
   b.slotText = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   b.slotText:SetPoint("CENTER", b.badge, "CENTER", 0, 0)
   b.slotText:SetText(i)
   b.level = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   b.level:SetPoint("LEFT", b.badge, "RIGHT", 4, 0)
   b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   b.name:SetPoint("LEFT", b.level, "RIGHT", 4, 0)
   b.name:SetWidth(HP_W + PW_W - 40)
   b.name:SetJustifyH("LEFT")
   b.name:SetWordWrap(false)
   b.name:SetShadowOffset(1, -1); b.name:SetShadowColor(0, 0, 0, 1)

   -- (health and power side by side, values under them)
   b.hpBox, b.hp = Bar(b, HP_W, HEALTH)
   b.hpBox:SetPoint("TOPLEFT", x - 1, -15)
   b.pwBox, b.pw = Bar(b, PW_W, { 0.2, 0.4, 1 })
   b.pwBox:SetPoint("LEFT", b.hpBox, "RIGHT", 6, 0)
   b.hpText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
   b.hpText:SetPoint("TOPLEFT", b.hpBox, "BOTTOMLEFT", 2, 0)
   b.pwText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
   b.pwText:SetPoint("TOPLEFT", b.pwBox, "BOTTOMLEFT", 2, 0)
   b.state = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
   b.state:SetPoint("TOPLEFT", b.hpBox, "BOTTOMLEFT", 2, 0)

   -- (buffs on the right)
   b.buffs = {}
   for k = 1, MAX_BUFFS do
      local t = b:CreateTexture(nil, "ARTWORK")
      t:SetSize(15, 15)
      t:SetPoint("LEFT", b.pwBox, "RIGHT", 8 + (k - 1) * 17, 4)
      t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      t:Hide()
      b.buffs[k] = t
   end

   -- (selected: gold corner brackets, as FFXIV's)
   b.bracket = CreateFrame("Frame", nil, b)
   b.bracket:SetAllPoints()
   for _, c in ipairs({ { "TOPLEFT", -2, 2, 10, 2 }, { "TOPLEFT", -2, 2, 2, 10 },
                        { "TOPRIGHT", 2, 2, 10, 2 }, { "TOPRIGHT", 2, 2, 2, 10 },
                        { "BOTTOMLEFT", -2, -2, 10, 2 }, { "BOTTOMLEFT", -2, -2, 2, 10 },
                        { "BOTTOMRIGHT", 2, -2, 10, 2 }, { "BOTTOMRIGHT", 2, -2, 2, 10 } }) do
      local t = b.bracket:CreateTexture(nil, "OVERLAY")
      t:SetColorTexture(1, 0.82, 0.3, 1)
      t:SetSize(c[4], c[5])
      t:SetPoint(c[1], b, c[1], c[2], c[3])
   end
   b.bracket:Hide()
   -- (attacked: a red edge)
   b.aggro = b:CreateTexture(nil, "OVERLAY")
   b.aggro:SetColorTexture(0.9, 0.15, 0.1, 1)
   b.aggro:SetSize(2, ROW_H - 6)
   b.aggro:SetPoint("RIGHT", b, "LEFT", -2, 0)
   b.aggro:Hide()
   rows[i] = b
end

---------------------------------------------------------------------------
-- Updating a row
---------------------------------------------------------------------------
local function Buffs(b, unit)
   local n = 0
   if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      for k = 1, 40 do
         if n >= MAX_BUFFS then break end
         local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, k, "HELPFUL")
         if not (ok and aura) then break end
         n = n + 1
         b.buffs[n]:SetTexture(aura.icon)
         b.buffs[n]:Show()
      end
   end
   for k = n + 1, MAX_BUFFS do b.buffs[k]:Hide() end
end

local function Update(b)
   local unit = b.unit
   if not UnitExists(unit) then return end
   local _, class = UnitClass(unit)
   local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
   if coords then b.class:SetTexCoord(coords[1], coords[2], coords[3], coords[4]); b.class:Show() else b.class:Hide() end
   local level = UnitLevel(unit)
   b.level:SetText((not Secret(level) and level and level > 0) and ("Lv" .. level) or "Lv??")
   b.name:SetText(UnitName(unit) or "?")
   -- (health and power may be secret: straight into the bars and texts)
   local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
   b.hp:SetMinMaxValues(0, hpMax or 1)
   b.hp:SetValue(hp or 0)
   local ptype, ptoken = UnitPowerType(unit)
   local pc = PowerBarColor and (PowerBarColor[ptoken] or PowerBarColor[ptype])
   if pc then b.pw:SetStatusBarColor(pc.r, pc.g, pc.b, 1) else b.pw:SetStatusBarColor(0.2, 0.4, 1, 1) end
   local pw = UnitPower(unit)
   b.pw:SetMinMaxValues(0, UnitPowerMax(unit) or 1)
   b.pw:SetValue(pw or 0)
   local state = ""
   if unit ~= "player" and not Plain(UnitIsConnected(unit)) then state = "Offline"
   elseif Plain(UnitIsGhost(unit)) then state = "Ghost"
   elseif Plain(UnitIsDead(unit)) then state = "Dead" end
   b.state:SetText(state)
   if state == "" then
      pcall(b.hpText.SetText, b.hpText, hp)
      pcall(b.pwText.SetText, b.pwText, pw)
   else
      b.hpText:SetText(""); b.pwText:SetText("")
   end
   local inRange = true
   if unit ~= "player" and UnitInRange then
      local r, checked = UnitInRange(unit)
      if Plain(checked) then inRange = Plain(r) end
   end
   b:SetAlpha((state ~= "" or not inRange) and 0.45 or 1)
   -- (selected: the one the D-pad is on, or your target: the ring and name gold)
   local nav = addon.GroupNavigator and addon.GroupNavigator:GetAttribute("unit")
   local selected = Plain(UnitIsUnit(unit, "target")) or (type(nav) == "string" and Plain(UnitIsUnit(unit, nav)))
   if selected then
      b.ring:SetVertexColor(1, 0.82, 0.3, 1)
      b.name:SetTextColor(1, 0.82, 0.3)
   else
      b.ring:SetVertexColor(BRASS_LIGHT[1], BRASS_LIGHT[2], BRASS_LIGHT[3], 1)
      b.name:SetTextColor(1, 1, 1)
   end
   b.glow:SetShown(selected)
   b.bracket:SetShown(selected)
   local threat = UnitThreatSituation and UnitThreatSituation(unit)
   b.aggro:SetShown(not Secret(threat) and type(threat) == "number" and threat >= 2)
   pcall(Buffs, b, unit)
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
   if addon.GroupNavigator and addon.GroupNavigator.AddUnitFrameRefs and not InCombatLockdown() then
      addon.GroupNavigator:AddUnitFrameRefs()
   end
   -- (CrossHotbar's navigation box is replaced by the rows' own highlight; a
   -- frame of CrossHotbar's, so its alpha is ours to set; raids keep it)
   local box = addon.GroupNavigator and addon.GroupNavigator.SoftTargetFrame
   if box then box:SetAlpha((s.party and inGroup) and 0 or 1) end
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

-- /xhb party probe: what's still drawn round the party (for the debug log)
local function Probe()
   local log = addon.ForeverLog and function(m) addon:ForeverLog("party probe: " .. m) end or print
   local n = 0
   local function look(f)
      local name = f.GetName and f:GetName()
      if type(name) ~= "string" or Secret(name) then return end
      if not (name:find("Party") or name:find("Select") or name:find("Highlight") or name:find("SoftTarget")) then return end
      if not (f.IsVisible and f:IsVisible()) then return end
      local alpha = f.GetEffectiveAlpha and f:GetEffectiveAlpha() or 1
      if Secret(alpha) or alpha <= 0.05 then return end
      local parent = f:GetParent()
      local pname = parent and parent.GetName and parent:GetName()
      log(("%s alpha=%.2f strata=%s parent=%s"):format(name, alpha, tostring(f:GetFrameStrata()),
         (type(pname) == "string" and not Secret(pname)) and pname or "?"))
      n = n + 1
   end
   local f = EnumerateFrames()
   while f and n < 60 do
      pcall(look, f)
      f = EnumerateFrames(f)
   end
   log("done (" .. n .. ")")
   print("|cff66ccffCrossHotbar|r: party probe saved: /reload, then tell Claude.")
end

function addon:PartyCommand(value)
   local s = Settings()
   if not s then return end
   if value == "probe" then return Probe() end
   if value == "lock" then
      s.partyLocked = not s.partyLocked
      print("|cff66ccffCrossHotbar|r: party list " .. (s.partyLocked and "locked." or "unlocked: drag it where you want it."))
   else
      s.party = not s.party
      print("|cff66ccffCrossHotbar|r: party list " .. (s.party and "on (the game's party frames hidden)." or "off (the game's party frames back)."))
   end
   Apply()
end
