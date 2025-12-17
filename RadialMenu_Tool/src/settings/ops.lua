-- @description RadialMenu Tool - Settings operations
-- @about
--   Pure config/state operations used by settings controller.

local M = {}

function M.deep_copy_config(src)
  if type(src) ~= "table" then
    return src
  end

  local dst = {}
  for key, value in pairs(src) do
    if type(value) == "table" then
      dst[key] = M.deep_copy_config(value)
    else
      dst[key] = value
    end
  end

  -- Handle array part
  if #src > 0 then
    for i = 1, #src do
      if type(src[i]) == "table" then
        dst[i] = M.deep_copy_config(src[i])
      else
        dst[i] = src[i]
      end
    end
  end

  return dst
end

-- Preserve slot positions by filling gaps with "empty" placeholders.
function M.preserve_slot_positions(config)
  if not (config and config.sectors and config.menu) then return end

  for _, sector in ipairs(config.sectors) do
    if sector.slots then
      local real_max = 0
      for k, _ in pairs(sector.slots) do
        if type(k) == "number" and k > real_max then
          real_max = k
        end
      end

      local max_index = math.max(config.menu.max_slots_per_sector or 9, real_max)
      local fixed_slots = {}

      for i = 1, max_index do
        if sector.slots[i] and sector.slots[i].type ~= "empty" then
          table.insert(fixed_slots, sector.slots[i])
        else
          table.insert(fixed_slots, { type = "empty" })
        end
      end

      sector.slots = fixed_slots
    end
  end
end

-- Adjust sector count with stash-based restore.
-- Mutates config.sectors and removed_sector_stash.
function M.adjust_sector_count(config, state, removed_sector_stash, new_count)
  if not (config and config.sectors) then return end

  local current_count = #config.sectors
  if new_count == current_count then return end

  removed_sector_stash = removed_sector_stash or {}

  if new_count < current_count then
    for i = current_count, new_count + 1, -1 do
      removed_sector_stash[i] = M.deep_copy_config(config.sectors[i])
      table.remove(config.sectors, i)
    end

    if state and state.selected_sector_index and state.selected_sector_index > new_count then
      state.selected_sector_index = nil
      state.selected_slot_index = nil
    end
  else
    for i = current_count + 1, new_count do
      if removed_sector_stash[i] then
        local restored_sector = M.deep_copy_config(removed_sector_stash[i])
        restored_sector.id = i
        table.insert(config.sectors, restored_sector)
      else
        table.insert(config.sectors, {
          id = i,
          name = "扇区 " .. i,
          color = { 26, 26, 26, 180 },
          slots = {},
        })
      end
    end
  end

  for i, sector in ipairs(config.sectors) do
    sector.id = i
  end
end

return M
