/*
 * mod-guild-expansion: the guild quartermaster.
 *
 * Sells items and services for guild supplies from anywhere through the add-on. The fixed
 * stock lives in the world DB (mod_gspe_qm_stock); rows unlock with guild level and are
 * shown only to characters in their level range, which is how consumable tiers work.
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

private:
    QuartermasterMgr() = default;

    [[nodiscard]] bool CheckRequest(Player* player);
    [[nodiscard]] QuartermasterRow const* FindRow(uint16 id) const;
    [[nodiscard]] uint8 RowState(Player* player, QuartermasterRow const& row, uint8 guildLevel);
    [[nodiscard]] bool ServiceAvailable(Player* player, uint8 service) const;
    void RunService(Player* player, uint8 service);
    std::unordered_map<uint16, uint16>& Purchases(Player* player);

    std::vector<QuartermasterRow> _stock;
    std::unordered_map<ObjectGuid::LowType, std::unordered_map<uint16, uint16>> _purchases;
};

#define sQuartermasterMgr QuartermasterMgr::instance()

#endif
