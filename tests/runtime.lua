local repository = assert(arg[1], "repository path required")
local bundled = assert(arg[2], "bundled entry required")
local Harness = dofile(repository .. "/tests/harness.lua")
local originalPath = repository .. "/tests/fixtures/original-main.lua"
local examplePath = repository .. "/examples/main.lua"

local function check(condition, message)
    if not condition then error(message, 2) end
end

local passed = 0
local function test(name, callback)
    callback()
    passed = passed + 1
    print("PASS " .. name)
end

local function sameState(original, extracted)
    check(original.now == extracted.now, "clock mismatch")
    check(original.image.properties.src == extracted.image.properties.src, "frame mismatch")
    check(#original.history == #extracted.history, "frame write count mismatch")
    check(original.timers[1].paused == extracted.timers[1].paused, "timer gate mismatch")
    check(original.label.properties.text == extracted.label.properties.text, "time label mismatch")
    for position = (extracted.compared_count or 0) + 1, #original.history do
        local originalEvent = original.history[position]
        local extractedEvent = extracted.history[position]
        check(originalEvent.source == extractedEvent.source, "intermediate frame mismatch")
        check(originalEvent.time == extractedEvent.time, "frame timestamp mismatch")
    end
    extracted.compared_count = #original.history
end

test("60000 ticks match the original player, module and single-file example", function()
    local original = Harness.new(repository, originalPath)
    local modular = Harness.new(repository, examplePath)
    local single = Harness.new(repository, bundled)
    for _ = 1, 60000 do
        original:advance(83)
        modular:advance(83)
        single:advance(83)
        sameState(original, modular)
        sameState(original, single)
    end
end)

test("6000 mixed lifecycle events match the original player", function()
    local original = Harness.new(repository, originalPath)
    local modular = Harness.new(repository, examplePath)
    local single = Harness.new(repository, bundled)
    local eventState = 173
    for _ = 1, 6000 do
        eventState = (eventState * 75 + 74) % 65521
        local action = eventState % 9
        for _, simulation in ipairs({ original, modular, single }) do
            if action == 0 then simulation:screen("OFF")
            elseif action == 1 then simulation:screen("ON")
            elseif action == 2 then simulation:pause()
            elseif action == 3 then simulation:resume()
            elseif action == 4 then simulation:click()
            elseif action == 5 then simulation:screen("AOD")
            elseif action == 6 then simulation:force_tick()
            elseif action == 7 then simulation.subscribers.timeMinuteLow(simulation.root, 0)
            else simulation:advance(eventState % 300) end
        end
        sameState(original, modular)
        sameState(original, single)
    end
    for _, simulation in ipairs({ modular, single }) do
        check(simulation.root_count == 1 and simulation.image_count == 1
            and simulation.label_count == 1 and #simulation.timers == 1, "objects recreated")
    end
end)

test("200 shuffle rounds per configuration contain each clip once", function()
    for _, counts in ipairs({ { 1 }, { 12 }, { 3, 7 }, { 1, 2, 3, 4, 6, 9, 12 },
        { 26, 30, 16, 30, 40, 21, 18, 49 } }) do
        local total = 0
        for _, count in ipairs(counts) do total = total + count end
        local first = Harness.new(repository, nil, { counts = counts })
        local replay = Harness.new(repository, nil, { counts = counts })
        first:advance(total * 83 * 200)
        replay:advance(total * 83 * 200)
        local starts, repeated = first:starts(), replay:starts()
        local orders = {}
        for round = 0, 199 do
            local seen, order = {}, {}
            for offset = 1, #counts do
                local position = round * #counts + offset
                local clip = starts[position]
                check(clip and not seen[clip], "clip repeated or omitted within a round")
                check(clip == repeated[position], "same salt/time did not replay")
                if position > 1 and #counts > 1 then
                    check(clip ~= starts[position - 1], "adjacent clips repeated")
                end
                seen[clip], order[offset] = true, clip
            end
            orders[table.concat(order, ",")] = true
        end
        if #counts >= 3 then
            local unique = 0
            for _ in pairs(orders) do unique = unique + 1 end
            check(unique > 1, "round order never changed")
        end
    end
end)

test("normal first and final frames dwell for exactly one period", function()
    local counts = { 1, 3, 7 }
    for _, period in ipairs({ 1, 83, 100, 250 }) do
        local simulation = Harness.new(repository, nil, { counts = counts, period = period })
        for _ = 1, #counts * 4 do
            local clip, frame = simulation:frame()
            check(frame == 1, "clip did not start at frame one")
            for frameIndex = 1, counts[clip] do
                simulation:advance(period - 1)
                local actualClip, actualFrame = simulation:frame()
                check(actualClip == clip and actualFrame == frameIndex, "frame changed early")
                simulation:advance(1)
            end
            local nextClip, nextFrame = simulation:frame()
            check(nextClip ~= clip and nextFrame == 1, "clip transition incorrect")
        end
    end
end)

test("sleep pauses, ignores stale ticks and taps, and wake consumes exactly one clip", function()
    local simulation = Harness.new(repository)
    local oracle = Harness.new(repository)
    oracle:click()
    local expected = oracle:frame()
    simulation:advance(23)
    simulation:screen("OFF")
    local writes, ticks = #simulation.history, simulation.tick_calls
    simulation:advance(60000)
    simulation:force_tick()
    check(not simulation:click(), "sleeping tap accepted")
    check(#simulation.history == writes and simulation.tick_calls == ticks, "sleep drew a frame")
    check(simulation.timers[1].paused, "sleeping timer runs")
    simulation:screen("ON")
    local clip, frame = simulation:frame()
    check(clip == expected and frame == 1, "wake resumed interrupted clip")
    writes = #simulation.history
    simulation:screen("ON")
    simulation:resume()
    simulation.player:start()
    check(#simulation.history == writes and simulation.resume_calls == 2, "duplicate hook consumed a clip")
    simulation:advance(0)
    simulation:advance(82)
    check(#simulation.history == writes, "overdue wake callback skipped frame one")
    simulation:advance(1)
    check(#simulation.history == writes + 1, "wake did not advance after a period")
end)

test("screen and page gates work in either callback order, including AOD", function()
    for order = 1, 2 do
        local simulation = Harness.new(repository)
        simulation:pause()
        simulation:screen("AOD")
        local writes = #simulation.history
        simulation:advance(10000)
        if order == 1 then simulation:resume() else simulation:screen("ON") end
        simulation:force_tick()
        check(#simulation.history == writes, "one gate resumed playback")
        if order == 1 then simulation:screen("ON") else simulation:resume() end
        check(#simulation.history == writes + 1, "both gates did not start exactly once")
        for _, state in ipairs({ "AOD", "OFF", "DIM", "on" }) do
            simulation:screen(state)
            writes = #simulation.history
            simulation:advance(10000)
            simulation:resume()
            simulation:force_tick()
            check(#simulation.history == writes and simulation.timers[1].paused, "non-ON state ran")
        end
        simulation:screen(nil)
        check(simulation.timers[1].paused, "nil screen state ran")
    end
end)

test("tap uses the same queue and protects frame one near a pending callback", function()
    local simulation = Harness.new(repository)
    local oracle = Harness.new(repository)
    oracle:advance(100000)
    local expected = oracle:starts()
    for position = 2, 40 do
        simulation:advance(82)
        check(simulation:click(), "visible tap ignored")
        local clip, frame = simulation:frame()
        check(clip == expected[position] and frame == 1, "tap bypassed shuffle bag")
        local writes = #simulation.history
        simulation:advance(1)
        check(#simulation.history == writes, "pending callback skipped tap frame one")
    end
end)

test("manual pause participates in both visibility gates", function()
    local simulation = Harness.new(repository)
    simulation.player:set_paused(true)
    local writes = #simulation.history
    simulation:screen("OFF")
    simulation:pause()
    simulation.player:set_paused(false)
    simulation:resume()
    check(simulation.timers[1].paused, "manual resume bypassed screen gate")
    simulation:screen("ON")
    check(#simulation.history == writes + 1, "unpause did not start next clip")
    simulation.player:set_paused(false)
    check(#simulation.history == writes + 1, "duplicate unpause consumed another clip")
end)

test("explicit startup respects initially hidden or sleeping pages", function()
    for _, settings in ipairs({ { auto_start = false }, { screen_on = false }, { page_visible = false } }) do
        local simulation = Harness.new(repository, nil, settings)
        local oracle = Harness.new(repository)
        check(#simulation.history == 0 and simulation.timers[1].paused, "started while gated")
        simulation:advance(10000)
        simulation:force_tick()
        simulation:click()
        simulation:screen("ON")
        simulation:resume()
        simulation.player:start()
        local clip, frame = simulation:frame()
        check(clip == oracle:frame() and frame == 1, "startup consumed an extra item")
        check(#simulation.history == 1, "startup was not idempotent")
    end
end)

test("overlay hooks share the visible timer and do not reseed on wake", function()
    local simulation = Harness.new(repository, nil, { counts = { 7, 7, 7 } })
    check(#simulation.clip_calls == 1 and simulation.resume_calls == 1, "initial hooks missing")
    simulation:advance(83)
    check(simulation.tick_calls == 1, "visible timer hook missing")
    simulation:click()
    simulation:advance(83)
    check(simulation.tick_calls == 2, "prime tick should still flush status")
    simulation:screen("OFF")
    simulation:advance(60000)
    simulation:force_tick()
    simulation:screen("ON")
    check(simulation.time_calls == 1, "wake reseeded RNG")
    check(#simulation.clip_calls == 3 and simulation.resume_calls == 2, "clip/resume hook mismatch")
    check(#simulation.timers == 1 and simulation.image_count == 1, "hook allocated playback objects")
end)

test("minute updates and wake refresh time without advancing hidden frames", function()
    for _, entry in ipairs({ examplePath, bundled }) do
        local simulation = Harness.new(repository, entry)
        local text = simulation.label.properties.text
        simulation:screen("OFF")
        simulation:advance(120000)
        local writes = #simulation.history
        simulation.subscribers.timeMinuteLow(simulation.root, 0)
        check(simulation.label.properties.text ~= text, "minute subscription did not refresh time")
        check(#simulation.history == writes, "minute subscription advanced a hidden frame")
        text = simulation.label.properties.text
        simulation:advance(120000)
        simulation:screen("ON")
        check(simulation.label.properties.text ~= text, "wake retained stale time")
    end
end)

test("frame paths include SCRIPT_PATH, JPEG extension and three-digit frame indices", function()
    local simulation = Harness.new(repository, nil, { counts = { 101 }, extension = "jpg" })
    simulation:advance(83 * 99)
    check(simulation.image.properties.src == "fixtures/face_100.jpg", "frame path padding wrong")
    check(simulation.timers[1].period == 83, "period changed")
end)

test("invalid configuration is rejected before playback object allocation", function()
    local invalid = {
        function(options) options.clips = {} end,
        function(options) options.clips = { [2] = { prefix = "w2", count = 3 } } end,
        function(options) options.clips.extra = {} end,
        function(options) options.clips[1].count = 0 end,
        function(options) options.clips[1].count = -1 end,
        function(options) options.clips[1].count = 1.5 end,
        function(options) options.clips[1].count = 0 / 0 end,
        function(options) options.clips[1].count = math.huge end,
        function(options) options.clips[1].prefix = "../frame" end,
        function(options) options.clips[1].period_ms = 100 end,
        function(options) options.period_ms = 0 end,
        function(options) options.period_ms = 83.5 end,
        function(options) options.seed_salt = 0 end,
        function(options) options.seed_salt = 2147483647 end,
        function(options) options.seed_salt = true end,
        function(options) options.extension = "mp4" end,
        function(options) options.on_tick = true end,
        function(options) options.screen_on = "ON" end,
    }
    for _, configure in ipairs(invalid) do
        local allocated = false
        local success = pcall(Harness.new, repository, nil, {
            configure = function(options)
                configure(options)
                local originalImage = options.root.Image
                local originalTimer = options.lvgl.Timer
                options.root.Image = function(...)
                    allocated = true
                    return originalImage(...)
                end
                options.lvgl.Timer = function(...)
                    allocated = true
                    return originalTimer(...)
                end
            end,
        })
        check(not success, "invalid configuration accepted")
        check(not allocated, "invalid configuration allocated playback objects")
    end
end)

print(string.format("%d runtime scenarios passed", passed))
