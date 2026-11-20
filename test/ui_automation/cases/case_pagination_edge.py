"""
case_pagination_edge.py —— DevPagination 边界（首末页禁用态/跳页/往返）

背景：brew 仓库 ~4700 包动态分页（PageCalc 按容器高度算每页条数），
DevPagination 自绘 Gitee 风格（‹ / 页码带省略号 / ›），越界点击 onClick 内置 if 拦截。
本用例守边界：首页‹禁用、末页›禁用、大跳页（点末页页码）与回跳。

通道：dump 文本定位（页码是 Text 节点）+ 像素采样当前页高亮（当前页 bg=TEXT_PRIMARY
深色模式近白 L>200，非当前页透明底 L<100）+ 内容区 diff。

前置：HarmonyBrew 本体已安装（未装则'软件仓库' tab 不存在 → SKIP）。

断言矩阵：
  P1 软件仓库 tab 就位：分页条存在（‹ › 页码 1），当前页=1（高亮像素断言）
  P2 点 › → 当前页=2（高亮迁移）+ 内容区 diff>2000（列表翻页）
  P3 页 2 点 ‹ → 当前页=1
  P4 点末页页码（页码行最大数字）→ 该页高亮 + 内容区大 diff（远跳）
  P5 末页点 › → 无变化（diff<600，禁用态拦截）——越界回归闸
  P6 点页码 1 → 回首页，首行包名与 P1 一致（往返无损）

用法：python cases/case_pagination_edge.py [workdir]
"""

import sys, os, time, re, datetime, json
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.device import Device, _sh
from core import dump, vision
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TPL = f'{ROOT}/templates'
WIN_OFF = (0, 0)                  # test_mode 全屏：dump 坐标=屏幕坐标=窗口坐标
                                  # （旧自由窗口 (76,76) 偏移已废弃——2026-11-15 实证）
PAGE_ROW = (500, 1950, 2900, 2070)  # 分页条区域（屏幕坐标——实测贴底 y1989-2050）
TAB_ROW = (500, 200, 3120, 400)     # 页签行区域（标题 159-208 之下、内容 355+ 之上）
CONTENT = (500, 300, 2900, 1200)    # 列表内容区（屏幕坐标）


def to_win(x: int, y: int) -> tuple[int, int]:
    return x - WIN_OFF[0], y - WIN_OFF[1]


def page_numbers(root: dict) -> list[dict]:
    """分页条区域内的数字页码节点（含 bounds/screen 坐标）"""
    out = []
    for a in dump.texts(root):
        t = a['text'].strip()
        if not t.isdigit():
            continue
        b = [int(v) for v in re.findall(r'-?\d+', a['bounds'])]
        if len(b) == 4 and (b[0] >= PAGE_ROW[0] and b[1] >= PAGE_ROW[1]
                            and b[3] <= PAGE_ROW[3] + 60 and b[2] <= PAGE_ROW[2]):
            out.append({'n': int(t), 'bbox': b})
    return out


def arrow_pos(root: dict, ch: str) -> tuple[int, int] | None:
    p = dump.find(root, ch, in_region=PAGE_ROW)
    return p


def highlighted(num_nodes: list[dict], shot: Image.Image) -> int | None:
    """当前高亮页码=离群者（主题无关）：当前页 bg=TEXT_PRIMARY（深色主题白底/
    浅色主题黑底），非当前页透明底=面板色——取与中位亮度偏差最大且 >40 的节点"""
    if not num_nodes:
        return None
    lums = []
    for nd in num_nodes:
        b = nd['bbox']
        # 采样节点左右边缘（padding 区=纯底色）；中心会打到数字笔画——
        # 当前页白字深底/非当前黑字浅底两种节点都混有暗亮像素，中心采样必失效
        cy = (b[1] + b[3]) // 2
        pts = [to_win(b[0] + 2, cy), to_win(b[2] - 2, cy)]
        lv = []
        try:
            for px, py in pts:
                r, g, bl = shot.getpixel((px, py))[:3]
                lv.append(0.299 * r + 0.587 * g + 0.114 * bl)
            lums.append((sum(lv) / len(lv), nd['n']))
        except Exception:
            continue
    if not lums:
        return None
    vals = sorted(l[0] for l in lums)
    med = vals[len(vals) // 2]
    best, best_d = None, 0
    for lv, n in lums:
        d = abs(lv - med)
        if d > best_d:
            best, best_d = n, d
    return best if best_d > 40 else None


def content_diff(dev: Device, before: Image.Image, tag: str) -> int:
    """内容区（屏幕坐标→窗口裁剪）diff"""
    cur = dev.screenshot(tag)
    a = before.crop(CONTENT)
    b = cur.crop(CONTENT)
    return vision.diff(a, b)


def first_row_name(root: dict) -> str:
    """列表区最上一行的最左文本（=首行包名）"""
    cands = []
    for a in dump.texts(root):
        b = [int(v) for v in re.findall(r'-?\d+', a['bounds'])]
        if len(b) == 4 and 500 < b[0] < 2900 and 300 < b[1] < 700 and len(a['text'].strip()) > 1:
            cands.append((b[1], b[0], a['text'].strip()))
    cands.sort()
    return cands[0][2] if cands else '?'


def main(workdir: str) -> int:
    os.makedirs(workdir, exist_ok=True)
    dev = Device(workdir)
    results = []

    def record(aid: str, ok: bool, note: str):
        results.append((aid, 'PASS' if ok else 'FAIL', note))
        print(f'{aid}: {"PASS" if ok else "FAIL"} {note}')

    # 前置预检（MCP 真值）：brew 本体未装 → 软件仓库 tab 不存在 → SKIP（非回归）
    from core.mcp import McpClient
    mcp = McpClient()
    if mcp.connect(retries=3):
        try:
            r = mcp.result_text('brew_list')
            if 'not installed' in r.lower():
                record('PRE', False, 'SKIP：HarmonyBrew 本体未装（先跑 L2 brew 安装链路或手动装回）')
                return report(results)
        except Exception:
            pass   # MCP 不可用不阻断——继续用 UI 探测

    dev.restart_app(wait=9.0, test_mode=True)
    time.sleep(1)

    # 导航 HarmonyBrew
    meta = json.load(open(f'{TPL}/meta.json', encoding='utf-8'))
    root0 = dump.fresh_dump(workdir, 'pe_nav')
    p_nav = dump.find(root0, 'HarmonyBrew', in_region=(0, 500, 470, 2100))
    if not p_nav:
        record('NAV', False, 'HarmonyBrew 侧栏未定位')
        return report(results)
    dev.click(*p_nav)
    time.sleep(3.5)

    root = dump.fresh_dump(workdir, 'pe_p0')
    tab = dump.find(root, '软件仓库', in_region=TAB_ROW)
    if not tab:
        record('TAB', False, '软件仓库 tab 不存在（brew 未装？）——SKIP 需先装本体')
        return report(results)
    dev.click(*tab)
    # 全量目录加载轮询（实测 ~3s 就绪，容错 30s）
    nums = []
    for i in range(10):
        time.sleep(3)
        root = dump.fresh_dump(workdir, f'pe_repo{i}')
        nums = page_numbers(root)
        if nums:
            break

    root = dump.fresh_dump(workdir, 'pe_p1')
    nums = page_numbers(root) or nums
    prev_a, next_a = arrow_pos(root, '‹'), arrow_pos(root, '›')
    if not nums or not prev_a or not next_a:
        record('P1', False, f'分页条不完整：页码{len(nums)} ‹{bool(prev_a)} ›{bool(next_a)}')
        return report(results)
    shot = dev.screenshot('pe_s1')
    cur_page = highlighted(nums, shot)
    name_first = first_row_name(root)
    ok1 = cur_page == 1
    record('P1', ok1, f'页码数{len(nums)} 当前高亮={cur_page}（=1）首行={name_first}')

    # P2 › 下一页
    before = dev.screenshot('pe_b2')
    dev.click(*next_a); time.sleep(2.0)
    root = dump.fresh_dump(workdir, 'pe_p2')
    nums2 = page_numbers(root)
    shot2 = dev.screenshot('pe_s2')
    cur2 = highlighted(nums2, shot2)
    d2 = content_diff(dev, before, 'pe_d2')
    record('P2', cur2 == 2 and d2 > 2000, f'› 后当前页={cur2}（=2）内容diff={d2}')

    # P3 ‹ 回首页
    before = dev.screenshot('pe_b3')
    root = dump.fresh_dump(workdir, 'pe_p3')
    prev_a = arrow_pos(root, '‹') or prev_a
    dev.click(*prev_a); time.sleep(2.0)
    root = dump.fresh_dump(workdir, 'pe_p3b')
    nums3 = page_numbers(root)
    shot3 = dev.screenshot('pe_s3')
    cur3 = highlighted(nums3, shot3)
    record('P3', cur3 == 1, f'‹ 后当前页={cur3}（=1）')

    # P4 点末页页码（页码行最大数字）
    last_n = max(nd['n'] for nd in nums3) if nums3 else None
    if last_n is None or last_n < 2:
        record('P4', False, f'末页页码异常：{last_n}')
    else:
        tgt = next((nd for nd in nums3 if nd['n'] == last_n), None)
        if tgt:
            b = tgt['bbox']
            before = dev.screenshot('pe_b4')
            dev.click((b[0]+b[2])//2, (b[1]+b[3])//2); time.sleep(3.0)
            root4 = dump.fresh_dump(workdir, 'pe_p4')
            nums4 = page_numbers(root4)
            shot4 = dev.screenshot('pe_s4')
            cur4 = highlighted(nums4, shot4)
            d4 = content_diff(dev, before, 'pe_d4')
            record('P4', cur4 == last_n and d4 > 2000, f'跳末页 {last_n} 当前={cur4} diff={d4}')
        else:
            record('P4', False, f'末页页码 {last_n} 节点未找到')

    # P5 末页 › 越界（禁用拦截：无变化）
    root5 = dump.fresh_dump(workdir, 'pe_p5')
    next_a5 = arrow_pos(root5, '›')
    if next_a5:
        before = dev.screenshot('pe_b5')
        dev.click(*next_a5); time.sleep(1.6)
        d5 = content_diff(dev, before, 'pe_d5')
        record('P5', d5 < 600, f'末页 › 越界点击 diff={d5}（<600 禁用态拦截）')
    else:
        record('P5', False, '末页 › 未定位')

    # P6 回首页，首行一致
    root6 = dump.fresh_dump(workdir, 'pe_p6')
    one = next((nd for nd in page_numbers(root6) if nd['n'] == 1), None)
    if one:
        b = one['bbox']
        dev.click((b[0]+b[2])//2, (b[1]+b[3])//2); time.sleep(2.5)
        root6b = dump.fresh_dump(workdir, 'pe_p6b')
        name_back = first_row_name(root6b)
        record('P6', name_back == name_first, f'回首页首行={name_back}（初始={name_first}）')
    else:
        record('P6', False, '页码 1 未找到')

    return report(results)


def report(results) -> int:
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    rp = f'{ROOT}/reports/case_pagination_edge_{ts}.md'
    os.makedirs(f'{ROOT}/reports', exist_ok=True)
    with open(rp, 'w', encoding='utf-8') as f:
        f.write(f'# 分页边界用例 {ts}\n\n| 断言 | 结果 | 详情 |\n|---|---|---|\n')
        for aid, st, note in results:
            f.write(f'| {aid} | {st} | {note} |\n')
    fails = sum(1 for _, st, _ in results if st == 'FAIL')
    print(f'\n报告: {rp}\nPASS {len(results)-fails} / FAIL {fails}')
    return fails


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else '.'))
