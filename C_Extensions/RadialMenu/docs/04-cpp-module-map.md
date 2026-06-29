# Lua → C++ 模块对照

| Lua | C++ |
|-----|-----|
| `runtime/controller.lua` | `RuntimeWindow`（状态机 + 绘制循环） |
| `runtime/draw.lua` | `RuntimeWindow` + `WheelView` |
| `runtime/input.lua` | `InputHook` |
| `runtime/config_reload.lua` | `RuntimeWindow::maybe_reload_config` |
| `runtime/anim.lua` | `RuntimeWindow`（`anim_open_`、`sector_expand_`） |
| `runtime/perf.lua` | `RuntimeWindow`（`show_perf_hud`） |
| `gui/wheel.lua` | `WheelView` |
| `gui/list_view*.lua` | `RuntimeWindow::tick` 子菜单块 + `LayoutBake` |
| `logic/execution.lua` | `Execution` |
| `config_manager.lua` | `ConfigStore` |
| `config_defaults.lua` | `ConfigDefaults` |
| `settings/controller.lua` | `SetupWindow` |
| `settings/tabs/*.lua` | `SetupWindow`（内联 tab） |
| `utils/math_utils.lua` | `HitTest` + `Geometry.h` |
| `utils/utils_fx.lua` | `Catalog` |
| `utils/i18n.lua` | `I18n` |
| — | `UiNotify`（消息框、context 句柄释放） |
