local threads = {}
local playerCoords = { x = 0.0, y = 0.0, z = 0.0 }
local entered = 0
local exited = 0
local nearbyTicks = 0

lib = {}

function PlayerPedId() return 1 end
function GetEntityCoords(entity)
    assert(entity == 1)
    return playerCoords
end
function CreateThread(callback)
    threads[#threads + 1] = callback
end
function Wait()
    error('__point_tick_complete__')
end

local points = dofile('imports/points/client.lua')
assert(type(points.new) == 'function')
assert(#threads == 1, 'points should create only its low-frequency detector while idle')

local point = points.new({
    coords = { x = 1.0, y = 0.0, z = 0.0 },
    distance = 2.0,
    onEnter = function() entered = entered + 1 end,
    onExit = function() exited = exited + 1 end,
    nearby = function() nearbyTicks = nearbyTicks + 1 end,
})

local ok, err = pcall(threads[1])
assert(not ok and tostring(err):find('__point_tick_complete__', 1, true), tostring(err))
assert(entered == 1 and exited == 0)
assert(#threads == 2, 'the frame callback thread should start only after a point becomes nearby')

ok, err = pcall(threads[2])
assert(not ok and tostring(err):find('__point_tick_complete__', 1, true), tostring(err))
assert(nearbyTicks == 1)

playerCoords = { x = 10.0, y = 0.0, z = 0.0 }
ok, err = pcall(threads[1])
assert(not ok and tostring(err):find('__point_tick_complete__', 1, true), tostring(err))
assert(exited == 1)

ok, err = pcall(threads[2])
assert(ok, tostring(err))
assert(#threads == 2, 'leaving all points should stop rather than replace the frame callback thread')

point:remove()
print('points scheduler tests passed')
