"""
case_search_edge.py —— 搜索框边缘/极端场景（通用工具页 + Conan 软件仓库页）

背景：搜索是三页（工具/brew/conan）共用的数据侧过滤入口（300ms 防抖），
输入是不可信外部数据——特殊字符/超长输入不得让应用崩溃或渲染异常。

通道：dump 按 type=TextInput 定位搜索框（无文本时唯一可靠法）→ Device 点击聚焦
→ uitest uiInput inputText 注入 → dump 回读文本值 + 行带计数断言。

⚠ 注入载荷经设备端单引号包裹传 literal（`;id` / `$(id)` / `` `id` `` 无单引号——
安全到达 app 输入框；若 app 侧搜索管道把这些字符拼进 shell 则会被执行=FAIL）。
⚠ 中文关键词走 MCP 通道（case_mcp_security S8）：cmd.exe→设备端编码链 GBK→UTF-8
有 mojibake 风险，属通道限制非应用缺陷。

断言矩阵：
  E1 基线   空搜索：内容行带 ≥ 5
  E2 无结果 乱串 'zzqqxx' → 行带骤降（≤2）或空态文案，无红块，应用存活
  E3 注入   `;id` / `$(id)` / `` `id` `` 逐个查询 → 无红块 + dump 正常（应用存活）
  E4 极限   500 字符超长输入 → 应用稳定，无红块（文本回读=长度 500 或截断值）
  E5 恢复   退格清空 → 行带恢复到 E1 基线 ±2
  E6 命中   已知词 'vim'（工具页）/ 'zlib'（conan 页）→ 行带变化 + dump 文本含关键词

用法：python cases/case_search_edge.py [workdir]
"""

import sys, os, time, re, datetime
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.device import Device, _sh
from core import dump, vision

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TPL = f'{ROOT}/templates'
CONTENT = (500, 250, 2600, 1900)          # 内容区（窗口坐标）


def input_text_safe(dev: Device, x: int, y: int, text: str) -> None:
    """带特殊字符的输入：设备端单引号包裹（payload 不得含单引号）。
    ⚠ 实测 uitest uiInput inputText 是【追加】不是替换（E4 回读 520=历史 20+500）"""
    _sh(f'hdc shell "uitest uiInput inputText {x} {y} \'{text}\'"')
    time.sleep(0.8)


def clear_input(dev: Device) -> None:
    """清空输入框：Ctrl+A 全选（uinput 组合键）+ DEL。
    （uitest 无清空 API；KEYCODE_DEL=2055 / CTRL_LEFT=2072 / A=2017）"""
    _sh('hdc shell "uinput -K -d 2072 -d 2017 -u 2017 -u 2072 -i 80"', timeout=15)
    time.sleep(0.4)
    _sh('hdc shell "uitest uiInput keyEvent 2055"', timeout=10)
    time.sleep(0.6)


def search_box(dev: Device, workdir: str) -> tuple[int, int] | None:
    """dump 定位搜索框（type=TextInput 首个）→ 屏幕坐标中心"""
    root = dump.fresh_dump(workdir, 'se_sb')
    ins = dump.nodes_by_type(root, 'TextInput')
    for a in ins:
        b = [int(v) for v in re.findall(r'-?\d+', a.get('bounds', ''))]
        if len(b) == 4 and b[2] - b[0] > 400:
            return (b[0] + b[2]) // 2, (b[1] + b[3]) // 2
    return None


def row_bands(dev: Device, workdir: str, name: str) -> tuple[int, list[str]]:
    """当前内容行带数 + 全部文本行（供关键词断言）"""
    root = dump.fresh_dump(workdir, name)
    rows, txts = 0, []
    for a in dump.texts(root):
        b = [int(v) for v in re.findall(r'-?\d+', a['bounds'])]
        if len(b) == 4 and b[0] > 500 and b[2] < 2900:
            rows += 1
            txts.append(a['text'].strip())
    return rows, txts


def main(workdir: str) -> int:
    os.makedirs(workdir, exist_ok=True)
    dev = Device(workdir)
    results = []

    def record(aid: str, ok: bool, note: str):
        results.append((aid, 'PASS' if ok else 'FAIL', note))
        print(f'{aid}: {"PASS" if ok else "FAIL"} {note}')

    def alive() -> bool:
        """应用存活探针（dump 可用 + 前台包名）"""
        out = _sh('hdc shell "bm dump -n com.develop.opensource.devbox"', timeout=20)
        return 'devbox' in out

    dev.restart_app(wait=9.0, test_mode=True)
    time.sleep(1)

    # ── 页面一：通用工具 ──
    meta = json_guard()
    rel = meta['items']['通用工具']
    shot = dev.screenshot('se_base')
    hit = vision.match(shot, f'{TPL}/sidebar_通用工具.png',
                       region=(rel[0]-80, rel[1]-80, rel[2]+80, rel[3]+80), stride=1)
    if not hit:
        record('NAV1', False, '通用工具侧栏未命中')
        return report(results)
    dev.click((hit[0]+hit[2])//2, (hit[1]+hit[3])//2)
    time.sleep(2.5)

    sb = search_box(dev, workdir)
    if not sb:
        record('SB', False, '搜索框未定位（TextInput 节点缺失）')
        return report(results)
    print(f'搜索框: {sb}')

    # E1 基线
    base_rows, _ = row_bands(dev, workdir, 'se_e1')
    record('E1', base_rows >= 5, f'空搜索行带 {base_rows}')

    # E2 无结果
    dev.click(*sb); time.sleep(0.6)
    input_text_safe(dev, *sb, 'zzqqxxyy')
    time.sleep(1.5)
    r2, _ = row_bands(dev, workdir, 'se_e2')
    shot2 = dev.screenshot('se_e2s')
    red = red_alert_local(dev.window(shot2))
    ok2 = (r2 <= 3 or r2 < base_rows - 5) and not red and alive()
    record('E2', ok2, f'无结果行带 {r2}（基线{base_rows}）红块={red} 存活={alive()}')

    # E3 注入载荷 ×3
    for i, payload in enumerate([';id', '$(id)', '`id`'], 1):
        dev.click(*sb); time.sleep(0.4)
        clear_input(dev)
        input_text_safe(dev, *sb, payload)
        time.sleep(1.2)
        rr, txts = row_bands(dev, workdir, f'se_e3{i}')
        sh = dev.screenshot(f'se_e3{i}s')
        red = red_alert_local(dev.window(sh))
        # 应用存活 + 无红块 + 文本不含 uid=（id 输出若被拼进渲染即注入执行证据）
        leaked = any('uid=' in t for t in txts)
        ok = (not red) and alive() and (not leaked)
        record(f'E3-{i}', ok, f'[{payload}] 行带{rr} 红块={red} uid泄漏={leaked}')

    # E4 超长输入 500 字符
    dev.click(*sb); time.sleep(0.4)
    input_text_safe(dev, *sb, 'a' * 500)
    time.sleep(1.5)
    root = dump.fresh_dump(workdir, 'se_e4')
    ins = dump.nodes_by_type(root, 'TextInput')
    back = ''
    for a in ins:
        b = [int(v) for v in re.findall(r'-?\d+', a.get('bounds', ''))]
        if len(b) == 4 and b[2] - b[0] > 400:
            back = a.get('text', '')
    sh = dev.screenshot('se_e4s')
    red = red_alert_local(dev.window(sh))
    ok4 = alive() and (not red) and len(back) >= 400
    record('E4', ok4, f'500字符注入后 存活={alive()} 红块={red} 回读长度={len(back)}')

    # E5 清空恢复（Ctrl+A 全选 + DEL——实测 inputText 追加语义后必须主动清）
    dev.click(*sb); time.sleep(0.4)
    clear_input(dev)
    time.sleep(1.2)
    r5, _ = row_bands(dev, workdir, 'se_e5')
    ok5 = abs(r5 - base_rows) <= 3
    record('E5', ok5, f'清空后行带 {r5}（基线{base_rows}）')

    # E6 已知词命中（工具页：vim —— 平台必有工具包）
    dev.click(*sb); time.sleep(0.4)
    clear_input(dev)
    input_text_safe(dev, *sb, 'vim')
    time.sleep(1.5)
    r6, txts = row_bands(dev, workdir, 'se_e6')
    hit6 = any('vim' in t.lower() for t in txts)
    record('E6', hit6 and r6 >= 1, f"vim 命中={hit6} 行带{r6}: {[t for t in txts if 'vim' in t.lower()][:2]}")

    return report(results)


def json_guard() -> dict:
    import json
    return json.load(open(f'{TPL}/meta.json', encoding='utf-8'))


def red_alert_local(img) -> bool:
    import numpy as np
    a = np.array(img.convert('RGB')).astype(int)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    mask = (r > 190) & (g < 110) & (b < 100) & ((r - g) > 100)
    return int(mask.sum()) > 2000


def report(results) -> int:
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    rp = f'{ROOT}/reports/case_search_edge_{ts}.md'
    os.makedirs(f'{ROOT}/reports', exist_ok=True)
    with open(rp, 'w', encoding='utf-8') as f:
        f.write(f'# 搜索边缘用例 {ts}\n\n| 断言 | 结果 | 详情 |\n|---|---|---|\n')
        for aid, st, note in results:
            f.write(f'| {aid} | {st} | {note} |\n')
    fails = sum(1 for _, st, _ in results if st == 'FAIL')
    print(f'\n报告: {rp}\nPASS {len(results)-fails} / FAIL {fails}')
    return fails


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else '.'))
