# `.scratch/` —— 本仓库的本地 issue 追踪器

**进版本库是故意的**：spec 与 ticket 的历史要能跟着代码一起回溯，不依赖任何外部服务。

## 结构

```
.scratch/<feature-slug>/
├── spec.md                     # 方案（/to-spec 产出）
└── issues/
    ├── 01-<slug>.md            # 一个 ticket 一个文件，编号从 01 起
    └── 02-<slug>.md
```

- 每个 ticket 顶部有 `Status:` 行（`needs-triage` / `needs-info` / `ready-for-agent` /
  `ready-for-human` / `wontfix`），`/wayfinder` 另用 `Type:` 与 `Blocked by:`。
- 讨论追加在文件末尾的 `## Comments` 下。

约定全文见 `docs/agents/issue-tracker.md`，角色与标签的映射见 `docs/agents/triage-labels.md`。

## 与 `docs/` 的分工

- `.scratch/` = **进行中的工作**（会被 triage、会被关闭）。
- `docs/*.md` = **归档的结论**（带日期的方案/实测记录，只增不改）。
