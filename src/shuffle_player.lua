local ShufflePlayer = {}

local function positiveInteger(value, name, maximum)
    assert(type(value) == "number" and value > 0 and value < math.huge
        and value == math.floor(value) and (not maximum or value <= maximum),
        name .. " must be a positive integer" .. (maximum and " <= " .. maximum or ""))
    return value
end

function ShufflePlayer.new(options)
    assert(type(options) == "table", "options must be a table")
    local lvgl = assert(options.lvgl, "lvgl is required")
    local root = assert(options.root, "root is required")
    local period = positiveInteger(options.period_ms, "period_ms")
    local salt = positiveInteger(options.seed_salt, "seed_salt", 2147483646)
    local extension = options.extension or "png"
    assert(extension == "png" or extension == "jpg", "extension must be png or jpg")
    assert(type(options.clips) == "table" and #options.clips > 0, "clips must not be empty")
    for key in pairs(options.clips) do
        assert(type(key) == "number" and key == math.floor(key)
            and key >= 1 and key <= #options.clips, "clips must be a dense array")
    end
    for _, name in ipairs({ "on_clip", "on_tick", "on_resume", "img_path", "time" }) do
        assert(options[name] == nil or type(options[name]) == "function", name .. " must be a function")
    end
    for _, name in ipairs({ "screen_on", "page_visible" }) do
        assert(options[name] == nil or type(options[name]) == "boolean", name .. " must be a boolean")
    end

    local imgPath = options.img_path or function(source) return source end
    local clips = {}
    for clipIndex = 1, #options.clips do
        local clip = options.clips[clipIndex]
        assert(type(clip) == "table", "clips must be a dense array of tables")
        assert(type(clip.prefix) == "string" and clip.prefix:match("^[A-Za-z_][A-Za-z0-9_]*$"),
            "clip prefix must be an identifier")
        local count = positiveInteger(clip.count, "clip count")
        assert(clip.period_ms == nil or clip.period_ms == period, "all clips must use period_ms")
        local sources = {}
        for frameIndex = 1, count do
            sources[frameIndex] = imgPath(string.format("%s_%02d.%s", clip.prefix, frameIndex, extension))
        end
        clips[clipIndex] = { sources = sources, count = count }
    end

    local time = options.time or os.time
    local randomState = math.floor(((time() % 2147483646) + salt * 1.0) % 2147483646) + 1
    local function randomIndex(limit)
        local ceiling = 2147483646 - (2147483646 % limit)
        while true do
            local high = math.floor(randomState / 127773)
            local low = randomState % 127773
            randomState = 16807 * low - 2836 * high
            if randomState <= 0 then randomState = randomState + 2147483647 end
            local value = randomState - 1
            if value < ceiling then return value % limit + 1 end
        end
    end

    local bag = {}
    local bagPosition = 1
    local lastClip = nil
    local function takeNextClip()
        if bagPosition > #bag then
            for clipIndex = 1, #clips do bag[clipIndex] = clipIndex end
            for clipIndex = #bag, 2, -1 do
                local swapIndex = randomIndex(clipIndex)
                bag[clipIndex], bag[swapIndex] = bag[swapIndex], bag[clipIndex]
            end
            if #bag > 1 and bag[1] == lastClip then
                local swapIndex = randomIndex(#bag - 1) + 1
                bag[1], bag[swapIndex] = bag[swapIndex], bag[1]
            end
            bagPosition = 1
        end
        local nextClip = bag[bagPosition]
        bagPosition = bagPosition + 1
        lastClip = nextClip
        return nextClip
    end

    local screenOn = options.screen_on ~= false
    local pageVisible = options.page_visible ~= false
    local animPaused = false
    local started = false
    local running = false
    local needNext = true
    local activeClip = nil
    local currentFrame = 1
    local primeTick = false
    local timerHasStarted = false
    local onClip = options.on_clip
    local onTick = options.on_tick
    local onResume = options.on_resume
    local image = root:Image { src = clips[1].sources[1] }
    image:set {
        w = lvgl.HOR_RES(), h = lvgl.VER_RES(),
        align = { type = lvgl.ALIGN.TOP_MID, x_ofs = 0, y_ofs = 0 },
    }

    local function showNext()
        activeClip = takeNextClip()
        currentFrame = 1
        image:set { src = clips[activeClip].sources[1] }
        if onClip then onClip(activeClip) end
    end

    local timer = lvgl.Timer {
        period = period,
        cb = function()
            if not running or not screenOn or not pageVisible or animPaused then return end
            if onTick then onTick() end
            if primeTick then
                primeTick = false
                return
            end
            local clip = clips[activeClip]
            if currentFrame < clip.count then
                currentFrame = currentFrame + 1
                image:set { src = clip.sources[currentFrame] }
            else
                showNext()
            end
        end,
    }
    timer:pause()

    local function pauseAll()
        running = false
        needNext = true
        primeTick = false
        timer:pause()
    end

    local function resumeActive()
        if running or not screenOn or not pageVisible or animPaused then return false end
        if needNext then
            showNext()
            needNext = false
        end
        primeTick = timerHasStarted
        timerHasStarted = true
        running = true
        timer:resume()
        return true
    end

    local function updatePlayback()
        if started and screenOn and pageVisible and not animPaused then
            if resumeActive() and onResume then onResume() end
        else
            pauseAll()
        end
    end

    local player = {}

    function player:start()
        started = true
        updatePlayback()
    end

    function player:set_screen_state(state)
        screenOn = state == "ON"
        updatePlayback()
    end

    function player:set_page_visible(visible)
        assert(type(visible) == "boolean", "visible must be a boolean")
        pageVisible = visible
        updatePlayback()
    end

    function player:set_paused(paused)
        assert(type(paused) == "boolean", "paused must be a boolean")
        animPaused = paused
        updatePlayback()
    end

    function player:skip_next()
        if not running then return false end
        showNext()
        primeTick = true
        return true
    end

    return player
end

return ShufflePlayer
