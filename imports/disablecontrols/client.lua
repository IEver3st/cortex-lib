local DisableControlAction = DisableControlAction
local DisablePlayerFiring = DisablePlayerFiring
local DisableAllControlActions = DisableAllControlActions
local PlayerId = PlayerId
local Wait = Wait

local CONTROL_GROUPS = {
    movement = {30, 31, 32, 33, 34, 35, 36, 21, 22, 44, 45, 269, 270},
    carMovement = {59, 60, 71, 72, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90},
    combat = {24, 25, 37, 47, 58, 140, 141, 142, 143, 257, 263, 264, 265},
    mouse = {1, 2, 106}
}

local CONTROL_MAP = {
    INPUT_LOOK_LR = 1,
    INPUT_LOOK_UD = 2,
    INPUT_ATTACK = 24,
    INPUT_AIM = 25,
    INPUT_MOVE_LR = 30,
    INPUT_MOVE_UD = 31,
    INPUT_DUCK = 36,
    INPUT_VEH_MOVE_LR = 59,
    INPUT_VEH_MOVE_UD = 60,
    INPUT_VEH_ACCELERATE = 71,
    INPUT_VEH_BRAKE = 72,
    INPUT_VEH_EXIT = 75,
    INPUT_VEH_HANDBRAKE = 76,
    INPUT_JUMP = 22,
    INPUT_SPRINT = 21,
    INPUT_ENTER = 23,
    INPUT_RELOAD = 45,
    INPUT_MELEE_ATTACK = 140,
    INPUT_VEH_ATTACK = 69,
    INPUT_VEH_ATTACK2 = 68,
    INPUT_COVER = 44
}

local DisableControls = {}
DisableControls.__index = DisableControls

local function readBooleanOption(options, primary, alias)
    local primaryValue = options[primary]
    local aliasValue = alias and options[alias] or nil

    if primaryValue ~= nil and type(primaryValue) ~= 'boolean' then
        error(('lib.disableControls option %s must be a boolean'):format(primary), 3)
    end

    if aliasValue ~= nil and type(aliasValue) ~= 'boolean' then
        error(('lib.disableControls option %s must be a boolean'):format(alias), 3)
    end

    return primaryValue == true or aliasValue == true
end

local function normalizeControl(control)
    if type(control) == 'string' then
        control = CONTROL_MAP[control]
    end

    if type(control) ~= 'number' or control ~= control or
       control <= -math.huge or control >= math.huge or
       control % 1 ~= 0 or control < 0 or control > 360 then
        return nil
    end

    return control
end


local function hasWork(self)
    return self._active and (
        self._disableAll or
        self._disableMovement or
        self._disableCarMovement or
        self._disableCombat or
        self._disableMouse or
        next(self._controls) ~= nil
    )
end

local function startThread(self)
    if self._threadActive or not hasWork(self) then return end

    self._threadActive = true
    CreateThread(function()
        while hasWork(self) do
            if self._disableAll then
                DisableAllControlActions(0)
            else
                if self._disableMovement then
                    for _, control in ipairs(CONTROL_GROUPS.movement) do
                        DisableControlAction(0, control, true)
                    end
                end

                if self._disableCarMovement then
                    for _, control in ipairs(CONTROL_GROUPS.carMovement) do
                        DisableControlAction(0, control, true)
                    end
                end

                if self._disableCombat then
                    for _, control in ipairs(CONTROL_GROUPS.combat) do
                        DisableControlAction(0, control, true)
                    end
                    DisablePlayerFiring(PlayerId(), true)
                end

                if self._disableMouse then
                    for _, control in ipairs(CONTROL_GROUPS.mouse) do
                        DisableControlAction(0, control, true)
                    end
                end

                for control in pairs(self._controls) do
                    DisableControlAction(0, control, true)
                end
            end

            Wait(0)
        end

        self._threadActive = false
    end)
end

local function disableControls(options)
    options = options or {}
    if type(options) ~= 'table' then
        error('lib.disableControls options must be a table', 2)
    end

    local self = setmetatable({
        _active = true,
        _threadActive = false,
        _controls = {},
        _disableMovement = readBooleanOption(options, 'disableMovement', 'move'),
        _disableCarMovement = readBooleanOption(options, 'disableCarMovement', 'car'),
        _disableCombat = readBooleanOption(options, 'disableCombat', 'combat'),
        _disableMouse = readBooleanOption(options, 'disableMouse', 'mouse'),
        _disableAll = readBooleanOption(options, 'disableAll')
    }, DisableControls)

    startThread(self)
    return self
end

function DisableControls:Add(control)
    control = normalizeControl(control)
    if control then
        self._controls[control] = true
        startThread(self)
    end

    return self
end

function DisableControls:Remove(control)
    control = normalizeControl(control)
    if control then
        self._controls[control] = nil
    end

    return self
end

function DisableControls:Clear()
    self._controls = {}
    return self
end

function DisableControls:Destroy()
    self._active = false
    self._controls = {}
end

DisableControls.destroy = DisableControls.Destroy

exports('disableControls', disableControls)

lib.disableControls = disableControls

return disableControls
