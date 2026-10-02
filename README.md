# 网站日常工作流程

你可以在这个项目的 Codex 聊天里直接说：

- “预览我刚修改的文章。”
- “重新生成亲密关系这本书，同步到网站并预览。”
- “把刚才确认的修改发布到网站，检查上线结果。”

本地需要 PowerShell 7、Hugo、Git；书籍另外需要 Quarto。GitHub CLI 用于查看远端和部署检查。Hugo 主题通过 Git 子模块管理，新环境需初始化子模块。

## 脚本

在项目根目录运行（通常由 Codex 代为执行）：

```powershell
pwsh -File scripts/site.ps1 -Action Check
pwsh -File scripts/site.ps1 -Action Preview
```

Check 使用正式构建规则，不包含草稿；Preview 包含草稿，默认地址为 http://localhost:1313/，Ctrl+C 停止服务。

书籍同步：

```powershell
pwsh -File scripts/sync-book.ps1 -Source '<书籍项目绝对路径>' -BookId intimate-relationships
```

已在本机 `books.local.json` 登记亲密关系源稿，日常可简写为 `pwsh -File scripts/sync-book.ps1 -BookId intimate-relationships`。这份本机路径配置被 Git 忽略；增加其他书籍时可登记新的标识、标题和 source。

脚本复制源项目到 `.site-work` 后生成整本 HTML，再更新 `static/books/<BookId>`。旧的网站书籍文件保存在 `.site-work` 下的独立备份目录。默认排除 docs、_book、_site 和 Quarto 辅助目录；如果另一本书将这些名称用于源素材，先调整排除规则。新增书籍还需在 `content/cn/study/_index.md` 增加入口。

发布示例（路径替换成已经检查过的实际改动，可在 PowerShell 中传入多个路径）：

```powershell
./scripts/site.ps1 -Action Publish -Paths @('content/cn/posts/某篇文章.md') -Message 'Update post'
```

Publish 核对 main 与远端、检查改动范围、构建网站，然后提交并推送。已有暂存内容、范围外改动或远端差异会明确报错；不做强制推送或自动合并。若推送失败，本地提交会保留，需要核对后重试推送。

Git 推送与 Cloudflare 上线是两个不同阶段。应检查对应提交的 Cloudflare 状态及正式页面，才能确认发布完成。分支预览需先核对 Cloudflare 项目的预览分支设置。

## 云端使用

本地模式能够直接使用电脑上的 Quarto 源项目。Codex 云端需要可访问的 Git 仓库，以及 Hugo、Quarto 和相应书籍运行依赖；单独保存于电脑上的源稿不会自动随 mysite 出现在云端。当前推荐先使用本地流程，未来有离线运行或跨设备需求时，再将书籍源项目纳入独立仓库并配置云端环境。

网站仓库里的 `static/books` 保存发布结果，不替代书籍源项目的备份。
