-- @description RadialMenu Tool - Runtime animation helpers
-- @about
--   Animation calculations (dt-driven) and anim_active policy.

local M = {}

local math_utils = require("math_utils")

function M.calc_wheel_open_scale(config, anim_open_start_time, now)
  local anim_scale = 1.0
  if config and config.menu and config.menu.animation and config.menu.animation.enable then
    local open_dur = config.menu.animation.duration_open or 0.06
    local t_open = math.max(0, math.min(1, (now - (anim_open_start_time or 0)) / open_dur))
    anim_scale = math_utils.ease_out_cubic(t_open)
  end
  return anim_scale
end

-- Updates R.anim_active based on mouse movement / open anim / recent interact.
function M.update_anim_active_policy(R, should_update, anim_scale, now)
  R.anim_active = false

  if not R.is_open then
    return
  end

  if should_update then
    local mouse_x, mouse_y = reaper.ImGui_GetMousePos(R.ctx)
    if R.last_mouse_x and R.last_mouse_y then
      local ui_scale = 1.0
      local font_size = reaper.ImGui_GetFontSize(R.ctx)
      if font_size and font_size > 0 then
        ui_scale = font_size / 13.0
      end
      local mouse_threshold = 2.0 * ui_scale
      local mouse_dx = math.abs(mouse_x - R.last_mouse_x)
      local mouse_dy = math.abs(mouse_y - R.last_mouse_y)
      if mouse_dx > mouse_threshold or mouse_dy > mouse_threshold then
        R.anim_active = true
      end
      R.last_mouse_x = mouse_x
      R.last_mouse_y = mouse_y
    else
      R.anim_active = true
      R.last_mouse_x = mouse_x
      R.last_mouse_y = mouse_y
    end
  end

  if anim_scale < 1.0 then
    R.anim_active = true
  end

  if (now - (R.last_interact_time or 0)) < 0.2 then
    R.anim_active = true
  end
end

-- Updates R.sector_anim_states for hover expansion and flags anim_active when in-flight.
-- Returns current_hover_id.
-- 【已废弃】保留此函数以向后兼容，但推荐使用 update_sector_expansion_with_active
function M.update_sector_expansion(R, config, should_update, center_x, center_y)
  local expansion_enabled = (config.menu.enable_sector_expansion ~= false)
  local current_hover_id = nil

  if should_update and expansion_enabled and config.sectors and R.last_mouse_x and R.last_mouse_y then
    local angle, distance = math_utils.get_mouse_angle_and_distance(R.last_mouse_x, R.last_mouse_y, center_x, center_y)
    local ir = config.menu.inner_radius
    local orr = config.menu.outer_radius

    if distance >= ir and distance <= orr then
      local sector_index = math_utils.angle_to_sector_index(angle, #config.sectors, -math.pi / 2)
      if sector_index >= 1 and sector_index <= #config.sectors then
        current_hover_id = config.sectors[sector_index].id
      end
    end

    if current_hover_id ~= R.last_hover_sector_id then
      R.anim_active = true
      R.last_hover_sector_id = current_hover_id
    end
  else
    current_hover_id = R.last_hover_sector_id
  end

  if config.sectors then
    for _, sector in ipairs(config.sectors) do
      local id = sector.id
      local current_val = R.sector_anim_states[id] or 0.0
      local target_val = 0.0  -- 【关键】默认必须是 0

      -- 【修复1：关闭功能时强制重置】必须要有 else，否则会残留状态
      if expansion_enabled then
        local is_active_submenu = (R.show_submenu and R.clicked_sector and R.clicked_sector.id == id)
        -- 【修复】确保 ID 比较正确，使用字符串比较避免类型问题
        local hover_match = (current_hover_id ~= nil and tostring(id) == tostring(current_hover_id))
        if hover_match or is_active_submenu then
          target_val = 1.0
        else
          -- 鼠标未悬停且未激活子菜单时，目标值强制为 0
          target_val = 0.0
        end
      else
        -- 【修复1：关闭动画时，强制目标值为 0，清除残留状态】
        target_val = 0.0
      end

      local speed_level_raw = config.menu.hover_animation_speed or 8
      local speed_level
      if type(speed_level_raw) == "number" then
        if speed_level_raw < 1 then
          speed_level = math.max(1, math.min(10, math.floor((speed_level_raw / 0.05) + 0.5)))
        else
          speed_level = math.max(1, math.min(10, math.floor(speed_level_raw + 0.5)))
        end
      else
        speed_level = 4
      end

      local k = 6 + (speed_level - 1) * 2
      local settle_epsilon = 0.002
      
      -- 【修复】当鼠标离开扇区时（target_val 从 1.0 变为 0.0），立即重置，不进行平滑过渡
      -- 这样颜色会立即消失，符合 Sexan 的交互体验
      if target_val == 0.0 and current_val > 0.0 then
        -- 鼠标离开时立即重置
        R.sector_anim_states[id] = 0.0
        R.anim_active = true
      elseif math.abs(current_val - target_val) > settle_epsilon then
        -- 鼠标进入时使用平滑过渡
        local alpha = 1 - math.exp(-k * (R.current_frame_dt or 0.0))
        R.sector_anim_states[id] = current_val + (target_val - current_val) * alpha
        R.anim_active = true
      else
        R.sector_anim_states[id] = target_val
      end
    end
  end

  return current_hover_id
end

-- 【新增】使用已计算好的 active_sector_id 更新扇区扩展动画
-- 这是"先算后画"架构的关键函数，避免重复计算
function M.update_sector_expansion_with_active(R, config, should_update, active_sector_id)
  local expansion_enabled = (config.menu.enable_sector_expansion ~= false)
  local current_hover_id = active_sector_id or nil

  -- 更新 hover 状态变化标志
  if current_hover_id ~= R.last_hover_sector_id then
    R.anim_active = true
    R.last_hover_sector_id = current_hover_id
  end

  -- 更新每个扇区的动画状态
  if config.sectors then
    for _, sector in ipairs(config.sectors) do
      local id = sector.id
      local current_val = R.sector_anim_states[id] or 0.0
      local target_val = 0.0  -- 【关键】默认必须是 0

      -- 【修复1：关闭功能时强制重置】必须要有 else，否则会残留状态
      if expansion_enabled then
        local is_active_submenu = (R.show_submenu and R.clicked_sector and R.clicked_sector.id == id)
        -- 【修复】确保 ID 比较正确，使用字符串比较避免类型问题
        local hover_match = (current_hover_id ~= nil and tostring(id) == tostring(current_hover_id))
        if hover_match or is_active_submenu then
          target_val = 1.0
        else
          -- 鼠标未悬停且未激活子菜单时，目标值强制为 0
          target_val = 0.0
        end
      else
        -- 【修复1：关闭动画时，强制目标值为 0，清除残留状态】
        target_val = 0.0
      end

      local speed_level_raw = config.menu.hover_animation_speed or 8
      local speed_level
      if type(speed_level_raw) == "number" then
        if speed_level_raw < 1 then
          speed_level = math.max(1, math.min(10, math.floor((speed_level_raw / 0.05) + 0.5)))
        else
          speed_level = math.max(1, math.min(10, math.floor(speed_level_raw + 0.5)))
        end
      else
        speed_level = 4
      end

      local k = 6 + (speed_level - 1) * 2
      local settle_epsilon = 0.002
      
      -- 【修复】当鼠标离开扇区时（target_val 从 1.0 变为 0.0），立即重置，不进行平滑过渡
      -- 这样颜色会立即消失，符合 Sexan 的交互体验
      if target_val == 0.0 and current_val > 0.0 then
        -- 鼠标离开时立即重置
        R.sector_anim_states[id] = 0.0
        R.anim_active = true
      elseif math.abs(current_val - target_val) > settle_epsilon then
        -- 鼠标进入时使用平滑过渡
        local alpha = 1 - math.exp(-k * (R.current_frame_dt or 0.0))
        R.sector_anim_states[id] = current_val + (target_val - current_val) * alpha
        R.anim_active = true
      else
        R.sector_anim_states[id] = target_val
      end
    end
  end

  return current_hover_id
end

return M
