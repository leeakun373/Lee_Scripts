-- Shared/Toolbox/framework/ui_font.lua
-- 字体层级：default / heading / bold。
-- 不强依赖任何外部字体文件；如果 fonts/ 里有 .ttf/.otf，可优先使用。

local M = {}
local r = reaper

local function script_root()
  local src = debug.getinfo(1, "S").source
  return src:match("^@(.+[\\/])")
end

local function pick_font_from_folder(folder)
  -- 优先找一个 .ttf/.otf
  local i = 0
  local file = r.EnumerateFiles(folder, i)
  while file do
    if file:match("%.[Tt][Tt][Ff]$") or file:match("%.[Oo][Tt][Ff]$") then
      return folder .. file
    end
    i = i + 1
    file = r.EnumerateFiles(folder, i)
  end
end

local function detach_all(ctx, ImGui, fonts)
  if not fonts then
    return
  end
  for _, f in pairs(fonts) do
    pcall(ImGui.Detach, ctx, f)
  end
end

-- 根据 scale/size 变化重新 attach（返回 fonts 表）
function M.ensure(ctx, ImGui, opts)
  opts = opts or {}

  local scale = opts.scale or 1.0
  local base_size = opts.base_size or 14
  local size = math.floor(base_size * scale)
  size = math.max(10, math.min(32, size))

  M._cache = M._cache or {}
  local key = (opts.font_name or "") .. ":" .. tostring(size)
  if M._cache.key == key and M._cache.fonts then
    return M._cache.fonts
  end

  -- 重新生成
  detach_all(ctx, ImGui, M._cache.fonts)

  local fonts_dir = script_root():gsub("framework[\\/]$", "") .. "fonts\\"
  local font_file = pick_font_from_folder(fonts_dir)

  -- Windows 上更接近 nvk 的默认观感：Segoe UI
  local font_name = opts.font_name or (reaper.GetOS():match("Win") and "Segoe UI" or "sans-serif")
  local font_src = font_file or font_name

  local h1 = math.floor(size * 1.6)
  local h2 = math.floor(size * 1.25)

  local fonts = {
    default = ImGui.CreateFont(font_src, size),
    bold = ImGui.CreateFont(font_src, size, ImGui.FontFlags_Bold),
    heading1 = ImGui.CreateFont(font_src, h1, ImGui.FontFlags_Bold),
    heading2 = ImGui.CreateFont(font_src, h2, ImGui.FontFlags_Bold),
    mono = ImGui.CreateFont(reaper.GetOS():match("Win") and "Consolas" or "Menlo", size),
  }

  for _, f in pairs(fonts) do
    ImGui.Attach(ctx, f)
  end

  M._cache.key = key
  M._cache.fonts = fonts

  return fonts
end

function M.detach(ctx, ImGui)
  if not M._cache then
    return
  end
  detach_all(ctx, ImGui, M._cache.fonts)
  M._cache = nil
end

return M
