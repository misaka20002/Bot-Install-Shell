#!/usr/bin/env bash
# ============================================================
# tests/static-checks.sh —— 秒级机械检查（不需要能跑被测脚本、不联网、不需要 root）
#
# 用法：
#   bash tests/static-checks.sh             # 检查全部受版本控制的 *.sh
#   bash tests/static-checks.sh a.sh b.sh   # 只检查指定文件（pre-commit 用）
#
# 做五件事：
#   1) 每个 *.sh 的 `bash -n`；
#   2) 每个 node heredoc 块的 `node --check` —— `bash -n` 看不到 heredoc 里的 JS。
#      2026-10-19 两次改坏那个 4900 行脚本，真凶都在 JS 里，而 `bash -n` 只报了一个不相干的 `}`；
#   3) 行尾混用检测：同一文件里既有 CRLF 又有 LF 时，Linux 上执行会在 \r 处炸。
#      整份翻转型改写交给 `.gitattributes` 的 `* text=auto` 兜底（git 在 add 时归一化）。
#   4) *.md 的重复同级标题：整段被写两遍的唯一可靠信号（见文件末尾注释）；
#   5) AGENTS.md 体积上限：超过 40KB 就一次读不完（见该段注释）。
#
# 退出码：0 = 全过；1 = 有问题（逐条打印 "文件: 原因"）。
# ============================================================
set -o pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "static-checks: 不在 git 仓库内" >&2
    exit 1
}
cd "${ROOT}" || exit 1

sh_files=()
md_files=()
if [ "$#" -gt 0 ]; then
    for f in "$@"; do
        case "${f}" in
            *.sh) sh_files+=("${f}") ;;
            *.md) md_files+=("${f}") ;;
        esac
    done
else
    while IFS= read -r f; do sh_files+=("${f}"); done < <(git ls-files '*.sh')
    # core.quotePath=false：中文文件名默认会被 git 加引号转义，node 会读不到
    while IFS= read -r f; do md_files+=("${f}"); done < <(git -c core.quotePath=false ls-files '*.md')
fi
if [ "${#sh_files[@]}" -eq 0 ] && [ "${#md_files[@]}" -eq 0 ]; then
    echo "static-checks: 没有要检查的文件"
    exit 0
fi

fail=0
say() { printf '%s: %s\n' "$1" "$2"; }

# ---- 1) bash -n ----
for f in "${sh_files[@]}"; do
    [ -f "${f}" ] || continue
    if ! err=$(bash -n "${f}" 2>&1); then
        say "${f}" "bash -n 失败 → ${err}"
        fail=1
    fi
done

# ---- 2) heredoc 里的 node 块 ----
node_files=()
for f in "${sh_files[@]}"; do
    [ -f "${f}" ] || continue
    if grep -q "^[^#]*node .*<<'NODE'" "${f}"; then node_files+=("${f}"); fi
done
if [ "${#node_files[@]}" -gt 0 ]; then
    if ! command -v node >/dev/null 2>&1; then
        echo "static-checks: 缺少 node，跳过 heredoc 检查（被测脚本本身也依赖 node）" >&2
        fail=1
    else
        for f in "${node_files[@]}"; do
            out=$(node - "${f}" <<'JS'
const fs = require("fs");
const file = process.argv[2];
const lines = fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n").split("\n");
const blocks = [];
let i = 0;
while (i < lines.length) {
  const line = lines[i];
  // 只看真正的 heredoc 起始（注释行里提到 <<'NODE' 不算）
  if (!line.trimStart().startsWith("#") && /<<'NODE'/.test(line)) {
    const start = i + 1;
    let j = start;
    while (j < lines.length && lines[j] !== "NODE") j += 1;
    if (j >= lines.length) {
      console.log(`第 ${start} 行的 node heredoc 没有对应的 NODE 结尾`);
      process.exit(0);
    }
    blocks.push({ line: start + 1, code: lines.slice(start, j).join("\n") });
    i = j + 1;
  } else {
    i += 1;
  }
}
const { execFileSync } = require("child_process");
const os = require("os");
const path = require("path");
let bad = 0;
blocks.forEach((b, n) => {
  const tmp = path.join(os.tmpdir(), `static-check-${process.pid}-${n}.js`);
  fs.writeFileSync(tmp, b.code);
  try {
    execFileSync(process.execPath, ["--check", tmp], { stdio: "pipe" });
  } catch (error) {
    bad += 1;
    const msg = String(error.stderr || error.message).split("\n").slice(0, 2).join(" ");
    console.log(`第 ${b.line} 行起的 node 块语法错误 → ${msg}`);
  } finally {
    try { fs.unlinkSync(tmp); } catch {}
  }
});
JS
)
            if [ -n "${out}" ]; then
                say "${f}" "heredoc 检查未通过 → ${out}"
                fail=1
            fi
        done
    fi
fi

# ---- 3) 行尾混用检测 ----
# 只看「同一个文件里既有 CRLF 又有 LF」：这种文件在 Linux 上执行会在 \r 处炸
# （`$'\r': command not found`），而且多半是 sed/awk 局部改写留下的。
# 不做「整份行尾翻转」检测：本仓库 core.autocrlf=true，git 在 add 时会归一化，
# `git diff` 根本看不到行尾差异（2026-10-19 实测），据此报警只会制造假阳性。
# 真正的护栏是 `.gitattributes` 里那条 `* text=auto`：无论谁在什么系统提交，对象库都是 LF。
eol_report=$(node - "${sh_files[@]}" <<'JS'
const fs = require("fs");
const files = process.argv.slice(2);
const problems = [];
for (const f of files) {
  let raw;
  try { raw = fs.readFileSync(f, "utf8"); } catch { continue; }
  if (!raw) continue;
  const crlf = (raw.match(/\r\n/g) || []).length;
  const lf = (raw.match(/(?<!\r)\n/g) || []).length;
  if (crlf > 0 && lf > 0) problems.push(`${f}: 文件内混用 CRLF（${crlf} 行）与 LF（${lf} 行），bash 执行到 CR 处会报错`);
}
if (problems.length) console.log(problems.join("\n"));
JS
)
if [ -n "${eol_report}" ]; then
    while IFS= read -r line; do say "${line%%:*}" "${line#*: }"; done <<< "${eol_report}"
    fail=1
fi

# ---- 4) Markdown 结构：同一文件里重复的同级标题 ----
# 2026-10-20 事故：用 node 的 String.replace 改 AGENTS.md，替换串里的 `$` + 反引号
# 被当成「插入匹配点之前的全部内容」，整份正文被写成两份；bash -n 和行尾检查都看不出，
# 只有 `git diff --stat` 显示 +803 行才发现。重复标题是这种「整段写两遍」的可靠特征。
if [ "${#md_files[@]}" -gt 0 ]; then
    md_report=$(node - "${md_files[@]}" <<'JS'
const fs = require("fs");
const files = process.argv.slice(2);
const problems = [];
for (const f of files) {
  let raw;
  try { raw = fs.readFileSync(f, "utf8"); } catch { continue; }
  const lines = raw.replace(/\r\n/g, "\n").split("\n");
  const seen = new Map();
  lines.forEach((line, i) => {
    const m = /^(#{2,6}) +(.+?)\s*$/.exec(line);
    if (!m) return;
    const key = m[1].length + " " + m[2];
    if (seen.has(key)) {
      problems.push(`${f}\t第 ${i + 1} 行与第 ${seen.get(key)} 行是重复的同级标题「${m[2]}」——多半整段被写了两遍`);
    } else {
      seen.set(key, i + 1);
    }
  });
}
if (problems.length) console.log(problems.join("\n"));
JS
)
    if [ -n "${md_report}" ]; then
        while IFS=$'\t' read -r md_file md_msg; do say "${md_file}" "${md_msg}"; done <<< "${md_report}"
        fail=1
    fi
fi

# ---- 5) AGENTS.md 体积上限 ----
# 2026-10-22：AGENTS.md 涨到 90KB / 831 行，`Read` 工具在 20000 token 处直接拒读，
# 于是「推给每个 Agent 的规则」实际上没人能一次读完——当天只能拿 2KB 预览干活，靠 grep 补。
# 解法不是删规则，是把「单个脚本的专属约定」外移到 docs/agents/（同 domain.md 的既有做法），
# AGENTS.md 只留 1-2 行指针。40KB 是「还能一次读完」的经验上限（中文约 13k token）。
AGENTS_MAX_BYTE=${AGENTS_MAX_BYTE:-40960}
if [ -f AGENTS.md ]; then
    ag_size=$(wc -c < AGENTS.md)
    if [ "${ag_size}" -gt "${AGENTS_MAX_BYTE}" ]; then
        say "AGENTS.md" "体积 ${ag_size}B 超过 ${AGENTS_MAX_BYTE}B：把某个脚本的专属约定外移到 docs/agents/，再用 1-2 行指针指回来"
        fail=1
    fi
fi

if [ "${fail}" -ne 0 ]; then
    echo
    echo "static-checks: FAIL（修好后再提交；只跑指定文件：bash tests/static-checks.sh 路径…）" >&2
    exit 1
fi
echo "static-checks: OK（${#sh_files[@]} 个 sh：bash -n / heredoc node --check / 行尾混用；${#md_files[@]} 个 md：重复标题；AGENTS.md ${ag_size:-?}B ≤ ${AGENTS_MAX_BYTE}B）"
