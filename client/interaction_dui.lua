-- World prompts drawn by the game from one DUI texture (ui/world.html).
--
-- A NUI prompt is positioned from World3dToScreen2d, which uses the previous
-- frame's camera, crosses SendNUIMessage, and reaches the screen through CEF a
-- frame or two later, so it trails its anchor and stutters whenever the camera
-- turns. Here every prompt group renders into a fixed cell of one transparent
-- DUI texture, and each frame the renderer draws that cell at the anchor with
-- SetDrawOrigin, which the game resolves at render time with the current
-- camera. Positions never cross into CEF; the DUI repaints only when a prompt's
-- content changes (rows, selection, hold ring, mash dial).
--
-- The page reports each content revision it has painted
-- (interactionWorldReady). A cell with new content (another list, a flip) is
-- drawn once its revision is painted, so the game never draws a blank or
-- stale cell; a page that cannot report falls back to short timers.
--
-- Renderer-private: client/interaction_renderer.lua drives it and keeps the
-- NUI world layer until the DUI has painted, if it fails, or when the convar
-- `cortex_lib_world_dui` is 0.

local math_abs = math.abs
local math_floor = math.floor
local math_huge = math.huge
local math_min = math.min

-- Atlas layout in prompt units (--ix). A cell holds one group: up to four
-- rows plus a peek row and the rail tails (about 250ix), labels capped at
-- 340ix beside a 44ix disc. The anchor is the first disc's centre.
local COLUMNS, ROWS = 2, 3
local CELLS = COLUMNS * ROWS
local CELL_W, CELL_H = 480, 288
local ANCHOR_X, ANCHOR_Y = 48, 60
-- Texture edge cap: prompt sizes beyond it render smaller and draw upscaled
-- (at 4K that is large prompts above about 138% UI scale).
local MAX_EDGE = 3072
-- The NUI flips a group leftwards past 0.68 of the width. A flip needs a
-- repaint here, so it uses hysteresis.
local FLIP_X, FLIP_ON, FLIP_OFF = 0.68, 0.70, 0.66
-- New content in a cell waits for the page to report it painted: at most
-- REVEAL_MAX_MS (a lost report), or REVEAL_MS from a page that never reports.
local REVEAL_MS, REVEAL_MAX_MS = 100, 300
-- A released cell keeps its content this long, so a list that drops out for a
-- moment (a merge split, the range edge) comes back without a repaint.
local CELL_HOLD_MS = 400
-- Lifecycle. Messages sent before the page listens are lost, so a state is
-- resent until the page reports painting it; from a page that never reports,
-- quickly for a while, then about once a second while anything is shown.
local AVAILABLE_TIMEOUT_MS = 8000
local WARMUP_MS = 1500
local FAST_RESEND_MS, FAST_WINDOW_MS, RESEND_MS = 250, 4000, 1000
local RESCALE_STABLE_MS = 500
-- A replaced DUI outlives the frames that may still be drawing its texture.
local RETIRE_MS = 250
local TXD_NAME = 'cortex_lib_world'

local resourceName = GetCurrentResourceName()
local URL = 'nui://' .. resourceName .. '/ui/world.html?resource=' .. resourceName .. '&dui=%d'

local Dui = { CELLS = CELLS }

local txd = nil
local serial = 0
local active, pending = nil, nil
local retired = {}
local failed = false
local rescaleFailedIx = nil
local stableIx, stableSince = nil, 0
local cells = {}
local dirty = true
local revision, lastContent = 0, nil
local lastPromptScale = 1.0
local profile = nil
local paused = false
-- The open mash session's messages, replayed to a DUI that starts mid-session.
local skillReplay = {}

for index = 1, CELLS do
    cells[index] = { group = nil, heldGroup = nil, heldEntry = nil, releasedAt = -math_huge, flipped = false }
end

local function supported()
    if type(CreateDui) ~= 'function' or type(IsDuiAvailable) ~= 'function' or type(GetDuiHandle) ~= 'function'
        or type(CreateRuntimeTxd) ~= 'function' or type(CreateRuntimeTextureFromDuiHandle) ~= 'function'
        or type(SendDuiMessage) ~= 'function' or type(DestroyDui) ~= 'function'
        or type(DrawSpriteUv) ~= 'function' or type(SetDrawOrigin) ~= 'function'
        or type(json) ~= 'table' or type(json.encode) ~= 'function'
    then
        return false
    end
    return type(GetConvarInt) ~= 'function' or GetConvarInt('cortex_lib_world_dui', 1) ~= 0
end
-- Read once: natives do not appear later, and the convar is a startup choice.
local SUPPORTED = supported()

-- Texture pixels per prompt unit for a screen --ix, within MAX_EDGE.
local function renderIxFor(ix)
    return math_min(ix, MAX_EDGE / (COLUMNS * CELL_W), MAX_EDGE / (ROWS * CELL_H))
end

local function create(renderIx, now)
    serial = serial + 1
    local cellWidth = math_floor(CELL_W * renderIx + 0.5)
    local cellHeight = math_floor(CELL_H * renderIx + 0.5)
    local width, height = cellWidth * COLUMNS, cellHeight * ROWS
    local object = CreateDui(URL:format(serial), width, height)
    if not object then return nil end
    return {
        serial = serial,
        object = object,
        textureName = 'prompts' .. serial,
        renderIx = renderIx,
        width = width,
        height = height,
        cellWidth = cellWidth,
        cellHeight = cellHeight,
        anchorX = math_floor(ANCHOR_X * renderIx + 0.5),
        anchorRight = cellWidth - math_floor(ANCHOR_X * renderIx + 0.5),
        anchorY = math_floor(ANCHOR_Y * renderIx + 0.5),
        createdAt = now,
        painted = 0,
        sentAt = 0,
    }
end

local function destroy(entry)
    if entry and entry.object then DestroyDui(entry.object) end
end

local function replaySkill(entry)
    for index = 1, #skillReplay do SendDuiMessage(entry.object, json.encode(skillReplay[index])) end
    if skillReplay.progress then SendDuiMessage(entry.object, json.encode(skillReplay.progress)) end
end

-- 'ready' once the DUI has a texture and its page has painted the latest
-- state (or, from a page that never reports, once the warm-up has passed).
local function advance(entry, now)
    if not entry.availableAt then
        if not IsDuiAvailable(entry.object) then
            return now - entry.createdAt < AVAILABLE_TIMEOUT_MS and 'waiting' or 'failed'
        end
        txd = txd or CreateRuntimeTxd(TXD_NAME)
        -- The native returns a pointer: nil or 0 when it failed.
        local texture = CreateRuntimeTextureFromDuiHandle(txd, entry.textureName, GetDuiHandle(entry.object))
        if not texture or texture == 0 then return 'failed' end
        entry.availableAt = now
        -- Feed it the current content while it loads.
        dirty = true
    end
    if entry.reported and entry.painted >= (entry.sentRevision or 0) then return 'ready' end
    if now - entry.availableAt >= WARMUP_MS then return 'ready' end
    return 'waiting'
end

-- Called every renderer pass with the screen's --ix. Returns 'draw' (draw
-- from the DUI), 'prime' (the first DUI is loading: send it content, keep the
-- NUI layer) or false (the NUI layer only).
function Dui.update(now, ix)
    for index = #retired, 1, -1 do
        if now - retired[index].retiredAt >= RETIRE_MS then
            destroy(retired[index])
            table.remove(retired, index)
        end
    end
    if failed or not SUPPORTED then return false end

    local wanted = renderIxFor(ix)
    if stableIx == nil or math_abs(stableIx - wanted) > 0.001 then
        stableIx, stableSince = wanted, now
    end
    -- A new size needs a new DUI; wait until the scale stops changing (the
    -- settings preview steps through values) and keep drawing the old one.
    if not pending and (not active or math_abs(active.renderIx - wanted) > 0.001)
        and (not active or now - stableSince >= RESCALE_STABLE_MS)
        and (not rescaleFailedIx or math_abs(rescaleFailedIx - wanted) > 0.001)
    then
        pending = create(wanted, now)
        if not pending then
            if active then
                rescaleFailedIx = wanted
            else
                failed = true
                print('[cortex-lib] world prompts: CreateDui failed; using the NUI layer')
            end
        end
    end

    if pending then
        local status = advance(pending, now)
        if status == 'ready' then
            if active then
                active.retiredAt = now
                retired[#retired + 1] = active
            end
            active, pending = pending, nil
            replaySkill(active)
        elseif status == 'failed' then
            destroy(pending)
            if active then
                -- Keep the current size rather than retry the same one forever.
                rescaleFailedIx = pending.renderIx
            else
                failed = true
                print('[cortex-lib] world prompts: the DUI did not start; using the NUI layer')
            end
            pending = nil
        end
    end

    if active then return 'draw' end
    if pending and pending.availableAt then return 'prime' end
    return false
end

-- Assigns each list (cluster) a cell, or none when all are taken: an
-- undrawn list must not be presented as visible. Sets cluster.cell.
function Dui.assign(now, clusters, count)
    for index = 1, CELLS do cells[index].claimed = false end

    -- Lists keep their cell, or take back the one they just left (its
    -- content is still painted unless the hold ran out).
    for clusterIndex = 1, count do
        local cluster = clusters[clusterIndex]
        local group = cluster.head.groupId
        cluster.cell = nil
        for index = 1, CELLS do
            local cell = cells[index]
            if not cell.claimed and (cell.group == group or (not cell.group and cell.heldGroup == group)) then
                if not cell.group then
                    cell.group = group
                    dirty = true
                    if now - cell.releasedAt >= CELL_HOLD_MS then cell.waitReveal = true end
                end
                cell.claimed = true
                cluster.cell = index
                break
            end
        end
    end

    -- New lists take the cell free the longest (the least likely to be taken
    -- back); it shows once the page has painted the list into it.
    for clusterIndex = 1, count do
        local cluster = clusters[clusterIndex]
        if not cluster.cell then
            local best = nil
            for index = 1, CELLS do
                local cell = cells[index]
                if not cell.group and (not best or cell.releasedAt < cells[best].releasedAt) then best = index end
            end
            if best then
                local cell = cells[best]
                cell.group = cluster.head.groupId
                cell.heldGroup, cell.heldEntry = nil, nil
                cell.claimed = true
                cell.flipped = cluster.head.screenX > FLIP_X
                cell.waitReveal = true
                cluster.cell = best
                dirty = true
            end
        end
    end

    for index = 1, CELLS do
        local cell = cells[index]
        if cell.group and not cell.claimed then
            cell.heldGroup = cell.group
            cell.group = nil
            cell.cluster = nil
            cell.releasedAt = now
        end
    end

    for clusterIndex = 1, count do
        local cluster = clusters[clusterIndex]
        local cell = cluster.cell and cells[cluster.cell]
        if cell then
            cell.cluster = cluster
            local x = cluster.head.screenX
            local flipped = cell.flipped and x > FLIP_OFF or (not cell.flipped and x > FLIP_ON)
            if flipped ~= cell.flipped then
                cell.flipped = flipped
                cell.waitReveal = true
                dirty = true
            end
        end
    end
end

local function copyItem(item)
    return {
        id = item.id, owner = item.owner, label = item.label, key = item.key,
        panel = item.panel, holdDuration = item.holdDuration, holdActive = item.holdActive,
        holdRevision = item.holdRevision, tier = 'prompt', group = item.group,
        selected = item.selected, active = item.active, focused = item.focused,
        -- The DUI page places the group itself; positions stay native.
        x = 0, y = 0, distance = 0,
    }
end

local function deliver(entry, now, list, occupied)
    if not entry or not entry.availableAt or entry.sentRevision == revision then return end
    entry.encoded = json.encode({
        action = 'world:state',
        data = {
            revision = revision,
            u = entry.renderIx / lastPromptScale,
            scale = lastPromptScale,
            cellWidth = entry.cellWidth,
            cellHeight = entry.cellHeight,
            columns = COLUMNS,
            anchorX = entry.anchorX,
            anchorRight = entry.anchorRight,
            anchorY = entry.anchorY,
            theme = profile or false,
            cells = list,
        },
    })
    entry.sentRevision = revision
    entry.occupied = occupied
    entry.sentAt = now
    SendDuiMessage(entry.object, entry.encoded)
end

-- Builds the cells' content and sends it to every live DUI that does not
-- have it. `stamp` is the renderer pass whose staged rows are shown.
local function sendState(now, stamp)
    dirty = false
    local list, occupied = {}, false
    for index = 1, CELLS do
        local cell = cells[index]
        local entry = false
        local cluster = cell.group and cell.cluster
        if cluster then
            local items = {}
            for rowIndex = 1, cluster.count do
                local descriptor = cluster.rows[rowIndex]
                if descriptor.frameStamp == stamp then items[#items + 1] = copyItem(descriptor.frameItem) end
            end
            if #items > 0 then entry = { group = cell.group, flipped = cell.flipped, items = items } end
            cell.heldEntry = entry or nil
        elseif cell.heldEntry and now - cell.releasedAt < CELL_HOLD_MS then
            entry = cell.heldEntry
        else
            cell.heldEntry = nil
        end
        if entry then occupied = true end
        list[index] = entry
    end

    local content = json.encode({ list, profile or false, lastPromptScale })
    if content ~= lastContent then
        lastContent = content
        revision = revision + 1
    end
    local target = active or pending
    local deadline = now + ((target and target.reported) and REVEAL_MAX_MS or REVEAL_MS)
    for index = 1, CELLS do
        local cell = cells[index]
        if cell.waitReveal then
            cell.waitReveal = false
            cell.revealRevision, cell.revealDeadline = revision, deadline
        end
    end
    deliver(active, now, list, occupied)
    deliver(pending, now, list, occupied)
end

-- Repeats the last state while the page may have missed it: until it reports
-- painting it, or (from a page that never reports) while anything is shown.
local function resend(entry, now)
    if not entry or not entry.encoded then return end
    local interval
    if entry.reported then
        if entry.painted >= entry.sentRevision then return end
        interval = FAST_RESEND_MS
    else
        if not entry.occupied then return end
        interval = now - entry.availableAt < FAST_WINDOW_MS and FAST_RESEND_MS or RESEND_MS
    end
    if now - entry.sentAt >= interval then
        entry.sentAt = now
        SendDuiMessage(entry.object, entry.encoded)
    end
end

-- Releases every cell, so nothing is drawn; their content is held as usual.
function Dui.clear(now)
    for index = 1, CELLS do
        local cell = cells[index]
        if cell.group then
            cell.heldGroup = cell.group
            cell.group = nil
            cell.cluster = nil
            cell.releasedAt = now
        end
    end
end

-- Sends the cells' content when it changed (`changed`: the renderer saw a
-- row, flag or grouping change this pass) and resends it while needed.
function Dui.publish(now, stamp, changed, promptScale)
    if not active and not pending then return end
    if promptScale ~= lastPromptScale then
        lastPromptScale = promptScale
        dirty = true
    end
    for index = 1, CELLS do
        local cell = cells[index]
        if not cell.group and cell.heldEntry and now - cell.releasedAt >= CELL_HOLD_MS then dirty = true end
    end
    if changed or dirty then
        sendState(now, stamp)
        return
    end
    resend(active, now)
    resend(pending, now)
end

-- Visible rows of a list (ui/surfaces/interactions.js getInteractionListWindow
-- plus the peek row), for the bottom-edge clamp.
local function visibleRows(cluster)
    local count = cluster.count
    if count <= 4 then return count end
    local selected = (cluster.selectedIndex or 1) - 1
    local start = math.max(0, math_min(count - 4, selected - 2))
    return 4 + ((start + 4 < count) and 1 or 0)
end

-- Whether a cell's content is painted in the active DUI.
local function revealed(cell, now)
    if cell.waitReveal then return false end
    local wanted = cell.revealRevision
    if not wanted then return true end
    if active.painted >= wanted or now >= cell.revealDeadline then
        cell.revealRevision = nil
        return true
    end
    return false
end

-- Draws every assigned list at its anchor. `ix`/`u` are the screen's prompt
-- unit and base unit in pixels.
function Dui.draw(now, clusters, count, screenWidth, screenHeight, ix, u)
    if not active or paused then return end
    local scale = ix / active.renderIx
    local width, height = active.cellWidth * scale, active.cellHeight * scale
    local spriteWidth, spriteHeight = width / screenWidth, height / screenHeight
    local cellU, cellV = active.cellWidth / active.width, active.cellHeight / active.height

    for clusterIndex = 1, count do
        local cluster = clusters[clusterIndex]
        local cellIndex = cluster.cell
        local cell = cellIndex and cells[cellIndex]
        if cell and revealed(cell, now) then
            local head = cluster.head
            local left = -(cell.flipped and active.anchorRight or active.anchorX) * scale
            local top = -active.anchorY * scale
            -- Keep the list above the bottom edge, as the NUI layer did.
            local estimate = 50 + math.max(0, visibleRows(cluster) - 1) * 36
            local maxY = screenHeight - estimate * ix - 24 * u
            if head.pixelY > maxY then top = top - (head.pixelY - maxY) end
            -- Whole pixels from this pass's projection: text stays sharp while
            -- the camera is still (a moving camera blurs nothing it keeps).
            left = left + math_floor(head.pixelX + left + 0.5) - (head.pixelX + left)
            top = top + math_floor(head.pixelY + top + 0.5) - (head.pixelY + top)

            local column = (cellIndex - 1) % COLUMNS
            local row = math_floor((cellIndex - 1) / COLUMNS)
            local u1, v1 = column * cellU, row * cellV
            SetDrawOrigin(head.worldX, head.worldY, head.worldZ, 0)
            DrawSpriteUv(TXD_NAME, active.textureName,
                (left + width * 0.5) / screenWidth, (top + height * 0.5) / screenHeight,
                spriteWidth, spriteHeight, u1, v1, u1 + cellU, v1 + cellV, 0.0, 255, 255, 255, 255)
            ClearDrawOrigin()
        end
    end
end

-- Mash-session messages (imports/skillCheck/client.lua): the dial renders in
-- its world prompt's key disc.
lib._interactionDuiMirror = function(message)
    local action = message.action
    if action == 'skill:open' then
        skillReplay = { message }
    elseif action == 'skill:close' then
        skillReplay = {}
    elseif action == 'skill:progress' then
        skillReplay.progress = message
    elseif action == 'skill:start' and #skillReplay == 1 then
        skillReplay[2] = message
    end
    if active then SendDuiMessage(active.object, json.encode(message)) end
end

local function readProfile(data)
    local value = type(data) == 'table' and data.profile
    if type(value) ~= 'table' then return end
    local next = { accent = value.accent, opacity = value.opacity, motion = value.motion }
    if not profile or profile.accent ~= next.accent or profile.opacity ~= next.opacity
        or profile.motion ~= next.motion
    then
        profile = next
        dirty = true
    end
end

AddEventHandler('cortex-lib:presentation', readProfile)
CreateThread(function()
    local ok, data = pcall(function() return exports[resourceName]:getPresentation() end)
    if ok then readProfile(data) end
end)

AddEventHandler('cortex-lib:pauseChanged', function(open)
    paused = open == true
end)

-- From ui/world.js: { dui = <serial>, revision = <painted content revision> }.
RegisterNUICallback('interactionWorldReady', function(data, cb)
    local id = type(data) == 'table' and tonumber(data.dui) or nil
    local painted = type(data) == 'table' and tonumber(data.revision) or 0
    for _, entry in pairs({ active, pending }) do
        if entry.serial == id then
            if not entry.reported then
                entry.reported = true
                -- Anything sent before the page listened is resent at once.
                entry.sentAt = 0
            end
            if painted and painted % 1 == 0 and painted > entry.painted and painted <= (entry.sentRevision or 0) then
                entry.painted = painted
            end
        end
    end
    cb({ ok = true })
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= resourceName then return end
    for index = 1, #retired do destroy(retired[index]) end
    destroy(pending)
    destroy(active)
    retired, pending, active = {}, nil, nil
end)

lib._interactionDui = Dui
