# AGENTS.md

## Prototypes

- 仓库内的 UI / 交互原型统一存放在根目录 `prototypes/` 下（索引见 `prototypes/README.md`），不要留在 agent 自身的临时或 artifact 目录中。
- 在开发新界面、调整布局或修改交互流程前，先查看 `prototypes/README.md` 并复用已有原型中的信息层级、布局结构与交互设计；具体代码实现须遵循当前 `Sources/MailroomFeatures/` 的现有架构与主题规范。
- 新增或更新原型时，直接保存在 `prototypes/` 下，并同步更新 `prototypes/README.md`。

## Release

- 版本号升级、打标与 GitHub Releases 签名公证发布流程统一封装在项目级 skill [.agents/skills/release/SKILL.md](.agents/skills/release/SKILL.md) 中，发布专用脚本位于 `.agents/skills/release/scripts/`。执行发版或调整发布工作流前先阅读该 skill。
