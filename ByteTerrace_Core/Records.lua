-- Records: a module's keyed collection of typed records, persisted like rows.
--
--   addon:Module("Ledger", { records = { {
--       name = "people",                               -- "<Module>.<name>", like a row
--       fields = { { name = "kind", kind = "string", default = "grudge", values = { "grudge", "glory" } },
--                  { name = "deaths", kind = "number", default = 0, min = 0, step = 1 } },
--       limit = 300, evict = "seen",                   -- at the limit, a new key evicts the lowest "seen"
--       keep = function(key) return ... end,           -- optional: keys eviction never picks
--       scope = "account",                             -- or "character"
--   } } })
--   local people = module.Records.people
--   people:Set("Bob-Realm", { deaths = people:Field("Bob-Realm", "deaths") + 1 })
--
-- Fields are declared like rows (kind, default, values, min / max / step) and every write goes through the same
-- admission check, so a record never holds a secret, a NaN, or an off-enum value. Keys are plain strings of 1 to
-- MaxKeyLength bytes. A keep function that errors protects nothing: its error reaches the error handler, and loading
-- goes on. A collection is usable once its addon has loaded. Earlier use is an error.
--
-- A collection is also a runtime number row of the same name: its version, which moves on every change. Watchers and
-- rules read that row like any other, so a change publishes with its batch. Eviction and replacement publish together,
-- never exposing a temporary vacancy to a watcher.
--
-- Loading validates the saved table: a record that isn't a table or has a bad key is dropped, a field that no longer
-- validates (or no longer exists) is reset, and a collection over its limit (a lowered limit) is trimmed by eviction.
-- Only fields that differ from their default are stored.
--
-- Public members: Name (the full "<Module>.<name>"), Limit, and Keep (the spec's keep function, or nil).

local FieldPattern = "^%a[%w_]*$"
local MaxKeyLength = 64

local ByteTerrace = ByteTerrace
local ipairs = ipairs
local issecretvalue = issecretvalue
local pairs = pairs
local Refuse = ByteTerrace.Refuse
local SafeCall = ByteTerrace.SafeCall
local sort = table.sort
local tostring = tostring
local type = type

local Records = {}

ByteTerrace.Records = Records
Records.__index = Records

local function Bump(self)
    local state = self.m_addon.State
    local id = self.m_versionId

    if not id then
        id = state:Id(self.Name)
        self.m_versionId = id
    end

    state:Set(id, state.Values[id] + 1)
end

-- Returns whether keep protects key. The keep function is the feature's code, so an error in it reaches the error
-- handler and leaves the key unprotected: a broken keep can't stop the addon loading.
local function Kept(keep, key)
    local ok, kept = SafeCall(keep, key)

    return ((ok and kept and true) or false)
end

local function Loaded(self)
    if not self.m_store then
        error(self.m_addon.Name .. ": records " .. self.Name .. " used before the addon loaded", 3)
    end

    return self.m_store
end

local function ValidKey(key)
    return ((type(key) == "string") and not issecretvalue(key) and (#key >= 1) and (#key <= MaxKeyLength))
end

--- Validates a collection's spec without registering it. AddOn:Module declares its version row only after all of that
--- module's declarations pass.
---@param addon table the owning AddOn
---@param name string "<Module>.<name>"
---@param spec table see the file header
function ByteTerrace.NewRecords(addon, name, spec)
    local problems = {}
    local fields = {}
    local fieldOrder = {}

    for _, field in ipairs(spec.fields or {}) do
        local own = {}

        for key, value in pairs(field) do
            own[key] = value
        end

        local fieldName = tostring(own.name)

        if not fieldName:find(FieldPattern) then
            problems[#problems + 1] = (name .. ": field name '" .. fieldName .. "' must be an identifier")
        elseif fields[fieldName] then
            problems[#problems + 1] = (name .. ": duplicate field " .. fieldName)
        else
            -- Fields have no settings control of their own.
            own.persist, own.label = false, nil
            ByteTerrace.State.Prepare(name .. "." .. fieldName, own, problems)
            fields[fieldName] = own
            fieldOrder[#fieldOrder + 1] = fieldName
        end
    end

    if #fieldOrder == 0 then
        problems[#problems + 1] = (name .. ": a collection needs fields")
    end

    local limit = spec.limit

    if (type(limit) ~= "number") or (limit < 1) or ((limit % 1) ~= 0) then
        problems[#problems + 1] = (name .. ": limit must be a positive whole number")
    end

    if (spec.evict ~= nil) and (not fields[spec.evict] or (fields[spec.evict].kind ~= "number")) then
        problems[#problems + 1] = (name .. ": evict must name a number field")
    end

    if (spec.keep ~= nil) and (type(spec.keep) ~= "function") then
        problems[#problems + 1] = (name .. ": keep must be a function(key)")
    end

    Refuse(addon.Name .. " records", problems)

    local scope = (spec.scope or "account")

    return setmetatable({
        Keep = spec.keep, Limit = limit, m_addon = addon, m_count = 0, m_evict = spec.evict, m_fieldOrder = fieldOrder,
        m_fields = fields, m_scope = scope, m_store = nil, m_versionId = nil, Name = name,
    }, Records)
end

--- Returns how many records there are.
---@return integer
function Records:Count()
    Loaded(self)

    return self.m_count
end

--- Returns the key with the lowest evict field (ties by key, so eviction is deterministic), skipping keys Keep
--- protects. Only a collection with an evict field has one.
---@return string? key nil when every key is kept
function Records:EvictionCandidate()
    local store = Loaded(self)
    local evict = self.m_evict
    local keep = self.Keep
    local default = self.m_fields[evict].default
    local best
    local bestValue

    for key, record in pairs(store) do
        if not (keep and Kept(keep, key)) then
            local value = record[evict]

            if value == nil then
                value = default
            end

            if not best or (value < bestValue) or ((value == bestValue) and (key < best)) then
                best, bestValue = key, value
            end
        end
    end

    return best
end

--- Returns every key in eviction order: unkept keys first, then kept ones, each by the lowest evict field then by key.
--- It sorts once, so trimming a collection far over its limit stays cheap.
---@return string[]
function Records:EvictionOrder()
    local store = Loaded(self)
    local evict = self.m_evict
    local keep = self.Keep
    local default = ((evict and self.m_fields[evict].default) or 0)
    local keys = {}
    local kept = {}
    local value = {}

    for key, record in pairs(store) do
        keys[#keys + 1] = key
        kept[key] = ((keep ~= nil) and Kept(keep, key))
        local field = (evict and record[evict])

        value[key] = (((field == nil) and default) or field)
    end

    sort(keys, function(a, b)
        if kept[a] ~= kept[b] then
            return not kept[a]
        end

        if value[a] ~= value[b] then
            return (value[a] < value[b])
        end

        return (a < b)
    end)

    return keys
end

--- Returns a field's value for key, or the field's default when the record (or field) is absent. An undeclared field is
--- an error.
---@param key string
---@param field string
function Records:Field(key, field)
    local spec = self.m_fields[field]

    if not spec then
        error(self.m_addon.Name .. ": records " .. self.Name .. " has no field " .. tostring(field), 2)
    end

    local record = Loaded(self)[key]
    local value = (record and record[field])

    if value == nil then
        return spec.default
    end

    return value
end

--- Returns a copy of the record with every field filled in, or nil.
---@param key string
---@return table?
function Records:Get(key)
    local record = Loaded(self)[key]

    if not record then
        return nil
    end

    local copy = {}

    for _, field in ipairs(self.m_fieldOrder) do
        local value = record[field]

        if value == nil then
            value = self.m_fields[field].default
        end

        copy[field] = value
    end

    return copy
end

--- Returns whether a record exists for key.
---@return boolean
function Records:Has(key)
    return (Loaded(self)[key] ~= nil)
end

--- Returns every key, sorted, in a fresh array.
---@return string[]
function Records:Keys()
    local keys = {}

    for key in pairs(Loaded(self)) do
        keys[#keys + 1] = key
    end

    sort(keys)

    return keys
end

--- Binds the collection to its SavedVariables table (after State:Compile) and validates it. A collection over its limit
--- (a lowered limit) evicts until it fits, kept keys too if it must.
---@param stores table { account = table, character = table? }
---@return integer dropped records dropped
---@return integer reset fields reset
function Records:Load(stores)
    local root = stores[self.m_scope]
    local store = root[self.Name]

    if type(store) ~= "table" then
        store = {}
        root[self.Name] = store
    end

    local fields = self.m_fields
    local admits = ByteTerrace.State.Admits
    local dropped = 0
    local reset = 0
    local count = 0

    for key, record in pairs(store) do
        if not ValidKey(key) or (type(record) ~= "table") then
            store[key] = nil
            dropped = (dropped + 1)
        else
            for field, value in pairs(record) do
                local spec = fields[field]

                if not spec or not admits(spec, value) then
                    record[field] = nil
                    reset = (reset + 1)
                elseif value == spec.default then
                    -- A value equal to the default isn't stored: a record keeps only what differs from it.
                    record[field] = nil
                end
            end

            count = (count + 1)
        end
    end

    self.m_store, self.m_count = store, count

    -- Nothing watches yet, so the version doesn't move.
    if self.m_count > self.Limit then
        local victims = self:EvictionOrder()

        for i = 1, self.m_count - self.Limit do
            store[victims[i]] = nil
        end

        dropped = ((dropped + self.m_count) - self.Limit)
        self.m_count = self.Limit
    end

    return dropped, reset
end

--- Removes the record for key.
---@return boolean removed false when there was none
function Records:Remove(key)
    local store = Loaded(self)

    if (key == nil) or (store[key] == nil) then
        return false
    end

    store[key] = nil
    self.m_count = (self.m_count - 1)
    Bump(self)

    return true
end

--- Creates or updates the record for key, merging the given fields. Every value is validated before anything is
--- written, so a bad write changes nothing. At the limit, a new key evicts the lowest record by the evict field. With
--- nothing to evict, it's an error.
---@param key string 1 to 64 characters
---@param values table field = value
function Records:Set(key, values)
    local store = Loaded(self)

    if not ValidKey(key) then
        local message = "%s: records %s key must be a plain string of 1 to %d characters"

        error(message:format(self.m_addon.Name, self.Name, MaxKeyLength), 2)
    end

    local fields = self.m_fields
    local admits = ByteTerrace.State.Admits

    for field, value in pairs(values) do
        local spec = fields[field]

        if not spec then
            error(self.m_addon.Name .. ": records " .. self.Name .. " has no field " .. tostring(field), 2)
        end

        local ok, why = admits(spec, value)

        if not ok then
            error(self.m_addon.Name .. ": records " .. self.Name .. "." .. field .. " " .. why, 2)
        end
    end

    local record = store[key]
    local changed = false

    if not record then
        if self.m_count >= self.Limit then
            local victim = (self.m_evict and self:EvictionCandidate())

            if not victim then
                error(self.m_addon.Name .. ": records " .. self.Name .. " is full (" .. self.Limit .. ")", 2)
            end

            -- Publish only after the replacement is complete. Publishing the removal here lets a watcher fill the
            -- vacancy before this write resumes and exceed the limit.
            store[victim] = nil
            self.m_count = (self.m_count - 1)
        end

        record = {}
        store[key] = record
        self.m_count = (self.m_count + 1)
        changed = true
    end

    for field, value in pairs(values) do
        local stored = value

        if value == fields[field].default then
            stored = nil
        end

        if record[field] ~= stored then
            record[field] = stored
            changed = true
        end
    end

    if changed then
        Bump(self)
    end
end
