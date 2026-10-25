# 设备接入与验证

## 资源与固件接口

播放器只使用已在原工程采用的接口：

- `root:Image { src = ... }` 和 `image:set { src = ... }`。
- `lvgl.Timer { period = ..., cb = ... }`，以及 `timer:pause()` / `timer:resume()`。
- `lvgl.HOR_RES()` / `lvgl.VER_RES()` 和 `lvgl.ALIGN.TOP_MID`。
- 调用方转发页面回调和全局 `ScreenStateChangedCB`。

完整示例另使用 Label、Font、点击事件和 `dataman.subscribe("timeMinuteLow", ...)`。这些属于当前 Lua / LVGL 桥接写法，不是桌面 LVGL C API 的直接映射；换固件要先验证最小对象、图片和计时器。

模块不执行 `dataman` 订阅，不读取电量、心率或蓝牙。分钟订阅独立于动画；恢复时 `on_resume` 从当前系统时间刷新，避免错过分钟通知后仍显示旧时间。

## 与原信息层协作

```lua
local player = ShufflePlayer.new {
    lvgl = lvgl,
    root = root,
    clips = clips,
    period_ms = 83,
    seed_salt = 338129365,
    img_path = imgPath,
    on_clip = function(index)
        if info then
            local success, message = pcall(info.setClip, index)
            if not success then disableInfo(message) end
        end
    end,
    on_tick = function()
        if info then
            local success, message = pcall(info.flushStatus)
            if not success then disableInfo(message) end
        end
    end,
    on_resume = refreshTime,
}
```

上面是接入片段，`info`、`disableInfo`、`refreshTime` 等由你的工程提供。先创建播放器背景，再创建信息层，最后启动。状态订阅回调只更新缓存和 dirty 标志；可见 `on_tick` 再绘制。不要为了静态表盘套用这个例子而增加高频轮询。

颜色等属性绑定 `on_clip` 提供的真实片段索引，不能按“切换了几次”自行轮换；恢复和点击也会消费队列。`on_resume` 在实际开始播放后调用一次，重复通知不会反复触发它。

若已有 `pageOnPause`、`pageOnResume` 或 `ScreenStateChangedCB`，在已有函数中加入转发。不要复制一个新的全局函数覆盖原有订阅、界面或电源处理。

## 打包时检查

1. 图片前缀、帧数、扩展名和 `SCRIPT_PATH` 拼接必须与包内资源一致。每段首帧从 `01` 开始，没有 `00`。
2. 所有片段使用同一周期；导帧阶段也应使用对应固定帧率，不能在帧数超限时静默降低某一段帧率。
3. 加入模块会改变包内文件清单，可能改变 Lua 主入口和资源索引。原工程的索引 `26` 是当时容器约束，不是通用常量。
4. 若采用单文件内联，只加入生成的主脚本；不要误把 `tests/fixtures/original-main.lua` 打进设备包。
5. AOD 在这里仅作为暂停信号；静态 AOD 资源与描述记录由你的打包工具负责。本模块不创建 AOD 界面。

播放器不提供 MP4 解码、导帧或 `.face` 容器写入。原始项目的素材、字体和历史构建也不是本仓库的依赖。

## 真机检查建议

| 场景 | 观察证据 |
|---|---|
| 连续播放至少两轮 | 每轮所有片段都出现，段末衔接和跨轮相邻片段符合规则 |
| 点击连续跳段 | 沿同一袋子推进，没有重播被打断的片段 |
| 灭屏后唤醒 | 下一段从第 1 帧开始；重复回调不多跳段 |
| 切到其他页面再回来 | 隐藏期间不推进，回来取下一段 |
| 进入 / 退出 AOD | 动画暂停；页面未切走时也能暂停 |
| 亮屏和页面恢复顺序颠倒 | 两个条件都满足后才启动一次 |
| 跨分钟 / 长时间灭屏 | 时间正常更新，唤醒后校正 |
| 多次亮灭屏与长时运行 | 记录实际稳定性、内存现象和耗电，不由桌面测试推断 |

记录设备、固件、包 ID、包哈希和实际观察；不要只记录“可以安装”。本仓库不随附设备功耗或长时稳定性结论。
