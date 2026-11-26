-- moriac/ui_mini.lua: extracted verbatim from moriac.lua (behaviour-preserving split).
-- Dependencies come in through D (see the init call in moriac.lua); live bindings
-- that moriac.lua reassigns (ctrl, loadout, ...) are read through D.<name>().
local M = {}

function M.init(runtime, UI, D)
    local ARC = D.ARC
    local GOLD = D.GOLD
    local GOOD = D.GOOD
    local ImGui = D.ImGui
    local MODES = D.MODES
    local MUTED = D.MUTED
    local VERSION = D.VERSION
    local WARN = D.WARN
    local accent = D.accent
    local hasActualNPCXtarget = D.hasActualNPCXtarget
    local idxOf = D.idxOf
    local isHostileTarget = D.isHostileTarget
    local mq = D.mq
    local setManualHunterPetHold = D.setManualHunterPetHold
-- ============================================================================
-- Compact window (/ac compact, /ac mini). One dense column: the engine
-- controls, what the engine is doing right now, the target, your vitals,
-- the camp anchor, the session tracker, the plugin / script buttons chosen
-- on Settings -> Plugins and the same MQ2Nav / MoveUtils warnings as the
-- full window. Right-click the window (or the Menu button) for its options:
-- every row can be hidden, and like the other HUDs it can be locked, made
-- frameless and ghosted (ctrl.mini_*; mini_ghost is mirrored into the
-- shared window option so the core's fade drives it).
-- ============================================================================
UI.MINI_SECTIONS = {
    { key = 'mini_show_activity', label = 'Activity line',   tip = 'What the engine is doing right now (pulling, fighting, resting, ...).' },
    { key = 'mini_show_target',   label = 'Target bar',      tip = 'Your target (and the Main Assist\'s target in Assist mode) with an HP bar.' },
    { key = 'mini_show_vitals',   label = 'My vitals',       tip = 'Your HP / Mana / Endurance bars.' },
    { key = 'mini_show_camp',     label = 'Camp row',        tip = 'Camp anchor (set / clear / distance) in the modes that use one.' },
    { key = 'mini_show_tracker',  label = 'Session tracker', tip = 'Session time, AA/hr and Plat/hr.' },
    { key = 'mini_show_buttons',  label = 'Plugin buttons',  tip = 'Buttons for the windows / scripts pinned on Setup -> Plugins.' },
}

-- Handles the Combo widgets for the primary mode and its submode (shared by
-- the compact window and the Control tab). Switching the primary mode
-- resets the submode to the first one and manages the Manual pet hold,
-- exactly as the Control tab always did.
function UI.applyPrimaryMode(newPrimaryMode)
    if newPrimaryMode == nil or newPrimaryMode == D.ctrl().mode then return false end
    if D.ctrl().mode == 'Manual' and newPrimaryMode ~= 'Manual' then
        setManualHunterPetHold(false)
    elseif newPrimaryMode == 'Manual' then
        if not D.ctrl().running or not (runtime.isCombat and runtime.isCombat()) then
            setManualHunterPetHold(true, true)
        end
    end
    D.ctrl().mode = newPrimaryMode
    if runtime.bossReset then runtime.bossReset() end
    if MODES.SUBMODES[D.ctrl().mode] then
        D.ctrl().submode = MODES.SUBMODES[D.ctrl().mode][1]
    else
        D.ctrl().submode = 'Hunt'
    end
    runtime.saveLoadout(true)
    return true
end

function UI.applySubmode(newSubmode)
    if newSubmode == nil or newSubmode == D.ctrl().submode then return false end
    D.ctrl().submode = newSubmode
    runtime.saveLoadout(true)
    return true
end

function UI.drawModeCombos(idSuffix, wPrimary, wSub)
    ImGui.SetNextItemWidth(wPrimary or 100)
    local curPrimaryIdx = idxOf(MODES.PRIMARY, D.ctrl().mode)
    local newPrimaryIdx = ImGui.Combo('##primary' .. idSuffix, curPrimaryIdx, MODES.PRIMARY)
    if ImGui.IsItemHovered() then
        UI.setTooltip(MODES.DESC[D.ctrl().mode] or 'Primary combat mode (Manual, Puller, Assist).')
    end
    if newPrimaryIdx ~= curPrimaryIdx then
        UI.applyPrimaryMode(MODES.PRIMARY[newPrimaryIdx])
    end
    local subList = MODES.SUBMODES[D.ctrl().mode]
    if subList then
        ImGui.SameLine()
        ImGui.SetNextItemWidth(wSub or 90)
        local curSubIdx = idxOf(subList, D.ctrl().submode)
        local newSubIdx = ImGui.Combo('##sub' .. idSuffix, curSubIdx, subList)
        if ImGui.IsItemHovered() then
            UI.setTooltip(MODES.SUB_DESC[D.ctrl().mode .. ':' .. tostring(D.ctrl().submode)] or ('Submode for ' .. tostring(D.ctrl().mode) .. '.'))
        end
        if newSubIdx ~= curSubIdx then
            UI.applySubmode(subList[newSubIdx])
        end
    end
end

-- The modes that anchor to ctrl.camp_loc.
function UI.modeUsesCamp()
    if D.ctrl().mode == 'Manual' or D.ctrl().mode == 'Boss' then return true end
    return (D.ctrl().mode == 'Puller' or D.ctrl().mode == 'Assist') and (D.ctrl().submode == 'Camp' or D.ctrl().submode == 'Lure')
end

-- What the engine is doing right now: text plus colour for the compact
-- window's activity line. Rests win over pull states, pull states over
-- plain combat, combat over casting / moving, and the idle text says what
-- the mode is waiting for.
function UI.miniActivity()
    if not D.ctrl().running then return 'Paused', WARN end
    if runtime.medBreakActive then return 'Med break - resting', ARC end
    if runtime.pullHpRest then
        return string.format('Resting - HP below %d%%', tonumber(D.ctrl().pull_min_hp_pct) or 0), ARC
    end
    local function spawnName(id)
        local nm = nil
        if (tonumber(id) or 0) > 0 then
            pcall(function()
                local s = mq.TLO.Spawn(id)
                if s and s() then nm = s.CleanName() end
            end)
        end
        return nm
    end
    if D.ctrl().mode == 'Puller' then
        if runtime.pullState == 'TO_MOB' then
            return 'Pulling ' .. (spawnName(runtime.pullTargetId) or 'a mob'), GOLD
        elseif runtime.pullState == 'TO_CAMP' then
            return 'Bringing ' .. (spawnName(runtime.pullTargetId) or 'the pull') .. ' to camp', GOLD
        end
    end
    local tId, tName = 0, nil
    pcall(function()
        local t = mq.TLO.Target
        if t and t() and (t.ID() or 0) > 0 then
            tId = t.ID() or 0
            tName = t.CleanName()
        end
    end)
    local attacking = false
    pcall(function() attacking = (mq.TLO.Me.Combat() == true) end)
    if runtime.lureHolding(tId) then return 'Waiting at camp for ' .. tostring(tName or 'target'), WARN end
    if tId > 0 and (attacking or runtime.pullState == 'FIGHTING') and isHostileTarget(tId) then
        return 'Fighting ' .. tostring(tName or 'target'), { 1.0, 0.45, 0.40, 1.0 }
    end
    if hasActualNPCXtarget() then return 'In combat', { 1.0, 0.45, 0.40, 1.0 } end
    local casting = nil
    pcall(function() casting = mq.TLO.Me.Casting.Name() end)
    if casting and casting ~= '' and casting ~= 'NULL' then return 'Casting ' .. tostring(casting), GOOD end
    local navActive = false
    pcall(function() navActive = (mq.TLO.Navigation.Active() == true) end)
    if navActive then
        if D.ctrl().mode == 'Puller' and D.ctrl().submode == 'Hunt' then return 'Roaming for a target', ARC end
        if D.ctrl().mode == 'Assist' and D.ctrl().submode == 'Chase' then return 'Following the Main Assist', ARC end
        if D.ctrl().camp_loc and UI.modeUsesCamp() then return 'Returning to camp', ARC end
        return 'Moving', ARC
    end
    if D.ctrl().mode == 'Assist' then return 'Waiting on the Main Assist', MUTED end
    if D.ctrl().mode == 'Puller' then return 'Looking for a pull', MUTED end
    if D.ctrl().mode == 'Boss' then
        local bs = runtime.bossState
        if bs and bs.why == 'wait' then
            return string.format('Waiting - boss at %d%%', tonumber(bs.bossHp) or 100), WARN
        end
        return 'Waiting for the fight to start', MUTED
    end
    return 'Idle - waiting for a target', MUTED
end

-- Rows of the compact window. Each is a plain function so the layout in
-- UI.drawMiniGui reads top to bottom.
-- The bars size themselves to the widest text / button row of the previous
-- frame (runtime.miniRowWidth) instead of "fill available": each row calls
-- UI.miniMeasure() after its last item, the bars are left out, so the
-- auto-resizing window can shrink back once a wide warning row goes.
function UI.miniRowWidth()
    local w = tonumber(runtime.miniRowWidth) or 0
    if w < 120 then return -1 end
    return w
end

function UI.miniMeasure()
    pcall(function()
        local x1 = ImGui.GetItemRectMax()
        if type(x1) ~= 'number' then x1 = x1 and x1.x end
        if x1 and (not runtime.miniFrameMaxX or x1 > runtime.miniFrameMaxX) then
            runtime.miniFrameMaxX = x1
        end
    end)
end

-- Bar height that fits the current font (the popout HUDs use fixed 14 px
-- bars, which clip the label on larger fonts).
function UI.miniBarHeight()
    local h = 18
    pcall(function()
        local fs = ImGui.GetFontSize()
        if type(fs) == 'number' and fs > 0 then h = math.floor(fs + 5) end
    end)
    return h
end

function UI.drawMiniHeader()
    UI.drawStartPauseButton('##miniRun', UI.px(72), 0)
    ImGui.SameLine()
    UI.drawBurnButton('##miniBurn', UI.px(64), 0, 'BURN!', 'Burn')
    ImGui.SameLine(0, UI.px(10))
    UI.drawModeCombos('MiniMode', UI.px(86), UI.px(82))
    ImGui.SameLine(0, UI.px(10))
    if ImGui.Button('Expand##miniFull') then
        D.ctrl().compact = false
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then UI.setTooltip('Back to the full window.') end
    ImGui.SameLine()
    if ImGui.Button('Menu##miniMenuBtn') then
        ImGui.OpenPopup('##miniMenu')
    end
    if ImGui.IsItemHovered() then UI.setTooltip('Compact window options (also on right-click).') end
    UI.miniMeasure()
end

function UI.drawMiniActivity()
    UI.drawStatusLine(true)
    UI.miniMeasure()
end

function UI.drawMiniTarget()
    local maInfo = nil
    if D.ctrl().mode == 'Assist' or (D.ctrl().ma_id and D.ctrl().ma_id > 0) or (D.ctrl().ma_name and D.ctrl().ma_name ~= '') then
        maInfo = runtime.getMaTargetInfo and runtime.getMaTargetInfo()
    end
    if maInfo then
        accent(GOLD, 'MA')
        ImGui.SameLine()
        if maInfo.hasMA then
            ImGui.Text(tostring(maInfo.maName))
            ImGui.SameLine(); ImGui.TextDisabled('->')
            ImGui.SameLine()
            if maInfo.hasTarget then
                accent(UI.getConColorRgb(maInfo.targetCon), string.format('%s (%d%%)', maInfo.targetName, maInfo.targetHp))
                ImGui.SameLine()
                if ImGui.SmallButton('Target##miniTargMA') then
                    mq.cmdf('/target id %d', maInfo.targetId)
                end
                if ImGui.IsItemHovered() then
                    UI.setTooltip('Target the Main Assist\'s target: %s (ID %d, %d%% HP, %.0fft)',
                        maInfo.targetName, maInfo.targetId, maInfo.targetHp, maInfo.targetDist)
                end
            else
                ImGui.TextDisabled('no target')
            end
        else
            accent(MUTED, 'none set')
            if ImGui.IsItemHovered() then UI.setTooltip('Pick a Main Assist on the Mode & Pulling page of the full window.') end
        end
        UI.miniMeasure()
    end

    local t = {}
    pcall(function()
        local T = mq.TLO.Target
        if T and T() and (T.ID() or 0) > 0 then
            t.id = T.ID() or 0
            t.name = T.CleanName() or 'Unknown'
            t.lvl = T.Level() or 0
            t.class = T.Class.ShortName() or '?'
            t.con = T.ConColor() or 'White'
            t.hp = T.PctHPs() or 0
            t.dist = T.Distance() or 0
            t.type = T.Type() or 'NPC'
            t.los = T.LineOfSight() or false
            t.aggro = T.PctAggro() or 0
        end
    end)
    if not t.id then
        accent(MUTED, 'No target')
        return
    end
    local conCol = UI.getConColorRgb(t.con)
    accent(conCol, tostring(t.name or 'Unknown'))
    ImGui.SameLine()
    ImGui.TextDisabled(string.format('L%d %s  %.0fft', t.lvl or 0, tostring(t.class or '?'), t.dist or 0))
    local hostile = (t.type == 'NPC') and isHostileTarget(t.id)
    if hostile then
        ImGui.SameLine()
        if (t.aggro or 0) >= 100 then
            accent({ 1.0, 0.45, 0.40, 1.0 }, 'tanking')
        else
            ImGui.TextDisabled(string.format('aggro %d%%', t.aggro or 0))
        end
    end
    if not t.los then
        ImGui.SameLine(); accent(WARN, 'no LoS')
    end
    UI.miniMeasure()
    local r, g, b = 0.25, 0.80, 0.35
    if (t.hp or 0) <= 20 then
        r, g, b = 0.90, 0.20, 0.20
    elseif (t.hp or 0) <= 50 then
        r, g, b = 0.95, 0.75, 0.20
    end
    UI.drawStatusProgressBar((t.hp or 0) / 100.0, UI.miniRowWidth(), UI.miniBarHeight(), string.format('%d%%', t.hp or 0), r, g, b, 1.0)
    if ImGui.IsItemHovered() then
        UI.setTooltip('%s (ID %d)\nLevel %d %s, con %s, %s\n%.1fft, line of sight: %s\nMy aggro: %d%%',
            tostring(t.name or 'Unknown'), t.id, t.lvl or 0, tostring(t.class or '?'), tostring(t.con or 'White'),
            hostile and 'hostile' or 'not hostile', t.dist or 0, t.los and 'yes' or 'no', t.aggro or 0)
    end
end

function UI.drawMiniVitals()
    local hp, mana, en, maxMana = 0, 0, 0, 0
    pcall(function()
        hp = mq.TLO.Me.PctHPs() or 0
        mana = mq.TLO.Me.PctMana() or 0
        en = mq.TLO.Me.PctEndurance() or 0
        maxMana = mq.TLO.Me.MaxMana() or 0
    end)
    local bars = { { 'HP', hp, 0.25, 0.80, 0.35 } }
    if (hp or 0) <= 25 then
        bars[1][3], bars[1][4], bars[1][5] = 0.90, 0.20, 0.20
    elseif (hp or 0) <= 50 then
        bars[1][3], bars[1][4], bars[1][5] = 0.95, 0.75, 0.20
    end
    if (maxMana or 0) > 0 then bars[#bars + 1] = { 'Mana', mana, 0.25, 0.50, 0.95 } end
    bars[#bars + 1] = { 'End', en, 0.85, 0.65, 0.20 }
    local rowW = UI.miniRowWidth()
    if rowW < 0 then rowW = 400 end
    local spacing = 6
    local barW = math.max(80, math.floor((rowW - spacing * (#bars - 1)) / #bars))
    for i, bar in ipairs(bars) do
        if i > 1 then ImGui.SameLine(0, spacing) end
        UI.drawStatusProgressBar((bar[2] or 0) / 100.0, barW, UI.miniBarHeight(), string.format('%s %d%%', bar[1], bar[2] or 0), bar[3], bar[4], bar[5], 1.0)
    end
end

function UI.drawMiniCamp()
    accent(GOLD, 'Camp')
    ImGui.SameLine()
    if D.ctrl().camp_loc then
        local dist = nil
        pcall(function()
            local mx, my, mz = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
            if mx and my and mz then
                local dx, dy, dz = (D.ctrl().camp_loc.x or 0) - mx, (D.ctrl().camp_loc.y or 0) - my, (D.ctrl().camp_loc.z or 0) - mz
                dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            end
        end)
        local radius = D.ctrl().camp_radius or 100
        if dist then
            accent(dist <= radius and GOOD or WARN, string.format('%.0fft away', dist))
        else
            ImGui.Text('set')
        end
        if ImGui.IsItemHovered() then
            UI.setTooltip('Camp at %.1f, %.1f, %.1f (radius %d).', D.ctrl().camp_loc.x or 0, D.ctrl().camp_loc.y or 0, D.ctrl().camp_loc.z or 0, radius)
        end
    elseif D.ctrl().mode == 'Puller' then
        accent(WARN, 'not set - the puller needs one')
    else
        accent(MUTED, 'not set')
    end
    ImGui.SameLine()
    if ImGui.SmallButton('Set Here##miniCampSet') then
        local mx, my, mz = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
        if mx and my and mz then
            D.ctrl().camp_loc = { x = mx, y = my, z = mz }
            runtime.saveLoadout(true)
        end
    end
    if ImGui.IsItemHovered() then UI.setTooltip('Use where you stand as the camp anchor.') end
    if D.ctrl().camp_loc then
        ImGui.SameLine()
        if ImGui.SmallButton('Clear##miniCampClear') then
            D.ctrl().camp_loc = nil
            if D.ctrl().mode == 'Puller' then
                runtime.pullState = 'IDLE'; runtime.pullTargetId = 0
            end
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then UI.setTooltip('Forget the camp anchor.') end
    end
    UI.miniMeasure()
end

function UI.drawMiniTracker()
    UI.updateTracker()
    local elapsedSec = os.time() - (runtime.trackStartTime or os.time())
    local elapsedHrs = math.max(elapsedSec / 3600.0, 0)
    local aaGained = (runtime.startAA and runtime.currentAA) and math.max(0, runtime.currentAA - runtime.startAA) or 0
    local aaRate = (elapsedHrs > 0.0001) and (aaGained / elapsedHrs) or 0.0
    local platGained = (runtime.startPlat and runtime.currentPlat) and (runtime.currentPlat - runtime.startPlat) or 0
    local platRate = (elapsedHrs > 0.0001) and (platGained / elapsedHrs) or 0.0
    local m = math.floor(elapsedSec / 60)
    local s = elapsedSec % 60
    local h = math.floor(m / 60)
    m = m % 60
    local timeStr = h > 0 and string.format('%dh %02dm', h, m) or string.format('%dm %02ds', m, s)

    ImGui.TextDisabled(timeStr)
    ImGui.SameLine(); ImGui.TextDisabled('|')
    ImGui.SameLine(); accent(GOOD, string.format('%.1f AA/hr', aaRate))
    ImGui.SameLine(); ImGui.TextDisabled('|')
    ImGui.SameLine(); accent(GOLD, string.format('%.0f plat/hr', platRate))
    ImGui.SameLine()
    if ImGui.SmallButton('Reset##miniResetTrack') then
        UI.resetTracker()
    end
    if ImGui.IsItemHovered() then
        UI.setTooltip(
            "Session %s\n" ..
            "AA:   %+.2f gained (%.2f / hr)\n" ..
            "Plat: %+d gained (%.1f / hr)\n" ..
            "Click Reset to start a new session.",
            timeStr, aaGained, aaRate, platGained, platRate)
    end
    UI.miniMeasure()
end

function UI.drawMiniButtons()
    -- initPluginManager runs plugin chunks / onInit and must never execute on
    -- the render thread; it is always initialised before the first frame.
    if not runtime.pluginManager then return end
    local pm = runtime.pluginManager
    if not (pm and type(pm.drawHeaderButtons) == 'function') then return end
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 5, 2)
    local ok, drawn = pcall(pm.drawHeaderButtons, 0)
    ImGui.PopStyleVar()
    if not ok then
        if runtime.lastHeaderButtonErr ~= tostring(drawn) then
            runtime.lastHeaderButtonErr = tostring(drawn)
            print('\ar[MoriAC]\ax header buttons failed: ' .. tostring(drawn))
        end
        drawn = 0
    end
    if drawn == 0 then
        ImGui.TextDisabled('(no pinned windows - pin them on Setup -> Plugins)')
    end
    UI.miniMeasure()
end

function UI.drawMiniWarnings()
    if #UI.collectIssues() == 0 then return end
    UI.drawIssuesStrip()
    UI.miniMeasure()
end

-- Ghost mode for the compact window: ctrl.mini_ghost is the saved switch;
-- the core's fade reads the shared window option, so the two are kept in
-- step (setWindowOpt saves the loadout itself, only when it changes).
function UI.setMiniGhost(on)
    on = (on == true)
    D.ctrl().mini_ghost = on
    UI.setWindowOpt('mini', 'ghost', on)
    runtime.saveLoadout(true)
end

function UI.syncMiniGhost()
    local o = UI.windowOpts('mini')
    local want = D.ctrl().mini_ghost == true
    if ((o and o.ghost == true) or false) ~= want then UI.setWindowOpt('mini', 'ghost', want) end
end

-- Right-click / Menu popup: window behaviour and which rows are shown.
function UI.drawMiniMenu()
    if not ImGui.BeginPopupContextWindow('##miniMenu') then return end
    UI.applyWindowScale('mini')
    if ImGui.MenuItem('Full Window') then
        D.ctrl().compact = false
        runtime.saveLoadout(true)
    end
    ImGui.Separator()
    ImGui.TextDisabled('Show')
    for _, sec in ipairs(UI.MINI_SECTIONS) do
        local on = D.ctrl()[sec.key] ~= false
        local val = ImGui.Checkbox(sec.label .. '##' .. sec.key, on)
        if val ~= on then
            D.ctrl()[sec.key] = val
            runtime.saveLoadout(true)
        end
        if ImGui.IsItemHovered() then UI.setTooltip(sec.tip) end
    end
    ImGui.Separator()
    ImGui.TextDisabled('Window')
    local lockVal = ImGui.Checkbox('Lock position##miniLock', D.ctrl().mini_lock == true)
    if lockVal ~= (D.ctrl().mini_lock == true) then
        D.ctrl().mini_lock = lockVal
        runtime.saveLoadout(true)
    end
    local tbVal = ImGui.Checkbox('Title bar##miniTitle', D.ctrl().mini_titlebar ~= false)
    if tbVal ~= (D.ctrl().mini_titlebar ~= false) then
        D.ctrl().mini_titlebar = tbVal
        runtime.saveLoadout(true)
    end
    if ImGui.IsItemHovered() then UI.setTooltip('Hide the title bar for a cleaner overlay. Right-click the window to get back here.') end
    local ghostVal = ImGui.Checkbox('Ghost mode##miniGhost', D.ctrl().mini_ghost == true)
    if ghostVal ~= (D.ctrl().mini_ghost == true) then
        UI.setMiniGhost(ghostVal)
    end
    if ImGui.IsItemHovered() then UI.setTooltip('The background, border, title bar and buttons fade out when the mouse leaves the window and fade back in under it; the text and bars stay.\nPairs well with the title bar off. /ac ghost toggles it.') end
    UI.drawWindowMenuItems('mini', { header = false, titleBar = false, ghost = false, lock = false, scale = false, layout = false, close = false })
    UI.drawWindowScaleControl('mini', 'Scale', 130)
    ImGui.SetNextItemWidth(UI.px(140))
    local alpha = ImGui.SliderFloat('Opacity##miniAlpha', D.ctrl().mini_alpha or 0.92, 0.20, 1.0, '%.2f')
    if alpha ~= (D.ctrl().mini_alpha or 0.92) then
        D.ctrl().mini_alpha = alpha
        runtime.saveLoadout(true)
    end
    ImGui.EndPopup()
end

function UI.drawMiniGui()
    if not D.open() or not D.ctrl().compact then return end
    UI.pushTheme()
    UI.syncMiniGhost()
    UI.preBeginWindow('mini')
    pcall(ImGui.SetNextWindowBgAlpha, UI.windowBgAlpha('mini', D.ctrl().mini_alpha or 0.92))
    local flags = ImGuiWindowFlags.AlwaysAutoResize
    if D.ctrl().mini_lock then flags = bit.bor(flags, ImGuiWindowFlags.NoMove) end
    if D.ctrl().mini_titlebar == false and ImGuiWindowFlags.NoTitleBar then flags = bit.bor(flags, ImGuiWindowFlags.NoTitleBar) end
    flags = UI.windowFlags('mini', flags)
    local show
    -- The X on the mini window returns to the full window; it used to write
    -- the script-level `open` flag and so terminated the whole script.
    local miniOpen
    miniOpen, show = ImGui.Begin('MoriAC v' .. VERSION .. '###triuneMini', true, flags)
    if not miniOpen then
        D.ctrl().compact = false
        UI.preEndWindow('mini', true)
        ImGui.End()
        UI.popTheme()
        return
    end

    if show then UI.guardedDraw(function()
        UI.postBeginWindow('mini')
        local x0 = nil
        pcall(function()
            local x = ImGui.GetCursorScreenPos()
            if type(x) == 'number' then x0 = x elseif x then x0 = x.x end
        end)
        runtime.miniFrameMaxX = nil
        UI.drawMiniMenu()
        UI.drawMiniHeader()
        if D.ctrl().mini_show_activity ~= false then
            UI.drawMiniActivity()
        end
        if D.ctrl().mini_show_target ~= false then
            ImGui.Separator()
            UI.drawMiniTarget()
        end
        if D.ctrl().mini_show_vitals ~= false then
            UI.drawMiniVitals()
        end
        if D.ctrl().mini_show_camp ~= false and UI.modeUsesCamp() then
            ImGui.Separator()
            UI.drawMiniCamp()
        end
        if D.ctrl().mini_show_tracker ~= false then
            ImGui.Separator()
            UI.drawMiniTracker()
        end
        if D.ctrl().mini_show_buttons ~= false then
            ImGui.Separator()
            UI.drawMiniButtons()
        end
        UI.drawMiniWarnings()
        if x0 and runtime.miniFrameMaxX then
            runtime.miniRowWidth = math.floor(runtime.miniFrameMaxX - x0 + 0.5)
        end
    end) end

    UI.preEndWindow('mini', true)
    ImGui.End()
    UI.popTheme()
end
end

return M
