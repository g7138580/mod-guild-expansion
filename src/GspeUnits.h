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

struct UnitTemplate
{
    uint16 id = 0;
    uint8 kind = 0;                 // 0 hero, 1 specialist, 2 troop
    std::string name;
    std::vector<uint8> races;
    uint8 classId = 0;
    uint8 role = UNIT_ROLE_DAMAGE;
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
    // Adds XP, levelling the unit up to the cap. Returns the number of levels gained.
    uint32 AddXp(GuildUnit& unit, uint32 xp, uint8 cap);

    [[nodiscard]] static uint32 XpForNextLevel(uint8 level);
    [[nodiscard]] static uint16 ItemLevelForLevel(uint8 level);

    // Client requests.
    void SendTemplates(Player* player);
    void SendUnits(Player* player);
    void HandleRecruit(Player* player, uint32 candidateId);
    void HandleDismiss(Player* player, uint32 unitId);
    void HandleTrainTroop(Player* player, uint16 templateId);

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
    [[nodiscard]] uint8 RollQuality() const;
    [[nodiscard]] uint32 RecruitCost(uint8 quality) const;
    std::string PickName(uint8 race, uint8 gender, std::vector<GuildUnit> const& existing) const;
    void DeleteUnit(uint32 unitId);
    void SendUnitLine(Player* player, GuildUnit const& unit);

    std::vector<UnitTemplate> _templates;
    std::unordered_map<uint16, std::size_t> _templateIndex;
    std::map<std::pair<uint8, uint8>, std::vector<std::string>> _names;
    std::unordered_map<uint32, std::vector<GuildUnit>> _guilds;
    uint32 _nextId = 1;
};

#define sUnitMgr UnitMgr::instance()

#endif
