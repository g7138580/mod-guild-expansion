# mod-guild-expansion

An AzerothCore (WotLK 3.3.5a) module that adds guild progression built for playing on your own: guild levels and perks, work orders, daily contracts, a guild quartermaster, recruitable units and a mission table. It comes with a client addon that provides the interface.

> **Work in progress.** Features, settings and database tables will change often, and updates may not be compatible with older versions.

## Features

- **Guild levels and perks.** Guilds level from 1 to 25 by earning guild XP. Perks include bonus experience and reputation, a faster mount, cheaper repairs, a shorter Hearthstone cooldown, longer elixirs and flasks, and a summonable guild bank.
- **Work orders.** Each character gets crafting and gathering orders based on its professions. Place the items in the order and turn it in for gold, guild XP and Guild Supplies. An abandoned order is replaced after a delay.
- **Daily contracts.** Each character gets three contracts a day from normal play: slay a creature type, slay elites, complete quests, gather, fish, defeat dungeon bosses, play battlegrounds or earn honorable kills. They pay out as soon as they are done, with a bonus cache for finishing all three.
- **Guild quartermaster.** Spend Guild Supplies on bags, fishing poles, potions, flasks and services such as extra rerolls. A weekly stock adds gear picked for each character, plus a material, recipes and a pet or mount shared by the guild.
- **Units.** Recruit heroes and specialists into the guild. Units have a role, level, item level, abilities and traits, and are promoted from uncommon to rare to epic with experience.
- **Unit equipment.** Give units a weapon and armor to raise their item level, and an accessory in their effect slot for a bonus that depends on the profession that made it.
- **Troops.** Train troops with Guild Supplies to fill mission slots. They wear out after a few missions.
- **Missions.** Send units on timed missions for gold, supplies, guild XP, crafting materials and gear. Missions keep running while you are offline. Some missions are rare or carry an effect, and each kind of consumable sent along has its own bonus.
- **Guild Supplies.** Earned from work orders, contracts and missions, spent on missions, recruits, troops and at the quartermaster.

## Requirements

- [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk) (WotLK 3.3.5a)
- The included `GuildExpansion` client addon

## Installation

1. Clone this repository into `azerothcore-wotlk/modules/`.
2. Re-run CMake and rebuild the server.
3. In your server's `configs/modules` folder, copy `mod_guild_expansion.conf.dist` to `mod_guild_expansion.conf` and adjust it if you like.
4. Start the worldserver. The database tables are created automatically when `Updates.EnableDatabases` is enabled.
5. Copy `client_addon/GuildExpansion` into your client's `Interface/AddOns` folder.

This module replaces mod-guild-levels. Do not run both. Existing guild levels from mod-guild-levels are imported the first time the server starts.

## Usage

Open the window from the tab on the side of the Guild window (Social > Guild), or type `/gl`.

| Command | Opens |
|---|---|
| `/gl missions` | Missions |
| `/gl units` | Units and recruits |
| `/gl orders` | Work orders |
| `/gl contracts` | Daily contracts |
| `/gl qm` | Quartermaster |
| `/gl guild` | Guild level and perks |
| `/gl scale 0.9` | Resizes the window (0.6 to 1.4) |

GM commands: `.gspe info`, `.gspe setlevel`, `.gspe addxp`, `.gspe supplies`, `.gspe missions`, `.gspe finish`, `.gspe recruits`, `.gspe orders`, `.gspe contracts`, `.gspe contract N`, `.gspe weekly`, `.gspe reload`.

## Configuration

All settings are in `mod_guild_expansion.conf`: guild XP rates, perk values, work order and contract rewards, recruit costs, mission rewards and the quartermaster's weekly stock. The quartermaster's items are in the world database tables `mod_gspe_qm_stock`, `mod_gspe_qm_material` and `mod_gspe_qm_curiosity`.

## Credits

The guild level and perk code started from [mod-guild-levels](https://github.com/Old-Man-Warcraft/mod-guild-levels).

## License

GPL-3.0. See [LICENSE](LICENSE).
