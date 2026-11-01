-- Startup banner and update notice. Asks GitHub once for the latest stable
-- release, prints the Cortex banner, then whether this install is current.
-- Owners turn it off with: set cortex_lib_version_check 0
local REPOSITORY = 'IEver3st/cortex-lib'
local API_URL = ('https://api.github.com/repos/%s/releases/latest'):format(REPOSITORY)
local UPDATE_URL = 'https://gsdmods.com/scripts'

-- Console colour persists across prints, so every line sets its own and resets.
local BANNER = [==[
^7     ▄████▄   ▒█████   ██▀███  ▄▄▄█████▓▓█████ ▒██   ██▒
    ▒██▀ ▀█  ▒██▒  ██▒▓██ ▒ ██▒▓  ██▒ ▓▒▓█   ▀ ▒▒ █ █ ▒░
    ▒▓█    ▄ ▒██░  ██▒▓██ ░▄█ ▒▒ ▓██░ ▒░▒███   ░░  █   ░
    ▒▓▓▄ ▄██▒▒██   ██░▒██▀▀█▄  ░ ▓██▓ ░ ▒▓█  ▄  ░ █ █ ▒
    ▒ ▓███▀ ░░ ████▓▒░░██▓ ▒██▒  ▒██▒ ░ ░▒████▒▒██▒ ▒██▒
    ░ ░▒ ▒  ░░ ▒░▒░▒░ ░ ▒▓ ░▒▓░  ▒ ░░   ░░ ▒░ ░▒▒ ░ ░▓ ░
      ░  ▒     ░ ▒ ▒░   ░▒ ░ ▒░    ░     ░ ░  ░░░   ░▒ ░
    ░        ░ ░ ░ ▒    ░░   ░   ░         ░    ░    ░
    ░ ░          ░ ░     ░                 ░  ░ ░    ░
    ░

    CORTEX LIB
    by Ever3st, GSD Modifications
    ^2Loaded^7
]==]

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
    local latestText
    if status == 200 and type(body) == 'string' then
        local ok, release = pcall(json.decode, body)
        if ok and type(release) == 'table' and type(release.tag_name) == 'string' then
            latestText = release.tag_name
        end
    end
    local latest, current = parseVersion(latestText), parseVersion(installed)

    print(('^7[Cortex] My Version: [%s]'):format(installed or 'unknown'))
    print(('^7[Cortex] Latest Version: [%s]'):format(latestText or 'unknown'))
    print(BANNER)

    if status ~= 200 then
        print(('^3[Cortex] Could not check for updates (HTTP %s).^7'):format(tostring(status)))
    elseif not latest or not current then
        print('^3[Cortex] Could not read the release versions.^7')
    elseif compareVersions(latest, current) > 0 then
        print(('^3[Cortex] Update available: %s (installed %s).^7'):format(latestText:gsub('^v', ''), installed))
        print(('^3[Cortex] Update now at ^5%s^7'):format(UPDATE_URL))
    else
        print('^2[Cortex] Up to date!^7')
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
