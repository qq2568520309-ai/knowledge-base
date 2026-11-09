# 发布到 GitHub Pages

目标：`git push` 之后，网站自动更新到 `https://<用户名>.github.io/<仓库名>/`。

## 1. 在本地初始化仓库

```bash
cd knowledge-base
git init
git add .
git commit -m "init: knowledge base"
```

## 2. 在 GitHub 建一个空仓库

网页上 **New repository**：

- 名字：`knowledge-base`（想用 `用户名.github.io` 作为地址就起这个名）
- 可见性：**Public**（免费账号的 Pages 只对公开仓库开放；私有仓库需要 GitHub Pro/Team）
- **不要**勾选 README / .gitignore / license，保持空仓库

然后推送：

```bash
git remote add origin https://github.com/<用户名>/knowledge-base.git
git branch -M main
git push -u origin main
```

!!! tip "还没配过 Git 身份？"
    ```bash
    git config --global user.name  "你的名字"
    git config --global user.email "你的邮箱"
    ```
    HTTPS 推送需要 Personal Access Token（Settings → Developer settings → Tokens），
    或者直接装 [GitHub CLI](https://cli.github.com/) 后 `gh auth login`。

## 3. 打开 Pages 的构建来源

仓库 **Settings → Pages → Build and deployment → Source**，选择 **GitHub Actions**。

这是关键一步：本仓库的 workflow 用的是官方的 `actions/deploy-pages`，
选它才能让 Actions 发布的结果真正生效。选错成 "Deploy from a branch" 会出现「构建成功但网站 404 / 还是旧内容」。

## 4. 触发第一次构建

推送任意提交即可，或者到 **Actions** 页手动 **Run workflow**。

流水线分两个 job：

1. `build`：装依赖 → `mkdocs build --strict` → 上传 `site/` 产物
2. `deploy`：把产物发布到 Pages

第一次跑大约 1–2 分钟。成功后：

- Actions 里 `deploy` 这一步会显示站点 URL
- **Settings → Pages** 顶部出现 `Your site is live at ...`

## 5. 关于网址的两种形态

| 仓库名 | 访问地址 | 说明 |
| --- | --- | --- |
| `knowledge-base` | `https://<用户名>.github.io/knowledge-base/` | 项目站，一个账号可以有无数个 |
| `<用户名>.github.io` | `https://<用户名>.github.io/` | 用户站，一个账号只有一个 |

如果仓库名是 `用户名.github.io`，记得把 `mkdocs.yml` 的 `site_url` 改成根地址：

```yaml
site_url: https://<用户名>.github.io/
```

## 6. 绑定自定义域名（可选）

1. 域名 DNS 加一条 CNAME 记录指向 `<用户名>.github.io`
2. 仓库 **Settings → Pages → Custom domain** 填 `wiki.example.com`，勾选 **Enforce HTTPS**
3. MkDocs 侧加一个 `docs/CNAME` 文件，内容就是域名（否则每次部署可能把域名设置冲掉）

```bash
echo "wiki.example.com" > docs/CNAME
```

## 常见故障排查

??? question "Actions 报 `Permission denied` / `Resource not accessible by integration`"
    检查 `.github/workflows/deploy.yml` 顶部的 `permissions:` 是否包含
    `contents: read`、`pages: write`、`id-token: write`。三者缺一不可。

??? question "构建成功，但页面 404"
    - Settings → Pages 的 Source 是不是 **GitHub Actions**
    - 仓库是否 Public（免费账号）
    - 首次部署后有 1 分钟左右生效延迟

??? question "页面样式全丢、CSS 404"
    `site_url` 写错了。项目站必须是 `https://<用户名>.github.io/<仓库名>/`，结尾带斜杠。

??? question "`mkdocs build --strict` 失败，提示 `contains a link to ... which is not found`"
    相对链接写错了。链接目标是文件路径，指向目录时要用 `xxx.md` 或 `xxx/`，
    别写成绝对路径 `/guide/quickstart.md`。

??? question "中文搜索搜不到"
    确认 `plugins.search.lang: zh`，并且 `mkdocs build` 后 `search/search_index.json` 正常生成。
    本地 `mkdocs serve` 的搜索索引与线上是同一套逻辑，可以本地先验证。

??? question "想回滚到上一个版本"
    Pages 部署记录在 **Actions** 里，找到历史成功的那次 run，
    用 `git revert` 提交一次反向改动推送即可；Pages 本身不保留版本历史。

## 备选方案：`mkdocs gh-deploy`

不想碰 Actions，也可以本地一条命令把站点推到 `gh-pages` 分支：

```bash
mkdocs gh-deploy --force
```

然后把 Settings → Pages 的 Source 改回 **Deploy from a branch**，分支选 `gh-pages` / `root`。
缺点是每次更新都要在本地手动跑，且依赖你本机环境；团队协作或想「推代码即上线」时还是 Actions 更省心。
