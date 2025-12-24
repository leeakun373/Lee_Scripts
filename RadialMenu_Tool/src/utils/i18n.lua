-- @description RadialMenu Tool - 国际化/多语言支持
-- @author Lee
-- @about
--   提供中英双语切换功能

local M = {}

-- 当前语言：'zh' 中文, 'en' 英文
local current_lang = 'zh'

-- 从 ExtState 加载语言设置
local function load_language()
    local saved_lang = reaper.GetExtState("RadialMenu", "Language")
    if saved_lang == "en" or saved_lang == "zh" then
        current_lang = saved_lang
    else
        -- 默认使用中文
        current_lang = "zh"
    end
end

-- 保存语言设置
local function save_language()
    reaper.SetExtState("RadialMenu", "Language", current_lang, false)
end

-- 初始化：加载保存的语言设置
load_language()

-- 翻译表
local translations = {
    zh = {
        -- 窗口标题
        window_title = "RadialMenu 设置编辑器",
        
        -- 语言切换
        language = "语言",
        language_zh = "中文",
        language_en = "English",
        
        -- 操作栏
        save = "保存",
        discard = "丢弃",
        reset = "重置",
        
        -- 预设相关
        preset = "预设",
        new_preset = "新建预设",
        save_preset = "保存预设",
        rename = "重命名",
        delete = "删除",
        confirm = "确认",
        cancel = "取消",
        
        -- 扇区相关
        sector = "扇区",
        add_sector = "添加扇区",
        delete_sector = "删除扇区",
        sector_name = "扇区名称",
        
        -- 插槽相关
        slot = "插槽",
        empty = "空",
        clear = "清除",
        clean_slot = "清理插槽",
        delete_slot = "删除插槽",
        
        -- 类型
        type = "类型",
        action = "动作",
        fx = "效果器",
        chain = "链",
        template = "模板",
        
        -- 预览相关
        preview = "预览",
        enable_sector_expansion = "启用扇区膨胀动画",
        expansion_amount = "膨胀幅度",
        expansion_speed = "膨胀速度",
        hover_to_open = "悬停打开子菜单",
        
        -- 浏览器
        browser = "浏览器",
        list = "列表",
        run = "运行",
        actions = "Actions",
        fx_short = "FX",
        
        -- 通用
        px = "px",
        
        -- 错误和确认消息
        error = "错误",
        confirm = "确认",
        error_reaimgui_not_available = "错误: ReaImGui 未安装或不可用",
        error_init_failed = "初始化失败",
        error_cannot_create_context = "错误: 无法创建 ImGui 上下文",
        error_cannot_load_config = "错误: 无法加载配置",
        error_save_failed = "配置保存失败",
        confirm_discard_changes = "确定要丢弃所有未保存的更改吗？",
        confirm_reset = "确定要重置为默认配置吗？这将丢失所有自定义设置。",
        error_switch_preset_failed = "切换预设失败",
        error_save_preset_failed = "保存预设失败",
        error_cannot_delete_default = "不能删除默认预设",
        confirm_delete_preset = "确定要删除预设",
        error_preset_name_empty = "预设名称不能为空",
        error_preset_name_exists = "预设名称已存在，请使用其他名称",
        confirm_close_unsaved = "有未保存的更改，确定要关闭吗？",
        unknown_error = "未知错误",
        enter_preset_name = "请输入预设名称:",
        name = "名称",
        name_label = "名称:",
        new_name = "新名称",
        rename_label_prefix = "重命名: ",
        clear_sector = "清除扇区",
        current_sector_name = "当前扇区名称:",
        please_select_sector = "请点击上方轮盘选择一个扇区",
        global_settings = "全局设置",
        sector_count = "扇区数量:",
        outer_radius = "外半径:",
        inner_radius = "内半径:",
        width = "宽度:",
        height = "高度:",
        interaction_animation = "交互与动画",
        enable_ui_animation = "启用界面动画 (Master)",
        open_animation_duration = "开启动画时长:",
        create_blank_preset = "创建空白预设",
        duplicate_current = "复制当前（从已保存配置）",
        name_cannot_be_empty = "名称不能为空",
        wheel_size = "轮盘尺寸",
        submenu_size = "子菜单尺寸",
        submenu_button_size = "子菜单按钮尺寸",
        submenu_layout = "子菜单布局",
        button_width = "按钮宽度:",
        button_height = "按钮高度:",
        button_gap = "按钮间距:",
        window_padding = "窗口内边距:",
        drag_hint_empty_slot = "👋 将 Action 或 FX 拖入上方插槽",
        drag_hint_sub = "(支持从下方搜索列表直接拖拽)",
        drag_hint_no_slot = "👇 请从下方搜索 Action 或 FX 并拖入上方网格",
        save_failed = "保存失败",
        rename_failed = "重命名失败",
        name_already_exists = "名称已存在（已阻止覆盖）",
        default_cannot_rename = "Default 不能重命名",
        name_cannot_be_empty_short = "名称不能为空",
        create_new_preset = "创建新预设",
        update_current_preset = "更新当前预设",
        rename_current_preset = "重命名当前预设",
        default_cannot_rename_tooltip = "Default 不能重命名",
        delete_current_preset = "删除当前预设",
        default_cannot_delete_tooltip = "Default 不能删除",
    },
    en = {
        -- Window title
        window_title = "RadialMenu Settings Editor",
        
        -- Language
        language = "Language",
        language_zh = "中文",
        language_en = "English",
        
        -- Action bar
        save = "Save",
        discard = "Discard",
        reset = "Reset",
        
        -- Presets
        preset = "Preset",
        new_preset = "New Preset",
        save_preset = "Save Preset",
        rename = "Rename",
        delete = "Delete",
        confirm = "Confirm",
        cancel = "Cancel",
        
        -- Sectors
        sector = "Sector",
        add_sector = "Add Sector",
        delete_sector = "Delete Sector",
        sector_name = "Sector Name",
        
        -- Slots
        slot = "Slot",
        empty = "Empty",
        clear = "Clear",
        clean_slot = "Clean Slot",
        delete_slot = "Delete Slot",
        
        -- Types
        type = "Type",
        action = "Action",
        fx = "FX",
        chain = "Chain",
        template = "Template",
        
        -- Preview
        preview = "Preview",
        enable_sector_expansion = "Enable Sector Expansion Animation",
        expansion_amount = "Expansion Amount",
        expansion_speed = "Expansion Speed",
        hover_to_open = "Hover to Open Submenu",
        
        -- Browser
        browser = "Browser",
        list = "List",
        run = "Run",
        actions = "Actions",
        fx_short = "FX",
        
        -- Common
        px = "px",
        
        -- Error and confirmation messages
        error = "Error",
        confirm = "Confirm",
        error_reaimgui_not_available = "Error: ReaImGui is not installed or unavailable",
        error_init_failed = "Initialization Failed",
        error_cannot_create_context = "Error: Cannot create ImGui context",
        error_cannot_load_config = "Error: Cannot load config",
        error_save_failed = "Config save failed",
        confirm_discard_changes = "Are you sure you want to discard all unsaved changes?",
        confirm_reset = "Are you sure you want to reset to default config? This will lose all custom settings.",
        error_switch_preset_failed = "Switch preset failed",
        error_save_preset_failed = "Save preset failed",
        error_cannot_delete_default = "Cannot delete default preset",
        confirm_delete_preset = "Are you sure you want to delete preset",
        error_preset_name_empty = "Preset name cannot be empty",
        error_preset_name_exists = "Preset name already exists, please use another name",
        confirm_close_unsaved = "There are unsaved changes, are you sure you want to close?",
        unknown_error = "Unknown error",
        enter_preset_name = "Please enter preset name:",
        name = "Name",
        name_label = "Name:",
        new_name = "New Name",
        rename_label_prefix = "Rename: ",
        clear_sector = "Clear Sector",
        current_sector_name = "Current Sector Name:",
        please_select_sector = "Please click a sector in the wheel above",
        global_settings = "Global Settings",
        sector_count = "Sector Count:",
        outer_radius = "Outer Radius:",
        inner_radius = "Inner Radius:",
        width = "Width:",
        height = "Height:",
        interaction_animation = "Interaction & Animation",
        enable_ui_animation = "Enable UI Animation (Master)",
        open_animation_duration = "Open Animation Duration:",
        create_blank_preset = "Create Blank Preset",
        duplicate_current = "Duplicate Current (from saved config)",
        name_cannot_be_empty = "Name cannot be empty",
        wheel_size = "Wheel Size",
        submenu_size = "Submenu Size",
        submenu_button_size = "Submenu Button Size",
        submenu_layout = "Submenu Layout",
        button_width = "Button Width:",
        button_height = "Button Height:",
        button_gap = "Button Gap:",
        window_padding = "Window Padding:",
        drag_hint_empty_slot = "👋 Drag Action or FX to slot above",
        drag_hint_sub = "(Drag from search list below)",
        drag_hint_no_slot = "👇 Search Actions or FX below and drag to grid above",
        save_failed = "Save failed",
        rename_failed = "Rename failed",
        name_already_exists = "Name already exists (overwrite prevented)",
        default_cannot_rename = "Default cannot be renamed",
        name_cannot_be_empty_short = "Name cannot be empty",
        create_new_preset = "Create new preset",
        update_current_preset = "Update current preset",
        rename_current_preset = "Rename current preset",
        default_cannot_rename_tooltip = "Default cannot be renamed",
        delete_current_preset = "Delete current preset",
        default_cannot_delete_tooltip = "Default cannot be deleted",
    }
}

-- 获取翻译文本
function M.t(key)
    local lang_table = translations[current_lang] or translations.zh
    return lang_table[key] or key
end

-- 切换语言
function M.toggle_language()
    if current_lang == 'zh' then
        current_lang = 'en'
    else
        current_lang = 'zh'
    end
    save_language()
end

-- 获取当前语言
function M.get_language()
    return current_lang
end

-- 设置语言
function M.set_language(lang)
    if lang == 'zh' or lang == 'en' then
        current_lang = lang
        save_language()
    end
end

-- 获取语言显示名称（简化版：ZH/EN）
function M.get_language_display()
    if current_lang == 'zh' then
        return "ZH"
    else
        return "EN"
    end
end

return M

