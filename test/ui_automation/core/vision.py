"""
vision.py —— 像素断言原语（PIL+numpy，零第三方视觉依赖）

能力：
- diff(a, b)              两图变化像素数（点击是否生效的硬判据）
- find_buttons(img)       DevBtn primary 蓝色按钮定位（RGB 窗口法，真机标定）
- text_rows(img, region)  边缘密度行带（文本行存在性粗断言）
- match(img, tpl, th)     归一化互相关（NCC）模板匹配——把"文字/徽章/图标"截成
                          小模板后即可代码化查找（替代大模型看图）
- pixel(img, x, y)        单点颜色（进度条/主题色断言）

模板约定：templates/*.png 均为 DevBox 窗口坐标系（先 device.window() 裁剪再匹配）。
"""

import numpy as np
from PIL import Image

# DevBtn primary 蓝系（深/浅主题两种取值，真机取色）
BLUE_LO = (90, 130, 200)
BLUE_HI = (130, 200, 255)


def to_gray(img: Image.Image) -> np.ndarray:
    return np.array(img.convert('L')).astype(np.float64)


def diff(a: Image.Image, b: Image.Image, region: tuple | None = None) -> int:
    """两图变化像素数（|Δ|>30 灰度阈值）。region=(x1,y1,x2,y2) 可选局部"""
    ga, gb = to_gray(a), to_gray(b)
    if region:
        x1, y1, x2, y2 = region
        ga, gb = ga[y1:y2, x1:x2], gb[y1:y2, x1:x2]
    if ga.shape != gb.shape:
        return int(min(ga.size, gb.size))
    return int((np.abs(ga - gb) > 30).sum())


def find_buttons(img: Image.Image, region: tuple | None = None,
                 min_w: int = 40, min_h: int = 20) -> list[tuple[int, int, int, int]]:
    """扫描蓝色 DevBtn（返回窗口坐标 bbox 列表，按 y 序）。
    原理：RGB 三通道窗口判定 + 行聚类成块 + 宽高校验过滤文字着色。"""
    a = np.array(img.convert('RGB')).astype(int)
    if region:
        x1, y1, x2, y2 = region
        a = a[y1:y2, x1:x2]
        ox, oy = x1, y1
    else:
        ox, oy = 0, 0
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    mask = (b >= BLUE_LO[2]) & (b <= BLUE_HI[2] or (b >= BLUE_LO[2])) & \
           (g >= BLUE_LO[1]) & (g <= BLUE_HI[1]) & \
           (r >= BLUE_LO[0] - 60) & (r <= BLUE_HI[0]) & ((b - r) > 60)
    rows = {}
    for y in range(mask.shape[0]):
        cnt = int(mask[y].sum())
        if cnt >= 5:
            rows[y] = cnt
    # 行带聚类
    bands = []
    for y in sorted(rows):
        if bands and y - bands[-1][1] <= 5:
            bands[-1][1] = y
        else:
            bands.append([y, y])
    out = []
    for y0, y1 in bands:
        h = y1 - y0
        if h < min_h:
            continue
        # 该行带的 x 并集
        xs = []
        for y in range(y0, y1 + 1, 2):
            xs += np.where(mask[y])[0].tolist()
        if not xs:
            continue
        x0, x1 = min(xs), max(xs)
        if x1 - x0 < min_w:
            continue
        out.append((ox + x0, oy + y0, ox + x1, oy + y1))
    return out


def text_rows(img: Image.Image, region: tuple | None = None,
              edge_th: int = 40, min_edges: int = 20) -> list[tuple[int, int]]:
    """边缘密度行带（文本行探测）：返回 (y1,y2) 列表。
    用途：'该区域是否有文字行'的粗断言（非 OCR——精确内容用模板匹配）。"""
    g = to_gray(img)
    if region:
        x1, y1, x2, y2 = region
        g = g[y1:y2, x1:x2]
    oy = region[1] if region else 0
    rows = {}
    for y in range(g.shape[0]):
        edges = np.abs(np.diff(g[y].astype(np.int64)))
        n = int((edges > edge_th).sum())
        if n >= min_edges:
            rows[y] = n
    bands = []
    for y in sorted(rows):
        if bands and y - bands[-1][1] <= 10:
            bands[-1][1] = y
        else:
            bands.append([y, y])
    return [(b[0] + oy, b[1] + oy) for b in bands]   # 绝对坐标（region 偏移加回）


def match(img: Image.Image, tpl_path: str, region: tuple | None = None,
          stride: int = 1, th: float = 0.78) -> tuple[int, int, int, int, float] | None:
    """NCC 模板匹配（降采样 + 步进滑窗；命中返回窗口坐标 bbox+相似度）。
    文字/徽章/图标模板均走此入口——不依赖 OCR/大模型。"""
    tpl = Image.open(tpl_path).convert('L')
    # 降采样 2 倍（4 倍会把 32px 高文本模板压到 8px——NCC 失效，真机实证）
    scale = 2
    ig = to_gray(img.resize((img.width // scale, img.height // scale), Image.BILINEAR))
    tg = to_gray(tpl.resize((tpl.width // scale, tpl.height // scale), Image.BILINEAR))
    if region:
        # clamp 到图内（负坐标会被 Python 切片当尾部索引——真机实证导致匹配错乱）
        # clamp：先换尺度再截界（先 min 后 //scale 会把底部错截——y>1000 的条目全灭实证）
        x1 = max(0, region[0]) // scale
        y1 = max(0, region[1]) // scale
        x2 = min(ig.shape[1], region[2] // scale)
        y2 = min(ig.shape[0], region[3] // scale)
        ig = ig[y1:y2, x1:x2]
    else:
        x1 = y1 = 0
    t_mean = tg.mean()
    t_norm = np.sqrt(((tg - t_mean) ** 2).sum())
    if t_norm == 0:
        return None
    best = (0.0, -1, -1)
    th_, tw_ = tg.shape
    for y in range(0, ig.shape[0] - th_ + 1, stride):
        for x in range(0, ig.shape[1] - tw_ + 1, stride):
            win = ig[y:y + th_, x:x + tw_]
            w_mean = win.mean()
            num = ((win - w_mean) * (tg - t_mean)).sum()
            den = np.sqrt(((win - w_mean) ** 2).sum()) * t_norm
            if den == 0:
                continue
            ncc = num / den
            if ncc > best[0]:
                best = (ncc, x, y)
    if best[0] < th or best[1] < 0:
        return None
    bx = (best[1] + x1) * scale
    by = (best[2] + y1) * scale
    return (bx, by, bx + tpl.width, by + tpl.height, round(best[0], 3))


def pixel(img: Image.Image, x: int, y: int) -> tuple[int, int, int]:
    return img.getpixel((x, y))[:3]


def has_blue_progress(img: Image.Image, region: tuple | None = None) -> bool:
    """区域内是否存在蓝色进度条（4px 高蓝带）"""
    btns = find_buttons(img, region, min_w=60, min_h=2)
    return any(y1 == y2 - 2 or (y2 - y1) <= 8 for x1, y1, x2, y2 in btns)
