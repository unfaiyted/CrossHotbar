-- WoW Forever: CrossHotbar's bars on the game's own crossbar slots.
--
-- Forever's Gamepad UI keeps its crossbar in action slots of its own (page 1:
-- 181-208, page 2: 209-236, page 3: 237-264; GamepadActionBarBindingUtil maps
-- page + page unit slot to them). The game's Spellbook "Bind" mode and
-- Improved Forever's Bindings tab write there. Pointing CrossHotbar's buttons
-- at those slots makes both fill CrossHotbar, with the pad, no drag and drop,
-- and shows whatever was already set up on the game's crossbar.
--
--   CrossHotbar bar              game crossbar bar (page unit slots)
--   hold L2   (L hotbars 1-3)    left    9-16
--   hold R2   (R hotbars 1-3)    right  17-24
--   L2 -> R2  (LR hotbar)        bottom 25-32  (the game's "both triggers")
--   R2 -> L2  (RL hotbar)        unchanged: CrossHotbar's own page
-- Only buttons 1-8 (the face buttons and D-pad) move; 9-12, the expanded /
-- paddle extras, keep CrossHotbar's pages. CrossHotbar's sets pick the game's
-- page: set 1 -> page 1, 2 -> 2, 3 -> 3, 4 -> 1...
--
-- How: a button with ID 0 runs its "action" attribute instead of
-- ID + (page - 1) * 12, so buttons 1-8 get ID 0 (their place in the bar is
-- kept in .chbIndex, Hotbar.lua), and each set change sets "action" from a
-- table stored as attributes ("nativeaction-<page>-<button>") by the secure
-- "apply-native" snippet, run from CrossHotbar's page handler. Out of combat
-- set up; the snippet itself is secure, so set changes work in combat.
local ADDON, addon = ...

local Util = _G.GamepadActionBarBindingUtil
if not (Util and Util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID) then return end

local PAGES = 3
-- CrossHotbar button (1-4 face: right, top, bottom, left; 5-8 D-pad: right,
-- up, down, left) -> the game's slot within a bar (1-4 D-pad: left, up,
-- right, down; 5-8 face: left, top, right, bottom)
local UNIT_OF_BUTTON = { 7, 6, 8, 5, 3, 2, 4, 1 }
-- Hotbar -> the game's bar (1 left, 2 right, 3 bottom)
local NATIVE_BAR = {
   WXHBLHotbar1 = 1, WXHBLHotbar2 = 1, WXHBLHotbar3 = 1,
   WXHBRHotbar1 = 2, WXHBRHotbar2 = 2, WXHBRHotbar3 = 2,
   WXHBLRHotbar1 = 3,
}

local function Storage(page, unit)
   local ok, slot = pcall(Util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID, page, unit)
   return ok and slot or nil
end

local setUp = false

local function SetUp()
   if setUp or InCombatLockdown() then return end
   local crossbar = addon.Crosshotbar
   if not crossbar then return end
   for name, bar in pairs(NATIVE_BAR) do
      local hotbar = _G[name]
      if hotbar and hotbar.Buttons then
         hotbar:SetAttribute("nativebar", bar)
         for b = 1, 8 do
            for page = 1, PAGES do
               hotbar:SetAttribute("nativeaction-" .. page .. "-" .. b, Storage(page, bar * 8 + UNIT_OF_BUTTON[b]))
            end
            local button = hotbar.Buttons[b]
            if button then button:SetID(0) end
         end
      end
   end
   crossbar:SetAttribute("nativepages", PAGES)
   crossbar:SetAttribute("apply-native", [[
      local set = tonumber(...) or 1
      local pages = self:GetAttribute("nativepages") or 3
      local page = ((set - 1) % pages) + 1
      for i = 1, 8 do
         local hotbar = self:GetFrameRef('Hotbar'..i)
         if hotbar and hotbar:GetAttribute("nativebar") then
            for b = 1, 8 do
               local button = hotbar:GetFrameRef('ActionButton'..b)
               local action = hotbar:GetAttribute("nativeaction-" .. page .. "-" .. b)
               if button and action then button:SetAttribute("action", action) end
            end
         end
      end
   ]])
   setUp = true
   crossbar:Execute([[ self:RunAttribute("apply-native", self:GetAttribute("activeset") or 1) ]])
end

function addon:NativeSlotsActive()
   return setUp
end

addon:AddInitCallback(SetUp)

-- (CrossHotbar applies its config again on entering the world: make sure the
-- slots are set, after it)
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
   C_Timer.After(0, function()
      if InCombatLockdown() then return end
      SetUp()
      local crossbar = addon.Crosshotbar
      if setUp and crossbar then
         crossbar:Execute([[ self:RunAttribute("apply-native", self:GetAttribute("activeset") or 1) ]])
      end
   end)
end)
