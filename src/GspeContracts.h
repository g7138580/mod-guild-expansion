/*
 * mod-guild-expansion: daily guild contracts.
 *
 * Each character gets a few contracts a day ("Slay 25 Undead", "Complete 5 quests",
 * "Win a battleground" and so on), counted from normal play. A finished contract pays
 * out right away; finishing all of the day's contracts also pays a bonus cache.
 * Contracts are replaced at the server's daily quest reset.
 */

#ifndef MOD_GSPE_CONTRACTS_H_
#define MOD_GSPE_CONTRACTS_H_

#include "Define.h"
#include "ObjectGuid.h"

#include <array>
#include <ctime>
#include <string>
#include <unordered_map>
#include <vector>

class Battleground;
class Creature;
class Player;
class Quest;

// Keep in sync with client_addon/GuildExpansion/Contracts.lua.
enum ContractKind : uint8
{
    CONTRACT_NONE         = 0,
    CONTRACT_SLAY_TYPE    = 1,   // target: creature type
    CONTRACT_SLAY_ELITE   = 2,
    CONTRACT_QUESTS       = 3,
    CONTRACT_GATHER       = 4,   // target: gathering skill
    CONTRACT_FISH         = 5,
    CONTRACT_DUNGEON_BOSS = 6,
    CONTRACT_BG_COMPLETE  = 7,
    CONTRACT_BG_WIN       = 8,
    CONTRACT_HONOR_KILLS  = 9,
};

struct Contract
{
    uint8 slot = 0;
    uint8 kind = CONTRACT_NONE;
    uint32 target = 0;
    uint16 needed = 1;
    uint16 progress = 0;
    uint8 level = 1;
    uint32 gold = 0;        // copper
    uint32 supplies = 0;
    uint32 guildXp = 0;
    bool done = false;
};

class ContractMgr
{
public:
    static ContractMgr* instance();

    // Builds the creature-type tables from the world's spawns. Call once at startup.
    void BuildCatalog();

    void OnLogout(Player* player);

    // Progress from normal play.
    void OnKillCredit(Player* player, Creature* creature);
    void OnQuestRewarded(Player* player, Quest const* quest);
    void OnGather(Player* player, uint32 skillId);
    void OnLoot(Player* player, ObjectGuid lootGuid);
    void OnHonorableKill(Player* player);
    void OnBattlegroundEnd(Player* player, Battleground* bg, bool won);

    // Client requests.
    void SendContracts(Player* player);
    void HandleReroll(Player* player, uint8 slot);

    // Quartermaster service: one more reroll today.
    void AddReroll(Player* player);
    // GM helpers: replace the character's contracts; finish one.
    void ResetContracts(Player* player);
    void FinishContract(Player* player, uint8 slot);

private:
    ContractMgr() = default;

    struct CharacterContracts
    {
        uint32 day = 0;             // NextDailyReset() when rolled
        std::vector<Contract> contracts;
        uint8 rerollsUsed = 0;
        uint8 extraRerolls = 0;
        bool bonusPaid = false;
    };

    [[nodiscard]] bool CheckRequest(Player* player);
    // The character's contracts for today, rolled if needed; null for characters without contracts.
    CharacterContracts* Get(Player* player);
    void Roll(Player* player, CharacterContracts& cc);
    bool Generate(Player* player, CharacterContracts const& cc, Contract& out);
    void SetRewards(Player* player, Contract& c);
    void Save(Player* player, Contract const& c);
    void SaveDay(Player* player, CharacterContracts const& cc);
    void Advance(Player* player, uint8 kind, uint32 target, uint16 amount = 1);
    void Complete(Player* player, CharacterContracts& cc, Contract& c);
    void PayBonus(Player* player, CharacterContracts& cc);
    void SendLine(Player* player, Contract const& c);

    [[nodiscard]] std::string Title(Contract const& c) const;
    [[nodiscard]] std::string Label(Contract const& c) const;

    // Spawn counts of normal and elite creatures per creature type and level.
    static constexpr uint8 MAX_LEVEL = 83;
    static constexpr uint8 CREATURE_TYPES = 11;
    std::array<std::array<uint32, MAX_LEVEL + 1>, CREATURE_TYPES> _normalSpawns{};
    std::array<uint32, MAX_LEVEL + 1> _eliteSpawns{};

    std::unordered_map<ObjectGuid::LowType, CharacterContracts> _characters;
    // Last fishing loot counted per character, so a catch with several items counts once.
    struct FishLoot
    {
        ObjectGuid guid;
        time_t at = 0;
    };
    std::unordered_map<ObjectGuid::LowType, FishLoot> _lastFishLoot;
};

#define sContractMgr ContractMgr::instance()

#endif
