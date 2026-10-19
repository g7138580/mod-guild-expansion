--[[
  Guild Expansion: Advancement page.
  Guild levels after 25 each give a Guild Point. Points go into tracks of small
  guild-wide bonuses, up to 25 points each. The guild master and officers spend them;
  Reset refunds every point for a supplies fee.
]]

local GE = GuildExpansion
local UI = GE.UI

local HEADER_HEIGHT = 74
local ROW_HEIGHT = 52

-- Keep in sync with AdvancementTrack in src/GspeAdvancement.h. per: bonus per point;
-- fmt turns the total into text.
local TRACKS = {
    { id = 1, name = "Supply Lines", icon = "INV_Crate_01", per = 1,
      fmt = "+%s%% guild supplies earned", desc = "+1% guild supplies earned per point." },
    { id = 2, name = "Field Command", icon = "Ability_Warrior_BattleShout", per = 1,
      fmt = "+%s mission success chance", desc = "+1 mission success chance per point." },
    { id = 3, name = "Swift Couriers", icon = "Ability_Rogue_Sprint", per = 1,
      fmt = "-%s%% mission duration", desc = "Missions take 1% less time per point." },
    { id = 4, name = "Trade Agreements", icon = "INV_Misc_Coin_02", per = 2,
      fmt = "+%s%% gold from orders, contracts and missions", desc = "+2% gold from work orders, contracts and missions per point." },
    { id = 5, name = "Drill Sergeant", icon = "Spell_Holy_HolyGuidance", per = 2,
      fmt = "+%s%% unit XP", desc = "Units gain 2% more experience per point." },
    { id = 6, name = "Quartermaster's Favor", icon = "INV_Box_02", per = 1,
      fmt = "-%s%% quartermaster prices", desc = "Quartermaster prices are 1% lower per point." },
    { id = 7, name = "Seasoned Travelers", icon = "Ability_Hunter_Pathfinding", per = 0.4,
      fmt = "+%s%% XP from kills and quests", desc = "+0.4% character XP from kills and quests per point, on top of Fast Track." },
    { id = 8, name = "Good Standing", icon = "Achievement_Reputation_01", per = 0.4,
      fmt = "+%s%% reputation", desc = "+0.4% reputation gains per point, on top of Mr. Popularity." },
    { id = 9, name = "Steady Hands", icon = "Trade_BlackSmithing", per = 0.4,
      fmt = "+%s%% chance of an extra skill-up", desc = "+0.4% chance of an extra profession skill-up per point, on top of Working Overtime." },
}

local function FormatValue(v)
    if v == math.floor(v) then
        return tostring(v)
    end
    return string.format("%.1f", v)
end

StaticPopupDialogs["GUILDEXPANSION_RESET_POINTS"] = {
    text = "Refund all %d spent Guild Points for %d guild supplies?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        GE.Send("ARESET")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function Available()
    local a = GE.advancement
    return math.max(0, a.earned - a.spent)
end

-- Header ---------------------------------------------------------------------------

local function BuildHeader(page)
    local ui = page.ui
    local head = UI.Inset(page.frame)
    head:SetPoint("TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", 0, 0)
    head:SetHeight(HEADER_HEIGHT)

    ui.title = head:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    ui.title:SetPoint("TOPLEFT", 16, -12)
    ui.title:SetText("Guild Points")
    ui.points = head:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.points:SetPoint("TOPLEFT", ui.title, "BOTTOMLEFT", 0, -8)

    ui.reset = UI.Button(head, "Reset Points", 120, 24)
    ui.reset:SetPoint("TOPRIGHT", -16, -14)
    ui.reset:SetScript("OnClick", function()
        local a = GE.advancement
        StaticPopup_Show("GUILDEXPANSION_RESET_POINTS", a.spent, a.resetCost)
    end)
    ui.reset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Reset Points")
        GameTooltip:AddLine(string.format("Refunds every spent point for %d guild supplies.", GE.advancement.resetCost), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    ui.reset:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ui.note = head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.note:SetPoint("TOPRIGHT", ui.reset, "BOTTOMRIGHT", 0, -8)
end

local function RefreshHeader(page)
    local ui = page.ui
    local a = GE.advancement
    if a.status ~= 0 then
        ui.points:SetText(a.status == 1 and "Join a guild to earn Guild Points." or "Guild Expansion is turned off on this server.")
        ui.reset:Hide()
        ui.note:SetText("")
        return
    end

    if a.earned == 0 then
        ui.points:SetText(string.format("Every guild level after %d gives a Guild Point. Your guild is level %d.", GE.PERK_LEVEL, a.level))
    else
        ui.points:SetText(string.format("Available: |cff80ff80%d|r     Earned: |cffffffff%d|r     Spent: |cffffffff%d|r",
            Available(), a.earned, a.spent))
    end
    ui.reset:Show()
    if a.canEdit and a.spent > 0 then
        ui.reset:Enable()
    else
        ui.reset:Disable()
    end
    ui.note:SetText(a.canEdit and "Click + to spend a point, Shift-click to spend 5."
        or "Only the guild master and officers can spend points.")
end

-- Tracks ---------------------------------------------------------------------------

local function BuildTrack(page, i)
    local def = TRACKS[i]
    local row = UI.ParchmentRow(page.frame, UI.CONTENT_WIDTH, ROW_HEIGHT - 4)
    row:EnableMouse(false)
    row:SetPoint("TOPLEFT", 0, -(HEADER_HEIGHT + 8 + (i - 1) * ROW_HEIGHT))

    row.icon = UI.IconButton(row, 36)
    row.icon:SetPoint("LEFT", 10, 0)
    row.icon.icon:SetTexture("Interface\\Icons\\" .. def.icon)
    row.icon.tooltip = function()
        GameTooltip:AddLine(def.name)
        GameTooltip:AddLine(def.desc, 1, 1, 1, true)
        GameTooltip:AddLine(string.format("Up to %d points.", GE.advancement.trackMax), 0.8, 0.8, 0.8)
    end

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -2)
    row.name:SetText(def.name)
    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetWidth(260)
    row.bar:SetHeight(14)
    row.bar:SetPoint("RIGHT", -60, 0)
    row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.bar:SetStatusBarColor(1, 0.7, 0.1)
    local barBg = row.bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints(true)
    barBg:SetTexture(0, 0, 0, 0.6)
    row.barText = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.barText:SetPoint("CENTER")

    row.add = UI.Button(row, "+", 32, 24)
    row.add:SetPoint("RIGHT", -14, 0)
    row.add:SetScript("OnClick", function()
        GE.Send(string.format("ASPEND %d %d", def.id, IsShiftKeyDown() and 5 or 1))
    end)
    return row
end

local function RefreshTracks(page)
    local a = GE.advancement
    local available = Available()
    for i, row in ipairs(page.ui.tracks) do
        local def = TRACKS[i]
        local points = a.tracks[def.id] or 0
        row.bar:SetMinMaxValues(0, math.max(1, a.trackMax))
        row.bar:SetValue(points)
        row.barText:SetText(string.format("%d / %d", points, a.trackMax))
        if points > 0 then
            row.value:SetText("|cff80ff80" .. string.format(def.fmt, FormatValue(points * def.per)) .. "|r")
        else
            row.value:SetText("|cff999999" .. def.desc .. "|r")
        end
        row.icon.icon:SetDesaturated(points == 0)
        if a.status == 0 and a.canEdit and available > 0 and points < a.trackMax then
            row.add:Enable()
        else
            row.add:Disable()
        end
    end
end

-- Page -----------------------------------------------------------------------------

local function Build(page)
    page.ui = {}
    BuildHeader(page)
    page.ui.tracks = {}
    for i = 1, #TRACKS do
        page.ui.tracks[i] = BuildTrack(page, i)
    end
    page.frame:SetScript("OnShow", function()
        GE.Send("ADV")
    end)
end

local function Refresh(page)
    -- A level-up changes the points earned; ask again when the level moved.
    if GE.state and GE.advancement.status == 0 and GE.state.level ~= GE.advancement.level then
        GE.advancement.level = GE.state.level
        GE.Send("ADV")
    end
    RefreshHeader(page)
    RefreshTracks(page)
end

UI.RegisterPage("advancement", "Advancement", "Guild Points", Build, Refresh)
