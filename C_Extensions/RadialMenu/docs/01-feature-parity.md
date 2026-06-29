# 功能对照（Lua 基线 → C++）

## 运行时

- [x] 热键按住打开 / 松开关闭（`JS_VKeys`）
- [x] Pin、扇区 hover / 点击、`hover_to_open` 离开扇区收起子菜单
- [x] 子菜单 4×3 网格（至少 12 格）、空槽占位按钮、圆角/半透明样式
- [x] 扇区膨胀（指数进入、离开归零）、`anim_enable` + `duration_open`
- [x] 扇区颜色分段插值（Mantrika）
- [x] Pin 模式 hover 限制在外半径内
- [x] 外圈左键：先关子菜单，再关轮盘（非 Pin）
- [x] 拖拽槽位时主轮盘 `NoInputs` 穿透
- [x] 管理模式：Setup 虚拟扇区 + 预设切换
- [x] Perf HUD（简化计时显示，`show_perf_hud`）
- [x] 配置热重载（`RadialMenu/ConfigUpdated`）
- [ ] 单窗口 + submenu bake（C++ 采用双窗口方案 A，行为已对齐）

## 执行

- [x] `action` / `fx` / `chain` / `template`
- [x] NamedCommand 字符串、`CF_GetCommandText` 自动填名（Setup Inspector）

## Setup

- [x] Lua 式左右分栏：预览 + 全局/子菜单/动画滑块 | 网格 + Inspector + Browser
- [x] `DrawSetupPreview`（非运行时 `DrawWheel`）
- [x] Catalog `RequestBuild`、FX 过滤（含 Chain/Template 扫描）
- [x] `DND_ACTION` / `DND_FX` payload、网格 `+`、右键清除、交换
- [x] Browser：Action List、Run、双击、Tab 搜索同步
- [x] 预设 Blank/Duplicate 弹窗、重置/丢弃/关闭确认
- [x] `preserve_slot_positions` 保存前占位
- [x] Markers Modern 主题、保存绿色反馈

## 刻意与 Lua 相同的不对齐项

- 运行时/预览忽略 `sector.color`（Mantrika 硬编码）
- `duration_submenu`、扇区 icon：Lua Setup 亦无 UI
- `submenu_width/height`：已写入 JSON 与 Setup 滑块；运行时子菜单尺寸仍由 slot 布局推导

## ExtState

| Section | Key | 用途 |
|---------|-----|------|
| `RadialMenu_Tool` | `Running` | 运行时互斥 |
| `RadialMenu` | `SettingsOpen` | Setup 互斥 |
| `RadialMenu` | `ConfigUpdated` | 热重载 |
| `RadialMenu` | `Language` | `zh` / `en` |

## 手测验收（重启 REAPER 后）

1. 连续开关 Setup / 轮盘 30 次无崩溃
2. Browser 有 Actions/FX；拖入网格；保存后轮盘反映配置
3. `hover_to_open`：移出扇区子菜单收起
4. 管理右键 → Setup 扇区打开设置
5. 脏数据关窗出现确认框
