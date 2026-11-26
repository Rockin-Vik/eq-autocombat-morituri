-- moriac_ui_plugins.lua: extracted verbatim from moriac.lua (behaviour-preserving split).
-- Dependencies come in through D (see the init call in moriac.lua); live bindings
-- that moriac.lua reassigns (ctrl, loadout, ...) are read through D.<name>().
local M = {}

function M.init(runtime, UI, D)
    local ARC = D.ARC
    local ERR = D.ERR
    local GOLD = D.GOLD
    local GOOD = D.GOOD
    local ImGui = D.ImGui
    local MUTED = D.MUTED
    local WARN = D.WARN
    local accent = D.accent
-- Setup -> Update: the Updater plugin's panel on its own page, so checking
-- and installing is one click away instead of under Plugins -> Config.
function UI.drawUpdateTab()
    -- pm is created once at startup (runtime.initPluginManager in main), never from draw
    local pm = runtime.pluginManager
    if not pm then return end
    ImGui.PushTextWrapPos(0)
    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4],
        'Check and Install looks for newer MoriAC files on GitHub and installs them if there are any. Restart MoriAC afterwards to load them; your settings and loadouts are kept.')
    ImGui.PopTextWrapPos()
    ImGui.Spacing()
    pm.drawPluginSettings('update_check')
end

function UI.drawPluginsTab()
    -- pm is created once at startup (runtime.initPluginManager in main), never from draw
    local pm = runtime.pluginManager
    if not pm then return end

    -- Toolbar: title, folder, actions and counts on one line.
    ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], 'Plugins')
    ImGui.SameLine()
    local dirStr = pm.dirPath or 'lua/tac'
    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], tostring(dirStr))
    ImGui.SameLine()
    if ImGui.SmallButton('Rescan##btnRescanPlugins') then
        pm.defer('rescan plugins folder', pm.discover)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Scans the lua/tac directory for newly dropped or updated .lua plugins.')
    end
    ImGui.SameLine()
    if ImGui.SmallButton('Reload All##btnReloadAllPlugins') then
        pm.defer('reload all plugins', pm.reloadAll)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Restarts and reloads all discovered plugins.')
    end

    local totalLoaded = #pm.pluginOrder
    local activeCount = 0
    for _, id in ipairs(pm.pluginOrder) do
        local p = pm.plugins[id]
        if p and p.enabled and p.status ~= 'Error' then
            activeCount = activeCount + 1
        end
    end

    -- Sorted once per pm.listVer bump (every pm.loadErrors / pm.scripts change).
    local lc = pm.sortedListsCache
    if not lc or lc.ver ~= (pm.listVer or 0) then
        local failedFiles = {}
        for fname, info in pairs(pm.loadErrors or {}) do
            failedFiles[#failedFiles + 1] = { file = fname, info = info }
        end
        table.sort(failedFiles, function(a, b) return a.file:lower() < b.file:lower() end)

        local scriptFiles = {}
        for fname, entry in pairs(pm.scripts or {}) do
            scriptFiles[#scriptFiles + 1] = entry
            entry.file = entry.file or fname
        end
        table.sort(scriptFiles, function(a, b) return a.name:lower() < b.name:lower() end)
        lc = { ver = pm.listVer or 0, failed = failedFiles, scripts = scriptFiles }
        pm.sortedListsCache = lc
    end
    local failedFiles, scriptFiles = lc.failed, lc.scripts

    ImGui.SameLine()
    ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], string.format('Loaded: %d | Active: %d', totalLoaded, activeCount))
    if #scriptFiles > 0 then
        ImGui.SameLine()
        ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], string.format('| Standalone scripts: %d', #scriptFiles))
    end
    if #failedFiles > 0 then
        ImGui.SameLine()
        ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], string.format('| Failed to load: %d', #failedFiles))
    end
    if pm.hasDeferred() then
        ImGui.SameLine()
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], '| working...')
    end
    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4],
        'On = enabled   Cbt = keeps ticking in combat   Hdr = button on the main window header   Name colour: green active, blue sleeping in combat, grey disabled, red error. Hover a cell for details.')

    -- Tight rows for every table on this page.
    ImGui.PushStyleVar(ImGuiStyleVar.CellPadding, 4, 1)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 3, 1)
    local okBody, stop = xpcall(function()
    local tblFlags = bit.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable, ImGuiTableFlags.SizingFixedFit)

    -- Files in the plugin folder that are not loadable plugins (syntax errors,
    -- duplicate ids). They are never registered, so without this list a bad
    -- drop-in would only ever show as one chat line.
    if #failedFiles > 0 then
        if ImGui.CollapsingHeader(string.format('Failed to load (%d)##plgFailedHdr', #failedFiles), ImGuiTreeNodeFlags.DefaultOpen) then
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'Files in the plugin folder that could not be loaded:')
            for i, entry in ipairs(failedFiles) do
                ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], entry.file)
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('Retry##retryPlg_%d', i)) then
                    pm.defer('retry ' .. entry.file, function() pm.loadPlugin(entry.file, entry.info.fullPath) end)
                end
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('Dismiss##dismissPlg_%d', i)) then
                    pm.loadErrors[entry.file] = nil
                    pm.listVer = (pm.listVer or 0) + 1 -- invalidates the Plugins page sorted lists
                end
                ImGui.SameLine()
                ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], tostring(entry.info.msg or ''))
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', tostring(entry.info.msg or ''))
                end
            end
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'Only files that return a plugin table (an `id` or lifecycle hooks) are loaded as plugins; other runnable files are listed under Standalone Scripts.')
        end
    end

    -- Standalone scripts dropped into the folder: not plugins, but they get a
    -- basic entry with Run / Stop so they can be launched independently of
    -- Triune (`/lua run <folder>/<name>`), and optionally a header button.
    if #scriptFiles > 0 then
        local openScripts = ImGui.CollapsingHeader(string.format('Standalone Scripts (%d)##plgScriptsHdr', #scriptFiles), ImGuiTreeNodeFlags.DefaultOpen)
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('%s', 'Runnable .lua files in the plugin folder that do not follow the plugin contract. MoriAC does not load them; Run / Stop launches each as its own /lua script.\nHdr puts a Run / Stop button for the script on the main window header, named by Button Name (blank = file name).')
        end
        if openScripts and ImGui.BeginTable('TriuneScriptsTable', 5, tblFlags) then
            ImGui.TableSetupColumn('Script', ImGuiTableColumnFlags.WidthFixed, UI.px(150))
            ImGui.TableSetupColumn('Status', ImGuiTableColumnFlags.WidthFixed, UI.px(64))
            ImGui.TableSetupColumn('Pin', ImGuiTableColumnFlags.WidthFixed, UI.px(30))
            ImGui.TableSetupColumn('Button Name', ImGuiTableColumnFlags.WidthStretch, 0)
            ImGui.TableSetupColumn('Actions', ImGuiTableColumnFlags.WidthFixed, UI.px(120))
            ImGui.TableHeadersRow()
            for i, entry in ipairs(scriptFiles) do
                ImGui.TableNextRow()
                local running = pm.isScriptRunning(entry)

                ImGui.TableNextColumn()
                ImGui.Text(entry.name)
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', string.format('/lua run %s\nNot loaded as a plugin: %s', tostring(entry.runName), tostring(entry.reason or '')))
                end

                ImGui.TableNextColumn()
                if running then
                    ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], 'Running')
                else
                    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'Stopped')
                end

                -- Header button toggle: a Run / Stop button on the main window header
                ImGui.TableNextColumn()
                local hdrOn = pm.scriptHeaderButtonEnabled(entry)
                local newHdr = ImGui.Checkbox(string.format('##hdrScr_%d', i), hdrOn)
                if newHdr ~= hdrOn then
                    pm.setScriptHeaderButton(entry, newHdr)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', string.format('%s "%s" in the main window sidebar (tick to run, untick to stop).',
                        hdrOn and 'Pinned:' or 'Tick to pin', pm.scriptButtonLabel(entry)))
                end

                -- Button name: saved when the field loses focus, not per keystroke
                ImGui.TableNextColumn()
                local curName = pm.scriptButtonName(entry)
                ImGui.SetNextItemWidth(-1)
                local newName = ImGui.InputText(string.format('##lblScr_%d', i), curName, 64)
                if type(newName) == 'string' and newName ~= curName then
                    pm.setScriptButtonName(entry, newName, false)
                end
                local okDone, done = pcall(ImGui.IsItemDeactivatedAfterEdit)
                if (okDone and done) or (not okDone and type(newName) == 'string' and newName ~= curName) then
                    runtime.saveLoadout(true)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', 'Text on the header button. Leave blank to use the file name (' .. tostring(entry.name) .. ').')
                end

                ImGui.TableNextColumn()
                if ImGui.SmallButton((running and 'Stop' or 'Run') .. string.format('##scr_%d', i)) then
                    pm.toggleScript(entry)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', running and ('Executes /lua stop ' .. tostring(entry.runName))
                        or ('Executes /lua run ' .. tostring(entry.runName) .. '\nThe script runs as its own MQ Lua process, independent of MoriAC.'))
                end
                ImGui.SameLine()
                if ImGui.SmallButton(string.format('Re-check##scrchk_%d', i)) then
                    pm.defer('re-check ' .. entry.file, function() pm.loadPlugin(entry.file, entry.fullPath) end)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', 'Re-evaluates the file: if it now returns a plugin table it is loaded as a plugin.')
                end
            end
            ImGui.EndTable()
        end
    end

    if totalLoaded == 0 then
        ImGui.TextColored(WARN[1], WARN[2], WARN[3], WARN[4], 'No plugins found in ' .. tostring(dirStr) .. '.')
        ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'Drop any compatible .lua plugin into the folder and click "Rescan".')
        return true
    end

    -- One line per plugin. Status is the name colour (details in the
    -- tooltip); the description is clipped to its column with the full text
    -- on hover.
    if ImGui.BeginTable('TriunePluginsTable', 8, tblFlags) then
        ImGui.TableSetupColumn('On', ImGuiTableColumnFlags.WidthFixed, UI.px(26))
        ImGui.TableSetupColumn('Cbt', ImGuiTableColumnFlags.WidthFixed, UI.px(30))
        ImGui.TableSetupColumn('Pin', ImGuiTableColumnFlags.WidthFixed, UI.px(30))
        ImGui.TableSetupColumn('Plugin', ImGuiTableColumnFlags.WidthFixed, UI.px(165))
        ImGui.TableSetupColumn('Uses', ImGuiTableColumnFlags.WidthFixed, UI.px(105))
        ImGui.TableSetupColumn('ms', ImGuiTableColumnFlags.WidthFixed, UI.px(44))
        ImGui.TableSetupColumn('Description', ImGuiTableColumnFlags.WidthStretch, 0)
        ImGui.TableSetupColumn('Actions', ImGuiTableColumnFlags.WidthFixed, UI.px(170))
        ImGui.TableHeadersRow()

        for idx, id in ipairs(pm.pluginOrder) do
            local p = pm.plugins[id]
            if p then
                ImGui.TableNextRow()
                local w = pm.getWindow(id)

                -- Col 1: Active toggle
                ImGui.TableNextColumn()
                local isEn = (p.enabled == true)
                if p.pendingEnabled ~= nil then isEn = p.pendingEnabled end
                local newEn = ImGui.Checkbox(string.format('##enPlg_%d', idx), isEn)
                if newEn ~= isEn then
                    p.pendingEnabled = newEn
                    pm.defer((newEn and 'enable ' or 'disable ') .. id, function()
                        if newEn then
                            pm.enablePlugin(id)
                        else
                            pm.disablePlugin(id)
                        end
                        p.pendingEnabled = nil
                        local cur = pm.plugins[id]  -- record may have been replaced meanwhile
                        if cur then cur.pendingEnabled = nil end
                        runtime.saveLoadout(true)
                    end)
                end
                if ImGui.IsItemHovered() then
                    local tip = isEn and 'Plugin is enabled. Uncheck to disable.' or 'Plugin is disabled. Check to enable.'
                    local usedBy = pm.usedBy(id)
                    if #usedBy > 0 then
                        local names = {}
                        for _, u in ipairs(usedBy) do names[#names + 1] = u.id end
                        tip = tip .. string.format('\n%s by: %s (see the Uses column).', isEn and 'Disabling turns off features used' or 'Enabling restores features used', table.concat(names, ', '))
                    end
                    ImGui.SetTooltip('%s', tip)
                end

                -- Col 2: In-Combat toggle
                ImGui.TableNextColumn()
                local runInCombat = not p.runOutOfCombatOnly
                local newRunInCombat = ImGui.Checkbox(string.format('##cbPlg_%d', idx), runInCombat)
                if newRunInCombat ~= runInCombat then
                    p.runOutOfCombatOnly = not newRunInCombat
                    if not D.ctrl().plugins then D.ctrl().plugins = {} end
                    if not D.ctrl().plugins[id] then D.ctrl().plugins[id] = {} end
                    D.ctrl().plugins[id].runInCombat = newRunInCombat
                    runtime.saveLoadout(true)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', runInCombat
                        and 'Active in Combat: Fiber updates continuously during battle.\nUncheck to put to sleep during combat.'
                        or 'Sleeps in Combat: Fiber pauses during combat to eliminate latency.\nCheck to allow continuous updates in battle.')
                end

                -- Col 3: Header button toggle (plugins that own a window)
                ImGui.TableNextColumn()
                if w then
                    local hdrOn = pm.headerButtonEnabled(id)
                    local newHdr = ImGui.Checkbox(string.format('##hdrPlg_%d', idx), hdrOn)
                    if newHdr ~= hdrOn then
                        pm.setHeaderButton(id, newHdr)
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('%s', string.format('%s "%s" in the main window sidebar for one-click open / close. Every window is also in the Windows menu.',
                            hdrOn and 'Pinned:' or 'Tick to pin', tostring(w.label or id)))
                    end
                else
                    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], '—')
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('%s', 'This plugin has no window of its own.')
                    end
                end

                -- Col 4: Name, coloured by status; version / author / status in the tooltip
                ImGui.TableNextColumn()
                local statusCol, statusText = MUTED, 'Disabled'
                if p.status == 'Active' then
                    statusCol, statusText = GOOD, 'Active'
                elseif p.status == 'Sleeping (Combat)' then
                    statusCol, statusText = ARC, 'Sleeping (combat)'
                elseif p.status == 'Error' then
                    statusCol, statusText = ERR, 'Error: ' .. tostring(p.errorMsg or '?')
                end
                ImGui.TextColored(statusCol[1], statusCol[2], statusCol[3], statusCol[4], p.name or id)
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', string.format('%s  (id: %s)\nv%s by %s\nStatus: %s%s', p.name or id, id, p.version or '1.0', p.author or 'Unknown', statusText,
                        w and ('\nWindow: ' .. tostring(w.label or id) .. (pm.isWindowOpen(id) and ' (open)' or ' (closed)')) or ''))
                end

                -- Col 5: Uses (optional integrations with other plugins) and
                -- used-by. Amber when a used plugin is off or missing: that
                -- feature is silently disabled.
                ImGui.TableNextColumn()
                local usedBy = pm.usedBy(id)
                if #(p.uses or {}) == 0 and #usedBy == 0 then
                    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], '—')
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('%s', 'Standalone: does not use, and is not used by, any other plugin.')
                    end
                else
                    local tip = {}
                    for i, u in ipairs(p.uses or {}) do
                        local st = pm.useState(u.id)
                        local col = (st == 'active') and GOOD or WARN
                        if i > 1 then ImGui.SameLine(0, UI.px(4)) end
                        ImGui.TextColored(col[1], col[2], col[3], col[4], u.id)
                        tip[#tip + 1] = string.format('Uses %s (%s)%s', u.id,
                            st == 'active' and 'active' or (st == 'missing' and 'NOT LOADED' or 'DISABLED'),
                            u.why and (': ' .. u.why) or '')
                        if st ~= 'active' then
                            tip[#tip + 1] = string.format('  -> %s works without it; that feature is off until %s is active.', p.name or id, u.id)
                        end
                    end
                    if #usedBy > 0 then
                        if #(p.uses or {}) > 0 then ImGui.SameLine(0, UI.px(4)) end
                        ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], string.format('(used by %d)', #usedBy))
                        if #tip > 0 then tip[#tip + 1] = '' end
                        tip[#tip + 1] = 'Used by:'
                        for _, u in ipairs(usedBy) do
                            local o = pm.plugins[u.id]
                            tip[#tip + 1] = string.format('  %s%s', o and o.name or u.id, u.why and (' - ' .. u.why) or '')
                        end
                        tip[#tip + 1] = string.format('Disabling %s turns those features off; the other plugins keep running.', p.name or id)
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('%s', table.concat(tip, '\n'))
                    end
                end

                -- Col 6: Latency Profiler
                ImGui.TableNextColumn()
                if p.enabled and p.status ~= 'Disabled' then
                    local avg = p.avgExecMs or 0
                    local col = (avg < 1.0) and GOOD or ((avg < 3.0) and WARN or ERR)
                    ImGui.TextColored(col[1], col[2], col[3], col[4], string.format('%.2f', avg))
                    if ImGui.IsItemHovered() then
                        local tip = string.format('Average tick: %.3f ms\nLast tick: %.3f ms\nInterval: %.2fs\nRuns in combat: %s',
                            avg, p.lastExecMs or 0, p.tickInterval or 0.1, p.runOutOfCombatOnly and 'No (sleeps)' or 'Yes')
                        -- Per-phase breakdown when the plugin keeps one (map, chat).
                        local prof = p.instance and p.instance.profile
                        if type(prof) == 'table' then
                            local keys = {}
                            for k in pairs(prof) do keys[#keys + 1] = k end
                            table.sort(keys)
                            for _, k in ipairs(keys) do
                                local v = prof[k]
                                if type(v) == 'number' then
                                    tip = tip .. string.format('\n  %s: %s', k, (v == math.floor(v)) and tostring(v) or string.format('%.2f', v))
                                end
                            end
                        end
                        ImGui.SetTooltip('%s', tip)
                    end
                else
                    ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], '—')
                end

                -- Col 7: Description (one line, clipped; full text on hover)
                ImGui.TableNextColumn()
                ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], p.description or '')
                if ImGui.IsItemHovered() and p.description and p.description ~= '' then
                    ImGui.SetTooltip('%s', p.description)
                end

                -- Col 8: Actions
                ImGui.TableNextColumn()
                if p.instance and p.instance.onDrawSettings then
                    if ImGui.SmallButton(string.format('Config##cfg_%d', idx)) then
                        pm.activeConfigPluginId = id
                        pm.openConfigRequested = true
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('%s', 'Open this plugin\'s settings.')
                    end
                    ImGui.SameLine()
                end
                if w then
                    local wOpen = pm.isWindowOpen(id)
                    if ImGui.SmallButton(string.format(wOpen and 'Hide##win_%d' or 'Show##win_%d', idx)) then
                        pm.toggleWindow(id)
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('%s', wOpen and 'Close this plugin\'s window.' or 'Open this plugin\'s window now.')
                    end
                    ImGui.SameLine()
                end
                if ImGui.SmallButton(string.format('Reload##rel_%d', idx)) then
                    pm.defer('reload ' .. id, function() pm.reloadPlugin(id) end)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', 'Restart this plugin (onDestroy -> onInit).')
                end
            end
        end

        ImGui.EndTable()
    end
    end, debug.traceback)
    ImGui.PopStyleVar(2) -- always balanced, even if the body errored
    if not okBody then error(stop, 0) end -- shown by UI.guardedDraw
    if stop then return end

    -- Plugin Configuration Modal Popup Dialog
    if pm.openConfigRequested then
        pm.openConfigRequested = false
        ImGui.OpenPopup('Plugin Configuration##PluginConfigModal')
    end

    if pm.activeConfigPluginId and pm.plugins[pm.activeConfigPluginId] then
        local p = pm.plugins[pm.activeConfigPluginId]
        ImGui.SetNextWindowSize(UI.px(540), UI.px(420), ImGuiCond.FirstUseEver)
        local openModal, showModal = ImGui.BeginPopupModal('Plugin Configuration##PluginConfigModal', true, ImGuiWindowFlags.AlwaysAutoResize)
        if showModal then
            UI.applyWindowScale('main')
            accent(GOLD, string.format('%s (v%s)', p.name or p.id, p.version or '1.0'))
            ImGui.SameLine()
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], string.format('by %s', p.author or 'Unknown'))
            if p.description and p.description ~= '' then
                ImGui.TextWrapped(p.description)
            end
            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()

            -- Quick Toggles inside Modal
            local isEn = (p.enabled == true)
            if p.pendingEnabled ~= nil then isEn = p.pendingEnabled end
            local newEn = ImGui.Checkbox('Enabled##modalEn', isEn)
            if newEn ~= isEn then
                local modalId = pm.activeConfigPluginId
                p.pendingEnabled = newEn
                pm.defer((newEn and 'enable ' or 'disable ') .. modalId, function()
                    if newEn then pm.enablePlugin(modalId) else pm.disablePlugin(modalId) end
                    p.pendingEnabled = nil
                    local cur = pm.plugins[modalId]  -- record may have been replaced meanwhile
                    if cur then cur.pendingEnabled = nil end
                    runtime.saveLoadout(true)
                end)
            end
            ImGui.SameLine()
            local runInCombat = not p.runOutOfCombatOnly
            local newCombat = ImGui.Checkbox('Run During Combat##modalCombat', runInCombat)
            if newCombat ~= runInCombat then
                p.runOutOfCombatOnly = not newCombat
                if not D.ctrl().plugins then D.ctrl().plugins = {} end
                if not D.ctrl().plugins[pm.activeConfigPluginId] then D.ctrl().plugins[pm.activeConfigPluginId] = {} end
                D.ctrl().plugins[pm.activeConfigPluginId].runInCombat = newCombat
                runtime.saveLoadout(true)
            end
            if pm.getWindow(pm.activeConfigPluginId) then
                ImGui.SameLine()
                local hdrOn = pm.headerButtonEnabled(pm.activeConfigPluginId)
                local newHdr = ImGui.Checkbox('Pin to sidebar##modalHdr', hdrOn)
                if newHdr ~= hdrOn then
                    pm.setHeaderButton(pm.activeConfigPluginId, newHdr)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', 'List this window in the main window sidebar for one-click open / close.')
                end
            end
            ImGui.SameLine()
            if ImGui.SmallButton('Reload Plugin##modalReload') then
                local modalId = pm.activeConfigPluginId
                pm.defer('reload ' .. modalId, function() pm.reloadPlugin(modalId) end)
            end

            -- One "Show" box per window the plugin declares (replaces the
            -- per-plugin "Window: Visible (Click to Hide)" buttons).
            if p.enabled and p.status ~= 'Error' then
                local shown = 0
                for _, e in ipairs(pm.windowPlugins(false)) do
                    if e.pluginId == pm.activeConfigPluginId then
                        if shown > 0 then ImGui.SameLine() end
                        local on = pm.isWindowOpen(e.id)
                        if ImGui.Checkbox(string.format('Show %s##modalWin_%s', tostring(e.window.label or e.id), e.id), on) ~= on then
                            pm.setWindowOpen(e.id, not on)
                        end
                        if ImGui.IsItemHovered() and e.window.desc then UI.setTooltip('%s', tostring(e.window.desc)) end
                        shown = shown + 1
                    end
                end
            end

            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()

            -- Custom Settings Panel inside child frame for smooth scrolling if large
            if p.instance and p.instance.onDrawSettings then
                if ImGui.BeginChild('plgModalSettingsChild', UI.px(600), UI.px(380), true) then
                    pm.drawPluginSettings(pm.activeConfigPluginId)
                end
                ImGui.EndChild()
            else
                ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'This plugin does not require any additional configuration.')
            end

            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()

            local closeClicked = ImGui.Button('Close##modalClose', UI.px(100), UI.px(24))
            if closeClicked or not openModal then
                ImGui.CloseCurrentPopup()
                pm.activeConfigPluginId = nil
            end

            ImGui.EndPopup()
        elseif not openModal then
            pm.activeConfigPluginId = nil
        end
    end
end
end

return M
