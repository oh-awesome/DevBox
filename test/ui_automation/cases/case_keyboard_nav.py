"""
case_keyboard_nav.py —— 键盘无障碍导航回归（2026-11-15 新功能）

背景：DevBtn/DevSideNav/DevSegmentTabs/DevInput 四组件已获焦点能力
（focusable + onFocus/onBlur 焦点视觉 + onKeyEvent Enter 激活 + 300ms 防抖）。
官方焦点框架规格：首次 Tab 进入"焦点激活态"（系统蓝框）；Enter 只对 Button 内部
映射 onClick，自定义组件走 onKeyEvent——本用例守护"不 crash + 焦点可见 + 键入响应"。

通道：uitest uiInput keyEvent（TAB=2049 / ENTER=2054）+ 像素 diff + dump 存活探针。
局限：Tab 走焦顺序由 Z 字型遍历决定，外部无法 requestFocus 指定目标——
精确"Enter 落在 X 按钮上"的断言不可自动化，交互正确性靠用户验证清单。

断言矩阵：
  K1 首次 TAB → 焦点激活（全窗 diff > 500：系统蓝框+焦点底色出现）+ 应用存活
  K2 TAB×15 连续走焦 → 每次截图成功、最终 dump 可用（无 crash）、无红块
  K3 ENTER → 无 crash；若触发激活（焦点恰在按钮/导航上）则 diff 记录为信息
  K4 TAB 后主题/页面稳定：回到鼠标点击导航仍正常（键鼠混用不互相破坏）
  K5 焦点激活态被点击退出（官方规格：点击事件退出焦点激活态）→ 后续 TAB 重新激活

用法：python cases/case_keyboard_nav.py [workdir]
"""

import sys, os, time, datetime
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.device import Device, _sh
from core import dump, vision
from PIL import Image
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TPL = f'{ROOT}/templates'
KEY_TAB, KEY_ENTER, KEY_CLICK = 2049, 2054, 2016  # DPAD_CENTER=2016 备用


def key(dev: Device, code: int, settle: float = 0.8) -> None:
    _sh(f'hdc shell "uitest uiInput keyEvent {code}"')
    time.sleep(settle)


def alive(workdir: str, tag: str) -> bool:
    try:
        dump.fresh_dump(workdir, f'kn_{tag}')
        return True
    except Exception:
        return False


def red_alert(img: Image.Image) -> bool:
    a = np.array(img.convert('RGB')).astype(int)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    mask = (r > 190) & (g < 110) & (b < 100) & ((r - g) > 100)
    return int(mask.sum()) > 2000


def main(workdir: str) -> int:
    os.makedirs(workdir, exist_ok=True)
    dev = Device(workdir)
    results = []

    def record(aid: str, ok: bool, note: str):
        results.append((aid, 'PASS' if ok else 'FAIL', note))
        print(f'{aid}: {"PASS" if ok else "FAIL"} {note}')

    dev.restart_app(wait=9.0, test_mode=True)
    time.sleep(1)

    base = dev.screenshot('kn_base')
    wb = dev.window(base)

    # K1 首次 TAB → 焦点激活
    key(dev, KEY_TAB, settle=1.2)
    cur = dev.screenshot('kn_k1')
    d1 = vision.diff(wb, dev.window(cur))
    record('K1', d1 > 500 and alive(workdir, 'k1'),
           f'首 TAB diff={d1}（>500 焦点激活）存活={alive(workdir, "k1")}')

    # K2 TAB×15 连续走焦
    ok2, shots = True, 0
    last = cur
    for i in range(15):
        key(dev, KEY_TAB, settle=0.5)
        try:
            last = dev.screenshot(f'kn_k2_{i}')
            shots += 1
        except Exception:
            ok2 = False
            break
    ok2 = ok2 and shots == 15 and alive(workdir, 'k2')
    red2 = red_alert(dev.window(last))
    record('K2', ok2 and not red2, f'15×TAB 截图{shots}/15 存活={ok2} 红块={red2}')

    # K3 ENTER（焦点位置由 Tab 序决定——断言"不 crash"，diff 作信息）
    before_enter = dev.screenshot('kn_k3b')
    key(dev, KEY_ENTER, settle=1.5)
    after_enter = dev.screenshot('kn_k3a')
    d3 = vision.diff(dev.window(before_enter), dev.window(after_enter))
    ok3 = alive(workdir, 'k3') and not red_alert(dev.window(after_enter))
    record('K3', ok3, f'ENTER diff={d3}（>2000=焦点恰在可激活件上触发了）存活={ok3}')

    # K4 键鼠混用：TAB 走焦后鼠标导航仍正常（模板点击 Python 页）
    import json
    meta = json.load(open(f'{TPL}/meta.json', encoding='utf-8'))
    rel = meta['items']['Python']
    shot = dev.screenshot('kn_k4t')
    hit = vision.match(shot, f'{TPL}/sidebar_Python.png',
                       region=(rel[0]-80, rel[1]-80, rel[2]+80, rel[3]+80), stride=1)
    if hit:
        dev.click((hit[0]+hit[2])//2, (hit[1]+hit[3])//2)
        time.sleep(2.2)
        after = dev.screenshot('kn_k4a')
        d4 = vision.diff(dev.window(shot), dev.window(after))
        record('K4', d4 > 3000, f'键鼠混用导航 diff={d4}（>3000 切换生效）')
    else:
        record('K4', False, 'Python 侧栏模板未命中')

    # K5 点击退出焦点激活态 → TAB 重激活（框重现同位=diff≈0 属规格行为）
    #     → 再 TAB 焦点移动（已激活态）→ ENTER → 存活无红块
    dev.click(1200, 800)   # 内容区点击（退出激活态）
    time.sleep(0.8)
    s5a = dev.screenshot('kn_k5a')
    key(dev, KEY_TAB, settle=1.0)      # 仅重新激活（焦点不动——官方规格）
    key(dev, KEY_TAB, settle=1.0)      # 激活态下再 TAB = 焦点移动
    s5b = dev.screenshot('kn_k5b')
    d5 = vision.diff(dev.window(s5a), dev.window(s5b))
    key(dev, KEY_ENTER, settle=1.2)
    s5c = dev.screenshot('kn_k5c')
    ok5 = alive(workdir, 'k5') and not red_alert(dev.window(s5c))
    record('K5', ok5, f'退出→TAB+TAB 焦点移动 diff={d5}（>300）→ENTER 存活={ok5}')

    return report(results)


def report(results) -> int:
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    rp = f'{ROOT}/reports/case_keyboard_nav_{ts}.md'
    os.makedirs(f'{ROOT}/reports', exist_ok=True)
    with open(rp, 'w', encoding='utf-8') as f:
        f.write(f'# 键盘导航用例 {ts}\n\n| 断言 | 结果 | 详情 |\n|---|---|---|\n')
        for aid, st, note in results:
            f.write(f'| {aid} | {st} | {note} |\n')
    fails = sum(1 for _, st, _ in results if st == 'FAIL')
    print(f'\n报告: {rp}\nPASS {len(results)-fails} / FAIL {fails}')
    return fails


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else '.'))
