-- Crossbar editor: put spells, items and macros on CrossHotbar's bars with
-- the gamepad (or the mouse / drag and drop).
--
--   Left: what can go on a bar (tabs: Spells, Items, Macros).
--   Right: the four crossbars of the current set (L2, R2, L2->R2, R2->L2),
--          12 slots each: D-pad (left, up, right, down), face buttons (left,
--          top, right, bottom), and the four expanded slots.
--
-- Pad: D-pad up/down picks in the list, LB/RB switch tabs, A takes it. Then
-- either hold L2 / R2 (L2 then R2, R2 then L2 for the WXHB bars) and press the
-- slot's button, the way FFXIV assigns, or move to a slot with the D-pad and
-- press A. X empties the slot under the cursor, B goes back / closes.
-- Mouse: click an entry, then a slot (right-click empties it); slots also
-- take anything dropped on them, and can be dragged out.
--
-- Writes with PickupSpell/PickupItem/PickupMacro + PlaceAction into the
-- action slot the CrossHotbar button shows right now (so the set and, for
-- the R2 bar, the stance page shown). Out of combat only.
--
-- Open with /xhb (or /crossbar), CrossHotbar_OpenEditor(), or Improved
-- Forever's binding "CrossHotbar editor".
local ADDON, addon = ...

local E = {}
addon.Editor = E

local ROWS = {
   { label = "L2",      hotbar = "WXHBLHotbar1" },
   { label = "R2",      hotbar = "WXHBRHotbar1" },
   { label = "L2 > R2", hotbar = "WXHBLRHotbar1" },
   { label = "R2 > L2", hotbar = "WXHBRLHotbar1" },
}
-- Columns, left to right: CrossHotbar button index shown there
-- (5-8 D-pad: right, up, down, left; 1-4 face: right, top, bottom, left; 9-12 expanded)
local COLUMNS = { 8, 6, 5, 7, 4, 2, 1, 3, 9, 10, 11, 12 }
local DEFAULT_KEYS = { "PAD2", "PAD4", "PAD1", "PAD3", "PADDRIGHT", "PADDUP", "PADDDOWN", "PADDLEFT" }
local TABS = { "Spells", "Items", "Macros" }
local VISIBLE = 13
local SLOT = 34

local win, list, grid, hint, tabText
local state = { tab = 1, sel = 1, top = 1, mode = "list", row = 1, col = 1, picked = nil, held = {} }
local entries = {}

local function Log(msg)
   if addon.ForeverLog then addon:ForeverLog("editor: " .. msg) end
end

local function Say(msg)
   print("|cff66ccffCrossHotbar|r: " .. msg)
end

---------------------------------------------------------------------------
-- What the face / D-pad buttons are for each hotbar button (CrossHotbar's
-- config: TRIGACTION HOTBARBTN<n> on a button)
---------------------------------------------------------------------------
local function SlotKeys()
   local keys = {}
   local pad = addon.Config and addon.Config.PadActions
   if pad then
      for _, attributes in pairs(pad) do
         local n = tonumber(tostring(attributes.TRIGACTION or ""):match("^HOTBARBTN(%d+)$"))
         if n and n <= 8 and attributes.BIND then keys[n] = attributes.BIND end
      end
   end
   for n = 1, 8 do keys[n] = keys[n] or DEFAULT_KEYS[n] end
   return keys
end

local function KeyLabel(key)
   local text = GetBindingText and GetBindingText(key, "KEY_ABBR") or key
   return (text and text ~= "") and text or key
end

-- The action slot a CrossHotbar button shows now
local function ActionSlot(row, index)
   local hotbar = _G[ROWS[row].hotbar]
   local button = hotbar and hotbar.Buttons and hotbar.Buttons[index]
   if not button then return nil end
   local action = button.action
   if not action and button.CalculateAction then action = button:CalculateAction() end
   return tonumber(action)
end

---------------------------------------------------------------------------
-- What can go on a bar
---------------------------------------------------------------------------
local function SpellEntries()
   local out, seen = {}, {}
   local function add(id, name, icon, group)
      if id and name and not seen[id] then
         seen[id] = true
         out[#out + 1] = { kind = "spell", id = id, name = name, icon = icon, group = group }
      end
   end
   if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
      local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
      local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
      for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
         local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
         if info and not info.shouldHide then
            for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
               local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
               if item and (spellType == nil or item.itemType == spellType) and not item.isPassive
                  and not item.isOffSpec then
                  add(item.spellID or item.actionID, item.name, item.iconID, info.name)
               end
            end
         end
      end
   elseif GetNumSpellTabs then
      for tab = 1, GetNumSpellTabs() do
         local group, _, offset, count = GetSpellTabInfo(tab)
         for i = offset + 1, offset + count do
            local kind, id = GetSpellBookItemInfo(i, "spell")
            if kind == "SPELL" and not IsPassiveSpell(i, "spell") then
               add(id, GetSpellBookItemName(i, "spell"), GetSpellBookItemTexture(i, "spell"), group)
            end
         end
      end
   end
   return out
end

local function ItemEntries()
   local out, seen = {}, {}
   local container = C_Container
   if not container then return out end
   for bag = 0, (NUM_BAG_SLOTS or 4) do
      for slot = 1, container.GetContainerNumSlots(bag) or 0 do
         local info = container.GetContainerItemInfo(bag, slot)
         local id = info and info.itemID
         if id and not seen[id] then
            local useSpell = (C_Item and C_Item.GetItemSpell and C_Item.GetItemSpell(id)) or (GetItemSpell and GetItemSpell(id))
            if useSpell then
               seen[id] = true
               local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id)) or ("item " .. id)
               out[#out + 1] = { kind = "item", id = id, name = name, icon = info.iconFileID, group = "Bags" }
            end
         end
      end
   end
   table.sort(out, function(a, b) return a.name < b.name end)
   return out
end

local function MacroEntries()
   local out = {}
   if not GetNumMacros then return out end
   local account, character = GetNumMacros()
   local perAccount = MAX_ACCOUNT_MACROS or 120
   local function add(index, group)
      local name, icon = GetMacroInfo(index)
      if name then out[#out + 1] = { kind = "macro", id = index, name = name, icon = icon, group = group } end
   end
   for i = 1, account or 0 do add(i, "General") end
   for i = 1, character or 0 do add(perAccount + i, "Character") end
   return out
end

local function Load()
   local ok, result = pcall(({ SpellEntries, ItemEntries, MacroEntries })[state.tab])
   if not ok then Log("list error: " .. tostring(result)); result = {} end
   entries = result
   if state.sel > #entries then state.sel = math.max(1, #entries) end
end

---------------------------------------------------------------------------
-- Writing a slot
---------------------------------------------------------------------------
local function Pickup(entry)
   if entry.kind == "spell" then
      local pickup = (C_Spell and C_Spell.PickupSpell) or PickupSpell
      pickup(entry.id)
   elseif entry.kind == "item" then
      local pickup = (C_Item and C_Item.PickupItem) or PickupItem
      pickup(entry.id)
   elseif entry.kind == "macro" then
      PickupMacro(entry.id)
   end
end

local Refresh

local function Place(entry, row, index)
   if InCombatLockdown() then Say("can't change bars in combat.") return end
   local slot = ActionSlot(row, index)
   if not (entry and slot) then return end
   ClearCursor()
   local ok, err = pcall(Pickup, entry)
   if ok and GetCursorInfo() then
      ok, err = pcall(PlaceAction, slot)
   end
   ClearCursor()
   Log(("place %s %s -> %s #%d (action %d)%s"):format(entry.kind, tostring(entry.id), ROWS[row].label, index, slot,
      ok and "" or (" FAILED " .. tostring(err))))
   if not ok then Say("couldn't place it: " .. tostring(err)) end
   PlaySound(SOUNDKIT and SOUNDKIT.IG_ABILITY_ICON_DROP or 838)
   Refresh()
end

local function Empty(row, index)
   if InCombatLockdown() then Say("can't change bars in combat.") return end
   local slot = ActionSlot(row, index)
   if not slot then return end
   ClearCursor()
   pcall(PickupAction, slot)
   ClearCursor()
   Log(("empty %s #%d (action %d)"):format(ROWS[row].label, index, slot))
   Refresh()
end

-- Something on the cursor (dragged from the spellbook, bags...) dropped on a slot
local function DropOn(row, index)
   if InCombatLockdown() then return end
   local slot = ActionSlot(row, index)
   if slot and GetCursorInfo() then
      pcall(PlaceAction, slot)
      Log(("drop -> %s #%d (action %d)"):format(ROWS[row].label, index, slot))
      Refresh()
   end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local rowsUI, slotsUI = {}, {}

local function SlotText(index, keys)
   if index > 8 then return "E" .. (index - 8) end
   return KeyLabel(keys[index])
end

Refresh = function()
   if not win or not win:IsShown() then return end
   tabText:SetText(("|cff999999LB|r   %s   |cff999999RB|r"):format(
      (TABS[state.tab]):upper() .. "  (" .. #entries .. ")"))
   -- list
   if state.sel < state.top then state.top = state.sel end
   if state.sel >= state.top + VISIBLE then state.top = state.sel - VISIBLE + 1 end
   for i = 1, VISIBLE do
      local ui, entry = rowsUI[i], entries[state.top + i - 1]
      if entry then
         ui.icon:SetTexture(entry.icon)
         ui.text:SetText(entry.name)
         ui.sub:SetText(entry.group or "")
         ui:Show()
         local lit = state.top + i - 1 == state.sel
         ui.light:SetShown(lit and state.mode == "list")
         ui.picked:SetShown(state.picked == entry)
      else
         ui:Hide()
      end
   end
   -- grid
   local keys = SlotKeys()
   for r = 1, #ROWS do
      for c, index in ipairs(COLUMNS) do
         local ui = slotsUI[r][c]
         local slot = ActionSlot(r, index)
         local texture = slot and GetActionTexture(slot)
         ui.icon:SetTexture(texture or nil)
         ui.icon:SetShown(texture ~= nil)
         ui.key:SetText(SlotText(index, keys))
         ui.light:SetShown(state.mode == "slot" and state.row == r and state.col == c)
      end
   end
   -- hint
   if state.mode == "list" then
      hint:SetText("D-pad: choose    LB / RB: tab    A: pick    B: close"
         .. "    |cff999999(mouse: click an entry, or drag anything onto a slot)|r")
   else
      hint:SetText(("|cffffd100%s|r  ->  hold L2 / R2 (+ the other for WXHB) and press its button,"
         .. " or D-pad to a slot and A.    X: empty slot    B: back"):format(state.picked and state.picked.name or "?"))
   end
end

local function Close()
   if win then win:Hide() end
end

local function Pick()
   local entry = entries[state.sel]
   if not entry then return end
   state.picked = entry
   state.mode = "slot"
   PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION or 857)
   Refresh()
end

-- Held triggers, in the order pressed: L, R, LR (L first) or RL (R first)
local function TriggerRow()
   local h = state.held
   if h.L and h.R then return (h.L < h.R) and 3 or 4 end
   if h.L then return 1 end
   if h.R then return 2 end
end

local function OnPad(_, key)
   if key == "PADLTRIGGER" then state.held.L = GetTime() return end
   if key == "PADRTRIGGER" then state.held.R = GetTime() return end
   local triggerRow = TriggerRow()
   if state.mode == "slot" and triggerRow then
      -- FFXIV-style: the trigger(s) held + the slot's button
      local keys = SlotKeys()
      for index = 1, 8 do
         if keys[index] == key then
            for c, i in ipairs(COLUMNS) do if i == index then state.row, state.col = triggerRow, c end end
            Place(state.picked, triggerRow, index)
            return
         end
      end
      return
   end
   if key == "PAD2" then   -- B
      if state.mode == "slot" then state.mode = "list"; state.picked = nil; Refresh() else Close() end
   elseif state.mode == "list" then
      if key == "PADDDOWN" then state.sel = math.min(#entries, state.sel + 1)
      elseif key == "PADDUP" then state.sel = math.max(1, state.sel - 1)
      elseif key == "PADDRIGHT" then state.sel = math.min(#entries, state.sel + VISIBLE)
      elseif key == "PADDLEFT" then state.sel = math.max(1, state.sel - VISIBLE)
      elseif key == "PADLSHOULDER" or key == "PADRSHOULDER" then
         state.tab = (state.tab - 1 + (key == "PADRSHOULDER" and 1 or -1)) % #TABS + 1
         state.sel, state.top = 1, 1
         Load()
      elseif key == "PAD1" then Pick() return
      end
      Refresh()
   else
      if key == "PADDDOWN" then state.row = math.min(#ROWS, state.row + 1)
      elseif key == "PADDUP" then state.row = math.max(1, state.row - 1)
      elseif key == "PADDRIGHT" then state.col = math.min(#COLUMNS, state.col + 1)
      elseif key == "PADDLEFT" then state.col = math.max(1, state.col - 1)
      elseif key == "PAD1" then Place(state.picked, state.row, COLUMNS[state.col]) return
      elseif key == "PAD3" then Empty(state.row, COLUMNS[state.col]) return
      end
      Refresh()
   end
end

local function OnPadUp(_, key)
   if key == "PADLTRIGGER" then state.held.L = nil end
   if key == "PADRTRIGGER" then state.held.R = nil end
end

local function Build()
   win = CreateFrame("Frame", "CrossHotbarEditorFrame", UIParent, "BackdropTemplate")
   win:SetSize(300 + 24 + 80 + 12 * (SLOT + 4) + 24 + 30, 470)
   win:SetPoint("CENTER", 0, 40)
   win:SetFrameStrata("DIALOG")
   win:SetToplevel(true)
   win:EnableMouse(true)
   win:SetMovable(true)
   win:RegisterForDrag("LeftButton")
   win:SetScript("OnDragStart", win.StartMoving)
   win:SetScript("OnDragStop", win.StopMovingOrSizing)
   if win.SetBackdrop then
      win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      win:SetBackdropColor(0.04, 0.05, 0.08, 0.94)
      win:SetBackdropBorderColor(0.5, 0.5, 0.6, 1)
   end
   tinsert(UISpecialFrames, win:GetName())   -- (Esc closes it)

   local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
   title:SetPoint("TOPLEFT", 16, -12)
   title:SetText("Crossbar editor")
   local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
   close:SetPoint("TOPRIGHT", -2, -2)

   tabText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   tabText:SetPoint("TOPLEFT", 16, -42)

   -- list
   list = CreateFrame("Frame", nil, win)
   list:SetPoint("TOPLEFT", 12, -62)
   list:SetSize(300, VISIBLE * 26)
   list:EnableMouseWheel(true)
   list:SetScript("OnMouseWheel", function(_, delta)
      state.sel = math.max(1, math.min(#entries, state.sel - delta * 3)); Refresh()
   end)
   for i = 1, VISIBLE do
      local ui = CreateFrame("Button", nil, list)
      ui:SetSize(300, 24)
      ui:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
      ui.icon = ui:CreateTexture(nil, "ARTWORK"); ui.icon:SetSize(22, 22); ui.icon:SetPoint("LEFT", 2, 0)
      ui.text = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); ui.text:SetPoint("LEFT", ui.icon, "RIGHT", 6, 0)
      ui.text:SetWidth(170); ui.text:SetJustifyH("LEFT"); ui.text:SetWordWrap(false)
      ui.sub = ui:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); ui.sub:SetPoint("RIGHT", -4, 0)
      ui.light = ui:CreateTexture(nil, "BACKGROUND"); ui.light:SetAllPoints(); ui.light:SetColorTexture(1, 0.82, 0, 0.18)
      ui.picked = ui:CreateTexture(nil, "BORDER"); ui.picked:SetAllPoints(); ui.picked:SetColorTexture(0.2, 0.8, 1, 0.25)
      local hl = ui:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
      ui:SetScript("OnClick", function()
         state.sel = state.top + i - 1; state.mode = "list"; Pick()
      end)
      ui:RegisterForDrag("LeftButton")
      ui:SetScript("OnDragStart", function()
         local entry = entries[state.top + i - 1]
         if entry and not InCombatLockdown() then pcall(Pickup, entry) end
      end)
      rowsUI[i] = ui
   end

   -- grid
   grid = CreateFrame("Frame", nil, win)
   grid:SetPoint("TOPLEFT", list, "TOPRIGHT", 24, 0)
   grid:SetSize(80 + 12 * (SLOT + 4) + 20, #ROWS * (SLOT + 40))
   local groups = { "D-pad", "Face buttons", "Expanded" }
   for g, label in ipairs(groups) do
      local fs = grid:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      fs:SetPoint("TOPLEFT", 80 + (g - 1) * 4 * (SLOT + 4) + (g - 1) * 8, 0)
      fs:SetText(label)
   end
   for r, row in ipairs(ROWS) do
      local y = -16 - (r - 1) * (SLOT + 40)
      local name = grid:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      name:SetPoint("TOPLEFT", 0, y - SLOT / 2 + 6)
      name:SetText(row.label)
      slotsUI[r] = {}
      for c, index in ipairs(COLUMNS) do
         local ui = CreateFrame("Button", nil, grid)
         ui:SetSize(SLOT, SLOT)
         ui:SetPoint("TOPLEFT", 80 + (c - 1) * (SLOT + 4) + math.floor((c - 1) / 4) * 8, y)
         local bg = ui:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.07)
         ui.icon = ui:CreateTexture(nil, "ARTWORK"); ui.icon:SetPoint("TOPLEFT", 2, -2); ui.icon:SetPoint("BOTTOMRIGHT", -2, 2)
         ui.key = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ui.key:SetPoint("TOP", ui, "BOTTOM", 0, -2)
         ui.light = ui:CreateTexture(nil, "OVERLAY"); ui.light:SetPoint("TOPLEFT", -3, 3); ui.light:SetPoint("BOTTOMRIGHT", 3, -3)
         ui.light:SetColorTexture(1, 0.82, 0, 0.45)
         local hl = ui:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.2)
         ui:RegisterForClicks("LeftButtonUp", "RightButtonUp")
         ui:RegisterForDrag("LeftButton")
         ui:SetScript("OnClick", function(_, button)
            state.row, state.col = r, c
            if button == "RightButton" then Empty(r, index)
            elseif GetCursorInfo() then DropOn(r, index)
            elseif state.picked then Place(state.picked, r, index) end
         end)
         ui:SetScript("OnReceiveDrag", function() DropOn(r, index) end)
         ui:SetScript("OnDragStart", function()
            local slot = ActionSlot(r, index)
            if slot and not InCombatLockdown() then PickupAction(slot); Refresh() end
         end)
         ui:SetScript("OnEnter", function(self)
            local slot = ActionSlot(r, index)
            if slot and HasAction(slot) then
               GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetAction(slot); GameTooltip:Show()
            end
         end)
         ui:SetScript("OnLeave", function() GameTooltip:Hide() end)
         slotsUI[r][c] = ui
      end
   end

   hint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   hint:SetPoint("BOTTOMLEFT", 16, 14)
   hint:SetPoint("BOTTOMRIGHT", -16, 14)
   hint:SetJustifyH("LEFT")

   -- the pad, ours while shown
   win:SetScript("OnGamePadButtonDown", OnPad)
   win:SetScript("OnGamePadButtonUp", OnPadUp)
   win:EnableGamePadButton(false)
   win:SetScript("OnShow", function(self)
      self:EnableGamePadButton(true)
      state.held = {}
      Load(); Refresh()
   end)
   win:SetScript("OnHide", function(self)
      self:EnableGamePadButton(false)
      state.mode, state.picked = "list", nil
      ClearCursor()
   end)
   win:RegisterEvent("PLAYER_REGEN_DISABLED")
   win:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
   win:RegisterEvent("BAG_UPDATE_DELAYED")
   win:SetScript("OnEvent", function(self, event)
      if event == "PLAYER_REGEN_DISABLED" then self:Hide()
      elseif event == "BAG_UPDATE_DELAYED" and state.tab == 2 then Load(); Refresh()
      else Refresh() end
   end)
   win:Hide()
end

function E.IsOpen()
   return win ~= nil and win:IsShown()
end

function E.Toggle()
   if InCombatLockdown() then Say("the crossbar editor opens out of combat.") return end
   if not win then Build() end
   win:SetShown(not win:IsShown())
end

function CrossHotbar_OpenEditor()
   E.Toggle()
end

SLASH_CROSSHOTBAREDITOR1 = "/xhb"
SLASH_CROSSHOTBAREDITOR2 = "/crossbar"
SlashCmdList.CROSSHOTBAREDITOR = function() E.Toggle() end

---------------------------------------------------------------------------
-- The game's own Bind mode (Spellbook / bags -> Bind, then a press): it
-- writes the Gamepad UI's crossbar slots (GamepadActionBarBindingUtil). The
-- same action is put on CrossHotbar's matching slot too: its left bar ->
-- L2, right -> R2, both triggers -> L2 > R2. (Only if the game routes it
-- through that Lua table; logged either way.)
---------------------------------------------------------------------------
local Util = _G.GamepadActionBarBindingUtil
local UNIT_TO_INDEX = { 8, 6, 5, 7, 4, 2, 1, 3 }   -- (game slot within a bar -> CrossHotbar button)
local BAR_TO_ROW = { [1] = 1, [2] = 2, [3] = 3 }
local reverse

local function Reverse()
   if reverse then return reverse end
   reverse = {}
   if Util and Util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID then
      for page = 1, 3 do
         for unit = 1, 32 do
            local ok, slot = pcall(Util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID, page, unit)
            if ok and slot then reverse[slot] = unit end
         end
      end
   end
   return reverse
end

local function Mirror(storage)
   if InCombatLockdown() then return end
   local unit = Reverse()[storage]
   local kind, id = GetActionInfo(storage)
   if not (unit and kind and id) then Log("bind mode: storage " .. tostring(storage) .. " unmapped / empty") return end
   local bar, n = math.floor((unit - 1) / 8), (unit - 1) % 8 + 1
   local row = BAR_TO_ROW[bar]
   if not row then Log("bind mode: unit " .. unit .. " is on the top bar, not mirrored") return end
   local entry
   if kind == "spell" then entry = { kind = "spell", id = id }
   elseif kind == "item" then entry = { kind = "item", id = id }
   elseif kind == "macro" then entry = { kind = "macro", id = id } end
   if entry then
      Place(entry, row, UNIT_TO_INDEX[n])
      Say(("bound to %s %s."):format(ROWS[row].label, SlotText(UNIT_TO_INDEX[n], SlotKeys())))
   end
end

if Util and Util.AssignActionToGamepadStandardSlot then
   hooksecurefunc(Util, "AssignActionToGamepadStandardSlot", function(storage)
      Log("bind mode assigned game slot " .. tostring(storage))
      C_Timer.After(0, function() Mirror(storage) end)
   end)
end
