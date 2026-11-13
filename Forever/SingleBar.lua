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
      local expanded = tonumber(pad:GetAttribute("state-expanded")) or 0
      -- (CrossHotbar's trigger states: 4 none, 6 / 2 L2, 7 / 1 R2, 3 L2>R2, 5 R2>L2;
      -- expanded: 1 L2's, 2 R2's)
      if trigger == 3 or trigger == 5 then
         wantL, wantR = 0, 0
      elseif trigger == 6 or trigger == 2 or expanded == 1 then
         last, wantL, wantR = "L", 1, 0
      elseif trigger == 7 or trigger == 1 or expanded == 2 then
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
      print("|cff66ccffCrossHotbar|r: single-bar mode " .. (s.singleBar and "on" or "off") .. ".")
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
   return s and s.singleBar
end
