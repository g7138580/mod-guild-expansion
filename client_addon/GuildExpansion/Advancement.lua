--[[
  Guild Expansion: Advancement page.
  Guild levels after 25 each give a Guild Point. Left: tracks of small guild-wide
  bonuses, up to 25 points each. Right: milestones every 25 levels, each a choice of
  two lasting bonuses, and the level 250 capstone. The guild master and officers spend
  points and choose; Reset refunds every point, and changing a choice costs supplies.
]]

local GE = GuildExpansion
local UI = GE.UI

local HEADER_HEIGHT = 74
local ROW_HEIGHT = 50
local LEFT_WIDTH = 470

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
      fmt = "+%s%% gold (orders, contracts, missions)", desc = "+2% gold from work orders, contracts and missions per point." },
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

-- Keep in sync with the milestone effects in src/GspeAdvancement.cpp.
local MILESTONES = {
    { lv = 50,
      a = { "+1 mission slot", "One more mission can run at a time." },
      b = { "+1 unit slot", "The roster holds one more unit." } },
    { lv = 75,
      a = { "+2 troop slots", "Two more troops can be trained." },
      b = { "Troops last longer", "Troops last one more mission before wearing out." } },
    { lv = 100,
      a = { "+1 recruit candidate", "One more recruit candidate is offered." },
      b = { "Better recruits", "Recruits are more often rare (+10%) and epic (+3%)." } },
    { lv = 125,
      a = { "+1 weekly gear piece", "The quartermaster's weekly stock has a third gear piece for each character." },
      b = { "+1 weekly pet or mount", "The quartermaster's weekly stock has a second pet or mount." } },
    { lv = 150,
      a = { "+1 contract a day", "Each character gets one more daily contract." },
      b = { "Reroll and bigger bonus", "One more free contract reroll a day, and the bonus cache gives 50% more supplies." } },
    { lv = 175,
      a = { "+1 work order", "Each character gets one more work order." },
      b = { "No wait after abandoning", "An abandoned work order is replaced right away." } },
    { lv = 200,
      a = { "Rare missions x2", "Rare missions (double rewards) show up twice as often." },
      b = { "Salvage x2", "Successful missions bring back salvage twice as often." } },
    { lv = 225,
      a = { "+25% mission supplies", "Successful missions give 25% more supplies." },
      b = { "+25% gold and materials", "Successful missions give 25% more gold and crafting materials." } },
}
local CAPSTONE_LEVEL = 250

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

StaticPopupDialogs["GUILDEXPANSION_CHOOSE_MILESTONE"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        GE.Send(string.format("ACHOOSE %d %d", data.lv, data.choice))
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
        or "Only the guild master and officers can spend points and choose.")
end

-- Tracks (left) --------------------------------------------------------------------

local function BuildTrack(page, i)
    local def = TRACKS[i]
    local row = UI.ParchmentRow(page.frame, LEFT_WIDTH, ROW_HEIGHT - 4)
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
    row.value:SetWidth(LEFT_WIDTH - 190)
    row.value:SetJustifyH("LEFT")

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetWidth(100)
    row.bar:SetHeight(14)
    row.bar:SetPoint("RIGHT", -52, 0)
    row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.bar:SetStatusBarColor(1, 0.7, 0.1)
    local barBg = row.bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints(true)
    barBg:SetTexture(0, 0, 0, 0.6)
    row.barText = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.barText:SetPoint("CENTER")

    row.add = UI.Button(row, "+", 32, 24)
    row.add:SetPoint("RIGHT", -12, 0)
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

-- Milestones (right) ---------------------------------------------------------------

local function ChoiceButton(row, ms, choice)
    local opt = choice == 1 and ms.a or ms.b
    local b = UI.Button(row, opt[1], 140, 22)
    b:GetFontString():SetFontObject("GameFontHighlightSmall")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(opt[1])
        GameTooltip:AddLine(opt[2], 1, 1, 1, true)
        local current = GE.advancement.milestones[ms.lv] or 0
        if current ~= 0 and current ~= choice then
            GameTooltip:AddLine(string.format("Switching costs %d guild supplies.", GE.advancement.changeCost), 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function()
        local current = GE.advancement.milestones[ms.lv] or 0
        local text = current == 0
            and string.format("Choose \"%s\" for level %d? You can switch later for %d guild supplies.", opt[1], ms.lv, GE.advancement.changeCost)
            or string.format("Switch level %d to \"%s\" for %d guild supplies?", ms.lv, opt[1], GE.advancement.changeCost)
        local dialog = StaticPopup_Show("GUILDEXPANSION_CHOOSE_MILESTONE", text)
        if dialog then
            dialog.data = { lv = ms.lv, choice = choice }
        end
    end)
    b.check = b:CreateTexture(nil, "OVERLAY")
    b.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    b.check:SetWidth(16)
    b.check:SetHeight(16)
    b.check:SetPoint("RIGHT", b, "LEFT", 0, 0)
    return b
end

local function BuildMilestone(page, i, ms)
    local width = UI.CONTENT_WIDTH - LEFT_WIDTH - 8
    local row = UI.ParchmentRow(page.frame, width, ROW_HEIGHT - 4)
    row:EnableMouse(false)
    row:SetPoint("TOPLEFT", LEFT_WIDTH + 8, -(HEADER_HEIGHT + 8 + (i - 1) * ROW_HEIGHT))

    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.level:SetPoint("TOPLEFT", 12, -7)
    row.level:SetText(ms.lv)
    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.rank:SetPoint("TOPLEFT", row.level, "BOTTOMLEFT", 0, -2)
    for _, r in ipairs(GE.GUILD_RANKS) do
        if r.lv == ms.lv then
            row.rank:SetText(r.name)
        end
    end

    if ms.a then
        row.b = ChoiceButton(row, ms, 2)
        row.b:SetPoint("RIGHT", -10, 0)
        row.a = ChoiceButton(row, ms, 1)
        row.a:SetPoint("RIGHT", row.b, "LEFT", -20, 0)
    else
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("RIGHT", -16, 0)
        row.text:SetText(ms.text)
    end
    return row
end

local function RefreshMilestones(page)
    local a = GE.advancement
    local level = a.status == 0 and a.level or 0
    for _, row in ipairs(page.ui.milestones) do
        local ms = row.ms
        local reached = level >= ms.lv
        row.level:SetTextColor(reached and 1 or 0.5, reached and 0.82 or 0.5, reached and 0 or 0.5)
        row.rank:SetTextColor(reached and 1 or 0.5, reached and 1 or 0.5, reached and 1 or 0.5)
        if row.a then
            local current = a.milestones[ms.lv] or 0
            for choice, b in ipairs({ row.a, row.b }) do
                if current == choice then
                    b.check:Show()
                    b:LockHighlight()
                else
                    b.check:Hide()
                    b:UnlockHighlight()
                end
                if reached and a.canEdit and current ~= choice then
                    b:Enable()
                else
                    b:Disable()
                end
            end
        elseif row.text then
            row.text:SetTextColor(reached and 0.5 or 0.5, reached and 1 or 0.5, reached and 0.5 or 0.5)
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
    page.ui.milestones = {}
    for i, ms in ipairs(MILESTONES) do
        local row = BuildMilestone(page, i, ms)
        row.ms = ms
        page.ui.milestones[i] = row
    end
    local capstone = { lv = CAPSTONE_LEVEL, text = "Capstone: the Legendary rank and a large supplies payout" }
    local row = BuildMilestone(page, #MILESTONES + 1, capstone)
    row.ms = capstone
    page.ui.milestones[#MILESTONES + 1] = row

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
    RefreshMilestones(page)
end

UI.RegisterPage("advancement", "Advancement", "Guild Points and Milestones", Build, Refresh)
