-- JSON locale loader with a fallback chain: chosen language -> Config.Locale -> en -> key.
-- Nested JSON is flattened to dotted keys: { "ui": { "title": "x" } } -> "ui.title".

Locale = { dicts = {}, active = nil }

local RES = GetCurrentResourceName()

local function flatten(tbl, prefix, out)
    for k, v in pairs(tbl) do
        local key = prefix and (prefix .. '.' .. k) or k
        if type(v) == 'table' then flatten(v, key, out) else out[key] = v end
    end
    return out
end

function Locale.Load(code)
    if not code then return false end
    if Locale.dicts[code] ~= nil then return Locale.dicts[code] end
    local raw = LoadResourceFile(RES, ('locales/%s.json'):format(code))
    if not raw then
        Locale.dicts[code] = false
        return false
    end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then
        print(('^1[%s] locales/%s.json is not valid JSON^7'):format(RES, code))
        Locale.dicts[code] = false
        return false
    end
    Locale.dicts[code] = flatten(data, nil, {})
    return Locale.dicts[code]
end

function Locale.Exists(code)
    return Locale.Load(code) ~= false
end

function Locale.Set(code)
    if Locale.Exists(code) then
        Locale.active = code
        return true
    end
    return false
end

function Locale.T(key, vars, code)
    local str
    -- `false` instead of nil: ipairs stops at the first nil, which skipped the whole chain
    -- on the server (no active language there).
    for _, c in ipairs({ code or Locale.active or false, Config.Locale or false, 'en' }) do
        local d = c and Locale.Load(c)
        if d and d[key] then str = d[key] break end
    end
    if not str then return key end
    if vars then
        str = (str:gsub('{([%w_]+)}', function(k)
            local v = vars[k]
            return v ~= nil and tostring(v) or ('{' .. k .. '}')
        end))
    end
    return str
end

--- Full dictionary for the NUI, with fallbacks already merged in.
function Locale.Merged(code)
    local out = {}
    for _, c in ipairs({ 'en', Config.Locale, code }) do
        local d = c and Locale.Load(c)
        if d then for k, v in pairs(d) do out[k] = v end end
    end
    return out
end

--- { { code = 'fi', name = 'Suomi' }, ... } for languages that actually loaded.
function Locale.Available()
    local list = {}
    for _, code in ipairs(Config.Languages) do
        local d = Locale.Load(code)
        if d then list[#list + 1] = { code = code, name = d['_meta.name'] or code } end
    end
    return list
end

_L = Locale.T
