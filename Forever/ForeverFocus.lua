-- WoW Forever: share the gamepad with the game's own Gamepad UI.
--
-- Forever's Gamepad UI drives its menus, radials and windows through a stack of
-- binding sets (GamepadSharedUtility.InputBindingManager). CrossHotbar binds the
-- face buttons, D-pad, sticks and shoulders with priority override bindings, so
-- while those are on, the game's navigation never sees a press: menus can't be
-- moved through, and the Menu button never opens the radial.
--
-- Two things fix that:
--   1. Keys the Gamepad UI needs in the world are never bound by CrossHotbar
--      (RESERVED: Menu opens the game's radial / menus). ConfigActions iterates
--      addon:ForeverPadActions(config.PadActions) instead of the full table.
--   2. While anything but the core binding set is active (a menu, radial or
--      window has the pad), every CrossHotbar binding is released; when the
--      pad comes back to the world, they're applied again.
-- Bindings can't change in combat: PLAYER_REGEN_DISABLED (fired just before
-- the lockdown) takes them back, so the crossbar works through any fight.
-- The focus is read every 0.1 s, never by a callback of ours in the game's
-- lists (that would taint its secure work; same approach as ImprovedForever).
local ADDON, addon = ...

local GamepadMode = _G.GamepadMode
if not GamepadMode then return end   -- (no Gamepad UI on this client: nothing to share)

-- Keys left to the game while its Gamepad UI is on
local RESERVED = {
   PADFORWARD = true,   -- Menu: the game's radial / menus (and Improved Forever's double press)
}

function addon:ForeverPadActions(padactions)
   local filtered = {}
   for button, attributes in pairs(padactions) do
      if not RESERVED[attributes.BIND] then filtered[button] = attributes end
   end
   return filtered
end

-- A small log of what this file did, for debugging from outside the game:
-- CrossHotbar_DB.ForeverLog (written on /reload or logout), newest last
local LOG_MAX = 200
function addon:ForeverLog(msg)
   if type(CrossHotbar_DB) ~= "table" then return end
   local log = CrossHotbar_DB.ForeverLog
   if type(log) ~= "table" then log = {}; CrossHotbar_DB.ForeverLog = log end
   log[#log + 1] = date("%H:%M:%S") .. string.format(".%03d ", (GetTime() * 1000) % 1000) .. msg
   while #log > LOG_MAX do table.remove(log, 1) end
end

-- The game's bind mode (Spellbook / bags -> Bind): its own overlay, opened
-- with only the core binding set active, so it's checked by what's shown.
-- (GamepadMainActionBarFrame is parked hidden by CrossHotbar; visible means
-- the game brought it back for binding.)
local STUCK = 20          -- (the main bar up this long with no edit frame: the game left it, hide it again)
local barSince = nil
local function BindModeOpen()
   local edit = _G.GamepadActionBarEditFrame
   if edit and edit:IsVisible() then barSince = nil; return true, "edit frame" end
   local bar = _G.GamepadMainActionBarFrame
   if bar and bar:IsVisible() then
      barSince = barSince or GetTime()
      if GetTime() - barSince > STUCK and not InCombatLockdown() and addon.Crosshotbar
         and addon.Crosshotbar.HideGamepadBar then
         addon:ForeverLog("main bar left visible " .. STUCK .. "s: hiding it again")
         addon.Crosshotbar:HideGamepadBar(bar)
         barSince = nil
         return false
      end
      return true, "main bar"
   end
   barSince = nil
   return false
end

-- The game's focus: true while only its core bindings are active (the world)
-- and its bind mode isn't open
local function InWorld()
   local binding, why = BindModeOpen()
   if binding then return false, "bind mode (" .. why .. ")" end
   local manager = _G.GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
   if not (manager and manager.IsOnlyCoreBindingSetActive) then return true, "no binding manager" end
   if manager:IsOnlyCoreBindingSetActive() then return true, "world" end
   return false, "game window / menu"
end

-- CrossHotbar's own bars out of sight while the game binds (its bar is the
-- target then); our frame, so its alpha is ours to set
local function ShowBars(shown)
   local root = _G.Crosshotbar
   if root then root:SetAlpha(shown and 1 or 0) end
end

local HOTBARS = {
   "WXHBLHotbar1", "WXHBLHotbar2", "WXHBLHotbar3",
   "WXHBRHotbar1", "WXHBRHotbar2", "WXHBRHotbar3",
   "WXHBLRHotbar1", "WXHBRLHotbar1",
}

local released = false

local function Release(why)
   local pad = addon.GamePad
   if not pad or InCombatLockdown() then return end
   addon:ForeverLog("release: " .. tostring(why))
   ShowBars(not (why and why:find("^bind mode")))
   pad:SetAttribute("state-expanded", 0)
   pad:SetAttribute("state-trigger", 4)   -- (4: no trigger held; hotbars drop their keys)
   pad:ClearActions()
   if addon.GroupNavigator then ClearOverrideBindings(addon.GroupNavigator) end
   for _, name in ipairs(HOTBARS) do
      local bar = _G[name]
      if bar and bar.Buttons then
         for _, b in pairs(bar.Buttons) do ClearOverrideBindings(b) end
      end
   end
   released = true
end

local function Take(why)
   local pad = addon.GamePad
   if not pad or InCombatLockdown() then return end
   addon:ForeverLog("take: " .. tostring(why))
   ShowBars(true)
   released = false
   pad:ConfigActions()   -- (rebinds everything, the GroupNavigator through the trigger state)
end

function addon:ForeverFocusReleased()
   return released
end

local watch = CreateFrame("Frame")
local since = 0
watch:SetScript("OnUpdate", function(_, elapsed)
   since = since + elapsed
   if since < 0.1 then return end
   since = 0
   if not addon.GamePad or InCombatLockdown() then return end
   local world, why = InWorld()
   if world and released then
      Take(why)
   elseif not world and not released then
      Release(why)
   end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function()
   -- (a fight: the crossbar on, whatever has the focus; it can't change until it's over)
   ShowBars(true)
   if released then
      released = false
      addon:ForeverLog("take: combat")
      local pad = addon.GamePad
      if pad then pad:ConfigActions() end
   end
end)

-- CrossHotbar re-applies its config on its own (after each fight, on a
-- settings change): if a game window has the pad then, release again
local function HookPad()
   local pad = addon.GamePad
   if not pad or pad.__foreverHooked then return end
   pad.__foreverHooked = true
   hooksecurefunc(pad, "ConfigActions", function()
      released = false   -- (now bound; the next tick releases again if a window has the pad)
   end)
end
addon:AddInitCallback(HookPad)
