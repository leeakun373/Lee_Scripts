# nvk Take Marker 实现文档

## 目录

1. [概述](#概述)
2. [核心 API](#核心-api)
3. [实现方式](#实现方式)
4. [算法详解](#算法详解)
5. [代码示例](#代码示例)
6. [工作流程](#工作流程)
7. [关键概念](#关键概念)

---

## 概述

nvk_TAKES 是一套用于 REAPER 的脚本集合，专门设计用于改进使用 takes 的工作流程，特别是在游戏音频和声音设计方面。核心功能是自动在 take 中嵌入 take markers，这些 markers 可以用于轻松地在包含多个变体的文件中通过单个按键切换变体。

### 主要特性

- **自动检测音频变化点**：使用智能算法自动检测音频中的变化点或片段边界
- **批量处理**：支持批量处理多个 items 和 takes
- **多种添加方式**：提供多种添加 take marker 的方式（手动、自动、基于位置等）
- **位置计算**：精确计算 marker 在源文件中的位置，考虑 offset、snap offset 和 playrate

### 系统要求

- REAPER 7 或更高版本（不支持 REAPER 6）
- 需要 nvk_SHARED 依赖库
- 使用 ReaImGui 作为界面框架

---

## 核心 API

### REAPER 原生 API

#### 1. SetTakeMarker

```lua
reaper.SetTakeMarker(take, idx, name, srcpos)
```

**参数：**
- `take`: take 对象
- `idx`: marker 索引（-1 表示添加新 marker，0 表示在开头插入）
- `name`: marker 名称（字符串）
- `srcpos`: 源位置（秒，在源文件中的绝对位置）

**返回值：** 成功返回 marker 索引，失败返回 -1

#### 2. GetNumTakeMarkers

```lua
reaper.GetNumTakeMarkers(take)
```

**参数：**
- `take`: take 对象

**返回值：** marker 数量

#### 3. GetTakeMarker

```lua
reaper.GetTakeMarker(take, idx)
```

**参数：**
- `take`: take 对象
- `idx`: marker 索引

**返回值：** marker 名称, marker 源位置

#### 4. DeleteTakeMarker

```lua
reaper.DeleteTakeMarker(take, idx)
```

**参数：**
- `take`: take 对象
- `idx`: marker 索引

### nvk 封装的 API

#### 1. take:SetTakeMarker()

```lua
take:SetTakeMarker(idx, name, srcpos)
```

封装了 `reaper.SetTakeMarker`，提供更简洁的调用方式。

#### 2. take:Clips()

```lua
take:Clips(enable_markers)
```

自动检测音频中的变化点并添加 take markers。

**参数：**
- `enable_markers`: 布尔值，是否启用 marker 添加（可选）

#### 3. take.takemarkers

```lua
for _, takemarker in ipairs(take.takemarkers) do
    -- takemarker.srcpos: marker 的源位置
    -- takemarker.name: marker 名称
end
```

遍历 take 中的所有 markers。

---

## 实现方式

### 方式 1：在 Item 开头添加命名的 Take Marker

**脚本：** `nvk_TAKES - Add named take marker to start of selected items.lua`

**实现逻辑：**

```lua
run(function()
    -- 1. 获取用户输入的 marker 名称
    local retval, retvals_csv = r.GetUserInputs(scr.name, 1, 'Take Marker Name,extrawidth=220', '')
    if retval == false then return end
    
    -- 2. 遍历所有选中的 items
    for i = 0, r.CountSelectedMediaItems(0) - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local take = r.GetActiveTake(item)
        
        -- 3. 获取 take 的 start offset
        local offset = r.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
        
        -- 4. 在 offset 位置添加 marker（索引 0 表示在开头插入）
        r.SetTakeMarker(take, 0, retvals_csv, offset)
    end
end)
```

**关键点：**
- 使用 `D_STARTOFFS` 获取 take 在源文件中的起始偏移
- 索引 0 表示在开头插入 marker
- 所有选中的 items 都会在相同位置添加相同名称的 marker

### 方式 2：在鼠标位置快速添加编号的 Take Marker

**脚本：** `nvk_TAKES - Quick add numbered take marker at mouse position.lua`

**实现逻辑：**

```lua
run(function()
    local items = Items():Unselect()
    
    -- 1. 选中鼠标下的 item
    r.Main_OnCommand(40528, 0) -- select item under mouse cursor
    
    if r.CountSelectedMediaItems(0) > 0 then
        -- 2. 使用内置命令在鼠标位置添加 marker
        r.Main_OnCommand(42391, 0) -- quick add take marker at mouse position
        
        local item = r.GetSelectedMediaItem(0, 0)
        local take = r.GetActiveTake(item)
        
        -- 3. 遍历所有 markers，将它们重命名为数字编号
        for i = 0, r.GetNumTakeMarkers(take) do
            r.SetTakeMarker(take, i, tostring(i + 1))
        end
    end
    
    items:Select(true)
end)
```

**关键点：**
- 使用 REAPER 内置命令 `42391` 在鼠标位置添加 marker
- 然后遍历所有 markers，将它们重命名为数字编号（1, 2, 3...）

### 方式 3：将 Item 分割合并为 Take Markers

**脚本：** `nvk_TAKES - Consolidate item splits as take markers in first item.lua`

**实现逻辑：**

```lua
run(function()
    local items = Items()
    if #items == 0 then return end
    items:Unselect()
    
    local num = 0
    local initTrack
    local initItem
    
    -- 1. 遍历所有 items，检测同一轨道上相同源文件的 items
    for i, item in ipairs(items) do
        local track = item.track
        local take = item.take
        if take then
            if track == initTrack then
                if take.srcfile == initItem.srcfile then
                    -- 2. 相同源文件，计算位置并添加 marker
                    num = num + 1
                    if num > 1 then
                        -- 计算位置：take.offset + item.snapoffset * take.playrate
                        initItem.take:SetTakeMarker(-1, tostring(num), 
                            take.offset + item.snapoffset * take.playrate)
                    end
                    if i > 1 then item:Delete() end
                else
                    item:Select()
                end
            else
                -- 3. 新轨道，重置计数
                if num > 1 then
                    initItem.take:SetTakeMarker(-1, '1', 
                        initItem.offset + initItem.snapoffset * initItem.playrate)
                end
                initTrack = track
                initItem = item
                initItem:Select()
                num = 1
            end
        end
    end
    
    -- 4. 处理最后一个 item
    if num > 1 then 
        initItem.take:SetTakeMarker(-1, '1', 
            initItem.offset + initItem.snapoffset * initItem.playrate) 
    end
    
    -- 5. 合并为 takes
    r.Main_OnCommand(40543, 0) -- Take: Implode items on same track into takes
end)
```

**关键点：**
- 检测同一轨道上相同源文件的 items
- 计算每个 item 的位置：`take.offset + item.snapoffset * take.playrate`
- 使用 `-1` 作为索引添加新 marker
- 删除多余的 items，最后合并为 takes

### 方式 4：使用 Clips() 方法自动检测

**脚本：** `nvk_TAKES - Add take markers to all variations in selected items takes.lua`

**实现逻辑：**

```lua
run(function()
    for i, item in ipairs(Items()) do
        for i, take in ipairs(item.takes) do
            -- 自动检测音频中的变化点并添加 take markers
            take:Clips(true)
        end
    end
end)
```

**关键点：**
- 使用 nvk 封装的 `take:Clips(true)` 方法
- 自动检测音频中的变化点并添加 take markers
- 这是 nvk_TAKES 的核心功能，用于游戏音频和声音设计工作流

---

## 算法详解

nvk 使用两种主要算法来判断在什么位置添加 take marker：

### 算法 1：窗口分析 + 中值滤波 + 阈值检测

**适用场景：** 检测音频中的变化点（variations），适用于包含多个变体的音频文件。

**脚本：** `nvk_TAKES - Add take markers to variations in items.eel`

#### 步骤 1：音频采样与分析

```eel
window = 0.01; // 窗口大小：10ms
speed = 10;   // 降采样比例，用于加速

// 将音频分成 10ms 窗口，计算每个窗口的绝对值总和（能量）
loop(n_blocks,
    GetAudioAccessorSamples(accessor, rate, 1, read_pos, size, buffer);
    
    sum_com = 0;
    loop(floor(size/speedRatio),
        sum_com += abs(buffer[i]);  // 计算窗口内的能量
        i += speedRatio;
    );
    bc[j] = sum_com;  // 存储每个窗口的能量值
    j += 1;
    read_pos += window;
);
```

**关键参数：**
- `window = 0.01` 秒（10ms 窗口）
- `speed = 10`：降采样比例，用于提高性能

#### 步骤 2：中值滤波平滑

```eel
// 使用 3 点中值滤波去除噪声
loop(j-2,
    bc[i-1] < bc[i] && bc[i] < bc[i+1] ? (
        bs[i] = bc[i];
    ) : (
        bc[i] < bc[i-1] && bc[i-1] < bc[i+1] ? (
            bs[i] = bc[i-1];
        ) : (
            bs[i] = bc[i+1];
        );
    );
    i += 1;
);
```

**作用：** 去除噪声，平滑能量曲线

#### 步骤 3：计算阈值

```eel
// 计算平均值和最大值
loop(j,
    bs[i] > high ? high = bs[i];
    mid += bs[i];
    i += 1;
);
mid /= j;
thresh = mid/3;  // 阈值 = 平均值的 1/3
```

**阈值计算：** `thresh = mid/3`（平均值的 1/3）

#### 步骤 4：统计声音/静音段

```eel
// 统计声音段长度和静音段长度
loop(j,
    bs[i] > thresh ? (
        cnt += 1;  // 声音段计数
        sil = 0;
    ) : (
        cnt > 0 ? (
            numCnt += 1;
            cntAvg += cnt;  // 累计声音段长度
        );
        cnt = 0;
        sil += 1;  // 静音段计数
    );
    i += 1;
);
cntAvg /= numCnt;  // 平均声音段长度
silAvg /= numSil;  // 平均静音段长度
```

#### 步骤 5：检测变化点并添加 Marker

```eel
loop(j,
    bs[i] > thresh ? (
        // 在声音段中
        cnt += 1;
        bc[i] > peak ? (
            peak = bc[i];
            peak > ptPeak+pMod ? (
                ptPeak = peak;
                peakTime = i * window + window/2;  // 记录峰值位置
            );
        );
    ) : (
        // 在静音段中
        sil += 1;
        // 判断条件：同时满足以下三个条件
        cnt*10 >= cntAvg && sil*1.5 > silAvg && peak*6 > high ? (
            SetTakeMarker(take, idx, #idx, peakTime, colorIn);
            idx += 1;
            // 重置计数器
            peak = 0;
            sil = 0;
            cnt = 0;
        );
    );
    i += 1;
);
```

**判断条件（同时满足）：**
1. `cnt*10 >= cntAvg`：当前声音段长度 ≥ 平均值的 10 倍
2. `sil*1.5 > silAvg`：当前静音段长度 > 平均值的 1.5 倍
3. `peak*6 > high`：峰值 > 最大值的 1/6

**Marker 位置：** `peakTime = i * window + window/2`（峰值所在窗口的中心）

---

### 算法 2：瞬态检测 + 静音检测

**适用场景：** 检测音频片段（clips），适用于包含多个独立声音片段的音频。

**脚本：** `nvk_TAKES - Consolidate takes with take markers SMART.eel`

#### 参数设置

```eel
Retrig_sec = 0.5;              // 重触发时间
AboveSilenceTime_sec = 0.01;   // 声音段持续时间阈值
BelowSilenceTime_sec = 0.18;   // 静音段持续时间阈值
SilenceThreshold_dB = -40;     // 静音阈值（dB）
SoundThreshold_dB = -25;       // 声音阈值（dB）
```

#### 核心检测逻辑

```eel
// 转换为线性值
SilenceThreshold = 10^(SilenceThreshold_dB/20);  // -40dB
SoundThreshold = 10^(SoundThreshold_dB/20);      // -25dB

// 转换为采样数
AboveSilenceTime = floor(AboveSilenceTime_sec * srate);
BelowSilenceTime = floor(BelowSilenceTime_sec * srate);

// 逐样本检测
loop(samples,
    input = abs(samplebuffer[smpl]);
    
    // 1. 瞬态检测（峰值跟踪）
    input > maxPeak + PeakSensitivity ? (
        maxPeak = input;
        mrk_pos = starttime_sec + smpl/srate;  // 记录峰值位置
        peakSensitivity = input*2;  // 自适应阈值
    );
    
    // 2. 声音段检测
    input > SoundThreshold ? (
        aboveSilenceCount += 1;
        aboveSilenceCount > AboveSilenceTime ? (
            setPeak = 1;  // 标记已检测到声音段
        );
    ) : (
        // 3. 静音段检测
        input < SilenceThreshold ? (
            belowSilenceCount += 1;
            belowSilenceCount > BelowSilenceTime ? (
                // 4. 添加 Marker 的条件
                setPeak == 1 && retrig_cnt > Retrig ? (
                    SetTakeMarker(take, idx, str, mrk_pos, colorIn);
                    idx += 1;
                    // 重置状态
                    setPeak = 0;
                    maxPeak = 0;
                );
            );
        );
    );
    retrig_cnt += 1;
    smpl += 1;
);
```

#### 检测流程

1. **瞬态检测（峰值跟踪）**
   - 当 `input > maxPeak + PeakSensitivity` 时更新峰值
   - `PeakSensitivity = input*2`（自适应阈值）
   - 记录峰值位置 `mrk_pos`

2. **声音段检测**
   - `input > SoundThreshold`（-25dB）时开始计数
   - `aboveSilenceCount > AboveSilenceTime`（0.01 秒）时标记 `setPeak = 1`

3. **静音段检测**
   - `input < SilenceThreshold`（-40dB）时开始计数
   - `belowSilenceCount > BelowSilenceTime`（0.18 秒）时判定为静音

4. **Marker 添加条件**
   - `setPeak == 1`（已检测到声音段）
   - `retrig_cnt > Retrig`（满足重触发时间，0.5 秒）
   - 在峰值位置 `mrk_pos` 添加 marker

---

### 算法对比总结

| 特性 | 算法 1（窗口分析） | 算法 2（瞬态检测） |
|------|-------------------|-------------------|
| **适用场景** | 多个变体（variations） | 多个片段（clips） |
| **检测方式** | 窗口能量分析 | 逐样本检测 |
| **平滑处理** | 中值滤波 | 无 |
| **阈值类型** | 动态（平均值/3） | 固定（-25dB/-40dB） |
| **判断条件** | 声音段长度 + 静音段长度 + 峰值 | 声音段 + 静音段 + 重触发时间 |
| **性能** | 较快（降采样） | 较慢（逐样本） |
| **精度** | 中等（10ms 窗口） | 高（样本级） |

---

## 代码示例

### 示例 1：读取 Take Markers

```lua
-- 脚本：nvk_TAKES - Set snap offset to first visible take marker.lua

run(function()
    for _, item in ipairs(Items.Selected()) do
        local take = item.take
        if take then
            local offset = take.offset
            
            -- 遍历所有 take markers
            for _, takemarker in ipairs(take.takemarkers) do
                -- 找到第一个可见的 marker（在 offset 之后）
                if takemarker.srcpos >= offset then
                    -- 计算 snap offset
                    local snapoffset = (takemarker.srcpos - offset) / take.rate
                    if snapoffset < item.length then 
                        item.snapoffset = snapoffset 
                    end
                    break
                end
            end
        end
    end
end)
```

### 示例 2：批量添加 Take Markers

```lua
-- 在选中 items 的开头添加命名的 take marker

run(function()
    -- 获取用户输入
    local retval, retvals_csv = r.GetUserInputs(scr.name, 1, 
        'Take Marker Name,extrawidth=220', '')
    if retval == false then return end
    
    -- 遍历所有选中的 items
    for i = 0, r.CountSelectedMediaItems(0) - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local take = r.GetActiveTake(item)
        
        -- 获取 take 的 start offset
        local offset = r.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
        
        -- 在 offset 位置添加 marker
        r.SetTakeMarker(take, 0, retvals_csv, offset)
    end
end)
```

### 示例 3：使用 Clips() 方法

```lua
-- 为所有选中的 items 的 takes 添加 take markers

run(function()
    for i, item in ipairs(Items()) do
        for i, take in ipairs(item.takes) do
            -- 自动检测并添加 take markers
            take:Clips(true)
        end
    end
end)
```

### 示例 4：位置计算

```lua
-- 计算 marker 在源文件中的位置

local function calculateMarkerPosition(item, take)
    -- 方法 1：使用 take offset
    local offset = r.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
    
    -- 方法 2：考虑 snap offset 和 playrate
    local srcpos = take.offset + item.snapoffset * take.playrate
    
    return srcpos
end

-- 添加 marker
local srcpos = calculateMarkerPosition(item, take)
r.SetTakeMarker(take, -1, "Marker Name", srcpos)
```

---

## 工作流程

### 典型工作流程 1：游戏音频变体管理

1. **准备音频文件**
   - 将多个音频变体放在同一个文件中
   - 每个变体之间用静音分隔

2. **自动添加 Take Markers**
   - 运行 `nvk_TAKES - Add take markers to all variations in selected items takes.lua`
   - 脚本会自动检测变化点并添加 markers

3. **使用 Take Markers**
   - 使用 `nvk_TAKES - Select next/previous take SMART` 脚本切换变体
   - 通过单个按键快速浏览所有变体

### 典型工作流程 2：Item 分割合并

1. **分割 Items**
   - 在时间轴上分割 items，每个分割代表一个片段

2. **合并为 Take Markers**
   - 运行 `nvk_TAKES - Consolidate item splits as take markers in first item.lua`
   - 脚本会将分割的 items 合并为一个 item，每个分割位置添加一个 take marker

3. **结果**
   - 一个 item 包含多个 takes
   - 每个 take 对应一个分割位置
   - 可以通过切换 takes 来访问不同的片段

### 典型工作流程 3：手动添加 Markers

1. **选择位置**
   - 在时间轴上选择需要添加 marker 的位置
   - 或使用鼠标定位

2. **添加 Marker**
   - 运行 `nvk_TAKES - Quick add numbered take marker at mouse position.lua`
   - 或运行 `nvk_TAKES - Add named take marker to start of selected items.lua`

3. **使用 Markers**
   - Markers 可以用于对齐、导航或切换 takes

---

## 关键概念

### 1. Take Offset (D_STARTOFFS)

Take 在源文件中的起始偏移量（秒）。

```lua
local offset = r.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
```

### 2. Snap Offset

Item 的 snap offset，用于对齐。在源文件中的位置计算：

```lua
local srcpos = take.offset + item.snapoffset * take.playrate
```

### 3. Source Position

Marker 在源文件中的绝对位置（秒）。

```lua
-- 添加 marker
r.SetTakeMarker(take, idx, name, srcpos)

-- 读取 marker
local name, srcpos = r.GetTakeMarker(take, idx)
```

### 4. Playrate

Take 的播放速率。影响位置计算：

```lua
local playrate = r.GetMediaItemTakeInfo_Value(take, 'D_PLAYRATE')
local srcpos = take.offset + item.snapoffset * playrate
```

### 5. Marker 索引

- `-1`：添加新 marker（追加到末尾）
- `0`：在开头插入 marker
- `1, 2, 3...`：在指定索引位置插入或修改 marker

### 6. 位置转换

从源位置转换为 item 中的位置：

```lua
local offset = take.offset
local srcpos = takemarker.srcpos
local snapoffset = (srcpos - offset) / take.playrate
```

---

## 总结

nvk 的 take marker 实现提供了多种方式来添加和管理 take markers：

1. **基础方式**：直接使用 REAPER API `SetTakeMarker`
2. **位置计算**：考虑 offset、snap offset 和 playrate
3. **自动化**：`Clips()` 方法自动检测变化点
4. **批量处理**：支持批量处理多个 items/takes
5. **封装**：通过 `functions.dat` 提供更高级的对象方法

这些方法特别适用于游戏音频和声音设计工作流，可以快速创建和管理多个音频变体。

---

## 参考资料

- nvk_TAKES 官方文档：https://nvk.tools/docs/workflow/takes
- REAPER API 文档：https://www.reaper.fm/sdk/reascript/reascripthelp.html
- nvk 脚本仓库：https://github.com/nickvonkaenel/nvk-ReaScripts

---

*文档生成时间：2025-11-23*
*基于 nvk_TAKES 2.6.0 版本分析*
