-- moriac/plugin_manager.lua: extracted verbatim from moriac.lua (behaviour-preserving split).
-- Dependencies come in through D (see the init call in moriac.lua); live bindings
-- that moriac.lua reassigns (ctrl, loadout, ...) are read through D.<name>().
local M = {}

function M.init(runtime, UI, D)
    local ARC = D.ARC
    local CLASS_SLOTS = D.CLASS_SLOTS
    local ERR = D.ERR
    local GOLD = D.GOLD
    local GOOD = D.GOOD
    local ImGui = D.ImGui
    local MUTED = D.MUTED
    local VERSION = D.VERSION
    local WARN = D.WARN
    local castTracker = D.castTracker
    local classColor = D.classColor
    local cleanSpellName = D.cleanSpellName
    local fmtSec = D.fmtSec
    local getAbilityBaseCooldown = D.getAbilityBaseCooldown
    local getDiscCooldownAndDuration = D.getDiscCooldownAndDuration
    local getMultiPetList = D.getMultiPetList
    local getNumGems = D.getNumGems
    local getPetSpawnInfo = D.getPetSpawnInfo
    local idxOf = D.idxOf
    local isSpawnAlive = D.isSpawnAlive
    local mq = D.mq
    local normalizeSpellName = D.normalizeSpellName
    local parseCombatAbilityTimer = D.parseCombatAbilityTimer
    local parseDurationSec = D.parseDurationSec
    local parseSpellRecastTime = D.parseSpellRecastTime
    local petState = D.petState
    local pursuit = D.pursuit
    local scriptDir = D.scriptDir
    local stuckState = D.stuckState
    local tlog = D.tlog
function runtime.initPluginManager()
    if runtime.pluginManager then return end

    local pm = {
        plugins = {},
        pluginOrder = {},
        dirPath = nil,
        lastScanAt = 0,
    }
    runtime.pluginManager = pm

    function pm.getPluginDir()
        if pm.dirPath then return pm.dirPath end
        local rawCandidates = {}

        if mq and mq.luaDir then
            local l = tostring(mq.luaDir):gsub('[/\\]+$', '')
            table.insert(rawCandidates, l .. '/tac')
            table.insert(rawCandidates, l .. '/TAC')
            table.insert(rawCandidates, l .. '/../TAC/lua/tac')
            table.insert(rawCandidates, l .. '/../lua/tac')
        end

        if scriptDir then
            local s = tostring(scriptDir):gsub('[/\\]+$', '')
            table.insert(rawCandidates, s .. '/tac')
            table.insert(rawCandidates, s .. '/TAC')
            table.insert(rawCandidates, s .. '/../lua/tac')
            table.insert(rawCandidates, s .. '/../TAC/lua/tac')
        end

        table.insert(rawCandidates, 'lua/tac')
        table.insert(rawCandidates, 'lua/TAC')
        table.insert(rawCandidates, 'TAC/lua/tac')
        table.insert(rawCandidates, 'autocombat/lua/tac') -- dev checkout layout (this repo)
        table.insert(rawCandidates, './tac')
        table.insert(rawCandidates, './TAC')
        table.insert(rawCandidates, 'tac')
        table.insert(rawCandidates, 'TAC')

        local candidates = {}
        local seenCand = {}
        for _, c in ipairs(rawCandidates) do
            local norm = c:gsub('\\', '/'):lower()
            if not seenCand[norm] then
                seenCand[norm] = true
                table.insert(candidates, c)
            end
        end

        local okLfs, lfs = pcall(require, 'lfs')
        if okLfs and lfs and lfs.attributes then
            for _, d in ipairs(candidates) do
                local mode = nil
                pcall(function() mode = lfs.attributes(d, 'mode') end)
                if mode == 'directory' then
                    pm.dirPath = d
                    return d
                end
            end
        end

        local probeFiles = { 'hud_unitframes.lua', 'auto_accept.lua', 'floating_damage.lua' }
        for _, d in ipairs(candidates) do
            for _, pf in ipairs(probeFiles) do
                local f = io.open(d .. '/' .. pf, 'r')
                if f then
                    f:close()
                    pm.dirPath = d
                    return d
                end
            end
        end

        pm.dirPath = (scriptDir and (scriptDir .. 'tac')) or 'lua/tac'
        return pm.dirPath
    end

    -- Spell Info for a spell id or name: the Game Database plugin's card when
    -- it is loaded and replacing the game's window, else the client's own
    -- Spell Display window. Every "Inspect" in Triune goes through this.
    -- Returns true when either opened.
    function pm.inspectSpell(spell)
        if spell == nil or spell == '' then return false end
        local p = pm.plugins and pm.plugins.gamedb
        if p and p.enabled and p.instance and p.instance.inspectSpell then
            local ok, res = pcall(p.instance.inspectSpell, spell)
            if ok and res == true then return true end
        end
        local ok, shown = pcall(function()
            local sp = mq.TLO.Spell(spell)
            if sp and sp() and sp.Inspect then
                sp.Inspect()
                return true
            end
            return false
        end)
        return ok and shown == true
    end

    -- One shared core API table for every plugin. `ctrl` / `loadout` and the
    -- other mutable core tables are resolved live through __index because
    -- runtime.onCharacterChanged() replaces them wholesale; a snapshot taken at
    -- init would leave plugins reading (and writing) a dead config table.
    function pm.getCoreApi()
        if pm.coreApi then return pm.coreApi end
        local live = {
            ctrl       = function() return D.ctrl() end,
            loadout    = function() return D.loadout() end,
            petState   = function() return petState end,
            pursuit    = function() return pursuit end,
            stuckState = function() return stuckState end,
            myClasses  = function() return D.myClasses() end,
            castTracker = function() return castTracker end,
        }
        local api = {
            VERSION               = VERSION,
            mq                    = mq,
            ImGui                 = ImGui,
            runtime               = runtime,
            -- core.log.debug('myplugin', 'fmt %d', n) etc. Debug lines only
            -- go out while Debug Mode is on; all levels land in the log file
            -- when Log To File is on. See tac/triune_log.lua.
            log                   = tlog,
            DATA                  = D.DATA(),
            saveLoadout           = runtime.saveLoadout,
            -- crash-safe replace: path.bak backup, write path.tmp, rename over path
            atomicWrite           = function(path, text) return runtime.atomicWrite(path, text) end,
            colors               = { GOLD = GOLD, ARC = ARC, MUTED = MUTED, GOOD = GOOD, WARN = WARN, ERR = ERR },
            pushTheme             = UI.pushTheme,
            popTheme              = UI.popTheme,
            accent                = UI.accent,
            setTooltip            = UI.setTooltip,
            -- Main-window layout helpers, so plugin settings read the same:
            -- formLabel('Opacity') then the widget with a '##id' label;
            -- section(key, label, open) is a remembered collapsing header.
            formLabel             = UI.formLabel,
            section               = function(key, label, defaultOpen) return UI.pageSection('plg_' .. tostring(key), label, defaultOpen) end,
            cardTitle             = UI.cardTitle,
            preBeginWindow        = UI.preBeginWindow,
            postBeginWindow       = UI.postBeginWindow,
            preEndWindow          = UI.preEndWindow,
            postEndWindow         = UI.postEndWindow,
            windowFlags           = UI.windowFlags,
            windowBgAlpha         = UI.windowBgAlpha,
            drawWindowMenuItems   = UI.drawWindowMenuItems,
            windowOpts            = UI.windowOpts,
            setWindowOpt          = UI.setWindowOpt,
            px                    = UI.px,
            currentWindowScale    = function() return runtime.curWindowScale or 1.0 end,
            windowScale           = UI.windowScale,
            pushWindowScale       = UI.pushWindowScale,
            applyWindowScale      = UI.applyWindowScale,
            drawWindowScaleControl = UI.drawWindowScaleControl,
            drawStatusProgressBar = UI.drawStatusProgressBar,
            drawSpellIcon         = UI.drawSpellIcon,
            getConColorRgb        = UI.getConColorRgb,
            resolveTargetOfTarget = UI.resolveTargetOfTarget,
            getMultiPetList       = runtime.getMultiPetList or getMultiPetList,
            getPetSpawnInfo       = runtime.getPetSpawnInfo or getPetSpawnInfo,
            isSpawnAlive          = runtime.isSpawnAlive or isSpawnAlive,
            addIgnore             = runtime.addIgnore,
            addZoneIgnore         = runtime.addZoneIgnore,
            -- Extended Target window per-spawn overrides (see runtime.setXtForce)
            setXtForce            = runtime.setXtForce,
            setXtIgnore           = runtime.setXtIgnore,
            isXtIgnoredId         = runtime.isXtIgnoredId,
            getXtForceId          = function() return runtime.xtForceId or 0 end,
            parseDurationSec      = parseDurationSec,
            parseSpellRecastTime  = parseSpellRecastTime,
            parseCombatAbilityTimer = parseCombatAbilityTimer,
            getAbilityBaseCooldown = getAbilityBaseCooldown,
            getDiscCooldownAndDuration = getDiscCooldownAndDuration,
            getNumGems            = getNumGems,
            classColor            = classColor,
            migrateConfigFile     = runtime.migrateConfigFile,
            CLASS_SLOTS           = CLASS_SLOTS,
            cleanSpellName        = cleanSpellName,
            normalizeSpellName    = normalizeSpellName,
            requestClassRedetect  = function() D.set_reDetectRequested(true) end,
            fmtSec                = fmtSec,
            idxOf                 = idxOf,
            col32                 = UI.col32,
            toVec                 = UI.toVec,
            toggleTool            = UI.toggleTool,
            getSpellIconAnimation = UI.getSpellIconAnimation,
            getGemCooldownSec     = UI.getGemCooldownSec,
            drawSpellbookIcon     = UI.drawSpellbookIcon,
            -- Spell Info for an id or name: the Game Database card, else the
            -- game's Spell Display window. Use this instead of Spell().Inspect().
            inspectSpell          = function(spell) return pm.inspectSpell(spell) end,
            delay                 = function(ms, cond) return pm.delay(ms, cond) end,
            -- short main-loop passes for the next `sec` seconds (call again to extend)
            fastLoop              = function(sec) runtime.fastLoopUntil = os.clock() + math.min(5, tonumber(sec) or 1) end,
            -- Queue work to run on the main script coroutine next tick. Any
            -- plugin button that fires an ability / casts / targets (anything
            -- that may mq.delay) must go through this instead of calling the
            -- runtime function directly from onDrawUI.
            defer                 = function(label, fn) return pm.defer(label, fn) end,
        }
        setmetatable(api, {
            __index = function(_, k)
                local getter = live[k]
                if getter then return getter() end
                return nil
            end,
        })
        pm.coreApi = api
        return api
    end

    -- Cooperative stand-in for mq.delay inside a plugin fiber. Yields the fiber
    -- back to the main loop every tick until `ms` has elapsed or `cond()` is
    -- true, so a sequential plugin workflow (buff casting, bag moves) can wait
    -- without ever stalling the combat loop. Outside a fiber it degrades to
    -- mq.delay on the main coroutine. Returns true when the condition fired.
    pm.inFiber = false
    pm.inDraw = false
    function pm.delay(ms, cond)
        ms = tonumber(ms) or 0
        if pm.inDraw then
            -- Called from an ImGui render callback (onDrawUI / onDrawSettings /
            -- a button label evaluator). mq.delay here is a hard crash
            -- ("Cannot delay from non-yieldable thread") that also corrupts the
            -- ImGui Begin/End stack, so refuse and let the caller carry on.
            -- Plugins that need to wait from a button must core.defer() the work.
            if cond then
                local ok, res = pcall(cond)
                return ok and res == true
            end
            return false
        end
        if not pm.inFiber then
            if mq and mq.delay then mq.delay(ms, cond) end
            if cond then
                local ok, res = pcall(cond)
                return ok and res == true
            end
            return false
        end
        local deadline = os.clock() + ms / 1000
        while true do
            if cond then
                local ok, res = pcall(cond)
                if ok and res then return true end
            end
            if os.clock() >= deadline then return false end
            coroutine.yield()
        end
    end

    -- Every plugin fiber is the same loop: run onTick, yield, repeat while enabled.
    -- Flags a plugin as errored. Chat gets the one-line message; the log file
    -- gets the full traceback (xpcall/debug.traceback output) so a bug report
    -- has the stack without spamming chat with it.
    -- `phase` is the hook name ('onDrawUI', 'onTick', 'fiber', ...), kept as
    -- the errorMsg prefix the Plugins tab shows.
    function pm.reportError(p, phase, err)
        local full = tostring(err)
        local first = full:match('^([^\n]*)') or full
        p.status = 'Error'
        p.errorMsg = phase .. ': ' .. first
        print(string.format('\ar[MoriAC Plugin Error]\ax %s %s failed: %s', p.name, phase, first))
        if full ~= first then tlog.error('plugin', '%s %s traceback:\n%s', p.name, phase, full) end
    end

    function pm.createFiber(p)
        return coroutine.create(function()
            while p.enabled do
                if p.instance.onTick then
                    local ok, err = xpcall(p.instance.onTick, debug.traceback)
                    if not ok then
                        pm.reportError(p, 'fiber', err)
                        break
                    end
                end
                coroutine.yield()
            end
        end)
    end

    -- Files in the plugin folder that could not be loaded, keyed by filename:
    -- { msg = ..., fullPath = ..., at = os.clock() }. Shown on the Plugins page
    -- so a bad drop-in is visible there, not only as one chat line.
    pm.loadErrors = {}

    local PLUGIN_HOOKS = {
        'onInit', 'onDestroy', 'onTick', 'onDrawUI', 'onDrawSettings', 'onCombatTick', 'onZoned',
        'onLoadoutSaved', 'onSaveSettings', 'onLoadSettings', 'wantsCombatHold', 'onBetweenPulls', 'onCommand',
    }

    -- Lower-case filenames in lua/tac/ that are core library modules, not
    -- plugins (loaded via require() at the top of this file). pm.discover()
    -- skips them so the scanner never runs their chunk a second time.
    local PLUGIN_DIR_LIBRARIES = {
        ['triune_log.lua'] = true,
    }

    -- Executing a dropped-in file runs its main chunk on the core's main
    -- coroutine. A standalone MQ script would start its own mq.delay loop
    -- there (hanging Triune), or register ImGui callbacks / binds / events
    -- that nothing ever cleans up. While a plugin file's chunk runs, those
    -- entry points raise instead, so the file fails to load with a clear
    -- message and no side effects. Real plugins do all of this in onInit.
    local function runPluginChunk(fn, filename)
        local guards = {
            { tbl = mq, key = 'delay',    why = 'mq.delay (a plugin must not block at load; use onTick / core.delay)' },
            { tbl = mq, key = 'doevents', why = 'mq.doevents (the core pumps events)' },
            { tbl = mq, key = 'bind',     why = 'mq.bind at load (register binds in onInit, release them in onDestroy)' },
            { tbl = mq, key = 'event',    why = 'mq.event at load (register events in onInit, release them in onDestroy)' },
            { tbl = mq, key = 'exit',     why = 'mq.exit (a plugin runs inside MoriAC and cannot exit the script)' },
            { tbl = mq and mq.imgui, key = 'init', why = 'mq.imgui.init (draw from onDrawUI instead)' },
        }
        local saved = {}
        for i, g in ipairs(guards) do
            if type(g.tbl) == 'table' then
                saved[i] = g.tbl[g.key]
                g.tbl[g.key] = function()
                    error(string.format('%s is a standalone script, not a MoriAC plugin: it called %s while loading', filename, g.why), 2)
                end
            end
        end
        local ok, res = pcall(fn)
        for i, g in ipairs(guards) do
            if type(g.tbl) == 'table' then g.tbl[g.key] = saved[i] end
        end
        return ok, res
    end

    local function looksLikePlugin(inst)
        if type(inst) ~= 'table' then return false end
        if type(inst.id) == 'string' and inst.id ~= '' then return true end
        for _, h in ipairs(PLUGIN_HOOKS) do
            if type(inst[h]) == 'function' then return true end
        end
        return false
    end

    local function loadFailed(filename, fullPath, msg)
        print(string.format('\ar[MoriAC Plugin Error]\ax %s: %s', filename, tostring(msg)))
        pm.loadErrors[filename] = { msg = tostring(msg), fullPath = fullPath, at = os.clock() }
        pm.scripts[filename] = nil
        pm.listVer = (pm.listVer or 0) + 1 -- invalidates the Plugins page sorted lists
        return false, tostring(msg)
    end

    -- Files that load fine but are not plugins (standalone MQ scripts, data
    -- files, anything without the plugin contract). They get a basic entry on
    -- the Plugins page with Run / Stop buttons that launch them through
    -- `/lua run`, completely independent of Triune's plugin lifecycle.
    pm.scripts = {}

    -- The name `/lua run` needs for a file inside the plugin folder: relative
    -- to the MQ lua directory when the folder lives under it (e.g. `tac/foo`),
    -- otherwise the folder's last path segment plus the file (`tac/foo`).
    function pm.scriptRunName(fullPath)
        local path = tostring(fullPath or ''):gsub('\\', '/'):gsub('%.lua$', '')
        local luaDir = mq and mq.luaDir and tostring(mq.luaDir):gsub('\\', '/'):gsub('/+$', '') or nil
        if luaDir and luaDir ~= '' and path:sub(1, #luaDir + 1):lower() == (luaDir .. '/'):lower() then
            return path:sub(#luaDir + 2)
        end
        local folder, file = path:match('([^/]+)/([^/]+)$')
        if folder and file then return folder .. '/' .. file end
        return path:match('([^/]+)$') or path
    end

    local function registerScript(filename, fullPath, reason)
        local runName = pm.scriptRunName(fullPath)
        pm.scripts[filename] = {
            name = (tostring(filename):gsub('%.lua$', '')),
            file = filename,
            fullPath = fullPath,
            runName = runName,
            reason = tostring(reason),
            at = os.clock(),
        }
        pm.loadErrors[filename] = nil
        pm.listVer = (pm.listVer or 0) + 1 -- invalidates the Plugins page sorted lists
        print(string.format('\ay[MoriAC]\ax %s is not a MoriAC plugin (%s). Listed under Setup -> Plugins -> Standalone Scripts; run it with /lua run %s.',
            filename, tostring(reason), runName))
        return false, tostring(reason)
    end

    -- Lua.Script() is a TLO call per script per frame from the header bar
    -- and the Plugins page; poll it once per main-loop pass instead.
    pm.scriptRunningCache = {}
    function pm.isScriptRunning(entry, fresh)
        if not entry then return false end
        local c = pm.scriptRunningCache[entry.runName]
        if c and not fresh and runtime.tickSerial and c.tick == runtime.tickSerial then return c.v end
        local running = false
        pcall(function()
            local s = mq.TLO.Lua.Script(entry.runName)
            running = (s() and s.Status() == 'RUNNING') == true
        end)
        pm.scriptRunningCache[entry.runName] = { tick = runtime.tickSerial, v = running }
        return running
    end

    -- Run or stop a standalone script (`/lua run` / `/lua stop`). Returns
    -- 'started' or 'stopped'.
    function pm.toggleScript(entry)
        if not entry then return nil end
        pm.scriptRunningCache[entry.runName] = nil -- re-poll after the toggle
        if pm.isScriptRunning(entry, true) then
            mq.cmd('/lua stop ' .. entry.runName)
            return 'stopped'
        end
        mq.cmd('/lua run ' .. entry.runName)
        return 'started'
    end

    -- Standalone scripts can get a Run / Stop button on the main window
    -- header too (Settings -> Plugins -> Standalone Scripts). Per-file
    -- settings live in ctrl.scripts[filename] = { headerButton, label } and
    -- save with the loadout like the plugin header buttons.
    local function scriptCfg(entry, create)
        if not entry or not entry.file then return nil end
        if type(D.ctrl().scripts) ~= 'table' then D.ctrl().scripts = {} end
        local c = D.ctrl().scripts[entry.file]
        if not c and create then
            c = {}
            D.ctrl().scripts[entry.file] = c
        end
        return c
    end

    function pm.scriptHeaderButtonEnabled(entry)
        local c = scriptCfg(entry)
        return c ~= nil and c.headerButton == true
    end

    function pm.setScriptHeaderButton(entry, val)
        if pm.invalidateHeaderButtons then pm.invalidateHeaderButtons() end
        local c = scriptCfg(entry, true)
        if not c then return end
        c.headerButton = (val == true)
        runtime.saveLoadout(true)
    end

    -- The user's raw button name ('' when unset) and the text the header
    -- actually shows (falls back to the file name).
    function pm.scriptButtonName(entry)
        local c = scriptCfg(entry)
        return c and type(c.label) == 'string' and c.label or ''
    end

    function pm.scriptButtonLabel(entry)
        local label = pm.scriptButtonName(entry)
        if label:match('%S') then return label end
        return tostring(entry and entry.name or '?')
    end

    -- `save` false updates the name without writing the loadout (used while
    -- the user is still typing).
    function pm.setScriptButtonName(entry, label, save)
        local c = scriptCfg(entry, true)
        if not c then return end
        label = tostring(label or '')
        c.label = (label ~= '') and label or nil
        if save ~= false then runtime.saveLoadout(true) end
    end

    -- Standalone scripts with a header button, sorted by name.
    function pm.headerScripts()
        local out = {}
        for fname, entry in pairs(pm.scripts or {}) do
            entry.file = entry.file or fname
            if pm.scriptHeaderButtonEnabled(entry) then out[#out + 1] = entry end
        end
        table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
        return out
    end

    -- Optional plugin integrations. A plugin that talks to another plugin
    -- declares it with
    --   uses = { 'boxnet' }                                  -- or
    --   uses = { boxnet = 'hotbar sync across boxes' }        -- id -> what it is for
    -- These are soft links: the plugin must keep working (feature off) when
    -- the other plugin is missing or disabled. The Plugins page shows them
    -- in the Uses column, amber when the used plugin is not active, and the
    -- reverse list ("used by") on the used plugin. Returns a sorted list of
    -- { id = 'boxnet', why = '...' }.
    function pm.normalizeUses(uses)
        local out = {}
        if type(uses) ~= 'table' then return out end
        local seen = {}
        for k, v in pairs(uses) do
            local id, why
            if type(k) == 'number' then
                id = v
            else
                id, why = k, v
            end
            if type(why) ~= 'string' or why == '' then why = nil end
            if type(id) == 'string' and id ~= '' then
                if seen[id] then
                    seen[id].why = seen[id].why or why
                else
                    seen[id] = { id = id, why = why }
                    out[#out + 1] = seen[id]
                end
            end
        end
        table.sort(out, function(a, b) return a.id < b.id end)
        return out
    end

    -- 'active' when the plugin is loaded, enabled and not in error;
    -- 'disabled' when loaded but off / errored; 'missing' when not loaded.
    function pm.useState(id)
        local p = pm.plugins[id]
        if not p then return 'missing' end
        if p.enabled and p.status ~= 'Error' then return 'active' end
        return 'disabled'
    end

    -- Plugins (in load order) that declare `id` in their uses list.
    function pm.usedBy(id)
        local out = {}
        for _, otherId in ipairs(pm.pluginOrder) do
            local o = pm.plugins[otherId]
            for _, u in ipairs(o and o.uses or {}) do
                if u.id == id then
                    out[#out + 1] = { id = otherId, why = u.why }
                    break
                end
            end
        end
        return out
    end

    function pm.loadPlugin(filename, fullPath)
        local fn, err = loadfile(fullPath)
        if not fn then
            return loadFailed(filename, fullPath, 'Syntax error: ' .. tostring(err))
        end

        local ok, inst = runPluginChunk(fn, filename)
        if not ok then
            local msg = tostring(inst)
            if msg:find('standalone script, not a MoriAC plugin', 1, true) then
                return registerScript(filename, fullPath, 'standalone script: ' .. (msg:match('it called (.-) while loading') or 'uses MQ script entry points at load'))
            end
            return loadFailed(filename, fullPath, 'Execution error: ' .. msg)
        end
        if type(inst) ~= 'table' then
            return registerScript(filename, fullPath, string.format('returns %s instead of a plugin table', type(inst)))
        end
        if not looksLikePlugin(inst) then
            return registerScript(filename, fullPath, 'returned table has no `id` and none of the plugin hooks')
        end

        local id = inst.id or filename:gsub('%.lua$', '')
        local existing = pm.plugins[id]
        if existing and existing.filename and existing.filename:lower() ~= tostring(filename):lower() then
            return loadFailed(filename, fullPath, string.format('Plugin id "%s" is already registered by %s; rename the id in this file', id, existing.filename))
        end
        pm.loadErrors[filename] = nil
        pm.scripts[filename] = nil
        pm.listVer = (pm.listVer or 0) + 1 -- invalidates the Plugins page sorted lists

        -- Reusing a live record: tear the old instance down first so its
        -- onInit side effects don't leak, and let enablePlugin init the new one.
        if existing and existing.enabled and existing.instance and existing.instance.onDestroy then
            pcall(existing.instance.onDestroy)
        end
        if existing then existing.enabled = false; existing.thread = nil end
        local p = existing or {
            id = id,
            lastExecMs = 0,
            avgExecMs = 0,
            lastTickAt = 0,
            showSettings = false,
        }

        p.filename = filename
        p.fullPath = fullPath
        p.name = inst.name or id
        p.version = inst.version or '1.0.0'
        p.author = inst.author or 'Unknown'
        p.description = inst.description or ''
        p.uses = pm.normalizeUses(inst.uses)
        p.tickInterval = tonumber(inst.tickInterval) or 0.1
        if not D.ctrl().plugins then D.ctrl().plugins = {} end
        local savedCfg = D.ctrl().plugins[id]
        if savedCfg and savedCfg.runInCombat ~= nil then
            p.runOutOfCombatOnly = not savedCfg.runInCombat
        else
            p.runOutOfCombatOnly = (inst.runOutOfCombatOnly == true)
        end
        p.hasThread = (inst.hasThread == true)
        p.instance = inst
        p.status = 'Disabled'
        p.errorMsg = nil

        if not existing then
            pm.plugins[id] = p
            table.insert(pm.pluginOrder, id)
        end

        local shouldEnable
        if savedCfg and savedCfg.enabled ~= nil then
            shouldEnable = savedCfg.enabled
        else
            shouldEnable = pm.defaultEnabledOf(inst)
        end

        if shouldEnable then
            pm.enablePlugin(id)
        else
            p.enabled = false
            p.status = 'Disabled'
        end

        return true
    end

    -- defaultEnabled may be a function, read at every (re)start, so a
    -- server-dependent default follows a camp to another server.
    function pm.defaultEnabledOf(inst)
        local d = inst.defaultEnabled
        if type(d) == 'function' then
            local ok, v = pcall(d)
            return ok and v == true
        end
        return d ~= false
    end

    function pm.enablePlugin(id)
        if pm.invalidateHeaderButtons then pm.invalidateHeaderButtons() end
        local p = pm.plugins[id]
        if not p then return end
        -- a second onInit would double-register the plugin's events/threads
        if p.enabled and p.status == 'Active' then return end

        p.enabled = true
        p.status = 'Active'
        p.errorMsg = nil
        if not D.ctrl().plugins then D.ctrl().plugins = {} end
        if not D.ctrl().plugins[id] then D.ctrl().plugins[id] = {} end
        D.ctrl().plugins[id].enabled = true

        local coreApi = pm.getCoreApi()
        if p.instance.onInit then
            local ok, err = xpcall(p.instance.onInit, debug.traceback, coreApi)
            if not ok then
                pm.reportError(p, 'onInit', err)
                return
            end
        end

        if p.instance.onLoadSettings and D.ctrl().plugins[id].settings then
            local okLoad, loadErr = pcall(p.instance.onLoadSettings, D.ctrl().plugins[id].settings)
            if not okLoad then
                print(string.format('\ay[MoriAC Plugin]\ax %s onLoadSettings failed (using defaults): %s', p.name, tostring(loadErr)))
            end
        end

        if p.hasThread then
            p.thread = pm.createFiber(p)
        end
    end

    function pm.disablePlugin(id)
        if pm.invalidateHeaderButtons then pm.invalidateHeaderButtons() end
        local p = pm.plugins[id]
        if not p then return end

        p.enabled = false
        p.status = 'Disabled'
        p.thread = nil
        if not D.ctrl().plugins then D.ctrl().plugins = {} end
        if not D.ctrl().plugins[id] then D.ctrl().plugins[id] = {} end
        D.ctrl().plugins[id].enabled = false

        if p.instance.onDestroy then
            pcall(p.instance.onDestroy)
        end
    end

    function pm.reloadPlugin(id)
        local p = pm.plugins[id]
        if not p then return end
        local fullPath = p.fullPath
        local filename = p.filename
        local wasEnabled = p.enabled
        if p.enabled then
            pm.disablePlugin(id)
        end
        -- disablePlugin persisted enabled=false; restore the user's real choice so
        -- loadPlugin re-enables a plugin that was running before the reload.
        if wasEnabled and D.ctrl().plugins and D.ctrl().plugins[id] then
            D.ctrl().plugins[id].enabled = true
        end
        pm.loadPlugin(filename, fullPath)
    end

    function pm.reloadAll()
        if pm.invalidateHeaderButtons then pm.invalidateHeaderButtons() end
        for _, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p and p.enabled then
                pm.disablePlugin(id)
                -- disablePlugin persisted enabled=false; restore the user's real
                -- choice so discover() -> loadPlugin re-enables it (same as reloadPlugin).
                if D.ctrl().plugins and D.ctrl().plugins[id] then
                    D.ctrl().plugins[id].enabled = true
                end
            end
        end
        pm.plugins = {}
        pm.pluginOrder = {}
        pm.loadErrors = {}
        pm.scripts = {}
        pm.listVer = (pm.listVer or 0) + 1 -- invalidates the Plugins page sorted lists
        pm.discover()
    end

    -- Re-run every plugin's lifecycle against the *current* ctrl without touching
    -- disk. Called after a character swap so each plugin re-seeds its defaults on
    -- the new config table and re-reads its enabled / combat flags from it.
    function pm.restartAll()
        for _, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p then
                -- Read the new character's saved flags before disablePlugin writes
                -- enabled=false into ctrl.plugins[id].
                local savedCfg = D.ctrl().plugins and D.ctrl().plugins[id]
                local savedEnabled = savedCfg and savedCfg.enabled
                local savedRunInCombat = savedCfg and savedCfg.runInCombat
                if p.enabled then pm.disablePlugin(id) end
                if savedRunInCombat ~= nil then
                    p.runOutOfCombatOnly = not savedRunInCombat
                else
                    p.runOutOfCombatOnly = (p.instance.runOutOfCombatOnly == true)
                end
                local shouldEnable
                if savedEnabled ~= nil then
                    shouldEnable = savedEnabled
                else
                    shouldEnable = pm.defaultEnabledOf(p.instance)
                end
                if shouldEnable then
                    pm.enablePlugin(id)
                else
                    if not D.ctrl().plugins then D.ctrl().plugins = {} end
                    if not D.ctrl().plugins[id] then D.ctrl().plugins[id] = {} end
                    D.ctrl().plugins[id].enabled = false
                    D.ctrl().plugins[id].runInCombat = not p.runOutOfCombatOnly
                end
            end
        end
    end

    -- Scan the plugin folder and load any file not already registered. Files that
    -- are already loaded are left alone (use reloadPlugin / reloadAll for those) so
    -- a rescan never re-runs onInit on a live instance without onDestroy.
    function pm.discover()
        local dir = pm.getPluginDir()
        if not dir then return end
        local files = {}
        local fileSet = {}
        local loadedFiles = {}
        for _, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p and p.filename then loadedFiles[p.filename:lower()] = true end
        end
        -- Known standalone scripts are not re-executed on a rescan (their
        -- chunk may have side effects); "Re-check" on the Plugins page does that.
        for fname in pairs(pm.scripts or {}) do loadedFiles[tostring(fname):lower()] = true end
        -- Shared library modules that live in the plugin folder but are
        -- require()d by the core itself. Running their chunk again here
        -- would create a second instance and list them as a stray script.
        for fname in pairs(PLUGIN_DIR_LIBRARIES) do loadedFiles[fname] = true end

        local function addFile(fname)
            if fname and fname:match('%.lua$') then
                local low = fname:lower()
                if not fileSet[low] and not loadedFiles[low] then
                    fileSet[low] = true
                    table.insert(files, fname)
                end
            end
        end

        -- Method 1: LuaFileSystem (lfs)
        local okLfs, lfs = pcall(require, 'lfs')
        local lfsListed = false
        if okLfs and lfs and lfs.dir then
            pcall(function()
                for f in lfs.dir(dir) do
                    addFile(f)
                    lfsListed = true
                end
            end)
        end

        -- Method 2: OS popen directory query (dynamically finds custom dropped
        -- plugins). Only when lfs could not list the folder: on Windows this
        -- spawns cmd.exe on every Rescan / Reload All.
        if not lfsListed then pcall(function()
            local isWin = (package.config and package.config:sub(1, 1) == '\\')
            local cmd
            local dirStr = tostring(dir or '')
            if isWin then
                local winDir = dirStr:gsub('/', '\\')
                cmd = string.format('dir /b "%s\\*.lua" 2>nul', winDir)
            else
                cmd = string.format('ls -1 "%s"/*.lua 2>/dev/null', dirStr)
            end
            local p = io.popen(cmd)
            if p then
                for line in p:lines() do
                    local fname = line:match('([^\\/]+%.lua)$') or line:match('^%s*(.-%.lua)%s*$')
                    addFile(fname)
                end
                p:close()
            end
        end) end

        -- Method 3: Core known plugins direct probe fallback
        local known = {
            'hud_unitframes.lua',
            'auto_accept.lua',
            'floating_damage.lua',
            'hud_group.lua',
            'hud_effects.lua',
            'hud_xtarget.lua',
            'hud_cooldowns.lua',
            'hud_spellgems.lua',
            'auto_aa.lua',
            'spellbook.lua',
            'cursor.lua',
            'dps.lua',
            'inventory.lua',
            'buffbot.lua',
            'chat.lua',
            'map.lua',
            'boxnet.lua',
            'buttons.lua',
            'gamedb.lua',
            'parcels.lua',
            'nmsloot.lua',
            'nms_looter_handoff.lua',
            'gm_commands.lua',
            'update_check.lua',
            'alerts.lua',
            'timers.lua',
            'tradeskill.lua',
        }
        for _, f in ipairs(known) do
            if not fileSet[f:lower()] then
                local fp = dir .. '/' .. f
                local testF = io.open(fp, 'r')
                if testF then
                    testF:close()
                    addFile(f)
                end
            end
        end

        table.sort(files)
        for _, f in ipairs(files) do
            local fullPath = dir .. '/' .. f
            pm.loadPlugin(f, fullPath)
        end

        pm.lastScanAt = os.clock()
    end

    -- Plugin lifecycle work requested from the UI (Rescan, Reload, Retry,
    -- Re-check, Enable / Disable) is queued here and run from pm.tick() on the
    -- main script coroutine. Running a dropped-in file's chunk or a plugin's
    -- onInit / onDestroy inside the ImGui render callback crashed mq2lua
    -- (the chunk or hook can register ImGui callbacks, bind commands, or call
    -- mq.exit while the frame is being rendered), so the render thread only
    -- ever enqueues.
    pm.deferred = {}
    function pm.defer(label, fn)
        pm.deferred[#pm.deferred + 1] = { label = tostring(label or 'plugin op'), fn = fn }
    end

    function pm.hasDeferred()
        return #pm.deferred > 0
    end

    function pm.runDeferred()
        if #pm.deferred == 0 then return 0 end
        local ops = pm.deferred
        pm.deferred = {}
        for _, op in ipairs(ops) do
            local ok, err = xpcall(op.fn, debug.traceback)
            if not ok then
                local full = tostring(err)
                local first = full:match('^([^\n]*)') or full
                print(string.format('\ar[MoriAC Plugin Error]\ax %s failed: %s', op.label, first))
                if full ~= first then tlog.error('plugin', '%s traceback:\n%s', op.label, full) end
            end
        end
        return #ops
    end

    function pm.tick()
        pm.runDeferred()
        local inCombat = false
        pcall(function()
            inCombat = (mq.TLO.Me.Combat() or (mq.TLO.Me.CombatState and mq.TLO.Me.CombatState() == 'COMBAT'))
        end)

        local now = os.clock()
        for _, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p and p.enabled and p.status ~= 'Error' then
                if inCombat and p.runOutOfCombatOnly then
                    p.status = 'Sleeping (Combat)'
                else
                    p.status = 'Active'
                    if (now - p.lastTickAt) >= p.tickInterval then
                        p.lastTickAt = now
                        local t0 = os.clock()

                        if p.hasThread and p.thread then
                            if coroutine.status(p.thread) == 'dead' then
                                p.thread = pm.createFiber(p)
                            end
                            pm.inFiber = true
                            local ok, err = coroutine.resume(p.thread)
                            pm.inFiber = false
                            if not ok then
                                pm.reportError(p, 'fiber', debug.traceback(p.thread, tostring(err)))
                            end
                        elseif p.instance.onTick then
                            local ok, err = xpcall(p.instance.onTick, debug.traceback)
                            if not ok then
                                pm.reportError(p, 'onTick', err)
                            end
                        end

                        local elapsedMs = (os.clock() - t0) * 1000
                        p.lastExecMs = elapsedMs
                        p.avgExecMs = p.avgExecMs and (p.avgExecMs * 0.9 + elapsedMs * 0.1) or elapsedMs
                    end
                end
            end
        end
    end

    -- Render hook. A draw error is fatal for that plugin: an exception between
    -- ImGui.Begin and ImGui.End leaves the ImGui stack unbalanced, so we flag the
    -- plugin as Error (which stops drawing it) rather than retrying every frame.
    function pm.drawUI()
        pm.inDraw = true
        for _, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p and p.enabled and p.status ~= 'Error' and p.instance.onDrawUI then
                local ok, err = xpcall(p.instance.onDrawUI, debug.traceback)
                if not ok then
                    pm.reportError(p, 'onDrawUI', err)
                end
            end
        end
        pm.inDraw = false
    end

    -- Draws one plugin's settings panel inline. Lets a core Settings sub-tab keep
    -- its familiar place in the UI while the plugin owns the actual controls.
    function pm.drawPluginSettings(id)
        local p = pm.plugins[id]
        if not p then
            ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4],
                string.format('Plugin "%s" is not loaded. Drop %s.lua into %s and click Rescan on Setup -> Plugins.',
                    id, id, tostring(pm.dirPath or 'lua/tac')))
            return false
        end
        if p.status == 'Error' then
            ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], string.format('%s plugin hit an error: %s', p.name, tostring(p.errorMsg or '?')))
            if ImGui.SmallButton('Reload Plugin##reload_' .. id) then
                pm.defer('reload ' .. id, function() pm.reloadPlugin(id) end)
            end
            return false
        end
        if not p.enabled then
            ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], string.format('%s plugin is disabled.', p.name))
            ImGui.SameLine()
            if ImGui.SmallButton('Enable##enable_' .. id) then
                pm.defer('enable ' .. id, function()
                    pm.enablePlugin(id)
                    runtime.saveLoadout(true)
                end)
            end
            return false
        end
        if not p.instance.onDrawSettings then
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'This plugin has no configurable settings.')
            return true
        end
        local wasInDraw = pm.inDraw
        pm.inDraw = true
        local ok, err = xpcall(p.instance.onDrawSettings, debug.traceback)
        pm.inDraw = wasInDraw
        if not ok then
            pm.reportError(p, 'onDrawSettings', err)
            return false
        end
        return true
    end

    -- Runs a hook on every active plugin that defines it; a hook error flags the
    -- plugin. `firstTrue` stops at (and returns) the first truthy result.
    local function dispatch(hookName, firstTrue, ...)
        for _, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p and p.enabled and p.status ~= 'Error' and p.instance[hookName] then
                local ok, res = xpcall(p.instance[hookName], debug.traceback, ...)
                if not ok then
                    pm.reportError(p, hookName, res)
                elseif firstTrue and res then
                    return res
                end
            end
        end
        return false
    end

    -- Per-combat-tick and zone-change notifications.
    function pm.onCombatTick(targetId) dispatch('onCombatTick', false, targetId) end
    function pm.onZoned(curZone) dispatch('onZoned', false, curZone) end

    -- True while any plugin asks the combat loop to stand still (e.g. an AA
    -- purchase workflow with the AA window open).
    function pm.combatHold() return dispatch('wantsCombatHold', true) == true end

    -- Puller idle gap between pulls. A plugin returns true if it started
    -- something that needs the puller to yield this tick.
    function pm.onBetweenPulls() return dispatch('onBetweenPulls', true) == true end

    -- /ac <cmd> fallthrough. A plugin returns true if it handled the command.
    function pm.onCommand(cmd, args) return dispatch('onCommand', true, cmd, args) == true end

    -- Help lines contributed by plugins (plugin.help = { 'line', ... })
    function pm.helpLines()
        local out = {}
        for _, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p and p.enabled and type(p.instance.help) == 'table' then
                for _, hl in ipairs(p.instance.help) do out[#out + 1] = hl end
            end
        end
        return out
    end

    -- Fired after the loadout file has been written.
    function pm.onLoadoutSaved() dispatch('onLoadoutSaved', false) end

    -- ------------------------------------------------------------------
    -- Plugin windows. A plugin that owns a toggleable window declares
    --   plugin.window = { label = 'Map', tooltip = '...', flag = 'show_map',
    --                     headerButton = true, order = 20 }
    -- `flag` names the ctrl.* boolean that drives visibility (saved with the
    -- loadout); a plugin may supply isOpen() / setOpen(bool) instead. The
    -- Plugins page lets the user pick which of these get a toggle button on
    -- the main window header (ctrl.plugins[id].headerButton, defaulting to
    -- window.headerButton ~= false).
    -- A plugin with more than one window lists the others in
    --   plugin.windows = { { key = 'target_window', label = 'Target', flag = ..., ... }, ... }
    -- (same shape, `key` required and unique: it is the layout key). Each is
    -- addressed everywhere as '<pluginId>:<key>'; its header-button choice is
    -- kept in ctrl.plugins[pluginId].windowHeader[key].
    -- ------------------------------------------------------------------
    local function splitWindowId(id)
        local pid, sub = tostring(id):match('^([^:]+):(.+)$')
        if pid then return pid, sub end
        return id, nil
    end
    pm.splitWindowId = splitWindowId

    local function windowDecl(w)
        if type(w) ~= 'table' then return nil end
        if type(w.flag) ~= 'string' and type(w.isOpen) ~= 'function' then return nil end
        return w
    end

    function pm.getWindow(id)
        local pid, sub = splitWindowId(id)
        local p = pm.plugins[pid]
        local inst = p and p.instance
        if not inst then return nil end
        if not sub then return windowDecl(inst.window) end
        if type(inst.windows) ~= 'table' then return nil end
        for _, w in ipairs(inst.windows) do
            if type(w) == 'table' and w.key == sub then return windowDecl(w) end
        end
        return nil
    end

    function pm.isWindowOpen(id)
        local w = pm.getWindow(id)
        if not w then return false end
        if type(w.isOpen) == 'function' then
            local ok, res = pcall(w.isOpen)
            return ok and res == true
        end
        return D.ctrl()[w.flag] == true
    end

    function pm.setWindowOpen(id, val)
        local w = pm.getWindow(id)
        if not w then return false end
        val = (val == true)
        if type(w.setOpen) == 'function' then
            pcall(w.setOpen, val)
        else
            D.ctrl()[w.flag] = val
        end
        runtime.saveLoadout(true)
        return true
    end

    function pm.toggleWindow(id)
        return pm.setWindowOpen(id, not pm.isWindowOpen(id))
    end

    function pm.headerButtonEnabled(id)
        local w = pm.getWindow(id)
        if not w then return false end
        local pid, sub = splitWindowId(id)
        local pc = D.ctrl().plugins and D.ctrl().plugins[pid]
        local saved
        if sub then
            saved = pc and type(pc.windowHeader) == 'table' and pc.windowHeader[sub] or nil
        else
            saved = pc and pc.headerButton
        end
        if saved ~= nil then return saved == true end
        return w.headerButton ~= false
    end

    function pm.setHeaderButton(id, val)
        if pm.invalidateHeaderButtons then pm.invalidateHeaderButtons() end
        if not D.ctrl().plugins then D.ctrl().plugins = {} end
        local pid, sub = splitWindowId(id)
        if not D.ctrl().plugins[pid] then D.ctrl().plugins[pid] = {} end
        if sub then
            if type(D.ctrl().plugins[pid].windowHeader) ~= 'table' then D.ctrl().plugins[pid].windowHeader = {} end
            D.ctrl().plugins[pid].windowHeader[sub] = (val == true)
        else
            D.ctrl().plugins[pid].headerButton = (val == true)
        end
        runtime.saveLoadout(true)
    end

    -- Active plugins with a window, in header order (window.order, then load
    -- order); a plugin's extra windows follow its main one.
    function pm.windowPlugins(headerOnly)
        local out = {}
        for i, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p and p.enabled and p.status ~= 'Error' then
                local w = pm.getWindow(id)
                if w and (not headerOnly or pm.headerButtonEnabled(id)) then
                    out[#out + 1] = { id = id, pluginId = id, window = w, order = tonumber(w.order) or 100, idx = i }
                end
                local extra = p.instance and p.instance.windows
                if type(extra) == 'table' then
                    for j, x in ipairs(extra) do
                        if type(x) == 'table' and type(x.key) == 'string' then
                            local xid = id .. ':' .. x.key
                            local xw = pm.getWindow(xid)
                            if xw and (not headerOnly or pm.headerButtonEnabled(xid)) then
                                out[#out + 1] = { id = xid, pluginId = id, window = xw, order = tonumber(xw.order) or 100, idx = i + j / 1000 }
                            end
                        end
                    end
                end
            end
        end
        table.sort(out, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.idx < b.idx
        end)
        return out
    end

    -- Main-window header buttons: plugin window toggles (open windows are
    -- highlighted) followed by Run / Stop buttons for standalone scripts
    -- that asked for one (running scripts are highlighted). Rows hold at
    -- most HEADER_BUTTONS_PER_ROW buttons (the caller passes how many it
    -- already drew on the current row, e.g. the Compact Mode button) and
    -- also wrap early when the header runs out of width. Returns the number
    -- of buttons drawn.
    pm.HEADER_BUTTONS_PER_ROW = 8
    function pm.invalidateHeaderButtons() pm.headerButtonCache = nil end

    -- Body of the main window's Windows menu (call between BeginPopup /
    -- EndPopup or BeginMenu / EndMenu): every active plugin window as a
    -- checkable item, then the standalone scripts. Returns items drawn.
    function pm.drawWindowsMenu()
        local nowWm = os.clock()
        local wm = pm.windowsMenuCache
        if not wm or (nowWm - wm.at) >= 1.0 then
            wm = { at = nowWm, entries = pm.windowPlugins(false), scripts = pm.headerScripts() }
            pm.windowsMenuCache = wm
        end
        local drawn = 0
        for _, e in ipairs(wm.entries) do
            local label = tostring(e.window.label or e.id)
            if ImGui.MenuItem(label .. '##wmPlg_' .. e.id, nil, pm.isWindowOpen(e.id)) then
                pm.toggleWindow(e.id)
            end
            if ImGui.IsItemHovered() and e.window.tooltip then UI.setTooltip('%s', tostring(e.window.tooltip)) end
            drawn = drawn + 1
        end
        if #wm.scripts > 0 then
            if drawn > 0 then ImGui.Separator() end
            for _, sc in ipairs(wm.scripts) do
                if ImGui.MenuItem(pm.scriptButtonLabel(sc) .. '##wmScr_' .. tostring(sc.file), nil, pm.isScriptRunning(sc)) then
                    pm.toggleScript(sc)
                end
                drawn = drawn + 1
            end
        end
        if drawn == 0 then ImGui.TextDisabled('No plugin windows are enabled (Setup -> Plugins).') end
        return drawn
    end
    function pm.drawHeaderButtons(buttonsOnRow)
        -- windowPlugins / headerScripts allocate and sort per call; rebuild
        -- the ordered lists at most once a second (plugin enable/disable and
        -- header toggles call pm.invalidateHeaderButtons for an instant refresh).
        local nowHb = os.clock()
        local hb = pm.headerButtonCache
        if not hb or (nowHb - hb.at) >= 1.0 then
            hb = { at = nowHb, entries = pm.windowPlugins(true), scripts = pm.headerScripts() }
            pm.headerButtonCache = hb
        end
        local entries, scripts = hb.entries, hb.scripts
        if #entries == 0 and #scripts == 0 then return 0 end
        local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
        local perRow = tonumber(pm.HEADER_BUTTONS_PER_ROW) or 8
        local col = tonumber(buttonsOnRow) or 0
        local winW = 0
        pcall(function()
            local w = ImGui.GetWindowContentRegionMax and ImGui.GetWindowContentRegionMax()
            if type(w) == 'number' then winW = w elseif type(w) == 'table' or type(w) == 'userdata' then winW = w.x or 0 end
        end)
        local drawn = 0
        -- Places one button on the current row (or starts a new row when the
        -- row is full / out of width) and fires onClick when pressed.
        local function button(label, idSuffix, highlight, tip, onClick)
            if col > 0 then
                if col >= perRow then
                    -- Row is full: the next button starts a new row.
                    col = 0
                else
                    ImGui.SameLine()
                    if winW > 0 then
                        local okW, textW = pcall(function()
                            local tw = ImGui.CalcTextSize(label)
                            if type(tw) ~= 'number' then tw = tw and tw.x or 0 end
                            return tw + 16
                        end)
                        local okX, curX = pcall(ImGui.GetCursorPosX)
                        if okW and okX and type(curX) == 'number' and (curX + (textW or 0)) > winW then
                            ImGui.NewLine()
                            col = 0
                        end
                    end
                end
            end
            local pushed = 0
            if highlight and Col and pcall(ImGui.PushStyleColor, Col.Button, 0.12, 0.45, 0.65, 1.0) then pushed = 1 end
            if ImGui.Button(label .. idSuffix) then
                onClick()
            end
            if pushed > 0 then pcall(ImGui.PopStyleColor, pushed) end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('%s', tostring(type(tip) == 'function' and tip() or tip))
            end
            drawn = drawn + 1
            col = col + 1
        end
        for _, e in ipairs(entries) do
            -- labels / ids / tooltips are built once per entry and kept on it
            if not e.hdrLabel then
                e.hdrLabel = tostring(e.window.label or e.id)
                e.hdrId = '##hdrPlg_' .. e.id
                e.hdrTip = e.window.tooltip or ('Toggles the ' .. e.hdrLabel .. ' window (' .. e.id .. ' plugin).')
                e.hdrClick = function() pm.toggleWindow(e.id) end
            end
            button(e.hdrLabel, e.hdrId, pm.isWindowOpen(e.id), e.hdrTip, e.hdrClick)
        end
        for _, sc in ipairs(scripts) do
            local running = pm.isScriptRunning(sc)
            if not sc.hdrId then
                sc.hdrId = '##hdrScr_' .. tostring(sc.file)
                sc.hdrClick = function() pm.toggleScript(sc) end
                sc.hdrTipRun = string.format('Runs %s as its own /lua script (/lua run %s).\nClick again while it is running to stop it.', sc.name, tostring(sc.runName))
                sc.hdrTipStop = string.format('Stops %s (/lua stop %s).', sc.name, tostring(sc.runName))
            end
            button(pm.scriptButtonLabel(sc), sc.hdrId, running, running and sc.hdrTipStop or sc.hdrTipRun, sc.hdrClick)
        end
        return drawn
    end

    function pm.collectSettings()
        if not D.ctrl().plugins then D.ctrl().plugins = {} end
        for _, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p then
                if not D.ctrl().plugins[id] then D.ctrl().plugins[id] = {} end
                D.ctrl().plugins[id].enabled = (p.enabled == true)
                D.ctrl().plugins[id].runInCombat = not p.runOutOfCombatOnly
                if pm.getWindow(id) and D.ctrl().plugins[id].headerButton == nil then
                    D.ctrl().plugins[id].headerButton = pm.headerButtonEnabled(id)
                end
                if p.instance and p.instance.onSaveSettings then
                    local ok, s = pcall(p.instance.onSaveSettings)
                    if ok and type(s) == 'table' then
                        D.ctrl().plugins[id].settings = s
                    end
                end
            end
        end
    end

    pm.discover()
end
end

return M
