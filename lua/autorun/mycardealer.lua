--[[
    myCardealer - Modular Car Dealer Framework
    Three-tier architecture: Core (always) → Core Modules (swappable) → Plugins (additive)
]]

myCardealer = myCardealer or {}
myCardealer.Version = "2.1.0"
myCardealer.Loaded = false

local IsServer = function() return SERVER end
local IsClient = function() return CLIENT end

--[[-------------------------------------------------------------------------
    TYPE CONSTANTS
---------------------------------------------------------------------------]]

myCardealer.TIER_CORE = 1           -- Always loaded infrastructure
myCardealer.TIER_CORE_MODULE = 2    -- Swappable infrastructure  
myCardealer.TIER_PLUGIN = 3         -- Additive features

--[[-------------------------------------------------------------------------
    CORE EVENT BUS
---------------------------------------------------------------------------]]

myCardealer.Core = {
    Modules = {},
    CoreModules = {},
    Events = {},
    Hooks = {},
    Ready = false,
    TierLoaded = {false, false, false}
}

local MODULE_STATE = {
    REGISTERED = 1,
    LOADING = 2,
    LOADED = 3,
    ENABLED = 4,
    ERROR = 5,
    DISABLED = 6
}

function myCardealer.Core:On(eventName, listenerId, callback, priority)
    priority = tonumber(priority) or 100
    self.Events[eventName] = self.Events[eventName] or {}
    self.Events[eventName][priority] = self.Events[eventName][priority] or {}
    self.Events[eventName][priority][listenerId] = callback
    self.Hooks[listenerId] = {event = eventName, priority = priority}
    return true
end

function myCardealer.Core:Off(eventName, listenerId)
    if not self.Events[eventName] then return end
    for priority, listeners in pairs(self.Events[eventName]) do
        if listeners[listenerId] then
            listeners[listenerId] = nil
            self.Hooks[listenerId] = nil
            return true
        end
    end
    return false
end

function myCardealer.Core:OffAll(listenerPrefix)
    for id, data in pairs(self.Hooks) do
        if string.StartWith(id, listenerPrefix) then
            self:Off(data.event, id)
        end
    end
end

function myCardealer.Core:Emit(eventName, ...)
    if not self.Events[eventName] then return {} end
    local results = {}
    for priority, listeners in SortedPairs(self.Events[eventName]) do
        for listenerId, callback in pairs(listeners) do
            local success, result = pcall(callback, ...)
            if success then
                results[listenerId] = result
                if result == false then
                    results._cancelled = true
                    results._cancelledBy = listenerId
                    return results
                end
            else
                ErrorNoHalt(string.format("[myCardealer] Event '%s' error: %s\n", 
                    eventName, tostring(result)))
            end
        end
    end
    return results
end

--[[-------------------------------------------------------------------------
    TIER REGISTRY
---------------------------------------------------------------------------]]

function myCardealer.Core:RegisterTier(tier, name)
    if self.TierLoaded[tier] then
        ErrorNoHalt(string.format("[myCardealer] Tier %d (%s) already loaded!\n", tier, name))
        return
    end
    print(string.format("[myCardealer] ========== Tier %d: %s ==========", tier, name))
end

function myCardealer.Core:MarkTierLoaded(tier)
    self.TierLoaded[tier] = true
    self:Emit("Core:TierLoaded", tier)
end

function myCardealer.Core:GetModulesByTier(tier)
    local result = {}
    for name, mod in pairs(self.Modules) do
        if mod.Type == tier then
            result[name] = mod
        end
    end
    return result
end

--[[-------------------------------------------------------------------------
    CORE MODULE SLOTS (Tier 2)
---------------------------------------------------------------------------]]

function myCardealer.Core:RegisterCoreSlot(slotName, options)
    options = options or {}
    self.CoreModules[slotName] = {
        Slot = slotName,
        Current = nil,
        Required = options.Required ~= false,
        Multiple = options.Multiple or false,
        Default = options.Default,
        Modules = {}
    }
    print(string.format("[myCardealer] [Slot] Registered: %s", slotName))
end

function myCardealer.Core:RegisterCoreModule(moduleData)
    if not moduleData.Slot then
        error("Core modules must specify a Slot")
    end
    
    local slot = self.CoreModules[moduleData.Slot]
    if not slot then
        error(string.format("Unknown slot '%s'", moduleData.Slot))
    end
    
    moduleData.ModuleType = myCardealer.TIER_CORE_MODULE
    moduleData._isCoreModule = true
    slot.Modules[moduleData.Name] = moduleData
    
    local shouldAuto = false
    if moduleData.IsDefault and not slot.Current then
        shouldAuto = true
    elseif slot.Required and table.Count(slot.Modules) == 1 and not slot.Current then
        shouldAuto = true
    end
    
    if shouldAuto then
        moduleData.AutoEnable = true
        slot.Current = moduleData.Name
        print(string.format("[myCardealer] [Slot] Auto-selected '%s' for '%s'", 
            moduleData.Name, moduleData.Slot))
    else
        moduleData.AutoEnable = false
    end
    
    return self:RegisterModule(moduleData)
end

--[[-------------------------------------------------------------------------
    PLUGIN REGISTRATION (Tier 3)
---------------------------------------------------------------------------]]

function myCardealer.Core:RegisterPlugin(moduleData)
    moduleData.ModuleType = myCardealer.TIER_PLUGIN
    moduleData._isPlugin = true
    return self:RegisterModule(moduleData)
end

--[[-------------------------------------------------------------------------
    UNIFIED MODULE REGISTRY
---------------------------------------------------------------------------]]

function myCardealer.Core:RegisterModule(moduleData)
    if not istable(moduleData) then error("Module data must be a table") end
    
    local name = moduleData.Name
    if not isstring(name) or name == "" then error("Module must have a valid Name") end
    if self.Modules[name] then
        ErrorNoHalt(string.format("[myCardealer] Module '%s' already registered!\n", name))
        return nil
    end
    
    if moduleData.Dependencies then
        for _, dep in ipairs(moduleData.Dependencies) do
            if not self.Modules[dep] then
                ErrorNoHalt(string.format("[myCardealer] Module '%s' requires missing dependency '%s'\n", name, dep))
                return nil
            end
        end
    end
    
    local entry = {
        Name = name,
        Data = moduleData,
        State = MODULE_STATE.REGISTERED,
        Enabled = false,
        LoadTime = 0,
        Error = nil,
        Type = moduleData.ModuleType or myCardealer.TIER_PLUGIN,
        Tier = moduleData.ModuleType
    }
    
    self.Modules[name] = entry
    self:Emit("Core:ModuleRegistered", name, moduleData, entry.Type)
    return entry
end

function myCardealer.Core:EnableModule(name)
    local mod = self.Modules[name]
    if not mod then 
        ErrorNoHalt(string.format("[myCardealer] Cannot enable unknown module '%s'\n", name))
        return false 
    end
    if mod.State == MODULE_STATE.ENABLED then return true end
    if mod.State == MODULE_STATE.ERROR then return false end
    
    mod.State = MODULE_STATE.LOADING
    
    if mod.Data.Dependencies then
        for _, dep in ipairs(mod.Data.Dependencies) do
            if not self:EnableModule(dep) then
                mod.State = MODULE_STATE.ERROR
                mod.Error = "Failed to load dependency: " .. dep
                return false
            end
        end
    end
    
    if mod.Data._isCoreModule and mod.Data.Slot then
        local slot = self.CoreModules[mod.Data.Slot]
        if slot and slot.Current and slot.Current ~= name then
            mod.State = MODULE_STATE.DISABLED
            mod.Error = string.format("Slot '%s' already filled by '%s'", mod.Data.Slot, slot.Current)
            return false
        end
    end
    
    if mod.Data.Initialize then
        local startTime = SysTime()
        local success, result = pcall(mod.Data.Initialize, mod.Data)
        if not success then
            mod.State = MODULE_STATE.ERROR
            mod.Error = tostring(result)
            ErrorNoHalt(string.format("[myCardealer] Module '%s' init failed: %s\n", name, mod.Error))
            return false
        end
        mod.LoadTime = SysTime() - startTime
    end
    
    mod.State = MODULE_STATE.ENABLED
    mod.Enabled = true
    self:Emit("Core:ModuleEnabled", name, mod.Data, mod.LoadTime, mod.Type)
    
    local typeStr = mod.Type == myCardealer.TIER_CORE_MODULE and "[CORE]" or "[PLUGIN]"
    print(string.format("[myCardealer] %s '%s' enabled (%.3f ms)", typeStr, name, (mod.LoadTime or 0) * 1000))
    return true
end

function myCardealer.Core:DisableModule(name)
    local mod = self.Modules[name]
    if not mod or mod.State ~= MODULE_STATE.ENABLED then return false end
    
    if mod.Data.Shutdown then pcall(mod.Data.Shutdown, mod.Data) end
    self:OffAll(name .. ":")
    
    if mod.Data._isCoreModule and mod.Data.Slot then
        local slot = self.CoreModules[mod.Data.Slot]
        if slot and slot.Current == name then
            slot.Current = nil
        end
    end
    
    mod.State = MODULE_STATE.DISABLED
    mod.Enabled = false
    self:Emit("Core:ModuleDisabled", name, mod.Type)
    return true
end

function myCardealer.Core:SwitchCoreSlot(slotName, moduleName)
    local slot = self.CoreModules[slotName]
    if not slot then return false, "Unknown slot" end
    
    local newModule = slot.Modules[moduleName]
    if not newModule then return false, "Module not found in slot" end
    
    if slot.Current then
        self:DisableModule(slot.Current)
    end
    
    local success = self:EnableModule(moduleName)
    if success then
        slot.Current = moduleName
        newModule._activeSlot = slotName
        self:Emit("Core:SlotChanged", slotName, moduleName)
        return true
    end
    
    return false, "Failed to enable module"
end

function myCardealer.Core:Initialize()
    if self.Ready then return end
    
    self:MarkTierLoaded(myCardealer.TIER_CORE)
    
    print("[myCardealer] Initializing core modules...")
    for name, mod in pairs(self.Modules) do
        if mod.Type == myCardealer.TIER_CORE_MODULE and mod.Data.AutoEnable then
            self:EnableModule(name)
        end
    end
    
    for slotName, slot in pairs(self.CoreModules) do
        if slot.Required and not slot.Current then
            ErrorNoHalt(string.format("[myCardealer] CRITICAL: Slot '%s' has no active module!\n", slotName))
        end
    end
    
    self:MarkTierLoaded(myCardealer.TIER_CORE_MODULE)
    
    print("[myCardealer] Initializing plugins...")
    for name, mod in pairs(self.Modules) do
        if mod.Type == myCardealer.TIER_PLUGIN and mod.Data.AutoEnable ~= false then
            self:EnableModule(name)
        end
    end
    
    self:MarkTierLoaded(myCardealer.TIER_PLUGIN)
    
    self.Ready = true
    self:Emit("Core:Ready")
    print("[myCardealer] ========== Framework Ready ==========")
end

function myCardealer.Core:GetCoreSlot(slotName)
    return self.CoreModules[slotName]
end

function myCardealer.Core:GetActiveCoreModule(slotName)
    local slot = self.CoreModules[slotName]
    return slot and slot.Current and self.Modules[slot.Current]
end

function myCardealer.Core:DebugPrint()
    print("=== myCardealer Debug ===")
    
    print("\nTiers:")
    for i = 1, 3 do
        local status = self.TierLoaded[i] and "LOADED" or "PENDING"
        local name = i == 1 and "Core" or i == 2 and "Core Modules" or "Plugins"
        print(string.format("  [%d] %s: %s", i, name, status))
    end
    
    print("\nCore Slots:")
    for name, slot in pairs(self.CoreModules) do
        local status = slot.Current and ("→ " .. slot.Current) or "EMPTY"
        local req = slot.Required and "*" or ""
        print(string.format("  [%s%s] %s", name, req, status))
    end
    
    print("\nAll Modules:")
    for name, mod in SortedPairs(self.Modules) do
        local tierName = mod.Type == 1 and "CORE" or mod.Type == 2 and "CMOD" or "PLUG"
        local state = mod.State == 4 and "ON" or mod.State == 5 and "ERR" or "OFF"
        print(string.format("  [%s] %s: %s", tierName, name, state))
    end
    print("========================")
end

--[[-------------------------------------------------------------------------
    MODULE BASE CLASS
---------------------------------------------------------------------------]]

myCardealer.Module = {}
myCardealer.Module.__index = myCardealer.Module

function myCardealer.Module:New(name)
    local obj = setmetatable({}, self)
    obj.Name = name
    obj.Dependencies = {}
    obj.Config = {}
    obj.AutoEnable = true
    obj.ModuleType = myCardealer.TIER_PLUGIN
    obj._hooks = {}
    obj._netMessages = {}
    obj._conCommands = {}
    obj._timers = {}
    return obj
end

function myCardealer.Module:ForCore()
    self.ModuleType = myCardealer.TIER_CORE
    return self
end

function myCardealer.Module:ForSlot(slotName, options)
    options = options or {}
    self.ModuleType = myCardealer.TIER_CORE_MODULE
    self.Slot = slotName
    self.IsDefault = options.IsDefault or false
    self.SlotVersion = options.Version or "1.0"
    return self
end

function myCardealer.Module:AsPlugin()
    self.ModuleType = myCardealer.TIER_PLUGIN
    return self
end

function myCardealer.Module:Require(...)
    for _, dep in ipairs({...}) do
        if not table.HasValue(self.Dependencies, dep) then
            table.insert(self.Dependencies, dep)
        end
    end
    return self
end

function myCardealer.Module:SetConfig(key, value)
    self.Config[key] = value
    return self
end

function myCardealer.Module:GetConfig(key, default)
    return self.Config[key] ~= nil and self.Config[key] or default
end

function myCardealer.Module:ManualEnable()
    self.AutoEnable = false
    return self
end

function myCardealer.Module:On(eventName, callback, priority)
    local listenerId = self.Name .. ":" .. eventName
    myCardealer.Core:On(eventName, listenerId, function(...) return callback(self, ...) end, priority)
    table.insert(self._hooks, {event = eventName, id = listenerId})
    return self
end

function myCardealer.Module:Once(eventName, callback, priority)
    local listenerId = self.Name .. ":" .. eventName .. ":once:" .. CurTime()
    local wrapped = function(...)
        myCardealer.Core:Off(eventName, listenerId)
        return callback(self, ...)
    end
    myCardealer.Core:On(eventName, listenerId, wrapped, priority)
    return self
end

function myCardealer.Module:Emit(eventName, ...)
    return myCardealer.Core:Emit(eventName, ...)
end

if SERVER then
    function myCardealer.Module:NetMessage(messageName, handler)
        local fullName = self.Name .. "." .. messageName
        util.AddNetworkString("myCardealer." .. fullName)
        self._netMessages[fullName] = function(len, ply) handler(self, ply, len) end
        net.Receive("myCardealer." .. fullName, self._netMessages[fullName])
        return self
    end
    
    function myCardealer.Module:Send(ply, messageName, ...)
        local fullName = "myCardealer." .. self.Name .. "." .. messageName
        net.Start(fullName)
        self:WriteNetData(...)
        net.Send(ply)
    end
    
    function myCardealer.Module:Broadcast(messageName, ...)
        local fullName = "myCardealer." .. self.Name .. "." .. messageName
        net.Start(fullName)
        self:WriteNetData(...)
        net.Broadcast()
    end
else
    function myCardealer.Module:NetMessage(messageName, handler)
        local fullName = self.Name .. "." .. messageName
        util.AddNetworkString("myCardealer." .. fullName)
        self._netMessages[fullName] = function(len) handler(self, len) end
        net.Receive("myCardealer." .. fullName, self._netMessages[fullName])
        return self
    end
    
    function myCardealer.Module:SendServer(messageName, ...)
        local fullName = "myCardealer." .. self.Name .. "." .. messageName
        net.Start(fullName)
        self:WriteNetData(...)
        net.SendToServer()
    end
end

function myCardealer.Module:WriteNetData(...)
    local args = {...}
    net.WriteUInt(#args, 8)
    for _, v in ipairs(args) do
        local t = type(v)
        if t == "string" then net.WriteString(v)
        elseif t == "number" then net.WriteDouble(v)
        elseif t == "bool" then net.WriteBool(v)
        elseif t == "Entity" or t == "Player" then net.WriteEntity(v)
        elseif t == "table" then net.WriteString(util.TableToJSON(v))
        end
    end
end

function myCardealer.Module:ConCommand(name, callback, autoComplete, helpText)
    local fullName = "cardealer_" .. string.lower(self.Name) .. "_" .. name
    concommand.Add(fullName, function(ply, cmd, args, argStr)
        callback(self, ply, args, argStr)
    end, autoComplete, helpText)
    table.insert(self._conCommands, fullName)
    return self
end

function myCardealer.Module:Timer(identifier, delay, repetitions, callback)
    local fullId = self.Name .. ":" .. identifier
    timer.Create(fullId, delay, repetitions, function()
        local success, err = pcall(callback, self)
        if not success then
            ErrorNoHalt(string.format("[myCardealer] %s timer error: %s\n", self.Name, err))
        end
    end)
    table.insert(self._timers, fullId)
    return self
end

function myCardealer.Module:RemoveTimer(identifier)
    local fullId = self.Name .. ":" .. identifier
    timer.Remove(fullId)
    for i, id in ipairs(self._timers) do
        if id == fullId then table.remove(self._timers, i) break end
    end
    return self
end

function myCardealer.Module:HasModule(name)
    return myCardealer.Core:HasModule(name)
end

function myCardealer.Module:GetModule(name)
    local mod = myCardealer.Core:GetModule(name)
    return mod and mod.Data
end

function myCardealer.Module:GetCoreService(slotName)
    local slot = myCardealer.Core:GetActiveCoreModule(slotName)
    return slot and slot.Data
end

function myCardealer.Module:Register()
    local data = {
        Name = self.Name,
        Dependencies = self.Dependencies,
        Config = self.Config,
        AutoEnable = self.AutoEnable,
        ModuleType = self.ModuleType,
        Slot = self.Slot,
        IsDefault = self.IsDefault,
        SlotVersion = self.SlotVersion,
        Initialize = function() 
            if self.Initialize then return self:Initialize() end
            return true
        end,
        Shutdown = function()
            if self.Shutdown then return self:Shutdown() end
        end
    }
    
    if self.ModuleType == myCardealer.TIER_CORE then
        data.AutoEnable = true
        self._coreEntry = myCardealer.Core:RegisterModule(data)
        if self._coreEntry then
            myCardealer.Core:EnableModule(self.Name)
        end
    elseif self.ModuleType == myCardealer.TIER_CORE_MODULE then
        self._coreEntry = myCardealer.Core:RegisterCoreModule(data)
    else
        self._coreEntry = myCardealer.Core:RegisterPlugin(data)
    end
    
    if self._coreEntry then
        local tierName = self.ModuleType == 1 and "Core" or self.ModuleType == 2 and "CoreMod" or "Plugin"
        print(string.format("[myCardealer] [%s] Registered: %s", tierName, self.Name))
    end
    return self
end

--[[-------------------------------------------------------------------------
    THREE-TIER FILE LOADING WITH DETAILED LOGGING
---------------------------------------------------------------------------]]

local loadQueue = {shared = {}, server = {}, client = {}}
local loadStats = {shared = 0, server = 0, client = 0, total = 0}

function myCardealer:AddToQueue(path, realm, tierName)
    if realm == "shared" then 
        table.insert(loadQueue.shared, {path = path, tier = tierName})
        loadStats.shared = loadStats.shared + 1
    elseif realm == "server" and IsServer() then 
        table.insert(loadQueue.server, {path = path, tier = tierName})
        loadStats.server = loadStats.server + 1
    elseif realm == "client" and (IsClient() or IsServer()) then 
        table.insert(loadQueue.client, {path = path, tier = tierName})
        loadStats.client = loadStats.client + 1
    end
    loadStats.total = loadStats.total + 1
end

function myCardealer:IncludeFile(path, realm, tierName)
    local success, err = pcall(function()
        if realm == "client" and IsServer() then 
            print(string.format("[myCardealer] [AddCSLuaFile] %s", path))
            AddCSLuaFile(path)
        elseif (realm == "shared") or (realm == "server" and IsServer()) or (realm == "client" and IsClient()) then
            print(string.format("[myCardealer] [Include] %s", path))
            include(path)
        end
    end)
    if not success then
        ErrorNoHalt(string.format("[myCardealer] [ERROR] Failed to load '%s': %s\n", path, tostring(err)))
        return false
    end
    return true
end

function myCardealer:ScanDirectory(basePath, recursive, tierName)
    local files, folders = file.Find(basePath .. "/*", "LUA")
    
    -- Log folder being scanned
    if files and #files > 0 or folders and #folders > 0 then
        print(string.format("[myCardealer] [Scan] %s/", basePath))
    end
    
    for _, filename in ipairs(files or {}) do
        if not string.EndsWith(filename, ".lua") then continue end
        
        local fullPath = basePath .. "/" .. filename
        local realm = "shared"
        
        -- Detect realm by prefix
        if string.StartWith(filename, "sv_") then realm = "server"
        elseif string.StartWith(filename, "cl_") then realm = "client"
        elseif string.StartWith(filename, "sh_") then realm = "shared"
        end
        
        self:AddToQueue(fullPath, realm, tierName)
    end
    
    if recursive then
        for _, folder in ipairs(folders or {}) do
            if not string.StartWith(folder, "_") then
                self:ScanDirectory(basePath .. "/" .. folder, true, tierName)
            else
                print(string.format("[myCardealer] [Skip] Disabled: %s/", folder))
            end
        end
    end
end

function myCardealer:ExecuteQueue(tierName)
    local realmName = IsServer() and "Server" or "Client"
    print(string.format("[myCardealer] [%s] Executing queue on %s...", tierName or "Unknown", realmName))
    
    -- Shared files
    if #loadQueue.shared > 0 then
        print(string.format("[myCardealer] [%s] Loading %d shared file(s)...", tierName, #loadQueue.shared))
        for _, item in ipairs(loadQueue.shared) do
            self:IncludeFile(item.path, "shared", item.tier)
        end
    end
    
    -- Server files
    if IsServer() and #loadQueue.server > 0 then
        print(string.format("[myCardealer] [%s] Loading %d server file(s)...", tierName, #loadQueue.server))
        for _, item in ipairs(loadQueue.server) do
            self:IncludeFile(item.path, "server", item.tier)
        end
    end
    
    -- Client files (include on server for AddCSLuaFile, execute on client)
    if #loadQueue.client > 0 then
        local action = IsServer() and "Sending" or "Loading"
        print(string.format("[myCardealer] [%s] %s %d client file(s)...", tierName, action, #loadQueue.client))
        for _, item in ipairs(loadQueue.client) do
            self:IncludeFile(item.path, "client", item.tier)
        end
    end
    
    -- Clear queue for next tier
    loadQueue = {shared = {}, server = {}, client = {}}
end

function myCardealer:LoadFiles()
    print(string.format("[myCardealer] ========================================"))
    print(string.format("[myCardealer] Starting myCardealer v%s", self.Version))
    print(string.format("[myCardealer] ========================================"))
    
    -- Register slots before any files load
    print("[myCardealer] [Setup] Registering core slots...")
    self.Core:RegisterCoreSlot("database", {Required = true, Default = "database_sqlite"})
    self.Core:RegisterCoreSlot("permissions", {Required = true, Default = "permissions_default"})
    self.Core:RegisterCoreSlot("ui", {Required = false, Default = "ui_derma"})
    
    -- TIER 1: Core infrastructure (always loaded)
    self.Core:RegisterTier(1, "Core Infrastructure")
    print("[myCardealer] Scanning mycardealer/core/...")
    self:ScanDirectory("mycardealer/core", true, "Core")
    self:ExecuteQueue("Tier 1")
    
    -- Mark Tier 1 loaded immediately so UI is available
    self.Core.TierLoaded[1] = true
    self.Core:Emit("Core:TierLoaded", 1)
    print("[myCardealer] [Tier 1] Core infrastructure loaded")
    
    -- TIER 2: Core modules (swappable)
    self.Core:RegisterTier(2, "Core Modules")
    print("[myCardealer] Scanning mycardealer/core_modules/...")
    self:ScanDirectory("mycardealer/core_modules", true, "CoreMod")
    
    -- TIER 3: Plugins (additive)
    print("[myCardealer] Scanning mycardealer/plugins/...")
    self:ScanDirectory("mycardealer/plugins", true, "Plugin")
    
    -- Execute remaining tiers
    self:ExecuteQueue("Tier 2-3")
    
    -- Summary
    print(string.format("[myCardealer] [Summary] Total files queued: %d", loadStats.total))
    
    self.Loaded = true
    myCardealer.Core:Initialize()
    print(string.format("[myCardealer] ========================================"))
end

--[[-------------------------------------------------------------------------
    SERVER EXTENSIONS WITH REFRESH HANDLER
---------------------------------------------------------------------------]]

if SERVER then
    -- Network strings for refresh system
    util.AddNetworkString("myCardealer.RequestRefresh")
    util.AddNetworkString("myCardealer.ExecuteRefresh")
    
    -- Database placeholder (replaced by core module)
    myCardealer.Database = {
        Connected = false,
        Type = "sqlite"
    }
    
    function myCardealer.Database:Query(sql, callback)
        if self.Type == "sqlite" then
            local result = sql.Query(sql)
            if callback then callback(result, sql.LastError()) end
            return result
        end
    end
    
    function myCardealer.Database:Escape(str)
        return sql.SQLStr(str)
    end
    
    myCardealer.Players = {}
    
    function myCardealer:GetPlayerData(ply, key, default)
        if not IsValid(ply) then return default end
        local steamId = ply:SteamID()
        self.Players[steamId] = self.Players[steamId] or {}
        if key then
            return self.Players[steamId][key] ~= nil and self.Players[steamId][key] or default
        end
        return self.Players[steamId]
    end
    
    function myCardealer:SetPlayerData(ply, key, value)
        if not IsValid(ply) then return end
        local steamId = ply:SteamID()
        self.Players[steamId] = self.Players[steamId] or {}
        self.Players[steamId][key] = value
        myCardealer.Core:Emit("Player:DataChanged", ply, key, value)
    end
    
    -- Hooks
    hook.Add("Initialize", "myCardealer_Init", function()
        myCardealer.Core:Emit("Database:Initialize")
    end)
    
    hook.Add("PlayerInitialSpawn", "myCardealer_PlayerInit", function(ply)
        timer.Simple(1, function()
            if not IsValid(ply) then return end
            myCardealer:SetPlayerData(ply, "connected", true)
            myCardealer:SetPlayerData(ply, "connectTime", CurTime())
            myCardealer.Core:Emit("Player:Initialized", ply)
        end)
    end)
    
    hook.Add("PlayerDisconnected", "myCardealer_PlayerDisconnect", function(ply)
        myCardealer.Core:Emit("Player:Disconnected", ply)
        timer.Simple(30, function() myCardealer.Players[ply:SteamID()] = nil end)
    end)
    
    -- Console commands
    concommand.Add("cardealer_debug", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        myCardealer.Core:DebugPrint()
    end)
    
    concommand.Add("cardealer_switch", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        if #args < 2 then 
            print("Usage: cardealer_switch <slot> <module>")
            return 
        end
        local success, err = myCardealer.Core:SwitchCoreSlot(args[1], args[2])
        print(success and "Switched successfully" or ("Failed: " .. err))
    end)
    
    -- REFRESH HANDLER
    concommand.Add("cardealer_refresh", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        
        print("[myCardealer] [Refresh] Initiated by " .. (IsValid(ply) and ply:Nick() or "Console"))
        myCardealer.Core:Emit("System:PreRefresh", ply)
        
        -- Notify all clients
        net.Start("myCardealer.ExecuteRefresh")
        net.Broadcast()
        
        -- Server refreshes after delay
        timer.Simple(1.5, function()
            print("[myCardealer] [Refresh] Executing lua_refresh...")
            RunConsoleCommand("lua_refresh")
        end)
    end)
    
    -- Handle client refresh request
    net.Receive("myCardealer.RequestRefresh", function(len, ply)
        if not ply:IsSuperAdmin() then return end
        
        print("[myCardealer] [Refresh] Requested by client: " .. ply:Nick())
        myCardealer.Core:Emit("System:PreRefresh", ply)
        
        net.Start("myCardealer.ExecuteRefresh")
        net.Broadcast()
        
        timer.Simple(1.5, function()
            RunConsoleCommand("lua_refresh")
        end)
    end)
    
else
    -- CLIENT EXTENSIONS
    
    net.Receive("myCardealer.ExecuteRefresh", function()
        notification.AddLegacy("myCardealer refreshing...", NOTIFY_GENERIC, 3)
        surface.PlaySound("buttons/button15.wav")
        
        timer.Simple(1, function()
            RunConsoleCommand("lua_refresh")
        end)
    end)
    
    -- UI infrastructure
    myCardealer.UI = {
        Panels = {},
        Fonts = {},
        Colors = {
            Primary = Color(157, 78, 221),
            PrimaryDark = Color(120, 60, 180),
            Secondary = Color(30, 30, 30),
            Background = Color(20, 20, 20),
            Surface = Color(35, 35, 35),
            SurfaceLit = Color(45, 45, 45),
            Text = Color(255, 255, 255),
            TextDim = Color(180, 180, 180),
            Error = Color(220, 50, 50),
            Success = Color(50, 220, 50),
            Warning = Color(220, 180, 50)
        }
    }
    
    function myCardealer.UI:Color(name)
        return self.Colors[name] or color_white
    end
    
    -- Fonts
    surface.CreateFont("myCardealer.Header", {font = "Roboto", size = 20, weight = 700})
    surface.CreateFont("myCardealer.Title", {font = "Roboto", size = 16, weight = 600})
    surface.CreateFont("myCardealer.Body", {font = "Roboto", size = 14, weight = 400})
    surface.CreateFont("myCardealer.Small", {font = "Roboto", size = 12, weight = 400})
    surface.CreateFont("myCardealer.Mono", {font = "Consolas", size = 13, weight = 400})
    
    -- Registered frames
    local PANEL_FRAME = {}
    function PANEL_FRAME:Init()
        self:SetTitle("")
        self:ShowCloseButton(false)
        self:DockPadding(0, 28, 0, 0)
        
        self.TitleBar = vgui.Create("DPanel", self)
        self.TitleBar:Dock(TOP)
        self.TitleBar:SetTall(28)
        self.TitleBar.Paint = function(p, w, h)
            surface.SetDrawColor(myCardealer.UI:Color("Primary"))
            surface.DrawRect(0, 0, w, h)
            if self._Title then
                draw.SimpleText(self._Title, "myCardealer.Title", 10, 4, color_white)
            end
        end
        
        local close = vgui.Create("DButton", self.TitleBar)
        close:Dock(RIGHT)
        close:SetWide(28)
        close:SetText("×")
        close:SetFont("myCardealer.Header")
        close:SetTextColor(color_white)
        close.Paint = function() end
        close.DoClick = function() self:Close() end
        
        self.Content = vgui.Create("DPanel", self)
        self.Content:Dock(FILL)
        self.Content:DockPadding(8, 8, 8, 8)
        self.Content.Paint = function(p, w, h)
            surface.SetDrawColor(myCardealer.UI:Color("Background"))
            surface.DrawRect(0, 0, w, h)
        end
    end
    function PANEL_FRAME:SetTitleText(t) self._Title = t end
    function PANEL_FRAME:GetContent() return self.Content end
    function PANEL_FRAME:Paint(w, h)
        surface.SetDrawColor(0, 0, 0, 100)
        surface.DrawRect(4, 4, w, h)
        surface.SetDrawColor(myCardealer.UI:Color("Surface"))
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(myCardealer.UI:Color("Primary"))
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end
    vgui.Register("myCardealer.Frame", PANEL_FRAME, "DFrame")
    
    local PANEL_SIDEBAR = {}
    function PANEL_SIDEBAR:Init()
        self:DockPadding(0, 28, 0, 0)
        
        self.TitleBar = vgui.Create("DPanel", self)
        self.TitleBar:Dock(TOP)
        self.TitleBar:SetTall(28)
        self.TitleBar.Paint = function(p, w, h)
            surface.SetDrawColor(myCardealer.UI:Color("Primary"))
            surface.DrawRect(0, 0, w, h)
        end
        
        self.Sidebar = vgui.Create("DPanel", self)
        self.Sidebar:Dock(LEFT)
        self.Sidebar:SetWide(180)
        self.Sidebar.Paint = function(p, w, h)
            surface.SetDrawColor(myCardealer.UI:Color("Secondary"))
            surface.DrawRect(0, 0, w, h)
        end
        
        self.SidebarList = vgui.Create("DScrollPanel", self.Sidebar)
        self.SidebarList:Dock(FILL)
        self.SidebarList:DockPadding(4, 4, 4, 4)
        self.SidebarList.VBar:SetWide(6)
        
        self.MainContent = vgui.Create("DPanel", self)
        self.MainContent:Dock(FILL)
        self.MainContent.Paint = function(p, w, h)
            surface.SetDrawColor(myCardealer.UI:Color("Background"))
            surface.DrawRect(0, 0, w, h)
        end
        
        self.BottomBar = vgui.Create("DPanel", self)
        self.BottomBar:Dock(BOTTOM)
        self.BottomBar:SetTall(44)
        self.BottomBar.Paint = function(p, w, h)
            surface.SetDrawColor(myCardealer.UI:Color("Surface"))
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(myCardealer.UI:Color("Primary"))
            surface.DrawRect(0, 0, w, 1)
        end
    end
    function PANEL_SIDEBAR:AddSidebarItem(name, callback)
        local btn = vgui.Create("DButton", self.SidebarList)
        btn:Dock(TOP)
        btn:SetTall(36)
        btn:DockMargin(0, 0, 4, 2)
        btn:SetText("")
        btn.Paint = function(p, w, h)
            local col = p:IsHovered() and myCardealer.UI:Color("SurfaceLit") or myCardealer.UI:Color("Surface")
            surface.SetDrawColor(col)
            surface.DrawRect(0, 0, w, h)
            if p.Selected then
                surface.SetDrawColor(myCardealer.UI:Color("Primary"))
                surface.DrawRect(0, 0, 3, h)
            end
            draw.SimpleText(name, "myCardealer.Body", 10, 9, color_white)
        end
        btn.DoClick = function()
            for _, child in pairs(self.SidebarList:GetCanvas():GetChildren()) do
                if child.Selected then child.Selected = false end
            end
            btn.Selected = true
            callback()
        end
        return btn
    end
    function PANEL_SIDEBAR:GetContent() return self.MainContent end
    function PANEL_SIDEBAR:GetBottomBar() return self.BottomBar end
    function PANEL_SIDEBAR:Paint(w, h)
        surface.SetDrawColor(0, 0, 0, 100)
        surface.DrawRect(4, 4, w, h)
        surface.SetDrawColor(myCardealer.UI:Color("Surface"))
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(myCardealer.UI:Color("Primary"))
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end
    vgui.Register("myCardealer.Frame.Sidebar", PANEL_SIDEBAR, "EditablePanel")
    
    
    function myCardealer.UI:Button(parent, label, color)
        local btn = vgui.Create("DButton", parent)
        btn:SetText("")
        btn:SetTall(32)
        local baseColor = color or self:Color("Primary")
        local hoverColor = Color(math.min(baseColor.r + 20, 255), math.min(baseColor.g + 20, 255), math.min(baseColor.b + 20, 255))
        btn.Paint = function(p, w, h)
            surface.SetDrawColor(p:IsHovered() and hoverColor or baseColor)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(255, 255, 255, 20)
            surface.DrawRect(0, 0, w, h/2)
            draw.SimpleText(label, "myCardealer.Body", w/2, h/2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return btn
    end
    
    function myCardealer.UI:List(parent)
        local scroll = vgui.Create("DScrollPanel", parent)
        scroll:Dock(FILL)
        scroll.VBar:SetWide(6)
        scroll.VBar.Paint = function(p, w, h) surface.SetDrawColor(self:Color("Secondary")) surface.DrawRect(0, 0, w, h) end
        scroll.VBar.btnGrip.Paint = function(p, w, h) surface.SetDrawColor(self:Color("Primary")) surface.DrawRect(0, 0, w, h) end
        return scroll
    end
    
    function myCardealer.UI:ListItem(parent, title, subtitle, color)
        local item = vgui.Create("DButton", parent)
        item:Dock(TOP)
        item:DockMargin(0, 0, 6, 2)
        item:SetTall(48)
        item:SetText("")
        local baseColor = self:Color("Surface")
        local litColor = self:Color("SurfaceLit")
        local accent = color or self:Color("Primary")
        item.Paint = function(p, w, h)
            if p.Selected then
                surface.SetDrawColor(Color(40, 50, 40))
                surface.DrawRect(0, 0, w, h)
                surface.SetDrawColor(accent)
                surface.DrawRect(0, 0, 3, h)
            else
                surface.SetDrawColor(p:IsHovered() and litColor or baseColor)
                surface.DrawRect(0, 0, w, h)
            end
            draw.SimpleText(title, "myCardealer.Body", 10, 6, color_white)
            if subtitle then
                draw.SimpleText(subtitle, "myCardealer.Small", 10, 26, self:Color("TextDim"))
            end
        end
        return item
    end
    
    function myCardealer.UI:Label(parent, text, font)
        local lbl = vgui.Create("DLabel", parent)
        lbl:SetFont(font or "myCardealer.Body")
        lbl:SetText(text)
        lbl:SetTextColor(self:Color("Text"))
        lbl:SizeToContents()
        return lbl
    end
    
    myCardealer.PendingRequests = {}
    function myCardealer:Request(requestId, timeout)
        self.PendingRequests[requestId] = {time = CurTime(), timeout = timeout or 10}
    end
    function myCardealer:Confirm(requestId)
        self.PendingRequests[requestId] = nil
    end
    
    timer.Create("myCardealer_RequestCleanup", 5, 0, function()
        local now = CurTime()
        for id, req in pairs(myCardealer.PendingRequests) do
            if now - req.time > req.timeout then
                myCardealer.PendingRequests[id] = nil
                myCardealer.Core:Emit("Request:Timeout", id)
            end
        end
    end)
    
    hook.Add("InitPostEntity", "myCardealer_ClientReady", function()
        timer.Simple(2, function() myCardealer.Core:Emit("Client:Ready") end)
    end)
end

--[[-------------------------------------------------------------------------
    CONFIGURATION
---------------------------------------------------------------------------]]

myCardealer.Config = {
    DebugMode = false,
    LogLevel = "info",
    MaxEventListeners = 100,
    ModuleLoadTimeout = 5,
    Theme = {
        Primary = Color(157, 78, 221),
        Secondary = Color(30, 30, 30),
        Background = Color(20, 20, 20),
        Text = Color(255, 255, 255),
        Error = Color(220, 50, 50),
        Success = Color(50, 220, 50)
    },
    NetRateLimit = {
        Default = 1,
        Admin = 0.1
    }
}

if SERVER then
    myCardealer.Config.Database = {
        Type = "sqlite",
        MySQL = {
            Host = "localhost",
            Port = 3306,
            Database = "mycardealer",
            Username = "root",
            Password = ""
        }
    }
    myCardealer.Config.Security = {
        MaxFailedAttempts = 5,
        LockoutDuration = 300
    }
end

function myCardealer:GetConfig(key, default)
    local keys = string.Explode(".", key)
    local current = self.Config
    for _, k in ipairs(keys) do
        current = current[k]
        if current == nil then return default end
    end
    return current
end

function myCardealer:SetConfig(key, value)
    local keys = string.Explode(".", key)
    local current = self.Config
    for i = 1, #keys - 1 do
        if not current[keys[i]] then current[keys[i]] = {} end
        current = current[keys[i]]
    end
    current[keys[#keys]] = value
end

--[[-------------------------------------------------------------------------
    STARTUP
---------------------------------------------------------------------------]]

myCardealer:LoadFiles()