/*
 * mod-guild-expansion: item helpers shared by missions, contracts and the quartermaster.
 */

#include "GspeItems.h"

#include "Chat.h"
#include "DatabaseEnv.h"
#include "Item.h"
#include "Mail.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "World.h"

#include <algorithm>

namespace GspeItems
{
void GiveItem(Player* player, uint32 itemId, uint32 count, std::string const& mailSubject, int32 randomProperty)
{
    ItemTemplate const* proto = sObjectMgr->GetItemTemplate(itemId);
    if (!proto || !count)
        return;

    uint32 const stack = std::max<uint32>(1, proto->GetMaxStackSize());
    while (count)
    {
        uint32 const n = std::min(count, stack);
        count -= n;

        int32 const property = randomProperty ? randomProperty : Item::GenerateItemRandomPropertyId(itemId);
        ItemPosCountVec dest;
        if (player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, itemId, n) == EQUIP_ERR_OK)
        {
            if (Item* item = player->StoreNewItem(dest, itemId, true, property))
                player->SendNewItem(item, n, true, false);
            continue;
        }

        if (Item* item = Item::CreateItem(itemId, n, player, false, property))
        {
            CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
            item->SaveToDB(trans);
            MailDraft(mailSubject, "Your bags were full, so the guild sent these along.")
                .AddItem(item)
                .SendMailTo(trans, MailReceiver(player), MailSender(MAIL_NORMAL, player->GetGUID().GetCounter(), MAIL_STATIONERY_GM));
            CharacterDatabase.CommitTransaction(trans);
            ChatHandler(player->GetSession()).SendSysMessage("Your bags are full; the rest was sent by mail.");
        }
    }
}

uint32 BestArmorSubclass(Player* player)
{
    if (player->HasSkill(SKILL_PLATE_MAIL))
        return ITEM_SUBCLASS_ARMOR_PLATE;
    if (player->HasSkill(SKILL_MAIL))
        return ITEM_SUBCLASS_ARMOR_MAIL;
    if (player->HasSkill(SKILL_LEATHER))
        return ITEM_SUBCLASS_ARMOR_LEATHER;
    return ITEM_SUBCLASS_ARMOR_CLOTH;
}

uint32 NextDailyReset()
{
    return uint32(sWorld->GetNextDailyQuestsResetTime().count());
}

uint32 NextWeeklyReset()
{
    return uint32(sWorld->GetNextWeeklyQuestsResetTime().count());
}
} // namespace GspeItems
