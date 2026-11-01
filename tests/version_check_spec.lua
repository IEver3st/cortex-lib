-- Startup banner and update notice: one GitHub request, the Cortex banner, a
-- status line with the update link only when outdated, off by convar.
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

local function has(text, message)
    local output = table.concat(printed, '\n')
    assert(output:find(text, 1, true), message .. ': missing ' .. text .. '\n' .. output)
end

local function lacks(text, message)
    local output = table.concat(printed, '\n')
    assert(not output:find(text, 1, true), message .. ': unexpected ' .. text .. '\n' .. output)
end

-- Banner and version lines print on every checked start, and no line leaves a
-- colour set for the next resource's output.
local function expectBanner(latest)
    has('[Cortex] My Version: [' .. installed .. ']', 'installed version line')
    has('[Cortex] Latest Version: [' .. latest .. ']', 'latest version line')
    has('▄████▄   ▒█████', 'CORTEX art')
    has('CORTEX LIB', 'product line')
    for _, line in ipairs(printed) do
        local last
        for code in line:gmatch('%^(%d)') do last = code end
        assert(last == nil or last == '7', 'colour leaks past: ' .. line)
    end
end

run(200, '{"tag_name":"v3.4.0"}')
expectBanner('v3.4.0')
has('Update available: 3.4.0 (installed 3.3.1)', 'newer release is announced')
has('Update now at ^5https://gsdmods.com/scripts', 'update link')

run(200, '{"tag_name":"v3.3.1"}')
expectBanner('v3.3.1')
has('[Cortex] Up to date!', 'same version is up to date')
lacks('https://', 'no link when current')

run(200, '{"tag_name":"v3.3.0"}')
has('[Cortex] Up to date!', 'older release is not announced')

run(200, '{"tag_name":"v3.10.0"}')
has('Update available', 'numeric, not text, comparison')

installed = '3.3.1-rc.2'
run(200, '{"tag_name":"v3.3.1"}')
has('Update available', 'a release is newer than its pre-release')
installed = '3.3.1'

run(403, '')
expectBanner('unknown')
has('Could not check for updates (HTTP 403)', 'API failure is one quiet line')

run(200, 'not json')
expectBanner('unknown')
has('Could not read the release versions', 'malformed body does not throw')

convar = 0
run(200, '{"tag_name":"v9.0.0"}')
assert(#requests == 0 and #printed == 0, 'cortex_lib_version_check 0 disables the request')

print = nil
io.write('version check: banner/newer/same/older/pre-release/HTTP failure/malformed/opt-out passed\n')
