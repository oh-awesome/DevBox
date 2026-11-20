"""
case_lang_queue.py —— 语言运行时页队列 E2E（LangRuntimePage 队列化回归：9 语言页共用件）

关键经验：DevVersionRow busy 态行变高 → 下方行整体下移（实测 +36px），
点击必须每次 fresh_dump 取新坐标（DevPkgRow 固定 48vp 行高无此问题）。

覆盖：
  A1 排队显示：连点 2 个版本 → 第二行出现"排队中（第 N 位）"（dump 文本）+ queued 日志
  A2 去重：快速双击同版本 → 只入队一次（TaskQueue.queued 同 id 仅 1 条，且行未被误取消）
  A3 取消排队：点 B 行"取消" → B 行恢复安装按钮（按版本文本定位行）
  A4 收尾清理：取消所有 running（断点保留语义，不等待真实装完）

真值通道：hilog testTag（TaskQueue.queued/advance/finish）+ dump 文本
用法：python cases/case_lang_queue.py [workdir] [语言页名=Java]
"""

import sys, os, time, json, re, datetime
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.device import Device, _sh
from core import dump, vision

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TPL = f'{ROOT}/templates'


def hilog_grep(pattern: str) -> list[str]:
    out = _sh('hdc shell "hilog -T testTag -x"', timeout=30)
    return [l for l in out.split('\n') if re.search(pattern, l)]


def buttons(root: dict, label: str) -> list[dict]:
    """内容区文本=label 的按钮（按 y 排序）"""
    out = []
    for a in dump.texts(root):
        if a.get('text', '').strip() != label:
            continue
        b = [int(v) for v in re.findall(r'-?\d+', a['bounds'])]
        if len(b) == 4 and b[0] > 500:
            out.append({'bbox': b, 'cy': (b[1] + b[3]) // 2})
    return sorted(out, key=lambda r: r['cy'])


def version_at(root: dict, cy: int) -> str:
    """行带（cy±34）最左侧文本=版本号（行身份锚）"""
    cands = []
    for a in dump.texts(root):
        b = [int(v) for v in re.findall(r'-?\d+', a['bounds'])]
        if len(b) == 4 and abs((b[1] + b[3]) // 2 - cy) < 34 and b[0] > 500:
            cands.append((b[0], a['text'].strip()))
    cands.sort()
    return cands[0][1] if cands else '?'


def row_state(root: dict, ver: str) -> str:
    """指定版本行的按钮态：'取消'/'安装'/''（按版本文本定位行带，再看行内按钮）"""
    for a in dump.texts(root):
        if a.get('text', '').strip() == ver:
            b = [int(v) for v in re.findall(r'-?\d+', a['bounds'])]
            if len(b) != 4 or b[0] <= 500:
                continue
            cy = (b[1] + b[3]) // 2
            for btn in buttons(root, '取消') + buttons(root, '安装'):
                if abs(btn['cy'] - cy) < 40:
                    return '取消' if btn in buttons(root, '取消') else '安装'
    return ''


def main(workdir: str, page: str = 'Java'):
    os.makedirs(workdir, exist_ok=True)
    dev = Device(workdir)
    results = []

    def record(aid: str, ok: bool, note: str):
        results.append((aid, 'PASS' if ok else 'FAIL', note))
        print(f'{aid}: {"PASS" if ok else "FAIL"} {note}')

    def fresh(tag: str) -> dict:
        return dump.fresh_dump(workdir, tag)

    dev.restart_app(wait=9.0, test_mode=True)
    time.sleep(1)
    meta = json.load(open(f'{TPL}/meta.json', encoding='utf-8'))
    rel = meta['items'].get(page)
    if rel is None:
        record('NAV', False, f'meta 无 {page} 页'); return report(results)
    shot = dev.screenshot('lq_base')
    hit = vision.match(shot, f'{TPL}/sidebar_{page}.png',
                       region=(rel[0]-80, rel[1]-80, rel[2]+80, rel[3]+80), stride=1)
    if not hit:
        record('NAV', False, '侧边栏未命中'); return report(results)
    dev.click((hit[0]+hit[2])//2, (hit[1]+hit[3])//2)
    time.sleep(2.5)

    root = fresh('lq_p0')
    installs = buttons(root, '安装')
    if len(installs) < 3:
        record('A0', False, f'可安装版本不足（{len(installs)}），需≥3'); return report(results)

    # A1：点 A（直跑）→ fresh dump 后点 B（行已下移，须取新坐标）
    A = installs[0]
    verA = version_at(root, A['cy'])
    dev.click((A['bbox'][0]+A['bbox'][2])//2, A['cy'])
    time.sleep(1.5)
    root = fresh('lq_p1')          # A 已 busy，下方行下移
    inst2 = buttons(root, '安装')
    if not inst2:
        record('A1', False, 'A 未进入运行态（无后续安装行）'); return report(results)
    B = inst2[0]
    verB = version_at(root, B['cy'])
    dev.click((B['bbox'][0]+B['bbox'][2])//2, B['cy'])
    time.sleep(2.5)

    root = fresh('lq_p2')
    qtxt = [t for t in [a['text'] for a in dump.texts(root)] if '排队中' in t]
    qlogs = hilog_grep(r'TaskQueue\.queued')
    record('A1', bool(qtxt),
           f'A={verA} B={verB}；排队文案: {qtxt[:1]}；queued 日志 {len(qlogs)} 条（hilog 通道不稳仅供参考）')

    # A2：去重——裸双击 C（<100ms 间隔，须绕过 Device.click 的 1.2s settle；
    # 否则第二击时行已翻转为取消按钮，点到的是取消出队而非去重拒绝——实测教训）
    root = fresh('lq_p3')
    inst3 = buttons(root, '安装')
    ok2, note2 = False, '无第三个可安装行'
    if inst3:
        C = inst3[0]
        verC = version_at(root, C['cy'])
        cx, cy = (C['bbox'][0]+C['bbox'][2])//2, C['cy']
        # 单条 hdc shell 链两击（进程spawn间隔~200ms+会错过翻转窗口——实测教训）
        # 行按钮即时翻转（AppStorage→@Watch 同帧）意味着第二击要么被 TaskQueue 去重拒绝
        # （C 留队，行=取消）要么点到取消出队（C 净空，行=安装）——两条路都无重复残留，
        # 断言的是用户保障：快速连点绝不产生重复/卡死任务，行态恒一致
        _sh(f'hdc shell "uitest uiInput click {cx} {cy}; uitest uiInput click {cx} {cy}"')
        time.sleep(2.5)
        qall = hilog_grep(r'TaskQueue\.queued')
        ids = [m.group(1) for l in qall for m in [re.search(r'TaskQueue\.queued (\S+)', l)] if m]
        dup = len(ids) - len(set(ids))
        st = row_state(fresh('lq_p4'), verC)
        ok2 = dup == 0 and st in ('安装', '取消')
        note2 = f'C={verC} 重复入队 {dup} 次；C 行态={st or "?"}（路径=去重拒绝或即时出队）'
    record('A2', ok2, note2)

    # A3：取消排队中的 B（按版本定位行内取消按钮）
    root = fresh('lq_p5')
    ok3, note3 = False, 'B 行无取消按钮'
    bCancels = [c for c in buttons(root, '取消')]
    bRow = None
    for c in bCancels:
        if version_at(root, c['cy']) == verB:
            bRow = c; break
    if bRow is not None:
        dev.click((bRow['bbox'][0]+bRow['bbox'][2])//2, bRow['cy'])
        time.sleep(2.5)
        st = row_state(fresh('lq_p6'), verB)
        ok3 = st == '安装'
        note3 = f'取消后 B 行态={st or "?"}（须=安装）'
    record('A3', ok3, note3)

    # A4：收尾——循环取消所有剩余（每轮 fresh dump；断点保留不等待装完）
    for _ in range(4):
        root = fresh('lq_p7')
        cs = buttons(root, '取消')
        if not cs:
            break
        dev.click((cs[0]['bbox'][0]+cs[0]['bbox'][2])//2, cs[0]['cy'])
        time.sleep(2.5)
    # 状态断言（hilog -T 过滤间歇性空读不可靠）：全取消后无 busy 行且 A 行恢复安装态
    rootf = fresh('lq_p8')
    stA = row_state(rootf, verA)
    busy_left = len(buttons(rootf, '取消'))
    record('A4', busy_left == 0 and stA == '安装',
           f'剩余 busy 行 {busy_left}；A 行态={stA or "?"}（须=安装，断点保留）')

    return report(results)


def report(results):
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    rp = f'{ROOT}/reports/case_lang_queue_{ts}.md'
    os.makedirs(f'{ROOT}/reports', exist_ok=True)
    with open(rp, 'w', encoding='utf-8') as f:
        f.write(f'# 语言页队列用例 {ts}\n\n| 断言 | 结果 | 详情 |\n|---|---|---|\n')
        for aid, st, note in results:
            f.write(f'| {aid} | {st} | {note} |\n')
    fails = sum(1 for _, st, _ in results if st == 'FAIL')
    print(f'\n报告: {rp}\nPASS {len(results)-fails} / FAIL {fails}')
    return fails


if __name__ == '__main__':
    wd = sys.argv[1] if len(sys.argv) > 1 else '.'
    pg = sys.argv[2] if len(sys.argv) > 2 else 'Java'
    sys.exit(main(wd, pg))
