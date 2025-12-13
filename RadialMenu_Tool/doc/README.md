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
├── Lee_RadialMenu.lua          # 主运行入口
├── Lee_RadialMenu_Setup.lua    # 设置编辑器入口
├── config.json                  # 用户配置文件（自动生成）
├── .gitignore                  # Git 忽略文件
├── README.md                   # 本文件
├── src/                        # 源代码
│   ├── config_manager.lua     # 配置文件管理
│   ├── main_runtime.lua        # 主运行时循环
│   ├── main_settings.lua       # 设置编辑器
│   ├── gui/                    # GUI 模块
│   │   ├── wheel.lua          # 轮盘绘制
│   │   ├── list_view.lua      # 子菜单列表
│   │   └── styles.lua          # 样式定义
│   └── logic/                  # 业务逻辑
│       ├── actions.lua        # Reaper Actions 执行
│       ├── fx_engine.lua      # FX 智能挂载引擎
│       └── search.lua         # 模糊搜索算法
├── utils/                      # 工具函数
│   ├── math_utils.lua         # 几何数学计算
│   ├── im_utils.lua           # ImGui 辅助函数
│   └── json.lua               # JSON 编码/解码
└── doc/                        # 文档
    ├── README.md              # 详细文档
    ├── TODO.md               # 开发路线图
    └── IMPLEMENTATION_NOTES.md # 实现说明
```

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

