-- Crossbar editor: put spells, items and macros on CrossHotbar's bars with
-- the gamepad (or the mouse / drag and drop).
--
--   Left: what can go on a bar (Spells, Items, Macros), with a tooltip of the
--         one highlighted.
--   Right: the four crossbars of a set, drawn as FFXIV crosses: L2 and R2 on
--          top, L2 > R2 and R2 > L2 (WXHB) below; each a D-pad cross, a face
--          button cross and a small cross of the four expanded slots.
--
-- Pad (the legend at the bottom shows it):
--   list:  left stick / D-pad up-down choose, D-pad left-right category,
--          A take it, B close
--   slot:  hold L2 / R2 (+ the other for WXHB) and press the slot's button,
--          FFXIV style; or move with the D-pad / left stick and A; X empties
--          the slot, B back
--   both:  LB / RB change the set being edited (1-6; "in use" marks the one
--          the crossbar shows in game: R1 + D-pad up / down there)
-- Mouse: click an entry, then a slot (right-click empties); slots take
-- anything dropped on them and can be dragged out.
--
-- A set's pages are worked out the way CrossHotbar's page handler does
-- (CrossHotbar.lua _onstate-page), so every set can be edited, not only the
-- one shown. Writes with Pickup* + PlaceAction. Out of combat only.
--
-- Open: /xhb, /crossbar, CrossHotbar_OpenEditor(), or Improved Forever's
-- binding "CrossHotbar editor".
local ADDON, addon = ...

local E = {}
addon.Editor = E

local ROWS = {
   { label = "L2",      hotbar = "WXHBLHotbar1",  left = true },
   { label = "R2",      hotbar = "WXHBRHotbar1" },
   { label = "L2 > R2", hotbar = "WXHBLRHotbar1", own = true },
   { label = "R2 > L2", hotbar = "WXHBRLHotbar1", own = true },
}
local SETS = 6
-- The crosses: CrossHotbar button index at up, left, right, down
-- (1-4 face: right, top, bottom, left; 5-8 D-pad: right, up, down, left;
--  9-12 expanded: D-pad right, up, down, left with the paddle / double tap)
local CROSSES = {
   { name = "D-pad", up = 6, left = 8, right = 5, down = 7 },
   { name = "Face",  up = 2, left = 4, right = 1, down = 3 },
   { name = "Expanded", up = 10, left = 12, right = 9, down = 11, small = true },
}
local DEFAULT_KEYS = { "PAD2", "PAD4", "PAD1", "PAD3", "PADDRIGHT", "PADDUP", "PADDDOWN", "PADDLEFT" }
local TABS = { "Spells", "Items", "Macros" }
local VISIBLE = 14
local ROW_H = 26
local S = 34          -- (slot size)
local SMALL = 26      -- (expanded slot size)

local win, tabText, setText, legend, carry
local rowsUI, slotsUI = {}, {}
local state = { tab = 1, sel = 1, top = 1, mode = "list", cursor = 1, picked = nil, held = {}, set = 1, stickY = 0, stickX = 0 }
local entries = {}

local function Log(msg)
   if addon.ForeverLog then addon:ForeverLog("editor: " .. msg) end
end

local function Say(msg)
   print("|cff66ccffCrossHotbar|r: " .. msg)
end

---------------------------------------------------------------------------
-- Buttons, labels
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

-- A pad button as the game draws it (Improved Forever's glyphs when loaded)
local function Glyph(key, size)
   local IF = _G.ImprovedForever
   if IF and IF.GlyphText then
      local ok, text = pcall(IF.GlyphText, key, size or 18)
      if ok and text and text ~= "" then return text end
   end
   local text = GetBindingText and GetBindingText(key, "KEY_ABBR")
   return (text and text ~= "") and text or key
end

---------------------------------------------------------------------------
-- Which action slot a bar's button uses in a set (as CrossHotbar's page
-- handler: set 1 uses each bar's own page (R2: by stance); sets 2-6 page
-- pairs 1/2, 3/4, 5/6, 7/8, 9/10; the WXHB bars always their own)
---------------------------------------------------------------------------
local function PageOf(set, row)
   local hotbar = _G[ROWS[row].hotbar]
   if not hotbar then return nil end
   local prefix, index = "", nil
   if set == 1 or ROWS[row].own then
      prefix = hotbar:GetAttribute("pageprefix") or ""
      index = hotbar:GetAttribute("pageindex")
   else
      local base = ({ [2] = 1, [3] = 3, [4] = 5, [5] = 7, [6] = 9 })[set] or 1
      index = ROWS[row].left and (base + 1) or base
   end
   if not index then return nil end
   local page = tonumber(SecureCmdOptionParse and SecureCmdOptionParse(prefix .. index) or index)
   if not page then   -- (possess / vehicle: what the bar shows now)
      page = tonumber(hotbar:GetAttribute("actionpage"))
   end
   return page
end

local function ActionSlot(set, row, index)
   local page = PageOf(set, row)
   return page and ((page - 1) * 12 + index) or nil
end

local function ActiveSet()
   local root = addon.Crosshotbar
   return root and tonumber(root:GetAttribute("activeset")) or 1
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
               local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id))
                  or (GetItemInfo and GetItemInfo(id)) or ("item " .. id)
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
   state.sel = math.max(1, math.min(state.sel, #entries))
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

local function Place(entry, set, row, index)
   if InCombatLockdown() then Say("can't change bars in combat.") return end
   local slot = ActionSlot(set, row, index)
   if not (entry and slot) then return end
   ClearCursor()
   local ok, err = pcall(Pickup, entry)
   if ok and GetCursorInfo() then ok, err = pcall(PlaceAction, slot) end
   ClearCursor()
   Log(("place %s %s -> set %d %s #%d (action %d)%s"):format(entry.kind, tostring(entry.id), set,
      ROWS[row].label, index, slot, ok and "" or (" FAILED " .. tostring(err))))
   if not ok then Say("couldn't place it: " .. tostring(err)) end
   PlaySound(SOUNDKIT and SOUNDKIT.IG_ABILITY_ICON_DROP or 838)
   Refresh()
end

local function Empty(set, row, index)
   if InCombatLockdown() then Say("can't change bars in combat.") return end
   local slot = ActionSlot(set, row, index)
   if not slot then return end
   ClearCursor()
   pcall(PickupAction, slot)
   ClearCursor()
   Log(("empty set %d %s #%d (action %d)"):format(set, ROWS[row].label, index, slot))
   Refresh()
end

local function DropOn(set, row, index)
   if InCombatLockdown() then return end
   local slot = ActionSlot(set, row, index)
   if slot and GetCursorInfo() then
      pcall(PlaceAction, slot)
      Log(("drop -> set %d %s #%d (action %d)"):format(set, ROWS[row].label, index, slot))
      Refresh()
   end
end

---------------------------------------------------------------------------
-- Tooltip: what the highlighted entry / slot does
---------------------------------------------------------------------------
local function ShowTip()
   if not (win and win:IsShown()) then return end
   GameTooltip:SetOwner(win, "ANCHOR_NONE")
   GameTooltip:ClearAllPoints()
   GameTooltip:SetPoint("TOPLEFT", win, "TOPRIGHT", 6, 0)
   local shown = false
   if state.mode == "list" then
      local e = entries[state.sel]
      if e and e.kind == "spell" then GameTooltip:SetSpellByID(e.id); shown = true
      elseif e and e.kind == "item" then GameTooltip:SetItemByID(e.id); shown = true
      elseif e and e.kind == "macro" then
         local name, _, body = GetMacroInfo(e.id)
         GameTooltip:SetText(name or "Macro", 1, 1, 1)
         if body then GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true) end
         shown = true
      end
   else
      local s = slotsUI[state.cursor]
      local slot = s and ActionSlot(state.set, s.row, s.index)
      if slot and HasAction(slot) then GameTooltip:SetAction(slot); shown = true end
   end
   if shown then GameTooltip:Show() else GameTooltip:Hide() end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function LegendText()
   local parts
   if state.mode == "list" then
      parts = {
         Glyph("PADDUP") .. Glyph("PADDDOWN") .. " choose",
         Glyph("PADDLEFT") .. Glyph("PADDRIGHT") .. " category",
         Glyph("PADLSHOULDER") .. Glyph("PADRSHOULDER") .. " set",
         Glyph("PAD1") .. " take",
         Glyph("PAD2") .. " close",
      }
   else
      parts = {
         Glyph("PADLTRIGGER") .. "/" .. Glyph("PADRTRIGGER") .. " + button: put it there",
         Glyph("PADDUP") .. " move",
         Glyph("PAD1") .. " put",
         Glyph("PAD3") .. " empty",
         Glyph("PADLSHOULDER") .. Glyph("PADRSHOULDER") .. " set",
         Glyph("PAD2") .. " back",
      }
   end
   return table.concat(parts, "     ")
end

Refresh = function()
   if not (win and win:IsShown()) then return end
   local active = ActiveSet()
   setText:SetText(("Set %d / %d%s"):format(state.set, SETS,
      state.set == active and "   |cff66ff66(in use)|r" or ("   |cff999999(in use: " .. active .. ")|r")))
   local tabs = {}
   for i, name in ipairs(TABS) do
      tabs[i] = (i == state.tab) and ("|cffffd100" .. name:upper() .. "|r") or ("|cff888888" .. name .. "|r")
   end
   tabText:SetText(table.concat(tabs, "    ") .. "   |cff666666(" .. #entries .. ")|r")
   -- list
   if state.sel < state.top then state.top = state.sel end
   if state.sel >= state.top + VISIBLE then state.top = state.sel - VISIBLE + 1 end
   for i = 1, VISIBLE do
      local ui, entry = rowsUI[i], entries[state.top + i - 1]
      if entry then
         ui.icon:SetTexture(entry.icon)
         ui.text:SetText(entry.name)
         ui.sub:SetText(entry.group or "")
         ui.light:SetShown(state.top + i - 1 == state.sel and state.mode == "list")
         ui.picked:SetShown(state.picked == entry)
         ui:Show()
      else
         ui:Hide()
      end
   end
   -- crosses
   local keys = SlotKeys()
   for n, s in ipairs(slotsUI) do
      local slot = ActionSlot(state.set, s.row, s.index)
      local texture = slot and GetActionTexture(slot)
      s.icon:SetTexture(texture or nil)
      s.icon:SetShown(texture ~= nil)
      s.key:SetText(s.index <= 8 and Glyph(keys[s.index], s.small and 12 or 14) or "")
      s.light:SetShown(state.mode == "slot" and state.cursor == n)
   end
   legend:SetText(LegendText())
   ShowTip()
end

---------------------------------------------------------------------------
-- Moving around
---------------------------------------------------------------------------
-- The nearest slot in a direction (screen space), for the cursor
local function Neighbour(from, dx, dy)
   local a = slotsUI[from]
   local best, bestScore
   for n, b in ipairs(slotsUI) do
      if n ~= from then
         local vx, vy = b.cx - a.cx, b.cy - a.cy
         local along = vx * dx + vy * dy
         if along > 1 then
            local across = math.abs(vx * dy - vy * dx)
            local score = along + across * 2.5
            if not bestScore or score < bestScore then best, bestScore = n, score end
         end
      end
   end
   return best or from
end

local function MoveList(delta)
   state.sel = math.max(1, math.min(#entries, state.sel + delta))
   Refresh()
end

local function MoveCursor(dx, dy)
   state.cursor = Neighbour(state.cursor, dx, dy)
   Refresh()
end

local function ChangeSet(delta)
   state.set = (state.set - 1 + delta) % SETS + 1
   PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
   Refresh()
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

local function TriggerRow()
   local h = state.held
   if h.L and h.R then return (h.L < h.R) and 3 or 4 end
   if h.L then return 1 end
   if h.R then return 2 end
end

local function CursorTo(row, index)
   for n, s in ipairs(slotsUI) do
      if s.row == row and s.index == index then state.cursor = n end
   end
end

local function OnPad(_, key)
   if key == "PADLTRIGGER" then state.held.L = GetTime() return end
   if key == "PADRTRIGGER" then state.held.R = GetTime() return end
   if key == "PADLSHOULDER" then ChangeSet(-1) return end
   if key == "PADRSHOULDER" then ChangeSet(1) return end
   local triggerRow = TriggerRow()
   if state.mode == "slot" and triggerRow then
      local keys = SlotKeys()
      for index = 1, 8 do
         if keys[index] == key then
            CursorTo(triggerRow, index)
            Place(state.picked, state.set, triggerRow, index)
            return
         end
      end
      return
   end
   if key == "PAD2" then
      if state.mode == "slot" then state.mode = "list"; state.picked = nil; Refresh() else Close() end
   elseif state.mode == "list" then
      if key == "PADDDOWN" then MoveList(1)
      elseif key == "PADDUP" then MoveList(-1)
      elseif key == "PADDRIGHT" or key == "PADDLEFT" then
         state.tab = (state.tab - 1 + (key == "PADDRIGHT" and 1 or -1)) % #TABS + 1
         state.sel, state.top = 1, 1
         Load(); Refresh()
      elseif key == "PAD1" then Pick()
      end
   else
      if key == "PADDDOWN" then MoveCursor(0, -1)
      elseif key == "PADDUP" then MoveCursor(0, 1)
      elseif key == "PADDRIGHT" then MoveCursor(1, 0)
      elseif key == "PADDLEFT" then MoveCursor(-1, 0)
      elseif key == "PAD1" then
         local s = slotsUI[state.cursor]
         Place(state.picked, state.set, s.row, s.index)
      elseif key == "PAD3" then
         local s = slotsUI[state.cursor]
         Empty(state.set, s.row, s.index)
      end
   end
end

local function OnPadUp(_, key)
   if key == "PADLTRIGGER" then state.held.L = nil end
   if key == "PADRTRIGGER" then state.held.R = nil end
end

-- The left stick: held past half way, it moves, then repeats
local DEAD, FIRST, REPEAT = 0.5, 0.35, 0.09
local stickNames = {}
local function OnStick(_, stick, x, y)
   if not stickNames[stick] then stickNames[stick] = true; Log("stick name: " .. tostring(stick)) end
   if stick == "Left" or stick == "LStick" or stick == "Movement" or stick == "Move" then
      state.stickX, state.stickY = x or 0, y or 0
   end
end

local function StickTick(_, elapsed)
   local x, y = state.stickX, state.stickY
   local dir
   if math.abs(y) >= DEAD and math.abs(y) >= math.abs(x) then dir = y > 0 and "up" or "down"
   elseif math.abs(x) >= DEAD then dir = x > 0 and "right" or "left" end
   if not dir then state.stickDir, state.stickWait = nil, 0 return end
   if dir ~= state.stickDir then
      state.stickDir, state.stickWait = dir, FIRST
   else
      state.stickWait = (state.stickWait or 0) - elapsed
      if state.stickWait > 0 then return end
      state.stickWait = REPEAT
   end
   if state.mode == "list" then
      if dir == "up" then MoveList(-1) elseif dir == "down" then MoveList(1) end
   else
      if dir == "up" then MoveCursor(0, 1) elseif dir == "down" then MoveCursor(0, -1)
      elseif dir == "left" then MoveCursor(-1, 0) else MoveCursor(1, 0) end
   end
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------
local function SlotButton(parent, row, index, size, x, y)
   local ui = CreateFrame("Button", nil, parent)
   ui:SetSize(size, size)
   ui:SetPoint("CENTER", parent, "TOPLEFT", x, y)
   ui.row, ui.index, ui.small = row, index, size < S
   ui.cx, ui.cy = x, y
   local bg = ui:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.08)
   local edge = ui:CreateTexture(nil, "BORDER"); edge:SetPoint("TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", 1, -1)
   edge:SetColorTexture(0, 0, 0, 0.6)
   ui.icon = ui:CreateTexture(nil, "ARTWORK"); ui.icon:SetPoint("TOPLEFT", 2, -2); ui.icon:SetPoint("BOTTOMRIGHT", -2, 2)
   ui.key = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ui.key:SetPoint("BOTTOMRIGHT", 4, -4)
   ui.light = ui:CreateTexture(nil, "OVERLAY"); ui.light:SetPoint("TOPLEFT", -4, 4); ui.light:SetPoint("BOTTOMRIGHT", 4, -4)
   ui.light:SetColorTexture(1, 0.82, 0, 0.5)
   local hl = ui:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.2)
   ui:RegisterForClicks("LeftButtonUp", "RightButtonUp")
   ui:RegisterForDrag("LeftButton")
   ui:SetScript("OnClick", function(self, button)
      CursorTo(row, index)
      if button == "RightButton" then Empty(state.set, row, index)
      elseif GetCursorInfo() then DropOn(state.set, row, index)
      elseif state.picked then Place(state.picked, state.set, row, index)
      else state.mode = "slot"; Refresh() end
   end)
   ui:SetScript("OnReceiveDrag", function() DropOn(state.set, row, index) end)
   ui:SetScript("OnDragStart", function()
      local slot = ActionSlot(state.set, row, index)
      if slot and not InCombatLockdown() then PickupAction(slot); Refresh() end
   end)
   ui:SetScript("OnEnter", function(self)
      local slot = ActionSlot(state.set, row, index)
      if slot and HasAction(slot) then
         GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetAction(slot); GameTooltip:Show()
      end
   end)
   ui:SetScript("OnLeave", function() ShowTip() end)
   return ui
end

-- One bar: three crosses side by side
local function BuildBar(parent, row, ox, oy)
   local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
   label:SetPoint("TOPLEFT", parent, "TOPLEFT", ox, oy)
   label:SetText(ROWS[row].label)
   local x = ox
   for _, cross in ipairs(CROSSES) do
      local size = cross.small and SMALL or S
      local step = size + 4
      local cx, cy = x + step * 1.5, oy - 28 - step * 1.5
      for _, place in ipairs({ { "up", 0, 1 }, { "left", -1, 0 }, { "right", 1, 0 }, { "down", 0, -1 } }) do
         local index = cross[place[1]]
         slotsUI[#slotsUI + 1] = SlotButton(parent, row, index, size, cx + place[2] * step, cy + place[3] * step)
      end
      local name = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      name:SetPoint("TOP", parent, "TOPLEFT", cx, cy - step * 1.5 - 4)
      name:SetText(cross.name)
      x = x + step * 3 + 14
   end
end

local function Build()
   local listW = 300
   local barW = (S + 4) * 3 * 2 + (SMALL + 4) * 3 + 28
   local W = 16 + listW + 24 + barW * 2 + 24 + 16
   local barH = 28 + (S + 4) * 3 + 22
   local H = 70 + math.max(VISIBLE * ROW_H, barH * 2 + 10) + 44
   win = CreateFrame("Frame", "CrossHotbarEditorFrame", UIParent, "BackdropTemplate")
   win:SetSize(W, H)
   win:SetPoint("CENTER", 0, 40)
   win:SetFrameStrata("DIALOG")
   win:SetToplevel(true)
   win:EnableMouse(true)
   win:SetMovable(true)
   win:SetClampedToScreen(true)
   win:RegisterForDrag("LeftButton")
   win:SetScript("OnDragStart", win.StartMoving)
   win:SetScript("OnDragStop", win.StopMovingOrSizing)
   if win.SetBackdrop then
      win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      win:SetBackdropColor(0.04, 0.05, 0.08, 0.95)
      win:SetBackdropBorderColor(0.5, 0.5, 0.6, 1)
   end
   tinsert(UISpecialFrames, win:GetName())

   local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
   title:SetPoint("TOPLEFT", 16, -12)
   title:SetText("Crossbar editor")
   setText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
   setText:SetPoint("TOPLEFT", 16 + listW + 24, -12)
   local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
   close:SetPoint("TOPRIGHT", -2, -2)
   tabText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   tabText:SetPoint("TOPLEFT", 16, -42)

   local list = CreateFrame("Frame", nil, win)
   list:SetPoint("TOPLEFT", 12, -64)
   list:SetSize(listW, VISIBLE * ROW_H)
   list:EnableMouseWheel(true)
   list:SetScript("OnMouseWheel", function(_, delta) MoveList(-delta * 3) end)
   for i = 1, VISIBLE do
      local ui = CreateFrame("Button", nil, list)
      ui:SetSize(listW, ROW_H - 2)
      ui:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
      ui.icon = ui:CreateTexture(nil, "ARTWORK"); ui.icon:SetSize(22, 22); ui.icon:SetPoint("LEFT", 2, 0)
      ui.text = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); ui.text:SetPoint("LEFT", ui.icon, "RIGHT", 6, 0)
      ui.text:SetWidth(180); ui.text:SetJustifyH("LEFT"); ui.text:SetWordWrap(false)
      ui.sub = ui:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); ui.sub:SetPoint("RIGHT", -4, 0)
      ui.light = ui:CreateTexture(nil, "BACKGROUND"); ui.light:SetAllPoints(); ui.light:SetColorTexture(1, 0.82, 0, 0.2)
      ui.picked = ui:CreateTexture(nil, "BORDER"); ui.picked:SetAllPoints(); ui.picked:SetColorTexture(0.2, 0.8, 1, 0.25)
      local hl = ui:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
      ui:SetScript("OnClick", function()
         state.sel = state.top + i - 1; state.mode = "list"; Pick()
      end)
      ui:SetScript("OnEnter", function() state.sel = state.top + i - 1; if state.mode == "list" then Refresh() end end)
      ui:RegisterForDrag("LeftButton")
      ui:SetScript("OnDragStart", function()
         local entry = entries[state.top + i - 1]
         if entry and not InCombatLockdown() then pcall(Pickup, entry) end
      end)
      rowsUI[i] = ui
   end

   local bars = CreateFrame("Frame", nil, win)
   bars:SetPoint("TOPLEFT", list, "TOPRIGHT", 24, 8)
   bars:SetSize(barW * 2, barH * 2)
   BuildBar(bars, 1, 0, 0)
   BuildBar(bars, 2, barW, 0)
   BuildBar(bars, 3, 0, -barH - 10)
   BuildBar(bars, 4, barW, -barH - 10)

   legend = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   legend:SetPoint("BOTTOMLEFT", 16, 16)
   legend:SetPoint("BOTTOMRIGHT", -16, 16)
   legend:SetJustifyH("LEFT")

   win:SetScript("OnGamePadButtonDown", OnPad)
   win:SetScript("OnGamePadButtonUp", OnPadUp)
   win:SetScript("OnGamePadStick", OnStick)
   win:EnableGamePadButton(false)
   if win.EnableGamePadStick then win:EnableGamePadStick(false) end
   win:SetScript("OnUpdate", StickTick)
   win:SetScript("OnShow", function(self)
      self:EnableGamePadButton(true)
      if self.EnableGamePadStick then self:EnableGamePadStick(true) end
      state.held, state.stickX, state.stickY = {}, 0, 0
      state.set = ActiveSet()
      Load(); Refresh()
   end)
   win:SetScript("OnHide", function(self)
      self:EnableGamePadButton(false)
      if self.EnableGamePadStick then self:EnableGamePadStick(false) end
      state.mode, state.picked = "list", nil
      GameTooltip:Hide()
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

   -- What's on the cursor, drawn beside it while the editor is open (the
   -- game doesn't draw it with the pad's cursor)
   carry = CreateFrame("Frame", nil, UIParent)
   carry:SetSize(36, 36)
   carry:SetFrameStrata("TOOLTIP")
   carry:EnableMouse(false)
   carry.icon = carry:CreateTexture(nil, "OVERLAY"); carry.icon:SetAllPoints()
   carry:Hide()
   carry:SetScript("OnUpdate", function(self)
      if not (win:IsShown() and GetCursorInfo()) then self:Hide() return end
      local x, y = GetCursorPosition()
      local scale = UIParent:GetEffectiveScale()
      self:ClearAllPoints()
      self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale + 18, y / scale - 18)
   end)
   win:RegisterEvent("CURSOR_CHANGED")
   win:HookScript("OnEvent", function(_, event)
      if event ~= "CURSOR_CHANGED" then return end
      local kind, a, b, c = GetCursorInfo()
      local texture
      if kind == "spell" then
         local id = c or b
         texture = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or (GetSpellTexture and GetSpellTexture(id))
      elseif kind == "item" then
         texture = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(a)) or (GetItemIcon and GetItemIcon(a))
      elseif kind == "macro" then
         texture = select(2, GetMacroInfo(a))
      elseif kind == "action" then
         texture = GetActionTexture(a)
      end
      if texture and win:IsShown() then carry.icon:SetTexture(texture); carry:Show() else carry:Hide() end
   end)
end

function E.IsOpen()
   return win ~= nil and win:IsShown()
end

function E.Toggle()
   if InCombatLockdown() then Say("the crossbar editor opens out of combat.") return end
   if not win then Build() end
   win:SetShown(not win:IsShown())
end

-- Open with something already taken (the slot step), e.g. from the game's bind mode
function E.OpenWith(entry)
   if InCombatLockdown() then return end
   if not win then Build() end
   if not win:IsShown() then win:Show() end
   state.picked, state.mode = entry, "slot"
   Refresh()
end

function CrossHotbar_OpenEditor()
   E.Toggle()
end

SLASH_CROSSHOTBAREDITOR1 = "/xhb"
SLASH_CROSSHOTBAREDITOR2 = "/crossbar"
SlashCmdList.CROSSHOTBAREDITOR = function() E.Toggle() end

---------------------------------------------------------------------------
-- The game's own Bind mode (Spellbook / bags -> Bind, then a press): it
-- writes the Gamepad UI's crossbar slots. If that goes through this Lua
-- table, the same action goes on CrossHotbar's matching slot in the set in
-- use: its left bar -> L2, right -> R2, both triggers -> L2 > R2. Logged.
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
      local set = ActiveSet()
      Place(entry, set, row, UNIT_TO_INDEX[n])
      Say(("bound to set %d, %s + %s."):format(set, ROWS[row].label, Glyph(SlotKeys()[UNIT_TO_INDEX[n]] or "?", 14)))
   end
end

if Util and Util.AssignActionToGamepadStandardSlot then
   hooksecurefunc(Util, "AssignActionToGamepadStandardSlot", function(storage)
      Log("bind mode assigned game slot " .. tostring(storage))
      C_Timer.After(0, function() Mirror(storage) end)
   end)
end
