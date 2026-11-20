"""
dump.py —— uitest dumpLayout 首帧读取（仅应用重启后可信；换页后卡幽灵帧——勿用于运行期）

用途：模板生成（一次性精确坐标）；运行期断言一律走 vision 模板匹配。
"""

import json
import re
import subprocess
import time


def _sh(cmd: str, timeout: float = 60) -> str:
    r = subprocess.run(cmd, shell=True, capture_output=True, timeout=timeout)
    return r.stdout.decode('utf-8', errors='replace')


def fresh_dump(workdir: str, name: str = 'dump') -> dict:
    """重启后首次 dump（可信窗口）→ 返回解析后的根节点"""
    _sh(f'hdc shell "uitest dumpLayout -p /data/local/tmp/{name}.json"')
    _sh(f'hdc file recv /data/local/tmp/{name}.json {workdir}/{name}.json')
    with open(f'{workdir}/{name}.json', 'rb') as f:
        raw = f.read().decode('utf-8', errors='replace')
    try:
        return json.loads(raw)
    except Exception:
        s = raw[raw.index('{'): raw.rindex('}') + 1]
        return json.loads(s)


def walk(node: dict, acc: list) -> None:
    a = node.get('attributes', {})
    if a.get('text', '') != '':
        acc.append(a)
    for c in node.get('children', []):
        walk(c, acc)


def texts(root: dict) -> list[dict]:
    acc: list[dict] = []
    walk(root, acc)
    return acc


def nodes_by_type(root: dict, type_substr: str) -> list[dict]:
    """按 type 子串收集节点（如 'TextInput' —— 搜索框无文本时唯一可靠定位法）"""
    out: list[dict] = []

    def _walk(n):
        a = n.get('attributes', {})
        if type_substr in a.get('type', ''):
            out.append(a)
        for c in n.get('children', []):
            _walk(c)

    _walk(root)
    return out


def find(root: dict, txt: str, nth: int = 0, in_region: tuple | None = None) -> tuple[int, int] | None:
    """第 nth 个匹配文本的屏幕中心坐标；in_region=(x1,y1,x2,y2) 限定命中范围
    （如侧边栏条目须限定 x<400——总览内容区有同名卡片会抢先命中）"""
    hits = [a for a in texts(root) if txt in a.get('text', '')]
    picked = -1
    for a in hits:
        b = re.findall(r'-?\d+', a['bounds'])
        if len(b) != 4:
            continue
        cx, cy = (int(b[0]) + int(b[2])) // 2, (int(b[1]) + int(b[3])) // 2
        if in_region and not (in_region[0] <= cx <= in_region[2] and in_region[1] <= cy <= in_region[3]):
            continue
        picked += 1
        if picked == nth:
            return cx, cy
    return None


def find_bbox(root: dict, txt: str, nth: int = 0) -> tuple[int, int, int, int] | None:
    """第 nth 个匹配文本的 bounds（屏幕坐标 x1,y1,x2,y2）——模板裁剪用全框"""
    hits = [a for a in texts(root) if txt in a.get('text', '')]
    picked = -1
    for a in hits:
        b = re.findall(r'-?\d+', a['bounds'])
        if len(b) != 4:
            continue
        picked += 1
        if picked == nth:
            return int(b[0]), int(b[1]), int(b[2]), int(b[3])
    return None
