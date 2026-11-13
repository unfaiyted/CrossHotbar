-- Common actions for the crossbar editor (Forever/Editor.lua), as FFXIV's
-- General actions: Follow, Trade, Assist... each a slash command with an
-- icon, made a macro of ours ("x:<name>", account-wide) when placed, so it
-- goes on a crossbar slot like a spell. Also the Mounts and Pets tabs, when
-- the client has the mount / pet collections (else bag mounts are Items).
local ADDON, addon = ...

local A = {}
addon.Actions = A

local I = "Interface\\Icons\\"
-- { key, name, icon, macro body, group }
A.COMMANDS = {
   { "follow",    "Follow target",        I .. "Ability_Rogue_Sprint",            "/follow",                 "Target" },
   { "assist",    "Assist target",        I .. "Ability_DualWield",               "/assist",                 "Target" },
   { "trade",     "Trade target",         I .. "INV_Misc_Coin_01",                "/trade",                  "Target" },
   { "inspect",   "Inspect target",       I .. "INV_Misc_Spyglass_03",            "/inspect",                "Target" },
   { "invite",    "Invite target",        I .. "Spell_Holy_PrayerOfSpirit",       "/invite",                 "Target" },
   { "whisper",   "Whisper target",       I .. "INV_Letter_15",
     "/run if UnitExists('target') and UnitIsPlayer('target') then ChatFrame_OpenChat('/w '..GetUnitName('target',true)..' ') end", "Target" },
   { "nearest",   "Target nearest enemy", I .. "Ability_Hunter_MarkedForDeath",   "/targetenemy",            "Target" },
   { "lasttgt",   "Last target",          I .. "Ability_Hunter_SniperShot",       "/targetlasttarget",       "Target" },
   { "cleartgt",  "Clear target",         I .. "Spell_Shadow_SacrificialShield",  "/cleartarget",            "Target" },
   { "attack",    "Start attack",         I .. "Ability_SteelMelee",              "/startattack",            "Combat" },
   { "sit",       "Sit / stand",          I .. "Spell_Nature_Sleep",              "/sit",                    "General" },
   { "dismount",  "Dismount",             I .. "Ability_Mount_RidingHorse",       "/dismount",               "General" },
   { "roll",      "Roll (1-100)",         I .. "INV_Misc_Bone_HumanSkull_01",     "/roll",                   "Group" },
   { "ready",     "Ready check",          I .. "INV_Misc_Note_01",                "/readycheck",             "Group" },
   { "petattack", "Pet: attack",          I .. "Ability_GhoulFrenzy",             "/petattack",              "Pet" },
   { "petfollow", "Pet: follow",          I .. "Ability_Tracking",                "/petfollow",              "Pet" },
   { "petstay",   "Pet: stay",            I .. "Spell_Nature_TimeStop",           "/petstay",                "Pet" },
   { "petpass",   "Pet: passive",         I .. "Ability_Seal",                    "/petpassive",             "Pet" },
   { "petdef",    "Pet: defensive",       I .. "Ability_Defend",                  "/petdefensive",           "Pet" },
   { "wave",      "Wave",                 I .. "INV_Misc_Toy_10",                 "/wave",                   "Emote" },
   { "bow",       "Bow",                  I .. "Ability_Warrior_BattleShout",     "/bow",                    "Emote" },
   { "cheer",     "Cheer",                I .. "Spell_Holy_Heal",                 "/cheer",                  "Emote" },
   { "thank",     "Thank",                I .. "INV_Misc_Gift_01",                "/thank",                  "Emote" },
   { "dance",     "Dance",                I .. "INV_Misc_Toy_07",                 "/dance",                  "Emote" },
}

function A.CommandEntries()
   local out = {}
   for _, c in ipairs(A.COMMANDS) do
      out[#out + 1] = { kind = "command", id = c[1], name = c[2], icon = c[3], body = c[4], group = c[5] }
   end
   return out
end

-- The macro for a command, made or brought up to date (out of combat); its index.
-- CreateMacro takes the icon's name (no path); a refused icon falls back to
-- the question mark. Errors go to the debug log.
local function IconName(icon)
   return (tostring(icon or ""):gsub("^[Ii]nterface\\[Ii]cons\\", ""))
end

function A.Macro(entry)
   local log = addon.ForeverLog and function(m) addon:ForeverLog("actions: " .. m) end or function() end
   if InCombatLockdown() or not (CreateMacro and GetMacroIndexByName) then log("no macro API / in combat") return nil end
   local name = ("x:" .. entry.name):sub(1, 16)
   local icon = IconName(entry.icon)
   local index = GetMacroIndexByName(name)
   if index and index > 0 then
      local _, _, body = GetMacroInfo(index)
      if body ~= entry.body then pcall(EditMacro, index, name, icon, entry.body) end
      return index
   end
   for _, try in ipairs({ icon, "INV_MISC_QUESTIONMARK", 134400 }) do
      local ok, made = pcall(CreateMacro, name, try, entry.body, false)
      if ok and made and made > 0 then
         log("made " .. name .. " (" .. tostring(made) .. ", icon " .. tostring(try) .. ")")
         return made
      end
      log("CreateMacro " .. name .. " icon " .. tostring(try) .. ": " .. tostring(made))
   end
   local account = GetNumMacros and GetNumMacros() or "?"
   print("|cff66ccffCrossHotbar|r: couldn't make the macro " .. name .. " (general macros in use: " .. tostring(account) .. ").")
   return nil
end

-- Mounts in the mount collection (when there is one): collected, usable here
function A.MountEntries()
   local out = {}
   local journal = C_MountJournal
   if not (journal and journal.GetMountIDs and journal.GetMountInfoByID) then return out end
   for _, id in ipairs(journal.GetMountIDs() or {}) do
      local name, spellID, icon, _, _, _, favorite, _, _, hide, collected = journal.GetMountInfoByID(id)
      if collected and not hide and spellID then
         out[#out + 1] = { kind = "spell", id = spellID, name = name, icon = icon,
                           group = favorite and "Favourite" or "Mount" }
      end
   end
   table.sort(out, function(a, b)
      if (a.group == "Favourite") ~= (b.group == "Favourite") then return a.group == "Favourite" end
      return a.name < b.name
   end)
   if #out > 0 and journal.SummonByID then
      table.insert(out, 1, { kind = "command", id = "randommount", name = "Random favourite mount",
                             icon = I .. "Ability_Mount_RidingHorse", body = "/run C_MountJournal.SummonByID(0)",
                             group = "Mount" })
   end
   return out
end

-- Companion pets in the pet collection (when there is one): owned
function A.PetEntries()
   local out = {}
   local pets = C_PetJournal
   if not (pets and pets.GetNumPets and pets.GetPetInfoByIndex) then return out end
   local _, owned = pets.GetNumPets()
   for i = 1, owned or 0 do
      local petID, _, isOwned, customName, _, favorite, _, speciesName, icon = pets.GetPetInfoByIndex(i)
      if petID and isOwned then
         out[#out + 1] = { kind = "pet", id = petID, name = customName or speciesName or "Pet", icon = icon,
                           group = favorite and "Favourite" or "Pet" }
      end
   end
   table.sort(out, function(a, b) return a.name < b.name end)
   return out
end
