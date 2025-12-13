# Lokasenna Radial Menu 脚本分析

## 📋 概述

Lokasenna Radial Menu 是一个圆形快速菜单系统，类似于FPS游戏中的武器选择菜单。它允许用户通过鼠标或键盘快速访问常用的REAPER操作。

## 🔧 脚本架构

### 1. **Lokasenna_Radial Menu Setup.lua** (设置脚本)

**功能：** 启动配置界面

**代码结构：**
```lua
setup = true  -- 设置标志，告诉主脚本进入配置模式
local script_path = debug.getinfo(1,'S').source:match[[^@?(.*[\/])[^\/]-$]]
dofile(script_path .. "Lokasenna_Radial Menu.lua")  -- 加载主脚本
```

**作用：**
- 这是一个**启动器脚本**，只有12行代码
- 设置 `setup = true` 标志
- 通过 `dofile()` 加载主脚本 `Lokasenna_Radial Menu.lua`
- 主脚本检测到 `setup = true` 时会打开配置界面而不是运行菜单

### 2. **Lokasenna_Radial Menu.lua** (主脚本)

**功能：** 完整的径向菜单系统

**文件大小：** 约9200行代码

**核心组件：**

#### A. GUI框架库
- **Lokasenna_GUI Library (beta 8)** - 内置的GUI框架
- 提供窗口管理、元素创建、事件处理等功能
- 使用 `gfx` API 进行图形渲染

#### B. 菜单数据结构
```lua
local mnu_arr = {}  -- 菜单数组，存储所有菜单层级
-- mnu_arr[-1] 存储全局设置
-- mnu_arr[0], mnu_arr[1], ... 存储不同深度的菜单
```

**菜单结构：**
- **深度系统 (Depth System)**: 支持多层级菜单（0 = 主菜单，1+ = 子菜单）
- **按钮数组**: 每个菜单包含多个按钮，每个按钮有：
  - `lbl`: 标签文本
  - `act`: 关联的REAPER操作ID或命令
  - 可选的子菜单深度

#### C. 核心功能模块

**1. 菜单加载/保存 (`load_menu`, `save_menu`)**
- 从文本文件读取菜单配置：`Lokasenna_Radial Menu - user settings.txt`
- 如果没有用户设置，使用示例文件：`Lokasenna_Radial Menu - example settings.txt`
- 使用Lua表序列化/反序列化保存配置

**2. 鼠标检测 (`check_mouse`)**
```lua
local mouse_angle, mouse_r, mouse_lr = 0, 0, 0
local mouse_mnu = -2  -- 当前鼠标悬停的菜单项索引
```
- 计算鼠标相对于菜单中心的**角度**和**半径**
- 根据角度确定鼠标悬停在哪个按钮上
- 使用三角函数 (`sin`, `cos`, `atan`) 进行角度计算

**3. 键盘检测 (`check_key`)**
- 检测快捷键绑定
- 支持"按住键"模式（key_mode）
- 处理键盘导航（方向键选择菜单项）

**4. 菜单渲染**
- 圆形布局：按钮按角度均匀分布
- 高亮显示：鼠标悬停的按钮会高亮
- 子菜单预览：显示子菜单内容
- 键盘提示：显示快捷键绑定

#### D. 运行模式

**1. 设置模式 (`setup = true`)**
- 打开配置窗口 (1024x640)
- 提供多个标签页：
  - **Menus**: 编辑菜单结构和按钮
  - **Global Settings**: 全局设置（窗口位置、鼠标模式等）
  - **Menu Settings**: 每个菜单的特定设置
  - **Button Settings**: 按钮设置（操作、颜色等）
  - **Context Menus**: 上下文菜单配置
  - **Key Bindings**: 快捷键绑定
  - **Help**: 帮助文档

**2. 运行模式 (`setup = false` 或 `nil`)**
- 显示圆形径向菜单
- 窗口大小根据菜单半径动态计算
- 窗口位置：
  - 模式1：跟随鼠标光标
  - 模式2：上次关闭的位置

#### E. 高级功能

**1. 上下文菜单 (Context Menus)**
- 根据REAPER的上下文（选中item、track等）自动切换到相应菜单
- 使用 `get_context_mnu()` 检测当前上下文

**2. 智能按钮 (Smart Buttons)**
- 某些按钮可以"预加载"操作，按空格键执行
- 用于需要确认的操作

**3. 滑动手势 (Swipe Gestures)**
- 支持在轨道上滑动触发菜单
- `track_swipe` 变量跟踪滑动状态

**4. 快捷键绑定**
- 可以为菜单项绑定键盘快捷键
- 支持显示/隐藏快捷键提示

## 🔄 工作流程

### 启动流程

1. **Setup脚本启动：**
   ```
   Lokasenna_Radial Menu Setup.lua
   → 设置 setup = true
   → dofile("Lokasenna_Radial Menu.lua")
   ```

2. **主脚本初始化：**
   ```
   检测 setup 标志
   → 如果 setup = true: 打开配置界面
   → 如果 setup = false/nil: 检查是否有设置文件
      → 有设置文件: 加载并运行菜单
      → 无设置文件: 提示并打开配置界面
   ```

3. **菜单运行：**
   ```
   加载菜单配置
   → 检测上下文（如果有）
   → 初始化菜单窗口
   → 进入主循环 (Main())
      → check_key() - 检测键盘
      → check_mouse() - 检测鼠标
      → 渲染菜单
      → 处理用户交互
   ```

### 用户交互流程

1. **鼠标模式：**
   - 用户移动鼠标到菜单中心
   - 系统计算鼠标角度
   - 高亮对应的按钮
   - 点击执行操作或进入子菜单

2. **键盘模式：**
   - 按住快捷键打开菜单
   - 使用方向键选择菜单项
   - 释放快捷键执行操作

## 📊 技术特点

### 优点

1. **模块化设计**
   - Setup脚本和主脚本分离
   - 配置与代码分离（使用文本文件存储配置）

2. **灵活的菜单系统**
   - 支持无限层级
   - 每个菜单可独立配置
   - 支持别名和上下文菜单

3. **用户友好**
   - 图形化配置界面
   - 实时预览
   - 详细的帮助文档

4. **性能优化**
   - 使用本地变量缓存常用函数（如 `sin`, `cos`）
   - 条件重绘 (`redraw_menu` 标志)
   - 高效的鼠标角度计算

### 技术实现细节

1. **角度计算：**
   ```lua
   local mouse_angle = atan2(mouse_y - oy, mouse_x - ox)
   -- 将鼠标坐标转换为相对于菜单中心的角度
   ```

2. **按钮分布：**
   ```lua
   local mnu_adj = (2 * pi) / num_btns  -- 每个按钮占用的角度
   -- 按钮按角度均匀分布在圆周上
   ```

3. **菜单深度管理：**
   ```lua
   local cur_depth = 0  -- 当前菜单深度
   local base_depth = 0  -- 基础深度
   local prev_depths = {}  -- 历史深度栈
   ```

## 🎯 使用场景

1. **快速访问常用操作**
   - 无需记忆快捷键
   - 视觉化选择

2. **工作流定制**
   - 为不同任务创建不同菜单
   - 上下文相关菜单

3. **触摸屏/平板支持**
   - 圆形菜单适合触摸操作
   - 滑动手势支持

## 📝 配置文件格式

菜单配置以Lua表格式存储在文本文件中：

```lua
return {
    [-1] = {
        -- 全局设置
        num_btns = 8,
        rd = 80,  -- 半径
        win_pos = 1,  -- 窗口位置模式
        ...
    },
    [0] = {
        -- 主菜单
        alias = "Main",
        [0] = { lbl = "Button 1", act = "40001" },
        [1] = { lbl = "Button 2", act = "40002", depth = 1 },
        ...
    },
    [1] = {
        -- 子菜单1
        alias = "Submenu 1",
        ...
    }
}
```

## 🔍 关键代码片段

### Setup检测
```lua
if not (setup or reaper.file_exists(settings_file_name) or reaper.file_exists(example_file_name)) then 
    reaper.ShowMessageBox("Couldn't find any saved settings. Opening in Setup mode.", "No settings found", 0)
    setup = true
end
```

### 模式切换
```lua
if setup then
    -- 配置模式
    GUI.name = "Radial Menu Setup"
    GUI.w, GUI.h = 1024, 640
    -- ... 初始化配置界面
else
    -- 运行模式
    GUI.name = "Radial Menu"
    GUI.w, GUI.h = frm_w, frm_w + 16
    -- ... 初始化菜单窗口
end
```

## 💡 总结

**Lokasenna_Radial Menu Setup.lua:**
- 简单的启动器脚本
- 设置配置模式标志
- 加载主脚本

**Lokasenna_Radial Menu.lua:**
- 完整的径向菜单系统
- 包含GUI框架库
- 支持配置和运行两种模式
- 复杂的菜单管理和交互逻辑
- 约9200行代码，功能丰富

这是一个设计精良的脚本系统，通过Setup脚本的巧妙设计实现了配置和运行模式的分离，使得用户可以通过图形界面轻松配置菜单，而无需直接编辑代码。




