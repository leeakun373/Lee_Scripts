# 文档目录

本目录包含 Lee Scripts 脚本库的相关文档和参考资料。

## 📚 核心文档（必读）

### 项目管理和维护

1. **[版本控制指南](VERSION_CONTROL_GUIDE.md)** ⭐ **新**
   - Git 基本操作和日常工作流
   - 如何推送和进行版本管理
   - Cursor AI 版本控制指南
   - 常见问题解答

2. **[项目维护指南](MAINTENANCE.md)** ⭐ **新**
   - 文档维护规范
   - 代码维护流程
   - 版本管理策略
   - 定期任务清单

## 📖 技术文档

### UI框架相关

3. **[UI框架资源](UI_FRAMEWORKS_RESOURCES.md)**
   - REAPER UI框架资源网站和文档
   - 可用的UI框架介绍（ReaImGui, rtk, Lokasenna GUI等）
   - 学习资源和示例位置
   - 许可证说明

4. **[rtk vs ReaImGui 对比分析](RTK_VS_REAIMGUI_COMPARISON.md)**
   - 两个框架的复杂度对比
   - 代码示例和迁移评估
   - 使用场景建议
   - 决策树和最佳实践

### 脚本分析

5. **[脚本功能分析](SCRIPT_ANALYSIS.md)**
   - 根目录脚本功能总结
   - 脚本分类建议
   - 功能模块分析

6. **[nvk Take Marker 学习文档](nvkLearn.md)**
   - nvk Take Marker 实现详解
   - 核心 API 使用
   - 算法和代码示例
   - 工作流程说明

### 技术研究

7. **[Lokasenna Radial Menu 分析](LOKASENNA_RADIAL_MENU_ANALYSIS.md)**
   - Setup脚本和主脚本的架构分析
   - 菜单系统的工作原理
   - 核心功能模块详解
   - 技术实现细节和使用场景

8. **[Mantrika Tools Radial Menu 系统分析](MANTRIKA_RADIAL_MENU_ANALYSIS.md)**
   - Mantrika Tools 技术架构分析（C++ + Slint）
   - Radial Menu 功能详解
   - 配置系统和数据持久化
   - 实现方案对比和建议

9. **[Radial Menu 实现方案汇总](RADIAL_MENU_IMPLEMENTATION_OPTIONS.md)**
   - 已知实现案例
   - 不同框架的实现对比
   - 实现建议和方案选择

10. **[Slint UI框架与REAPER兼容性分析](SLINT_FOR_REAPER_ANALYSIS.md)**
   - Slint框架特点分析
   - REAPER脚本兼容性评估
   - 适合REAPER的UI框架推荐
   - 针对Radial Menu功能的实现建议

11. **[REAPER C++扩展开发方案](REAPER_CPP_EXTENSION_DEVELOPMENT.md)**
   - C++扩展开发概述
   - 使用Slint等现代UI框架的方法
   - 开发步骤和部署流程
   - 参考项目和注意事项

12. **[部署复杂度对比](DEPLOYMENT_COMPARISON.md)**
   - Lua 脚本 vs C++ 扩展部署对比
   - 开发效率和维护成本分析
   - 实际案例对比
   - 技术选型建议

### 项目记录

13. **[对话摘要](CONVERSATION_SUMMARY.md)**
   - 项目讨论的关键发现
   - 技术选型分析
   - 推荐方案和决策点
   - 下一步行动

## 📖 快速导航

### 新手入门
- **第一次使用这个项目？** → 先看 [版本控制指南](VERSION_CONTROL_GUIDE.md)
- **如何维护项目？** → 查看 [项目维护指南](MAINTENANCE.md)
- **如何推送代码？** → 查看 [版本控制指南 - 日常工作流](VERSION_CONTROL_GUIDE.md#日常工作流)

### 技术学习
- **想了解有哪些UI框架可用？** → 查看 [UI框架资源](UI_FRAMEWORKS_RESOURCES.md)
- **想了解rtk是否适合我？** → 查看 [rtk vs ReaImGui 对比分析](RTK_VS_REAIMGUI_COMPARISON.md)
- **想学习UI开发？** → 两个文档都包含学习资源链接
- **想了解Take Marker实现？** → 查看 [nvk Take Marker 学习文档](nvkLearn.md)

### 功能研究
- **想了解Radial Menu的工作原理？** → 查看 [Lokasenna Radial Menu 分析](LOKASENNA_RADIAL_MENU_ANALYSIS.md)
- **想了解Mantrika Tools的Radial Menu实现？** → 查看 [Mantrika Tools Radial Menu 系统分析](MANTRIKA_RADIAL_MENU_ANALYSIS.md)
- **想了解Radial Menu实现方案？** → 查看 [Radial Menu 实现方案汇总](RADIAL_MENU_IMPLEMENTATION_OPTIONS.md)

### 技术选型
- **想了解Slint是否适合REAPER？** → 查看 [Slint UI框架与REAPER兼容性分析](SLINT_FOR_REAPER_ANALYSIS.md)
- **想用C++开发REAPER扩展？** → 查看 [REAPER C++扩展开发方案](REAPER_CPP_EXTENSION_DEVELOPMENT.md)
- **想了解部署复杂度差异？** → 查看 [部署复杂度对比](DEPLOYMENT_COMPARISON.md)
- **想回顾项目讨论内容？** → 查看 [对话摘要](CONVERSATION_SUMMARY.md)

## 📁 文档分类

### 核心文档
- 版本控制指南
- 项目维护指南

### 技术文档
- UI框架相关（2个文档）
- 脚本分析（2个文档）
- 技术研究（6个文档）
- 项目记录（1个文档）

### 配置文件
- `Scripts.code-workspace` - VS Code 工作区配置

## 🔄 更新日志

- 2024-11-18: 添加版本控制指南和维护文档
- 2024-11-18: 重新组织文档结构，优化导航
- 2024-11-18: 添加对话摘要文档
- 2024-11-18: 添加部署复杂度对比文档
- 2024-11-18: 添加Mantrika Tools Radial Menu系统分析文档
- 2024-11-18: 添加REAPER C++扩展开发方案文档
- 2024-11-18: 添加Slint框架兼容性分析文档
- 2024-11-18: 添加Lokasenna Radial Menu脚本分析文档
- 2024-11-18: 创建文档目录，整合UI框架相关文档

## 🔗 相关链接

- [项目主 README](../README.md)
- [GitHub 仓库](https://github.com/leeakun373/Lee_Reaper_Scripts)

