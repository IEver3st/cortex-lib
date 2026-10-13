-- Startup update notice: one GitHub request, one console line, off by convar.
local printed, requests, threads, convar, installed = {}, {}, {}, 1, '3.3.1'

json = {
    decode = function(text)
        local tag = text:match('"tag_name"%s*:%s*"([^"]*)"')
        if not tag then error('bad json') end
        return { tag_name = tag }
    end,
}
function print(line) printed[#printed + 1] = line end
function CreateThread(fn) threads[#threads + 1] = fn end
function GetConvarInt(name, default) assert(name == 'cortex_lib_version_check'); return convar end
function GetCurrentResourceName() return 'cortex-lib' end
function GetResourceMetadata(resource, key) assert(resource == 'cortex-lib' and key == 'version'); return installed end
function PerformHttpRequest(url, callback, method, _, headers)
    requests[#requests + 1] = { url = url, callback = callback, method = method, headers = headers }
end

local function run(status, body)
    printed, requests, threads = {}, {}, {}
    dofile('server/version_check.lua')
    assert(#threads == 1, 'loading starts one thread')
    threads[1]()
    if convar == 0 then return end
    assert(#requests == 1, 'one request per start')
    local request = requests[1]
    assert(request.url == 'https://api.github.com/repos/IEver3st/cortex-lib/releases/latest')
    assert(request.method == 'GET' and request.headers['User-Agent'], 'GitHub needs a User-Agent')
    request.callback(status, body)
end

local function expect(pattern, message)
    assert(#printed == 1 and printed[1]:find(pattern), message .. ': ' .. tostring(printed[1]))
end

run(200, '{"tag_name":"v3.4.0"}')
expect('Update available: ^2' .. '3.4.0', 'newer release is announced')
assert(printed[1]:find('installed 3.3.1', 1, true) and printed[1]:find('/releases/latest', 1, true))

run(200, '{"tag_name":"v3.3.1"}')
expect('up to date', 'same version is up to date')

run(200, '{"tag_name":"v3.3.0"}')
expect('up to date', 'older release is not announced')

run(200, '{"tag_name":"v3.10.0"}')
expect('Update available', 'numeric, not text, comparison')

installed = '3.3.1-rc.2'
run(200, '{"tag_name":"v3.3.1"}')
expect('Update available', 'a release is newer than its pre-release')
installed = '3.3.1'

run(403, '')
expect('Could not check for updates %(HTTP 403%)', 'API failure is one quiet line')

run(200, 'not json')
assert(#printed == 0, 'malformed body prints nothing')

convar = 0
run(200, '{"tag_name":"v9.0.0"}')
assert(#requests == 0 and #printed == 0, 'cortex_lib_version_check 0 disables the request')

print = nil
io.write('version check: newer/same/older/pre-release/HTTP failure/opt-out passed\n')
