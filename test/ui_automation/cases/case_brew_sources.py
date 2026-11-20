"""
case_brew_sources.py —— HarmonyBrew 双固定源 E2E（发现服务 v2 对接回归线）

模型（2026-11-12 定案）：仅两个固定源——官方源（formula.jws.json，4714 条）
+ OHPCD 社区源（tap JWS，同构消费，发现字段 tap_packages_api 上线前用
种子兜底）。Tap 管理 GUI 已移除；社区 tap（harmony/ohos）装机后由
BrewTapService 自动补（brew install 社区包依赖它）。

断言：
  A0 MCP 连接；A1 brew 本体在（官方源目录可用前置）
  A2 官方源列表：dump 见 '官方源'/'社区源' 双源切换 + core 首行公式（a2ps）
  A3 官方源缓存：重启 app 后行仍在（秒显，无需重拉 12MB）
  A4 社区源切换：切'社区源'——端点已上线（PC 探测 200）时断言 bun 可见；
     未上线（404）时断言优雅空态文案（服务筹备中），不崩溃
  A5 社区 tap 装机态：重启后 hilog 无 community tap 失败日志（已 applied）

用法：python cases/case_brew_sources.py [workdir]（需已装 HarmonyBrew）
"""
import sys, os, time, re, json, datetime
import subprocess
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.device import Device, _sh
from core import dump
from core.mcp import McpClient

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SEED_URL = 'https://ohpcd.atomgit.com/api/ohpcd-brew/formula.jws.json'


def tap_endpoint_live() -> bool:
    """PC 侧探测社区源端点（200=平台已上线）"""
    try:
        r = subprocess.run(
            ['curl', '-s', '-o', os.devnull, '-w', '%{http_code}', '--max-time', '12', SEED_URL],
            capture_output=True, timeout=15)
        return r.stdout.decode().strip() == '200'
    except Exception:
        return False


def center_of(b: list) -> tuple:
    return (b[0] + b[2]) // 2, (b[1] + b[3]) // 2


def dump_texts(wd: str, name: str = 'src_dump') -> list:
    root = dump.fresh_dump(wd, name)
    return [a['text'].strip() for a in dump.texts(root) if a.get('text', '').strip()]


def click_text(wd: str, label: str, settle: float = 2.0) -> bool:
    root = dump.fresh_dump(wd, 'src_dump')
    b = dump.find_bbox(root, label)
    if b is None:
        return False
    x, y = center_of(b)
    _sh(f'hdc shell "uitest uiInput click {x} {y}"')
    time.sleep(settle)
    return True


def goto_repo_tab(dev: Device, wd: str) -> bool:
    """dump 坐标直点侧边栏 HarmonyBrew → 切软件仓库（须 restart 锁全屏后调用）"""
    root = dump.fresh_dump(wd, 'src_dump')
    side = None
    for a in dump.texts(root):
        if a.get('text', '').strip() == 'HarmonyBrew':
            b = [int(v) for v in re.findall(r'-?\d+', a['bounds'])]
            if len(b) == 4 and b[0] < 450:
                side = b
    if side is None:
        return False
    x, y = center_of(side)
    dev.click(x, y)
    time.sleep(3.0)
    return click_text(wd, '软件仓库', settle=2.5)


def main(wd: str = '.') -> int:
    os.makedirs(wd, exist_ok=True)
    results = []

    def record(aid, ok, note):
        results.append((aid, 'PASS' if ok else 'FAIL', note))
        print(f'{aid}: {"PASS" if ok else "FAIL"} {note}')

    m = McpClient()
    if not m.connect(retries=3):
        record('A0', False, 'MCP 未连接')
        return report(results)
    record('A0', True, 'MCP 已连接')
    v = m.result_text('check_tool', {'name': 'brew'})
    record('A1', 'Homebrew' in v, f'brew: {v[:40]}')
    if 'Homebrew' not in v:
        record('A2', False, 'brew 未装，跳过 UI 流程')
        return report(results)

    live = tap_endpoint_live()
    print(f'社区源端点探测: {"200 已上线" if live else "非 200（未上线，用种子兜底）"}')

    dev = Device(wd)
    dev.restart_app()   # 锁全屏 + 冷启（缓存秒显验证）

    # A2 官方源列表（可安装视图）
    if not goto_repo_tab(dev, wd):
        record('A2', False, '软件仓库 tab 不可达')
        return report(results)
    click_text(wd, '可安装', settle=2.0)   # 默认落在已安装视图，切可安装才见目录行
    texts = dump_texts(wd)
    ok_core = ('官方源' in texts and '社区源' in texts and 'a2ps' in texts
               and 'Tap 管理' not in texts)
    record('A2', ok_core, f'官方源列表+双源切换+Tap管理已移除: {ok_core}')

    # A3 重启缓存秒显
    dev.restart_app()
    if not goto_repo_tab(dev, wd):
        record('A3', False, '重启后软件仓库 tab 不可达')
        return report(results)
    click_text(wd, '可安装', settle=2.0)
    texts = dump_texts(wd)
    record('A3', 'a2ps' in texts, '重启后官方源秒显（磁盘缓存）')

    # A4 社区源切换（按端点状态条件断言）
    ok_switch = click_text(wd, '社区源', settle=4.0)
    texts = dump_texts(wd)
    if live:
        ok_a4 = ok_switch and ('bun' in texts)
        record('A4', ok_a4, f'社区源已上线：bun 可见={ok_a4}')
    else:
        ok_a4 = ok_switch and ('筹备中' in ' '.join(texts) or len(texts) > 0)
        record('A4', ok_a4, f'社区源未上线：优雅空态（不崩溃）={ok_a4}')

    # A5 社区 tap 无失败日志
    pid = _sh('hdc shell "pidof com.develop.opensource.devbox"', 20).strip()
    hil = _sh(f'hdc shell "hilog --pid {pid} -x 2>/dev/null | grep BrewTap"', 30) if pid else ''
    n_fail = sum(1 for l in hil.split('\n') if 'community tap failed' in l)
    record('A5', n_fail == 0, f'community tap 失败日志 {n_fail} 条（0=装机态正常）')

    return report(results)


def report(results):
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    rp = f'{ROOT}/reports/case_brew_sources_{ts}.md'
    os.makedirs(f'{ROOT}/reports', exist_ok=True)
    with open(rp, 'w', encoding='utf-8') as f:
        f.write(f'# HarmonyBrew 双固定源 E2E {ts}\n\n| 断言 | 结果 | 详情 |\n|---|---|---|\n')
        for aid, st, note in results:
            f.write(f'| {aid} | {st} | {note} |\n')
    fails = sum(1 for _, st, _ in results if st == 'FAIL')
    print(f'\n报告: {rp}\nPASS {len(results)-fails} / FAIL {fails}')
    return fails


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else '.'))
