"""重写 data/config/difficulty.json 的 day_plans：每天只点当天已解锁的堡，并让每道堡都有真实客流。

第 1-7 天保留每张客单的 sp / fries / drink 原值与原位置，只改 burger 序号；
第 8 天起旧文件里没有行，sp / fries / drink 由本脚本按确定性公式造出来
（同一输入跑两次结果一致，不依赖随机种子）。

每种的落位用确定性均匀铺开（(i+0.5)*n/k），避免难单全堆在收尾。

  python tools/gen_plans.py          # 干跑，打印每天的人数 / 流水 / 点单构成
  python tools/gen_plans.py --write  # 写回 difficulty.json
"""
import io
import json
import sys

CFG = "data/config/difficulty.json"
DISH = "data/config/dishes.json"

SPECIES = 5  # customers.json 的物种数：0兔 1狐 2河马 3猫 4熊

# 每天各堡下标的点单人数。0经典 1鲜蔬 2至尊 3培根蛋 4酸笋 5全家。
# 章四（经济跑通检查）量出来第 4 天是断崖：酸笋堡 6 刀、一次上 4 份，
# 十个失误一次的超级 bot 都只出得了 5/12，所以新菜的"首秀量"压到 2 份再逐日加。
PLAN = [
    {0: 8},
    {0: 6, 1: 4},
    {0: 5, 1: 3, 4: 2},
    {0: 6, 1: 4, 4: 2},
    {0: 4, 1: 3, 2: 2, 3: 2, 4: 1},
    {0: 4, 1: 3, 2: 3, 3: 2, 4: 2},
    {0: 3, 1: 3, 2: 3, 3: 3, 4: 2},
    # 第二章（第 8~14 天）只多一道 8 层的「柴火全家堡」（下标 5）。
    # 难度靠两件事慢慢抬：来客人数 14→18，以及 7~8 层那种难单的占比 36%→61%。
    {0: 3, 1: 3, 2: 3, 3: 2, 4: 1, 5: 2},
    {0: 3, 1: 3, 2: 3, 3: 2, 4: 1, 5: 3},
    {0: 3, 1: 3, 2: 3, 3: 2, 4: 2, 5: 3},
    {0: 3, 1: 3, 2: 3, 3: 3, 4: 1, 5: 3},
    {0: 3, 1: 3, 2: 4, 3: 2, 4: 2, 5: 3},
    {0: 3, 1: 4, 2: 4, 3: 2, 4: 2, 5: 3},
    {0: 2, 1: 4, 2: 4, 3: 3, 4: 2, 5: 3},
]

# 旧文件里已经手写过 sp/fries/drink 的那些天，照原样保留（经济曲线是在它们上量出来的）
LEGACY_DAYS = 7

HARD_STACKS = 7  # 层数 >= 这个数算"难单"

NOTES = (
    "day_plans 为第 1-%d 天手工编排的客单。sp 为顾客物种序号（0兔 1狐 2河马 3猫 4熊），"
    "fries/drink 为是否加购。burger 为汉堡序号（0经典 1鲜蔬 2至尊 3培根蛋 4酸笋 5全家），"
    "每行只出现该天 dishes.json unlock_day 已达标的堡，六道堡在第二章内全部有真实点单；"
    "每种的落位由 (i+0.5)*n/k 均匀铺开，避免难单全堆在收尾。"
    "第 1-7 天的 sp/fries/drink 沿用开店首周的原值，第 8 天起由 tools/gen_plans.py 的"
    "确定性公式生成（无随机种子，跑两次一致）。" % len(PLAN)
)


def spread(counts: dict, n: int) -> list:
    """把 {下标: 人数} 铺成长度 n 的序列，同种彼此隔开。"""
    slots = [None] * n
    for idx in sorted(counts):
        k = counts[idx]
        for i in range(k):
            p = int(round((i + 0.5) * n / k)) % n
            while slots[p] is not None:
                p = (p + 1) % n
            slots[p] = idx
    return slots


def synth_rows(n: int, day: int) -> list:
    """第 8 天起的行：物种轮转 + 加购按确定性同余式判，跑两次完全一致。"""
    rows = []
    for i in range(n):
        rows.append({
            "sp": (i * 2 + day) % SPECIES,
            "fries": 1 if ((i * 7 + day * 3) % 10) < 6 else 0,
            "drink": 1 if ((i * 5 + day * 11) % 10) < 6 else 0,
        })
    return rows


def main() -> int:
    write = "--write" in sys.argv
    diff = json.load(io.open(CFG, encoding="utf-8"))
    dishes = json.load(io.open(DISH, encoding="utf-8"))
    burgers = dishes["burgers"]
    price = [int(b["price"]) for b in burgers]
    day_of = [int(b["unlock_day"]) for b in burgers]
    layers = [len(b["stack"]) for b in burgers]

    for d, counts in enumerate(PLAN, start=1):
        total = sum(counts.values())
        for idx in counts:
            assert idx < len(burgers), f"day {d} 点了不存在的堡下标 {idx}"
            assert day_of[idx] <= d, f"day {d} 点了第 {day_of[idx]} 天才解锁的 {burgers[idx]['id']}"
        if d <= LEGACY_DAYS:
            assert total == len(diff["day_plans"][d - 1]["customers"]), f"day {d} 人数变了"

    plans = []
    lines = []
    for d, counts in enumerate(PLAN, start=1):
        n = sum(counts.values())
        if d <= LEGACY_DAYS:
            customers = [dict(c) for c in diff["day_plans"][d - 1]["customers"]]
            assert len(customers) == n
        else:
            customers = synth_rows(n, d)
        new_idx = spread(counts, n)
        gross = sum(price[i] for i in new_idx)
        hard = sum(1 for i in new_idx if layers[i] >= HARD_STACKS)
        lines.append("day %2d  n=%2d  gross %3d  难单 %2d/%2d = %2.0f%%  mix %s" % (
            d, n, gross, hard, n, 100.0 * hard / n,
            " ".join("%s x%d" % (burgers[i]["short"], c) for i, c in sorted(counts.items()) if c)))
        for i, c in enumerate(customers):
            c["burger"] = new_idx[i]
        plans.append({"day": d, "customers": customers})

    seen = set(i for p in PLAN for i in p)
    missing = [burgers[i]["id"] for i in range(len(burgers)) if i not in seen]
    print("\n".join(lines))
    print("周流水: 一章 %d / 二章 %d" % (
        sum(sum(price[i] * c for i, c in counts.items()) for counts in PLAN[:7]),
        sum(sum(price[i] * c for i, c in counts.items()) for counts in PLAN[7:])))
    print("covered burger indices:", sorted(seen), "未点单:", missing or "无")
    if missing:
        print("FAIL: 有汉堡整周零人点单")
        return 1

    if not write:
        print("(dry run; pass --write)")
        return 0

    out = ["{", '  "notes": %s,' % json.dumps(NOTES, ensure_ascii=False), '  "day_plans": [']
    for i, p in enumerate(plans):
        out.append("    {")
        out.append('      "day": %d,' % p["day"])
        out.append('      "customers": [')
        rows = p["customers"]
        for j, c in enumerate(rows):
            tail = "," if j < len(rows) - 1 else ""
            out.append('        { "sp": %d, "burger": %d, "fries": %d, "drink": %s }%s' % (
                c["sp"], c["burger"], c["fries"], json.dumps(c["drink"]), tail))
        out.append("      ]")
        out.append("    }" + ("," if i < len(plans) - 1 else ""))
    out.append("  ],")
    out.append('  "bonus_pool": [')
    for j, c in enumerate(diff["bonus_pool"]):
        tail = "," if j < len(diff["bonus_pool"]) - 1 else ""
        out.append('    { "sp": %d, "burger": %d, "fries": %d, "drink": %s }%s' % (
            c["sp"], c["burger"], c["fries"], json.dumps(c["drink"]), tail))
    out.append("  ]")
    out.append("}")
    io.open(CFG, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
    again = json.load(io.open(CFG, encoding="utf-8"))
    assert [p["day"] for p in again["day_plans"]] == list(range(1, len(PLAN) + 1)), "天数不连续"
    assert again["bonus_pool"] == diff["bonus_pool"], "bonus_pool 被动过"
    print("wrote %s (%d days)" % (CFG, len(plans)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
