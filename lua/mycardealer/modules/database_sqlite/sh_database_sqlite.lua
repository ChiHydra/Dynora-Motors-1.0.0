--[[
    Core Module: SQLite Database
    Provides database functionality using GMod's built-in SQLite
]]

local SQLite = myCardealer.Module:New("database_sqlite")
    :ForSlot("database", {IsDefault = true, Version = "1.0"})
    :SetConfig("AutoCreateTables", true)

-- Query execution with error handling
function SQLite:Query(sql, callback)
    print(string.format("[DB] Query: %s", sql:sub(1, 80)))
    
    local result = sql.Query(sql)
    local err = sql.LastError()
    
    if err then
        ErrorNoHalt(string.format("[DB] SQL Error: %s\nQuery: %s\n", err, sql))
        if callback then callback(nil, err) end
        return nil, err
    end
    
    if callback then callback(result, nil) end
    return result, nil
end

-- Escape string for SQL
function SQLite:Escape(value)
    return sql.SQLStr(tostring(value))
end

-- Insert data into table
-- SQLite:Insert("vehicles", {steamid = "STEAM_0:1:123", class = "jeep"})
function SQLite:Insert(tableName, data, callback)
    local columns = {}
    local values = {}
    
    for k, v in pairs(data) do
        table.insert(columns, k)
        table.insert(values, self:Escape(v))
    end
    
    local sql = string.format("INSERT INTO %s (%s) VALUES (%s)",
        tableName,
        table.concat(columns, ", "),
        table.concat(values, ", "))
    
    return self:Query(sql, callback)
end

-- Update records
-- SQLite:Update("vehicles", {health = 80}, "id = 5")
function SQLite:Update(tableName, data, where, callback)
    local sets = {}
    
    for k, v in pairs(data) do
        table.insert(sets, k .. "=" .. self:Escape(v))
    end
    
    local sql = string.format("UPDATE %s SET %s WHERE %s",
        tableName,
        table.concat(sets, ", "),
        where)
    
    return self:Query(sql, callback)
end

-- Select records
-- SQLite:Select("vehicles", "*", "steamid = 'STEAM_0:1:123'")
function SQLite:Select(tableName, columns, where, callback)
    local cols = istable(columns) and table.concat(columns, ", ") or columns or "*"
    local sql = string.format("SELECT %s FROM %s", cols, tableName)
    
    if where and where ~= "" then
        sql = sql .. " WHERE " .. where
    end
    
    return self:Query(sql, callback)
end

-- Delete records
-- SQLite:Delete("vehicles", "id = 5")
function SQLite:Delete(tableName, where, callback)
    local sql = string.format("DELETE FROM %s WHERE %s", tableName, where)
    return self:Query(sql, callback)
end

-- Create table if not exists
function SQLite:CreateTable(name, schema)
    local columns = {}
    for colName, colDef in pairs(schema) do
        table.insert(columns, colName .. " " .. colDef)
    end
    
    local sql = string.format("CREATE TABLE IF NOT EXISTS %s (%s)", 
        name, 
        table.concat(columns, ", "))
    
    return self:Query(sql)
end

-- Initialize database
function SQLite:Initialize()
    print("[database_sqlite] Initializing SQLite database...")
    
    -- Test connection
    local test, err = self:Query("SELECT sqlite_version()")
    if err then
        ErrorNoHalt("[database_sqlite] Failed to connect: " .. err .. "\n")
        return false
    end
    
    print(string.format("[database_sqlite] SQLite version: %s", test and test[1] and test[1]["sqlite_version()"] or "unknown"))
    
    -- Create core tables
    if self:GetConfig("AutoCreateTables") then
        self:CreateCoreTables()
    end
    
    -- Make available globally
    myCardealer.DB = self
    
    -- Emit ready event
    self:Emit("Database:Connected", "sqlite")
    
    return true
end

function SQLite:CreateCoreTables()
    print("[database_sqlite] Creating core tables...")
    
    -- Player vehicles table
    self:CreateTable("mycardealer_vehicles", {
        id = "INTEGER PRIMARY KEY AUTOINCREMENT",
        steamid = "VARCHAR(32) NOT NULL",
        vehicle_class = "VARCHAR(64) NOT NULL",
        vehicle_name = "VARCHAR(128)",
        health = "INTEGER DEFAULT 100",
        fuel = "INTEGER DEFAULT 100",
        stored = "INTEGER DEFAULT 1",
        created_at = "TIMESTAMP DEFAULT CURRENT_TIMESTAMP",
        last_used = "TIMESTAMP",
        data = "TEXT"  -- JSON extra data
    })
    
    -- Create index on steamid
    self:Query("CREATE INDEX IF NOT EXISTS idx_vehicles_steamid ON mycardealer_vehicles(steamid)")
    self:Query("CREATE INDEX IF NOT EXISTS idx_vehicles_stored ON mycardealer_vehicles(stored)")
    
    -- Transactions/economy table
    self:CreateTable("mycardealer_transactions", {
        id = "INTEGER PRIMARY KEY AUTOINCREMENT",
        steamid = "VARCHAR(32) NOT NULL",
        type = "VARCHAR(32) NOT NULL",  -- purchase, sale, insurance, etc.
        amount = "INTEGER",
        description = "TEXT",
        created_at = "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
    })
    
    -- Insurance table
    self:CreateTable("mycardealer_insurance", {
        id = "INTEGER PRIMARY KEY AUTOINCREMENT",
        vehicle_id = "INTEGER NOT NULL",
        steamid = "VARCHAR(32) NOT NULL",
        coverage_type = "VARCHAR(32)",
        expires = "INTEGER",
        active = "INTEGER DEFAULT 1"
    })
    
    print("[database_sqlite] Core tables created")
end

function SQLite:Shutdown()
    print("[database_sqlite] Database connection closed")
end

SQLite:Register()




--[[

-- In another module:
local DB = myCardealer.DB  -- or self:GetCoreService("database")

-- Insert a vehicle
DB:Insert("mycardealer_vehicles", {
    steamid = ply:SteamID(),
    vehicle_class = "jeep",
    vehicle_name = "Jeep Wrangler",
    health = 100,
    stored = 1
})

-- Get player's vehicles
DB:Select("mycardealer_vehicles", "*", "steamid = '" .. DB:Escape(ply:SteamID()) .. "' AND stored = 1", function(results, err)
    if results then
        for _, row in ipairs(results) do
            print(row.vehicle_name)
        end
    end
end)

-- Update vehicle health
DB:Update("mycardealer_vehicles", {health = 50}, "id = " .. vehicleId)

-- Delete vehicle
DB:Delete("mycardealer_vehicles", "id = " .. vehicleId)


]]