/*
 * mod-guild-expansion: guild units (champions).
 *
 * Units belong to a guild and are sent on missions. Each comes from a template in the
 * world DB: a hero (race + class) or a specialist (e.g. Gnomish Engineer). Units have a
 * quality, level, XP, item level, abilities (which counter mission threats) and traits.
 * Recruit candidates are stored as units with status UNIT_STATUS_CANDIDATE.
 */

#ifndef MOD_GSPE_UNITS_H_
#define MOD_GSPE_UNITS_H_

#include "Define.h"

#include <map>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

class Player;

enum UnitRole : uint8
{
    UNIT_ROLE_TANK   = 0,
    UNIT_ROLE_HEALER = 1,
    UNIT_ROLE_DAMAGE = 2,
};

enum UnitStatus : uint8
{
    UNIT_STATUS_IDLE       = 0,
    UNIT_STATUS_ON_MISSION = 1,
    UNIT_STATUS_CANDIDATE  = 2,
};

enum UnitQuality : uint8
{
    UNIT_QUALITY_UNCOMMON = 2,
    UNIT_QUALITY_RARE     = 3,
    UNIT_QUALITY_EPIC     = 4,
};

// Ability ids 1..UNIT_ABILITY_COUNT; ability N counters mission threat N.
// Keep in sync with client_addon/GuildExpansion/Defs.lua.
constexpr uint8 UNIT_ABILITY_COUNT = 10;

// Trait ids. Keep in sync with client_addon/GuildExpansion/Defs.lua.
enum UnitTrait : uint8
{
    TRAIT_QUICK_STUDY     = 1,   // +50% unit XP
    TRAIT_HARDY           = 2,   // missions 25% shorter
    TRAIT_SCAVENGER       = 3,   // +25% gold
    TRAIT_LUCKY           = 4,   // +10% bonus loot chance
    TRAIT_HERBALIST       = 5,   // extra herbs
    TRAIT_PROSPECTOR      = 6,   // extra ore and stone
    TRAIT_SKINNER         = 7,   // extra leather
    TRAIT_TREASURE_HUNTER = 8,   // chance of extra gear
    TRAIT_FIELD_MEDIC     = 9,   // troops don't lose vitality
    TRAIT_SUPPLY_SERGEANT = 10,  // +25% supplies
};
constexpr uint8 UNIT_TRAIT_COUNT = 10;
constexpr uint8 UNIT_MAX_LEVEL = 80;
constexpr uint8 UNIT_KIND_TROOP = 2;
// Missions a new troop can go on before it wears out.
constexpr uint8 TROOP_VITALITY = 2;

// Gear can raise a unit's item level at most this far above normal for its level.
constexpr uint16 UNIT_GEAR_ILVL_ALLOWANCE = 20;

// Effect of the item in a unit's effect slot, by the profession that made it.
// Keep in sync with client_addon/GuildExpansion/Defs.lua.
enum UnitEffect : uint8
{
    UNIT_EFFECT_NONE           = 0,
    UNIT_EFFECT_ENGINEERING    = 1,   // counters Siege Engines
    UNIT_EFFECT_JEWELCRAFTING  = 2,   // +5% success
    UNIT_EFFECT_ALCHEMY        = 3,   // missions 15% shorter
    UNIT_EFFECT_INSCRIPTION    = 4,   // +10% success on delves and raids
    UNIT_EFFECT_TAILORING      = 5,   // +25% crafting materials
    UNIT_EFFECT_LEATHERWORKING = 6,   // troops survive lethal missions
    UNIT_EFFECT_ACCESSORY      = 7,   // any other trinket, ring or necklace: +3% success
};

// Which slot an item is given to.
enum UnitGearSlot : uint8
{
    UNIT_GEAR_WEAPON = 0,
    UNIT_GEAR_ARMOR  = 1,
    UNIT_GEAR_EFFECT = 2,
};

struct UnitXpResult
{
    uint32 levels = 0;
    uint32 promotions = 0;
};

struct UnitTemplate
{
    uint16 id = 0;
    uint8 kind = 0;                 // 0 hero, 1 specialist, 2 troop
    std::string name;
    std::vector<uint8> races;
    uint8 classId = 0;
    uint8 role = UNIT_ROLE_DAMAGE;
    uint8 armor = 0;                // armor subclass it can wear: 1 cloth .. 4 plate, 0 none
    std::vector<uint8> abilities;
    std::vector<uint8> traits;      // empty = any
    std::string icon;
    uint32 weight = 10;
};

struct GuildUnit
{
    uint32 id = 0;
    uint32 guildId = 0;
    uint16 templateId = 0;
    std::string name;
    uint8 race = 0;
    uint8 gender = 0;
    uint8 quality = UNIT_QUALITY_UNCOMMON;
    uint8 level = 1;
    uint32 xp = 0;
    uint16 itemLevel = 0;
    uint8 abilities[2] = { 0, 0 };
    uint8 traits[2] = { 0, 0 };
    uint8 status = UNIT_STATUS_IDLE;
    uint32 mission = 0;
    uint32 cost = 0;                // candidates only
    uint32 expires = 0;             // candidates only
    uint8 vitality = 0;             // troops only: missions left
    uint32 weaponItem = 0;
    uint16 weaponIlvl = 0;
    uint32 armorItem = 0;
    uint16 armorIlvl = 0;
    uint32 effectItem = 0;
    uint8 effectKind = UNIT_EFFECT_NONE;
    uint32 promoXp = 0;             // XP earned at the level cap toward the next quality
};

class UnitMgr
{
public:
    static UnitMgr* instance();

    void LoadTemplates();
    [[nodiscard]] UnitTemplate const* GetTemplate(uint16 id) const;

    // The guild's units and recruit candidates, loaded on first use.
    std::vector<GuildUnit>& GetUnits(uint32 guildId);
    GuildUnit* FindUnit(uint32 guildId, uint32 unitId);
    void SaveUnit(GuildUnit const& unit);
    // Deletes a unit or troop (dismissed, or a troop that died or wore out).
    void RemoveUnit(uint32 guildId, uint32 unitId);
    void OnGuildDisband(uint32 guildId);

    [[nodiscard]] bool IsTroop(GuildUnit const& unit) const;

    // Highest character level among the guild's members; units can't level past it.
    [[nodiscard]] uint8 LevelCap(uint32 guildId);
    // Adds XP, levelling the unit up to the cap; XP past the cap counts toward promotions.
    UnitXpResult AddXp(GuildUnit& unit, uint32 xp, uint8 cap);
    // XP needed at the level cap for the next quality, 0 at epic.
    [[nodiscard]] static uint32 PromotionXp(GuildUnit const& unit);
    // Item level from the unit's level and gear.
    static void RecalcItemLevel(GuildUnit& unit);

    [[nodiscard]] static uint32 XpForNextLevel(uint8 level);
    [[nodiscard]] static uint16 ItemLevelForLevel(uint8 level);

    // Client requests.
    void SendTemplates(Player* player);
    void SendUnits(Player* player);
    void HandleRecruit(Player* player, uint32 candidateId);
    void HandleDismiss(Player* player, uint32 unitId);
    void HandleTrainTroop(Player* player, uint16 templateId);
    void HandleEquip(Player* player, uint32 unitId, uint8 gearSlot, uint8 clientBag, uint8 clientSlot);

    // GM: replace the guild's recruit candidates now.
    void RerollCandidates(uint32 guildId);

private:
    UnitMgr() = default;

    [[nodiscard]] bool CheckRequest(Player* player);
    void EnsureStarterUnits(uint32 guildId, std::vector<GuildUnit>& units);
    void RefreshCandidates(uint32 guildId, std::vector<GuildUnit>& units, bool force);
    UnitTemplate const* PickTemplate(int8 role) const;
    GuildUnit RollUnit(uint32 guildId, UnitTemplate const& tmpl, uint8 quality, uint8 level,
                       std::vector<GuildUnit> const& existing);
    [[nodiscard]] uint8 RollQuality(uint32 guildId) const;
    [[nodiscard]] uint32 RecruitCost(uint8 quality) const;
    std::string PickName(uint8 race, uint8 gender, std::vector<GuildUnit> const& existing) const;
    void DeleteUnit(uint32 unitId);
    void SendUnitLine(Player* player, GuildUnit const& unit);
    void Promote(GuildUnit& unit);
    [[nodiscard]] uint8 EffectKindFor(struct ItemTemplate const* proto) const;

    std::vector<UnitTemplate> _templates;
    std::unordered_map<uint16, std::size_t> _templateIndex;
    std::map<std::pair<uint8, uint8>, std::vector<std::string>> _names;
    std::unordered_map<uint32, std::vector<GuildUnit>> _guilds;
    uint32 _nextId = 1;
};

#define sUnitMgr UnitMgr::instance()

#endif
