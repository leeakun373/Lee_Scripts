-- @description RadialMenu Tool - FX Utils
-- @author Lee (Adapted from NVK logic)
-- @about
--   FX 和 FX Chains 扫描工具模块
--   基于 NVK 的扫描逻辑实现

local M = {}

local fx_cache = nil
local chain_cache = nil
local template_cache = nil

-- ============================================================================
-- FX 扫描
-- ============================================================================

function M.get_all_fx(force_refresh)
    if fx_cache and not force_refresh then 
        return fx_cache 
    end
    
    local list = {}
    local i = 0
    
    while true do
        local retval, name, ident = reaper.EnumInstalledFX(i)
        if not retval then 
            break 
        end
        
        -- 分类和清理名称
        local fx_type = "Other"
        local clean_name = name
        
        -- 检测类型并清理前缀
        if name:match("^VST3:") then 
            fx_type = "VST3"
            clean_name = name:gsub("^VST3: ", "")
        elseif name:match("^VST:") then 
            fx_type = "VST"
            clean_name = name:gsub("^VST: ", "")
        elseif name:match("^JS:") then 
            fx_type = "JS"
            clean_name = name:gsub("^JS: ", "")
        elseif name:match("^AU:") then 
            fx_type = "AU"
            clean_name = name:gsub("^AU: ", "")
        elseif name:match("^CLAP:") then 
            fx_type = "CLAP"
            clean_name = name:gsub("^CLAP: ", "")
        elseif name:match("^LV2:") then 
            fx_type = "LV2"
            clean_name = name:gsub("^LV2: ", "")
        end
        
        -- 添加到列表
        table.insert(list, {
            name = clean_name,
            original_name = name,  -- 用于 AddFX API
            type = fx_type,
            ident = ident  -- 插件标识符
        })
        
        i = i + 1
    end
    
    -- 按名称字母顺序排序
    table.sort(list, function(a, b) 
        return a.name:lower() < b.name:lower() 
    end)
    
    fx_cache = list
    return list
end

-- ============================================================================
-- FX Chains 扫描
-- ============================================================================

function M.get_fx_chains(force_refresh)
    if chain_cache and not force_refresh then 
        return chain_cache 
    end
    
    local resource_path = reaper.GetResourcePath()
    local sep = package.config:sub(1, 1)  -- 获取路径分隔符
    local chains_path = resource_path .. sep .. "FXChains"
    
    local list = {}
    
    -- 递归扫描目录（基于 NVK 的 MatchingFilesDirectoryTable 逻辑）
    local function scan_directory(path)
        -- 先扫描子目录
        reaper.EnumerateSubdirectories(path, -1)
        for i = 0, math.huge do
            local subdir = reaper.EnumerateSubdirectories(path, i)
            if not subdir then
                break
            end
            scan_directory(path .. sep .. subdir)
        end
        
        -- 扫描当前目录的文件
        reaper.EnumerateFiles(path, -1)
        for i = 0, math.huge do
            local file = reaper.EnumerateFiles(path, i)
            if not file then
                break
            end
            
            -- 检查是否为 .RfxChain 文件
            if file:match("%.RfxChain$") then
                local full_path = path .. sep .. file
                local chain_name = file:gsub("%.RfxChain$", "")
                
                table.insert(list, {
                    name = chain_name,
                    path = full_path,
                    original_name = file,  -- 用于 FX Chain 添加逻辑
                    type = "Chain"
                })
            end
        end
    end
    
    -- 开始扫描
    scan_directory(chains_path)
    
    -- 按名称字母顺序排序
    table.sort(list, function(a, b) 
        return a.name:lower() < b.name:lower() 
    end)
    
    chain_cache = list
    return list
end

-- ============================================================================
-- Track Templates 扫描
-- ============================================================================

function M.get_track_templates(force_refresh)
    if template_cache and not force_refresh then 
        return template_cache 
    end
    
    local resource_path = reaper.GetResourcePath()
    local sep = package.config:sub(1, 1)
    local templates_path = resource_path .. sep .. "TrackTemplates"
    
    local list = {}
    
    -- 递归扫描函数
    local function scan_directory(path, relative_path)
        relative_path = relative_path or ""
        
        -- 扫描子目录
        reaper.EnumerateSubdirectories(path, -1)
        local i = 0
        while true do
            local subdir = reaper.EnumerateSubdirectories(path, i)
            if not subdir then 
                break 
            end
            scan_directory(path .. sep .. subdir, relative_path .. subdir .. sep)
            i = i + 1
        end
        
        -- 扫描文件
        reaper.EnumerateFiles(path, -1)
        i = 0
        while true do
            local file = reaper.EnumerateFiles(path, i)
            if not file then 
                break 
            end
            
            if file:match("%.RTrackTemplate$") then
                local full_path = path .. sep .. file
                -- 清理名称：移除扩展名
                local name = file:gsub("%.RTrackTemplate$", "")
                
                table.insert(list, {
                    name = name,
                    path = full_path,
                    type = "TrackTemplate",
                    category = "Template"  -- 用于分组
                })
            end
            i = i + 1
        end
    end
    
    scan_directory(templates_path, "")
    
    -- 按名称字母顺序排序
    table.sort(list, function(a, b) 
        return a.name:lower() < b.name:lower() 
    end)
    
    template_cache = list
    return list
end

-- ============================================================================
-- 缓存管理
-- ============================================================================

-- 清除所有缓存
function M.clear_cache()
    fx_cache = nil
    chain_cache = nil
    template_cache = nil
end

-- 清除 FX 缓存
function M.clear_fx_cache()
    fx_cache = nil
end

-- 清除 Chains 缓存
function M.clear_chain_cache()
    chain_cache = nil
end

-- 清除 Track Templates 缓存
function M.clear_template_cache()
    template_cache = nil
end

return M

