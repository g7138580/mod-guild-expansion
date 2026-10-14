/*
 * mod-guild-expansion: work orders.
 *
 * Each character gets a few orders matched to its professions: crafting orders for
 * recipes it knows (preferring ones that still give skill-ups) and provisioning
 * orders for gathered materials around its level. Items are placed into an order
 * from the add-on; turning in destroys exactly the placed items and pays gold,
 * guild XP and guild supplies.
 */

#ifndef MOD_GSPE_WORK_ORDERS_H_
#define MOD_GSPE_WORK_ORDERS_H_

#include "Define.h"
#include "ObjectGuid.h"

#include <string_view>
#include <unordered_map>
#include <vector>

class Player;

enum WorkOrderKind : uint8
{
    WORK_ORDER_CRAFT  = 0,
    WORK_ORDER_GATHER = 1,
};

struct WorkOrder
{
    uint32 id = 0;
    uint8 kind = WORK_ORDER_CRAFT;
    uint16 skill = 0;       // 0 = anyone (cloth)
    uint32 spell = 0;       // recipe, craft orders only
    uint32 item = 0;        // 0 = placeholder for an abandoned order; a new one arrives at `expires`
    uint16 quantity = 0;
    uint8 level = 1;
    uint32 gold = 0;        // copper
    uint32 supplies = 0;
    uint32 guildXp = 0;
    uint32 expires = 0;     // unix time
};

class WorkOrderMgr
{
public:
    static WorkOrderMgr* instance();

    // Builds the recipe and material tables. Call once DBCs, spells and items are loaded.
    void BuildCatalog();

    void OnLogout(Player* player);

    // Client requests (after "GSPE\t").
    void SendOrders(Player* player);
    void HandlePlace(Player* player, uint32 orderId, uint8 clientBag, uint8 clientSlot);
    void HandleClear(Player* player, uint32 orderId);
    void HandleFill(Player* player, uint32 orderId);
    void HandleTurnIn(Player* player, uint32 orderId);
    void HandleAbandon(Player* player, uint32 orderId);

    // GM: drop all of a character's orders and generate new ones.
    void ResetOrders(Player* player);

    // A random gathered material suited to the level, from one gathering skill or from any
    // (skill = ANY_SKILL); 0 if none.
    static constexpr uint16 ANY_SKILL = 0xFFFF;
    [[nodiscard]] uint32 RandomMaterial(uint8 level, uint16 skill = ANY_SKILL) const;

    // The profession whose recipes create this item, or 0.
    [[nodiscard]] uint16 CraftedBy(uint32 item) const;

private:
    WorkOrderMgr() = default;

    struct CraftRecipe
    {
        uint32 spell;
        uint32 item;
        uint32 createCount;
        uint32 minRank;
        uint32 yellowAt;
        uint32 grayAt;
        uint32 reagentValue;   // vendor value of one craft's reagents, copper
    };

    struct GatherItem
    {
        uint32 item;
        uint32 itemLevel;
    };

    struct Placement
    {
        ObjectGuid item;
        uint32 count;
    };

    struct CharacterOrders
    {
        std::vector<WorkOrder> orders;
        std::unordered_map<uint32, std::vector<Placement>> placements;
    };

    CharacterOrders* GetOrders(Player* player);
    WorkOrder* FindOrder(CharacterOrders& co, uint32 orderId);
    void Refill(Player* player, CharacterOrders& co);
    bool Generate(Player* player, CharacterOrders const& co, WorkOrder& out);
    bool GenerateCraft(Player* player, uint16 skill, WorkOrder& out);
    bool GenerateGather(Player* player, uint16 skill, WorkOrder& out);
    void SetRewards(Player* player, WorkOrder& order, uint32 materialValue);
    void Insert(Player* player, WorkOrder const& order);
    void Remove(CharacterOrders& co, uint32 orderId);

    // Drops placements whose item moved out of the bags, changed or shrank; returns the placed total.
    uint32 ValidatePlacements(Player* player, WorkOrder const& order, std::vector<Placement>& placed);
    void ForgetItemElsewhere(CharacterOrders& co, uint32 keepOrderId, ObjectGuid item);
    void SendPlaced(Player* player, uint32 orderId, uint32 total);
    void SendOrderLine(Player* player, WorkOrder const& order, uint32 placed);
    [[nodiscard]] bool CheckRequest(Player* player);

    std::unordered_map<uint16, std::vector<CraftRecipe>> _recipesBySkill;
    std::unordered_map<uint16, std::vector<GatherItem>> _gatherBySkill;
    std::unordered_map<uint32, uint16> _craftedBy;
    std::unordered_map<ObjectGuid::LowType, CharacterOrders> _characters;
    uint32 _nextId = 1;
};

#define sWorkOrderMgr WorkOrderMgr::instance()

#endif
