# Mantrika Tools Radial Menu 系统分析

## 📋 系统概述

**Mantrika Tools** 是一个使用 **Slint UI 框架**通过 **C++ 扩展（DLL）**方式实现的 REAPER 插件系统。其中 **Radial Menu** 是其核心功能之一。

## 🏗️ 技术架构

### 1. 技术栈

```
┌─────────────────────────────────────┐
│      REAPER 主程序                   │
│  ┌───────────────────────────────┐  │
│  │  reaper_MantrikaTools-x64.dll │  │ ← C++ 扩展插件
│  │  ┌─────────────────────────┐ │  │
│  │  │   Slint UI Framework     │ │  │ ← UI 框架
│  │  │   (slint_cpp.dll)        │ │  │ ← 运行时库 (~300KB)
│  │  └─────────────────────────┘ │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │  MantrikaTools Config/        │  │ ← 配置目录
│  │  ├── radial_menu.json         │  │
│  │  └── MantrikaTools-Config.json│  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

### 2. 文件结构

```
REAPER\UserPlugins\
├── reaper_MantrikaTools-x64.dll      # 主插件（频繁更新）
└── MantrikaTools Config\
    ├── runtime\
    │   └── slint_cpp.dll              # Slint 运行时库（大文件，但运行时只占~300KB内存）
    ├── radial_menu.json               # Radial Menu 配置
    └── MantrikaTools-Config.json      # 全局配置
```

### 3. 技术特点

- ✅ **C++ 扩展**：原生性能，功能强大
- ✅ **Slint UI 框架**：现代声明式 UI，GPU 加速
- ✅ **JSON 配置**：数据持久化，支持跨平台迁移
- ✅ **模块化设计**：配置与代码分离

## 🎯 Radial Menu 功能详解

### 1. 核心功能

#### 主界面
- **Action**: `mantrika : Synergy - Radial Menu`
- **Command ID**: `__MTK_SHOW_RADIAL_MENU`
- **UI**: 圆形菜单，鼠标悬停显示子菜单

#### 配置内容
- **Action**：REAPER 操作
- **FX**：效果器
- **Track Template**：轨道模板

#### 应用方式
1. **拖拽模式**：
   - 拖拽到目标 track 或 item 应用
   - ❌ 不支持批量应用

2. **点击模式**：
   - 选中 track/item 后点击子菜单项应用
   - ✅ 支持批量应用
   - **优先级规则**：
     - 如果 item 和其所在 track 都选中 → 应用到 item
     - 如果 item 所在 track 未选中 → 应用到最后触碰的 track

### 2. 显示模式

#### 一次性模式（Press to Show）
- 按下快捷键显示菜单
- 触发隐藏的条件：
  - 重复按键
  - 点击 REAPER 或其他内容
  - 执行子菜单中的内容

#### 按住模式（Hold to Show）
- 按住快捷键显示菜单
- 触发隐藏的条件：
  - 松开快捷键
  - 执行子菜单中的内容

### 3. 设置界面

**Action**: `mantrika : Synergy - Radial Menu Settings`
**Command ID**: `__MTK_SHOW_RADIAL_MENU_SETTINGS`

#### 左侧配置区
- **Sector Count**：扇形数量（1-6个）
- **Show Mode**：显示模式选择
- **Validate Configuration**：批量检查配置可用性
  - 不可用内容会显示红色警告
- **Save Changes**：保存配置
- **Discard Changes**：放弃更改
- **Reset to Defaults**：重置为默认（谨慎使用）

#### 右侧配置区
- **Main Menu Name**：扇形显示文本（最多13字符）
- **Copy**：复制当前扇形配置到其他扇形
- **子项配置**：
  - `:::` 拖拽手柄：调整顺序
  - **Label**：子菜单显示名称
  - **Type**：类型选择（Action / FX / Track Template）
  - **Find**：浏览并选择 REAPER 中的内容
  - **X**：删除子项
  - **[Missing]**：无效内容红色提示

### 4. 数据持久化

**配置文件位置**：
```
REAPER\UserPlugins\MantrikaTools Config\radial_menu.json
```

**特点**：
- ✅ JSON 格式，包含所有配置项
- ⚠️ 不建议手动修改
- ✅ 支持跨电脑、跨平台迁移
- ✅ 迁移后建议使用 Validate Configuration 验证

## 🔍 技术实现分析

### 1. Slint UI 框架的优势

根据文档和实现，Slint 在这个项目中的优势：

#### 性能优势
- **运行时内存占用小**：虽然 `slint_cpp.dll` 文件很大，但运行时只占约 300KB 内存
- **GPU 加速渲染**：流畅的圆形菜单动画和交互
- **原生性能**：C++ 编译代码，执行速度快

#### UI 优势
- **声明式 UI**：类似 HTML/CSS，易于设计和维护
- **现代界面**：支持主题切换（Dark/Light）
- **响应式设计**：支持不同屏幕尺寸

#### 开发优势
- **配置分离**：UI 设计与业务逻辑分离
- **易于扩展**：可以轻松添加新功能

### 2. 架构设计亮点

#### 模块化设计
```
主插件 DLL
├── Radial Menu 模块
├── Settings 模块
├── Assistants 模块（Auto Transient Detection, Auto Mirror, etc.）
└── 其他功能模块
```

#### 配置管理
- **JSON 配置**：所有配置存储在 JSON 文件中
- **验证机制**：Validate Configuration 功能确保配置有效性
- **迁移支持**：跨平台配置迁移

#### 用户体验
- **两种显示模式**：适应不同使用习惯
- **拖拽和点击**：灵活的交互方式
- **批量操作支持**：提高工作效率
- **智能应用规则**：自动判断应用目标（item vs track）

## 💡 对你的项目的启示

### 1. 技术选型建议

#### 如果追求性能和现代 UI（类似 Mantrika）
- ✅ **C++ 扩展 + Slint**
  - 性能最佳
  - UI 最现代
  - 但开发复杂度高

#### 如果追求快速开发和维护
- ✅ **Lua 脚本 + ReaImGui**
  - 开发速度快
  - 完全兼容 REAPER
  - 社区支持好

#### 如果追求平衡
- ✅ **Lua 脚本 + rtk**
  - 现代框架体验
  - 性能优秀
  - 开发相对简单

### 2. 功能设计参考

#### Radial Menu 核心功能
1. **圆形菜单布局**
   - 支持 1-6 个扇形
   - 鼠标悬停显示子菜单
   - 角度计算和交互

2. **配置系统**
   - 图形化配置界面
   - 支持 Action、FX、Track Template
   - 配置验证机制

3. **应用机制**
   - 拖拽模式
   - 点击模式
   - 智能目标判断

4. **显示模式**
   - 一次性模式
   - 按住模式

#### 可以借鉴的设计
- ✅ **配置验证**：Validate Configuration 功能
- ✅ **配置迁移**：跨平台 JSON 配置
- ✅ **智能应用规则**：自动判断应用目标
- ✅ **批量操作**：提高效率

### 3. 实现路径建议

#### 阶段 1：原型验证（Lua + ReaImGui）
- 快速实现基本功能
- 验证交互逻辑
- 测试用户体验

#### 阶段 2：功能完善（Lua + ReaImGui/rtk）
- 添加配置界面
- 实现配置持久化
- 优化交互体验

#### 阶段 3：性能优化（可选，C++ + Slint）
- 如果 Lua 版本性能不足
- 如果需要更现代的 UI
- 如果有 C++ 开发能力

## 📊 对比分析

| 特性 | Mantrika (C++ + Slint) | Lokasenna (Lua + GUI) | 你的项目建议 |
|------|----------------------|---------------------|------------|
| **性能** | ⭐⭐⭐ 优秀 | ⭐⭐ 良好 | Lua + ReaImGui: ⭐⭐⭐ |
| **UI 现代性** | ⭐⭐⭐ 非常现代 | ⭐⭐ 传统 | rtk: ⭐⭐⭐ |
| **开发速度** | ⭐ 慢 | ⭐⭐⭐ 快 | Lua: ⭐⭐⭐ |
| **维护成本** | ⭐⭐ 中等 | ⭐⭐⭐ 低 | Lua: ⭐⭐⭐ |
| **功能完整性** | ⭐⭐⭐ 完整 | ⭐⭐⭐ 完整 | 都可以实现 |
| **学习曲线** | ⭐⭐⭐ 陡峭 | ⭐ 平缓 | Lua: ⭐ |

## 🎯 推荐方案

### 对于你的项目（当前只对 Radial Menu 感兴趣）

#### 推荐：**Lua + ReaImGui**

**理由：**
1. ✅ **快速开发**：可以快速实现和验证功能
2. ✅ **性能足够**：ReaImGui 性能优秀，满足 Radial Menu 需求
3. ✅ **易于维护**：Lua 脚本易于修改和扩展
4. ✅ **社区支持**：有大量示例和文档
5. ✅ **渐进式开发**：可以先实现核心功能，再逐步完善

#### 实现重点
1. **圆形菜单渲染**：使用 ReaImGui 的绘图 API
2. **鼠标交互**：角度计算和扇形选择
3. **配置系统**：JSON 配置 + 图形化设置界面
4. **应用机制**：拖拽和点击两种模式

#### 如果未来需要更强大的框架
- 可以考虑用 **rtk** 重构
- 或者如果性能成为瓶颈，再考虑 **C++ + Slint**

## 📚 参考资源

### Mantrika Tools
- **安装方式**：通过 ReaPack 安装
- **GitHub**: https://github.com/qhtchestnut/Mantrika-Tools-Release
- **文档位置**：`E:\Audio_Projects\Tools\ReaScripts\Data\`

### Slint 框架
- **官网**: https://slint.dev/
- **C++ 文档**: https://slint.dev/docs/cpp/
- **示例**: https://github.com/slint-ui/slint/tree/master/examples

### REAPER 扩展开发
- **REAPER SDK**: https://www.reaper.fm/sdk/plugin/plugin.php
- **参考项目**: SWS Extension, ReaImGui

## 💡 总结

**Mantrika Tools 的 Radial Menu 是一个很好的参考实现：**

1. ✅ **证明了 Slint + C++ 扩展的可行性**
2. ✅ **展示了 Radial Menu 的完整功能设计**
3. ✅ **提供了优秀的用户体验参考**

**对于你的项目：**
- 建议先用 **Lua + ReaImGui** 实现
- 参考 Mantrika 的功能设计和交互逻辑
- 如果未来需要，再考虑升级到 C++ + Slint

**关键学习点：**
- 配置系统的设计（JSON + 验证）
- 智能应用规则（item vs track 判断）
- 两种显示模式（一次性 vs 按住）
- 拖拽和点击两种交互方式

需要我帮你规划具体的实现步骤吗？




