--[[
    myCardealer Tier 1 Core: Admin Module Manager
    Always available for superadmins to manage and refresh system
]]

local Manager = myCardealer.Module:New("admin_manager")
    :ForCore()
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
        self._Frame = nil
    end

    -- Use registered Sidebar frame
    local frame = myCardealer.UI:Open("Sidebar", 800, 500, "CarDealer Module Manager")
    if not frame then
        chat.AddText(myCardealer.UI:Color("Error"), "[CarDealer] Failed to create UI")
        return
    end
    
    self._Frame = frame
    
    -- Adjust sidebar width
    if frame.Sidebar then
        frame.Sidebar:SetWide(160)
    end
    
    local content = frame:GetContent()
    if not content then
        print("[admin_manager] ERROR: Frame has no content panel")
        return
    end
    
    local bottom = frame:GetBottomBar()
    
    -- Build sidebar
    local views = {
        {name = "Overview", func = function() self:ShowOverview(content) end},
        {name = "Core Modules", func = function() self:ShowCoreModules(content) end},
        {name = "Plugins", func = function() self:ShowPlugins(content) end},
        {name = "Slots", func = function() self:ShowSlots(content) end}
    }
    
    if frame.AddSidebarItem then
        for _, view in ipairs(views) do
            frame:AddSidebarItem(view.name, view.func)
        end
    end
    
    -- Refresh button
    if bottom and bottom:IsValid() then
        local refresh = myCardealer.UI:Button(bottom, "Refresh Lua", myCardealer.UI:Color("Warning"))
        refresh:Dock(RIGHT)
        refresh:SetWide(120)
        refresh:DockMargin(0, 6, 8, 6)
        refresh.DoClick = function()
            Derma_Query("Refresh all Lua files?", "Confirm", "Yes", function()
                self:RequestRefresh()
            end, "Cancel")
        end
        
        -- Close button - use Remove() since EditablePanel doesn't have Close()
        local closeBtn = myCardealer.UI:Button(bottom, "Close")
        closeBtn:Dock(RIGHT)
        closeBtn:SetWide(80)
        closeBtn:DockMargin(0, 6, 8, 6)
        closeBtn.DoClick = function()
            if IsValid(frame) then
                frame:Remove()
                self._Frame = nil
            end
        end
    end
    
    -- Show overview by default
    views[1].func()
end

function Manager:RequestRefresh()
    if game.SinglePlayer() or LocalPlayer():IsListenServerHost() then
        RunConsoleCommand("cardealer_refresh")
    else
        net.Start("myCardealer.RequestRefresh")
        net.SendToServer()
        
        if IsValid(self._Frame) then
            self._Frame:Remove()
            self._Frame = nil
        end
        
        chat.AddText(myCardealer.UI:Color("Primary"), "[CarDealer] ", 
            color_white, "Refresh requested from server...")
    end
end

function Manager:ShowOverview(parent)
    if not IsValid(parent) then return end
    parent:Clear()
    
    local title = myCardealer.UI:Label(parent, "System Overview", "myCardealer.Header")
    title:Dock(TOP)
    title:DockMargin(8, 8, 8, 16)
    
    -- Safely get counts
    local coreCount = 0
    local modCount = 0
    local plugCount = 0
    
    if myCardealer.Core and myCardealer.Core.GetModulesByTier then
        coreCount = table.Count(myCardealer.Core:GetModulesByTier(myCardealer.TIER_CORE))
        modCount = table.Count(myCardealer.Core:GetModulesByTier(myCardealer.TIER_CORE_MODULE))
        plugCount = table.Count(myCardealer.Core:GetModulesByTier(myCardealer.TIER_PLUGIN))
    end
    
    local stats = {
        {"Tier 1 (Core)", "Always loaded", tostring(coreCount) .. " modules"},
        {"Tier 2 (Modules)", "Swappable", tostring(modCount) .. " modules"},
        {"Tier 3 (Plugins)", "Additive", tostring(plugCount) .. " modules"},
        {"Active Slots", "Core slots", tostring(table.Count(myCardealer.Core.CoreModules or {}))}
    }
    
    for _, stat in ipairs(stats) do
        local row = vgui.Create("DPanel", parent)
        row:Dock(TOP)
        row:SetTall(40)
        row:DockMargin(8, 0, 8, 4)
        row.Paint = function(p, w, h)
            surface.SetDrawColor(myCardealer.UI:Color("Surface"))
            surface.DrawRect(0, 0, w, h)
            draw.SimpleText(stat[1], "myCardealer.Body", 12, 4, color_white)
            draw.SimpleText(stat[2], "myCardealer.Small", 12, 22, myCardealer.UI:Color("TextDim"))
            draw.SimpleText(stat[3], "myCardealer.Body", w - 12, 10, color_white, TEXT_ALIGN_RIGHT)
        end
    end
    
    -- Quick actions
    local actionsTitle = myCardealer.UI:Label(parent, "Quick Actions", "myCardealer.Title")
    actionsTitle:Dock(TOP)
    actionsTitle:DockMargin(8, 24, 8, 8)
    
    local btnRow = vgui.Create("DPanel", parent)
    btnRow:Dock(TOP)
    btnRow:SetTall(40)
    btnRow:DockMargin(8, 0, 8, 0)
    btnRow.Paint = nil
    
    local debugBtn = myCardealer.UI:Button(btnRow, "Print Debug")
    debugBtn:Dock(LEFT)
    debugBtn:SetWide(100)
    debugBtn.DoClick = function()
        RunConsoleCommand("cardealer_debug")
    end
    
    local closeAllBtn = myCardealer.UI:Button(btnRow, "Close All UI")
    closeAllBtn:Dock(LEFT)
    closeAllBtn:SetWide(100)
    closeAllBtn:DockMargin(8, 0, 0, 0)
    closeAllBtn.DoClick = function()
        myCardealer.UI:CloseAll()
        self._Frame = nil
    end
end

function Manager:ShowCoreModules(parent)
    if not IsValid(parent) then return end
    parent:Clear()
    
    local title = myCardealer.UI:Label(parent, "Core Modules", "myCardealer.Header")
    title:Dock(TOP)
    title:DockMargin(8, 8, 8, 4)
    
    local desc = myCardealer.UI:Label(parent, "Click to activate a module for its slot", "myCardealer.Small")
    desc:Dock(TOP)
    desc:DockMargin(8, 0, 8, 8)
    
    local list = myCardealer.UI:List(parent)
    
    if not myCardealer.Core or not myCardealer.Core.GetModulesByTier then return end
    
    local modules = myCardealer.Core:GetModulesByTier(myCardealer.TIER_CORE_MODULE)
    for name, mod in SortedPairs(modules) do
        local slot = mod.Data.Slot or "unknown"
        local slotData = myCardealer.Core.CoreModules and myCardealer.Core.CoreModules[slot]
        local isActive = slotData and slotData.Current == name
        local hasOptions = slotData and table.Count(slotData.Modules or {}) > 1
        
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
                notification.AddLegacy("Activated " .. name, NOTIFY_GENERIC, 3)
                timer.Simple(0.3, function()
                    if IsValid(parent) then
                        self:ShowCoreModules(parent)
                    end
                end)
            end
        end
    end
end

function Manager:ShowPlugins(parent)
    if not IsValid(parent) then return end
    parent:Clear()
    
    local title = myCardealer.UI:Label(parent, "Installed Plugins", "myCardealer.Header")
    title:Dock(TOP)
    title:DockMargin(8, 8, 8, 8)
    
    local list = myCardealer.UI:List(parent)
    
    if not myCardealer.Core or not myCardealer.Core.GetModulesByTier then 
        myCardealer.UI:Label(list, "Error loading plugin data", "myCardealer.Body"):Dock(TOP):DockMargin(8, 8, 8, 8)
        return
    end
    
    local plugins = myCardealer.Core:GetModulesByTier(myCardealer.TIER_PLUGIN)
    
    if table.Count(plugins) == 0 then
        myCardealer.UI:Label(list, "No plugins installed", "myCardealer.Body"):Dock(TOP):DockMargin(8, 8, 8, 8)
        return
    end
    
    for name, mod in SortedPairs(plugins) do
        local state = mod.State == 4 and "Enabled" or "Disabled"
        local auto = mod.Data.AutoEnable ~= false and "Auto" or "Manual"
        local stateColor = mod.State == 4 and myCardealer.UI:Color("Success") or myCardealer.UI:Color("TextDim")
        
        myCardealer.UI:ListItem(list, name, state .. " | " .. auto, stateColor)
    end
end

function Manager:ShowSlots(parent)
    if not IsValid(parent) then return end
    parent:Clear()
    
    local title = myCardealer.UI:Label(parent, "Core Slots", "myCardealer.Header")
    title:Dock(TOP)
    title:DockMargin(8, 8, 8, 4)
    
    local desc = myCardealer.UI:Label(parent, "Required slots marked with *", "myCardealer.Small")
    desc:Dock(TOP)
    desc:DockMargin(8, 0, 8, 8)
    
    local list = myCardealer.UI:List(parent)
    
    if not myCardealer.Core or not myCardealer.Core.CoreModules then
        myCardealer.UI:Label(list, "Error loading slot data", "myCardealer.Body"):Dock(TOP):DockMargin(8, 8, 8, 8)
        return
    end
    
    for slotName, slot in SortedPairs(myCardealer.Core.CoreModules) do
        local current = slot.Current or "None"
        local options = table.Count(slot.Modules or {})
        local required = slot.Required
        
        local statusText = "→ " .. current
        if not slot.Current and required then
            statusText = statusText .. " (REQUIRED)"
        end
        
        local color = slot.Current and myCardealer.UI:Color("Success") or 
                      (required and myCardealer.UI:Color("Error") or myCardealer.UI:Color("Warning"))
        
        local titleText = slotName .. (required and " *" or "")
        local subtitle = statusText .. " (" .. options .. " option" .. (options ~= 1 and "s" or "") .. ")"
        
        myCardealer.UI:ListItem(list, titleText, subtitle, color)
    end
end

-- Network: Receive refresh command from server
net.Receive("myCardealer.ExecuteRefresh", function()
    notification.AddLegacy("System refreshing...", NOTIFY_GENERIC, 3)
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

-- Bind to F6 (optional)
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