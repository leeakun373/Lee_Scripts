# 配置 Schema

与 [RadialMenu_Tool/config.example.json](../../../RadialMenu_Tool/config.example.json) 及 [config_defaults.lua](../../../RadialMenu_Tool/src/config_defaults.lua) 对齐。

## 顶层（磁盘文件）

```json
{
  "active_config": { ... },
  "presets": { "Default": { ... } },
  "current_preset_name": "Default"
}
```

旧格式（无 `presets`）在加载时自动迁移为 Preset 2.0。

## active_config

| 路径 | 类型 | 说明 |
|------|------|------|
| `version` | string | 如 `1.1.14` |
| `menu.outer_radius` | number | 外半径 |
| `menu.inner_radius` | number | 内圆（死区） |
| `menu.hover_to_open` | bool | 悬停开子菜单 |
| `menu.max_slots_per_sector` | int | 每扇区最大槽位 |
| `menu.slot_width` / `slot_height` | number | 子菜单按钮 |
| `menu.submenu_gap` / `submenu_padding` | number | 布局 |
| `menu.enable_sector_expansion` | bool | 扇区膨胀 |
| `menu.hover_expansion_pixels` | number | 膨胀像素 |
| `colors.*` | [r,g,b,a] | 全局颜色 |
| `sectors[]` | array | 扇区列表 |
| `sectors[].id` | number | 扇区 ID |
| `sectors[].name` | string | 显示名（支持 `\n`） |
| `sectors[].icon` | string | 图标字体字符 |
| `sectors[].color` | [r,g,b,a] | 扇区色 |
| `sectors[].slots[]` | array | 插槽 |

## 插槽

| `type` | `data` 字段 |
|--------|-------------|
| `action` | `command_id` (number 或 named string) |
| `fx` | `fx_name` |
| `chain` | `path` |
| `template` | `path` |
| `empty` | — |

C++ schema 版本常量：`CONFIG_SCHEMA_VERSION`（见 `ConfigDefaults.h`）。

保存时写入 `RadialMenu/ConfigUpdated` = Unix 时间戳字符串。
