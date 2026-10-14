/*
 * mod-guild-expansion: item helpers shared by missions, contracts and the quartermaster.
 */

#ifndef MOD_GSPE_ITEMS_H_
#define MOD_GSPE_ITEMS_H_

#include "Define.h"

#include <string>

class Player;

namespace GspeItems
{
// Gives the item, mailing whatever doesn't fit in the bags. randomProperty: the random
// suffix or property to use, or 0 to roll one.
void GiveItem(Player* player, uint32 itemId, uint32 count, std::string const& mailSubject, int32 randomProperty = 0);

// The best armor type the character can wear (ITEM_SUBCLASS_ARMOR_*).
[[nodiscard]] uint32 BestArmorSubclass(Player* player);

// Seconds since the epoch of the server's next daily / weekly quest reset. They change
// when a reset happens, so they also serve as the key of the current day / week.
[[nodiscard]] uint32 NextDailyReset();
[[nodiscard]] uint32 NextWeeklyReset();
} // namespace GspeItems

#endif
