-- @description RadialMenu Tool - 子菜单缓存池
-- @author Lee
-- @about
--   实现LRU缓存机制，避免频繁创建/销毁相同的子菜单
--   缓存窗口状态和布局数据，提升性能

local M = {}

-- ============================================================================
-- LRU缓存实现
-- ============================================================================

local MAX_CACHE_SIZE = 8

-- 缓存结构: { sector_id -> { data, last_used_time } }
local cache = {}
local access_order = {}  -- 用于LRU追踪的访问顺序列表

-- 获取当前时间戳（用于LRU）
local function get_timestamp()
    return reaper.time_precise()
end

-- 更新访问顺序（将key移到最前面）
local function update_access_order(sector_id)
    -- 从列表中移除（如果存在）
    for i, id in ipairs(access_order) do
        if id == sector_id then
            table.remove(access_order, i)
            break
        end
    end
    -- 添加到最前面（最近使用）
    table.insert(access_order, 1, sector_id)
end

-- 移除最旧的缓存项
local function evict_oldest()
    if #access_order == 0 then return end
    
    -- 移除列表末尾的项（最久未使用）
    local oldest_id = access_order[#access_order]
    table.remove(access_order, #access_order)
    cache[oldest_id] = nil
end

-- ============================================================================
-- 公共API
-- ============================================================================

-- 获取缓存的子菜单数据
-- @param sector_id: 扇区ID
-- @return: 缓存的子菜单数据，如果不存在则返回nil
function M.get(sector_id)
    if not sector_id then return nil end
    
    local cached = cache[sector_id]
    if cached then
        -- 更新访问时间和顺序（LRU）
        cached.last_used_time = get_timestamp()
        update_access_order(sector_id)
        return cached.data
    end
    
    return nil
end

-- 存储子菜单数据到缓存
-- @param sector_id: 扇区ID
-- @param submenu_data: 子菜单数据（包含窗口状态和布局信息）
function M.set(sector_id, submenu_data)
    if not sector_id or not submenu_data then return end
    
    -- 如果缓存已满，移除最旧的项
    if #access_order >= MAX_CACHE_SIZE then
        evict_oldest()
    end
    
    -- 存储新数据
    cache[sector_id] = {
        data = submenu_data,
        last_used_time = get_timestamp()
    }
    
    -- 更新访问顺序
    update_access_order(sector_id)
end

-- 更新缓存项的位置（不重建）
-- @param sector_id: 扇区ID
-- @param x, y: 新位置
function M.update_position(sector_id, x, y)
    local cached = cache[sector_id]
    if cached and cached.data then
        cached.data.x = x
        cached.data.y = y
        cached.last_used_time = get_timestamp()
        update_access_order(sector_id)
    end
end

-- 清除所有缓存
function M.clear()
    cache = {}
    access_order = {}
end

-- 移除特定扇区的缓存
-- @param sector_id: 扇区ID
function M.remove(sector_id)
    if not sector_id then return end
    
    cache[sector_id] = nil
    
    -- 从访问顺序列表中移除
    for i, id in ipairs(access_order) do
        if id == sector_id then
            table.remove(access_order, i)
            break
        end
    end
end

-- 获取缓存统计信息（用于调试）
function M.get_stats()
    return {
        size = #access_order,
        max_size = MAX_CACHE_SIZE,
        cached_ids = access_order
    }
end

return M

