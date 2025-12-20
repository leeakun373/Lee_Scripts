# FXMiner 模块结构说明

本文档说明 FXMiner 项目重构后的模块结构。项目已从两个大型单体文件（`db.lua` 和 `gui_browser.lua`）拆分为多个小型、可维护的模块。

## 目录结构

```
FXMiner/
├── src/
│   ├── db/                       # DB 子模块目录
│   │   ├── db.lua                # DB 模块主入口（整合子模块）
│   │   ├── db_utils.lua          # 工具函数
│   │   ├── db_core.lua           # 核心 DB 操作
│   │   ├── db_fields.lua         # 动态字段配置
│   │   ├── db_entries.lua        # 条目管理
│   │   ├── db_folders.lua         # 虚拟文件夹
│   │   └── db_team_sync.lua       # 团队同步
│   ├── gui_browser.lua           # GUI 模块主入口（整合子模块）
│   ├── gui_browser/              # GUI 子模块目录
│   │   ├── gui_state.lua         # 状态管理
│   │   ├── gui_utils.lua         # GUI 工具函数
│   │   ├── gui_topbar.lua        # 顶部栏
│   │   ├── gui_settings.lua       # 设置面板
│   │   ├── gui_folders.lua       # 文件夹面板
│   │   ├── gui_list.lua          # 列表面板
│   │   ├── gui_inspector.lua     # 检查器面板
│   │   └── gui_delete_dialog.lua # 删除确认对话框
│   ├── gui_saver.lua            # 保存器 UI（独立模块，未拆分）
│   ├── fx_engine.lua            # FX 引擎（文件操作）
│   ├── config.lua               # 配置文件
│   └── json.lua                 # JSON 处理
├── Lee_FXMiner - Browser.lua    # 浏览器主入口脚本
├── Lee_FXMiner - Saver.lua      # 保存器主入口脚本
└── README.md                     # 本文档
```

## 文件清理说明

重构过程中已清理的文件：
- `src/db_old.lua` - 已删除（旧版本备份，功能已迁移到 `db/db.lua`）
- `src/db.lua` - 已删除（向后兼容入口，已不再需要）

**更新说明**：
- 主入口脚本（`Lee_FXMiner - Browser.lua` 和 `Lee_FXMiner - Saver.lua`）已更新为直接使用 `require("db.db")`
- 由于没有外部依赖，移除了中间重定向层，代码更直接清晰

保留的文件：
- `src/gui_browser.lua` - 新的模块化主入口，整合所有 GUI 子模块
- `src/gui_saver.lua` - 独立的保存器 UI，未拆分（文件较小，功能独立）

## DB 模块说明

### `db.lua` (主入口)
- **功能**: 整合所有 DB 子模块，提供统一的 DB API
- **职责**: 
  - 加载并初始化所有子模块
  - 将子模块函数整合到主 DB 表中
  - 提供 `DB:new()` 构造函数和 `DB:ensure_initialized()` 初始化函数

### `db/db_utils.lua` (工具函数)
- **功能**: 提供通用的工具函数，供其他 DB 模块使用
- **主要函数**:
  - `now_sec()`: 获取当前时间戳
  - `ensure_dir()`: 确保目录存在
  - `show_error()`: 显示错误消息
  - `read_all()`, `write_all()`, `file_exists()`: 文件 I/O
  - `path_join()`, `split_slash()`, `norm_abs_path()`: 路径操作
  - `hash32()`: 字符串哈希
  - `trim()`, `lower()`: 字符串处理
  - `add_unique()`, `ensure_array()`: 数组操作

### `db/db_core.lua` (核心操作)
- **功能**: 处理数据库的加载、保存、索引和路径解析
- **主要函数**:
  - `new()`: 创建 DB 实例
  - `load()`, `save()`: 数据库加载和保存
  - `_reindex()`: 重建索引（内部函数）
  - `make_relpath()`, `rel_to_abs()`: 路径转换
  - `entries()`: 获取所有条目
  - `find_entry_by_rel()`: 按相对路径查找条目
  - `scan_fxchains()`: 扫描 FXChain 文件
  - `prune_missing_files()`: 清理缺失文件
  - `get_all_tags()`: 获取所有标签

### `db/db_fields.lua` (动态字段配置)
- **功能**: 管理动态字段配置和条目元数据处理
- **主要函数**:
  - `load_fields_config()`: 加载字段配置
  - `get_fields_config()`: 获取字段配置
  - `load_tag_config()`: 加载标签配置（遗留）
  - `get_tag_config()`: 获取标签配置（遗留）
  - `_ensure_entry_defaults()`: 确保条目有默认值（内部）
  - `calc_status()`: 计算条目状态（indexed/unindexed）
  - `rebuild_keywords()`: 重建关键字

### `db/db_entries.lua` (条目管理)
- **功能**: 管理单个 FXChain 条目的增删改操作
- **主要函数**:
  - `add_entry()`: 添加新条目
  - `delete_entry()`: 删除条目（可选删除文件）
  - `update_entry()`: 更新条目
  - `migrate_entries()`: 迁移现有条目（兼容性）
  - `collect_used_values()`: 收集字段的已使用值

### `db/db_folders.lua` (虚拟文件夹)
- **功能**: 管理虚拟文件夹系统
- **主要函数**:
  - `load_folders()`, `save_folders()`: 加载/保存文件夹数据库
  - `get_folders()`, `get_folder()`, `get_folder_name()`: 获取文件夹信息
  - `list_children()`: 列出子文件夹
  - `create_folder()`: 创建文件夹
  - `rename_folder()`: 重命名文件夹
  - `move_folder()`: 移动文件夹
  - `create_parent_folder()`: 创建父文件夹
  - `delete_folder()`: 删除文件夹
  - `set_entry_folder()`: 将条目分配到文件夹

### `db/db_team_sync.lua` (团队同步)
- **功能**: 处理团队数据库同步，包括文件锁定机制
- **主要函数**:
  - `load_team_db()`, `save_team_db()`: 加载/保存团队数据库
  - `sync_entry_to_team()`: 同步单个条目到团队
  - `get_team_entries()`: 获取团队条目列表
  - `acquire_lock()`, `release_lock()`: 文件锁定
  - `force_release_stale_lock()`: 强制释放过期锁
  - `push_to_team_locked()`: 带锁定的推送
  - `pull_from_team()`: 从团队拉取
  - `full_sync()`: 完整同步（双向）

## GUI 模块说明

### `gui_browser.lua` (主入口)
- **功能**: 整合所有 GUI 子模块，提供统一的 GUI API
- **职责**:
  - 加载并初始化所有子模块
  - 在 `init()` 中设置依赖关系
  - 在 `draw()` 中协调各个面板的绘制
  - 处理拖放逻辑（外部拖放到 Reaper）

### `gui_browser/gui_state.lua` (状态管理)
- **功能**: 管理 GUI 的全局状态和用户配置
- **主要内容**:
  - 定义全局 `state` 表（包含所有 UI 状态）
  - `load_user_config()`: 加载用户配置（团队路径等）
  - `save_user_config()`: 保存用户配置
  - `get()`: 获取状态表
  - 状态包括：搜索词、选中项、编辑字段、文件夹状态、设置面板状态等

### `gui_browser/gui_utils.lua` (GUI 工具函数)
- **功能**: 提供 GUI 相关的工具函数和 FXChain 加载逻辑
- **主要函数**:
  - `trim()`, `lower()`, `split_tokens()`: 字符串处理
  - `array_contains()`, `array_remove()`, `array_add_unique()`: 数组操作
  - `safe_append_fxchain()`: 安全加载 FXChain（智能检测目标）
  - `safe_append_fxchain_to_track()`: 加载到轨道
  - `safe_append_fxchain_to_take()`: 加载到 Take
  - `safe_append_fxchain_to_selected_items_or_track()`: 智能加载（自动检测上下文）
  - `set_selected_entry()`: 设置选中的条目
  - `build_search_content()`, `matches_search()`: 搜索相关

### `gui_browser/gui_topbar.lua` (顶部栏)
- **功能**: 绘制顶部栏 UI，包括标题、设置按钮、关闭按钮、库模式切换、刷新按钮、搜索框和同步按钮
- **主要功能**:
  - 标题显示和状态文本
  - 设置/关闭按钮
  - Local/Team 模式切换
  - 刷新按钮
  - 文件夹快速访问按钮
  - 搜索输入框
  - 同步按钮（Pull/Push）

### `gui_browser/gui_settings.lua` (设置面板)
- **功能**: 绘制设置面板，配置团队同步路径和操作
- **主要功能**:
  - 团队服务器路径配置（输入框 + 浏览按钮）
  - 路径验证和应用
  - 团队同步操作（Full Sync、Refresh List、Clear Lock）
  - 推送选中项到团队
  - 同步状态显示
  - 同步说明文本

### `gui_browser/gui_folders.lua` (文件夹面板)
- **功能**: 管理虚拟文件夹的显示和交互
- **主要功能**:
  - 文件夹树形结构显示
  - 文件夹展开/折叠
  - 内联重命名
  - 右键菜单（新建文件夹、重命名、删除等）
  - 拖放目标（将条目移动到文件夹）
  - 工具栏按钮（添加、添加父文件夹、删除）

### `gui_browser/gui_list.lua` (列表面板)
- **功能**: 显示 FXChain 条目列表，支持多选和搜索
- **主要功能**:
  - 显示本地或团队条目列表
  - 搜索过滤
  - 多选支持（Shift+Click 范围选择，Ctrl+Click 切换）
  - 双击加载 FXChain
  - 拖放源（从列表拖出到 Reaper）
  - 右键菜单（删除）
  - 团队条目特殊显示（显示发布者）

### `gui_browser/gui_inspector.lua` (检查器面板)
- **功能**: 显示和编辑选中条目的详细信息
- **主要功能**:
  - 名称和描述编辑
  - 动态字段输入（基于 config_fields.json）
  - 保存/清除按钮
  - 删除按钮（单/多选）
  - 团队条目只读模式

### `gui_browser/gui_delete_dialog.lua` (删除确认对话框)
- **功能**: 显示删除确认模态对话框
- **主要功能**:
  - 美观的模态对话框（居中、圆角、阴影）
  - 单/多选删除确认
  - 警告消息
  - 取消/确认按钮
  - 删除操作（带 Undo 支持）

## 模块依赖关系

### DB 模块依赖
```
db.lua
├── db_utils.lua (被所有模块使用)
├── db_core.lua (依赖 db_utils)
├── db_fields.lua (依赖 db_utils)
├── db_entries.lua (依赖 db_utils, 使用 db_core 和 db_fields)
├── db_folders.lua (依赖 db_utils, 使用 db_core)
└── db_team_sync.lua (依赖 db_utils, 使用 db_core 和 db_entries)
```

### GUI 模块依赖
```
gui_browser.lua
├── gui_state.lua (独立，被所有模块使用)
├── gui_utils.lua (依赖 gui_state, 被多个模块使用)
├── gui_topbar.lua (依赖 gui_state, gui_utils)
├── gui_settings.lua (依赖 gui_state, gui_utils)
├── gui_folders.lua (依赖 gui_state, gui_utils)
├── gui_list.lua (依赖 gui_state, gui_utils)
├── gui_inspector.lua (依赖 gui_state, gui_utils, gui_list)
└── gui_delete_dialog.lua (依赖 gui_state, gui_utils, gui_list)
```

## 使用示例

### 初始化 DB
```lua
local DB = require("db")
local db = DB:new(config)
db:ensure_initialized(script_root)
```

### 初始化 GUI
```lua
local GuiBrowser = require("gui_browser")
GuiBrowser.init(app_ctx, db_instance, config)
```

### 绘制 GUI
```lua
GuiBrowser.draw(ctx)
```

## 重构优势

1. **可维护性**: 每个模块职责单一，代码更易理解和修改
2. **可测试性**: 模块化后更容易单独测试
3. **可扩展性**: 新功能可以独立添加到相应模块
4. **AI 友好**: 较小的文件更适合 AI 代码分析和生成
5. **代码复用**: 工具函数集中在独立模块，避免重复

## 注意事项

- 所有子模块通过依赖注入获得共享资源（state, App, DB, Config 等）
- 主入口文件负责初始化依赖关系
- 模块间通过导出的函数和共享的 state 表通信
- 保持向后兼容：外部 API 保持不变

## 后续优化建议

1. 考虑将拖放逻辑单独提取为模块
2. 考虑将搜索逻辑提取为独立模块
3. 考虑添加单元测试
4. 考虑添加 TypeScript 风格的类型注解（通过注释）
