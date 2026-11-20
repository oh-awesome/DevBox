"""
run_all.py —— 全量回归套件编排（run_smoke + 全部 case 顺序执行 + 汇总）

用例分级：
  L1 冒烟   run_smoke（全 13 页导航渲染）
  L2 功能   现有四件（brew_conan_smoke / brew_sources / lang_queue / tools_queue）
  L3 边缘   search_edge / keyboard_nav / theme_toggle / pagination_edge / mcp_security

用法：python run_all.py [workdir] [--quick]
  --quick 只跑 L1 + L3（跳过 L2 含真实安装的长用例，约 10 分钟）
"""

import sys, os, time, datetime, subprocess

ROOT = os.path.dirname(os.path.abspath(__file__))

L1 = ['run_smoke.py']
L2 = ['cases/case_brew_conan_smoke.py', 'cases/case_brew_sources.py',
      'cases/case_lang_queue.py', 'cases/case_tools_queue.py']
L3 = ['cases/case_search_edge.py', 'cases/case_keyboard_nav.py',
      'cases/case_theme_toggle.py', 'cases/case_pagination_edge.py',
      'cases/case_mcp_security.py', 'cases/case_brew_priority.py']


def run_one(script: str, workdir: str) -> tuple[str, str]:
    t0 = time.time()
    print(f'\n{"="*60}\n▶ {script}\n{"="*60}')
    r = subprocess.run([sys.executable, f'{ROOT}/{script}', workdir],
                       capture_output=True, text=True, encoding='utf-8', errors='replace',
                       cwd=ROOT, timeout=1800)
    dt = time.time() - t0
    out = (r.stdout or '') + (r.stderr or '')
    print(out[-1500:])
    status = 'PASS' if r.returncode == 0 else 'FAIL'
    print(f'◀ {script} → {status}（{dt:.0f}s，exit={r.returncode}）')
    return status, f'{dt:.0f}s'


def normalize_theme() -> bool:
    """归一化到模板捕获主题（浅色）：NCC 模板对反色失配——深色下全量导航会假失败。
    探针=侧栏空白 (200,900)；非浅色则点顶栏主题开关中心（⟳+64 实证点位）切换。"""
    import sys
    sys.path.insert(0, ROOT)
    from core.device import Device
    try:
        dev = Device('.')
        cur = dev.screenshot('ra_theme')
        p = cur.getpixel((200, 900))[:3]
        if p[0] > 128:
            print('主题归一化: 已是浅色（模板主题）✓')
            return True
        import time
        dev.click(3044, 46, settle=1.5)
        time.sleep(1.0)
        after = dev.screenshot('ra_theme2')
        p2 = after.getpixel((200, 900))[:3]
        ok = p2[0] > 128
        print(f'主题归一化: 深→浅 {"✓" if ok else "FAIL（需人工切浅色再跑）"}')
        return ok
    except Exception as e:
        print(f'主题归一化异常（跳过）: {e}')
        return True


def main() -> int:
    workdir = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith('--') else '.'
    quick = '--quick' in sys.argv
    suite = L1 + (L3 if quick else L2 + L3)

    print(f'DevBox 全量回归  quick={quick}  workdir={workdir}')
    normalize_theme()
    t0 = time.time()
    summary = []
    for s in suite:
        try:
            status, note = run_one(s, workdir)
        except subprocess.TimeoutExpired:
            status, note = 'FAIL', '1800s 超时'
        except Exception as e:
            status, note = 'FAIL', str(e)[:60]
        summary.append((s, status, note))

    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    rp = f'{ROOT}/reports/run_all_{ts}.md'
    os.makedirs(f'{ROOT}/reports', exist_ok=True)
    with open(rp, 'w', encoding='utf-8') as f:
        f.write(f'# 全量回归汇总 {ts}（{"quick" if quick else "full"}，{time.time()-t0:.0f}s）\n\n')
        f.write('| 用例 | 结果 | 耗时 |\n|---|---|---|\n')
        for s, st, note in summary:
            f.write(f'| {s} | {st} | {note} |\n')
    fails = sum(1 for _, st, _ in summary if st != 'PASS')
    print(f'\n{"="*60}\n汇总: PASS {len(summary)-fails} / FAIL {fails} → {rp}')
    return fails


if __name__ == '__main__':
    sys.exit(main())
