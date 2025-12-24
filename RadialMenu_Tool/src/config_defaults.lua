-- @description RadialMenu Tool - Default config values (pure data)
-- @about
--   This module must remain PURE DATA:
--   - No functions
--   - No side effects
--   - Only returns a static table

return {
  -- Schema/version marker for maintenance & migrations
  CONFIG_SCHEMA_VERSION = "1.1.7",

  -- Config version stored in config.json (kept for backward compatibility)
  version = "1.1.7",

  -- 菜单外观设置
  menu = {
    outer_radius = 90, -- 轮盘外半径
    inner_radius = 25, -- 中心圆半径（死区）
    sector_border_width = 2, -- 扇区边框宽度
    hover_brightness = 1.3, -- 悬停时亮度增加倍数
    animation_speed = 0.2, -- 动画速度
    max_slots_per_sector = 9, -- 每个扇区最大槽位数（历史字段，运行时/编辑器会动态扩展显示）
    hover_to_open = true, -- 悬停打开子菜单（true = 悬停打开，false = 点击打开）

    -- Sector Expansion Settings
    enable_sector_expansion = true, -- 启用扇区膨胀动画
    hover_expansion_pixels = 4, -- 悬停时扇区向外扩展的像素数
    hover_animation_speed = 8, -- 悬停扩展动画速度 (1-10 整数刻度)

    -- Submenu slot size
    slot_width = 65, -- 子菜单插槽宽度（像素）
    slot_height = 25, -- 子菜单插槽高度（像素）

    animation = {
      enable = true, -- 是否启用动画
      duration_open = 0.06, -- 轮盘展开时间（秒）
      duration_submenu = 0.05, -- 子菜单弹出时间（秒）
    },

    -- Window Drag Settings
    enable_window_drag = false, -- 【已废弃】是否启用窗口拖拽功能（保留代码以便未来恢复）
  },

  -- 颜色配置（RGBA格式，0-255）
  colors = {
    background = { 30, 30, 30, 240 },
    center_circle = { 50, 50, 50, 255 },
    border = { 100, 100, 100, 200 },
    hover_overlay = { 255, 255, 255, 50 },
    text = { 255, 255, 255, 255 },
    text_shadow = { 0, 0, 0, 150 },
  },

  -- 扇区配置（默认 3 个扇区）
  -- 注意：图标字符使用图标字体字符（在 setup 界面中会通过 PushFont 显示为图标）
  sectors = {
    {
      id = 1,
      name = "Actions",
      icon = "!",  -- 使用图标字体字符（原为 ⚡）
      color = { 70, 130, 180, 200 }, -- Steel Blue
      slots = {},
    },
    {
      id = 2,
      name = "FX",
      icon = "P",  -- 使用图标字体字符（原为 🎛️）
      color = { 138, 43, 226, 200 }, -- Blue Violet
      slots = {},
    },
    {
      id = 3,
      name = "View",
      icon = "j",  -- 使用图标字体字符（原为 👁️）
      color = { 34, 139, 34, 200 }, -- Forest Green
      slots = {},
    },
  },

  -- Debug 配置
  debug = {
    show_perf_hud = false, -- 是否显示性能 HUD
  },
}






