# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

布局：**single-context**（单上下文）——本仓库是一组独立 shell 脚本，没有 `packages/*`、没有 workspace 文件。

## Before exploring, read these

- **`GLOSSARY.md`** at the repo root, or
- **`GLOSSARY-MAP.md`** at the repo root if it exists: it points at one `GLOSSARY.md` per context. Read each one relevant to the topic.
- **`docs/adr/`**: read ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

```
/
├── AGENTS.md              ← 常驻约定（指针为主；细节在 docs/）
├── GLOSSARY.md            ← 领域词表（按下文规则惰性创建）
├── docs/
│   ├── adr/               ← 架构决策记录
│   ├── agents/            ← 本套技能的配置（issue tracker / triage labels / domain）
│   └── *.md               ← 带日期的方案与实测文档（归档阅读材料，不是 issue）
├── .scratch/              ← 本地 issue 追踪器（见 issue-tracker.md）
├── Manage/                ← 受测脚本
└── tests/                 ← 脚本级回归（tests/<脚本名>/run.sh）
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `GLOSSARY.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
