local r = reaper

local ctx = r.ImGui_CreateContext('Chinese_Font_Test')

local font_cjk = nil

function Init()
    -- 【步骤 1】创建字体配置
    local config = r.ImGui_FontConfig_Create()
    
    -- 【步骤 2】关键！设置字符集为"简体中文通用"
    -- 如果没有这一步，即使加载了中文字体，汉字也不会显示
    local glyph_ranges = r.ImGui_FontAtlas_GetGlyphRangesChineseSimplifiedCommon(ctx)
    r.ImGui_FontConfig_SetGlyphRanges(config, glyph_ranges)
    
    -- 【步骤 3】判断系统并选择字体路径
    local font_path = ""
    if r.GetOS():match("Win") then
        font_path = "C:\\Windows\\Fonts\\msyh.ttc" -- Windows: 微软雅黑
    else
        font_path = "/System/Library/Fonts/PingFang.ttc" -- Mac: 苹方
    end
    
    -- 【步骤 4】创建并挂载字体 (字号设为 16)
    -- 注意：必须使用 Attach
    font_cjk = r.ImGui_CreateFont(font_path, 16, config)
    r.ImGui_Attach(ctx, font_cjk)
end

function Loop()
    local visible, open = r.ImGui_Begin(ctx, '中文测试窗口', true)
    if visible then
        
        -- 【步骤 5】在 UI 渲染开始时，Push 字体
        if font_cjk then
            r.ImGui_PushFont(ctx, font_cjk)
        end
        
        -- 这里写你的界面
        r.ImGui_Text(ctx, "你好，Reaper！")
        r.ImGui_Text(ctx, "这是一段测试文本：空心竹条 吹气")
        r.ImGui_Button(ctx, "点击测试")
        
        -- 【步骤 6】渲染结束时，Pop 字体 (复原)
        if font_cjk then
            r.ImGui_PopFont(ctx)
        end
        
        r.ImGui_End(ctx)
    end
    if open then r.defer(Loop) end
end

-- 执行初始化
Init()
r.defer(Loop)

