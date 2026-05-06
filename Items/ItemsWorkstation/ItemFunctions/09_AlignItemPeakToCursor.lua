--[[
  Item Function: Slip-Edit Align Peak to Cursor
  Description: 使用 Slip Edit 方式将选中Item的最高波峰对齐到光标线
  - 在光标前后小范围内（默认200ms）搜索每个选中Item的最高波峰
  - 保持Item位置和长度不变，仅调整Start Offset（起始偏移量）
  - 支持多通道音频
  - 自动跳过静音区域（阈值 -60dB）
  - 适用于在不破坏剪辑节奏的情况下微调对齐
]]

local proj = 0

-- 核心参数设置
local search_window_ms = 200  -- 搜索范围：光标前后各 200 毫秒

-- Execute function
local function execute()
    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()
    
    local cursor_pos = reaper.GetCursorPosition()
    local num_sel = reaper.CountSelectedMediaItems(proj)
    
    if num_sel == 0 then
        reaper.Undo_EndBlock("Slip-Edit Align Peak to Cursor", -1)
        reaper.PreventUIRefresh(-1)
        return false, "Error: No items selected"
    end

    local search_window = search_window_ms / 1000
    local aligned_count = 0
    local skipped_count = 0

    for i = 0, num_sel - 1 do
        local item = reaper.GetSelectedMediaItem(proj, i)
        local take = reaper.GetActiveTake(item)
        
        if take and not reaper.TakeIsMIDI(take) then
            -- 获取 Item 的位置信息
            local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            
            -- 获取当前的 Start Offset (素材起始偏移)
            local current_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
            
            -- 计算光标相对于 Item 的时间位置
            local cursor_in_item = cursor_pos - item_pos
            
            -- 只有光标在 Item 范围内才处理
            if cursor_in_item >= 0 and cursor_in_item <= item_len then
                
                -- 定义搜索区间
                local search_start = cursor_in_item - search_window
                local search_end = cursor_in_item + search_window
                
                -- 边界检查 (相对于 Item 内部显示的时间)
                if search_start < 0 then search_start = 0 end
                if search_end > item_len then search_end = item_len end
                
                if search_end > search_start then
                    -- 准备音频读取
                    local source = reaper.GetMediaItemTake_Source(take)
                    local samplerate = reaper.GetMediaSourceSampleRate(source)
                    local n_channels = reaper.GetMediaSourceNumChannels(source)
                    
                    local num_samples = math.ceil((search_end - search_start) * samplerate)
                    
                    if num_samples > 0 then
                        local accessor = reaper.CreateTakeAudioAccessor(take)
                        local buffer = reaper.new_array(num_samples * n_channels)
                        
                        -- 读取采样
                        reaper.GetAudioAccessorSamples(accessor, samplerate, n_channels, search_start, num_samples, buffer)
                        
                        -- 寻找最大峰值
                        local max_peak_val = -1
                        local max_peak_idx = -1
                        local tbl = buffer.table()
                        
                        for s = 0, num_samples - 1 do
                            local abs_sum = 0
                            for c = 0, n_channels - 1 do
                                local val = math.abs(tbl[s * n_channels + c + 1])
                                if val > abs_sum then abs_sum = val end
                            end
                            if abs_sum > max_peak_val then
                                max_peak_val = abs_sum
                                max_peak_idx = s
                            end
                        end
                        
                        reaper.DestroyAudioAccessor(accessor)
                        
                        -- 执行 Slip Edit
                        if max_peak_val > 0.001 then
                            -- 计算峰值所在的绝对时间位置
                            local peak_time_in_item = search_start + (max_peak_idx / samplerate)
                            local peak_abs_pos = item_pos + peak_time_in_item
                            
                            -- 计算偏差值：峰值位置 - 光标位置
                            -- 如果峰值在光标右边(>0)，我们需要把波形往左移(增加 Offset)
                            -- 如果峰值在光标左边(<0)，我们需要把波形往右移(减少 Offset)
                            local diff = peak_abs_pos - cursor_pos
                            
                            -- 更新 Start Offset
                            local new_offset = current_offset + diff
                            
                            -- 应用更改 (Reaper 会自动处理 Loop 或者是负数 Offset 的情况)
                            reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", new_offset)
                            
                            -- 强制刷新 Item 更新波形显示
                            reaper.UpdateItemInProject(item)
                            
                            aligned_count = aligned_count + 1
                        else
                            skipped_count = skipped_count + 1
                        end
                    end
                else
                    skipped_count = skipped_count + 1
                end
            else
                skipped_count = skipped_count + 1
            end
        else
            skipped_count = skipped_count + 1
        end
    end
    
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Slip-Edit Align Peak to Cursor", -1)
    reaper.PreventUIRefresh(-1)
    
    if aligned_count > 0 then
        return true, string.format("Slip-aligned %d item(s) to cursor", aligned_count)
    else
        return false, "No items aligned (no peaks found, cursor outside items, or items are MIDI)"
    end
end

-- Return module
return {
    name = "Slip-Edit Align Peak",
    description = "Slip-edit align selected items' peak to cursor (200ms, keeps item position)",
    execute = execute,
    buttonColor = {0x0F766EFF, 0x0F766EFF + 0x11111100, 0x0F766EFF - 0x11111100}  -- Use theme color (will be overridden)
}

