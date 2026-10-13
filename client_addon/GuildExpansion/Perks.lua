--[[ Guild Expansion: perk list. Keep in sync with src/GspePerks.h and the .conf defaults. ]]

local GE = GuildExpansion

-- use: request sent to the server for perks that are used rather than passive.
GE.PERKS = {
    { lv = 2,  name = "Fast Track (Rank 1)",        icon = "Ability_Rogue_Sprint",
      desc = "+5% experience from killing monsters and completing quests." },
    { lv = 3,  name = "Hasty Hearth",               icon = "INV_Misc_Rune_01",
      desc = "Hearthstone cooldown reduced by 15 minutes." },
    { lv = 6,  name = "Mr. Popularity (Rank 1)",    icon = "Achievement_Reputation_01",
      desc = "+5% reputation from killing monsters and completing quests." },
    { lv = 7,  name = "The Quick and the Dead",     icon = "Spell_Holy_GuardianSpirit",
      desc = "+50% movement speed while dead, and you return to life with full health and mana." },
    { lv = 8,  name = "Cash Flow (Rank 1)",         icon = "INV_Misc_Coin_02",
      desc = "An extra 5% of the money you loot from enemies is deposited into the guild bank." },
    { lv = 9,  name = "Mount Up",                   icon = "Ability_Mount_RidingHorse",
      desc = "+10% mounted movement speed." },
    { lv = 11, name = "Discount Repairs (Rank 1)",  icon = "Trade_BlackSmithing",
      desc = "Repairs cost 10% less." },
    { lv = 12, name = "Fast Track (Rank 2)",        icon = "Ability_Rogue_Sprint",
      desc = "Experience bonus increased to +10%." },
    { lv = 13, name = "Chug-A-Lug (Rank 1)",        icon = "INV_Potion_41",
      desc = "Elixirs and flasks last 50% longer." },
    { lv = 14, name = "Cash Flow (Rank 2)",         icon = "INV_Misc_Coin_02",
      desc = "Guild bank deposit increased to 10% of looted money." },
    { lv = 16, name = "Reinforce",                  icon = "INV_Shield_06",
      desc = "Durability lost on death is reduced by 20%." },
    { lv = 17, name = "Mr. Popularity (Rank 2)",    icon = "Achievement_Reputation_01",
      desc = "Reputation bonus increased to +10%." },
    { lv = 18, name = "Honorable Mention",          icon = "INV_BannerPVP_02",
      desc = "+10% honor from PvP kills." },
    { lv = 19, name = "Working Overtime",           icon = "Trade_Engineering",
      desc = "10% chance to gain an extra point when a profession skill increases." },
    { lv = 20, name = "Mobile Banking",             icon = "INV_Misc_Bag_10",
      desc = "Summons a guild bank next to you for 1 minute. Not usable in combat.",
      use = "BANK" },
    { lv = 21, name = "Discount Repairs (Rank 2)",  icon = "Trade_BlackSmithing",
      desc = "Repairs cost 20% less." },
    { lv = 24, name = "Chug-A-Lug (Rank 2)",        icon = "INV_Potion_41",
      desc = "Elixirs and flasks last twice as long." },
}

function GE.IconPath(perk)
    return "Interface\\Icons\\" .. perk.icon
end

-- Perks unlocked by going from oldLevel to newLevel.
function GE.PerksBetween(oldLevel, newLevel)
    local out = {}
    for _, perk in ipairs(GE.PERKS) do
        if perk.lv > oldLevel and perk.lv <= newLevel then
            out[#out + 1] = perk
        end
    end
    return out
end

function GE.NextPerk(level)
    for _, perk in ipairs(GE.PERKS) do
        if perk.lv > level then
            return perk
        end
    end
    return nil
end
