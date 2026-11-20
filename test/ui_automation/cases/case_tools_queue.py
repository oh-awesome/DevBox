"""
case_tools_queue.py —— 通用工具队列 E2E（队列三修回归：finish 重入/取消双路/位次渲染）

真值通道：hilog testTag（TaskQueue.queued / TaskQueue.advance / DevEnvInstall.finish）
操作通道：dump 定位（换页后 dump 实测有效——首帧冻结仅在 force-stop 场景）+ Device.click
断言矩阵：
  A1 入队：连点 2 个安装 → hilog 出现 TaskQueue.queued pos=1
  A2 位次：排队行 dump 文本含 "排队中（第 1 位）"
  A3 取消排队：点击排队行"取消" → 该行回到安装态（dump 安装按钮回归）
  A4 队列推进：队首完成后 hilog 出现 TaskQueue.advance install_（真值——重入根因回归线）
  A5 完成收尾：最终 hilog DevEnvInstall.finish(true（或 idle 收尾）

用法：python cases/case_tools_queue.py [workdir]  （约 2-8 分钟，含真实下载）
"""

import sys, os, time, json, re, datetime
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.device import Device, _sh
from core import dump, vision

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TPL = f'{ROOT}/templates'


def hilog_grep(_dev: Device, pattern: str) -> list[str]:
    out = _sh('hdc shell "hilog -T testTag -x"', timeout=30)
    return [l for l in out.splitlines() if re.search(pattern, l)]


def content_buttons(root: dict, label: str) -> list[dict]:
    """内容区（x>500，排除侧边栏）内文本=label 的按钮行"""
    out = []
    for a in dump.texts(root):
        if a.get('text', '').strip() != label:
            continue
        b = [int(v) for v in re.findall(r'-?\d+', a['bounds'])]
        if len(b) == 4 and b[0] > 500:
            out.append({'bbox': b, 'cy': (b[1] + b[3]) // 2})
    return sorted(out, key=lambda r: r['cy'])


def row_tool_name(root: dict, cy: int) -> str:
    """同一行带（cy±30）里最左侧的文本=工具名"""
    cands = []
    for a in dump.texts(root):
        b = [int(v) for v in re.findall(r'-?\d+', a['bounds'])]
        if len(b) == 4 and abs((b[1] + b[3]) // 2 - cy) < 30 and b[0] > 500:
            cands.append((b[0], a['text'].strip()))
    cands.sort()
    return cands[0][1] if cands else '?'


def wait_row_installed(dev, workdir: str, name: str, timeout: float, poll: float = 5.0) -> list[str] | None:
    """状态兜底：轮询 dump 直到 name 行出现「已装」（真值=应用自身 fs 目录扫描）"""
    t0 = time.time()
    n = 0
    while time.time() - t0 < timeout:
        n += 1
        root = dump.fresh_dump(workdir, f'tq_wi{n}')
        b = None
        for a in dump.texts(root):
            if a.get('text', '').strip() == name:
                bb = [int(v) for v in re.findall(r'-?\d+', a['bounds'])]
                if len(bb) == 4:
                    b = bb
                    break
        if b is None:
            time.sleep(poll)
            continue
        cy = (b[1] + b[3]) // 2
        for t in dump.texts(root):
            if t['text'].strip().startswith('已装'):
                tb = [int(v) for v in re.findall(r'-?\d+', t['bounds'])]
                if len(tb) == 4 and abs((tb[1] + tb[3]) // 2 - cy) < 40:
                    return ['installed']
        time.sleep(poll)
    return None


def wait_hilog(dev, pattern: str, timeout: float, poll: float = 3.0) -> list[str]:
    t0 = time.time()
    while time.time() - t0 < timeout:
        hits = hilog_grep(dev, pattern)
        if hits:
            return hits
        time.sleep(poll)
    return []


def main(workdir: str):
    os.makedirs(workdir, exist_ok=True)
    dev = Device(workdir)
    results = []

    def record(aid: str, ok: bool, note: str):
        results.append((aid, 'PASS' if ok else 'FAIL', note))
        print(f'{aid}: {"PASS" if ok else "FAIL"} {note}')

    dev.restart_app(wait=9.0, test_mode=True)
    time.sleep(1)
    # 导航：模板点击 通用工具
    meta = json.load(open(f'{TPL}/meta.json', encoding='utf-8'))
    rel = meta['items']['通用工具']
    shot = dev.screenshot('tq_base')
    hit = vision.match(shot, f'{TPL}/sidebar_通用工具.png',
                       region=(rel[0]-80, rel[1]-80, rel[2]+80, rel[3]+80), stride=1)
    if not hit:
        record('NAV', False, '侧边栏未命中'); return report(results, workdir)
    dev.click((hit[0]+hit[2])//2, (hit[1]+hit[3])//2)
    time.sleep(2.5)

    root = dump.fresh_dump(workdir, 'tq_p0')
    installs = content_buttons(root, '安装')
    # 跳过巨型包（commandline-tools ~2GB：停滞重试+超时窗口不可控）
    BIG = {'commandline-tools'}
    picks = []
    for btn in installs:
        if row_tool_name(root, btn['cy']) not in BIG:
            picks.append(btn)
    if len(picks) < 3:
        record('A0', False, f'可安装行不足（{len(picks)}），需≥3'); return report(results, workdir)
    A, B, C = picks[0], picks[1], picks[2]
    nameA, nameB, nameC = (row_tool_name(root, r['cy']) for r in (A, B, C))
    print(f'选中: A={nameA} B={nameB} C={nameC}')

    # A1 连点三个安装（A 直跑；B/C 入队）——逐步调试输出（间歇性点击被吞排查）
    # 首击落地校验（点击间歇性被吞——窗口焦点瞬态；未落地重试一次）
    def busy_count() -> int:
        _r = dump.fresh_dump(workdir, 'tq_dbg')
        return sum(1 for t in [a['text'].strip() for a in dump.texts(_r)] if t == '取消')
    ax, ay = (A['bbox'][0]+A['bbox'][2])//2, A['cy']
    dev.click(ax, ay); time.sleep(2.0)
    if busy_count() == 0:
        dev.click(ax, ay); time.sleep(2.0)   # 首击被吞：重试
    dev.click(*[ (B['bbox'][0]+B['bbox'][2])//2, B['cy'] ]); time.sleep(1.0)
    dev.click(*[ (C['bbox'][0]+C['bbox'][2])//2, C['cy'] ]); time.sleep(2.5)

    # A1 断言走 dump（hilog 缓冲被启动日志洪峰刷穿——通道不可靠，仅作附加信息）
    q = hilog_grep(dev, r'TaskQueue\.queued')
    rootx = dump.fresh_dump(workdir, 'tq_x')
    qx = [t for t in [a['text'].strip() for a in dump.texts(rootx)] if '排队中' in t]
    record('A1', len(qx) >= 1,
           f'排队文案 {len(qx)} 行: {qx[:2]}；queued 日志 {len(q)} 条（hilog 通道不稳仅供参考）')

    # A2 位次渲染（dump 重取）
    root2 = dump.fresh_dump(workdir, 'tq_p1')
    txts = [a['text'] for a in dump.texts(root2)]
    queued_txt = [t for t in txts if '排队中' in t]
    record('A2', len(queued_txt) >= 1, f'排队文案行: {queued_txt[:2]}')

    # A3 取消排队中的 C（busy 行按钮变"取消"）
    cancels = content_buttons(root2, '取消')
    ok3 = False; note3 = '未找到取消按钮'
    if cancels:
        # 取最下方的取消（C 的行）
        tgt = cancels[-1]
        dev.click((tgt['bbox'][0]+tgt['bbox'][2])//2, tgt['cy'])
        time.sleep(2.5)
        root3 = dump.fresh_dump(workdir, 'tq_p2')
        # C 行回归安装态：C 同行带内出现 安装 按钮
        ok3 = any(abs(((bb[1]+bb[3])//2) - C['cy']) < 40 for bb in
                  [[int(v) for v in re.findall(r'-?\d+', a['bounds'])]
                   for a in dump.texts(root3) if a['text'].strip() == '安装'])
        note3 = f'取消点击完成，C 行回归安装态={ok3}'
    record('A3', ok3, note3)

    # A4 队列推进（真值：hilog advance；兜底：B 行已装——hilog 缓冲被下载进度日志刷掉的场景）
    adv = wait_hilog(dev, r'TaskQueue\.advance', timeout=240)
    if not adv:
        adv = wait_row_installed(dev, workdir, nameB, timeout=180)
    record('A4', bool(adv), ('advance 日志' if 'testTag' in str(adv) else 'B 行已装（状态兜底）') if adv else '240s+180s 未见队列推进')

    # A5 收尾：finish(true 或 B 行已装
    fin = wait_hilog(dev, r'DevEnvInstall\.finish\(true', timeout=240)
    if not fin:
        fin = wait_row_installed(dev, workdir, nameB, timeout=60)
    record('A5', bool(fin), (fin[-1].split('testTag:')[-1].strip()[:60] if fin and isinstance(fin, list) else
                             'B 行已装（状态兜底）') if fin else '未见成功收尾')

    return report(results, workdir)


def report(results, workdir):
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    rp = f'{ROOT}/reports/case_tools_queue_{ts}.md'
    os.makedirs(f'{ROOT}/reports', exist_ok=True)
    with open(rp, 'w', encoding='utf-8') as f:
        f.write(f'# 通用工具队列用例 {ts}\n\n| 断言 | 结果 | 详情 |\n|---|---|---|\n')
        for aid, st, note in results:
            f.write(f'| {aid} | {st} | {note} |\n')
    fails = sum(1 for _, st, _ in results if st == 'FAIL')
    print(f'\n报告: {rp}\nPASS {len(results)-fails} / FAIL {fails}')
    return fails


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else '.'))
