-- @description 将选中 Item 的头部对齐到同名 Marker（极度宽容版：忽略大小写、后缀名、首尾空格）
-- @version 1.1
-- @author Gemini

-- 核心清理函数：负责剥离后缀、空格并转小写
local function clean_string(str)
    if not str then return "" end
    -- 1. 转换为小写
    local s = str:lower()
    -- 2. 去除拓展名 (例如 .wav, .mp4, .aif 等)
    s = s:gsub("%.%w+$", "")
    -- 3. 去除首尾的空格
    s = s:match("^%s*(.-)%s*$")
    return s
end

function main()
    -- 获取选中的 Item 数量
    local count_sel_items = reaper.CountSelectedMediaItems(0)
    if count_sel_items == 0 then return end

    -- 收集工程中所有的 Marker
    local markers_dict = {}
    local ret, num_markers, num_regions = reaper.CountProjectMarkers(0)
    
    for i = 0, num_markers + num_regions - 1 do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
        if not isrgn and name ~= "" then 
            local clean_name = clean_string(name)
            -- 记录 Marker 位置
            if clean_name ~= "" and not markers_dict[clean_name] then
                markers_dict[clean_name] = pos
            end
        end
    end

    -- 开启 Undo 块
    reaper.Undo_BeginBlock()

    -- 遍历并移动选中的 Item
    for i = 0, count_sel_items - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        
        if take then
            -- 获取 Take 名称并进行清理
            local retval, take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
            local clean_take_name = clean_string(take_name)

            -- 如果匹配成功，则移动 Item
            if clean_take_name ~= "" and markers_dict[clean_take_name] then
                reaper.SetMediaItemInfo_Value(item, "D_POSITION", markers_dict[clean_take_name])
            end
        end
    end

    -- 刷新界面
    reaper.UpdateArrange()
    
    -- 结束 Undo 块
    reaper.Undo_EndBlock("Align items to matching markers", -1)
    
    -- 注：已根据你的要求移除了所有弹窗提示
end

-- 执行主函数
main()
