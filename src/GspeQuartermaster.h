/*
 * mod-guild-expansion: the guild quartermaster.
 *
 * Sells items and services for guild supplies from anywhere through the add-on. The fixed
 * stock lives in the world DB (mod_gspe_qm_stock); rows unlock with guild level and are
 * shown only to characters in their level range, which is how consumable tiers work.
 *
 * The weekly stock changes at the server's weekly reset: two gear pieces rolled for each
 * character, and a material, two recipes and a pet or mount shared by the guild (each
 * shared offer can be bought once).
 */

#ifndef MOD_GSPE_QUARTERMASTER_H_
#define MOD_GSPE_QUARTERMASTER_H_

#include "Define.h"
#include "ObjectGuid.h"

#include <unordered_map>
#include <vector>

class Player;

enum QuartermasterCategory : uint8
{
    QM_CATEGORY_BAGS        = 1,
    QM_CATEGORY_TOOLS       = 2,
    QM_CATEGORY_CONSUMABLES = 3,
    QM_CATEGORY_SERVICES    = 4,
};

// Keep in sync with client_addon/GuildExpansion/Quartermaster.lua.
enum QuartermasterService : uint8
{
    QM_SERVICE_NONE           = 0,
    QM_SERVICE_RECRUITS       = 1,   // reroll recruit candidates
    QM_SERVICE_MISSION_BOARD  = 2,   // reroll the mission board
    QM_SERVICE_WORK_ORDER     = 3,   // replace an abandoned work order now
    QM_SERVICE_CONTRACT       = 4,   // one more contract reroll today
};

// Why a row can't be bought right now. Keep in sync with Quartermaster.lua.
enum QuartermasterRowState : uint8
{
    QM_ROW_OK          = 0,
    QM_ROW_LOCKED      = 1,   // guild level too low
    QM_ROW_UNUSABLE    = 2,   // the character can't use the item
    QM_ROW_LIMIT       = 3,   // per-character limit reached
    QM_ROW_UNAVAILABLE = 4,   // service has nothing to do right now
    QM_ROW_KNOWN       = 5,   // recipe, pet or mount already learned
    QM_ROW_SOLD        = 6,   // weekly offer already bought
    QM_ROW_EMPTY       = 7,   // nothing in this weekly slot
};

// Keep in sync with Quartermaster.lua.
enum QuartermasterWeeklySlot : uint8
{
    QM_WEEKLY_GEAR_1    = 1,
    QM_WEEKLY_GEAR_2    = 2,
    QM_WEEKLY_MATERIAL  = 3,
    QM_WEEKLY_RECIPE_1  = 4,
    QM_WEEKLY_RECIPE_2  = 5,
    QM_WEEKLY_CURIOSITY = 6,
};

struct WeeklyOffer
{
    uint8 slot = 0;
    uint32 item = 0;            // 0 = nothing this week
    uint16 count = 1;
    uint32 cost = 0;
    int32 randomProperty = 0;   // gear only
    uint32 boughtBy = 0;        // character that bought it, 0 = for sale
};

struct QuartermasterRow
{
    uint16 id = 0;
    uint8 category = QM_CATEGORY_BAGS;
    uint32 item = 0;
    uint16 count = 1;
    uint8 service = QM_SERVICE_NONE;
    uint32 cost = 0;
    uint8 guildLevel = 1;
    uint8 minLevel = 1;
    uint8 maxLevel = 255;
    uint16 charLimit = 0;
};

class QuartermasterMgr
{
public:
    static QuartermasterMgr* instance();

    void Load();
    void OnLogout(Player* player);

    // Client requests.
    void SendStock(Player* player);
    void HandleBuy(Player* player, uint16 rowId);
    void HandleBuyWeekly(Player* player, uint8 slot);

    void OnGuildDisband(uint32 guildId);
    // GM: roll the guild's weekly stock and the character's weekly gear again.
    void RerollWeekly(Player* player);

private:
    QuartermasterMgr() = default;

    [[nodiscard]] bool CheckRequest(Player* player);
    [[nodiscard]] QuartermasterRow const* FindRow(uint16 id) const;
    [[nodiscard]] uint8 RowState(Player* player, QuartermasterRow const& row, uint8 guildLevel);
    [[nodiscard]] bool ServiceAvailable(Player* player, uint8 service) const;
    void RunService(Player* player, uint8 service);
    std::unordered_map<uint16, uint16>& Purchases(Player* player);

    struct Material
    {
        uint32 item;
        uint8 minLevel;
        uint8 maxLevel;
        uint16 count;
        uint32 cost;
    };

    struct Curiosity
    {
        uint32 item;
        uint8 kind;         // 1 pet, 2 mount
        uint8 guildLevel;
        uint32 cost;
        uint32 weight;
    };

    struct Weekly
    {
        uint32 week = 0;    // NextWeeklyReset() when rolled
        std::vector<WeeklyOffer> offers;
    };

    void LoadWeeklyPools();
    // The guild's shared offers / the character's gear for this week, rolled if needed.
    Weekly& GuildWeekly(uint32 guildId);
    Weekly& CharacterWeekly(Player* player);
    void RollGuildWeekly(uint32 guildId, Weekly& weekly);
    void RollCharacterWeekly(Player* player, Weekly& weekly);
    [[nodiscard]] WeeklyOffer RollGear(Player* player, uint8 slot, uint32 exclude) const;
    void RollRecipes(uint32 guildId, Weekly& weekly) const;
    [[nodiscard]] WeeklyOffer RollCuriosity(uint32 guildId) const;
    void SaveGuildOffer(uint32 guildId, uint32 week, WeeklyOffer const& offer);
    void SaveGearOffer(Player* player, uint32 week, WeeklyOffer const& offer);
    [[nodiscard]] uint8 WeeklyState(Player* player, WeeklyOffer const& offer) const;
    void SendWeeklyLine(Player* player, WeeklyOffer const& offer);

    std::vector<QuartermasterRow> _stock;
    std::unordered_map<ObjectGuid::LowType, std::unordered_map<uint16, uint16>> _purchases;

    std::vector<uint32> _gearPool;
    std::vector<uint32> _recipePool;
    std::vector<Material> _materials;
    std::vector<Curiosity> _curiosities;
    std::unordered_map<uint32, Weekly> _guildWeekly;
    std::unordered_map<ObjectGuid::LowType, Weekly> _characterWeekly;
};

#define sQuartermasterMgr QuartermasterMgr::instance()

#endif
