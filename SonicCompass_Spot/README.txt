SonicCompass Spot (Phase 1 v3 — 单脚本 + 双向前置)
====================================================

【一句话】
把目录复制到 %APPDATA%\REAPER\Scripts\Lee_Scripts\SonicCompass_Spot\，
然后只把 "Lee_SonicCompass Spot - Focus Search.lua" 加到 REAPER 的 Action List，
绑定一个快捷键即可使用。

【无感知反复触发】
脚本顶部 reaper.set_action_options(1)：
  - 重复按快捷键不会弹"ReaScript task control"对话框
  - 旧实例自动终止，新实例直接弹输入框 + 重启 Listener
  - 一次按 = 一次 SC 唤起，体感无任何中间步骤

【双向前置（绕过 Windows 前台保护）】
  REAPER → SC：Lua 调 SC HTTP 后，SC 端用 Win32 trick（minimize-restore +
              AttachThreadInput）强制把主窗口拉到前台。
  SC → REAPER：点 →R 按钮时 SC 调 AllowSetForegroundWindow(ASFW_ANY) 授权；
              listener 完成插入后调 SWS BR_Win32_SetForegroundWindow 即可。

【依赖】
1) SWS 扩展（必装）— https://www.sws-extension.org
   缺失时脚本会弹中文错误。
2) SonicCompass_Mosaic 脚本包（提供共享 http_client.lua）
   预期路径：%APPDATA%\REAPER\Scripts\Lee_Scripts\SonicCompass_Mosaic\http_client.lua
3) ReaImGui（推荐）— ReaPack 安装"ReaImGui: ReaScript binding for Dear ImGui"
   有它：弹 SC 主题风格的小型悬浮输入窗
   没它：自动回退到 REAPER 原生 GetUserInputs 对话框

【典型工作流】
1. REAPER 内按快捷键 → 弹"SonicCompass — Spot 搜索"输入框
2. 输入关键词回车 → SonicCompass 主窗口被唤起，搜索框已预填
3. 在 SC 内试听、波形精修（框选）、或开 Shift+R 启用 region
4. 点击 SC 底部 "→R" 按钮 → 把内容写回 REAPER

【发回优先级】
SC 底部 "→R" 按钮根据当前状态决定发什么：
  1. 当前波形条上有"框选"      → 只发框选片段
  2. 当前波形条 Shift+R 启用 region → 每个 region 切一段，首尾相接
  3. 默认                        → 整条原文件
多选时其他条目按"整条"发送。

【临时切片落盘位置】
SC 通过 focus-search 时收到 REAPER 当前项目目录，把临时切片 WAV 写到：
    <REAPER 项目目录>\SonicCompass_Spot\
项目未保存或路径无效时，回退到 SC 设置 → Transfer 路径，最终回退系统 temp。

【收件箱目录】
Lua Listener 监听 SC 写来的命令文件：
    %APPDATA%\REAPER\Scripts\Lee_Scripts\SonicCompass_Spot\tmp\
    spot_cmd_<id>.json + spot_done_<id>.flag
执行成功写 spot_ack_<id>.json；失败写 spot_err_<id>.txt 便于排查。

【性能保证】
- Listener 250ms 节流轮询（约 4 次/秒），不影响 REAPER UI 帧率
- 每 tick 最多处理 2 条命令，余量留给 REAPER 主循环
- 单条命令解析失败会重试最多 12 个 tick (~3s)，避免 IO 锁瞬态丢任务

【文件清单】
  Lee_SonicCompass Spot - Focus Search.lua  ← 唯一对外脚本
  spot_listener.lua                          内部模块（被 Focus Search 自动 require）
  spot_dialog.lua                            内部模块（ReaImGui 输入框 + 兜底）
  spot_config.lua                            内部模块（共享常量）
  README.txt                                 本文件
