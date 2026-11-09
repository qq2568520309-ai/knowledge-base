# 三步上手

## 1. 装环境

需要 Python 3.9+（推荐 3.12）。

=== "Windows (PowerShell)"

    ```powershell
    cd knowledge-base
    python -m venv .venv
    .\.venv\Scripts\Activate.ps1
    pip install -r requirements.txt
    ```

=== "macOS / Linux"

    ```bash
    cd knowledge-base
    python3 -m venv .venv
    source .venv/bin/activate
    pip install -r requirements.txt
    ```

!!! warning "PowerShell 报「禁止运行脚本」"
    执行一次即可放开当前用户策略：

    ```powershell
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
    ```

## 2. 本地预览

```bash
mkdocs serve
```

打开 <http://127.0.0.1:8000>。保存任何 `.md` 文件，浏览器会自动刷新，改完立刻能看到效果。

想要手机同款窄屏效果，加 `-a 0.0.0.0:8000` 用局域网地址访问。

## 3. 写第一篇笔记

新建 `docs/notes/first.md`：

```markdown
# 第一篇笔记

这里是正文。支持 **加粗**、`行内代码`、[链接](https://example.com)。
```

然后在 `mkdocs.yml` 的 `nav:` 里登记：

```yaml
nav:
  - 首页: index.md
  - 笔记:
      - 第一篇: notes/first.md
```

!!! tip "不想手动维护 nav？"
    删掉整个 `nav:` 配置，MkDocs 会按文件名自动生成导航（文件名排序）。
    文件多起来之后，也可以在对应目录放 `.pages` 文件单独控制顺序。

## 构建静态站点

```bash
mkdocs build
```

产物在 `site/` 目录，是纯 HTML/CSS/JS，可以放到任何静态托管上。
