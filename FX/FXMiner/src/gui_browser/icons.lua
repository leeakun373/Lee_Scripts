-- FXMiner/src/gui_browser/icons.lua
-- Remix Icons 映射表
-- 
-- 注意：如果看到"豆腐块"（矩形字符），请验证字体版本和代码点是否正确。
-- Remix Icon 的代码点可能因字体版本而异（V2/V3）。
-- 如果图标显示不正确，请检查 remixicon.ttf 的版本并调整代码点。

local Icons = {
  -- 常用图标（使用 Remix Icon V2/V3 代码点）
  -- 格式：\xHH\xHH (UTF-8 编码)
  SEARCH = "\xEE\xA2\x82",      -- ri-search-line
  FOLDER = "\xED\x95\x90",      -- ri-folder-2-line
  FOLDER_OPEN = "\xED\x95\x92", -- ri-folder-open-line
  FILE = "\xEC\xB3\xB6",        -- ri-file-list-line
  SETTINGS = "\xEF\x83\xA7",    -- ri-settings-3-line
  PLAY = "\xEF\x80\x8A",        -- ri-play-circle-line
  TRASH = "\xEB\xA6\x9D",       -- ri-delete-bin-line
  TAG = "\xEF\x81\x92",         -- ri-price-tag-3-line
  REFRESH = "\xEF\x81\xA4",     -- ri-refresh-line
  LINK = "\xEE\xBB\x8A",        -- ri-link
  PLUS = "\xEE\xAE\x8B",        -- ri-add-line (修正：应该是 \xEE\xAE\x8B)
  CLOSE = "\xEB\x99\xAB",       -- ri-close-line
}

return Icons

