# RadialMenu Tool

一个为 REAPER 设计的现代化轮盘菜单工具，使用 Lua 和 ReaImGui 开发。

## 📖 项目简介

RadialMenu Tool 是一个模块化的轮盘菜单系统，旨在为 REAPER 提供快速、直观的操作界面。通过圆形布局的扇区菜单，用户可以快速访问常用的 Actions、FX 插件和脚本。

### 主要特性

- 🎨 **可视化轮盘界面** - 圆形扇区布局，直观易用
- ⚙️ **高度可配置** - 通过 JSON 配置文件自定义菜单内容
- 🎯 **智能上下文检测** - 自动判断 FX 挂载到 Track 还是 Item
- 🔍 **模糊搜索** - 快速查找 Actions 和 FX（设置界面）
- 🚀 **模块化架构** - GUI/Logic/Data 清晰分离，易于维护和扩展
- 🖱️ **悬停/点击模式** - 支持悬停打开或点击打开子菜单
- 📌 **Pin 模式** - 可以固定菜单窗口，方便多次操作

---

## 📁 项目结构

```
RadialMenu_Tool/
├── Lee_RadialMenu.lua          # 主运行入口（轮盘菜单启动脚本）
├── Lee_RadialMenu_Setup.lua    # 设置编辑器入口（配置界面启动脚本）
├── Lee_RadialMenu_reset_state.lua  # 状态重置工具
├── config.json                  # 用户配置文件（自动生成）
├── config.example.json          # 配置文件模板
├── src/                        # 源代码目录
│   ├── config_manager.lua     # 配置管理器：读取/保存/验证 JSON 配置
│   ├── main_runtime.lua        # 主运行时循环：轮盘菜单的核心运行逻辑
│   ├── main_settings.lua       # 设置编辑器主文件：整合所有设置界面模块
│   │
│   ├── gui/                    # GUI 渲染模块
│   │   ├── wheel.lua          # 轮盘绘制：绘制圆形扇区、处理扇区交互
│   │   ├── list_view.lua      # 子菜单列表：绘制子菜单网格、处理拖拽和点击
│   │   └── styles.lua          # 样式定义：ImGui 主题和颜色配置
│   │
│   ├── logic/                  # 业务逻辑模块
│   │   ├── actions.lua        # Actions 执行：执行 REAPER Actions
│   │   ├── execution.lua      # 执行引擎：统一处理所有插槽类型的执行逻辑
│   │   ├── fx_engine.lua      # FX 智能挂载引擎：自动判断 Track/Item 上下文
│   │   └── search.lua         # 模糊搜索算法：Actions 和 FX 的搜索功能
│   │
│   └── settings/               # 设置界面模块（v1.1.0 重构）
│       ├── tab_preview.lua    # 预览面板：左侧轮盘预览和全局设置
│       ├── tab_grid.lua       # 网格编辑器：中间插槽网格编辑区域
│       ├── tab_inspector.lua  # 属性编辑栏：右侧选中插槽的属性编辑
│       ├── tab_browser.lua    # 资源浏览器：Actions/FX/Chains/Templates 浏览
│       └── tab_presets.lua    # 预设管理：配置预设的保存和加载
│
├── utils/                      # 工具函数库
│   ├── math_utils.lua         # 几何数学计算：角度、坐标转换、缓动函数
│   ├── im_utils.lua           # ImGui 辅助函数：常用 UI 组件封装
│   ├── json.lua               # JSON 编码/解码：配置文件读写
│   └── utils_fx.lua           # FX 工具：扫描 FX/Chains/Templates，缓存管理
│
└── doc/                        # 文档目录
    ├── README.md              # 本文件（项目说明）
    ├── USER_MANUAL.md         # 用户手册（详细使用指南）
    ├── CHANGELOG.md           # 更新日志（版本历史）
    ├── TODO.md                # 开发路线图（计划功能）
    ├── IMPLEMENTATION_NOTES.md # 实现说明（技术细节）
    └── GITHUB_SETUP.md        # GitHub 设置指南
```

### 📦 模块功能说明

#### 🚀 入口文件
- **Lee_RadialMenu.lua**: 轮盘菜单的主入口，初始化配置、启动运行时循环
- **Lee_RadialMenu_Setup.lua**: 设置编辑器的入口，启动配置界面

#### 🎨 GUI 模块 (`src/gui/`)
- **wheel.lua**: 
  - 绘制圆形轮盘界面（扇区、中心圆）
  - 处理扇区的悬停、点击交互
  - 计算扇区角度和鼠标位置检测
  - 扇区扩展动画效果
  
- **list_view.lua**: 
  - 绘制子菜单网格（插槽按钮列表）
  - 处理插槽的拖拽和点击事件
  - 管理拖拽状态和反馈显示
  - 子菜单窗口的显示和隐藏逻辑
  
- **styles.lua**: 
  - 定义 ImGui 主题样式（颜色、字体、间距等）
  - 提供统一的 UI 风格配置

#### ⚙️ 业务逻辑模块 (`src/logic/`)
- **actions.lua**: 
  - 执行 REAPER Actions（通过 Command ID）
  - 获取 Action 名称和描述
  
- **execution.lua**: 
  - **核心执行引擎**：统一处理所有插槽类型的执行
  - 根据插槽类型（action/fx/chain/template）调用相应的执行函数
  - 处理执行结果和错误
  
- **fx_engine.lua**: 
  - **智能上下文检测**：自动判断 FX 应该挂载到 Track 还是 Item
  - 使用 `GetItemFromPoint` 检测鼠标位置的上下文
  - 处理 FX 窗口的显示逻辑
  
- **search.lua**: 
  - 模糊搜索算法：快速查找 Actions 和 FX
  - 支持部分匹配和权重排序

#### 🛠️ 设置界面模块 (`src/settings/`) - v1.1.0 新增
- **tab_preview.lua**: 
  - 左侧预览面板：实时显示轮盘配置效果
  - 全局设置：轮盘大小、动画速度等
  
- **tab_grid.lua**: 
  - 中间网格编辑器：显示和编辑扇区的所有插槽
  - 支持拖拽重新排列插槽
  - 插槽的添加、删除、清理操作
  
- **tab_inspector.lua**: 
  - 右侧属性编辑栏：编辑选中插槽的详细属性
  - 插槽类型选择（action/fx/chain/template）
  - 插槽标签编辑
  - 清理插槽和删除插槽功能
  
- **tab_browser.lua**: 
  - 资源浏览器：浏览和搜索 Actions、FX、Chains、Templates
  - 分类过滤（VST、VST3、JS、AU、CLAP、LV2 等）
  - 支持拖拽到插槽
  
- **tab_presets.lua**: 
  - 预设管理：保存和加载配置预设
  - 预设的创建、删除、重命名

#### 🔧 工具函数库 (`utils/`)
- **math_utils.lua**: 
  - 几何计算：角度转弧度、坐标转换、距离计算
  - 缓动函数：easeInOut、easeOut 等动画曲线
  - 颜色处理：RGB/HSV 转换、亮度调整
  
- **im_utils.lua**: 
  - ImGui 常用组件封装：按钮、输入框、下拉框等
  - UI 辅助函数：布局、对齐、间距等
  
- **json.lua**: 
  - JSON 编码/解码：配置文件的读写
  - 基于 dkjson 库实现
  
- **utils_fx.lua**: 
  - FX 扫描：扫描系统中所有已安装的 FX
  - Chains 扫描：扫描 FX Chains 文件
  - Templates 扫描：扫描轨道模板文件
  - 缓存管理：提高扫描性能

#### 📋 核心文件
- **config_manager.lua**: 
  - 配置文件的读取、保存、验证
  - 默认配置生成
  - 配置版本迁移和兼容性处理
  
- **main_runtime.lua**: 
  - 主运行时循环：轮盘菜单的核心运行逻辑
  - 处理全局输入事件（鼠标、键盘）
  - 协调 GUI 模块的渲染和交互
  - 管理菜单的显示/隐藏、Pin 状态
  
- **main_settings.lua**: 
  - 设置编辑器主文件：整合所有设置界面模块
  - 管理设置界面的标签页切换
  - 处理配置的保存和加载
  - 中央状态管理（is_modified、selected_sector_index 等）

---

## 🛠️ 技术栈

- **语言**: Lua
- **UI 框架**: ReaImGui
- **配置格式**: JSON
- **平台**: REAPER (Windows/macOS/Linux)

---

## 📦 安装要求

### 必需扩展

1. **ReaImGui** - UI 框架
   - 通过 ReaPack 安装：`Extensions > ReaPack > Browse Packages`
   - 搜索 "ReaImGui" 并安装

2. **JS_ReaScriptAPI** (可选，用于长按模式)
   - 通过 ReaPack 安装
   - 搜索 "JS_ReaScriptAPI" 并安装

### 安装步骤

1. 将整个 `RadialMenu_Tool` 文件夹复制到 REAPER 的 Scripts 目录：
   ```
   Windows: %APPDATA%\REAPER\Scripts\
   macOS: ~/Library/Application Support/REAPER/Scripts/
   Linux: ~/.config/REAPER/Scripts/
   ```

2. 在 REAPER 中：
   - 打开 `Actions > Show action list`
   - 找到 `Lee_RadialMenu.lua` 和 `Lee_RadialMenu_Setup.lua`
   - 为它们分配快捷键（推荐为 `Lee_RadialMenu.lua` 分配一个容易按的快捷键）

---

## 🚀 快速开始

### 基本使用

1. **启动轮盘菜单**：
   - 按下你分配的快捷键
   - 或运行 `Lee_RadialMenu.lua`

2. **选择扇区**：
   - 点击或悬停（取决于配置）在轮盘上的扇区
   - 子菜单会自动显示

3. **执行 Action**：
   - 点击子菜单中的按钮执行对应的 Action
   - 执行后菜单会自动关闭（除非已 Pin）

4. **Pin 模式**：
   - 点击中心圆可以固定菜单窗口
   - 固定后可以多次执行操作而不关闭菜单

### 配置菜单

1. **打开设置编辑器**：
   - 运行 `Lee_RadialMenu_Setup.lua`

2. **添加 Actions**：
   - 在左侧预览中选择扇区
   - 在右侧网格中点击空插槽
   - 从浏览器中拖放 Action 到插槽

3. **添加 FX**：
   - 点击空插槽，选择 "Add FX"
   - 从 FX 浏览器中拖放 FX 到插槽
   - 支持 VST、VST3、JS、AU、CLAP、LV2、Chain、Template

4. **编辑扇区**：
   - 在左侧面板中编辑扇区名称、图标、颜色
   - 使用"清除整个扇区"按钮清空所有插槽

5. **重新排列**：
   - 在插槽网格中拖拽插槽进行重新排列

---

## ⚙️ 配置说明

配置文件 `config.json` 位于脚本目录，包含以下主要设置：

### 菜单外观

```json
{
  "menu": {
    "outer_radius": 110,      // 外半径（像素）
    "inner_radius": 30,       // 内半径（像素）
    "hover_to_open": false,   // 悬停打开子菜单
    "max_slots_per_sector": 9 // 每个扇区最大插槽数
  }
}
```

### 扇区配置

每个扇区包含：
- `id`: 扇区 ID
- `name`: 扇区名称
- `icon`: 图标（可选）
- `color`: 颜色 [R, G, B, A]
- `slots`: 插槽数组

### 插槽配置

每个插槽包含：
- `type`: 类型 ("action", "fx", "script")
- `name`: 显示名称
- `data`: 数据对象
  - Action: `{"command_id": 12345}`
  - FX: `{"fx_name": "ReaEQ"}`
  - Script: `{"script_path": "path/to/script.lua"}`

---

## 🎯 功能状态

### ✅ 已完成

- [x] Phase 1: 基础设施与数据管理
- [x] Phase 2: 轮盘 UI 与数学计算
- [x] Phase 3: 子菜单与基本交互
- [x] Phase 4: Action 执行功能
- [x] 设置编辑器 UI
- [x] 悬停/点击模式切换
- [x] Pin 模式
- [x] FX 智能挂载引擎
- [x] FX 浏览器（支持多种格式）
- [x] 拖拽功能（从浏览器到插槽）
- [x] 内部网格交换（拖拽重新排列）
- [x] 模糊搜索功能
- [x] 智能上下文检测（Track/Item）

### 📋 计划中

- [ ] 动画效果
- [ ] 配置预设系统
- [ ] 快捷键支持（数字键快速选择）

---

## 📖 文档

- **[用户手册](USER_MANUAL.md)** - 详细的使用指南和教程
- **[更新日志](CHANGELOG.md)** - 版本更新历史

## 🐛 问题反馈

如果遇到问题，请：

1. 查看 [用户手册](USER_MANUAL.md) 的常见问题部分
2. 检查 ReaImGui 是否已安装
3. 检查配置文件格式是否正确
4. 查看 REAPER 控制台的错误信息

---

## 📄 许可证

本项目采用 MIT 许可证。

---

## 👨‍💻 作者

Lee

---

## 🙏 致谢

- 参考了 Pie3000 和其他轮盘菜单脚本的实现
- 使用 ReaImGui 社区提供的优秀工具

---

## 📝 更新日志

详细的更新日志请查看 [CHANGELOG.md](CHANGELOG.md)

### v1.0.0 (2024-12-09)
- ✨ 完整的轮盘菜单系统
- ✨ 可视化设置编辑器
- ✨ 支持 Actions、FX、Chains、Templates
- ✨ 拖拽功能（从浏览器拖放到插槽）
- ✨ 内部网格交换（拖拽插槽进行重新排列）
- ✨ 悬停打开/点击打开模式
- ✨ Pin 模式（固定菜单窗口）
- ✨ FX 浏览器（分类过滤）
- ✨ 智能上下文检测（自动判断添加到 Track 还是 Item）

---

## 🔗 相关链接

- [REAPER 官网](https://www.reaper.fm/)
- [ReaImGui 文档](https://github.com/cfillion/reaimgui)
- [REAPER 脚本开发文档](https://www.reaper.fm/sdk/reascript/reascripthelp.html)

