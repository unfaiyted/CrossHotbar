-- Crossbar editor: put spells, items and macros on CrossHotbar's bars with
-- the gamepad (or the mouse / drag and drop).
--
--   1. The list: what can go on a bar (Spells, Items, Macros; D-pad
--      left / right; D-pad up / down to choose), a tooltip of the one
--      highlighted. A takes it.
--   2. The crossbar, as the game draws it: [L2 D-pad][L2 face]  [R2 D-pad]
--      [R2 face], each slot with its pad button. Hold L2 / R2 (L2 then R2,
--      R2 then L2: the WXHB bars) and press the button: it goes there, and
--      it's back to the list. Or move with the D-pad / left stick and A.
--      Y cycles the view (L2 | R2, WXHB, Expanded), X empties a slot, B back.
--   LB / RB: the set being edited (1-6), any time.
-- Mouse: click an entry, then a slot (right-click empties); dragging
-- anything (spellbook, bags) shows the crossbar to drop it on.
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
local DEFAULT_KEYS = { "PAD2", "PAD4", "PAD1", "PAD3", "PADDRIGHT", "PADDUP", "PADDDOWN", "PADDLEFT",
                       "PADDRIGHT", "PADDUP", "PADDDOWN", "PADDLEFT" }
local TABS = { "Spells", "Actions", "Items", "Macros", "Mounts", "Pets" }
local VISIBLE = 14
local ROW_H = 26
local S = 40          -- (slot size)

local win, tabText, setText, legend, carry
local rowsUI, slotsUI = {}, {}
local state = { tab = 1, sel = 1, top = 1, mode = "list", cursor = 1, picked = nil, held = {}, lastUp = {}, set = 1, view = 1,
                stickY = 0, stickX = 0, expanded = false, needRelease = false, displaced = false, dragging = false }
local DOUBLE_TAP = 0.35
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
-- The pad button of each of a bar's 12 slots: 1-8 from CrossHotbar's
-- trigger actions; 9-12 (expanded) as CrossHotbar.lua's ApplyConfig binds
-- them: the face buttons (HOTBARBTN1-4), the L2 bar's on the D-pad
-- (HOTBARBTN5-8) in this fork
local function SlotKeys(row)
   local keys = {}
   local pad = addon.Config and addon.Config.PadActions
   if pad then
      for _, attributes in pairs(pad) do
         local n = tonumber(tostring(attributes.TRIGACTION or ""):match("^HOTBARBTN(%d+)$"))
         if n and n <= 8 and attributes.BIND then keys[n] = attributes.BIND end
      end
   end
   for n = 1, 8 do keys[n] = keys[n] or DEFAULT_KEYS[n] end
   local from = (row == 1 and addon.MirrorExpanded ~= false) and 5 or 1
   for i = 0, 3 do keys[9 + i] = keys[from + i] end
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
   local A = addon.Actions
   local sources = { SpellEntries, A and A.CommandEntries, ItemEntries, MacroEntries, A and A.MountEntries, A and A.PetEntries }
   local ok, result = pcall(sources[state.tab] or function() return {} end)
   if not ok then Log("list error: " .. tostring(result)); result = {} end
   table.insert(result, 1, { kind = "empty", name = "Empty a slot", icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
                             group = "" })
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
   elseif entry.kind == "command" then
      local index = addon.Actions and addon.Actions.Macro(entry)
      if index then PickupMacro(index) end
   elseif entry.kind == "pet" then
      if C_PetJournal and C_PetJournal.PickupPet then C_PetJournal.PickupPet(entry.id) end
   end
end

local Refresh

-- What's on the cursor, as a list entry (an action PlaceAction pushed out)
local function CursorEntry()
   local kind, a, b, c = GetCursorInfo()
   if kind == "spell" then
      local id = c or b
      local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id))
      local icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or (GetSpellTexture and GetSpellTexture(id))
      return { kind = "spell", id = id, name = name or ("spell " .. tostring(id)), icon = icon }
   elseif kind == "item" then
      local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(a)) or (GetItemInfo and GetItemInfo(a))
      local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(a)) or (GetItemIcon and GetItemIcon(a))
      return { kind = "item", id = a, name = name or ("item " .. tostring(a)), icon = icon }
   elseif kind == "macro" then
      local name, icon = GetMacroInfo(a)
      return name and { kind = "macro", id = a, name = name, icon = icon } or nil
   elseif kind == "mount" and C_MountJournal and C_MountJournal.GetMountInfoByID then
      local name, spellID, icon = C_MountJournal.GetMountInfoByID(a)
      return spellID and { kind = "spell", id = spellID, name = name, icon = icon } or nil
   elseif kind == "battlepet" and C_PetJournal and C_PetJournal.GetPetInfoByPetID then
      local _, customName, _, _, _, _, _, name, icon = C_PetJournal.GetPetInfoByPetID(a)
      return { kind = "pet", id = a, name = customName or name or "Pet", icon = icon }
   end
end

local Empty

-- Puts the entry on the slot; returns what was there before (pushed out), if anything
local function Place(entry, set, row, index)
   if InCombatLockdown() then Say("can't change bars in combat.") return end
   if entry and entry.kind == "empty" then Empty(set, row, index) return end
   local slot = ActionSlot(set, row, index)
   if not (entry and slot) then return end
   ClearCursor()
   local ok, err = pcall(Pickup, entry)
   if ok and GetCursorInfo() then ok, err = pcall(PlaceAction, slot) end
   local displaced = ok and CursorEntry() or nil
   ClearCursor()
   Log(("place %s %s -> set %d %s #%d (action %d)%s"):format(entry.kind, tostring(entry.id), set,
      ROWS[row].label, index, slot, ok and "" or (" FAILED " .. tostring(err))))
   if not ok then Say("couldn't place it: " .. tostring(err)) end
   PlaySound(SOUNDKIT and SOUNDKIT.IG_ABILITY_ICON_DROP or 838)
   Refresh()
   return displaced
end

Empty = function(set, row, index)
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
      local displaced = CursorEntry()
      ClearCursor()
      Log(("drop -> set %d %s #%d (action %d)"):format(set, ROWS[row].label, index, slot))
      Refresh()
      return displaced
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
      elseif e and e.kind == "command" then
         GameTooltip:SetText(e.name, 1, 1, 1)
         GameTooltip:AddLine(e.body, 0.8, 0.8, 0.8, true)
         GameTooltip:AddLine("Placed as the general macro \"" .. ("x:" .. e.name):sub(1, 16) .. "\".", 0.5, 0.5, 0.5, true)
         shown = true
      elseif e and e.kind == "pet" then
         GameTooltip:SetText(e.name, 1, 1, 1)
         shown = true
      elseif e and e.kind == "macro" then
         local name, _, body = GetMacroInfo(e.id)
         GameTooltip:SetText(name or "Macro", 1, 1, 1)
         if body then GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true) end
         shown = true
      end
   else
      local s = slotsUI[state.cursor]
      local slot = s and s.visible and ActionSlot(state.set, s.row, s.index)
      if slot and HasAction(slot) then GameTooltip:SetAction(slot); shown = true end
   end
   if shown then GameTooltip:Show() else GameTooltip:Hide() end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
-- Two steps, one window that changes size:
--   list:   what to put on a bar (the list, a tooltip beside it)
--   assign: the crossbar as the game draws it, [L2 D-pad][L2 face]
--           [R2 D-pad][R2 face]; the trigger(s) held light their half (or
--           switch to the WXHB bars), the slot's button puts it there.
--           Y cycles the view: L2 | R2, WXHB (L2>R2 | R2>L2), Expanded.
local VIEWS = {
   { row = 1, crosses = { 1, 2, 3 } },
   { row = 2, crosses = { 1, 2, 3 } },
   { row = 3, crosses = { 1, 2 } },   -- (the WXHB bars have no expanded slots)
   { row = 4, crosses = { 1, 2 } },
}
local LIST_W = 340
local SLOT_GAP = 6
local STEP = S + SLOT_GAP
local CROSS_W = STEP * 3
local HALF_GAP = 40

local function LegendText()
   local parts
   if state.mode == "list" then
      parts = {
         Glyph("PADDUP") .. Glyph("PADDDOWN") .. " choose",
         Glyph("PADDLEFT") .. Glyph("PADDRIGHT") .. " category",
         Glyph("PAD1") .. " take",
         Glyph("PAD4") .. " one bar " .. ((addon.ForeverSettings and addon:ForeverSettings() and addon:ForeverSettings().singleBar) and "on" or "off"),
         Glyph("PADFORWARD") .. " Improved Forever",
         Glyph("PAD2") .. " close",
      }
   else
      parts = {
         "hold " .. Glyph("PADLTRIGGER") .. " / " .. Glyph("PADRTRIGGER") .. " + button: put it there",
         Glyph("PADLSHOULDER") .. Glyph("PADRSHOULDER") .. " set",
         Glyph("PAD2") .. (state.displaced and " drop it" or " back"),
      }
   end
   return table.concat(parts, "    ")
end

-- The rows lit by the triggers held (and the view they switch to)
local function TriggerRow()
   local h = state.held
   if h.L and h.R then return (h.L < h.R) and 3 or 4 end
   if h.L then return 1 end
   if h.R then return 2 end
end

local function CurrentView()
   return TriggerRow() or state.view
end

-- The bar and crosses to draw: the trigger(s) held (a double tap and hold:
-- the expanded cross), or, dragging with the mouse, the bar Y picked; else none
local function Shown()
   local row = TriggerRow()
   if row then
      if state.expanded and row <= 2 then return row, { 3 } end
      return row, { 1, 2 }
   end
   if state.dragging then return VIEWS[state.view].row, VIEWS[state.view].crosses end
end

-- Places the slots of the view shown; hides the rest
local assign, assignTitle, viewText, prompt, halfLabels, crossLabels = nil, nil, nil, nil, {}, {}
local function Layout()
   local row, crosses = Shown()
   for _, s in ipairs(slotsUI) do s.visible = false end
   for _, label in pairs(crossLabels) do label:Hide() end
   halfLabels[2]:Hide()
   if not row then
      halfLabels[1]:Hide()
      for _, s in ipairs(slotsUI) do s:Hide() end
      assign:SetSize(480, 36 + CROSS_W + 20)
      return 480
   end
   halfLabels[1]:ClearAllPoints()
   halfLabels[1]:SetPoint("BOTTOMLEFT", assign, "TOPLEFT", 0, -26)
   halfLabels[1]:SetText(ROWS[row].label .. ((state.expanded and row <= 2 and TriggerRow()) and "  expanded" or ""))
   halfLabels[1]:Show()
   local view = { row = row }
   local x = 0
   for _, c in ipairs(crosses) do
      local cx, cy = x + CROSS_W / 2, -36 - CROSS_W / 2
      for _, s in ipairs(slotsUI) do
         if s.row == view.row and s.cross == c then
            local px, py = cx + s.dx * STEP, cy + s.dy * STEP
            s:ClearAllPoints()
            s:SetPoint("CENTER", assign, "TOPLEFT", px, py)
            s.cx, s.cy = px, py
            s.visible = true
         end
      end
      if not crossLabels[c] then
         crossLabels[c] = assign:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      end
      crossLabels[c]:ClearAllPoints()
      crossLabels[c]:SetPoint("TOP", assign, "TOPLEFT", cx, cy - CROSS_W / 2 - 2)
      crossLabels[c]:SetText(CROSSES[c].name)
      crossLabels[c]:Show()
      x = x + CROSS_W + (c == 2 and 30 or 12)
   end
   for _, s in ipairs(slotsUI) do s:SetShown(s.visible) end
   local width = x - 12
   assign:SetSize(width, 36 + CROSS_W + 20)
   return width
end

local function SetMode(mode)
   state.mode = mode
   if not win then return end
   local listShown = mode == "list"
   win.list:SetShown(listShown)
   tabText:SetShown(listShown)
   assign:SetShown(not listShown)
end

Refresh = function()
   if not (win and win:IsShown()) then return end
   local active = ActiveSet()
   setText:SetText(("Set %d / %d%s"):format(state.set, SETS,
      state.set == active and "  |cff66ff66in use|r" or ("  |cff999999(in use: " .. active .. ")|r")))
   local width
   if state.mode == "list" then
      local tabs = {}
      for i, name in ipairs(TABS) do
         tabs[i] = (i == state.tab) and ("|cffffd100" .. name:upper() .. "|r") or ("|cff888888" .. name .. "|r")
      end
      tabText:SetText(table.concat(tabs, "    ") .. "   |cff666666(" .. #entries .. ")|r")
      if state.sel < state.top then state.top = state.sel end
      if state.sel >= state.top + VISIBLE then state.top = state.sel - VISIBLE + 1 end
      for i = 1, VISIBLE do
         local ui, entry = rowsUI[i], entries[state.top + i - 1]
         if entry then
            ui.icon:SetTexture(entry.icon)
            ui.text:SetText(entry.name)
            ui.sub:SetText(entry.group or "")
            ui.light:SetShown(state.top + i - 1 == state.sel)
            ui:Show()
         else
            ui:Hide()
         end
      end
      width = LIST_W
      win:SetSize(width + 32, 64 + VISIBLE * ROW_H + 44)
   else
      width = Layout()
      local p = state.picked
      local title = p and ("|T" .. tostring(p.icon) .. ":20|t  " .. p.name) or "Drop it on a slot"
      if state.displaced and p then title = title .. "   |cffff9933(pushed out: put it somewhere, or " .. Glyph("PAD2", 14) .. " to drop it)|r" end
      assignTitle:SetText(title)
      if state.dragging then
         local names = {}
         for v, view in ipairs(VIEWS) do
            local label = ROWS[view.row].label
            names[v] = (v == state.view) and ("|cffffd100" .. label .. "|r") or ("|cff777777" .. label .. "|r")
         end
         viewText:SetText(Glyph("PAD4", 14) .. "  " .. table.concat(names, "  "))
      else
         viewText:SetText("")
      end
      prompt:SetShown(Shown() == nil)
      prompt:SetText("Hold " .. Glyph("PADLTRIGGER", 22) .. " or " .. Glyph("PADRTRIGGER", 22) .. " to show that bar, then press the button.\n"
         .. "|cffaaaaaaBoth (one then the other): the WXHB bars.   Tap twice and hold: the expanded slots.|r")
      local lit = nil
      if not (slotsUI[state.cursor] and slotsUI[state.cursor].visible) then
         for n, s in ipairs(slotsUI) do if s.visible then state.cursor = n break end end
      end
      for n, s in ipairs(slotsUI) do
         if s.visible then
            local slot = ActionSlot(state.set, s.row, s.index)
            local texture = slot and GetActionTexture(slot)
            s.icon:SetTexture(texture or nil)
            s.icon:SetShown(texture ~= nil)
            s.empty:SetShown(texture == nil)
            local key = SlotKeys(s.row)[s.index]
            s.key:SetText(key and Glyph(key, 20) or "")
            s.light:SetShown(state.cursor == n)
            s:SetAlpha((not lit or s.row == lit) and 1 or 0.3)
         end
      end
      win:SetSize(math.max(width + 32, 520), 64 + 36 + CROSS_W + 20 + 44)
   end
   legend:SetText(LegendText())
   ShowTip()
end

---------------------------------------------------------------------------
-- Moving around
---------------------------------------------------------------------------
-- The nearest shown slot in a direction (screen space), for the cursor
local function Neighbour(from, dx, dy)
   local a = slotsUI[from]
   if not (a and a.visible) then return from end
   local best, bestScore
   for n, b in ipairs(slotsUI) do
      if n ~= from and b.visible then
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

local function Back()
   if state.displaced and state.picked then Say("dropped " .. tostring(state.picked.name) .. ".") end
   state.picked, state.displaced, state.dragging = nil, false, false
   SetMode("list")
   ClearCursor()
   Refresh()
end

local function Pick()
   local entry = entries[state.sel]
   if not entry then return end
   state.picked = entry
   state.view = 1
   SetMode("slot")
   PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION or 857)
   Refresh()
end

local function CursorTo(row, index)
   for n, s in ipairs(slotsUI) do
      if s.row == row and s.index == index then state.cursor = n end
   end
end

-- Placed: back to the list; or, if it pushed something out, that's picked next
-- (the trigger let go first, so the same press doesn't put it straight back)
local function Placed(displaced)
   if displaced then
      state.picked, state.displaced, state.dragging = displaced, true, false
      state.needRelease = TriggerRow() ~= nil
      Refresh()
   else
      local wasDisplaced = state.displaced
      state.displaced = false
      if wasDisplaced then state.picked = nil end
      Back()
   end
end

local function OnPad(_, key)
   if key == "PADLTRIGGER" or key == "PADRTRIGGER" then
      local side = key == "PADLTRIGGER" and "L" or "R"
      local now = GetTime()
      -- (tapped, then pressed again quickly and held: the expanded slots)
      if state.lastUp[side] and now - state.lastUp[side] <= DOUBLE_TAP and not (state.held.L or state.held.R) then
         state.expanded = true
      end
      state.held[side] = now
      Refresh()
      return
   end
   if key == "PADLSHOULDER" then ChangeSet(-1) return end
   if key == "PADRSHOULDER" then ChangeSet(1) return end
   if state.mode == "slot" then
      local row = TriggerRow()
      if row then
         if state.needRelease then return end
         local keys = SlotKeys(row)
         local first, last = 1, 8
         if state.expanded and row <= 2 then first, last = 9, 12 end
         for index = first, last do
            if keys[index] == key then
               CursorTo(row, index)
               if state.picked then
                  Placed(Place(state.picked, state.set, row, index))
               end
               return
            end
         end
         return
      end
      if key == "PAD2" then Back()
      elseif key == "PAD4" and state.dragging then state.view = state.view % #VIEWS + 1; Refresh()
      end
      return
   end
   if key == "PAD2" then Close()
   elseif key == "PAD4" and addon.ToggleSingleBar then
      local on = addon:ToggleSingleBar()
      Say("single-bar mode " .. (on and "on" or "off") .. ".")
      Refresh()
   elseif key == "PADFORWARD" then
      local IF = _G.ImprovedForever
      if IF and IF.Menu and IF.Menu.Toggle then Close(); IF.Menu.Toggle() end
   elseif key == "PADDDOWN" then MoveList(1)
   elseif key == "PADDUP" then MoveList(-1)
   elseif key == "PADDRIGHT" or key == "PADDLEFT" then
      state.tab = (state.tab - 1 + (key == "PADDRIGHT" and 1 or -1)) % #TABS + 1
      state.sel, state.top = 1, 1
      Load(); Refresh()
   elseif key == "PAD1" then Pick()
   end
end

local function OnPadUp(_, key)
   if key == "PADLTRIGGER" or key == "PADRTRIGGER" then
      local side = key == "PADLTRIGGER" and "L" or "R"
      state.held[side] = nil
      state.lastUp[side] = GetTime()
      if not (state.held.L or state.held.R) then
         state.expanded, state.needRelease = false, false
      end
      Refresh()
   end
end

-- The left stick: held past half way, it moves, then repeats
local DEAD, FIRST, REPEAT = 0.5, 0.35, 0.09
local stickNames = {}
local function OnStick(_, stick, x, y)
   if not stickNames[stick] then stickNames[stick] = true; Log("stick name: " .. tostring(stick)) end
   -- (no stick scrolls the list: the left stick stays the game's, for
   -- moving, and "Look", the right stick, also carries the gyro on some pads,
   -- which kept scrolling it to the top. Logged only.)
   if false then
      state.stickX, state.stickY = x or 0, y or 0
   end
end

local function StickTick(_, elapsed)
   local x, y = state.stickX, state.stickY
   -- (the D-pad held in the list: repeats, like a held stick)
   if state.mode == "list" and IsKeyDown then
      if IsKeyDown("PADDUP") then y = 1 elseif IsKeyDown("PADDDOWN") then y = -1 end
   end
   local dir
   if math.abs(y) >= DEAD and math.abs(y) >= math.abs(x) then dir = y > 0 and "up" or "down"
   elseif math.abs(x) >= DEAD then dir = x > 0 and "right" or "left" end
   if not dir then state.stickDir, state.stickWait = nil, 0 return end
   if dir ~= state.stickDir then
      -- (the press itself already moved one: repeats start after FIRST)
      state.stickDir, state.stickWait = dir, FIRST
      return
   else
      state.stickWait = (state.stickWait or 0) - elapsed
      if state.stickWait > 0 then return end
      state.stickWait = REPEAT
   end
   if state.mode == "list" then
      if dir == "up" then MoveList(-1) elseif dir == "down" then MoveList(1) end
   end
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------
local function SlotButton(parent, row, cross, index, dx, dy)
   local ui = CreateFrame("Button", nil, parent)
   ui:SetSize(S, S)
   ui.row, ui.cross, ui.index, ui.dx, ui.dy = row, cross, index, dx, dy
   ui.cx, ui.cy = 0, 0
   -- (contrast: a dark well with a light rim; the icon inside it)
   local rim = ui:CreateTexture(nil, "BACKGROUND", nil, 0); rim:SetPoint("TOPLEFT", -2, 2); rim:SetPoint("BOTTOMRIGHT", 2, -2)
   rim:SetColorTexture(0.75, 0.75, 0.8, 0.55)
   local well = ui:CreateTexture(nil, "BACKGROUND", nil, 1); well:SetAllPoints(); well:SetColorTexture(0.02, 0.02, 0.03, 1)
   ui.empty = ui:CreateTexture(nil, "BORDER"); ui.empty:SetPoint("TOPLEFT", 4, -4); ui.empty:SetPoint("BOTTOMRIGHT", -4, 4)
   ui.empty:SetColorTexture(1, 1, 1, 0.05)
   ui.icon = ui:CreateTexture(nil, "ARTWORK"); ui.icon:SetPoint("TOPLEFT", 1, -1); ui.icon:SetPoint("BOTTOMRIGHT", -1, 1)
   -- (the pad button, big, on a dark badge in the corner)
   local badge = ui:CreateTexture(nil, "OVERLAY", nil, 1); badge:SetSize(22, 22); badge:SetPoint("BOTTOMRIGHT", 8, -8)
   badge:SetColorTexture(0, 0, 0, 0.75)
   ui.key = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); ui.key:SetPoint("CENTER", badge, "CENTER", 0, 0)
   ui.key:SetDrawLayer("OVERLAY", 2)
   -- (the cursor: a gold frame round the slot)
   ui.light = CreateFrame("Frame", nil, ui, "BackdropTemplate")
   ui.light:SetPoint("TOPLEFT", -5, 5); ui.light:SetPoint("BOTTOMRIGHT", 5, -5)
   if ui.light.SetBackdrop then
      ui.light:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 3 })
      ui.light:SetBackdropBorderColor(1, 0.82, 0, 1)
   end
   ui.light:Hide()
   local hl = ui:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
   ui:RegisterForClicks("LeftButtonUp", "RightButtonUp")
   ui:RegisterForDrag("LeftButton")
   ui:SetScript("OnClick", function(_, button)
      CursorTo(row, index)
      if button == "RightButton" then Empty(state.set, row, index)
      elseif GetCursorInfo() then Placed(DropOn(state.set, row, index))
      elseif state.picked then Placed(Place(state.picked, state.set, row, index))
      else Refresh() end
   end)
   ui:SetScript("OnReceiveDrag", function() Placed(DropOn(state.set, row, index)) end)
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

local function Build()
   win = CreateFrame("Frame", "CrossHotbarEditorFrame", UIParent, "BackdropTemplate")
   win:SetSize(LIST_W + 32, 500)
   win:SetPoint("CENTER", 0, 60)
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
      win:SetBackdropColor(0.10, 0.11, 0.15, 0.96)
      win:SetBackdropBorderColor(0.6, 0.6, 0.7, 1)
   end
   tinsert(UISpecialFrames, win:GetName())

   local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
   title:SetPoint("TOPLEFT", 16, -12)
   title:SetText("Crossbar")
   setText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   setText:SetPoint("LEFT", title, "RIGHT", 14, 0)
   local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
   close:SetPoint("TOPRIGHT", -2, -2)
   tabText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   tabText:SetPoint("TOPLEFT", 16, -40)

   -- step 1: the list
   local list = CreateFrame("Frame", nil, win)
   win.list = list
   list:SetPoint("TOPLEFT", 12, -62)
   list:SetSize(LIST_W, VISIBLE * ROW_H)
   list:EnableMouseWheel(true)
   list:SetScript("OnMouseWheel", function(_, delta) MoveList(-delta * 3) end)
   for i = 1, VISIBLE do
      local ui = CreateFrame("Button", nil, list)
      ui:SetSize(LIST_W, ROW_H - 2)
      ui:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
      ui.icon = ui:CreateTexture(nil, "ARTWORK"); ui.icon:SetSize(22, 22); ui.icon:SetPoint("LEFT", 2, 0)
      ui.text = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); ui.text:SetPoint("LEFT", ui.icon, "RIGHT", 6, 0)
      ui.text:SetWidth(200); ui.text:SetJustifyH("LEFT"); ui.text:SetWordWrap(false)
      ui.sub = ui:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); ui.sub:SetPoint("RIGHT", -4, 0)
      ui.light = ui:CreateTexture(nil, "BACKGROUND"); ui.light:SetAllPoints(); ui.light:SetColorTexture(1, 0.82, 0, 0.25)
      local hl = ui:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
      ui:SetScript("OnClick", function() state.sel = state.top + i - 1; Pick() end)
      ui:SetScript("OnEnter", function() state.sel = state.top + i - 1; if state.mode == "list" then Refresh() end end)
      ui:RegisterForDrag("LeftButton")
      ui:SetScript("OnDragStart", function()
         local entry = entries[state.top + i - 1]
         if entry and not InCombatLockdown() then pcall(Pickup, entry) end
      end)
      rowsUI[i] = ui
   end

   -- step 2: the crossbar
   assign = CreateFrame("Frame", nil, win)
   assign:SetPoint("TOPLEFT", 16, -64)
   assignTitle = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
   assignTitle:SetPoint("TOPLEFT", assign, "TOPLEFT", 0, 26)
   assignTitle:SetParent(assign)
   prompt = assign:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
   prompt:SetPoint("TOPLEFT", assign, "TOPLEFT", 0, -50)
   prompt:SetWidth(480)
   prompt:SetJustifyH("LEFT")
   prompt:SetSpacing(8)
   viewText = assign:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   viewText:SetPoint("TOPRIGHT", win, "TOPRIGHT", -36, -40)
   for h = 1, 2 do
      halfLabels[h] = assign:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
   end
   for row = 1, #ROWS do
      for c, cross in ipairs(CROSSES) do
         for _, place in ipairs({ { "up", 0, 1 }, { "left", -1, 0 }, { "right", 1, 0 }, { "down", 0, -1 } }) do
            slotsUI[#slotsUI + 1] = SlotButton(assign, row, c, cross[place[1]], place[2], place[3])
         end
      end
   end
   assign:Hide()

   legend = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   legend:SetPoint("BOTTOMLEFT", 16, 14)
   legend:SetPoint("BOTTOMRIGHT", -16, 14)
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
      state.set, state.view = ActiveSet(), 1
      if state.mode ~= "slot" then SetMode("list") end
      Load(); Refresh()
   end)
   win:SetScript("OnHide", function(self)
      self:EnableGamePadButton(false)
      if self.EnableGamePadStick then self:EnableGamePadStick(false) end
      state.picked = nil
      SetMode("list")
      GameTooltip:Hide()
      ClearCursor()
   end)
   win:RegisterEvent("PLAYER_REGEN_DISABLED")
   win:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
   win:RegisterEvent("BAG_UPDATE_DELAYED")
   win:RegisterEvent("CURSOR_CHANGED")

   -- What's on the cursor, drawn beside it (the game doesn't with the pad's cursor)
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

   local function CursorTexture()
      local kind, a, b, c = GetCursorInfo()
      if kind == "spell" then
         local id = c or b
         return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or (GetSpellTexture and GetSpellTexture(id))
      elseif kind == "item" then
         return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(a)) or (GetItemIcon and GetItemIcon(a))
      elseif kind == "macro" then
         return select(2, GetMacroInfo(a))
      elseif kind == "action" then
         return GetActionTexture(a)
      end
   end

   win:SetScript("OnEvent", function(self, event)
      if event == "PLAYER_REGEN_DISABLED" then self:Hide()
      elseif event == "BAG_UPDATE_DELAYED" and state.tab == 2 then Load(); Refresh()
      elseif event == "CURSOR_CHANGED" then
         local texture = self:IsShown() and CursorTexture()
         if texture then
            carry.icon:SetTexture(texture); carry:Show()
            -- (dragging something: show the bar to drop it on)
            if state.mode == "list" then state.picked = nil; state.view = 1; state.dragging = true; SetMode("slot"); Refresh() end
         else
            carry:Hide()
         end
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

-- Open with something already taken (the slot step), e.g. from the game's bind mode
function E.OpenWith(entry)
   if InCombatLockdown() then return end
   if not win then Build() end
   state.picked, state.view = entry, 1
   SetMode("slot")
   if not win:IsShown() then win:Show() end
   Refresh()
end

function CrossHotbar_OpenEditor()
   E.Toggle()
end

SLASH_CROSSHOTBAREDITOR1 = "/xhb"
SLASH_CROSSHOTBAREDITOR2 = "/crossbar"
SlashCmdList.CROSSHOTBAREDITOR = function(msg)
   if msg and msg:find("%S") and addon.ForeverBarCommand and addon:ForeverBarCommand(msg) then return end
   E.Toggle()
end

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
      Say(("bound to set %d, %s + %s."):format(set, ROWS[row].label, Glyph(SlotKeys(row)[UNIT_TO_INDEX[n]] or "?", 14)))
   end
end

if Util and Util.AssignActionToGamepadStandardSlot then
   hooksecurefunc(Util, "AssignActionToGamepadStandardSlot", function(storage)
      Log("bind mode assigned game slot " .. tostring(storage))
      C_Timer.After(0, function() Mirror(storage) end)
   end)
end
