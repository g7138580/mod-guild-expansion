/*
 * mod-guild-expansion: messages to the GuildExpansion client add-on.
 */

#include "GspeAddonComm.h"
#include "GspeConfig.h"
#include "GspeProgress.h"

#include "Chat.h"
#include "Guild.h"
#include "GuildMgr.h"
#include "Log.h"
#include "Player.h"
#include "StringFormat.h"
#include "WorldPacket.h"
#include "WorldSession.h"

namespace GspeAddonComm
{
std::string Sanitize(std::string_view in, std::size_t maxLen)
{
    std::string out;
    out.reserve(std::min(in.size(), maxLen));
    for (unsigned char c : in)
    {
        if (out.size() >= maxLen)
            break;
        if (c == '\t' || c == '\r' || c == '\n' || c == '|')
            out.push_back(' ');
        else if (c >= 32 && c < 127)
            out.push_back(char(c));
    }
    return out;
}

void Send(Player* player, std::string_view payload)
{
    if (!player || !player->GetSession() || !sGspeConfig->addonSync)
        return;

    std::string full = std::string(PREFIX).append("\t").append(payload);
    if (full.size() > 255)
    {
        LOG_ERROR("module", "GuildExpansion: addon line over 255 bytes dropped: {}", full.substr(0, 40));
        return;
    }

    WorldPacket data;
    ChatHandler::BuildChatPacket(data, CHAT_MSG_WHISPER, LANG_ADDON, player, player, full);
    player->GetSession()->SendPacket(&data);
}

void SendClear(Player* player)
{
    Send(player, "CLEAR");
}

void SendError(Player* player, std::string_view text)
{
    Send(player, std::string("ERROR\t").append(Sanitize(text, 200)));
}

void SendState(Player* player)
{
    if (!player)
        return;

    Guild* guild = player->GetGuildId() ? sGuildMgr->GetGuildById(player->GetGuildId()) : nullptr;
    GuildProgressState st{};
    if (!guild || !sGuildProgressMgr->LoadProgress(guild->GetId(), st))
    {
        SendClear(player);
        return;
    }

    uint64 const prevXp = GuildProgressMgr::CumulativeXpForLevel(st.level);
    uint64 const nextXp = st.level < GuildProgressMgr::MaxGuildLevel()
        ? GuildProgressMgr::CumulativeXpForLevel(st.level + 1)
        : st.xp;

    Send(player, Acore::StringFormat("STATE\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
        uint32(st.level), st.xp, prevXp, nextXp, st.todayXp, st.weekXp,
        sGspeConfig->dailyXpCap, sGspeConfig->weeklyXpCap, st.supplies,
        guild->GetId(), Sanitize(guild->GetName(), 48)));
}

void BroadcastState(uint32 guildId)
{
    if (!guildId || !sGspeConfig->addonSync)
        return;

    Guild* guild = sGuildMgr->GetGuildById(guildId);
    if (!guild)
        return;

    struct Sender
    {
        void operator()(Player* p) const { SendState(p); }
    } sender;
    guild->BroadcastWorker(sender);
}
} // namespace GspeAddonComm
