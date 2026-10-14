/*
 * mod-guild-expansion: guild missions.
 *
 * Each guild has one mission board: offers built from templates in the world DB, at a
 * level set by the guild's units. Members send units (and troops) on an offer, optionally
 * with a consumable; the mission runs on a timer (also while offline) and is collected
 * for rewards and unit XP. Offers can be rare and can carry an effect.
 */

#ifndef MOD_GSPE_MISSIONS_H_
#define MOD_GSPE_MISSIONS_H_

#include "Define.h"

#include <string>
#include <unordered_map>
#include <vector>

class Item;
class Player;
struct GuildUnit;

enum MissionType : uint8
{
    MISSION_PATROL    = 0,
    MISSION_GATHERING = 1,
    MISSION_SUPPLY    = 2,
    MISSION_BOUNTY    = 3,
    MISSION_DUNGEON   = 4,
    MISSION_TRAINING  = 5,
    MISSION_RAID      = 7,
};

enum MissionState : uint8
{
    MISSION_STATE_OFFER   = 0,
    MISSION_STATE_RUNNING = 1,
};

// Keep in sync with client_addon/GuildExpansion/Missions.lua.
enum MissionEffect : uint8
{
    MISSION_EFFECT_NONE    = 0,
    MISSION_EFFECT_SLOWING = 1,   // double duration
    MISSION_EFFECT_LETHAL  = 2,   // troops sent die
    MISSION_EFFECT_CURSED  = 3,   // no bonus loot
    MISSION_EFFECT_COSTLY  = 4,   // double supply cost
};

// Kinds of consumable that can be sent with a mission, each with its own effect.
// Keep in sync with client_addon/GuildExpansion/Defs.lua.
enum MissionConsumableKind : uint8
{
    CONSUMABLE_NONE        = 0,
    CONSUMABLE_POTION      = 1,   // +10%
    CONSUMABLE_FLASK       = 2,   // +20%
    CONSUMABLE_ELIXIR      = 3,   // +10%, units gain 25% more XP
    CONSUMABLE_FOOD        = 4,   // +10%, units gain 25% more XP
    CONSUMABLE_BANDAGE     = 5,   // +5%, troops don't lose a use
    CONSUMABLE_ENHANCEMENT = 6,   // +10%, +10 item level for every unit
    CONSUMABLE_SCROLL      = 7,   // +10% on delves and raids, +5% elsewhere
    CONSUMABLE_EXPLOSIVE   = 8,   // counters Siege Engines and Minion Swarm, +5%
    CONSUMABLE_POISON      = 9,   // +10%, +10% bonus loot chance
};

constexpr uint8 MAX_MISSION_UNITS = 3;

struct MissionTemplate
{
    uint16 id = 0;
    uint8 type = MISSION_PATROL;
    std::string name;
    std::string description;
    uint8 slots = 1;
    uint32 minMinutes = 30;
    uint32 maxMinutes = 60;
    std::vector<uint8> threats;
    uint8 threatCount = 0;
    std::vector<uint8> roles;
    uint8 minLevel = 1;
    uint32 weight = 10;
};

struct GuildMission
{
    uint32 id = 0;
    uint32 guildId = 0;
    uint16 templateId = 0;
    uint8 state = MISSION_STATE_OFFER;
    uint8 level = 1;
    std::vector<uint8> threats;
    uint32 duration = 0;    // seconds; for running missions, the actual duration
    uint32 cost = 0;        // supplies
    uint32 gold = 0;        // copper
    uint32 supplies = 0;
    uint32 guildXp = 0;
    uint32 unitXp = 0;
    uint32 item = 0;        // crafting material
    uint32 itemCount = 0;
    uint8 gear = 0;         // gear reward quality, 0 = none
    std::vector<uint32> units;
    uint32 chance = 0;      // 0-200, set when started
    uint32 ends = 0;
    uint32 expires = 0;
    uint8 effect = MISSION_EFFECT_NONE;
    bool rare = false;
    uint8 consumable = CONSUMABLE_NONE;   // running missions
    bool notified = false;  // completion alert sent (memory only)
};

// A consumable sent with a mission, by client bag and slot.
struct MissionConsumable
{
    bool set = false;
    uint8 bag = 0;
    uint8 slot = 0;
};

class MissionMgr
{
public:
    static MissionMgr* instance();

    // Loads templates, the gear reward pool and every running mission.
    void Load();
    // Sends completion alerts for missions that just finished. Call every few seconds.
    void Update();
    void OnGuildDisband(uint32 guildId);

    // Client requests.
    void SendTemplates(Player* player);
    void SendBoard(Player* player);
    void HandlePreview(Player* player, uint32 missionId, std::vector<uint32> const& unitIds, MissionConsumable const& consumable);
    void HandleStart(Player* player, uint32 missionId, std::vector<uint32> const& unitIds, MissionConsumable const& consumable);
    void HandleCollect(Player* player, uint32 missionId);

    // GM helpers.
    void RerollBoard(uint32 guildId);
    void FinishRunning(uint32 guildId);

    // A gear piece of the quality (or lower, if none) for the character, up to the level; 0 if none.
    uint32 RollGear(Player* player, uint8 level, uint8 quality) const;

private:
    MissionMgr() = default;

    struct Chance
    {
        uint32 value = 0;
        uint32 duration = 0;
        uint32 consumableBonus = 0;
        std::vector<uint8> countered;
        std::vector<uint8> missingRoles;
    };

    [[nodiscard]] MissionTemplate const* GetTemplate(uint16 id) const;
    std::vector<GuildMission>& GetMissions(uint32 guildId);
    GuildMission* Find(uint32 guildId, uint32 missionId);
    [[nodiscard]] bool CheckRequest(Player* player);
    void RefillBoard(uint32 guildId, std::vector<GuildMission>& missions);
    bool GenerateOffer(uint32 guildId, std::vector<GuildMission> const& existing, GuildMission& out);
    void SetRewards(GuildMission& mission, MissionTemplate const& tmpl);
    [[nodiscard]] Chance ComputeChance(GuildMission const& mission, std::vector<GuildUnit const*> const& units,
                                       uint8 consumableKind) const;
    bool ResolveUnits(Player* player, GuildMission const& mission, std::vector<uint32> const& unitIds,
                      std::vector<GuildUnit*>& out, bool reportErrors);
    // Kind of the consumable (CONSUMABLE_NONE if none or unsuitable); *item receives the item.
    uint8 ConsumableKind(Player* player, GuildMission const& mission, MissionConsumable const& consumable,
                         Item** item, bool reportErrors) const;
    void Save(GuildMission const& mission);
    void Delete(uint32 missionId);
    void SendMissionLine(Player* player, GuildMission const& mission);

    std::vector<MissionTemplate> _templates;
    std::unordered_map<uint16, std::size_t> _templateIndex;
    std::unordered_map<uint32, std::vector<GuildMission>> _guilds;
    std::vector<uint32> _gearPool;
    uint32 _nextId = 1;
};

#define sMissionMgr MissionMgr::instance()

#endif
