--[[ Guild Expansion: Guild page: level, experience, and perks by tier ]]

local GE = GuildExpansion
local UI = GE.UI

local ROW_HEIGHT = 44
local PER_COLUMN = 9

local function ShowPerkTooltip(owner, perk)
    local st = GE.state
    local level = st and st.level or 0
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(perk.name)
    if level >= perk.lv then
        GameTooltip:AddLine("Active", 0.5, 1, 0.5)
    else
        GameTooltip:AddLine(string.format("Unlocks at guild level %d", perk.lv), 1, 0.3, 0.3)
    end
    GameTooltip:AddLine(perk.desc, 1, 1, 1, true)
    if perk.use and level >= perk.lv then
        GameTooltip:AddLine("Click Use, or type /gl bank.", 0, 1, 0, true)
    end
    GameTooltip:Show()
end

local function Build(page)
    local p = page.frame
    local ui = {}
    page.ui = ui

    -- Level and experience.
    local top = UI.Inset(p)
    top:SetPoint("TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", 0, 0)
    top:SetHeight(100)
    top:SetBackdropColor(0.12, 0.09, 0.05, 0.85)

    ui.guildName = top:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    ui.guildName:SetPoint("TOPLEFT", 20, -12)
    ui.level = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    ui.level:SetPoint("TOPLEFT", ui.guildName, "BOTTOMLEFT", 0, -6)
    ui.nextPerk = top:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.nextPerk:SetPoint("TOPRIGHT", -20, -20)
    ui.today = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.today:SetPoint("TOPRIGHT", ui.nextPerk, "BOTTOMRIGHT", 0, -8)

    ui.bar = CreateFrame("StatusBar", nil, top)
    ui.bar:SetPoint("BOTTOMLEFT", 20, 14)
    ui.bar:SetPoint("BOTTOMRIGHT", -20, 14)
    ui.bar:SetHeight(22)
    ui.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    ui.bar:SetStatusBarColor(0.25, 0.55, 0.95)
    ui.bar:SetMinMaxValues(0, 1)
    ui.bar.bg = ui.bar:CreateTexture(nil, "BACKGROUND")
    ui.bar.bg:SetAllPoints(true)
    ui.bar.bg:SetTexture(0, 0, 0, 0.7)
    ui.bar.text = ui.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.bar.text:SetPoint("CENTER")

    -- Perks, two columns of tiers.
    local perks = UI.Inset(p)
    perks:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -8)
    perks:SetPoint("BOTTOMRIGHT", 0, 38)
    local header = perks:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 14, -12)
    header:SetText("Guild Perks")

    local colWidth = (UI.CONTENT_WIDTH - 40) / 2
    ui.rows = {}
    for i, perk in ipairs(GE.PERKS) do
        local col = math.floor((i - 1) / PER_COLUMN)
        local rowIndex = (i - 1) % PER_COLUMN
        local row = CreateFrame("Frame", nil, perks)
        row:SetWidth(colWidth - 10)
        row:SetHeight(ROW_HEIGHT - 4)
        row:SetPoint("TOPLEFT", 14 + col * colWidth, -36 - rowIndex * ROW_HEIGHT)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self) ShowPerkTooltip(self, perk) end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints(true)
        row.highlight:SetTexture(1, 0.82, 0, 0.14)

        row.tier = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        row.tier:SetPoint("LEFT", 0, 0)
        row.tier:SetWidth(34)
        row.tier:SetText(perk.lv)

        row.icon = UI.IconButton(row, 34)
        row.icon:SetPoint("LEFT", 40, 0)
        row.icon.icon:SetTexture(GE.IconPath(perk))
        row.icon:SetScript("OnEnter", function() ShowPerkTooltip(row, perk) end)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 3)
        row.desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.desc:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
        row.desc:SetPoint("RIGHT", row, "RIGHT", perk.use and -60 or -6, 0)
        row.desc:SetJustifyH("LEFT")
        row.desc:SetJustifyV("TOP")
        row.desc:SetHeight(24)
        row.desc:SetText(perk.desc)

        if perk.use then
            row.use = UI.Button(row, "Use", 50, 20)
            row.use:SetPoint("RIGHT", -4, 0)
            row.use:SetScript("OnClick", function() GE.Send("USE " .. perk.use) end)
        end
        ui.rows[i] = row
    end

    -- Options.
    local function Check(label, key, x)
        local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
        cb:SetWidth(24)
        cb:SetHeight(24)
        cb:SetPoint("BOTTOMLEFT", x, 6)
        local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        text:SetText(label)
        cb:SetScript("OnShow", function(self) self:SetChecked(GE.Options()[key]) end)
        cb:SetScript("OnClick", function(self) GE.SetOption(key, self:GetChecked() and true or false) end)
    end
    Check("Level-up alerts", "levelAlert", 4)
    Check("Show guild XP gains", "xpText", 150)

    local scaleLabel = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleLabel:SetPoint("BOTTOMRIGHT", -110, 12)
    scaleLabel:SetText("Window size")
    local smaller = UI.Button(p, "-", 40, 22)
    smaller:SetPoint("BOTTOMRIGHT", -56, 8)
    smaller:SetScript("OnClick", function() GE.SetScale((GE.Options().scale or 1) - 0.05) end)
    local bigger = UI.Button(p, "+", 40, 22)
    bigger:SetPoint("BOTTOMRIGHT", -10, 8)
    bigger:SetScript("OnClick", function() GE.SetScale((GE.Options().scale or 1) + 0.05) end)
end

local function Refresh(page)
    local ui = page.ui
    local st = GE.state

    if not st then
        ui.guildName:SetText("No guild")
        ui.level:SetText("Join a guild to earn guild levels and perks.")
        ui.nextPerk:SetText("")
        ui.today:SetText("")
        ui.bar:SetValue(0)
        ui.bar.text:SetText("")
    else
        ui.guildName:SetText(st.guildName ~= "" and st.guildName or "Your Guild")
        ui.level:SetText(string.format("Guild Level |cffffffff%d|r of %d", st.level, GE.MAX_LEVEL))
        if st.level >= GE.MAX_LEVEL then
            ui.bar:SetValue(1)
            ui.bar.text:SetText("Maximum guild level")
        else
            local span = math.max(1, st.nextXp - st.prev)
            local into = math.max(0, st.xp - st.prev)
            ui.bar:SetValue(math.min(1, into / span))
            ui.bar.text:SetText(string.format("%s / %s XP  (%d%%)  -  %s XP to level %d", GE.FormatNumber(into),
                GE.FormatNumber(span), math.floor(into / span * 100), GE.FormatNumber(span - into), st.level + 1))
        end
        local today = "Earned today: " .. GE.FormatNumber(st.today)
        if st.dailyCap > 0 then
            today = today .. " / " .. GE.FormatNumber(st.dailyCap)
        end
        ui.today:SetText(today)
        local nextPerk = GE.NextPerk(st.level)
        ui.nextPerk:SetText(nextPerk and string.format("Next perk at level %d: |cffffffff%s|r", nextPerk.lv, nextPerk.name)
            or "All perks unlocked")
    end

    local level = st and st.level or 0
    local nextPerk = GE.NextPerk(level)
    for i, perk in ipairs(GE.PERKS) do
        local row = ui.rows[i]
        local unlocked = level >= perk.lv
        row.icon.icon:SetDesaturated(not unlocked)
        row.icon.icon:SetAlpha(unlocked and 1 or 0.6)
        if unlocked then
            row.icon.border:SetVertexColor(1, 0.82, 0)
            row.icon.border:Show()
            row.name:SetText("|cff80ff80" .. perk.name .. "|r")
            row.tier:SetTextColor(1, 0.82, 0)
        else
            row.icon.border:Hide()
            row.name:SetText("|cff999999" .. perk.name .. "|r")
            row.tier:SetTextColor(0.5, 0.5, 0.5)
        end
        row.desc:SetTextColor(unlocked and 1 or 0.6, unlocked and 1 or 0.6, unlocked and 1 or 0.6)
        if perk == nextPerk then
            row.highlight:Show()
        else
            row.highlight:Hide()
        end
        if row.use then
            if unlocked then
                row.use:Enable()
            else
                row.use:Disable()
            end
        end
    end
end

UI.RegisterPage("guild", "Guild", "Guild Advancement", Build, Refresh)
