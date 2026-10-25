local lvgl = require("lvgl")
local dataman = require("dataman")
local ShufflePlayer = require("shuffle_player")

local scriptPath = rawget(_G, "SCRIPT_PATH") or ""
local root = lvgl.Object(nil, {
    w = lvgl.HOR_RES(), h = lvgl.VER_RES(),
    bg_color = 0x000000, bg_opa = lvgl.OPA(100),
    border_width = 0, pad_all = 0,
})
root:clear_flag(lvgl.FLAG.SCROLLABLE)
root:add_flag(lvgl.FLAG.EVENT_BUBBLE)

local clockLabel
local function refreshTime()
    if clockLabel then clockLabel:set { text = os.date("%H:%M", os.time()) } end
end

local player = ShufflePlayer.new {
    lvgl = lvgl,
    root = root,
    clips = {
        { prefix = "face", count = 26 },
        { prefix = "w2", count = 30 },
        { prefix = "w3", count = 16 },
        { prefix = "w4", count = 30 },
        { prefix = "w5", count = 40 },
        { prefix = "w6", count = 21 },
        { prefix = "w7", count = 18 },
        { prefix = "w8", count = 49 },
    },
    period_ms = 83,
    seed_salt = 338129365,
    img_path = function(source) return scriptPath .. source end,
    on_resume = refreshTime,
}

clockLabel = lvgl.Label(root, {
    text = "",
    text_font = lvgl.Font("montserrat", 48, "normal"),
    text_color = 0xFFFFFF,
    align = { type = lvgl.ALIGN.BOTTOM_MID, x_ofs = 0, y_ofs = -30 },
})
refreshTime()
pcall(function()
    dataman.subscribe("timeMinuteLow", root, function(object, value)
        refreshTime()
    end)
end)

pageOnPause = function()
    player:set_page_visible(false)
end

pageOnResume = function()
    player:set_page_visible(true)
end

function ScreenStateChangedCB(previous, current, reason)
    player:set_screen_state(current)
end

root:add_flag(lvgl.FLAG.CLICKABLE)
root:onevent(lvgl.EVENT.SHORT_CLICKED, function(object, code)
    player:skip_next()
end)

player:start()
