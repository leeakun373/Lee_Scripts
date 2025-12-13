# RadialMenu Tool - 开发路线图

本文档列出了 RadialMenu Tool 的开发阶段和任务清单。

---

## Phase 1: Infrastructure & Data (基础设施与数据) ✅ 已完成

### 配置系统

- [x] **Setup `index.lua` to check for ReaImGui installation**

  - 检查 `reaper.ImGui_CreateContext` 是否存在
  - 如果不存在，显示错误消息并退出
  - 设置模块搜索路径
- [x] **Implement `config_manager.lua` to create a default JSON if none exists**

  - 实现 `get_config_path()` 函数
  - 实现 `get_default()` 函数，返回默认配置结构
  - 实现 `load()` 函数，加载配置或创建默认配置
  - 实现 `save(config)` 函数，保存配置到文件
  - 实现 `validate(config)` 函数，验证配置结构
- [x] **Define the JSON structure (Sectors -> Slots -> Data)**

  - 定义配置文件的完整数据结构
  - 包含菜单外观设置（半径、颜色等）
  - 包含扇区数组，每个扇区包含：
    - id, name, icon, color
    - slots 数组，每个 slot 包含：
      - type ("action", "fx", "script")
      - name, data, description

### JSON 库

- [x] **Implement `json.lua` encode/decode functions**
  - 实现 `encode(data)` 函数
  - 实现 `decode(json_string)` 函数
  - 实现 `load_from_file(path)` 函数
  - 实现 `save_to_file(data, path)` 函数
  - 处理各种数据类型和错误情况

---

## Phase 2: The Wheel (UI & Math) (轮盘界面与数学) ✅ 已完成

### 数学工具

- [x] **Implement `math_utils.lua`: Function `GetMouseAngleAndDistance()`**

  - 实现 `get_mouse_angle_and_distance(mouse_x, mouse_y, center_x, center_y)`
  - 返回鼠标相对于中心的角度（弧度）和距离
  - 实现角度归一化函数
- [x] **Implement geometry helper functions**

  - 实现 `polar_to_cartesian(angle, radius)`
  - 实现 `cartesian_to_polar(x, y)`
  - 实现 `is_point_in_sector(angle, distance, ...)`
  - 实现 `is_point_in_ring(px, py, cx, cy, inner_r, outer_r)`

### 轮盘绘制

- [x] **Implement `gui/wheel.lua`: Use `ImDrawList` to draw 6 static sectors**

  - 实现 `draw_wheel(ctx, config)` 主绘制函数
  - 实现 `draw_sector(...)` 绘制单个扇区
  - 实现 `draw_sector_arc(...)` 绘制扇形弧
  - 实现 `draw_center_circle(...)` 绘制中心圆
  - 实现 `draw_sector_text(...)` 在扇区中绘制文本和图标
- [x] **Add logic to highlight the sector based on mouse angle**

  - 实现 `get_hovered_sector(mouse_x, mouse_y, center_x, center_y, config)`
  - 根据鼠标角度和距离判断悬停的扇区
  - 改变悬停扇区的颜色（高亮效果）

### 样式系统

- [x] **Implement `gui/styles.lua`: Define colors, fonts, and spacing**
  - 定义颜色常量（背景、文本、悬停等）
  - 定义尺寸常量（半径、边框宽度等）
  - 实现 `apply_theme(ctx)` 应用样式
  - 实现 `rgba_to_u32()` 颜色转换函数

### 主运行时

- [x] **Implement `main_runtime.lua`: Main loop with defer**
  - 实现 `init()` 初始化 ImGui 上下文
  - 实现 `loop()` 主循环（使用 defer）
  - 实现 `draw()` 绘制界面
  - 实现 `cleanup()` 清理资源
  - 实现 `run()` 启动函数

---

## Phase 3: The Submenu & Interaction (子菜单与交互) ✅ 已完成

### 列表视图

- [x] **Implement `gui/list_view.lua`: Show a window/child next to the active sector**

  - 实现 `draw_submenu(ctx, sector_data)` 绘制子菜单
  - 实现 `draw_slot_item(ctx, slot, index)` 绘制单个插槽项
  - 实现 `calculate_submenu_position(...)` 计算子菜单位置
  - 确保子菜单不超出屏幕边界
- [x] **Populate list from the Config data**

  - 从配置中读取扇区的 slots 数据
  - 动态显示列表项
  - 实现空状态提示（扇区无插槽时）

### 交互逻辑

- [x] **Implement click handling**
  - 实现 `handle_item_click(slot)` 处理列表项点击
  - 根据 slot.type 调用相应的执行函数
  - 在 `main_runtime.lua` 中实现 `handle_input()`
  - 实现 `on_sector_click(sector)` 和 `on_slot_click(slot)`

### 动作执行

- [x] **Implement `logic/actions.lua`: Wrappers to execute Reaper Command IDs**
  - 实现 `execute_command(command_id)` 执行 Reaper 命令
  - 实现 `execute_named_command(command_name)` 通过名称执行
  - 实现 `execute_script(script_path)` 执行外部脚本
  - 实现命令历史记录功能
  - 添加错误处理和日志记录

---

## Phase 4: Logic Implementation (业务逻辑实现) ✅ 已完成

### FX 引擎

- [x] **Implement `logic/fx_engine.lua`: `SmartAddFX(name)` function (Item vs Track detection)**
  - 实现 `determine_target()` 判断挂载目标
    - 优先级：选中的 Item > 选中的 Track
  - 实现 `add_fx_to_track(track, fx_name)` 添加 FX 到轨道
  - 实现 `add_fx_to_item(item, fx_name)` 添加 FX 到 Item
  - 实现 `smart_add_fx(fx_name)` 智能添加 FX
  - 可选：实现 FX 预设加载功能

### 拖拽功能 ✅ 已实现

- [x] **Implement Drag & Drop logic (from ImGui item to Reaper window)**
  - ✅ 实现了从浏览器到插槽的拖拽功能
  - ✅ 实现了内部网格交换（拖拽插槽重新排列）
  - ✅ 使用 Tooltip 防止拖拽反馈被窗口裁切
  - ✅ 修复了拖拽与悬停打开逻辑冲突

### 搜索功能

- [x] **Implement Fuzzy Search in the Settings menu**
  - 实现 `logic/search.lua`：
    - `fuzzy_search(query, items, options)` 模糊搜索
    - `calculate_similarity(query, text)` 相似度计算
    - `levenshtein_distance(s1, s2)` 编辑距离算法
  - 在设置编辑器中实现搜索栏
  - 实现搜索结果的实时过滤和显示

### 设置编辑器

- [x] **Implement `main_settings.lua`: Settings Editor UI**
  - 实现 `init()` 和 `loop()` 主循环
  - 实现 `draw_sector_list()` 扇区列表面板
  - 实现 `draw_sector_editor()` 扇区编辑器
  - 实现 `draw_slot_editor(slot, index)` 插槽编辑器
  - 实现 `draw_menu_bar()` 菜单栏（保存、加载、重置）
  - 实现 `draw_search_bar()` 搜索栏
  - 实现配置的增删改功能
  - ✅ 实现了 FX 浏览器（支持多种格式：VST, VST3, JS, AU, CLAP, LV2, Chain, Template）

---

## Phase 5: Polish & Advanced Features (优化与高级功能)

### UI 优化

- [ ] **添加动画效果**

  - 扇区悬停时的平滑过渡
  - 子菜单的淡入淡出
  - 鼠标移动的响应式动画
- [ ] **改进视觉效果**

  - 添加阴影和渐变
  - 优化颜色方案

### 功能增强

- [ ] **快捷键支持**

  - 实现全局快捷键呼出菜单
  - 实现数字键快速选择扇区
  - 实现搜索模式快捷键
- [ ] **配置预设**

  - 支持多配置文件切换
  - 提供默认预设模板
  - 导入/导出配置功能
- [ ] **扩展性**

  - 支持自定义扇区数量
  - 支持子菜单的嵌套层级
  - 插件系统（允许第三方扩展）

### 文档与测试

- [x] **完善文档**

  - ✅ 用户使用手册 (USER_MANUAL.md)
  - ✅ README.md 更新
  - ✅ 配置文件格式说明
  - ⏳ API 文档（待补充）
  - ⏳ 开发者指南（待补充）
- [x] **测试**

  - ✅ 功能测试清单
  - ✅ 边界情况测试
  - ✅ 性能优化
  - ✅ Bug 修复

---

## 当前状态

**v1.0.0 已完成！所有核心功能已实现。**

- ✅ **Phase 1 已完成** (Infrastructure & Data)
  - ✅ JSON 库（使用 dkjson）
  - ✅ 配置管理器（完整实现）
  - ✅ 入口脚本（依赖检查、路径设置）
- ✅ **Phase 2 已完成** (The Wheel - UI & Math)
  - ✅ 数学工具和几何计算
  - ✅ 轮盘绘制和悬停检测
  - ✅ 样式系统
  - ✅ 主运行时循环
- ✅ **Phase 3 已完成** (The Submenu & Interaction)
  - ✅ 列表视图和子菜单
  - ✅ 交互逻辑
  - ✅ 动作执行系统
- ✅ **Phase 4 已完成** (Logic Implementation)
  - ✅ FX 智能挂载引擎
  - ✅ 拖拽功能（浏览器到插槽，内部网格交换）
  - ✅ 模糊搜索功能
  - ✅ 设置编辑器 UI
  - ✅ FX 浏览器（支持多种格式）
- ⏳ **Phase 5 部分完成** (Polish & Advanced Features)
  - ✅ 悬停/点击模式切换
  - ✅ Pin 模式
  - ✅ 智能上下文检测
  - ⏳ 动画效果（待实现）
  - ⏳ 快捷键支持（待实现）
  - ⏳ 配置预设系统（待实现）

---

## 开发建议

1. **按阶段顺序开发**：先完成 Phase 1，再进入 Phase 2，以此类推
2. **测试驱动**：每完成一个功能，立即测试
3. **迭代优化**：先实现基本功能，再逐步优化
4. **保持模块化**：确保模块间松耦合，易于维护
5. **记录进展**：在此文件中标记已完成的任务（将 `[ ]` 改为 `[x]`）

---

## 开发时间估算

- Phase 1: 2-3 天
- Phase 2: 3-4 天
- Phase 3: 2-3 天
- Phase 4: 3-4 天
- Phase 5: 3-5 天

**总计：约 13-19 天**（根据实际情况可能有所调整）
