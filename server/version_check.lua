-- Startup update notice. Asks GitHub once for the latest stable release and
-- prints one console line when it is newer than this install.
-- Owners turn it off with: set cortex_lib_version_check 0
local REPOSITORY = 'IEver3st/cortex-lib'
local RELEASES_URL = ('https://github.com/%s/releases/latest'):format(REPOSITORY)
local API_URL = ('https://api.github.com/repos/%s/releases/latest'):format(REPOSITORY)

local function parseVersion(value)
    if type(value) ~= 'string' then return nil end
    local major, minor, patch, pre = value:match('^v?(%d+)%.(%d+)%.(%d+)%-?([%w%.%-]*)')
    if not major then return nil end
    return { tonumber(major), tonumber(minor), tonumber(patch), pre ~= '' and pre or nil }
end

-- -1, 0 or 1 by semver precedence; a pre-release sorts below its release.
local function compareVersions(a, b)
    for i = 1, 3 do
        if a[i] ~= b[i] then return a[i] < b[i] and -1 or 1 end
    end
    if a[4] == b[4] then return 0 end
    if not a[4] then return 1 end
    if not b[4] then return -1 end
    local left, right = {}, {}
    for part in a[4]:gmatch('[^%.]+') do left[#left + 1] = part end
    for part in b[4]:gmatch('[^%.]+') do right[#right + 1] = part end
    for i = 1, math.min(#left, #right) do
        local x, y = tonumber(left[i]), tonumber(right[i])
        if x and y then
            if x ~= y then return x < y and -1 or 1 end
        elseif x or y then
            return x and -1 or 1
        elseif left[i] ~= right[i] then
            return left[i] < right[i] and -1 or 1
        end
    end
    if #left == #right then return 0 end
    return #left < #right and -1 or 1
end

local function report(status, body, installed)
    if status ~= 200 or type(body) ~= 'string' then
        print(('^3[cortex-lib]^7 Could not check for updates (HTTP %s).'):format(tostring(status)))
        return
    end
    local ok, release = pcall(json.decode, body)
    local latestText = ok and type(release) == 'table' and release.tag_name or nil
    local latest, current = parseVersion(latestText), parseVersion(installed)
    if not latest or not current then return end
    local tag = latestText:gsub('^v', '')
    if compareVersions(latest, current) > 0 then
        print(('^3[cortex-lib]^7 Update available: ^2%s^7 (installed %s). Download: %s'):format(tag, installed, RELEASES_URL))
    else
        print(('^2[cortex-lib]^7 Version %s is up to date.'):format(installed))
    end
end

CreateThread(function()
    if GetConvarInt('cortex_lib_version_check', 1) == 0 then return end
    local installed = GetResourceMetadata(GetCurrentResourceName(), 'version', 0)
    PerformHttpRequest(API_URL, function(status, body)
        report(status, body, installed)
    end, 'GET', '', {
        ['Accept'] = 'application/vnd.github+json',
        ['User-Agent'] = 'cortex-lib-version-check',
    })
end)
