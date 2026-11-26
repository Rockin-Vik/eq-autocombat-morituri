-- moriac_wp_presets.lua: extracted verbatim from moriac.lua (behaviour-preserving split).
-- Dependencies come in through D (see the init call in moriac.lua); live bindings
-- that moriac.lua reassigns (ctrl, loadout, ...) are read through D.<name>().
local M = {}

function M.init(runtime, UI, D)
    local WP = D.WP
    local copyWaypointList = D.copyWaypointList
local function sanitizeWpField(s)
    return (tostring(s or ''):gsub('%c', ''))
end

local function base64Encode(data)
    local chars = WP.B64_CHARS
    local out = {}
    local len = #data
    for i = 1, len, 3 do
        local b1, b2, b3 = data:byte(i, i + 2)
        b2 = b2 or 0
        b3 = b3 or 0
        local n = b1 * 65536 + b2 * 256 + b3
        local rem = math.min(3, len - i + 1)
        out[#out + 1] = chars:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
        out[#out + 1] = chars:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        out[#out + 1] = (rem >= 2) and chars:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or '='
        out[#out + 1] = (rem >= 3) and chars:sub(n % 64 + 1, n % 64 + 1) or '='
    end
    return table.concat(out)
end

local function base64Decode(str)
    local lookup = WP.B64_LOOKUP
    str = tostring(str or ''):gsub('[^A-Za-z0-9%+%/%=]', '')
    local out = {}
    local i = 1
    local slen = #str
    while i + 3 <= slen do
        local c1 = lookup[str:sub(i, i)]
        local c2 = lookup[str:sub(i + 1, i + 1)]
        local s3, s4 = str:sub(i + 2, i + 2), str:sub(i + 3, i + 3)
        local c3, c4 = lookup[s3], lookup[s4]
        if not c1 or not c2 then return nil end
        local n = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if s3 ~= '=' and c3 then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
        if s4 ~= '=' and c4 then out[#out + 1] = string.char(n % 256) end
        i = i + 4
    end
    return table.concat(out)
end

local function splitByChar(s, sep)
    local out = {}
    local start = 1
    while true do
        local idx = s:find(sep, start, true)
        if not idx then
            out[#out + 1] = s:sub(start)
            break
        end
        out[#out + 1] = s:sub(start, idx - 1)
        start = idx + 1
    end
    return out
end
-- Exports a named preset as a shareable "TACWP2:..." string. Only named
-- presets can be exported (not the auto-tracked "Current" state) so every
-- export always carries a name for the recipient to import under.
function runtime.wpPresetExport(name)
    name = tostring(name or ''):match('^%s*(.-)%s*$')
    if name == '' then return nil, 'Select a preset to export first.' end
    local zs = runtime.getCurrentZoneShortName()
    local snap
    for _, p in ipairs(runtime.wpPresetsForZone(zs)) do
        if p.name == name then snap = p break end
    end
    if not snap then return nil, 'Preset not found.' end
    if not snap.waypoints or #snap.waypoints == 0 then
        return nil, 'That preset has no waypoints in it.'
    end

    local fields = {
        sanitizeWpField(snap.name),
        sanitizeWpField(zs or ''),
        sanitizeWpField(snap.zoneName or runtime.getZoneDisplayName(zs)),
        string.format('%.2f', snap.waypoint_radius or 0),
        string.format('%.2f', snap.waypoint_scan_radius or 0),
        snap.waypoint_loop and '1' or '0',
        snap.waypoint_anchors and '1' or '0',
    }
    local payload = { table.concat(fields, WP.RS) }
    for _, wp in ipairs(snap.waypoints) do
        runtime.wpNormalize(wp)
        payload[#payload + 1] = table.concat({
            sanitizeWpField(wp.name or ''),
            string.format('%.2f', wp.x or 0),
            string.format('%.2f', wp.y or 0),
            string.format('%.2f', wp.z or 0),
            wp.kind, tostring(wp.combat_radius), tostring(wp.wait_seconds), wp.roam and '1' or '0',
        }, WP.US)
    end
    return WP.PREFIX .. base64Encode(table.concat(payload, WP.RS))
end

-- Parses an exported string WITHOUT writing anything -- callers decide what
-- to do next (e.g. confirm before overwriting a same-named preset). Never
-- executes the string as code; only tonumber()/splitByChar() touch it.
function runtime.wpPresetParseImport(str)
    str = tostring(str or ''):match('^%s*(.-)%s*$')
    if str == '' then return nil, 'Paste an exported waypoint string first.' end

    local versionStr, body = str:match('^TACWP(%d+):(.+)$')
    if not versionStr then return nil, 'Not a recognized MoriAC waypoint string.' end
    local version = tonumber(versionStr)
    if version ~= 1 and version ~= WP.VERSION then
        return nil, string.format(
            'This string uses waypoint format v%s, but this version of MoriAC only supports v%d. Update MoriAC and try again.',
            versionStr, WP.VERSION)
    end

    local payload = base64Decode(body)
    if not payload or payload == '' then
        return nil, 'Could not decode that string -- it looks corrupted or incomplete.'
    end

    local parts = splitByChar(payload, WP.RS)
    if #parts < 6 then return nil, 'That string is missing data -- it looks corrupted or incomplete.' end

    local name, zoneShort, zoneDisplay = parts[1], parts[2], parts[3]
    local radius = tonumber(parts[4])
    local scanRadius = tonumber(parts[5])
    if name == '' then return nil, 'That string has no preset name in it -- it looks corrupted.' end
    if zoneShort == '' or not radius or not scanRadius then
        return nil, 'That string is missing data -- it looks corrupted or incomplete.'
    end

    local function finite(v) return v and v == v and v ~= math.huge and v ~= -math.huge end
    if not finite(radius) or radius <= 0 or not finite(scanRadius) or scanRadius <= 0
        or (parts[6] ~= '0' and parts[6] ~= '1') then return nil, 'Invalid patrol radii or loop flag.' end
    if version == 2 and parts[7] ~= '0' and parts[7] ~= '1' then return nil, 'Invalid anchor patrol flag.' end
    local waypoints = {}
    for i = (version == 2 and 8 or 7), #parts do
        local wpFields = splitByChar(parts[i], WP.US)
        local wx, wy, wz = tonumber(wpFields[2]), tonumber(wpFields[3]), tonumber(wpFields[4])
        if not (finite(wx) and finite(wy) and finite(wz)) then
            return nil, 'That string is missing data -- it looks corrupted or incomplete.'
        end
        local wp = { name = wpFields[1] or '', x = wx, y = wy, z = wz }
        if version == 2 then
            local cr, wait = tonumber(wpFields[6]), tonumber(wpFields[7])
            if #wpFields ~= 8 or (wpFields[5] ~= 'Travel' and wpFields[5] ~= 'Hunt')
                or not finite(cr) or cr <= 0 or not finite(wait) or wait < 0
                or (wpFields[8] ~= '0' and wpFields[8] ~= '1') then
                return nil, 'Invalid waypoint type, combat radius, wait time, or roaming flag.'
            end
            wp.kind, wp.combat_radius, wp.wait_seconds, wp.roam = wpFields[5], cr, wait, wpFields[8] == '1'
        end
        waypoints[#waypoints + 1] = runtime.wpNormalize(wp)
    end
    if #waypoints == 0 then return nil, 'That string has no waypoints in it.' end

    local currentZs = runtime.getCurrentZoneShortName()
    local collision = false
    for _, p in ipairs(runtime.wpPresetsForZone(zoneShort)) do
        if p.name == name then collision = true break end
    end

    return {
        name                 = name,
        zoneShort            = zoneShort,
        zoneDisplay          = zoneDisplay ~= '' and zoneDisplay or zoneShort,
        waypoint_radius      = radius,
        waypoint_scan_radius = scanRadius,
        waypoint_loop        = parts[6] == '1',
        waypoint_anchors     = version == 2 and parts[7] == '1',
        waypoints            = waypoints,
        zoneMismatch         = (currentZs ~= '' and currentZs ~= zoneShort),
        currentZoneDisplay   = runtime.getZoneDisplayName(currentZs),
        collision            = collision,
    }
end

-- Writes a pending import (from wpPresetParseImport) into that zone's preset
-- list, overwriting any same-named preset. Callers are expected to have
-- already confirmed the overwrite with the user when pending.collision is true.
function runtime.wpPresetCommitImport(pending)
    if not pending then return false end
    runtime.upsertZonePreset(pending.zoneShort, {
        name                 = pending.name,
        zoneName             = pending.zoneDisplay,
        waypoints            = copyWaypointList(pending.waypoints),
        waypoint_radius      = pending.waypoint_radius,
        waypoint_scan_radius = pending.waypoint_scan_radius,
        waypoint_loop        = pending.waypoint_loop,
        waypoint_anchors     = pending.waypoint_anchors == true,
    })
    return true
end
end

return M
