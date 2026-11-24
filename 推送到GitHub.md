# Windows 上把 QuickRemind 推到 GitHub 并构建 IPA

> **当前状态（已全部完成到推送这一步）**
> - 仓库已创建：https://github.com/bruce-rm/QuickRemind
> - 代码已推送到 `main` 分支，本地与远程提交一致（`b310629`）
> - 工作流文件 `.github/workflows/build-ipa.yml` 已确认在仓库中（5372 bytes）
> - 接下来的动作：在网页上 **Run workflow** 构建并下载 IPA（见第 3 步）

本地仓库已经初始化完成（`.git/` 已建好，分支 `main`，首次提交已做）。
下面的步骤记录了完整流程，供以后重建仓库或排查问题时参考。

---

## 第 1 步：在 GitHub 上新建空仓库

1. 打开 https://github.com/new
2. Repository name 填 `QuickRemind`（或任意名字）
3. **不要**勾选 "Add a README file" / ".gitignore" / "license"，保持完全空仓库
4. 点 Create repository
5. 复制页面给出的仓库地址，形如：
   - HTTPS：`https://github.com/你的用户名/QuickRemind.git`
   - SSH：`git@github.com:你的用户名/QuickRemind.git`

---

## 第 2 步：关联远程仓库并推送

打开 Git Bash，**进入项目目录**后执行（把地址换成你自己的）：

```bash
cd "E:/文档/WeChat Files/ruanshiming001/FileStorage/File/2026-11/WorkBuddy-Mac迁移包/2026-11-23-12-04-10/QuickRemind"

# 关联远程仓库
git remote add origin https://github.com/你的用户名/QuickRemind.git

# 确认分支名为 main
git branch -M main

# 推送（-u 把本地 main 关联到远程 main，以后直接 git push 即可）
git push -u origin main
```

### 如果推送时要求登录
HTTPS 方式现在不再接受账号密码，需要用 **Personal Access Token（PAT）** 作为密码：
1. GitHub 右上角头像 → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token → 勾选 `repo` 权限 → 生成并复制
3. 推送时 Username 填 GitHub 用户名，Password 粘贴 token（粘贴时不显示，正常）

如果嫌每次输 token 麻烦，可在 Windows 凭据管理器里保存：
控制面板 → 凭据管理器 → Windows 凭据 → 添加普通凭据：
- 网络地址：`git:https://github.com`
- 用户名：GitHub 用户名
- 密码：token

---

## 第 3 步：在 GitHub 网页上构建 IPA

1. 打开你的仓库页面，点顶部 **Actions** 标签
2. 左侧工作流列表里选 **构建速记 IPA**
   - 如果列表是空的：确认 `.github/workflows/build-ipa.yml` 已经推上去（在仓库页面能看到 `.github` 目录）
3. 右侧点 **Run workflow** → 下拉框选 `unsigned` → 绿色按钮 **Run workflow**
4. 等待约 2-5 分钟，运行结束后点进这次运行
5. 页面底部 **Artifacts** 区，下载 `QuickRemind-IPA.zip`
6. 解压得到 `QuickRemind-unsigned.ipa`

> unsigned 模式零配置，不需要任何证书或付费账号。产出的 IPA 需要用 Sideloadly 重签才能装到 iPhone。

---

## 第 4 步：把 IPA 装到 iPhone（Windows）

1. 下载安装 [Sideloadly](https://sideloadly.io/)（Windows 版）
2. 用数据线连接 iPhone，手机上点"信任此电脑"
3. Sideloadly 里拖入 `QuickRemind-unsigned.ipa`
4. 填 Apple ID（免费即可）和密码
5. 点 Start，等待安装完成
6. 免费账号签名有效期 7 天，到期重新签一次即可

---

## 常见问题

**Q：推送时报 `remote origin already exists`**
说明已经关联过了，直接推送：`git push -u origin main`
若要改地址：`git remote set-url origin 新地址`

**Q：Actions 页面看不到"构建速记 IPA"**
工作流文件只在默认分支生效。确认已推送到 `main`，刷新页面。

**Q：构建失败，日志说找不到 Xcode**
工作流指定了 `macos-15` runner，一般自带 Xcode。偶尔镜像异常，重新 Run workflow 一次即可。

**Q：想生成带签名的 IPA（TestFlight / 长期安装）**
在仓库 Settings → Secrets and variables → Actions → New repository secret 添加 5 个 Secret：
`CERT_P12_BASE64`、`CERT_PASSWORD`、`PROVISIONING_PROFILE_BASE64`、`DEVELOPMENT_TEAM`、`PROVISIONING_PROFILE_NAME`。
然后 Run workflow 时选 `development`。详见 README.md 的"生成带签名的 IPA"章节。

**Q：以后改了代码怎么更新**
```bash
git add .
git commit -m "说明这次改了什么"
git push
```
然后重新 Run workflow 构建新 IPA。

---

## 本地已完成的准备

- [x] `git init -b main` 初始化仓库
- [x] `.gitignore` 排除构建产物（`build/`、`staging/`、`*.ipa`、Python 缓存等）
- [x] `.gitattributes` 锁定 LF 换行符，避免脚本在 macOS 上执行失败
- [x] 首次提交完成
- [x] 创建 GitHub 仓库 `bruce-rm/QuickRemind`
- [x] 推送 `main` 分支，工作流文件已上传
- [x] 远程地址已清理，git 配置中无 token 残留
- [ ] 网页上 Run workflow 构建 IPA（需要你操作，见第 3 步）

## 以后本地更新代码怎么推送

远程地址是干净的 HTTPS，推送时需要认证。两种方式：

**方式 A：让 Windows 记住 token（推荐）**

```bash
git config --global credential.helper manager
```

第一次 push 时 Username 填 `bruce-rm`，Password 填 token，之后 Windows 凭据管理器会记住，不用再输。

**方式 B：每次用临时 URL（不保存凭据）**

```bash
git push https://bruce-rm:你的TOKEN@github.com/bruce-rm/QuickRemind.git main
```
