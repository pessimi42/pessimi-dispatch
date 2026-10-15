-- Persistent call storage. Calls live in memory (Calls.list); this saves the ones chosen in
-- Config.Storage (by default those a dispatcher made) so they survive a restart, and keeps
-- them as history.
--
-- Backends: 'none' (memory only), 'kvp' (the resource's own key-value store, no setup),
-- 'oxmysql' (a database table, created automatically), 'auto' (oxmysql when it is running,
-- otherwise kvp). Another backend is one table in Storage.backends with:
--   init()            -> true when ready
--   save(record, noWait)  insert or update one call (record.id is unique); noWait while
--                     the resource is stopping
--   loadRecent(n)     -> records: every open call plus the n newest closed ones
--   maxId()           -> highest id ever saved (call numbers continue after a restart)
--   prune(before)     delete closed calls closed before this os.time()

Storage = { backends = {}, active = nil, name = 'none' }

local cfg = Config.Storage or {}
local dirty = {}          -- [id] = record: saved on the next flush

---------------------------------------------------------------------------
-- What is saved
---------------------------------------------------------------------------
--- Should this call be saved? Chosen by origin; AI calls only with saveAi.
function Storage.Wants(call)
    if not Storage.active or not call then return false end
    if call._ai and not cfg.saveAi then return false end
    local origins = cfg.origins or { dispatcher = true }
    return origins.all == true or origins[call.origin] == true
end

local FIELDS = {
    'id', 'service', 'type', 'priority', 'status', 'message', 'information', 'code', 'coords',
    'street', 'caller', 'origin', 'createdBy', 'createdAt', 'updatedAt', 'closedAt', 'notes', 'meta',
}

--- The saved form of a call: plain data, no server-only fields or live units.
function Storage.Record(call)
    local r = {}
    for _, k in ipairs(FIELDS) do r[k] = call[k] end
    if call._ai then r.ai = true end
    return r
end

---------------------------------------------------------------------------
-- KVP backend: one JSON value per call, key "call:<id>"
---------------------------------------------------------------------------
local kvp = {}
Storage.backends.kvp = kvp

function kvp.init() return true end

function kvp.save(r) SetResourceKvp('call:' .. r.id, json.encode(r)) end

local function kvpEach(fn)
    local handle = StartFindKvp('call:')
    if handle == -1 then return end
    while true do
        local key = FindKvp(handle)
        if not key then break end
        local ok, r = pcall(json.decode, GetResourceKvpString(key) or '')
        if ok and type(r) == 'table' and tonumber(r.id) then fn(key, r) end
    end
    EndFindKvp(handle)
end

function kvp.loadRecent(n)
    local open, closed = {}, {}
    kvpEach(function(_, r)
        if r.status == 'closed' then closed[#closed + 1] = r else open[#open + 1] = r end
    end)
    table.sort(closed, function(a, b) return (a.closedAt or 0) > (b.closedAt or 0) end)
    for i = 1, math.min(n, #closed) do open[#open + 1] = closed[i] end
    return open
end

function kvp.maxId()
    local m = GetResourceKvpInt('calls:maxId') or 0
    kvpEach(function(_, r) if r.id > m then m = r.id end end)
    return m
end

function kvp.prune(before)
    local old = {}
    kvpEach(function(key, r)
        if r.status == 'closed' and (r.closedAt or 0) < before then old[#old + 1] = key end
    end)
    for _, key in ipairs(old) do DeleteResourceKvp(key) end
    return #old
end

---------------------------------------------------------------------------
-- oxmysql backend: table Config.Storage.table, searchable columns + the call as JSON
---------------------------------------------------------------------------
local sql = {}
Storage.backends.oxmysql = sql

local function db(method, query, params, noWait)
    if noWait then return exports.oxmysql[method](exports.oxmysql, query, params or {}) end
    local p = promise.new()
    exports.oxmysql[method](exports.oxmysql, query, params or {}, function(result) p:resolve(result) end)
    return Citizen.Await(p)
end

local function tbl() return '`' .. (cfg.table or 'pessimi42_dispatch_calls'):gsub('[^%w_]', '') .. '`' end

function sql.init()
    if GetResourceState('oxmysql') ~= 'started' then return false end
    db('query', ([[CREATE TABLE IF NOT EXISTS %s (
        `id` INT UNSIGNED NOT NULL PRIMARY KEY,
        `service` VARCHAR(32) NULL,
        `type` VARCHAR(64) NULL,
        `priority` CHAR(1) NULL,
        `status` VARCHAR(16) NOT NULL,
        `origin` VARCHAR(32) NULL,
        `created_by` VARCHAR(60) NULL,
        `created_at` INT UNSIGNED NOT NULL,
        `updated_at` INT UNSIGNED NOT NULL,
        `closed_at` INT UNSIGNED NULL,
        `data` LONGTEXT NOT NULL,
        KEY `status` (`status`),
        KEY `closed_at` (`closed_at`)
    )]]):format(tbl()))
    return true
end

function sql.save(r, noWait)
    db('query', ([[INSERT INTO %s (id, service, type, priority, status, origin, created_by,
        created_at, updated_at, closed_at, data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE service = VALUES(service), type = VALUES(type),
        priority = VALUES(priority), status = VALUES(status), updated_at = VALUES(updated_at),
        closed_at = VALUES(closed_at), data = VALUES(data)]]):format(tbl()),
        { r.id, r.service, r.type, r.priority, r.status, r.origin, r.createdBy,
          r.createdAt, r.updatedAt, r.closedAt, json.encode(r) }, noWait)
end

local function decodeRows(rows)
    local out = {}
    for _, row in ipairs(rows or {}) do
        local ok, r = pcall(json.decode, row.data or '')
        if ok and type(r) == 'table' then out[#out + 1] = r end
    end
    return out
end

function sql.loadRecent(n)
    local open = decodeRows(db('query', ('SELECT data FROM %s WHERE status <> ?'):format(tbl()), { 'closed' }))
    local closed = decodeRows(db('query',
        ('SELECT data FROM %s WHERE status = ? ORDER BY closed_at DESC LIMIT ?'):format(tbl()), { 'closed', n }))
    for _, r in ipairs(closed) do open[#open + 1] = r end
    return open
end

function sql.maxId()
    return tonumber(db('scalar', ('SELECT MAX(id) FROM %s'):format(tbl()))) or 0
end

function sql.prune(before)
    local res = db('update', ('DELETE FROM %s WHERE status = ? AND closed_at < ?'):format(tbl()), { 'closed', before })
    return tonumber(res) or 0
end

---------------------------------------------------------------------------
-- Saving
---------------------------------------------------------------------------
--- Called on every change of a call (Calls.changed). Saved in the next flush, so a call
--- edited many times in a few seconds is written once.
function Storage.Changed(call)
    if Storage.Wants(call) then dirty[call.id] = Storage.Record(call) end
end

function Storage.Flush(stopping)
    if not Storage.active then return end
    local batch = dirty
    dirty = {}
    for id, r in pairs(batch) do
        local ok, err = pcall(Storage.active.save, r, stopping)
        if not ok then
            print(('^1[%s] saving call #%d failed: %s^7'):format(Utils.Resource, id, tostring(err)))
            if not dirty[id] then dirty[id] = r end      -- try again on the next flush
        end
    end
    if Storage.name == 'kvp' and Calls.nextId > 1 then SetResourceKvpInt('calls:maxId', Calls.nextId - 1) end
end

---------------------------------------------------------------------------
-- Start: pick the backend, bring saved calls back, continue numbering
---------------------------------------------------------------------------
local function choose()
    local want = cfg.backend or 'none'
    if want == 'none' then return nil, 'none' end
    -- oxmysql may still be starting when this resource starts
    local t = GetGameTimer() + 15000
    while GetResourceState('oxmysql') == 'starting' and GetGameTimer() < t do Wait(250) end
    if want == 'auto' then want = GetResourceState('oxmysql') == 'started' and 'oxmysql' or 'kvp' end
    local b = Storage.backends[want]
    if not b then
        print(('^1[%s] unknown storage backend "%s", calls are kept in memory only^7'):format(Utils.Resource, want))
        return nil, 'none'
    end
    local ok, ready = pcall(b.init)
    if not ok or not ready then
        print(('^1[%s] storage "%s" is not available (%s), calls are kept in memory only^7')
            :format(Utils.Resource, want, ok and 'not running' or tostring(ready)))
        return nil, 'none'
    end
    return b, want
end

--- A saved call back in memory. Units are not restored (players may have left); an
--- active call goes back to the queue.
local function restore(r)
    local call = r
    call.id = tonumber(r.id)
    call.notes = type(r.notes) == 'table' and r.notes or {}
    call._units = {}
    call._ai = r.ai == true
    call.ai = nil
    if call.status == 'active' then call.status = 'pending' end
    call._broadcast = call.status == 'broadcast' or nil
    Calls.list[call.id] = call
end

function Storage.Start()
    Storage.active, Storage.name = choose()
    if not Storage.active then return end

    local maxId = Storage.active.maxId() or 0
    if maxId >= Calls.nextId then Calls.nextId = maxId + 1 end

    if (cfg.keepDays or 0) > 0 then
        local removed = Storage.active.prune(os.time() - cfg.keepDays * 86400)
        if (removed or 0) > 0 then Utils.Debug(('removed %d saved calls older than %d days'):format(removed, cfg.keepDays)) end
    end

    local n = 0
    if cfg.restore ~= false then
        for _, r in ipairs(Storage.active.loadRecent(Config.Calls.keepClosed or 25)) do
            if tonumber(r.id) and not Calls.list[tonumber(r.id)] then
                restore(r)
                n = n + 1
            end
        end
    end
    print(('[%s] calls are saved with %s (%d restored, numbering continues from #%d)')
        :format(Utils.Resource, Storage.name, n, Calls.nextId))
end

CreateThread(function()
    Storage.Start()
    while true do
        Wait((cfg.flushSeconds or 5) * 1000)
        Storage.Flush()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Storage.Flush(true) end
end)
