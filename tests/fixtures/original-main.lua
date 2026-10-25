-- 小米手环 11 动态表盘
-- 8 张壁纸 / 共 230 帧
local lvgl = require("lvgl")
local dataman = require("dataman")

local SCRIPT_PATH = rawget(_G, "SCRIPT_PATH") or ""

local function imgPath(src)
    return SCRIPT_PATH .. src
end

-- 根对象
local root = lvgl.Object(nil, {
    w = lvgl.HOR_RES(),
    h = lvgl.VER_RES(),
    bg_color = 0x000000,
    bg_opa = lvgl.OPA(100),
    border_width = 0,
    pad_all = 0,
})
root:clear_flag(lvgl.FLAG.SCROLLABLE)
root:add_flag(lvgl.FLAG.EVENT_BUBBLE)

local WALLS = {
    { prefix = "face", count = 26, period = 83 },
    { prefix = "w2", count = 30, period = 83 },
    { prefix = "w3", count = 16, period = 83 },
    { prefix = "w4", count = 30, period = 83 },
    { prefix = "w5", count = 40, period = 83 },
    { prefix = "w6", count = 21, period = 83 },
    { prefix = "w7", count = 18, period = 83 },
    { prefix = "w8", count = 49, period = 83 },
}
for _, wall in ipairs(WALLS) do
    wall.srcs = {}
    for frameIndex = 1, wall.count do
        wall.srcs[frameIndex] = imgPath(string.format("%s_%02d.png", wall.prefix, frameIndex))
    end
end

local randomState = math.floor(((os.time() % 2147483646) + 338129365 * 1.0) % 2147483646) + 1
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
local lastWall = nil
local function takeNextWall()
    if bagPosition > #bag then
        for wallIndex = 1, #WALLS do bag[wallIndex] = wallIndex end
        for wallIndex = #bag, 2, -1 do
            local swapIndex = randomIndex(wallIndex)
            bag[wallIndex], bag[swapIndex] = bag[swapIndex], bag[wallIndex]
        end
        if #bag > 1 and bag[1] == lastWall then
            local swapIndex = randomIndex(#bag - 1) + 1
            bag[1], bag[swapIndex] = bag[swapIndex], bag[1]
        end
        bagPosition = 1
    end
    local nextWall = bag[bagPosition]
    bagPosition = bagPosition + 1
    lastWall = nextWall
    return nextWall
end

local screenOn = true
local pageVisible = true
local animPaused = false
local running = false
local needNext = true
local activeWall = nil
local currentFrame = 1
local primeTick = false
local timerHasStarted = false
local image = root:Image { src = WALLS[1].srcs[1] }
image:set {
    w = lvgl.HOR_RES(), h = lvgl.VER_RES(),
    align = { type = lvgl.ALIGN.TOP_MID, x_ofs = 0, y_ofs = 0 },
}

local function showNext()
    activeWall = takeNextWall()
    currentFrame = 1
    image:set { src = WALLS[activeWall].srcs[1] }
end

local timer = lvgl.Timer {
    period = 83,
    cb = function()
        if not running or not screenOn or not pageVisible or animPaused then return end
        if primeTick then
            primeTick = false
            return
        end
        local wall = WALLS[activeWall]
        if currentFrame < wall.count then
            currentFrame = currentFrame + 1
            image:set { src = wall.srcs[currentFrame] }
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

local function skipNext()
    if not running then return end
    showNext()
    primeTick = true
end

-- ===== 时间 / 日期（叠加在动图上，位置由工具生成）=====
local infoVisible = true
local timeLabel = lvgl.Label(root, {
    text = "",
    text_font = lvgl.Font("montserrat", 48, "normal"),
    text_color = 0xFFFFFF,
    align = { type = lvgl.ALIGN.BOTTOM_MID, x_ofs = 0, y_ofs = -30 },
})

local function refreshTime()
    local t = os.time()
    timeLabel:set { text = os.date("%H:%M", t) }
end

refreshTime()
pcall(function()
    dataman.subscribe("timeMinuteLow", root, function(obj, value)
        refreshTime()
    end)
end)

local function setInfoVisible(v)
    infoVisible = v
    if timeLabel then
        if v then timeLabel:clear_flag(lvgl.FLAG.HIDDEN) else timeLabel:add_flag(lvgl.FLAG.HIDDEN) end
    end
end

local function updatePlayback()
    if screenOn and pageVisible and not animPaused then
        if resumeActive() then refreshTime() end
    else
        pauseAll()
    end
end

pageOnPause = function()
    pageVisible = false
    updatePlayback()
end

pageOnResume = function()
    pageVisible = true
    updatePlayback()
end

function ScreenStateChangedCB(pre, now, reason)
    screenOn = now == "ON"
    updatePlayback()
end

updatePlayback()

-- ===== 点击交互：短按播放队列下一段 =====
root:add_flag(lvgl.FLAG.CLICKABLE)

root:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
    skipNext()
end)
