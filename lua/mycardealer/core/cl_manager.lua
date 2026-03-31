--[[
    myCardealer Tier 1 Core: Admin Module Manager
    Always available for superadmins to manage and refresh system
]]

local Manager = myCardealer.Module:New("admin_manager")
    :ForCore()  -- Tier 1 - always loaded
    :SetConfig("ChatCommand", "!modules")
    :SetConfig("ConsoleCommand", "cardealer_modules")

function Manager:OpenUI()
    if not IsValid(LocalPlayer()) or not LocalPlayer():IsSuperAdmin() then
        chat.AddText(myCardealer.UI:Color("Error"), "[CarDealer] Superadmin required")
        return
    end

    -- Close existing
    if IsValid(self._Frame) then
        self._Frame:Remove()
    end

    -- Use Tier 1 registered frame
    local frame = myCardealer.UI:Open("Sidebar", 800, 500, "CarDealer Module Manager")
    self._Frame = frame
    
    frame.Sidebar:SetWide(160)
    
    local content = frame:GetContent()
    local bottom = frame:GetBottomBar()
    
    -- Build sidebar
    local views = {
        {name = "Overview", func = function() self:ShowOverview(content) end},
        {name = "Core Modules", func = function() self:ShowCoreModules(content) end},
        {name = "Plugins", func = function() self:ShowPlugins(content) end},
        {name = "Slots", func = function() self:ShowSlots(content) end}
    }
    
    for _, view in ipairs(views) do
        frame:AddSidebarItem(view.name, view.func)
    end
    
    -- Refresh button with confirmation
    local refresh = myCardealer.UI:Button(bottom, "↻ Refresh Lua", myCardealer.UI:Color("Warning"))
    refresh:Dock(RIGHT)
    refresh:SetWide(120)
    refresh:DockMargin(0, 6, 8, 6)
    refresh.DoClick = function()
        Derma_Query(
            "Refresh all Lua files?\nThis will reload the entire system and may cause brief lag.",
            "Confirm System Refresh",
            "Refresh Now",
            function()
                self:RequestRefresh()
            end,
            "Cancel"
        )
    end
    
    -- Close button
    local close = myCardealer.UI:Button(bottom, "Close")
    close:Dock(RIGHT)
    close:SetWide(80)
    close:DockMargin(0, 6, 8, 6)
    close.DoClick = function() frame:Close() end
    
    -- Default view
    views[1].func()
end

function Manager:RequestRefresh()
    -- Notify server first (if connected)
    if game.SinglePlayer() or LocalPlayer():IsListenServerHost() then
        -- Single player or listen server - just refresh
        RunConsoleCommand("lua_refresh")
    else
        -- Dedicated server - request server refresh
        net.Start("myCardealer.RequestRefresh")
        net.SendToServer()
        
        -- Close UI and wait
        if IsValid(self._Frame) then
            self._Frame:Close()
        end
        
        chat.AddText(myCardealer.UI:Color("Primary"), "[CarDealer] ", 
            color_white, "Refresh requested from server...")
    end
end

-- View: System Overview
function Manager:ShowOverview(parent)
    parent:Clear()
    
    myCardealer.UI:Label(parent, "System Overview", "myCardealer.Header")
        :Dock(TOP):DockMargin(8, 8, 8, 16)
    
    local tiers = {
        {"Tier 1: Core Infrastructure", "Always loaded", myCardealer.TIER_CORE},
        {"Tier 2: Core Modules", "Swappable systems", myCardealer.TIER_CORE_MODULE},
        {"Tier 3: Plugins", "Additive features", myCardealer.TIER_PLUGIN}
    }
    
    for _, tier in ipairs(tiers) do
        local count = table.Count(myCardealer.Core:GetModulesByTier(tier[3]))
        local loaded = myCardealer.Core.TierLoaded[tier[3]] or (tier[3] == 1)
        
        local row = vgui.Create("DPanel", parent)
        row:Dock(TOP)
        row:SetTall(44)
        row:DockMargin(8, 0, 8, 4)
        row.Paint = function(p, w, h)
            surface.SetDrawColor(myCardealer.UI:Color("Surface"))
            surface.DrawRect(0, 0, w, h)
            
            draw.SimpleText(tier[1], "myCardealer.Body", 12, 6, color_white)
            draw.SimpleText(tier[2], "myCardealer.Small", 12, 24, myCardealer.UI:Color("TextDim"))
            
            local status = loaded and "✓ Ready" or "○ Pending"
            local statusColor = loaded and myCardealer.UI:Color("Success") or myCardealer.UI:Color("TextDim")
            draw.SimpleText(count .. " modules", "myCardealer.Body", w - 12, 12, color_white, TEXT_ALIGN_RIGHT)
        end
    end
    
    -- Quick actions
    myCardealer.UI:Label(parent, "Quick Actions", "myCardealer.Title")
        :Dock(TOP):DockMargin(8, 24, 8, 8)
    
    local btnRow = vgui.Create("DPanel", parent)
    btnRow:Dock(TOP)
    btnRow:SetTall(40)
    btnRow:DockMargin(8, 0, 8, 0)
    btnRow.Paint = nil
    
    local debugBtn = myCardealer.UI:Button(btnRow, "Print Debug Info")
    debugBtn:Dock(LEFT)
    debugBtn:SetWide(140)
    debugBtn.DoClick = function()
        RunConsoleCommand("cardealer_debug")
    end
    
    local closeAllBtn = myCardealer.UI:Button(btnRow, "Close All Windows")
    closeAllBtn:Dock(LEFT)
    closeAllBtn:SetWide(140)
    closeAllBtn:DockMargin(8, 0, 0, 0)
    closeAllBtn.DoClick = function()
        myCardealer.UI:CloseAll()
    end
end

-- View: Core Modules (swappable)
function Manager:ShowCoreModules(parent)
    parent:Clear()
    
    myCardealer.UI:Label(parent, "Core Modules", "myCardealer.Header")
        :Dock(TOP):DockMargin(8, 8, 8, 4)
    
    myCardealer.UI:Label(parent, "Click a module to activate it for its slot. Only one module per slot can be active.", "myCardealer.Small")
        :Dock(TOP):DockMargin(8, 0, 8, 8)
    
    local list = myCardealer.UI:List(parent)
    
    local modules = myCardealer.Core:GetModulesByTier(myCardealer.TIER_CORE_MODULE)
    for name, mod in SortedPairs(modules) do
        local slot = mod.Data.Slot or "unknown"
        local slotData = myCardealer.Core.CoreModules[slot]
        local isActive = slotData and slotData.Current == name
        local hasOptions = slotData and table.Count(slotData.Modules) > 1
        
        local color = isActive and myCardealer.UI:Color("Success") or 
                      (hasOptions and myCardealer.UI:Color("Primary") or myCardealer.UI:Color("TextDim"))
        
        local subtitle = slot
        if isActive then
            subtitle = slot .. " [ACTIVE]"
        elseif not hasOptions then
            subtitle = slot .. " (only option)"
        end
        
        local item = myCardealer.UI:ListItem(list, name, subtitle, color)
        
        if not isActive and hasOptions then
            item:SetCursor("hand")
            item.DoClick = function()
                RunConsoleCommand("cardealer_switch", slot, name)
                notification.AddLegacy("Activated " .. name .. " for " .. slot, NOTIFY_GENERIC, 3)
                surface.PlaySound("buttons/button14.wav")
                timer.Simple(0.3, function() self:ShowCoreModules(parent) end)
            end
        else
            item:SetCursor("arrow")
            item.DoClick = function()
                if isActive then
                    notification.AddLegacy(name .. " is already active", NOTIFY_HINT, 2)
                end
            end
        end
    end
end

-- View: Plugins
function Manager:ShowPlugins(parent)
    parent:Clear()
    
    myCardealer.UI:Label(parent, "Installed Plugins", "myCardealer.Header")
        :Dock(TOP):DockMargin(8, 8, 8, 8)
    
    local list = myCardealer.UI:List(parent)
    local plugins = myCardealer.Core:GetModulesByTier(myCardealer.TIER_PLUGIN)
    
    if table.Count(plugins) == 0 then
        myCardealer.UI:Label(list, "No plugins installed", "myCardealer.Body")
            :Dock(TOP):DockMargin(8, 8, 8, 8)
        return
    end
    
    for name, mod in SortedPairs(plugins) do
        local state = mod.State == 4 and "Enabled" or "Disabled"
        local auto = mod.Data.AutoEnable ~= false and "Auto-start" or "Manual"
        local stateColor = mod.State == 4 and myCardealer.UI:Color("Success") or myCardealer.UI:Color("TextDim")
        
        myCardealer.UI:ListItem(list, name, state .. " | " .. auto, stateColor)
    end
end

-- View: Slots
function Manager:ShowSlots(parent)
    parent:Clear()
    
    myCardealer.UI:Label(parent, "Core Module Slots", "myCardealer.Header")
        :Dock(TOP):DockMargin(8, 8, 8, 4)
    
    myCardealer.UI:Label(parent, "Required slots (*) must have an active module.", "myCardealer.Small")
        :Dock(TOP):DockMargin(8, 0, 8, 8)
    
    local list = myCardealer.UI:List(parent)
    
    for slotName, slot in SortedPairs(myCardealer.Core.CoreModules) do
        local current = slot.Current or "None"
        local options = table.Count(slot.Modules)
        local required = slot.Required
        
        local statusText = "→ " .. current
        if not slot.Current and required then
            statusText = statusText .. " (REQUIRED)"
        end
        
        local color = slot.Current and myCardealer.UI:Color("Success") or 
                      (required and myCardealer.UI:Color("Error") or myCardealer.UI:Color("Warning"))
        
        local title = slotName .. (required and " *" or "")
        local subtitle = statusText .. " (" .. options .. " option" .. (options ~= 1 and "s" or "") .. ")"
        
        myCardealer.UI:ListItem(list, title, subtitle, color)
    end
end

-- Network: Receive refresh command from server
net.Receive("myCardealer.ExecuteRefresh", function()
    notification.AddLegacy("Server refreshing Lua...", NOTIFY_GENERIC, 3)
    surface.PlaySound("buttons/button15.wav")
    timer.Simple(1, function()
        RunConsoleCommand("lua_refresh")
    end)
end)

-- Chat command
hook.Add("OnPlayerChat", "myCardealer_Manager", function(ply, text)
    if ply ~= LocalPlayer() then return end
    
    local cmd = Manager:GetConfig("ChatCommand")
    if text ~= cmd then return end
    
    Manager:OpenUI()
    return true
end)

-- Console command
concommand.Add("cardealer_modules", function()
    Manager:OpenUI()
end)

-- Bind to F6 if desired (optional)
hook.Add("PlayerBindPress", "myCardealer_ManagerBind", function(ply, bind, pressed)
    if not pressed then return end
    if bind ~= "F6" then return end
    if not ply:IsSuperAdmin() then return end
    Manager:OpenUI()
    return true
end)

function Manager:Initialize()
    print("[admin_manager] Tier 1 core loaded. Command: " .. self:GetConfig("ChatCommand"))
    return true
end

Manager:Register()