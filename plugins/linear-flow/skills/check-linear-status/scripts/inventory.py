#!/usr/bin/env python3
"""盤點 Linear 未完成票：算可動性、解鎖效益、排序，輸出建議與待修正清單。

與 Jira 版最大的結構差異：Linear 的 `list_issues` **完全不回傳阻塞關係**，
`fields` 也沒有對應選項。關係只能靠 `get_issue({id, includeRelations: true})`
一張票一次取得。所以這支腳本吃的是「清單 + 關係表」兩份資料合起來的 JSON，
而不是像 Jira 版那樣一份 JQL 回傳就自足。

輸入形狀（三種都吃）：

    {"issues": [...], "relations": {"PROJ-1": {"blockedBy": [...], "blocks": [...]}}}
    {"issues": [...]}          # 沒有關係資料，全部票標記為「關係未查」
    [...]                      # 裸 list，同上

`issues` 的元素就是 list_issues 回傳的物件原樣。
`relations` 的每個 value 可以是識別碼字串陣列，也可以是完整 issue 物件陣列；
是字串時腳本會回頭到 issues 清單裡找它的狀態，找不到就當作「未解決」——
寧可少建議一張可動票，也不要建議一張其實動不了的。

用法：
    python3 inventory.py <json 檔>
    python3 inventory.py <json 檔> --json
    python3 inventory.py <json 檔> --branch-tickets PROJ-16,PROJ-17
    python3 inventory.py <json 檔> --block-state Blocked --container-mode parent
    cat x.json | python3 inventory.py -
"""

import argparse
import json
import re
import sys
from datetime import datetime, timezone

# Linear 的 statusType 只有這六種，跨 team 穩定，不會因為欄位改名而變。
# 拿它當判準，永遠不要比對狀態欄的顯示名稱。
RESOLVED_TYPES = {"completed", "canceled", "duplicate"}  # 不再擋住任何人
COMPLETED_TYPE = "completed"                              # 真正做完（Epic 收尾只認這個）
IN_FLIGHT_TYPES = {"started"}                             # 正在流動 → 收尾優先
OPEN_TYPES = {"backlog", "unstarted", "started"}          # 還沒解決

# Linear 優先序：0=None、1=Urgent、2=High、3=Medium、4=Low。
# 陷阱：0 不是「最急」而是「沒設」。直接拿數字排序會把所有未設優先序的票
# 排到最前面，於是建議清單被一堆沒人分類過的票佔滿。
PRIORITY_RANK = {1: 1, 2: 2, 3: 3, 4: 4, 0: 5}
PRIORITY_NAME = {0: "無", 1: "Urgent", 2: "High", 3: "Medium", 4: "Low"}

STALE_DAYS = 14  # 在「進行中」類狀態超過這麼久沒動，視為停滯值得提醒


def load(path):
    raw = sys.stdin.read() if path == "-" else open(path, encoding="utf-8").read()
    data = json.loads(raw)
    if isinstance(data, list):
        return data, {}
    if isinstance(data, dict) and "issues" in data:
        return data["issues"], data.get("relations") or {}
    raise SystemExit("認不出這份 JSON 的形狀：預期 {issues: [...], relations: {...}} 或裸 list")


def ident(issue):
    """Linear 的 list_issues 把識別碼放在 `id`（形如 PROJ-1），不是 UUID。

    但 get_issue 的回傳與某些欄位會用 `identifier`，所以兩個都試。
    """
    if isinstance(issue, str):
        return issue
    return issue.get("identifier") or issue.get("id") or ""


def status_type(issue):
    """取 statusType。get_issue 與 list_issues 的形狀不完全一致，兩種都容忍。"""
    if not isinstance(issue, dict):
        return None
    t = issue.get("statusType")
    if t:
        return t
    st = issue.get("state") or issue.get("status")
    if isinstance(st, dict):
        return st.get("type")
    return None


def status_name(issue):
    if not isinstance(issue, dict):
        return "－"
    s = issue.get("status")
    if isinstance(s, str):
        return s
    if isinstance(s, dict):
        return s.get("name") or "－"
    st = issue.get("state")
    if isinstance(st, dict):
        return st.get("name") or "－"
    return "－"


def is_resolved(issue):
    """已解決 = 不再擋住任何人。

    包含 canceled 與 duplicate，不只 completed——一張被取消的票不會再動，
    留著它當 blocker 會讓下游永遠算不可動。這是 Linear 特有的：Jira 的
    statusCategory 沒有獨立的取消類別，取消票通常也落在 done 類。
    """
    return status_type(issue) in RESOLVED_TYPES


def priority_of(issue):
    p = issue.get("priority")
    # list_issues 回傳的是 {"value": 0, "name": "No priority"}，
    # 但寫入時吃的是純數字，所以兩種形狀都可能出現在手動組出來的檔案裡。
    if isinstance(p, dict):
        val = p.get("value")
        name = p.get("name")
    else:
        val, name = p, None
    try:
        val = int(val)
    except (TypeError, ValueError):
        val = 0
    return PRIORITY_RANK.get(val, 5), name or PRIORITY_NAME.get(val, "－")


def brief(issue, by_key):
    """把一筆關係對象壓成摘要。

    對象可能只是一個識別碼字串（模型只抄了票號沒抄狀態），這時回頭到主清單
    找它的狀態；主清單也沒有（例如它已經完成、不在未完成查詢結果裡）就標
    unknown 並視為未解決。
    """
    key = ident(issue)
    src = issue if isinstance(issue, dict) and status_type(issue) else by_key.get(key)
    if src is None:
        return {"key": key, "summary": "", "status": "？", "resolved": False, "known": False}
    return {
        "key": key,
        "summary": src.get("title") or "",
        "status": status_name(src),
        "resolved": is_resolved(src),
        "known": True,
    }


def days_since(ts):
    if not ts:
        return None
    try:
        # Linear 一律是 ISO-8601 UTC：2026-08-05T00:25:36.863Z
        dt = datetime.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
        return (datetime.now(timezone.utc) - dt).days
    except (ValueError, IndexError):
        return None


def numeric(key):
    m = re.search(r"-(\d+)$", str(key))
    return int(m.group(1)) if m else 10**9


def analyse(issues, relations, branch_tickets=(), block_state="", container_mode="project"):
    by_key = {ident(i): i for i in issues}

    # containerMode = parent 時，被別張票指為 parentId 的票是容器，不是可執行任務。
    # containerMode = project 時 Linear Project 不是 issue，主清單裡不會有容器票，
    # 這個集合自然是空的——不需要特別處理。
    container_keys = set()
    if container_mode == "parent":
        # parentId 可能是 UUID 也可能是識別碼（PROJ-1），視資料怎麼取得而定，
        # 所以兩種都建索引再比對。對不到的 parentId 代表父票不在本次查詢範圍內
        # （通常是它已經完成），那它本來就不會出現在盤點清單裡，忽略即可。
        alias = {}
        for i in issues:
            k = ident(i)
            alias[k] = k
            for extra in (i.get("uuid"), i.get("_id")):
                if extra:
                    alias[extra] = k
        for i in issues:
            parent = i.get("parent")
            pid = i.get("parentId") or (parent.get("id") if isinstance(parent, dict) else parent)
            if pid and pid in alias:
                container_keys.add(alias[pid])

    rows, containers, unknown_rel = [], [], []

    for issue in issues:
        key = ident(issue)
        # 封存票不該進盤點。正常呼叫會送 includeArchived:false，這裡是第二道防線——
        # 忘了送那個參數是 Linear 最容易犯的錯，而症狀（完成數虛高）看起來像好消息。
        if issue.get("archivedAt"):
            continue
        if key in container_keys:
            containers.append({"key": key, "summary": issue.get("title") or "",
                               "status": status_name(issue)})
            continue
        if is_resolved(issue):
            continue

        rel = relations.get(key)
        known = rel is not None
        if not known:
            unknown_rel.append(key)
        rel = rel or {}

        blocked_by = [brief(b, by_key) for b in (rel.get("blockedBy") or [])]
        blocks = [brief(b, by_key) for b in (rel.get("blocks") or [])]
        open_blockers = [b for b in blocked_by if not b["resolved"]]
        # 解鎖效益只算「還沒解決」的下游。擋住一張早就完成的票等於沒擋住任何人——
        # 真實看板上這種殘留關係很常見，全算進去會把效益虛報得離譜。
        open_downstream = [b for b in blocks if not b["resolved"]]

        rank, pname = priority_of(issue)
        stype = status_type(issue) or "unknown"
        rows.append({
            "key": key,
            "summary": issue.get("title") or "",
            "status": status_name(issue),
            "status_type": stype,
            "priority": pname,
            "priority_rank": rank,
            "project": (issue.get("project") if isinstance(issue.get("project"), str)
                        else (issue.get("project") or {}).get("name")),
            "labels": issue.get("labels") or [],
            "assignee": (issue.get("assignee") if isinstance(issue.get("assignee"), str)
                         else (issue.get("assignee") or {}).get("name")),
            "idle_days": days_since(issue.get("updatedAt")),
            "url": issue.get("url"),
            "relations_known": known,
            "blocked_by_open": open_blockers,
            "blocked_by_all": blocked_by,
            "unlocks": open_downstream,
            # 關係沒查過的票不算可動。少建議一張，好過建議一張其實動不了的。
            "actionable": known and not open_blockers,
            "on_branch": key.upper() in {t.upper() for t in branch_tickets},
        })

    actionable = [r for r in rows if r["actionable"]]
    blocked = [r for r in rows if r["relations_known"] and not r["actionable"]]
    unchecked = [r for r in rows if not r["relations_known"]]

    def sort_key(r):
        return (
            # 1. 收尾優先：半成品的價值是 0。已在 started 類狀態的票通常只差最後一哩。
            0 if r["status_type"] in IN_FLIGHT_TYPES else 1,
            # 2. 解鎖效益：能讓最多下游動起來的先做，看板整體才會流動。
            -len(r["unlocks"]),
            # 3. 優先序（0=無 已經被映射成最低）。
            r["priority_rank"],
            # 4. 票號：穩定的收尾條件。
            numeric(r["key"]),
        )

    actionable.sort(key=sort_key)
    blocked.sort(key=lambda r: (r["priority_rank"], numeric(r["key"])))
    unchecked.sort(key=lambda r: (r["priority_rank"], numeric(r["key"])))

    return {
        "recommended": actionable[0] if actionable else None,
        "runners_up": actionable[1:4],
        "actionable": actionable,
        "blocked": blocked,
        "unchecked": unchecked,
        "containers": containers,
        "unknown_relations": unknown_rel,
        "anomalies": anomalies(rows, branch_tickets, block_state),
    }


def anomalies(rows, branch_tickets, block_state):
    """找狀態不一致。只回報，不修——盤點順手改看板是幫倒忙。"""
    out = []
    in_flight = [r for r in rows if r["status_type"] in IN_FLIGHT_TYPES]
    bs = (block_state or "").strip().lower()

    for r in rows:
        # 可解未解：blocker 全解決了，票卻還躺在 Blocked 欄。
        # 這是看板最常見的假訊號，會讓人以為沒事可做。
        if (r["actionable"] and r["blocked_by_all"]
                and bs and r["status"].strip().lower() == bs):
            out.append({
                "kind": "可解未解",
                "key": r["key"],
                "detail": f"blocker 全部解決（{', '.join(b['key'] for b in r['blocked_by_all'])}），"
                          f"票仍停在「{r['status']}」",
                "suggest": "推 todo",
            })
        if r["on_branch"] and r["status_type"] in {"backlog", "unstarted"}:
            out.append({
                "kind": "分支已動工但票未推進",
                "key": r["key"],
                "detail": f"分支名對到這張票，票仍在「{r['status']}」",
                "suggest": "推 inProgress",
            })
        if (r["status_type"] in IN_FLIGHT_TYPES and r["idle_days"] is not None
                and r["idle_days"] >= STALE_DAYS):
            out.append({
                "kind": "停滯",
                "key": r["key"],
                "detail": f"在「{r['status']}」已 {r['idle_days']} 天沒更新",
                "suggest": "確認是否早該收尾或其實卡住了",
            })

    if len(in_flight) > 1 and branch_tickets:
        off = [r["key"] for r in in_flight if not r["on_branch"]]
        if off:
            out.append({
                "kind": "多張票同時在進行中",
                "key": ", ".join(r["key"] for r in in_flight),
                "detail": f"分支只對到 {', '.join(branch_tickets) or '（無）'}；"
                          f"{', '.join(off)} 可能被遺忘在進行中",
                "suggest": "確認這些票的真實進度",
            })
    return out


def render(res, scope_note=None):
    L = []
    if scope_note:
        L.append(f"⚠️  {scope_note}\n")

    if res["unknown_relations"]:
        n = len(res["unknown_relations"])
        L.append(f"⚠️  有 {n} 張票沒有關係資料（未跑 get_issue includeRelations），"
                 f"它們不列入可動判定：{', '.join(res['unknown_relations'][:8])}"
                 f"{' …' if n > 8 else ''}\n")

    rec = res["recommended"]
    if rec:
        L.append("### 建議下一張")
        L.append(f"**{rec['key']}** {rec['summary']}")
        L.append(f"- 可動 ✅ {'無 blocker' if not rec['blocked_by_all'] else 'blocker 全清'}")
        L.append(f"- 優先序 {rec['priority']}")
        unlocks = rec["unlocks"]
        L.append(f"- 解鎖效益 {'解開 ' + ', '.join(b['key'] for b in unlocks) if unlocks else '無下游等待'}")
        if rec["status_type"] in IN_FLIGHT_TYPES:
            note = f"- 已在「{rec['status']}」，屬收尾工作"
            # 推薦收尾一張停滯很久的票時，要當場說出停滯——否則使用者會直接動手，
            # 卻沒發現它可能早就完成了、或卡在某個沒記錄下來的問題上。
            if rec["idle_days"] is not None and rec["idle_days"] >= STALE_DAYS:
                note += f"，但已 {rec['idle_days']} 天沒更新，先確認它的真實進度"
            L.append(note)
        if rec["project"]:
            L.append(f"- 所屬 Project：{rec['project']}")
        if res["runners_up"]:
            L.append("\n次選：" + " ／ ".join(
                f"{r['key']} {r['summary'][:28]}" for r in res["runners_up"]))
    elif res["blocked"]:
        L.append("### 建議下一張\n沒有可動的票——所有未完成票都還被擋住，見下方卡住清單。")
    else:
        L.append("### 建議下一張\n這個範圍內沒有未完成的可執行票。")

    if res["actionable"]:
        L.append("\n### 可動（blocker 全清）")
        for r in res["actionable"]:
            mark = " ←分支對到這張" if r["on_branch"] else ""
            un = f"  解鎖 {len(r['unlocks'])}" if r["unlocks"] else ""
            L.append(f"- [{r['status']}] {r['key']} {r['summary']}{un}{mark}")

    if res["blocked"]:
        L.append("\n### 卡住")
        for r in res["blocked"]:
            who = ", ".join(f"{b['key']}({b['status']})" for b in r["blocked_by_open"])
            L.append(f"- [{r['status']}] {r['key']} {r['summary']}  ⛔ 等 {who}")

    if res["unchecked"]:
        L.append("\n### 關係未查（不列入可動判定）")
        for r in res["unchecked"]:
            L.append(f"- [{r['status']}] {r['key']} {r['summary']}")

    if res["anomalies"]:
        L.append("\n### 待修正（本 skill 不動票，請自行決定）")
        for a in res["anomalies"]:
            L.append(f"- ⚠️ {a['key']}：{a['detail']} → 建議{a['suggest']}")

    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path", help="JSON 檔路徑，或 - 讀 stdin")
    ap.add_argument("--branch-tickets", default="",
                    help="從分支名抽到的票號，逗號分隔（大小寫不拘）")
    ap.add_argument("--block-state", default="",
                    help="設定檔 states.block.name，用來偵測「可解未解」")
    ap.add_argument("--container-mode", default="project", choices=["project", "parent"],
                    help="設定檔 containerMode。parent 時把被指為 parentId 的票視為容器")
    ap.add_argument("--scope-note", default="")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    issues, relations = load(a.path)
    tickets = tuple(x.strip() for x in a.branch_tickets.split(",") if x.strip())
    res = analyse(issues, relations, tickets, a.block_state, a.container_mode)
    print(json.dumps(res, ensure_ascii=False, indent=2) if a.json
          else render(res, a.scope_note or None))


if __name__ == "__main__":
    main()
