#!/usr/bin/env python3
"""用 Python 复刻 NaturalLanguageParser 的核心逻辑，离线验证测试用例。
仅用于开发期验证算法，不参与 App 编译。
"""
import re
from datetime import datetime, timedelta

NOW = datetime(2026, 11, 23, 12, 0)  # 周一

CN_DIGIT = {
    "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
    "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
}


def chinese_number(s):
    if s.isdigit():
        return int(s)
    if s == "十":
        return 10
    if "十" in s:
        parts = s.split("十")
        tens = 1 if parts[0] == "" else CN_DIGIT.get(parts[0][0], 0)
        ones = 0 if parts[1] == "" else CN_DIGIT.get(parts[1][0], 0)
        return tens * 10 + ones
    if len(s) == 1:
        return CN_DIGIT.get(s)
    return None


def normalize(s):
    mp = str.maketrans("０１２３４５６７８９：／－。，、", "0123456789:/-   ")
    s = s.translate(mp)
    return re.sub(r"\s+", " ", s).strip()


def parse(raw):
    text = normalize(raw)
    result = {"title": "", "due": None, "priority": 0, "tags": [], "recurrence": None, "has_time": False}
    # 复合词展开
    for w, r in [("明早", "明天 早上"), ("明晚", "明天 晚上"), ("今晚", "今天 晚上"), ("今早", "今天 早上")]:
        text = text.replace(w, r)

    # 标签
    tags = re.findall(r"#([^\s#]+)", text)
    result["tags"] = tags
    text = re.sub(r"#([^\s#]+)", " ", text)
    text = re.sub(r"\s+", " ", text).strip()

    # 优先级
    for kw in ["紧急", "重要", "急件", "加急", "!!!", "！！"]:
        if kw in text:
            text = text.replace(kw, " ")
            result["priority"] = 1
            break
    if result["priority"] == 0 and re.search(r"!{3,}", text):
        text = re.sub(r"!{3,}", " ", text)
        result["priority"] = 1

    # 重复
    if re.search(r"(每天|每日|天天)", text):
        text = re.sub(r"(每天|每日|天天)", " ", text)
        result["recurrence"] = "daily"
    else:
        m = re.search(r"(每(周|星期|礼拜))\s*([一二三四五六日天、,和\s]+)", text)
        if m:
            wdmap = {"一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1}
            wds = sorted({wdmap[c] for c in m.group(3) if c in wdmap})
            if wds:
                text = text[:m.start()] + " " + text[m.end():]
                result["recurrence"] = ("weekly", wds)
    text = re.sub(r"\s+", " ", text).strip()

    date_base = None

    # 相对时长
    m = re.search(r"([0-9]+|半|[一两二三四五六七八九十]+)\s*(分钟|小时|个小时|天|周)\s*(后|之后|以后)", text)
    handled_relative = False
    if m:
        num, unit = m.group(1), m.group(2)
        if num == "半":
            val = 30
            delta = timedelta(minutes=30)
        else:
            val = chinese_number(num)
            if unit in ("分钟",):
                delta = timedelta(minutes=val)
            elif unit in ("小时", "个小时"):
                delta = timedelta(hours=val)
            elif unit == "天":
                delta = timedelta(days=val)
            else:
                delta = timedelta(weeks=val)
        date_base = NOW + delta
        result["has_time"] = True
        text = text[:m.start()] + " " + text[m.end():]
        handled_relative = True

    if not handled_relative:
        # 绝对日期
        m = re.search(r"([0-9]{4})[-/]([0-9]{1,2})[-/]([0-9]{1,2})", text)
        if m:
            date_base = datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)))
            text = text[:m.start()] + " " + text[m.end():]
        else:
            m = re.search(r"([0-9]{1,2})\s*[月/]\s*([0-9]{1,2})\s*[号日]?", text)
            if m:
                mo, d = int(m.group(1)), int(m.group(2))
                y = NOW.year
                if datetime(y, mo, d) < NOW.replace(hour=0, minute=0):
                    y += 1
                date_base = datetime(y, mo, d)
                text = text[:m.start()] + " " + text[m.end():]
            else:
                m = re.search(r"([0-9]{1,2})\s*[号日]", text)
                if m:
                    d = int(m.group(1))
                    mo = NOW.month
                    y = NOW.year
                    if d < NOW.day:
                        mo += 1
                        if mo > 12:
                            mo = 1
                            y += 1
                    date_base = datetime(y, mo, d)
                    text = text[:m.start()] + " " + text[m.end():]

        # 相对日期
        if date_base is None:
            today = NOW.replace(hour=0, minute=0)
            simple = [
                ("大后天", 3), ("后天", 2), ("明天", 1), ("明日", 1), ("明晚", 1),
                ("今晚", 0), ("今天", 0), ("今日", 0),
            ]
            for kw, offset in simple:
                if kw in text:
                    text = text.replace(kw, " ")
                    date_base = today + timedelta(days=offset)
                    break

        if date_base is None:
            m = re.search(r"下(个)?(周|星期|礼拜)([一二三四五六日天])", text)
            if m:
                wdmap = {"一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1}
                target = wdmap[m.group(3)]
                cur = NOW.isoweekday() % 7 + 1
                delta = (target - cur + 7) % 7
                delta = 7 if delta == 0 else delta + 7
                date_base = NOW.replace(hour=0, minute=0) + timedelta(days=delta)
                text = text[:m.start()] + " " + text[m.end():]
            else:
                m = re.search(r"(这|本)?(周|星期|礼拜)([一二三四五六日天])", text)
                if m:
                    wdmap = {"一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1}
                    target = wdmap[m.group(3)]
                    cur = NOW.isoweekday() % 7 + 1
                    delta = (target - cur + 7) % 7
                    date_base = NOW.replace(hour=0, minute=0) + timedelta(days=delta)
                    text = text[:m.start()] + " " + text[m.end():]

    # 时刻
    clock = None
    pattern = re.compile(
        r"(上午|早上|早晨|凌晨|中午|下午|傍晚|晚上|夜里|晚)?\s*"
        r"([0-9]{1,2}|[一二三四五六七八九十]{1,3})\s*[点:：]\s*"
        r"([0-9]{1,2}|[一二三四五六七八九十]{1,3})?\s*分?\s*(半)?"
    )
    if not handled_relative:
        m = pattern.search(text)
        if m:
            h = chinese_number(m.group(2))
            mi = chinese_number(m.group(3)) if m.group(3) else 0
            if m.group(4):
                mi = 30
            p = m.group(1)
            if p in ("下午", "傍晚", "晚上", "夜里", "晚") and h < 12:
                h += 12
            elif p == "中午" and h < 11:
                h += 12
            elif p == "凌晨" and h == 12:
                h = 0
            elif p in ("上午", "早上", "早晨") and h == 12:
                h = 0
            clock = (h, mi)
            text = text[:m.start()] + " " + text[m.end():]
            result["has_time"] = True

    if date_base is not None:
        if clock:
            date_base = date_base.replace(hour=clock[0], minute=clock[1])
        result["due"] = date_base
    elif clock:
        d = NOW.replace(hour=clock[0], minute=clock[1])
        if d < NOW:
            d += timedelta(days=1)
        result["due"] = d

    if result["recurrence"]:
        h, mi = clock if clock else (9, 0)
        is_weekly = isinstance(result["recurrence"], tuple) and result["recurrence"][0] == "weekly"
        if is_weekly:
            target = result["recurrence"][1][0]
            candidate = NOW.replace(hour=0, minute=0)
            while (candidate.isoweekday() % 7 + 1) != target:
                candidate += timedelta(days=1)
            anchor = candidate.replace(hour=h, minute=mi)
            if anchor < NOW:
                anchor += timedelta(days=7)
        else:
            anchor = NOW.replace(hour=h, minute=mi)
            if anchor < NOW:
                anchor += timedelta(days=1)
        result["due"] = anchor
        result["has_time"] = True

    # 孤立时段词兜底：有日期无时刻时补默认时刻
    if result["due"] is not None and not result["has_time"]:
        period_hours = {"早上":9,"上午":9,"中午":12,"下午":15,"晚上":20,"傍晚":20,"夜里":20,"凌晨":6}
        for w, h in period_hours.items():
            if w in text:
                result["due"] = result["due"].replace(hour=h, minute=0)
                result["has_time"] = True
                break
    # 剥离孤立时段词
    for w in ["上午", "下午", "中午", "早上", "晚上", "傍晚", "凌晨", "夜里"]:
        text = text.replace(w, " ")
    # 标题清洗
    text = re.sub(r"\s+", " ", text).strip()
    for p in ["提醒我", "记得", "帮我", "要", "去"]:
        if text.startswith(p):
            text = text[len(p):]
    text = text.strip(" :,，。！!?？、")
    text = re.sub(r"^\s*(前|之前)\s*", "", text)
    result["title"] = text or "新提醒"
    return result


CASES = [
    ("明天下午三点交报告", "交报告", "2026-11-24 15:00", 0),
    ("后天上午10点开会", "开会", "2026-11-25 10:00", 0),
    ("今晚8点打电话给妈妈", "打电话给妈妈", "2026-11-23 20:00", 0),
    ("明早八点半晨跑", "晨跑", "2026-11-24 08:30", 0),
    ("明天 14:30 项目评审", "项目评审", "2026-11-24 14:30", 0),
    ("30分钟后吃药", "吃药", "2026-11-23 12:30", 0),
    ("半小时后看火", "看火", "2026-11-23 12:30", 0),
    ("两小时后交表", "交表", "2026-11-23 14:00", 0),
    ("下周一 9:00 周会", "周会", "2026-11-30 09:00", 0),
    ("这周五下午交方案", "交方案", "2026-11-27 15:00", 0),
    ("12月25日 上午10点 送礼物", "送礼物", "2026-12-25 10:00", 0),
    ("每天 7点半 晨跑", "晨跑", "2026-11-24 07:30", 0),
    ("每周一三五 9点 健身", "健身", "2026-11-30 09:00", 0),
    ("每周五 18:00 周报", "周报", "2026-11-27 18:00", 0),
    ("紧急 明天交税", "交税", "2026-11-24 00:00", 1),
    ("交电费!!! 明天", "交电费", "2026-11-24 00:00", 1),
    ("明天 #工作 对齐需求", "对齐需求", "2026-11-24 00:00", 0),
    ("买牛奶", "买牛奶", "None", 0),
    ("明天下午３点交报告", "交报告", "2026-11-24 15:00", 0),
]

passed = 0
for raw, exp_title, exp_due, exp_priority in CASES:
    r = parse(raw)
    due_str = r["due"].strftime("%Y-%m-%d %H:%M") if r["due"] else "None"
    ok_title = r["title"] == exp_title
    ok_due = due_str == exp_due
    ok_pri = r["priority"] == exp_priority
    status = "PASS" if (ok_title and ok_due and ok_pri) else "FAIL"
    if status == "PASS":
        passed += 1
    print(f"{status} | {raw:<22} -> 标题={r['title']:<10} 时间={due_str:<16} 优先级={r['priority']}")
    if status == "FAIL":
        print(f"      期望: 标题={exp_title} 时间={exp_due} 优先级={exp_priority}")

print(f"\n通过 {passed}/{len(CASES)}")
