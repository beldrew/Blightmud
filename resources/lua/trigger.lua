local mod = {}

--------------------------------------------------------------------------------
-- Trigger ---------------------------------------------------------------------
--------------------------------------------------------------------------------

-- next_id should be global over all TriggerGroups so that an ID can uniquely
-- identify a trigger
local next_id = 1

mod.Trigger = {}
local Trigger = mod.Trigger
Trigger.__index = Trigger

function Trigger.new(re, options, callback)
    local ret = setmetatable({}, Trigger)

    ret.regex = regex.new(re)
    ret.callback = callback
    ret.gag = options.gag or false
    ret.raw = options.raw or false
    ret.prompt = options.prompt or false
    ret.count = options.count or nil
    ret.enabled = true
    if options.enabled ~= nil then
        ret.enabled = options.enabled
    end
    ret.id = next_id
    next_id = next_id + 1

    return ret
end

function Trigger.is_trigger(obj)
    return getmetatable(obj) == Trigger
end

function Trigger:enable()
    self.enabled = true
end

function Trigger:disable()
    self.enabled = false
end

function Trigger:set_enabled(flag)
    self.enabled = flag
end

function Trigger:is_enabled()
    return self.enabled
end

function Trigger:check_line(line)
    if not self.enabled then
        return
    end
    if line:prompt() ~= self.prompt then return end
    local str
    if self.raw then
        str = line:raw()
    else
        str = line:line()
    end

    local matches = self.regex:match(str)
    if matches then
        if self.gag then
            line:gag(true)
        end
        line:matched(true)
        if self.count and self.count > 0 then
            self.count = self.count - 1
        end

        local startTime = os.time()
        debug.sethook(function ()
            if os.time() > startTime + 2 then
                debug.sethook()
                error("Trigger callback has been running for +2 seconds. Aborting", 2)
            end
        end, "", 500)
    self.callback(matches, line)
    debug.sethook()
end
end

--------------------------------------------------------------------------------
-- TriggerGroup ----------------------------------------------------------------
--------------------------------------------------------------------------------

local next_group_id = 2

mod.TriggerGroup = {
}
local TriggerGroup = mod.TriggerGroup
TriggerGroup.__index = TriggerGroup

function TriggerGroup.new(id)
    local ret = setmetatable({}, TriggerGroup)

    ret.id = id
    ret.enabled = true
    ret.triggers = {}

    return ret
end

function TriggerGroup:add(regex_or_trigger, options, callback)
    local trigger
    if Trigger.is_trigger(regex_or_trigger) then
        trigger = regex_or_trigger
    else
        trigger = Trigger.new(regex_or_trigger, options, callback)
    end
    self.triggers[trigger.id] = trigger
    return trigger
end

function TriggerGroup:get(id)
    return self.triggers[id]
end

function TriggerGroup:get_triggers()
    return self.triggers
end

function TriggerGroup:remove(id)
    self.triggers[id] = nil
end

function TriggerGroup:clear()
    self.triggers = {}
end

function TriggerGroup:is_enabled()
    return self.enabled
end

function TriggerGroup:set_enabled(flag)
    self.enabled = flag
end

function TriggerGroup:enable()
    self.enabled = true
end

function TriggerGroup:disable()
    self.enabled = false
end

function TriggerGroup:check_line(line)
    if not self.enabled then
        return
    end
    local toRemove = {}
    for _, trigger in pairs(self.triggers) do
        trigger:check_line(line)
        if trigger.count == 0 then
            toRemove[#toRemove + 1] = trigger.id
        end
    end
    for _, trigger in ipairs(toRemove) do
        self:remove(trigger)
    end
end

--------------------------------------------------------------------------------
-- module ----------------------------------------------------------------------
--------------------------------------------------------------------------------

mod.trigger_groups = {
    TriggerGroup.new(1)
}
local user_trigger_groups = mod.trigger_groups

mod.system_trigger_groups = {
    TriggerGroup.new(1)
}
local system_trigger_groups = mod.system_trigger_groups

local function get_trigger_groups()
    if blight.is_core_mode() then
        return system_trigger_groups
    end
    return user_trigger_groups
end

function mod.add(regex, options, callback)
    return get_trigger_groups()[1]:add(regex, options, callback)
end

function mod.get(id)
    for _, group in pairs(get_trigger_groups()) do
        local trigger = group:get(id)
        if trigger then return trigger end
    end
    return nil
end

function mod.get_group(id)
    if not id then id = 1 end
    return get_trigger_groups()[id]
end

function mod.remove(id)
    for _, group in pairs(get_trigger_groups()) do
        group:remove(id)
    end
end

function mod.clear()
    for _, group in pairs(get_trigger_groups()) do
        group:clear()
    end
end

function mod.add_group()
    local ret = TriggerGroup.new(next_group_id)
    get_trigger_groups()[next_group_id] = ret
    next_group_id = next_group_id + 1

    return ret
end

mud.add_output_listener(function(line)
    for _, group in pairs(system_trigger_groups) do
        group:check_line(line)
    end
    for _, group in pairs(user_trigger_groups) do
        group:check_line(line)
    end
    return line
end)

return mod
