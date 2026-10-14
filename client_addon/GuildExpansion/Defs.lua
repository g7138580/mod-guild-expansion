--[[ Guild Expansion: unit abilities, traits, races and roles. Keep ids in sync with src/GspeUnits.h. ]]

local GE = GuildExpansion

-- Ability N counters mission threat N.
GE.ABILITIES = {
    [1]  = { name = "Beast Lore",  threat = "Wild Beasts",     icon = "Ability_Hunter_BeastTaming" },
    [2]  = { name = "Purify",      threat = "Unholy Curse",    icon = "Spell_Holy_Purify" },
    [3]  = { name = "Banish",      threat = "Fel Corruption",  icon = "Spell_Shadow_Cripple" },
    [4]  = { name = "Ward",        threat = "Elemental Fury",  icon = "Spell_Frost_FrostWard" },
    [5]  = { name = "Vigilance",   threat = "Ambush",          icon = "Ability_Warrior_Vigilance" },
    [6]  = { name = "Sabotage",    threat = "Siege Engines",   icon = "INV_Misc_Bomb_04" },
    [7]  = { name = "Shield Wall", threat = "Massive Strike",  icon = "Ability_Warrior_ShieldWall" },
    [8]  = { name = "Area Attack", threat = "Minion Swarm",    icon = "Ability_Whirlwind" },
    [9]  = { name = "Interrupt",   threat = "Powerful Caster", icon = "Ability_Kick" },
    [10] = { name = "Healing",     threat = "Grievous Wounds", icon = "Spell_Holy_Heal" },
}

GE.TRAITS = {
    [1]  = { name = "Quick Study",     icon = "INV_Misc_Book_09",        desc = "Gains 50% more experience." },
    [2]  = { name = "Hardy",           icon = "Spell_Holy_DevotionAura", desc = "Missions with this unit take 25% less time." },
    [3]  = { name = "Scavenger",       icon = "INV_Misc_Coin_05",        desc = "Missions with this unit bring back 25% more gold." },
    [4]  = { name = "Lucky",           icon = "INV_Misc_Gem_Pearl_04",   desc = "+10% chance of bonus rewards." },
    [5]  = { name = "Herbalist",       icon = "INV_Misc_Flower_02",      desc = "Brings back extra herbs." },
    [6]  = { name = "Prospector",      icon = "INV_Pick_02",             desc = "Brings back extra ore and stone." },
    [7]  = { name = "Skinner",         icon = "INV_Misc_Pelt_Wolf_01",   desc = "Brings back extra leather." },
    [8]  = { name = "Treasure Hunter", icon = "INV_Box_02",              desc = "25% chance of an extra piece of gear from a successful mission." },
    [9]  = { name = "Field Medic",     icon = "INV_Misc_Bandage_15",     desc = "Troops on missions with this unit don't lose vitality." },
    [10] = { name = "Supply Sergeant", icon = "INV_Crate_01",            desc = "Missions with this unit bring back 25% more supplies." },
}

GE.RACES = {
    [1] = "Human", [2] = "Orc", [3] = "Dwarf", [4] = "Night Elf", [5] = "Undead", [6] = "Tauren",
    [7] = "Gnome", [8] = "Troll", [9] = "Goblin", [10] = "Blood Elf", [11] = "Draenei",
}

GE.ROLES = {
    [0] = { name = "Tank",   lfg = "TANK" },
    [1] = { name = "Healer", lfg = "HEALER" },
    [2] = { name = "Damage", lfg = "DAMAGER" },
}

GE.QUALITY_NAMES = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic" }

GE.ARMOR_NAMES = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }

-- Consumables sent with a mission. Keep in sync with MissionConsumableKind in src/GspeMissions.h.
GE.CONSUMABLES = {
    [1] = { name = "Potion",      desc = "+10% success" },
    [2] = { name = "Flask",       desc = "+20% success" },
    [3] = { name = "Elixir",      desc = "+10% success, units gain 25% more XP" },
    [4] = { name = "Food",        desc = "+10% success, units gain 25% more XP" },
    [5] = { name = "Bandage",     desc = "+5% success, troops don't lose a use" },
    [6] = { name = "Enhancement", desc = "+10% success, +10 item level for every unit" },
    [7] = { name = "Scroll",      desc = "+10% success on delves and raids, +5% elsewhere" },
    [8] = { name = "Explosive",   desc = "Counters Siege Engines and Minion Swarm, +5% success" },
    [9] = { name = "Poison",      desc = "+10% success, +10% bonus loot chance" },
}

-- Effect-slot items, by the profession that made them. Keep in sync with UnitEffect in src/GspeUnits.h.
GE.UNIT_EFFECTS = {
    [1] = { name = "Engineering",    desc = "Counters Siege Engines" },
    [2] = { name = "Jewelcrafting",  desc = "+5% success on every mission" },
    [3] = { name = "Alchemy",        desc = "Missions 15% shorter" },
    [4] = { name = "Inscription",    desc = "+10% success on delves and raids" },
    [5] = { name = "Tailoring",      desc = "+25% crafting materials from missions" },
    [6] = { name = "Leatherworking", desc = "Troops sent with this unit survive lethal missions" },
    [7] = { name = "Accessory",      desc = "+3% success on every mission" },
}

-- r, g, b only (GetItemQualityColor also returns a hex string, which SetVertexColor can't take).
function GE.QualityRGB(quality)
    local r, g, b = GetItemQualityColor(quality or 2)
    return r, g, b
end

function GE.QualityHex(quality)
    local r, g, b = GetItemQualityColor(quality or 2)
    return string.format("%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

-- Sets a texture to the LFG role icon if the client has it.
function GE.SetRoleIcon(texture, role)
    local info = GE.ROLES[role]
    if info and GetTexCoordsForRole then
        texture:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
        texture:SetTexCoord(GetTexCoordsForRole(info.lfg))
        texture:Show()
    else
        texture:Hide()
    end
end

-- "Dwarf Warrior" for heroes, "Gnomish Engineer" for specialists.
function GE.UnitDescription(unit)
    local tmpl = GE.unitTemplates[unit.template]
    if not tmpl then
        return GE.RACES[unit.race] or ""
    end
    if tmpl.kind == 0 then
        return (GE.RACES[unit.race] or "") .. " " .. tmpl.name
    end
    return tmpl.name
end
