-- 开启撤销块
reaper.Undo_BeginBlock()

local num_sel_items = reaper.CountSelectedMediaItems(0)

if num_sel_items > 0 then
    -- 用于按轨道存储选中的 items
    local tracks = {}
    
    -- 1. 遍历所有选中的 item 并按轨道分组
    for i = 0, num_sel_items - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local track = reaper.GetMediaItem_Track(item)
        if not tracks[track] then
            tracks[track] = {}
        end
        table.insert(tracks[track], item)
    end

    -- 2. 对每个轨道分别进行独立处理
    for track, items in pairs(tracks) do
        
        -- 对当前轨道上的选中 items 按起始位置排序，保持原始先后顺序
        table.sort(items, function(a, b)
            return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
        end)

        -- 获取该轨道上最靠前的那个选中素材的起始位置
        local first_sel_pos = reaper.GetMediaItemInfo_Value(items[1], "D_POSITION")
        
        -- 默认插入位置在工程开头 0:00
        local insert_pos = 0.0 
        local num_items_on_track = reaper.CountTrackMediaItems(track)
        
        -- 3. 判断前方是否有未选中的素材
        for i = 0, num_items_on_track - 1 do
            local item = reaper.GetTrackMediaItem(track, i)
            
            -- 如果是未选中的素材
            if not reaper.IsMediaItemSelected(item) then
                local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                
                -- 判断这个未选中素材是否在“选中的素材群体”之前
                if pos < first_sel_pos then
                    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    local end_pos = pos + len
                    
                    -- 找到前方素材中，最靠右的末尾位置作为新的插入点
                    if end_pos > insert_pos then
                        insert_pos = end_pos
                    end
                end
            end
        end

        -- 4. 从确定的 insert_pos 开始，依次无缝排列所有选中的 items
        for _, item in ipairs(items) do
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", insert_pos)
            local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            -- 更新下一个 item 的插入位置
            insert_pos = insert_pos + len
        end
    end
end

-- 刷新界面
reaper.UpdateArrange()
-- 结束撤销块
reaper.Undo_EndBlock("Move and align items to 0:00 or after preceding items", -1)
