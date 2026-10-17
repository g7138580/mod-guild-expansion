--[[
  Guild Expansion: minimap button.
  Left-click opens the window, right-click opens Contracts, drag moves it around the
  minimap. The tooltip shows the guild's level and what's ready. Turned on and off from
  the options on the Guild tab.
]]

local GE = GuildExpansion

local RADIUS = 80
local button

local function UpdatePosition()
    local angle = math.rad(GE.Options().minimapAngle or 200)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Guild Expansion")
    local st = GE.state
    if not st then
        GameTooltip:AddLine("Not in a guild", 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine(string.format("%s, level %d", st.guildName ~= "" and st.guildName or "Your guild", st.level), 1, 1, 1)
        local s = GE.Summary()
        GameTooltip:AddLine(" ")
        if s.contractsTotal > 0 then
            GameTooltip:AddDoubleLine("Contracts", string.format("%d / %d", s.contractsDone, s.contractsTotal),
                1, 0.82, 0, s.contractsDone == s.contractsTotal and 0.5 or 1, 1, s.contractsDone == s.contractsTotal and 0.5 or 1)
        end
        GameTooltip:AddDoubleLine("Missions ready", s.missionsReady, 1, 0.82, 0, s.missionsReady > 0 and 0.5 or 1, 1, s.missionsReady > 0 and 0.5 or 1)
        GameTooltip:AddDoubleLine("Missions running", s.missionsRunning, 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("Work orders ready", string.format("%d of %d", s.ordersReady, s.ordersOpen),
            1, 0.82, 0, s.ordersReady > 0 and 0.5 or 1, 1, s.ordersReady > 0 and 0.5 or 1)
        if s.weeklyResetsAt > GetTime() then
            GameTooltip:AddDoubleLine("New weekly stock in", GE.UI.FormatDuration(s.weeklyResetsAt - GetTime()), 1, 0.82, 0, 1, 1, 1)
        end
        GameTooltip:AddDoubleLine("Guild supplies", GE.FormatNumber(st.supplies), 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click to open, right-click for contracts. Drag to move.", 0, 1, 0, true)
    GameTooltip:Show()
end

local function Build()
    button = CreateFrame("Button", "GuildExpansionMinimapButton", Minimap)
    button:SetWidth(31)
    button:SetHeight(31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetWidth(20)
    background:SetHeight(20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(17)
    icon:SetHeight(17)
    icon:SetPoint("TOPLEFT", 7, -6)
    if SetPortraitToTexture then
        SetPortraitToTexture(icon, "Interface\\Icons\\INV_Shirt_GuildTabard_01")
    else
        icon:SetTexture("Interface\\Icons\\INV_Shirt_GuildTabard_01")
    end

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetWidth(53)
    border:SetHeight(53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            GE.UI.Show("contracts")
        else
            GE.UI.Toggle()
        end
    end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            GE.Options().minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            UpdatePosition()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    UpdatePosition()
end

local function Apply()
    if GE.Options().minimapButton then
        if not button then
            Build()
        end
        button:Show()
    elseif button then
        button:Hide()
    end
end

GE.RegisterListener(function(event)
    if event == "state" then
        Apply()
    end
end)

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", Apply)
