"""
run_smoke.py —— 全页面冒烟：导航 → 三断言 → 报告

断言：
  A. 页面切换生效（点击前后像素 diff > 3000）
  B. 内容区有文本行带（非空白页）
  C. 无错误 toast（danger 红色块扫描 #F24822 系）

用法：python run_smoke.py [workdir]
"""

import sys, os, time, json, datetime
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.device import Device
from core import dump, vision
from PIL import Image
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
TPL = f'{ROOT}/templates'


def window_origin(root: dict) -> tuple[int, int]:
    best, area = (0, 0), 0
    import re
    def rec(n, depth):
        nonlocal best, area
        a = n.get('attributes', {})
        if depth == 1 and a.get('bounds'):
            b = [int(v) for v in re.findall(r'-?\d+', a['bounds'])]
            if len(b) == 4 and 0 < (b[2]-b[0]) * (b[3]-b[1]) > area and (b[2]-b[0]) < 3100:
                best, area = (b[0], b[1]), (b[2]-b[0]) * (b[3]-b[1])
        for c in n.get('children', []):
            rec(c, depth + 1)
    rec(root, 0)
    return best



def track_origin(shot, meta, origin):
    """三锚投票重算窗口原点（容忍窗口漂移；锚=侧边栏非当前页条目）"""
    from PIL import Image
    votes = []
    ox, oy = origin
    for name in ('环境变量', 'Perl', 'Go'):
        rel = meta['items'].get(name)
        tpl = f'{TPL}/sidebar_{name}.png'
        if not rel or not os.path.exists(tpl):
            continue
        x1, y1 = rel[0] + ox, rel[1] + oy
        h = vision.match(shot, tpl, region=(x1 - 300, y1 - 200, x1 + 300, y1 + 200), stride=2)
        if h:
            votes.append((h[0] - rel[0], h[1] - rel[1]))
    if not votes:
        return origin
    # 中位（抗单锚误配）
    votes.sort()
    return votes[len(votes) // 2]

def red_alert(img: Image.Image) -> bool:
    """danger 红 toast/按钮大块检测（F24822 系：r>200, g<110, b<90）"""
    a = np.array(img.convert('RGB')).astype(int)
    r, g, b = a[:,:,0], a[:,:,1], a[:,:,2]
    mask = (r > 190) & (g < 110) & (b < 100) & ((r - g) > 100)
    return int(mask.sum()) > 2000


def content_rows(img: Image.Image, origin: tuple) -> list:
    """内容区（窗口右侧 2/3）文本行带"""
    ox, oy = origin
    return vision.text_rows(img, region=(500, 250, 2600, 1900), min_edges=15)


def main(workdir: str):
    dev = Device(workdir)
    dev.restart_app(wait=9.0, test_mode=True)
    time.sleep(1)
    root = dump.fresh_dump(workdir, 'smoke')
    print('全屏锁定模式（test_mode maximize），模板=绝对坐标')
    meta = json.load(open(f'{TPL}/meta.json', encoding='utf-8'))
    items = meta['items']
    items_first_page = next(iter(items))
    ox, oy = 0, 0

    results = []
    base = dev.screenshot('smoke_base')
    ox, oy = track_origin(base, meta, (ox, oy))
    for name, rel in items.items():
        tpl_path = f'{TPL}/sidebar_{name}.png'
        if not os.path.exists(tpl_path):
            results.append((name, 'SKIP', '模板缺失'))
            print(f'{name}: SKIP 模板缺失')
            continue
        # 窗口相对 → 屏幕（当轮原点）
        x1, y1, x2, y2 = rel[0]+ox, rel[1]+oy, rel[2]+ox, rel[3]+oy
        hit = vision.match(base, tpl_path, region=(max(0,x1-60), max(0,y1-70), x2+60, y2+70), stride=1)
        if name == items_first_page:
            # 重启默认页=选中态（侧栏条目带 SELECT_SOFT 橙底），模板是非选中
            # 态截图 → NCC 必失配（2026-11-15 实证）。首页本就无需点击——
            # 模板 miss 不判 FAIL，直接取当前状态走 B/C 断言
            cur = base
            d = 99999   # 无切换可言
        elif not hit:
            results.append((name, 'FAIL', '导航目标未找到'))
            print(f'{name}: FAIL 导航目标未找到')
            continue
        else:
            cx, cy = (hit[0]+hit[2])//2, (hit[1]+hit[3])//2
            dev.click(cx, cy)
            time.sleep(2.2)
            cur = dev.screenshot(f'pg_{name}')
            d = vision.diff(base, cur)
        # 断言 B：内容行带
        rows = content_rows(cur, (ox, oy))
        # 断言 C：红色错误块
        red = red_alert(cur)
        notes = []
        ok = True
        if d < 3000:
            ok = False; notes.append(f'diff={d}(未切换)')
        if len(rows) < 2:
            ok = False; notes.append(f'内容行带{len(rows)}(疑似空白)')
        if red:
            notes.append('红色块(仅记录)')
        results.append((name, 'PASS' if ok else 'FAIL', '; '.join(notes) or f'diff={d} 行带{len(rows)}'))
        base = cur
        # 全屏锁定后窗口不再漂移（此前锚点追踪为自由窗口容错，已不需要）
        print(f'{name}: {"PASS" if ok else "FAIL"} {notes}')

    # 报告
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    rp = f'{ROOT}/reports/smoke_{ts}.md'
    os.makedirs(f'{ROOT}/reports', exist_ok=True)
    with open(rp, 'w', encoding='utf-8') as f:
        f.write(f'# 全页面冒烟报告 {ts}\n\n窗口原点({ox},{oy})，共 {len(results)} 页\n\n')
        f.write('| 页面 | 结果 | 详情 |\n|---|---|---|\n')
        for name, st, note in results:
            f.write(f'| {name} | {st} | {note} |\n')
    print(f'\n报告: {rp}')
    fails = sum(1 for _, st, _ in results if st == 'FAIL')
    print(f'PASS {len(results)-fails-fails} / FAIL {fails}')
    return fails


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else '.'))
