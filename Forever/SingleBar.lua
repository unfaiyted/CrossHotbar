-- Single-bar mode: one side's crossbar at a time, the way you're using it.
--
--   L2 held (or its expanded bar)  -> the L2 bar at full, R2's hidden
--   R2 held (or its expanded bar)  -> the R2 bar at full, L2's hidden
--   L2 > R2 / R2 > L2 (WXHB)       -> both side bars hidden: the WXHB bar alone
--   nothing held                   -> the last side used stays, faded (R2 to begin)
--
-- Done with the bars' alpha (their frames, which CrossHotbar never fades
-- itself: it fades the buttons inside), so it works in combat too; the
-- trigger state is read from the GamePad frame's attributes every frame.
-- Settings in CrossHotbar_DB.Forever: singleBar (on by default), idleAlpha.
-- /xhb single  turns it on / off;  /xhb fade <0-1>  the idle bar's alpha.
local ADDON, addon = ...

local L_BARS = { "WXHBLHotbar1", "WXHBLHotbar2", "WXHBLHotbar3" }
local R_BARS = { "WXHBRHotbar1", "WXHBRHotbar2", "WXHBRHotbar3" }
local SPEED = 8          -- (alpha per second, fading in and out)

function addon:ForeverSettings()
   if type(CrossHotbar_DB) ~= "table" then return nil end
   CrossHotbar_DB.Forever = CrossHotbar_DB.Forever or {}
   local s = CrossHotbar_DB.Forever
   if s.singleBar == nil then s.singleBar = true end
   if s.idleAlpha == nil then s.idleAlpha = 0.35 end
   return s
end

local last = "R"
local current = { L = 1, R = 1 }

local function Apply(names, alpha)
   for _, name in ipairs(names) do
      local bar = _G[name]
      if bar then bar:SetAlpha(alpha) end
   end
end

local function Step(from, to, elapsed)
   if from < to then return math.min(to, from + SPEED * elapsed) end
   return math.max(to, from - SPEED * elapsed)
end

local watch = CreateFrame("Frame")
watch:SetScript("OnUpdate", function(_, elapsed)
   local s = addon:ForeverSettings()
   local pad = addon.GamePad
   if not (s and pad) then return end
   local wantL, wantR = 1, 1
   if s.singleBar then
      local trigger = tonumber(pad:GetAttribute("triggerstate")) or 4
      -- (CrossHotbar's trigger states: 4 none, 6 / 2 L2, 7 / 1 R2, 3 L2>R2, 5 R2>L2)
      -- (only a trigger held picks the side: CrossHotbar's expanded state
      -- stays latched after a double tap, so it isn't read; let go, the side
      -- used last stays, faded)
      if trigger == 3 or trigger == 5 then
         wantL, wantR = 0, 0
      elseif trigger == 6 or trigger == 2 then
         last, wantL, wantR = "L", 1, 0
      elseif trigger == 7 or trigger == 1 then
         last, wantL, wantR = "R", 0, 1
      elseif last == "L" then
         wantL, wantR = s.idleAlpha, 0
      else
         wantL, wantR = 0, s.idleAlpha
      end
   end
   local l, r = Step(current.L, wantL, elapsed), Step(current.R, wantR, elapsed)
   if l ~= current.L then current.L = l; Apply(L_BARS, l) end
   if r ~= current.R then current.R = r; Apply(R_BARS, r) end
end)

-- /xhb single, /xhb fade <n> (Editor.lua's slash command passes them here)
function addon:ForeverBarCommand(args)
   local s = addon:ForeverSettings()
   if not s then return false end
   local word, value = (args or ""):lower():match("^%s*(%S*)%s*(%S*)")
   if word == "single" then
      if value == "on" then s.singleBar = true elseif value == "off" then s.singleBar = false
      else s.singleBar = not s.singleBar end
      addon:ForeverLayout()
      print("|cff66ccffCrossHotbar|r: single-bar mode " .. (s.singleBar and "on" or "off") .. ".")
      return true
   elseif word == "enmity" then
      if addon.EnmityCommand then addon:EnmityCommand(value) end
      return true
   elseif word == "fade" then
      local n = tonumber(value)
      if n and n >= 0 and n <= 1 then s.idleAlpha = n end
      print("|cff66ccffCrossHotbar|r: the idle bar's alpha is " .. s.idleAlpha .. ".")
      return true
   end
   return false
end

function addon:ToggleSingleBar()
   local s = addon:ForeverSettings()
   if s then s.singleBar = not s.singleBar end
   addon:ForeverLayout()
   return s and s.singleBar
end

---------------------------------------------------------------------------
-- Centred: in single-bar mode both side bars sit in one spot, the middle of
-- the crossbar (only one shows at a time), the divider line goes, and the
-- set's name ("SET 1") sits where the line was. Frames move out of combat
-- only (secure frames can't be placed in one): on login, after CrossHotbar
-- lays its bars out, on toggling, and after a fight if one was in the way.
---------------------------------------------------------------------------
local pending = false

-- The middle of a bar's D-pad and face crosses (buttons 1-8), in its own frame's coordinates
local function GroupCenterX(bar)
   local left, right
   local barScale = bar:GetEffectiveScale()
   for i = 1, 8 do
      local b = bar.Buttons and bar.Buttons[i]
      if b and b:GetLeft() then
         -- (in the bar's own scale: CrossHotbar scales buttons)
         local k = b:GetEffectiveScale() / barScale
         local l, r = b:GetLeft() * k, b:GetRight() * k
         left = left and math.min(left, l) or l
         right = right and math.max(right, r) or r
      end
   end
   if not (left and bar:GetLeft()) then return nil end
   return (left + right) / 2 - bar:GetLeft()
end

local function Place(names, single)
   local root = addon.Crosshotbar
   for _, name in ipairs(names) do
      local bar = _G[name]
      if bar and root then
         local dx = 0
         if single then
            -- (the crosses' middle onto the crossbar's middle)
            local mid = GroupCenterX(bar)
            if mid then dx = bar:GetWidth() / 2 - mid end
         end
         bar:ClearAllPoints()
         bar:SetPoint("CENTER", root, "CENTER", dx, 0)
      end
   end
end

function addon:ForeverLayout()
   if InCombatLockdown() then pending = true return end
   pending = false
   local s = addon:ForeverSettings()
   if not s or not addon.Crosshotbar then return end
   local single = s.singleBar and true or false
   -- (a fresh start from CrossHotbar's own place, then centred)
   Place(L_BARS, false); Place(R_BARS, false)
   if single then Place(L_BARS, true); Place(R_BARS, true) end
   local line = _G.WXHBCrossHotbarMover_Texture
   if line then line:SetShown(not single) end
   local status = addon.Crosshotbar.PageStatusFrame
   if status then
      status:ClearAllPoints()
      if single then
         -- (centred, just under the bar's lowest button 1-8)
         local root = addon.Crosshotbar
         local _, rootY = root:GetCenter()
         local lowest
         for _, name in ipairs({ L_BARS[1], R_BARS[1] }) do
            local bar = _G[name]
            for i = 1, 8 do
               local b = bar and bar.Buttons and bar.Buttons[i]
               local bottom = b and b:GetBottom()
               if bottom then
                  bottom = bottom * b:GetEffectiveScale()
                  lowest = lowest and math.min(lowest, bottom) or bottom
               end
            end
         end
         local dy = 0
         if lowest and rootY then
            dy = (lowest - rootY * root:GetEffectiveScale()) / status:GetEffectiveScale() - 6
         end
         status:SetPoint("TOP", root, "CENTER", 0, dy)
      else
         status:SetPoint("TOP", addon.Crosshotbar, "BOTTOM", 0, 0)
      end
   end
end

local layoutEvents = CreateFrame("Frame")
layoutEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
layoutEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
layoutEvents:SetScript("OnEvent", function(_, event)
   if event == "PLAYER_REGEN_ENABLED" and not pending then return end
   -- (after CrossHotbar's own layout on entering the world)
   C_Timer.After(0.5, function() addon:ForeverLayout() end)
end)

addon:AddInitCallback(function()
   local root = addon.Crosshotbar
   if root and root.UpdateCrosshotbar then
      hooksecurefunc(root, "UpdateCrosshotbar", function() addon:ForeverLayout() end)
   end
end)
