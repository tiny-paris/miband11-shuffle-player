# Mi Band 11 Watchface Shuffle Player

[English](README.en.md)

给小米手环 Lua / LVGL 动态表盘开发者参考的 **Shuffle 队列、单计时器序列帧播放和可见性管理**。

从一个已获得小米手环 11 真机正向反馈的动态表盘中抽取。保留原有播放顺序和暂停 / 恢复规则，移除素材、字体图集、状态数据适配和 `.face` 构建链依赖。

**原表盘获得真机反馈；本仓库抽取后的模块只完成桌面 Lua 对照测试，尚未单独打包上机。** 换设备、固件或资源组织方式时，需要重新验证。

## 播放行为

- Fisher–Yates Shuffle Bag：一轮内每段恰好取出一次；多段时，新轮首段避开上一轮末段。
- 自动播放、点击跳段、灭屏 / 切页后的恢复，共用同一队列。
- 开始一段就视为已消费；中途被点击或灭屏打断，也不会把这一段放回队列。
- 只有屏幕状态为 `"ON"`、页面可见、没有手动暂停时才播放。
- 灭屏、AOD 或页面隐藏时暂停唯一的计时器；残留回调也不能改帧。
- 恢复从队列下一段的第 1 帧开始；重复恢复通知不会多取一段。
- 唤醒或点击后屏蔽一次可能已逾期的计时回调，保护第 1 帧；正常自动切段没有额外停顿。
- 使用私有 Park–Miller 随机数状态，不调用或重新播种全局 `math.random`。

单段配置也可以使用：每轮重播同一段，此时不保证相邻片段不同。这里的“每轮一次”表示**开始播放一次**，不保证被中断的片段完整播完。

## 快速接入

1. 将 `src/shuffle_player.lua` 放入你的 Lua 模块资源目录，使 `require("shuffle_player")` 可解析。
2. 参考 [examples/main.lua](examples/main.lua)，修改 `clips`、`period_ms`、`seed_salt` 和图片路径。
3. 转发现有页面、屏幕和点击回调，完成界面初始化后调用 `player:start()`。
4. 用你已有的打包工具生成 `.face`，检查新增模块后的文件索引和描述记录，再进行真机验证。

最小配置：

```lua
local ShufflePlayer = require("shuffle_player")

local player = ShufflePlayer.new {
    lvgl = lvgl,
    root = root,
    clips = {
        { prefix = "face", count = 26 },
        { prefix = "w2", count = 30 },
    },
    period_ms = 83,
    seed_salt = 338129365,
    img_path = function(source) return scriptPath .. source end,
}

pageOnPause = function() player:set_page_visible(false) end
pageOnResume = function() player:set_page_visible(true) end

function ScreenStateChangedCB(previous, current, reason)
    player:set_screen_state(current)
end

player:start()
```

这段代码假定你已有 `lvgl`、根对象 `root` 和 `scriptPath`。完整示例包含根对象创建、点击绑定、独立分钟订阅和恢复时刷新时间。若项目已有生命周期回调，应在原回调中转发，避免覆盖已有逻辑。

默认图片名是 `face_01.png`、`face_02.png`、`w2_01.png`……；`%02d` 是最小两位，100 帧会生成 `face_100.png`。所有片段使用相同的正整数毫秒周期，帧数可以不同。`83 ms` 约等于 `12.05 fps`，不是精确的 `12 fps`。

示例保留原八段的帧数配置，**图片资源由接入者提供**。运行模块需要固件提供的 `lvgl`；完整示例还使用 `dataman`，桌面测试用受限 mock 替代它们。

## 单文件接入

如果你的打包器不方便加入额外 Lua 模块，可以用 Python 3.10+ 标准库内联：

```bash
python3 tools/bundle.py
```

结果是 `dist/main.lua`，包含播放器和完整示例，只保留固件的 `lvgl` / `dataman` 依赖。修改自己的入口后也可生成：

```bash
python3 tools/bundle.py --entry path/to/main.lua --output dist/main.lua
```

入口需包含且只包含一行 `local ShufflePlayer = require("shuffle_player")`；工具只替换这一整行。**它不生成图片，也不打包 `.face`。** 内联可避免新增这个模块文件，但不能替代打包器的资源索引检查。

## 配置与接口

| 配置 | 含义 |
|---|---|
| `lvgl`、`root` | 固件 LVGL 模块和背景图片的父对象；必填 |
| `clips` | 非空连续数组，每项为 `{ prefix = "face", count = 26 }`；必填 |
| `period_ms` | 所有片段统一的正整数毫秒周期；必填 |
| `seed_salt` | `1..2147483646` 的整数盐；必填，构建时选一次 |
| `extension` | `"png"`（默认）或 `"jpg"` |
| `img_path(source)` | 图片资源路径转换；默认原样返回名称 |
| `time()` | 初始化随机数时使用的秒时间函数，默认 `os.time`；测试可注入固定值 |
| `screen_on`、`page_visible` | 初始门控布尔值，默认均为 `true` |
| `on_clip(index)` | 实际切入片段后调用，包括自动、点击、恢复入口；索引从 1 开始 |
| `on_tick()` | 可见播放计时点调用，在首帧保护判断之前；可刷新缓存的状态 |
| `on_resume()` | 实际开始 / 恢复播放后调用；可刷新错过的分钟数据 |

片段若另带 `period_ms`，必须与全局周期一致。`prefix` 只接受字母或下划线开头的字母、数字、下划线标识符。

| 方法 | 行为 |
|---|---|
| `player:start()` | 启用门控判断；重复调用不多取片段 |
| `player:set_screen_state(state)` | 只将精确的 `"ON"` 视为亮屏；其他值均暂停 |
| `player:set_page_visible(boolean)` | 转发页面可见状态 |
| `player:set_paused(boolean)` | 可选的手动暂停；仍受屏幕和页面门控约束 |
| `player:skip_next()` | 可见运行时取下一段并返回 `true`，否则返回 `false` |

`new` 创建一个 Image 和一个 Timer，预先生成全部帧路径；`start` 前计时器保持暂停。默认沿用“初始化时已亮屏且页面可见”的原工程假设，请在初始化完成后及时调用 `start`。首次启动前若长时间等待，原生计时器也可能已有逾期回调；首帧保护主要沿用原逻辑，针对已运行后的恢复和点击，详见 [时序说明](docs/behavior.md)。

回调同步执行，调用方应自行处理信息层错误，例如在 `on_clip` 中使用 `pcall`。不要在这些回调中阻塞或触发生命周期重入。背景 Image 在 `new` 时创建，信息层应随后创建以覆盖背景。

## 测试

安装 Python 3.10+ 和 Lua 5.1+，无需 Python 第三方依赖：

```bash
python3 -m unittest discover -s tests -v
LUA=luajit python3 -m unittest discover -s tests -v
```

测试直接执行 Lua。虚拟 LVGL 计时器保留暂停前的到期时间，模拟唤醒后立即触发的逾期回调。覆盖：

- 原播放器、模块示例和单文件示例的 60,000 次正常计时逐帧对照。
- 6,000 次混合事件对照：点击、重复亮屏、切页、AOD、分钟更新和残留计时回调。
- 多组帧数的 200 轮队列检查，包含单段、单帧、跨轮去重和固定时间 / 盐复现。
- 首末帧停留、不同周期、双门控顺序、手动暂停、状态刷新入口与固定对象数量。
- JPEG / 三位帧号路径、非法配置拒绝和原脚本 SHA-256 校验。

桌面测试不测真实 PNG 解码、Lua 桥接、安装兼容性、设备内存或功耗。原工程的真机正向反馈也不等于本模块已经独立通过这些项目。

## 原理与来源

- [播放队列、状态机与计时边界](docs/behavior.md)
- [设备接入与验证](docs/integration.md)

上游基础来自 [AIR-pixel/miband11-watchface-maker](https://github.com/AIR-pixel/miband11-watchface-maker)。Shuffle 是该工程工作副本中的本地扩展；本仓库不是上游官方组件，也不包含其完整构建工具。采用 MIT 许可，保留上游许可证，详见 [LICENSE](LICENSE) 和 [NOTICE.md](NOTICE.md)。
