#!/usr/bin/env python3
"""盤點 Jira 未完成票：算可動性、解鎖效益、排序，輸出建議與待修正清單。

吃一份 searchJiraIssuesUsingJql 的 JSON 回傳（MCP 超限落地的檔案、或自己存的檔），
輸出結構化盤點結果。之所以用腳本而不是讓模型心算：可動性與解鎖效益要跨票
交叉比對 issuelinks 的方向與狀態，那是機械計算，寫死比每次重推可靠，而且
大專案的原始 JSON 動輒二三十萬字元，不該整份進 context。

用法：
    python3 inventory.py <json 檔>                     # 文字盤點表
    python3 inventory.py <json 檔> --json              # 機器可讀
    python3 inventory.py <json 檔> --branch-tickets ACME-16,ACME-17
    cat x.json | python3 inventory.py -
"""

import argparse
import json
import sys
from datetime import datetime, timezone

# Jira 預設優先序。數字小 = 急。專案自訂了別的名稱時 fallback 用 priority.id。
PRIORITY_RANK = {
    "highest": 1, "high": 2, "medium": 3, "low": 4, "lowest": 5,
    "最高": 1, "高": 2, "中": 3, "低": 4, "最低": 5,
}

STALE_DAYS = 14  # 進行中／審核中超過這麼久沒動，視為停滯值得提醒


def load(path):
    raw = sys.stdin.read() if path == "-" else open(path, encoding="utf-8").read()
    data = json.loads(raw)
    # 支援三種形狀：MCP 回傳、REST 回傳、裸 list
    if isinstance(data, list):
        return data
    if "issues" in data and isinstance(data["issues"], dict):
        return data["issues"].get("nodes", [])
    if "issues" in data:
        return data["issues"]
    raise SystemExit("認不出這份 JSON 的形狀：預期 .issues.nodes / .issues / 裸 list")


def is_done(status):
    """statusCategory 是唯一可靠的完成判準——狀態名稱會因專案語言與自訂而變。"""
    return (status or {}).get("statusCategory", {}).get("key") == "done"


def category(status):
    return (status or {}).get("statusCategory", {}).get("key") or "unknown"


def priority_rank(fields):
    p = fields.get("priority") or {}
    name = (p.get("name") or "").strip().lower()
    if name in PRIORITY_RANK:
        return PRIORITY_RANK[name], p.get("name") or "－"
    try:
        return int(p.get("id", 99)), p.get("name") or "－"
    except (TypeError, ValueError):
        return 99, p.get("name") or "－"


def links(fields):
    """把 issuelinks 拆成「擋我的」與「我擋的」。

    方向陷阱：type 物件同時帶 inward 與 outward 兩個描述字串，所以不能靠
    type.outward 判方向——那個欄位在 inward link 上照樣有值。唯一可靠的判準是
    哪個鍵存在：inwardIssue 代表「這張票 is blocked by 對方」，
    outwardIssue 代表「這張票 blocks 對方」。
    """
    blocked_by, blocks = [], []
    for link in fields.get("issuelinks") or []:
        if (link.get("type") or {}).get("name") != "Blocks":
            continue
        if link.get("inwardIssue"):
            blocked_by.append(link["inwardIssue"])
        elif link.get("outwardIssue"):
            blocks.append(link["outwardIssue"])
    return blocked_by, blocks


def brief(issue):
    f = issue.get("fields", {})
    return {
        "key": issue.get("key"),
        "summary": f.get("summary") or "",
        "status": (f.get("status") or {}).get("name") or "－",
        "done": is_done(f.get("status")),
    }


def days_since(ts):
    if not ts:
        return None
    try:
        # Jira: 2026-07-30T12:34:56.789+0800
        dt = datetime.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S")
        tz = ts[19:].replace(":", "")
        if tz and tz[0] in "+-":
            dt = dt.replace(tzinfo=timezone.utc) - _offset(tz)
        else:
            dt = dt.replace(tzinfo=timezone.utc)
        return (datetime.now(timezone.utc) - dt).days
    except (ValueError, IndexError):
        return None


def _offset(tz):
    from datetime import timedelta
    sign = 1 if tz[0] == "+" else -1
    return sign * timedelta(hours=int(tz[1:3]), minutes=int(tz[3:5]))


def analyse(issues, container_names=(), branch_tickets=()):
    by_key = {i.get("key"): i for i in issues}
    rows, containers = [], []

    for issue in issues:
        f = issue.get("fields", {})
        it = f.get("issuetype") or {}
        # 容器票（Epic / 本專案的「工作流」）不是可執行任務，不該被建議去「做」。
        # hierarchyLevel > 0 比比對名稱通用；名稱清單只是給自訂型別的後路。
        # 子任務 hierarchyLevel = -1，是可執行的，要留著。
        if it.get("hierarchyLevel", 0) > 0 or it.get("name") in container_names:
            containers.append(brief(issue))
            continue
        if is_done(f.get("status")):
            continue

        blocked_by, blocks = links(f)
        open_blockers = [brief(b) for b in blocked_by if not is_done((b.get("fields") or {}).get("status"))]
        # 解鎖效益只算「還沒完成」的下游。擋住一張早就完成的票等於沒擋住任何人——
        # 真實資料裡這種殘留連結很常見，全算進去會把效益虛報得離譜。
        open_downstream = [brief(b) for b in blocks if not is_done((b.get("fields") or {}).get("status"))]

        rank, pname = priority_rank(f)
        cat = category(f.get("status"))
        rows.append({
            "key": issue.get("key"),
            "summary": f.get("summary") or "",
            "status": (f.get("status") or {}).get("name") or "－",
            "category": cat,
            "type": it.get("name") or "－",
            "parent": (f.get("parent") or {}).get("key"),
            "parent_summary": ((f.get("parent") or {}).get("fields") or {}).get("summary"),
            "priority": pname,
            "priority_rank": rank,
            "labels": f.get("labels") or [],
            "assignee": ((f.get("assignee") or {}).get("displayName")),
            "idle_days": days_since(f.get("updated")),
            "blocked_by_open": open_blockers,
            "blocked_by_all": [brief(b) for b in blocked_by],
            "unlocks": open_downstream,
            "actionable": not open_blockers,
            "on_branch": issue.get("key") in branch_tickets,
        })

    actionable = [r for r in rows if r["actionable"]]
    blocked = [r for r in rows if not r["actionable"]]

    def sort_key(r):
        return (
            # 1. 收尾優先：半成品的價值是 0。已在進行中／審核中的票通常只差最後一哩，
            #    把它收成完成比開新戰場划算得多。
            0 if r["category"] == "indeterminate" else 1,
            # 2. 解鎖效益：能讓最多下游動起來的先做，看板整體才會流動。
            -len(r["unlocks"]),
            # 3. Jira 優先序欄位。
            r["priority_rank"],
            # 4. 票號：穩定的收尾條件，小號通常是先規劃的。
            _numeric(r["key"]),
        )

    actionable.sort(key=sort_key)
    blocked.sort(key=lambda r: (r["priority_rank"], _numeric(r["key"])))

    return {
        "recommended": actionable[0] if actionable else None,
        "runners_up": actionable[1:4],
        "actionable": actionable,
        "blocked": blocked,
        "containers": containers,
        "anomalies": anomalies(rows, blocked, branch_tickets, by_key),
    }


def _numeric(key):
    try:
        return int(str(key).rsplit("-", 1)[-1])
    except (ValueError, IndexError):
        return 10**9


def anomalies(rows, blocked, branch_tickets, by_key):
    """找狀態不一致。只回報，不修——盤點順手改看板是幫倒忙。"""
    out = []
    in_flight = [r for r in rows if r["category"] == "indeterminate"]

    for r in rows:
        # 可解未解：blocker 全清了，票卻還躺在被擋住的狀態欄。
        # 這是看板最常見的假訊號，會讓人以為沒事可做。
        if r["actionable"] and r["blocked_by_all"] and "block" in r["status"].lower():
            out.append({
                "kind": "可解未解",
                "key": r["key"],
                "detail": f"blocker 全部完成（{', '.join(b['key'] for b in r['blocked_by_all'])}），"
                          f"票仍停在「{r['status']}」",
                "suggest": "推 todo",
            })
        if r["on_branch"] and r["category"] == "to do":
            out.append({
                "kind": "分支已動工但票未推進",
                "key": r["key"],
                "detail": f"分支名對到這張票，票仍在「{r['status']}」",
                "suggest": "推 inProgress",
            })
        if r["category"] == "indeterminate" and r["idle_days"] is not None and r["idle_days"] >= STALE_DAYS:
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

    rec = res["recommended"]
    if rec:
        L.append("### 建議下一張")
        L.append(f"**{rec['key']}** {rec['summary']}")
        L.append(f"- 可動 ✅ {'無 blocker' if not rec['blocked_by_all'] else 'blocker 全清'}")
        L.append(f"- 優先序 {rec['priority']}")
        unlocks = rec["unlocks"]
        L.append(f"- 解鎖效益 {'解開 ' + ', '.join(b['key'] for b in unlocks) if unlocks else '無下游等待'}")
        if rec["category"] == "indeterminate":
            note = f"- 已在「{rec['status']}」，屬收尾工作"
            # 推薦收尾一張停滯很久的票時，要當場說出停滯——否則使用者會直接動手，
            # 卻沒發現它可能早就完成了、或卡在某個沒記錄下來的問題上。
            if rec["idle_days"] is not None and rec["idle_days"] >= STALE_DAYS:
                note += f"，但已 {rec['idle_days']} 天沒更新，先確認它的真實進度"
            L.append(note)
        if rec["parent"]:
            L.append(f"- 所屬 {rec['parent']} {rec['parent_summary'] or ''}".rstrip())
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

    if res["anomalies"]:
        L.append("\n### 待修正（本 skill 不動票，請自行決定）")
        for a in res["anomalies"]:
            L.append(f"- ⚠️ {a['key']}：{a['detail']} → 建議{a['suggest']}")

    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path", help="JSON 檔路徑，或 - 讀 stdin")
    ap.add_argument("--container-type", default="",
                    help="容器票型別名稱，逗號分隔（例如 工作流,Epic）")
    ap.add_argument("--branch-tickets", default="",
                    help="從分支名抽到的票號，逗號分隔")
    ap.add_argument("--scope-note", default="")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    split = lambda s: tuple(x.strip() for x in s.split(",") if x.strip())
    res = analyse(load(a.path), split(a.container_type), split(a.branch_tickets))
    print(json.dumps(res, ensure_ascii=False, indent=2) if a.json
          else render(res, a.scope_note or None))


if __name__ == "__main__":
    main()
