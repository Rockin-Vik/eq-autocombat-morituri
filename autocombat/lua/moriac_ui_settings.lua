-- moriac_ui_settings.lua: extracted verbatim from moriac.lua (behaviour-preserving split).
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
    local castTracker = D.castTracker
    local hasActivePet = D.hasActivePet
    local mq = D.mq
    local navLoaded = D.navLoaded
    local navMeshLoaded = D.navMeshLoaded
    local pushButtonColors = D.pushButtonColors
    local stickLoaded = D.stickLoaded
    local tlog = D.tlog
function UI.drawWindowSettings()
    accent(GOLD, 'Window Layout & Position Persistence')
    ImGui.TextDisabled('Save and restore exact screen coordinates and dimensions for all MoriAC popout windows.\nPrevents window scrambling caused by monitor power-off, display sleep, or resolution changes.')
    ImGui.Separator()

    -- Primary Action Toolbar
    local pushedColors = 0

    pushedColors = pushedColors + pushButtonColors({
        { 'Button', 0.16, 0.50, 0.22 }, { 'ButtonHovered', 0.20, 0.62, 0.28 }, { 'ButtonActive', 0.12, 0.40, 0.18 },
    })
    if ImGui.Button('Save Current Positions##winSaveAll', UI.px(180), UI.px(26)) then
        runtime.saveWindowPositions(false)
    end
    if pushedColors > 0 then
        pcall(ImGui.PopStyleColor, pushedColors)
        pushedColors = 0
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Snapshots the current screen coordinates (X, Y) and sizes (W, H)\nof all open MoriAC windows and saves them to your character loadout.')
    end

    ImGui.SameLine()
    pushedColors = pushedColors + pushButtonColors({
        { 'Button', 0.18, 0.38, 0.62 }, { 'ButtonHovered', 0.22, 0.48, 0.78 }, { 'ButtonActive', 0.14, 0.30, 0.50 },
    })
    if ImGui.Button('Restore Saved Positions##winRestoreAll', UI.px(180), UI.px(26)) then
        local cnt = runtime.triggerRestoreWindows()
        print(string.format('\ag[MoriAC]\ax Restored positions for \ay%d\ax window(s).', cnt))
    end
    if pushedColors > 0 then
        pcall(ImGui.PopStyleColor, pushedColors)
        pushedColors = 0  -- luacheck: ignore 311
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Restores all windows to their previously saved screen coordinates and dimensions.')
    end

    ImGui.SameLine()
    if ImGui.Button('Reset to Defaults##winResetAll', UI.px(150), UI.px(26)) then
        runtime.resetWindowPositionsToDefault()
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Re-positions all windows to clean, sensible defaults on your current display.')
    end

    -- Options and metadata
    ImGui.Spacing()
    local autoResVal = ImGui.Checkbox('Auto-Restore on Display Resolution / Monitor Change', D.ctrl().winpos_auto_restore_on_resize ~= false)
    if autoResVal ~= (D.ctrl().winpos_auto_restore_on_resize ~= false) then
        D.ctrl().winpos_auto_restore_on_resize = autoResVal
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'Automatically detects when your monitor wakes up or resolution restores\nand snaps all windows back to their saved positions immediately.')
    end

    ImGui.SameLine()
    local visVal = ImGui.Checkbox('Include Open/Closed Visibility on Restore', D.ctrl().winpos_restore_visibility or false)
    if visVal ~= (D.ctrl().winpos_restore_visibility or false) then
        D.ctrl().winpos_restore_visibility = visVal
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('%s', 'When restoring, also opens or closes windows to match their state when saved.')
    end

    -- Status line
    local savedTimeStr = 'Never'
    if D.ctrl().saved_window_positions_at and D.ctrl().saved_window_positions_at > 0 then
        savedTimeStr = tostring(os.date('%Y-%m-%d %H:%M:%S', D.ctrl().saved_window_positions_at))
    end
    local dispW = runtime.lastDisplayWidth or 0
    local dispH = runtime.lastDisplayHeight or 0
    if dispW == 0 then
        pcall(function()
            local io = ImGui.GetIO()
            if io and io.DisplaySize then dispW = math.floor(io.DisplaySize.x); dispH = math.floor(io.DisplaySize.y) end
        end)
    end
    ImGui.TextDisabled(string.format('Display: %dx%d  |  Last Saved: %s  |  Tracked Windows: %d',
        dispW, dispH, savedTimeStr, #runtime.getManagedWindows()))

    ImGui.Spacing()
    -- UI scale: global factor + per-window override column below
    accent(GOLD, 'UI Scale')
    ImGui.SameLine()
    ImGui.SetNextItemWidth(UI.px(200))
    local curScale = UI.clampScale(D.ctrl().ui_scale) or 1.0
    local newScale = ImGui.SliderFloat('##uiScale', curScale, UI.SCALE_MIN, UI.SCALE_MAX, '%.2fx')
    if ImGui.IsItemHovered() then
        UI.setTooltip('Size of every MoriAC window (text, buttons, bars) - for high-resolution or small screens.\nA window can override it in the Scale column below or in its right-click menu.\nFonts are stretched, not re-rendered; for crisp text at large sizes raise MQ\'s overlay font size too.\nAlso: /ac scale <0.75-2.0> | /ac scale reset')
    end
    if newScale ~= curScale then UI.setUiScale(newScale) end
    ImGui.SameLine()
    for _, p in ipairs({ 1.0, 1.25, 1.5 }) do
        if ImGui.SmallButton(string.format('%.2fx##uiScalePreset', p)) then UI.setUiScale(p) end
        ImGui.SameLine()
    end
    ImGui.NewLine()
    ImGui.Separator()

    accent(GOLD, 'MoriAC Popout Windows:')

    -- Managed Windows Table. The columns are fixed-width and together are
    -- wider than the default main window; a table sized to the available
    -- width would silently clip the rightmost columns, so give it its full
    -- width instead and let the main window's horizontal scrollbar reach
    -- the rest.
    local tblFlags = bit.bor(
        (ImGuiTableFlags and ImGuiTableFlags.Borders) or 0,
        (ImGuiTableFlags and ImGuiTableFlags.RowBg) or 0,
        (ImGuiTableFlags and ImGuiTableFlags.SizingFixedFit) or 0
    )
    local colFixed = (ImGuiTableColumnFlags and ImGuiTableColumnFlags.WidthFixed) or 0
    local cols = {
        { 'Window', 180 }, { 'Status', 95 }, { 'Live Pos (X, Y) [W x H]', 150 }, { 'Saved Pos (X, Y) [W x H]', 150 },
        { 'Locked', 50 }, { 'Scale', 120 }, { 'Actions', 175 },
    }
    -- Column widths + cell padding / borders (~10px per column).
    local tblWidth = UI.px(10 * #cols)
    for _, c in ipairs(cols) do tblWidth = tblWidth + UI.px(c[2]) end
    if ImGui.BeginTable('ManagedWinTable', #cols, tblFlags, tblWidth, 0) then
        for _, c in ipairs(cols) do ImGui.TableSetupColumn(c[1], colFixed, UI.px(c[2])) end
        ImGui.TableHeadersRow()

        for _, def in ipairs(runtime.getManagedWindows()) do
            ImGui.TableNextRow()
            local isOpen = def.getOpen and def.getOpen() or false
            local live = runtime.liveWindowPositions and runtime.liveWindowPositions[def.key]
            local saved = D.ctrl().saved_window_positions and D.ctrl().saved_window_positions[def.key]

            -- Col 1: Window Name & short tag
            ImGui.TableNextColumn()
            ImGui.TextColored(GOLD[1], GOLD[2], GOLD[3], GOLD[4], def.short)
            ImGui.SameLine()
            ImGui.TextDisabled('(' .. def.key .. ')')
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('%s\n%s', def.name, def.desc or '')
            end

            -- Col 2: Status
            ImGui.TableNextColumn()
            if isOpen then
                ImGui.TextColored(GOOD[1], GOOD[2], GOOD[3], GOOD[4], 'OPEN')
            else
                ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'CLOSED')
            end
            ImGui.SameLine()
            if ImGui.SmallButton((isOpen and 'Hide##' or 'Show##') .. def.key) then
                if def.setOpen then def.setOpen(not isOpen) end
            end

            -- Col 3: Live Pos & Size
            ImGui.TableNextColumn()
            if live and live.x and live.y then
                ImGui.Text(string.format('%d, %d [%dx%d]', live.x, live.y, live.w or 0, live.h or 0))
            else
                ImGui.TextDisabled(isOpen and 'Tracking...' or '--')
            end

            -- Col 4: Saved Pos & Size
            ImGui.TableNextColumn()
            if saved and saved.x and saved.y then
                ImGui.TextColored(ARC[1], ARC[2], ARC[3], ARC[4], string.format('%d, %d [%dx%d]', saved.x, saved.y, saved.w or 0, saved.h or 0))
            else
                ImGui.TextDisabled('None')
            end

            -- Col 5: Locked toggle
            ImGui.TableNextColumn()
            if def.canLock and def.getLock and def.setLock then
                local isLocked = def.getLock()
                local newLock = ImGui.Checkbox('##lock' .. def.key, isLocked)
                if newLock ~= isLocked then
                    def.setLock(newLock)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', isLocked and 'Window is locked (cannot be dragged or resized)' or 'Window is unlocked')
                end
            else
                ImGui.TextDisabled('--')
            end

            -- Col 6: Scale (per-window override of ctrl.ui_scale)
            ImGui.TableNextColumn()
            UI.drawWindowScaleControl(def.key, '', 110)

            -- Col 7: Actions
            ImGui.TableNextColumn()
            if ImGui.SmallButton('Center##' .. def.key) then
                runtime.centerWindow(def.key)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Center "%s" on your current display.', def.name)
            end
            ImGui.SameLine()
            if ImGui.SmallButton('Restore##' .. def.key) then
                runtime.restoreSingleWindow(def.key)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Restore "%s" to its saved coordinates.', def.name)
            end
            ImGui.SameLine()
            if ImGui.SmallButton('Save##' .. def.key) then
                runtime.saveSingleWindow(def.key)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Save current position for "%s".', def.name)
            end
        end

        ImGui.EndTable()
    end

    -- Plugin window quick launchers. Built from the plugin manager's window
    -- declarations (every enabled plugin with a window, header button or
    -- not), so a new plugin shows up here without editing the core and a
    -- removed one disappears instead of leaving a dead button.
    ImGui.Spacing()
    if ImGui.CollapsingHeader('External MoriAC Tools & Windows', ImGuiTreeNodeFlags.None) then
        ImGui.TextDisabled('Toggle the MoriAC companion tool windows (plugins in lua/tac):')
        ImGui.Spacing()
        local pm = runtime.pluginManager
        local entries = pm and pm.windowPlugins(false) or {}
        local Col = ImGuiCol or _G.ImGuiCol or (mq.imgui and mq.imgui.Col)
        if not pm or #entries == 0 then
            ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'No plugin windows are loaded.')
        end
        if pm then
            for i, e in ipairs(entries) do
                if (i - 1) % 4 ~= 0 then ImGui.SameLine() end
                local label = tostring(e.window.label or e.id)
                local isOpen = pm.isWindowOpen(e.id)
                local pushed = 0
                if isOpen and Col and pcall(ImGui.PushStyleColor, Col.Button, 0.12, 0.45, 0.65, 1.0) then pushed = 1 end
                if ImGui.Button(label .. '##extWin_' .. e.id) then
                    pm.toggleWindow(e.id)
                end
                if pushed > 0 then pcall(ImGui.PopStyleColor, pushed) end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', tostring(e.window.tooltip or ('Toggles the ' .. label .. ' window (' .. e.id .. ' plugin).')))
                end
            end
        end
    end
end

-- Med Break: the start threshold must stay below the stop threshold, or the
-- break ends the moment it begins (or never starts). The slider just moved
-- wins; the other one is pushed out of its way.
function UI.clampMedBreak(kind, startMoved)
    local sk, ek = 'medbreak_' .. kind .. '_start', 'medbreak_' .. kind .. '_stop'
    local st, sp = tonumber(D.ctrl()[sk]) or 20, tonumber(D.ctrl()[ek]) or 90
    if st < sp then return end
    if startMoved then
        if st >= 100 then st = 99 end
        sp = st + 1
    else
        if sp <= 0 then sp = 1 end
        st = sp - 1
    end
    D.ctrl()[sk], D.ctrl()[ek] = st, sp
end

function UI.drawSettingsTab()
    ImGui.SetNextItemWidth(UI.px(260))
    local q = ImGui.InputTextWithHint('##settingsFind', 'Find a setting...', runtime.settingsQuery or '')
    if type(q) == 'string' then runtime.settingsQuery = q end
    if runtime.settingsQuery ~= '' then
        ImGui.SameLine()
        if ImGui.SmallButton('Clear##settingsFindClear') then runtime.settingsQuery = '' end
    end
    runtime.settingsMatches = 0
    ImGui.Spacing()

    -- 1. Character Classes & Profile
    UI.drawClassPicker()

    -- 2. Combat Style & Positioning
    if UI.settingsSection('setStyle', 'Combat style & positioning', 'melee ranged bow spell distance line of sight los retries lockout resist fail', true) then
        accent(GOLD, 'Engagement Style:')
        if ImGui.RadioButton('Melee', D.ctrl().combat_style == 'Melee') then
            runtime.setCombatStyle('Melee')
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Melee: close to melee range and swing with /attack on.')
        end
        ImGui.SameLine()
        if ImGui.RadioButton('Ranged (bow)', D.ctrl().combat_style == 'Ranged') then
            runtime.setCombatStyle('Ranged')
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Ranged: stand off at the range below and fire a bow/thrown weapon\n'
                .. 'using this server\'s "#attackmode ranged" toggle + /attack on.\n'
                .. 'Requires a ranged weapon and ammo equipped.')
        end
        ImGui.SameLine()
        if ImGui.RadioButton('Spell', D.ctrl().combat_style == 'Spell') then
            runtime.setCombatStyle('Spell')
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Spell: stand off at the range below and never auto-attack (no\n'
                .. '/attack, no /autofire) -- your Spell Gems loadout does all the\n'
                .. 'damage. For pure caster trios that don\'t melee or carry a bow.')
        end

        if D.ctrl().combat_style == 'Melee' then
            UI.formLabel('Melee distance')
            local newDist, changed = ImGui.SliderInt('##meleeRangeSlider', D.ctrl().melee_dist or 14, 5, 50)
            if changed or (newDist and newDist ~= D.ctrl().melee_dist) then
                D.ctrl().melee_dist = newDist
                runtime.saveLoadout(true)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Max melee distance to position at and strike targets (default: 14).\n'
                    .. 'Adjust to stick tighter (e.g. 8-10) or fight from further away (e.g. 15-25).')
            end
        else
            UI.formLabel('Ranged / spell distance')
            local newDist, changed = ImGui.SliderInt('##rangedRangeSlider', D.ctrl().ranged_dist or 40, 5, 200)
            if changed or (newDist and newDist ~= D.ctrl().ranged_dist) then
                D.ctrl().ranged_dist = newDist
                runtime.saveLoadout(true)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Distance to position at and engage targets from with ranged/spells (default: 40).\n'
                    .. 'Keep this within your bow / spell range or you will stand around doing nothing.')
            end
        end

        local losVal = ImGui.Checkbox('Re-face Instead Of Stepping Back On Lost Line-of-Sight', D.ctrl().los_face_only or false)
        if losVal ~= (D.ctrl().los_face_only or false) then
            D.ctrl().los_face_only = losVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'On "cannot see target", just turn to face it instead of stepping\n'
                .. 'back and strafing. Useful in tight spaces or areas cluttered\n'
                .. 'with obstacles, where stepping back can wedge you against a\n'
                .. 'wall/prop instead of helping. Applies to Melee, Ranged, and\n'
                .. 'Spell alike. Off by default.')
        end

        local enrVal = ImGui.Checkbox('Stop Attacking While The Target Is Enraged##enrageStop', D.ctrl().enrage_stop ~= false)
        if enrVal ~= (D.ctrl().enrage_stop ~= false) then
            D.ctrl().enrage_stop = enrVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('%s',
                'An enraged mob ripostes every melee swing from its front.\n'
                .. 'On: melee auto-attack goes off and pets are backed off until\n'
                .. '"<mob> is no longer enraged." (or the mob dies), then both resume.\n'
                .. 'Spells, bow auto-fire and other actions keep going. On by default.')
        end

        local kdVal = ImGui.Checkbox('Stand Up When Knocked Down##standKnockdown', D.ctrl().stand_knockdown ~= false)
        if kdVal ~= (D.ctrl().stand_knockdown ~= false) then
            D.ctrl().stand_knockdown = kdVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('%s',
                'Some mobs (Plane of Time) knock you to the ground: "<you> has fallen\n'
                .. 'to the ground." On: while a mob is on XTarget, MoriAC sends /stand.\n'
                .. 'Its own Feign Death casts are left alone. Turn this off if you feign\n'
                .. 'death by hand mid-fight. On by default.')
        end

        accent(GOLD, 'Spell Failures & Lockouts:')
        UI.formLabel('Retries before lockout')
        local retriesVal = ImGui.SliderInt('##cmr', D.ctrl().cast_max_retries or 2, 1, 10)
        if retriesVal ~= D.ctrl().cast_max_retries then
            D.ctrl().cast_max_retries = retriesVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Consecutive failed debuff/ability attempts before temporarily backing off on that target.\nDefault: 2 tries.')
        end
        ImGui.SameLine()
        UI.formLabel('Lockout time')
        local lockoutVal = ImGui.SliderInt('##castLockoutSec', D.ctrl().cast_lockout_sec or 30, 5, 300, '%d s')
        if lockoutVal ~= D.ctrl().cast_lockout_sec then
            D.ctrl().cast_lockout_sec = lockoutVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Seconds to back off before retrying a resisted debuff or locked spell.\nDefault: 30 seconds.')
        end
        ImGui.SameLine()
        local activeLocks = castTracker and castTracker.getActiveCount and castTracker.getActiveCount() or 0
        local clearLabel = (activeLocks > 0) and string.format('Clear Lockouts (%d)##clearLocksBtn', activeLocks) or 'Clear Lockouts##clearLocksBtn'
        if ImGui.Button(clearLabel) then
            if castTracker and castTracker.clear then
                castTracker.clear()
                print('\ag[MoriAC]\ax Cleared all active spell lockouts, target backoffs, and mob immunities.')
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Instantly clear all active spell lockouts, non-stacking buff backoffs, and mob immunities.')
        end
    end


    -- 3. Navigation & Hazard Avoidance
    if UI.settingsSection('setNav', 'Navigation', 'mq2nav mesh moveutils hazard stuck door gate levitation stick isolation path breadcrumbs', false) then
        if not navLoaded() then
            accent(WARN, 'MQ2Nav is NOT loaded! Navigation and pathfinding require MQ2Nav.')
            ImGui.SameLine()
            if ImGui.Button('Load MQ2Nav##settingsLoadNav') then
                mq.cmd('/plugin mq2nav'); if runtime.invalidatePluginProbes then runtime.invalidatePluginProbes() end
            end
            if ImGui.IsItemHovered() then
                UI.setTooltip('Executes /plugin mq2nav to load the MQ2Nav plugin.')
            end
        elseif not navMeshLoaded() then
            local curZone = mq.TLO.Zone.ShortName() or 'current zone'
            accent(WARN, string.format('No NavMesh loaded for zone "%s" (/nav reload).', curZone))
            ImGui.SameLine()
            if ImGui.Button('Reload Mesh##settingsReloadMesh') then
                mq.cmd('/nav reload'); if runtime.invalidatePluginProbes then runtime.invalidatePluginProbes() end
            end
            if ImGui.IsItemHovered() then
                UI.setTooltip('Executes /nav reload to attempt reloading the zone navmesh.')
            end
        end
        if not stickLoaded() then
            accent(WARN, 'MQ2MoveUtils is NOT loaded! Combat positioning and stick require MQ2MoveUtils.')
            ImGui.SameLine()
            if ImGui.Button('Load MQ2MoveUtils##settingsLoadMoveUtils') then
                mq.cmd('/plugin mq2moveutils'); if runtime.invalidatePluginProbes then runtime.invalidatePluginProbes() end
            end
            if ImGui.IsItemHovered() then
                UI.setTooltip('Executes /plugin mq2moveutils to load the MQ2MoveUtils plugin.')
            end
        end

        local hazVal = ImGui.Checkbox('Auto-Avoid Stuck Hotspots', D.ctrl().nav_hazard_avoidance ~= false)
        if hazVal ~= (D.ctrl().nav_hazard_avoidance ~= false) then
            D.ctrl().nav_hazard_avoidance = hazVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Remembers locations where the character repeatedly gets stuck and routes around them with detour waypoints.')
        end
        ImGui.SameLine()
        local rbcVal = ImGui.Checkbox('Reverse Breadcrumbs on Pull Return', D.ctrl().nav_reverse_breadcrumbs ~= false)
        if rbcVal ~= (D.ctrl().nav_reverse_breadcrumbs ~= false) then
            D.ctrl().nav_reverse_breadcrumbs = rbcVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('In Puller Camp mode, remembers the exact path taken to the mob and walks back in reverse to guarantee a safe return to camp.')
        end

        local doorVal = ImGui.Checkbox('Proactive Door & Gate Opening', D.ctrl().nav_proactive_doors ~= false)
        if doorVal ~= (D.ctrl().nav_proactive_doors ~= false) then
            D.ctrl().nav_proactive_doors = doorVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Predictively opens closed doors in your movement path before hitting them.')
        end
        ImGui.SameLine()
        local levVal = ImGui.Checkbox('Levitation Archway Duck-to-Clear', D.ctrl().nav_levitation_clear ~= false)
        if levVal ~= (D.ctrl().nav_levitation_clear ~= false) then
            D.ctrl().nav_levitation_clear = levVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Momentarily ducks under low door frames/archways if levitating to prevent ceiling snags.')
        end

        local stickVal = ImGui.Checkbox('Fallback to Stick on Nav Failure', D.ctrl().nav_fallback_stick or false)
        if stickVal ~= (D.ctrl().nav_fallback_stick or false) then
            D.ctrl().nav_fallback_stick = stickVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Off-mesh holes already stick toward the target and remap\n'
                .. 'nav once a path exists. This checkbox keeps /stick going\n'
                .. 'even after that recovery gives up -- which walks straight\n'
                .. 'at whatever wall is blocking the path.\n'
                .. 'Off by default: unreachable targets are dropped instead.')
        end

        local isoVal = ImGui.Checkbox('Mesh Isolation Recovery', D.ctrl().nav_mesh_isolation ~= false)
        if isoVal ~= (D.ctrl().nav_mesh_isolation ~= false) then
            D.ctrl().nav_mesh_isolation = isoVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'When every nearby NPC reports "no path" but ground we stood on\n'
                .. 'moments ago (or the camp) is unreachable too, the character is\n'
                .. 'on an unlinked navmesh island, not surrounded by unreachable\n'
                .. 'mobs. Walks straight back to the last good ground, then at the\n'
                .. 'nearest NPC, then tries the unstick maneuvers, re-checking the\n'
                .. 'mesh after each; logs the hole as an active hazard hotspot.\n'
                .. 'Also lets Hunter/Puller approach a close, visible NPC directly\n'
                .. 'when only its own spot is unmeshed.')
        end

        UI.formLabel('Max path detour')
        local newRatio = ImGui.SliderFloat('##navMaxPathRatio', D.ctrl().nav_max_path_ratio or 2.5, 1.2, 5.0, '%.1fx')
        if newRatio and newRatio ~= D.ctrl().nav_max_path_ratio then
            D.ctrl().nav_max_path_ratio = newRatio
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Rejects targets if NavMesh PathLength exceeds this multiple of direct 3D distance.\nFilters out mobs across walls or on high balconies requiring long dungeon detours.')
        end

        ImGui.SameLine()
        UI.formLabel('Hazard radius')
        local newHzRad = ImGui.SliderInt('##navHazardRadius', D.ctrl().nav_hazard_radius or 15, 8, 35, '%d units')
        if newHzRad and newHzRad ~= D.ctrl().nav_hazard_radius then
            D.ctrl().nav_hazard_radius = newHzRad
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Avoidance radius around learned stuck hotspots.')
        end
        ImGui.SameLine()
        UI.formLabel('Forget hazards after')
        local newDecayMin = ImGui.SliderInt('##navHazardForget', D.ctrl().nav_hazard_decay_minutes or 10, 1, 60, '%d min')
        if newDecayMin and newDecayMin ~= D.ctrl().nav_hazard_decay_minutes then
            D.ctrl().nav_hazard_decay_minutes = newDecayMin
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Every N minutes without a fresh stuck event, a hotspot loses one hit and eventually deactivates below the active threshold.')
        end

        local curZs = runtime.getCurrentZoneShortName and runtime.getCurrentZoneShortName() or 'unknown'
        local zoneHz = runtime.getZoneHazards and runtime.getZoneHazards(curZs) or {}
        local activeCount = 0
        for _, h in ipairs(zoneHz) do
            if (h.hits or 1) >= (D.ctrl().nav_hazard_min_hits or 2) then
                activeCount = activeCount + 1
            end
        end
        ImGui.TextDisabled(string.format('Zone "%s": %d hazard hotspot(s) logged (%d active)', curZs, #zoneHz, activeCount))
        ImGui.SameLine()
        if ImGui.Button('Clear Zone Hazards##clearHzBtn') then
            if runtime.clearZoneHazards then runtime.clearZoneHazards(curZs) end
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Clears all recorded stuck hotspots for the current zone.')
        end
    end


    -- 4. Closer-NPC Retargeting During Movement
    if UI.settingsSection('setRetarget', 'Retargeting while moving', 'closer mobs cone line of sight retarget box network pulls', false) then
        local chkVal = ImGui.Checkbox('Switch to Closer Mobs While Traveling', D.ctrl().check_closer_mobs ~= false)
        if chkVal ~= (D.ctrl().check_closer_mobs ~= false) then
            D.ctrl().check_closer_mobs = chkVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Allows switching to a significantly closer mob if one is encountered while traveling toward a distant target.')
        end
        ImGui.SameLine()
        local coneVal = ImGui.Checkbox('Forward Arc Cone Only (+/-75 deg)', D.ctrl().closer_forward_cone_only ~= false)
        if coneVal ~= (D.ctrl().closer_forward_cone_only ~= false) then
            D.ctrl().closer_forward_cone_only = coneVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Only retargets to closer mobs that lie in front of your movement direction, preventing 180 degree turnarounds.')
        end

        local losPrioVal = ImGui.Checkbox('Prioritize Visible Line-of-Sight Mobs', D.ctrl().closer_los_priority ~= false)
        if losPrioVal ~= (D.ctrl().closer_los_priority ~= false) then
            D.ctrl().closer_los_priority = losPrioVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Prioritizes closer mobs with direct Line of Sight if your distant target is obstructed behind walls/corners.')
        end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(UI.px(180))
        local curRetargets = D.ctrl().max_closer_retargets or 1
        local retargetFmt = (curRetargets == 0) and 'Disabled (0)' or '%d retarget(s)'
        UI.formLabel('Retargets per trip')
        local newMaxRetargets = ImGui.SliderInt('##maxCloserRetargets', curRetargets, 0, 5, retargetFmt)
        if newMaxRetargets and newMaxRetargets ~= D.ctrl().max_closer_retargets then
            D.ctrl().max_closer_retargets = newMaxRetargets
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Max times to switch to closer mobs during a single travel leg (0 = disabled / lock to first mob).')
        end

        ImGui.Spacing()
        local coordVal = ImGui.Checkbox('Stay Off Other Boxes\' Pulls (Box Network)', D.ctrl().box_pull_coordination ~= false)
        if coordVal ~= (D.ctrl().box_pull_coordination ~= false) then
            D.ctrl().box_pull_coordination = coordVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Puller (Camp / Hunt) skips mobs your other boxes are heading for or fighting, using the Box Network\n'
                .. 'heartbeat (boxnet plugin). When two pullers grab the same mob at once, the later one lets go.\n'
                .. 'Assist boxes are not affected. Only boxes in the same zone count.')
        end
    end


    -- 5. Resting & Resource Management
    if UI.settingsSection('setRest', 'Resting & med breaks', 'mana hp endurance med break rest sit pull minimum', false) then
        accent(GOLD, 'Combat Recovery & Pull Thresholds:')
        UI.formLabel('Min mana (non-heals)')
        local minManaVal = ImGui.SliderInt('##mmp', D.ctrl().min_mana_pct or 0, 0, 95, '%d%%')
        if minManaVal ~= D.ctrl().min_mana_pct then
            D.ctrl().min_mana_pct = minManaVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Prevents automatic spell casting if current mana drops below this percentage.\n'
                .. 'Ignored during Burn Mode (0 = disabled / cast at any mana level).')
        end
        ImGui.SameLine()
        UI.formLabel('Rest below HP')
        local minPullHpVal = ImGui.SliderInt('##minPullHpSettings', D.ctrl().pull_min_hp_pct or 0, 0, 95, '%d%%')
        if minPullHpVal ~= D.ctrl().pull_min_hp_pct then
            D.ctrl().pull_min_hp_pct = minPullHpVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('%s',
                'Pauses pulling and sits out of combat to recover if current HP drops below\n'
                .. 'this threshold. Pulling resumes once HP reaches 100%.\n'
                .. 'Automatically stands to fight if attacked (0 = disabled / pull at any HP).')
        end

        accent(GOLD, 'Med Break Recovery System:')
        local mbVal = ImGui.Checkbox('Enable Med Break', D.ctrl().medbreak_enabled or false)
        if mbVal ~= (D.ctrl().medbreak_enabled or false) then
            D.ctrl().medbreak_enabled = mbVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Stops everything and sits to recover once any enabled\n'
                .. 'resource below drops to its "at" threshold; resumes once ALL enabled\n'
                .. 'resources have recovered up to their "until" threshold.')
        end
        if D.ctrl().medbreak_enabled then
            local mbIgnoreGroup = ImGui.Checkbox('Ignore Group Combat While Medding##mbignoregroup', D.ctrl().medbreak_ignore_group_combat or false)
            if mbIgnoreGroup ~= (D.ctrl().medbreak_ignore_group_combat or false) then
                D.ctrl().medbreak_ignore_group_combat = mbIgnoreGroup
                runtime.saveLoadout(true)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Allows Med Break to continue while other group members are fighting.\n'
                    .. 'Med Break still cancels if this character enters combat, gains aggro,\n'
                    .. 'or a hostile XTarget is fighting this character or one of its pets.')
            end

            local mbHp = ImGui.Checkbox('HP##mbhp', D.ctrl().medbreak_hp_on or false)
            if mbHp ~= (D.ctrl().medbreak_hp_on or false) then
                D.ctrl().medbreak_hp_on = mbHp
                runtime.saveLoadout(true)
            end
            ImGui.SameLine(); ImGui.TextDisabled('at'); ImGui.SameLine(); ImGui.SetNextItemWidth(UI.px(120))
            local mbHpStart = ImGui.SliderInt('##mbhpstart', D.ctrl().medbreak_hp_start or 20, 0, 100, '%d%%')
            if mbHpStart ~= D.ctrl().medbreak_hp_start then
                D.ctrl().medbreak_hp_start = mbHpStart
                UI.clampMedBreak('hp', true)
                runtime.saveLoadout(true)
            end
            ImGui.SameLine(); ImGui.TextDisabled('until'); ImGui.SameLine(); ImGui.SetNextItemWidth(UI.px(120))
            local mbHpStop = ImGui.SliderInt('##mbhpstop', D.ctrl().medbreak_hp_stop or 90, 0, 100, '%d%%')
            if mbHpStop ~= D.ctrl().medbreak_hp_stop then
                D.ctrl().medbreak_hp_stop = mbHpStop
                UI.clampMedBreak('hp', false)
                runtime.saveLoadout(true)
            end

            local mbMana = ImGui.Checkbox('Mana##mbmana', D.ctrl().medbreak_mana_on or false)
            if mbMana ~= (D.ctrl().medbreak_mana_on or false) then
                D.ctrl().medbreak_mana_on = mbMana
                runtime.saveLoadout(true)
            end
            ImGui.SameLine(); ImGui.TextDisabled('at'); ImGui.SameLine(); ImGui.SetNextItemWidth(UI.px(120))
            local mbManaStart = ImGui.SliderInt('##mbmanastart', D.ctrl().medbreak_mana_start or 20, 0, 100, '%d%%')
            if mbManaStart ~= D.ctrl().medbreak_mana_start then
                D.ctrl().medbreak_mana_start = mbManaStart
                UI.clampMedBreak('mana', true)
                runtime.saveLoadout(true)
            end
            ImGui.SameLine(); ImGui.TextDisabled('until'); ImGui.SameLine(); ImGui.SetNextItemWidth(UI.px(120))
            local mbManaStop = ImGui.SliderInt('##mbmanastop', D.ctrl().medbreak_mana_stop or 90, 0, 100, '%d%%')
            if mbManaStop ~= D.ctrl().medbreak_mana_stop then
                D.ctrl().medbreak_mana_stop = mbManaStop
                UI.clampMedBreak('mana', false)
                runtime.saveLoadout(true)
            end

            local mbEnd = ImGui.Checkbox('Endurance##mbend', D.ctrl().medbreak_end_on or false)
            if mbEnd ~= (D.ctrl().medbreak_end_on or false) then
                D.ctrl().medbreak_end_on = mbEnd
                runtime.saveLoadout(true)
            end
            ImGui.SameLine(); ImGui.TextDisabled('at'); ImGui.SameLine(); ImGui.SetNextItemWidth(UI.px(120))
            local mbEndStart = ImGui.SliderInt('##mbendstart', D.ctrl().medbreak_end_start or 20, 0, 100, '%d%%')
            if mbEndStart ~= D.ctrl().medbreak_end_start then
                D.ctrl().medbreak_end_start = mbEndStart
                UI.clampMedBreak('end', true)
                runtime.saveLoadout(true)
            end
            ImGui.SameLine(); ImGui.TextDisabled('until'); ImGui.SameLine(); ImGui.SetNextItemWidth(UI.px(120))
            local mbEndStop = ImGui.SliderInt('##mbendstop', D.ctrl().medbreak_end_stop or 90, 0, 100, '%d%%')
            if mbEndStop ~= D.ctrl().medbreak_end_stop then
                D.ctrl().medbreak_end_stop = mbEndStop
                UI.clampMedBreak('end', false)
                runtime.saveLoadout(true)
            end
        end
    end

    -- 6. Pet Management & Discipline (conditionally shown if quartet has pet class or active pet)
    if runtime.quartetHasPetClass() or hasActivePet() then
        if UI.settingsSection('setPets', 'Pets', 'pet assist hold engage', false) then
            UI.formLabel('Pet engages at mob HP')
            local petAssistVal = ImGui.SliderInt('##pa', D.ctrl().pet_assist_at or 100, 1, 100, '%d%%')
            if petAssistVal ~= D.ctrl().pet_assist_at then
                D.ctrl().pet_assist_at = petAssistVal
                runtime.saveLoadout(true)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Send pets to attack once the target drops to or below\n'
                    .. 'this HP threshold AND the player has started hitting the mob.\n'
                    .. '100 percent = send as soon as the first hit connects (default).')
            end
            ImGui.SameLine()
            local petHoldVal = ImGui.Checkbox('Enable Pet Hold', D.ctrl().pet_hold_enabled ~= false)
            if petHoldVal ~= (D.ctrl().pet_hold_enabled ~= false) then
                D.ctrl().pet_hold_enabled = petHoldVal
                runtime.saveLoadout(true)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(
                    'Hold pets via "#petcmd hold all" whenever out of combat\n'
                    .. 'or prior to reaching the Pet Assist At HP threshold,\n'
                    .. 'releasing them to attack once threshold is met.')
            end
        end
    end


    -- 7. Interface, Overlays & Diagnostics
    if UI.settingsSection('setUi', 'Interface & diagnostics', 'zoning pause floating crit damage compact debug log file dump fov field of view camera restart reload', false) then
        local pauseZoneVal = ImGui.Checkbox('Pause Autocombat When Zoning', D.ctrl().pause_on_zone ~= false)
        if pauseZoneVal ~= (D.ctrl().pause_on_zone ~= false) then
            D.ctrl().pause_on_zone = pauseZoneVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Automatically pause autocombat execution upon entering a new zone.\n'
                .. 'When disabled, autocombat remains active and continues running across zone transitions.')
        end

        local critVal = ImGui.Checkbox('Critical Hit Floating Text', D.ctrl().show_crit_floaters or false)
        if critVal ~= (D.ctrl().show_crit_floaters or false) then
            D.ctrl().show_crit_floaters = critVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Shows flashy floating damage numbers above your character\n'
                .. 'when you land a critical hit, crippling blow, deadly strike,\n'
                .. 'or other special melee/spell criticals.')
        end

        local compactVal = ImGui.Checkbox('Compact Mini-Window HUD Mode', D.ctrl().compact or false)
        if compactVal ~= (D.ctrl().compact or false) then
            D.ctrl().compact = compactVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Switches the Morituri Auto Combat interface into a small, sleek HUD overlay widget.')
        end
        ImGui.SameLine()
        local dbgVal = ImGui.Checkbox('Debug Diagnostic Logging', D.ctrl().debug_mode or false)
        if dbgVal ~= (D.ctrl().debug_mode or false) then
            D.ctrl().debug_mode = dbgVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Prints extra diagnostic lines (e.g. Hunter\'s full targeting\n'
                .. 'state every few seconds) to help track down a stuck/frozen\n'
                .. 'report. Off by default -- noisy for normal use.')
        end
        local logVal = ImGui.Checkbox('Log To File', D.ctrl().log_to_file or false)
        if logVal ~= (D.ctrl().log_to_file or false) then
            D.ctrl().log_to_file = logVal
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Writes every MoriAC chat line, plugin message and (with Debug\n'
                .. 'Diagnostic Logging on) every debug line to a per-character\n'
                .. 'log file in the MacroQuest Logs folder. Plugin errors are\n'
                .. 'recorded with full tracebacks. Rotates at 8 MB.')
        end
        ImGui.SameLine()
        if ImGui.Button('Dump Diagnostics Now') then
            -- runs on the main coroutine next tick: the dump reads TLOs and
            -- writes a file, neither of which belongs in the render callback
            runtime.pluginManager.defer('diagnostic dump', function() runtime.dumpDiagnostics() end)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Writes a one-shot snapshot file (all settings, combat/pull state,\n'
                .. 'plugin status and the last few hundred log lines) that you can\n'
                .. 'attach to a bug report. Works even when Log To File is off.')
        end
        if D.ctrl().log_to_file then
            local lp = tlog.currentFilePath()
            if lp then
                ImGui.TextColored(MUTED[1], MUTED[2], MUTED[3], MUTED[4], 'Logging to: ' .. lp)
            else
                ImGui.TextColored(ERR[1], ERR[2], ERR[3], ERR[4], 'Log file not open: ' .. tostring(tlog.lastOpenError() or 'waiting'))
            end
        end

        accent(GOLD, 'Camera & Viewport:')
        local fovVal = ImGui.Checkbox('Maintain Field of View (/fov)##fovEnabled', D.ctrl().fov_enabled or false)
        if fovVal ~= (D.ctrl().fov_enabled or false) then
            D.ctrl().fov_enabled = fovVal
            if D.ctrl().fov_enabled and runtime.applyFov then
                runtime.applyFov()
            end
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Enforces your custom camera Field of View and automatically re-applies /fov after zoning.')
        end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(UI.px(200))
        local curFov = D.ctrl().fov or 100
        UI.formLabel('Field of view', 160)
        local newFov, fovChanged = ImGui.SliderInt('##fovSlider', curFov, 50, 150, '%d units')
        if fovChanged or (newFov and newFov ~= D.ctrl().fov) then
            D.ctrl().fov = newFov
            D.ctrl().fov_enabled = true
            if runtime.applyFov then runtime.applyFov() end
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Camera Field of View in units (50-150, default: 100).\nMoving the slider automatically enables FOV persistence across zoning.')
        end
        ImGui.SameLine()
        if ImGui.Button('Apply##applyFovBtn') then
            D.ctrl().fov_enabled = true
            if runtime.applyFov then runtime.applyFov() end
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(string.format('Executes /fov %d now and saves the setting.', D.ctrl().fov or 100))
        end

        ImGui.Separator()
        if ImGui.Button('Restart MoriAC##btnRestartScript', UI.px(140), UI.px(24)) then
            runtime.restartScript()
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Stops and re-runs the whole script (/lua stop moriac, /lua run moriac):\n'
                .. 'picks up edited files, reloads every plugin. Your loadout is saved first.')
        end
        ImGui.SameLine()
        ImGui.TextDisabled('also /ac restart')
    end
    if (runtime.settingsQuery or '') ~= '' and runtime.settingsMatches == 0 then
        ImGui.TextDisabled('No settings match "' .. runtime.settingsQuery .. '".')
    end
end
end

return M
