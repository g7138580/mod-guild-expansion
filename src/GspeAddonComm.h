/*
 * mod-guild-expansion: messages to and from the GuildExpansion client add-on.
 *
 * Server -> client: whispers to the player in LANG_ADDON, "GSPE\t<command>\t<fields...>".
 * Client -> server: the add-on whispers itself the same way; the module intercepts those
 * whispers so they never show up as chat. Every line fits in 255 bytes.
 */

#ifndef MOD_GSPE_ADDON_COMM_H_
#define MOD_GSPE_ADDON_COMM_H_

#include "Define.h"
#include <string>
#include <string_view>

class Player;

namespace GspeAddonComm
{
constexpr char PREFIX[] = "GSPE";

// Sends "GSPE\t<payload>". Dropped (and logged) if it would exceed 255 bytes.
void Send(Player* player, std::string_view payload);

// STATE\tlevel\txp\tprev\tnext\ttoday\tweek\tdailyCap\tweeklyCap\tsupplies\tguildId\tname
void SendState(Player* player);
void SendClear(Player* player);
// ERROR\ttext: the add-on shows it like a failed spell cast.
void SendError(Player* player, std::string_view text);

// Pushes STATE to every online member of the guild.
void BroadcastState(uint32 guildId);

// Replaces tabs, pipes and line breaks, drops non-ASCII and truncates.
[[nodiscard]] std::string Sanitize(std::string_view in, std::size_t maxLen);
} // namespace GspeAddonComm

#endif
