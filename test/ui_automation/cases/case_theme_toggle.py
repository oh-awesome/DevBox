"""
case_theme_toggle.py —— 主题切换（深↔浅）与浅色模式全页扫

背景：DevTheme 双模式 token（深 BG #1E1E1E / 浅 BG #F4F4F5），顶栏 DevThemeSwitch
切换；浅色模式此前是低频路径（默认深色）——本用例守浅色渲染不破（红块/空白/失衡）。

通道：dump 定位顶栏 '⟳' 刷新按钮 → 主题开关在其右侧（顶栏右端，无文本纯图标）
→ 点击切换 → 采样窗口背景像素亮度翻转断言 + 全页浅色扫（行带/红块）。

断言矩阵：
  T1 切浅色：背景采样亮度翻转（暗→亮，L>128）+ 全窗大 diff
  T2 切回深色：像素复原（L<60）——往返无损
  T3 浅色下遍历 4 页（总览/通用工具/HarmonyBrew/Conan）→ 无红块 + 行带 ≥ 3
  T4 压力：快速连切 4 次 → 最终态=初始态（偶数次往返）且应用存活
  T5 切换后 dump 正常（页面树完整——无渲染半途态）

用法：python cases/case_theme_toggle.py [workdir]
"""

import sys, os, time, re, datetime, json
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.device import Device, _sh
from core import dump, vision
from PIL import Image
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TPL = f'{ROOT}/templates'


def lum(img: Image.Image, x: int, y: int) -> float:
    """窗口坐标采样亮度"""
    r, g, b = img.getpixel((x, y))[:3]
    return 0.299 * r + 0.587 * g + 0.114 * b


def bg_probe(dev: Device) -> tuple[float, Image.Image]:
    """背景探针：窗口左下区域采样（避卡片——卡片随主题也翻转但取角更稳）"""
    shot = dev.screenshot('tt_probe')
    w = dev.window(shot)
    # 多点采样取中位（抗图标/卡片干扰）：左上/右下/中部空白带
    vals = [lum(w, 60, 60), lum(w, 80, 1200), lum(w, 1900, 1380)]
    vals.sort()
    return vals[1], shot


def theme_switch_pos(dev: Device, workdir: str) -> tuple[int, int] | None:
    """顶栏 '⟳' 刷新按钮中心 + 64px = 主题开关 46×盒正中心。
    （实证：⟳右缘+space10 起为 46px 开关，中心在 ⟳中心+64；左缘 +46 点击不命中）"""
    root = dump.fresh_dump(workdir, 'tt_top')
    p = dump.find(root, '⟳', in_region=(1400, 0, 3120, 400))
    if p:
        return p[0] + 64, p[1]
    return None


def red_alert(img: Image.Image) -> bool:
    a = np.array(img.convert('RGB')).astype(int)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    mask = (r > 190) & (g < 110) & (b < 100) & ((r - g) > 100)
    return int(mask.sum()) > 2000


def content_rows(shot: Image.Image) -> int:
    return len(vision.text_rows(shot, region=(500, 250, 2600, 1900), min_edges=15))


def main(workdir: str) -> int:
    os.makedirs(workdir, exist_ok=True)
    dev = Device(workdir)
    results = []

    def record(aid: str, ok: bool, note: str):
        results.append((aid, 'PASS' if ok else 'FAIL', note))
        print(f'{aid}: {"PASS" if ok else "FAIL"} {note}')

    dev.restart_app(wait=9.0, test_mode=True)
    time.sleep(1)

    sw = theme_switch_pos(dev, workdir)
    if not sw:
        record('SW', False, '主题开关未定位（顶栏 ⟳ 锚缺失）')
        return report(results)
    print(f'主题开关: {sw}')

    L0, base = bg_probe(dev)
    start_light = L0 > 128
    print(f'起始模式: {"浅色" if start_light else "深色"} L={L0:.0f}')

    # T1 翻转（方向自适应：起始可能是深或浅——用户停留态持久化）
    dev.click(*sw); time.sleep(1.5)
    L1, cur = bg_probe(dev)
    d1 = vision.diff(dev.window(base), dev.window(cur))
    flipped = (L1 > 128) != start_light
    record('T1', flipped and d1 > 20000, f'L={L0:.0f}→{L1:.0f}（翻转={flipped}）diff={d1}')

    # T2 切回起始
    dev.click(*sw); time.sleep(1.5)
    L2, cur2 = bg_probe(dev)
    d2 = vision.diff(dev.window(cur), dev.window(cur2))
    ok2 = abs(L2 - L0) < 40
    record('T2', ok2, f'往返 L={L0:.0f}→{L2:.0f}（±40 内复原）diff={d2}')

    # T3 非起始模式全页扫（dump 文本定位导航——主题无关；模板对反色失配不可用）
    dev.click(*sw); time.sleep(1.5)
    pages = ['总览', '通用工具', 'HarmonyBrew', 'Conan']
    bad = []
    for name in pages:
        root = dump.fresh_dump(workdir, f'tt_nav_{name}')
        p = dump.find(root, name, in_region=(0, 500, 470, 2100))
        if not p:
            bad.append(f'{name}:侧栏未定位')
            continue
        dev.click(*p)
        time.sleep(2.2)
        s = dev.screenshot(f'tt_pg_{name}')
        rows = content_rows(dev.window(s))
        red = red_alert(dev.window(s))
        if rows < 3 or red:
            bad.append(f'{name}:行带{rows}/红块{red}')
    record('T3', not bad, f'非起始模式 4 页扫 {"全部健康" if not bad else "; ".join(bad)}')

    # T4 压力连切 4 次（偶数次=回到 T3 扫描时模式）
    for i in range(4):
        dev.click(*sw); time.sleep(0.7)
    L_final, _ = bg_probe(dev)
    ok4 = ((L_final > 128) != start_light)
    record('T4', ok4, f'4 连切后 L={L_final:.0f}（偶数次回到非起始模式={ok4}）')

    # T5 切换后 dump 树完整
    ok5 = True
    try:
        root = dump.fresh_dump(workdir, 'tt_final')
        n = len(dump.texts(root))
        ok5 = n > 10
        note5 = f'dump 文本节点 {n} 个'
    except Exception as e:
        ok5 = False
        note5 = f'dump 失败: {str(e)[:40]}'
    record('T5', ok5, note5)

    # 收尾：恢复起始模式（T4 后=非起始态，切一次即回）
    dev.click(*sw); time.sleep(1.0)

    return report(results)


def report(results) -> int:
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    rp = f'{ROOT}/reports/case_theme_toggle_{ts}.md'
    os.makedirs(f'{ROOT}/reports', exist_ok=True)
    with open(rp, 'w', encoding='utf-8') as f:
        f.write(f'# 主题切换用例 {ts}\n\n| 断言 | 结果 | 详情 |\n|---|---|---|\n')
        for aid, st, note in results:
            f.write(f'| {aid} | {st} | {note} |\n')
    fails = sum(1 for _, st, _ in results if st == 'FAIL')
    print(f'\n报告: {rp}\nPASS {len(results)-fails} / FAIL {fails}')
    return fails


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else '.'))
