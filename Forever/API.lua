-- A small API for other addons (Forever builds of this fork).
--
--   CrossHotbar_GetPadAction(button)          -> the action on a pad button
--   CrossHotbar_SetPadAction(button, action)  -> true if set (out of combat)
-- button: a PadActions key ("FACEL", "FACED", "DPADU", "OPTIO"...); action:
-- one of CrossHotbar's actions, or "CLICK <frame>:<button>" to press another
-- addon's button (e.g. Improved Forever's peek map:
-- "CLICK ImprovedForeverPeekMapHold:LeftButton"). Saved with the rest of
-- the config at logout (addon:StoreConfig copies addon.Config).
local ADDON, addon = ...

function addon:IsClickAction(action)
   return type(action) == "string" and action:find("^CLICK [%w_]+:%w+$") ~= nil
end

function CrossHotbar_GetPadAction(button)
   local pad = addon.Config and addon.Config.PadActions and addon.Config.PadActions[button]
   return pad and pad.ACTION or nil
end

function CrossHotbar_SetPadAction(button, action)
   if InCombatLockdown() then return false end
   local pad = addon.Config and addon.Config.PadActions and addon.Config.PadActions[button]
   if not pad or type(action) ~= "string" then return false end
   pad.ACTION = action
   local gamepad = addon.GamePad
   if gamepad then
      gamepad:ClearActions()
      gamepad:ConfigActions()
   end
   if addon.ForeverLog then addon:ForeverLog("pad action " .. button .. " = " .. action) end
   return true
end
