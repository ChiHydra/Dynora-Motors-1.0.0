--[[
    myCardealer - Modular Car Dealer Framework
    Entry point + Core Event Bus + Module System (merged)
]]

myCardealer = myCardealer or {}
myCardealer.Version = "1.0.0"
myCardealer.Loaded = false

-- Realm detection
local function IsServer() return SERVER or false end
local function IsClient() return CLIENT or false end

--[[-------------------------------------------------------------------------
    CORE EVENT BUS (Pub/Sub)
---------------------------------------------------------------------------]]

myCardealer.Core = myCardealer.Core or {}
myCardealer.Core.Modules = {}
myCardealer.Core.Events = {}
myCardealer.Core.Hooks = {}
myCardealer.Core.Ready = false

local MODULE_STATE = {
    REGISTERED = 1,
    LOADING = 2,
    LOADED = 3,
    ENABLED = 4,
    ERROR = 5,
    DISABLED = 6
}

-- Subscribe to event
function myCardealer.Core:On(eventName, listenerId, callback, priority)
    if not isstring(eventName) then error("Event name must be a string") end
    if not isstring(listenerId) then error("Listener ID must be a string") end
    if not isfunction(callback) then error("Callback must be a function") end
    
    priority = tonumber(priority) or 100
    
    self.Events[eventName] = self.Events[eventName] or {}
    self.Events[eventName][priority] = self.Events[eventName][priority] or {}
    self.Events[eventName][priority][listenerId] = callback
    
    self.Hooks[listenerId] = {event = eventName, priority = priority}
    return true
end

-- Unsubscribe
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

-- Remove all by prefix
function myCardealer.Core:OffAll(listenerPrefix)
    for id, data in pairs(self.Hooks) do
        if string.StartWith(id, listenerPrefix) then
            self:Off(data.event, id)
        end
    end
end

-- Emit event
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
                ErrorNoHalt(string.format("[myCardealer] Event '%s' listener '%s' error: %s\n", 
                    eventName, listenerId, tostring(result)))
            end
        end
    end
    return results
end

-- Async emit
function myCardealer.Core:EmitAsync(eventName, callback, ...)
    local args = {...}
    timer.Simple(0, function()
        local results = self:Emit(eventName, unpack(args))
        if callback then pcall(callback, results) end
    end)
end

--[[-------------------------------------------------------------------------
    MODULE REGISTRY
---------------------------------------------------------------------------]]

function myCardealer.Core:RegisterModule(moduleData)
    if not istable(moduleData) then error("Module data must be a table") end
    
    local name = moduleData.Name
    if not isstring(name) or name == "" then error("Module must have a valid Name") end
    if self.Modules[name] then
        ErrorNoHalt(string.format("[myCardealer] Module '%s' already registered!\n", name))
        return nil
    end
    
    -- Validate dependencies
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
        Error = nil
    }
    
    self.Modules[name] = entry
    self:Emit("Core:ModuleRegistered", name, moduleData)
    return entry
end

function myCardealer.Core:GetModule(name)
    return self.Modules[name]
end

function myCardealer.Core:HasModule(name)
    local mod = self.Modules[name]
    return mod and mod.State >= MODULE_STATE.LOADED
end

function myCardealer.Core:IsModuleEnabled(name)
    local mod = self.Modules[name]
    return mod and mod.State == MODULE_STATE.ENABLED
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
    
    -- Load dependencies first
    if mod.Data.Dependencies then
        for _, dep in ipairs(mod.Data.Dependencies) do
            if not self:EnableModule(dep) then
                mod.State = MODULE_STATE.ERROR
                mod.Error = "Failed to load dependency: " .. dep
                return false
            end
        end
    end
    
    -- Initialize
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
    self:Emit("Core:ModuleEnabled", name, mod.Data, mod.LoadTime)
    
    print(string.format("[myCardealer] Module '%s' enabled (%.3f ms)", name, (mod.LoadTime or 0) * 1000))
    return true
end

function myCardealer.Core:DisableModule(name)
    local mod = self.Modules[name]
    if not mod or mod.State ~= MODULE_STATE.ENABLED then return false end
    
    if mod.Data.Shutdown then pcall(mod.Data.Shutdown, mod.Data) end
    self:OffAll(name .. ":")
    
    mod.State = MODULE_STATE.DISABLED
    mod.Enabled = false
    self:Emit("Core:ModuleDisabled", name)
    return true
end

function myCardealer.Core:GetAllModules()
    return self.Modules
end

function myCardealer.Core:GetEnabledModules()
    local enabled = {}
    for name, mod in pairs(self.Modules) do
        if mod.State == MODULE_STATE.ENABLED then enabled[name] = mod end
    end
    return enabled
end

function myCardealer.Core:Initialize()
    if self.Ready then return end
    print("[myCardealer] Initializing core...")
    
    self:Emit("Core:PreInitialize")
    
    for name, mod in pairs(self.Modules) do
        if mod.Data.AutoEnable ~= false then
            self:EnableModule(name)
        end
    end
    
    self.Ready = true
    self:Emit("Core:Ready")
    print("[myCardealer] Ready! " .. table.Count(self.Modules) .. " modules loaded")
end

function myCardealer.Core:DebugPrint()
    print("=== myCardealer Debug ===")
    print("Events: " .. table.Count(self.Events))
    for event, listeners in pairs(self.Events) do
        local count = 0
        for _, subs in pairs(listeners) do count = count + table.Count(subs) end
        print("  - " .. event .. ": " .. count .. " listeners")
    end
    print("\nModules:")
    for name, mod in SortedPairs(self.Modules) do
        local stateStr = "UNKNOWN"
        for k, v in pairs(MODULE_STATE) do if v == mod.State then stateStr = k break end end
        print(string.format("  - %s: %s", name, stateStr))
    end
    print("========================")
end

--[[-------------------------------------------------------------------------
    MODULE BASE CLASS
---------------------------------------------------------------------------]]

myCardealer.Module = myCardealer.Module or {}
myCardealer.Module.__index = myCardealer.Module

function myCardealer.Module:New(name)
    if not isstring(name) or name == "" then error("Module name required") end
    local obj = setmetatable({}, self)
    obj.Name = name
    obj.Dependencies = {}
    obj.Config = {}
    obj.AutoEnable = true
    obj._hooks = {}
    obj._netMessages = {}
    obj._conCommands = {}
    obj._timers = {}
    return obj
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

-- Networking
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

function myCardealer.Module:Register()
    local data = {
        Name = self.Name,
        Dependencies = self.Dependencies,
        Config = self.Config,
        AutoEnable = self.AutoEnable,
        Initialize = function() 
            if self.Initialize then return self:Initialize() end
            return true
        end,
        Shutdown = function()
            if self.Shutdown then return self:Shutdown() end
        end
    }
    self._coreEntry = myCardealer.Core:RegisterModule(data)
    if self._coreEntry then
        print(string.format("[myCardealer] Module '%s' registered", self.Name))
    end
    return self
end

--[[-------------------------------------------------------------------------
    FILE LOADING SYSTEM
---------------------------------------------------------------------------]]

local loadQueue = {shared = {}, server = {}, client = {}}

function myCardealer:AddToQueue(path, realm)
    if realm == "shared" then table.insert(loadQueue.shared, path)
    elseif realm == "server" and IsServer() then table.insert(loadQueue.server, path)
    elseif realm == "client" and (IsClient() or IsServer()) then table.insert(loadQueue.client, path)
    end
end

function myCardealer:IncludeFile(path, realm)
    local success, err = pcall(function()
        if realm == "client" and IsServer() then AddCSLuaFile(path)
        elseif (realm == "shared") or (realm == "server" and IsServer()) or (realm == "client" and IsClient()) then
            include(path)
        end
    end)
    if not success then
        ErrorNoHalt("[myCardealer] Failed to load '" .. path .. "': " .. tostring(err) .. "\n")
        return false
    end
    return true
end

function myCardealer:ScanDirectory(basePath, recursive)
    local files, folders = file.Find(basePath .. "/*", "LUA")
    for _, filename in ipairs(files or {}) do
        if not string.EndsWith(filename, ".lua") then continue end
        local fullPath = basePath .. "/" .. filename
        local realm = "shared"
        if string.StartWith(filename, "sv_") then realm = "server"
        elseif string.StartWith(filename, "cl_") then realm = "client"
        elseif string.StartWith(filename, "sh_") then realm = "shared"
        end
        self:AddToQueue(fullPath, realm)
    end
    if recursive then
        for _, folder in ipairs(folders or {}) do
            if not string.StartWith(folder, "_") then
                self:ScanDirectory(basePath .. "/" .. folder, true)
            end
        end
    end
end

function myCardealer:LoadFiles()
    print("[myCardealer] Loading v" .. self.Version .. "...")
    
    -- Core is already loaded (this file), just load modules
    self:ScanDirectory("mycardealer/modules", true)
    
    -- Execute queue
    print("[myCardealer] Loading shared files...")
    for _, path in ipairs(loadQueue.shared) do self:IncludeFile(path, "shared") end
    
    if IsServer() then
        print("[myCardealer] Loading server files...")
        for _, path in ipairs(loadQueue.server) do self:IncludeFile(path, "server") end
    end
    
    print("[myCardealer] Loading client files...")
    for _, path in ipairs(loadQueue.client) do self:IncludeFile(path, "client") end
    
    self.Loaded = true
    myCardealer.Core:Initialize()
    print("[myCardealer] Framework loaded successfully!")
end

--[[-------------------------------------------------------------------------
    SERVER/CLIENT EXTENSIONS
---------------------------------------------------------------------------]]

if SERVER then
    -- Database abstraction
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
    
    -- Player data
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
    hook.Add("Initialize", "myCardealer_DBInit", function()
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
    
    -- Debug command
    concommand.Add("cardealer_debug", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        myCardealer.Core:DebugPrint()
    end)
else
    -- Client UI helpers
    myCardealer.UI = {
        Panels = {},
        Fonts = {}
    }
    
    function myCardealer.UI:RegisterFont(name, fontData)
        surface.CreateFont("myCardealer." .. name, fontData)
        self.Fonts[name] = true
    end
    
    function myCardealer.UI:CreatePanel(name, parent)
        local panel = vgui.Create("DPanel", parent)
        self.Panels[panel] = name
        return panel
    end
    
    -- Default fonts
    myCardealer.UI:RegisterFont("Header", {font = "Roboto", size = 24, weight = 700})
    myCardealer.UI:RegisterFont("Body", {font = "Roboto", size = 16, weight = 400})
    myCardealer.UI:RegisterFont("Small", {font = "Roboto", size = 12, weight = 400})
    
    -- Request tracking
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

-- Begin loading immediately
myCardealer:LoadFiles()