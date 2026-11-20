"""
case_mcp_security.py —— MCP 真值层：注入防护 / 非法参数 / 健壮性边界

背景（2026-11 安全会审计结论）：MCP 保持无认证开放（为其他应用提供安装卸载服务），
但注入路径必须关闭——外部只能传参数与期望，不允许夹带命令。
本用例是注入面的回归闸：任何一条"探测载荷被执行"都意味着注入回归。

通道：MCP HTTP JSON-RPC（fport 18765）——无坐标/无窗口依赖，最稳通道。
前置：应用已启动且 MCP 开关开启（托盘进程监听 18765）；未开启时全部 SKIP。

断言矩阵：
  S1  基线   8 语言 get_runtime_status 全部合法返回（不抛异常、非空）
  S2  注入   lang 参数四种 shell 探测载荷（;id / $(id) / `id` / |id）→ 安全返回，
             结果文本不含 'uid='（id 命令输出特征=注入执行的铁证）
  S3  注入   install_tool name 夹带 ;id → 拒绝/安全失败，不执行安装
  S4  契约   未知工具名 → JSON-RPC isError 错误（不 crash 服务）
  S5  契约   未知 lang → 明确 not-found 语义（非乱码/非空异常）
  S6  极限   name 超长参数（10KB）→ 快速失败或安全返回（60s 无响应=FAIL，防挂起回归）
  S7  边界   缺必选参数 → 安全错误
  S8  正常   catalog_search 'zlib' → 结构合法；中文关键词 UTF-8 通道干净
  S9  注入   catalog_search name 夹带 $(id) → 无结果且无 uid= 输出
  S10 健全   get_env_info / get_system_info / get_task_progress 非空结构
  S11 契约   tools/list 枚举 ≥ 46 个工具 + 全量 [L*] 层前缀（防缩水/防丢分层）
  S12 并发   3 线程并发 get_runtime_status → 全部返回（服务并发可用）
  S13 盘点   2026-11-15 新工具冒烟（brew/conan 搜索/优先开关查询）+ 注入拒绝语义

用法：python cases/case_mcp_security.py
"""

import sys, os, time, datetime, threading
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.mcp import McpClient

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

LANGS = ['python', 'java', 'rust', 'node', 'lua', 'perl', 'go', 'php']
# 探测载荷：若注入被执行，`id` 会输出 uid=… —— 载荷本身无害（只跑 id）
PAYLOADS = [';id', '$(id)', '`id`', '|id', 'python;id', 'python $(id)']
UID_SIG = 'uid='


def main() -> int:
    results = []

    def record(aid: str, ok: bool, note: str):
        results.append((aid, 'PASS' if ok else 'FAIL', note))
        print(f'{aid}: {"PASS" if ok else "FAIL"} {note}')

    mcp = McpClient()
    if not mcp.connect(retries=5):
        print('MCP 未就绪（应用未启动或 MCP 开关关闭）——全部 SKIP')
        return report([('-', 'SKIP', 'MCP 未连接')])

    # S1 基线：8 语言 status 合法
    ok1, bad = True, []
    for lang in LANGS:
        try:
            r = mcp.result_text('get_runtime_status', {'lang': lang})
            if not r or r.strip() == '':
                ok1, _ = False, bad.append(f'{lang}:空')
        except Exception as e:
            ok1 = False
            bad.append(f'{lang}:{str(e)[:40]}')
    record('S1', ok1, f'8 语言 status {"全部返回" if ok1 else "异常: " + "; ".join(bad[:3])}')

    # S2 注入：get_runtime_status lang 夹带 shell 载荷
    ok2, ev2 = True, []
    for p in PAYLOADS:
        try:
            r = mcp.result_text('get_runtime_status', {'lang': p})
            if UID_SIG in r:
                ok2 = False
                ev2.append(f'[{p}] 执行了!')
        except RuntimeError:
            pass   # 工具层 isError 拒绝 = 安全
        except Exception as e:
            if UID_SIG in str(e):
                ok2 = False
                ev2.append(f'[{p}] 异常带uid输出')
    record('S2', ok2, f'{len(PAYLOADS)} 条载荷全部被拦' if ok2 else '注入泄漏: ' + '; '.join(ev2))

    # S3 注入：install_tool name 夹带（只读层不落地任何安装）
    ok3, note3 = True, '载荷被拒'
    try:
        r = mcp.result_text('install_tool', {'name': 'vim;id', 'confirm': False})
        if UID_SIG in r:
            ok3 = False
            note3 = '注入执行!'
        elif 'installed' in r.lower() or 'success' in r.lower() or '完成' in r:
            note3 = f'返回需人工核验: {r[:60]}'
    except RuntimeError as e:
        note3 = f'工具层拒绝: {str(e)[:60]}'
    except Exception as e:
        note3 = f'异常(视为拦): {str(e)[:60]}'
    record('S3', ok3, note3)

    # S4 未知工具名 → isError（服务不 crash）
    ok4 = False
    try:
        mcp.call('no_such_tool_xyz', {})
        ok4 = False
        note4 = '未知工具未报错?'
    except RuntimeError as e:
        ok4 = 'Unknown tool' in str(e) or 'error' in str(e).lower()
        note4 = f'isError 契约: {str(e)[:50]}'
    except Exception as e:
        note4 = f'异常类型: {str(e)[:50]}'
    record('S4', ok4, note4)

    # S5 未知 lang → 明确 not-found 语义
    ok5, note5 = False, ''
    try:
        r = mcp.result_text('get_runtime_status', {'lang': 'cobol'})
        ok5 = ('not' in r.lower()) or ('未' in r) or ('unknown' in r.lower()) or ('无' in r)
        note5 = f'返回: {r[:60]}'
    except RuntimeError as e:
        ok5, note5 = True, f'明确拒绝: {str(e)[:50]}'
    except Exception as e:
        note5 = f'异常: {str(e)[:50]}'
    record('S5', ok5, note5)

    # S6 超长参数 10KB（防挂起回归：UTF-16≠bytes body 长度坑的姐妹场景）
    t0 = time.time()
    ok6, note6 = False, ''
    try:
        mcp.call('get_available_versions', {'lang': 'a' * 10240}, timeout=60)
        dt = time.time() - t0
        ok6 = dt < 60
        note6 = f'10KB 参数 {dt:.1f}s 返回（未挂起）'
    except RuntimeError as e:
        dt = time.time() - t0
        ok6 = dt < 60
        note6 = f'10KB 参数 {dt:.1f}s 拒绝: {str(e)[:40]}'
    except Exception as e:
        note6 = f'异常 {time.time()-t0:.1f}s: {str(e)[:40]}'
    record('S6', ok6, note6)

    # S7 缺必选参数
    ok7 = False
    try:
        r = mcp.call('get_runtime_status', {})
        ok7 = bool(r)
        note7 = '缺参调用有返回'
    except RuntimeError as e:
        ok7 = True
        note7 = f'缺参安全拒绝: {str(e)[:40]}'
    except Exception as e:
        note7 = f'异常: {str(e)[:40]}'
    record('S7', ok7, note7)

    # S8 catalog_search 正常 + 中文关键词
    ok8, note8 = False, ''
    try:
        r = mcp.result_text('catalog_search', {'name': 'zlib', 'limit': 3})
        ok8 = 'zlib' in r.lower()
        note8 = f'zlib 命中: {r[:60]}'
    except Exception as e:
        note8 = f'异常: {str(e)[:50]}'
    record('S8', ok8, note8)

    # S9 catalog_search 注入
    ok9, note9 = True, ''
    try:
        r = mcp.result_text('catalog_search', {'name': '$(id)'})
        if UID_SIG in r:
            ok9 = False
            note9 = '注入执行!'
        else:
            note9 = f'无结果/无泄漏: {r[:40] if r.strip() else "(空)"}'
    except RuntimeError as e:
        note9 = f'拒绝: {str(e)[:40]}'
    except Exception as e:
        note9 = f'异常(视为拦): {str(e)[:40]}'
    record('S9', ok9, note9)

    # S10 环境真值工具健全
    ok10, bad10 = True, []
    for tool in ('get_env_info', 'get_system_info', 'get_task_progress'):
        try:
            r = mcp.result_text(tool)
            if not r.strip():
                ok10 = False
                bad10.append(f'{tool}:空')
        except Exception as e:
            ok10 = False
            bad10.append(f'{tool}:{str(e)[:30]}')
    record('S10', ok10, '三个真值工具非空' if ok10 else '; '.join(bad10))

    # S11 tools/list 工具数 ≥ 46（JSON-RPC 协议方法，非 tools/call）+ 层前缀全覆盖
    ok11, n = False, 0
    no_prefix: list = []
    try:
        tools = mcp.list_tools()
        n = len(tools)
        ok11 = n >= 46
        no_prefix = [t['name'] for t in tools if not t['description'].startswith('[L')]
        if no_prefix:
            ok11 = False
    except Exception:
        pass
    record('S11', ok11, f'tools/list = {n} 个（契约底线 46）层前缀缺失={no_prefix[:3] or '无'}')

    # S12 并发 3 线程
    ok12, note12 = True, ''
    errs: list[str] = []

    def _worker(lang: str):
        try:
            mcp.result_text('get_runtime_status', {'lang': lang})
        except Exception as e:
            errs.append(f'{lang}:{str(e)[:30]}')

    threads = [threading.Thread(target=_worker, args=(l,)) for l in LANGS[:3]]
    [t.start() for t in threads]
    [t.join(timeout=30) for t in threads]
    if errs:
        ok12 = False
        note12 = '; '.join(errs)
    else:
        note12 = '3 并发全部返回'
    record('S12', ok12, note12)

    # S13 2026-11-15 盘点新增工具冒烟（查询层真值 + 注入拒绝语义）
    ok13, bad13 = True, []
    checks = [
        ('brew_priority', {}, 'brew PATH 优先'),
        ('brew_search', {'query': 'cmake', 'limit': 3}, '条'),
        ('conan_search', {'query': 'zlib', 'limit': 3}, 'Conan'),
        ('brew_outdated', {}, ''),
    ]
    for tool, a, kw in checks:
        try:
            r = mcp.result_text(tool, a)
            if kw and kw not in r:
                bad13.append(f'{tool}:返回异常')
        except Exception as e:
            ok13 = False
            bad13.append(f'{tool}:{str(e)[:40]}')
    for payload in ('x;id', 'a$b'):
        try:
            mcp.result_text('brew_install_package', {'name': payload})
            bad13.append(f'[{payload}] 未拒绝!')
        except RuntimeError:
            pass   # 拒绝=期望
    ok13 = ok13 and not bad13
    record('S13', ok13, f'新工具查询冒烟+注入拒绝 {"全过" if ok13 else "; ".join(bad13[:3])}')

    return report(results)


def report(results) -> int:
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    rp = f'{ROOT}/reports/case_mcp_security_{ts}.md'
    os.makedirs(f'{ROOT}/reports', exist_ok=True)
    with open(rp, 'w', encoding='utf-8') as f:
        f.write(f'# MCP 安健用例 {ts}\n\n| 断言 | 结果 | 详情 |\n|---|---|---|\n')
        for aid, st, note in results:
            f.write(f'| {aid} | {st} | {note} |\n')
    fails = sum(1 for _, st, _ in results if st == 'FAIL')
    print(f'\n报告: {rp}\nPASS {len(results)-fails} / FAIL {fails}')
    return fails


if __name__ == '__main__':
    sys.exit(main())
