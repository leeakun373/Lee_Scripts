# GitHub 上传指南

## 步骤 1: 初始化 Git 仓库

在项目根目录（`RadialMenu_Tool`）打开终端，执行：

```bash
git init
```

## 步骤 2: 添加文件

```bash
git add .
```

注意：`config.json` 会被 `.gitignore` 忽略，不会上传到 GitHub（因为这是用户自定义配置）

## 步骤 3: 提交

```bash
git commit -m "Initial commit: RadialMenu Tool v1.0.0"
```

## 步骤 4: 在 GitHub 创建仓库

1. 登录 GitHub
2. 点击右上角的 "+" 按钮，选择 "New repository"
3. 仓库名称：`RadialMenu_Tool` 或 `reaper-radial-menu`
4. 描述：`A modern radial menu tool for REAPER`
5. 选择 Public 或 Private
6. **不要**勾选 "Initialize this repository with a README"（因为我们已经有了）
7. 点击 "Create repository"

## 步骤 5: 连接远程仓库并推送

GitHub 会显示命令，类似这样：

```bash
git remote add origin https://github.com/你的用户名/RadialMenu_Tool.git
git branch -M main
git push -u origin main
```

## 步骤 6: 验证

访问你的 GitHub 仓库页面，确认所有文件都已上传。

---

## 后续更新

每次修改后，使用以下命令更新 GitHub：

```bash
git add .
git commit -m "描述你的更改"
git push
```

---

## 注意事项

- `config.json` 不会上传（已在 `.gitignore` 中）
- 如果需要在 GitHub 上提供示例配置，可以创建一个 `config.example.json` 文件
- 确保所有敏感信息（如 API 密钥）不会提交到仓库

