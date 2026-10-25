local Harness = {}

local function loadInEnvironment(path, environment)
    if setfenv then
        local chunk = assert(loadfile(path))
        setfenv(chunk, environment)
        return chunk()
    end
    return assert(loadfile(path, "t", environment))()
end

local function decode(source)
    local prefix, frame = source:match("([^/]+)_(%d+)%.%w+$")
    assert(prefix, "unexpected frame path: " .. source)
    return prefix == "face" and 1 or tonumber(prefix:match("^w(%d+)$")), tonumber(frame)
end

function Harness.new(repository, entry, settings)
    settings = settings or {}
    local simulation = {
        now = 0, history = {}, timers = {}, subscribers = {},
        root_count = 0, image_count = 0, label_count = 0,
        clip_calls = {}, tick_calls = 0, resume_calls = 0, time_calls = 0,
    }
    local function object(kind, properties)
        local instance = { properties = properties or {}, flags = {}, events = {} }
        function instance:set(values)
            for key, value in pairs(values) do self.properties[key] = value end
            if kind == "image" and values.src then
                local clip, frame = decode(values.src)
                simulation.history[#simulation.history + 1] = {
                    clip = clip, frame = frame, time = simulation.now, source = values.src,
                }
            end
        end
        function instance:add_flag(flag) self.flags[flag] = true end
        function instance:clear_flag(flag) self.flags[flag] = nil end
        function instance:onevent(event, callback) self.events[event] = callback end
        function instance:Image(values)
            simulation.image_count = simulation.image_count + 1
            simulation.image = object("image", values)
            return simulation.image
        end
        return instance
    end
    local lvgl = {
        FLAG = { SCROLLABLE = 1, EVENT_BUBBLE = 2, HIDDEN = 3, CLICKABLE = 4 },
        EVENT = { SHORT_CLICKED = 1 }, ALIGN = { TOP_MID = 1, BOTTOM_MID = 2 },
        HOR_RES = function() return 212 end, VER_RES = function() return 520 end,
        OPA = function(value) return value end,
        Font = function() return "mock-font" end,
    }
    function lvgl.Object(parent, properties)
        simulation.root_count = simulation.root_count + 1
        simulation.root = object("root", properties)
        return simulation.root
    end
    function lvgl.Label(parent, properties)
        simulation.label_count = simulation.label_count + 1
        simulation.label = object("label", properties)
        return simulation.label
    end
    function lvgl.Timer(properties)
        local timer = { period = properties.period, cb = properties.cb,
            last = simulation.now, paused = false }
        function timer:pause() self.paused = true end
        function timer:resume() self.paused = false end
        simulation.timers[#simulation.timers + 1] = timer
        return timer
    end
    local dataman = {}
    function dataman.subscribe(topic, parent, callback)
        assert(simulation.subscribers[topic] == nil, "duplicate subscription")
        simulation.subscribers[topic] = callback
    end
    local environment = setmetatable({}, { __index = _G })
    environment._G = environment
    environment.SCRIPT_PATH = "fixtures/"
    environment.os = {
        time = function()
            simulation.time_calls = simulation.time_calls + 1
            return (settings.epoch or 1700000000) + math.floor(simulation.now / 1000)
        end,
        date = os.date,
    }
    environment.math = setmetatable({
        random = function() error("global math.random used") end,
        randomseed = function() error("global math.randomseed used") end,
    }, { __index = math })
    environment.require = function(name)
        if name == "lvgl" then return lvgl end
        if name == "dataman" then return dataman end
        if name == "shuffle_player" then
            return loadInEnvironment(repository .. "/src/shuffle_player.lua", environment)
        end
        error("unexpected module: " .. name)
    end

    if entry then
        loadInEnvironment(entry, environment)
    else
        local clips = {}
        for clipIndex, count in ipairs(settings.counts or { 3, 7, 1 }) do
            clips[clipIndex] = { prefix = clipIndex == 1 and "face" or "w" .. clipIndex, count = count }
        end
        local options = {
            lvgl = lvgl, root = lvgl.Object(nil, {}), clips = clips,
            period_ms = settings.period or 83, seed_salt = settings.salt or 338129365,
            extension = settings.extension,
            screen_on = settings.screen_on, page_visible = settings.page_visible,
            img_path = function(source) return environment.SCRIPT_PATH .. source end,
            on_clip = function(clip) simulation.clip_calls[#simulation.clip_calls + 1] = clip end,
            on_tick = function() simulation.tick_calls = simulation.tick_calls + 1 end,
            on_resume = function() simulation.resume_calls = simulation.resume_calls + 1 end,
        }
        if settings.configure then settings.configure(options) end
        simulation.player = environment.require("shuffle_player").new(options)
        if settings.auto_start ~= false then simulation.player:start() end
    end
    simulation.environment = environment

    function simulation:advance(milliseconds)
        local target = self.now + milliseconds
        local callbacks = 0
        while true do
            local nextTimer, nextTime = nil, target + 1
            for _, timer in ipairs(self.timers) do
                local due = math.max(self.now, timer.last + timer.period)
                if not timer.paused and due <= target and due < nextTime then
                    nextTimer, nextTime = timer, due
                end
            end
            if not nextTimer then break end
            self.now = nextTime
            nextTimer.last = self.now
            nextTimer.cb(nextTimer)
            callbacks = callbacks + 1
            assert(callbacks < 1000000, "timer failed to make progress")
        end
        self.now = target
    end
    function simulation:screen(state)
        if self.player then self.player:set_screen_state(state)
        else self.environment.ScreenStateChangedCB("ignored", state, "simulation") end
    end
    function simulation:pause()
        if self.player then self.player:set_page_visible(false)
        else self.environment.pageOnPause() end
    end
    function simulation:resume()
        if self.player then self.player:set_page_visible(true)
        else self.environment.pageOnResume() end
    end
    function simulation:click()
        if self.player then return self.player:skip_next() end
        self.root.events[lvgl.EVENT.SHORT_CLICKED](self.root, 1)
    end
    function simulation:frame() return decode(self.image.properties.src) end
    function simulation:starts()
        local starts = {}
        for _, event in ipairs(self.history) do
            if event.frame == 1 then starts[#starts + 1] = event.clip end
        end
        return starts
    end
    function simulation:force_tick() self.timers[1].cb(self.timers[1]) end
    return simulation
end

return Harness
