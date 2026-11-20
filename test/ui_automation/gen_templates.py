"""
gen_templates.py v5 —— 坐标系定案：dump 文本=窗口内坐标，屏幕 = dump + 窗口原点

窗口原点 = 顶层窗口节点（含侧栏文本的那个窗口）bounds 左上角。
模板裁剪/匹配均用换算后屏幕坐标；meta.json 存窗口相对坐标（运行期重算）。
"""

import sys, os, json, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.device import Device
from core import dump, vision

SIDEBAR_ITEMS = ['总览', '通用工具', '环境变量', 'Python', 'Java', 'Rust', 'Node.js',
                 'Lua', 'Perl', 'Go', 'PHP', 'HarmonyBrew', 'Conan']   # Ruby/Bun 商用不带
ROOT = os.path.dirname(os.path.abspath(__file__))
TPL_DIR = f'{ROOT}/templates'


def window_origin(root: dict) -> tuple[int, int]:
    """顶层窗口节点（内容窗口）原点：最大面积顶层节点 bounds 左上角"""
    best, area = (0, 0), 0
    def rec(n, depth):
        nonlocal best, area
        a = n.get('attributes', {})
        if depth == 1 and a.get('bounds'):
            import re
            b = [int(v) for v in re.findall(r'-?\d+', a['bounds'])]
            if len(b) == 4 and (b[2] - b[0]) * (b[3] - b[1]) > area:
                best, area = (b[0], b[1]), (b[2] - b[0]) * (b[3] - b[1])
        for c in n.get('children', []):
            rec(c, depth + 1)
    rec(root, 0)
    return best


def main(workdir: str):
    os.makedirs(TPL_DIR, exist_ok=True)
    dev = Device(workdir)
    dev.restart_app(wait=9.0)          # 窗口摆位/入场动画充分完成
    time.sleep(1)
    root = dump.fresh_dump(workdir, 'gen')
    ox, oy = window_origin(root)
    print(f'窗口原点: ({ox},{oy})')
    shot = dev.screenshot('gen_src')

    meta = {'window_origin': [ox, oy], 'items': {}}
    ok = 0
    for name in SIDEBAR_ITEMS:
        bb = dump.find_bbox(root, name)
        if bb is None:
            print(f'MISS dump未找到: {name}')
            continue
        # 窗口内 → 屏幕
        x1, y1, x2, y2 = bb[0] + ox, bb[1] + oy, bb[2] + ox, bb[3] + oy
        meta['items'][name] = list(bb)   # 窗口内坐标（相对，运行期 + 当轮原点）
        path = f'{TPL_DIR}/sidebar_{name}.png'
        shot.crop((x1, y1, x2, y2)).save(path)
        hit = vision.match(shot, path, region=(x1 - 260, y1 - 160, x2 + 260, y2 + 160), stride=2)
        score = hit[4] if hit else 0
        st = "OK" if hit and score >= 0.78 else "WEAK"
        if st == 'OK':
            ok += 1
        print(f'{st} sidebar_{name}: ncc={score} 屏幕({x1},{y1})-({x2},{y2})')
    json.dump(meta, open(f'{TPL_DIR}/meta.json', 'w'), ensure_ascii=False, indent=1)
    print(f'\n侧边栏模板 {ok}/{len(SIDEBAR_ITEMS)}')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
