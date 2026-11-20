"""
case_brew_priority.py —— brew PATH 优先开关 + 环境页冲突弹窗 E2E（2026-11-15 新功能）

功能语义：
  brew 页勾选"PATH 优先"→ 托管块内 .harmonybrew 段提为最前（rank -1）——
  brew 安装的命令优先命中；环境页保存若产生"块后前置式用户 PATH 行"
  （shell 顺序语义上会压制 brew）→ 弹窗"调整（brew 优先）/保留我的修改"。

前置：HarmonyBrew 本体已装（MCP brew_list 预检；未装 SKIP）。
通道：dump 全程（主题无关——模板对反色失配；AlertDialog/DevDialog 文本皆可 dump）。

断言矩阵：
  B1 开关就位：brew 页 'PATH 优先' 行存在
  B2 开启生效：环境页 PATH 合并值中 .harmonybrew 段索引 < usr/local 段（提前）
  B3 往返恢复：再点关闭 → .harmonybrew 索引 > usr/local（回 rank 3）
  B4 冲突-保留：编辑 PATH 值造块后前置行 → 保存 → 弹窗出现 → 点保留 →
      PATH 合并值 idx(.harmonybrew) < idx(brewtest)（块行在前=用户行在块后）
  B5 冲突-调整：再编辑 → 保存 → 弹窗 → 点调整 → PATH 合并值 idx(brewtest) <
      idx(.harmonybrew)（用户行被移到块前——文件行序反转）
  B6 清理：删除 PATH entry + 保存 → 值回归纯托管块（无 brewtest，优先序保持）
  B7 收尾：开关切回默认关闭（PATH 序恢复 rank 3）

用法：python cases/case_brew_priority.py [workdir]
"""

import sys, os, time, re, datetime
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.device import Device, _sh
from core import dump, vision
from core.mcp import McpClient

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TPL = f'{ROOT}/templates'
SWITCH_X = 3000            # 开关行右端（'PATH 优先' 行 y 由 dump 动态取）


def nav_sidebar(dev, workdir, name, tag):
    """dump 文本定位侧栏导航（主题无关）"""
    root = dump.fresh_dump(workdir, f'{tag}_nav')
    p = dump.find(root, name, in_region=(0, 500, 470, 2100))
    if not p:
        return False
    dev.click(*p)
    time.sleep(3.0)
    return True


def read_path_value(dev, workdir, tag):
    """环境页 → 展开 zshrc 卡 → 返回 PATH 合并值文本（None=失败）"""
    if not nav_sidebar(dev, workdir, '环境变量', tag):
        return None
    root = dump.fresh_dump(workdir, f'{tag}_e0')
    p = dump.find(root, '详细', in_region=(2900, 300, 3120, 800))
    if p:
        dev.click(*p)
        time.sleep(2.0)
    root = dump.fresh_dump(workdir, f'{tag}_e1')
    for a in dump.texts(root):
        t = a['text']
        if '.harmonybrew/bin' in t and 'usr/local' in t:
            return t
    # 卡可能已展开（收起态切换）：再 dump 一次容错
    root = dump.fresh_dump(workdir, f'{tag}_e2')
    for a in dump.texts(root):
        t = a['text']
        if '.harmonybrew/bin' in t and 'usr/local' in t:
            return t
    return None


def brew_page_switch(dev, workdir):
    """brew 页 'PATH 优先' 行中心 y（None=行不存在）"""
    if not nav_sidebar(dev, workdir, 'HarmonyBrew', 'bp'):
        return None
    root = dump.fresh_dump(workdir, 'bp_row')
    for a in dump.texts(root):
        if a['text'].strip() == 'PATH 优先':
            b = [int(v) for v in re.findall(r'-?\d+', a['bounds'])]
            if len(b) == 4:
                return (b[1] + b[3]) // 2
    return None


def click_switch(dev, cy):
    dev.click(SWITCH_X, cy, settle=2.0)


def toggle_and_verify(dev, workdir, want_brew_first, tag):
    """点开关并验证 PATH 序符合预期（首击被吞——窗口焦点瞬态——重试一次）。
    返回 (最终值, 尝试次数)；值 None 或序不符=失败"""
    v = None
    for i in range(3):
        cy = brew_page_switch(dev, workdir)
        if cy is None:
            return None, i + 1
        click_switch(dev, cy)
        v = read_path_value(dev, workdir, f'{tag}{i}')
        if v:
            iu, ib = v.find('usr/local'), v.find('.harmonybrew/bin')
            if want_brew_first and ib < iu:
                return v, i + 1
            if (not want_brew_first) and iu < ib:
                return v, i + 1
    return v, 3


def dialog_text_input(workdir, tag, contains):
    """编辑对话框内 text 含 contains 的 TextInput 中心坐标"""
    root = dump.fresh_dump(workdir, f'{tag}_dlg')
    for a in dump.nodes_by_type(root, 'TextInput'):
        if contains in a.get('text', ''):
            b = [int(v) for v in re.findall(r'-?\d+', a.get('bounds', ''))]
            if len(b) == 4:
                return (b[0] + b[2]) // 2, (b[1] + b[3]) // 2
    return None


def clear_input(dev, x, y):
    """Ctrl+A 全选 + DEL 清空（inputText 追加语义——必须主动清）"""
    _sh(f'hdc shell "uitest uiInput click {x} {y}"')
    time.sleep(0.4)
    _sh('hdc shell "uinput -K -d 2072 -d 2017 -u 2017 -u 2072 -i 80"', timeout=15)
    time.sleep(0.3)
    _sh('hdc shell "uitest uiInput keyEvent 2055"', timeout=10)
    time.sleep(0.5)


def input_at(dev, x, y, text):
    _sh(f'hdc shell "uitest uiInput inputText {x} {y} \'{text}\'"')
    time.sleep(0.8)


def find_text_pos(workdir, tag, txt, region=None):
    """dump 找文本中心坐标"""
    root = dump.fresh_dump(workdir, f'{tag}_f')
    return dump.find(root, txt, in_region=region)


def find_text_exact(workdir, tag, txt, region=None):
    """dump 精确等值匹配（子串匹配陷阱：'删除'会先命中弹窗标题'删除变量 PATH'——
    标题/按钮同词共存时必须等值）"""
    root = dump.fresh_dump(workdir, f'{tag}_x')
    for a in dump.texts(root):
        if a['text'].strip() == txt:
            b = [int(v) for v in re.findall(r'-?\d+', a['bounds'])]
            if len(b) != 4:
                continue
            cx, cy = (b[0] + b[2]) // 2, (b[1] + b[3]) // 2
            if region and not (region[0] <= cx <= region[2] and region[1] <= cy <= region[3]):
                continue
            return cx, cy
    return None


def main(workdir: str) -> int:
    os.makedirs(workdir, exist_ok=True)
    dev = Device(workdir)
    results = []

    def record(aid, ok, note):
        results.append((aid, 'PASS' if ok else 'FAIL', note))
        print(f'{aid}: {"PASS" if ok else "FAIL"} {note}')

    # PRE：先启动应用（托盘进程随持久化 MCP 开关拉起——刚装机时必经）
    dev.restart_app(wait=9.0, test_mode=True)
    time.sleep(2)
    mcp = McpClient()
    if not mcp.connect(retries=5):
        record('PRE', False, 'MCP 未连接（应用未启动/开关关）')
        return report(results)
    bl = mcp.result_text('brew_list')
    if 'not installed' in bl.lower():
        record('PRE', False, 'SKIP：HarmonyBrew 本体未装（brew_install 前置）')
        return report(results)
    # 预检后再冷启（重置 UI 状态机；MCP 已连通——托盘进程独立于主进程存活）
    dev.restart_app(wait=9.0, test_mode=True)
    time.sleep(1)

    # B0 状态归零（上一轮残留清偿——用例幂等性）：删残留用户 PATH 行 + 开关归
    # OFF（applyBrewPriority 重写块=死段过滤统一化顺带清历史污染段）
    nav_sidebar(dev, workdir, '环境变量', 'b0')
    root = dump.fresh_dump(workdir, 'b0_e')
    p = dump.find(root, '详细', in_region=(2900, 300, 3120, 800))
    if p:
        dev.click(*p); time.sleep(2.0)
    root = dump.fresh_dump(workdir, 'b0_e2')
    prow0 = dump.find(root, 'PATH', in_region=(500, 400, 900, 2000))
    if prow0:
        dev.click(*prow0); time.sleep(1.0)   # 选中（冷启后无选中态——首点必选中）
        pdel0 = dump.find(dump.fresh_dump(workdir, 'b0_e3'), '删除', in_region=(2500, 750, 3120, 1200))
        if pdel0:
            dev.click(*pdel0); time.sleep(1.5)
            pconf0 = find_text_exact(workdir, 'b0_conf', '删除', region=(700, 700, 2600, 1900))
            if pconf0:
                dev.click(*pconf0); time.sleep(1.5)
                psave0 = dump.find(dump.fresh_dump(workdir, 'b0_e4'), '保存', in_region=(2500, 750, 3120, 1200))
                if psave0:
                    dev.click(*psave0); time.sleep(2.5)
                    # 保存后可能弹残留冲突——点保留兜底
                    pk0 = dump.find(dump.fresh_dump(workdir, 'b0_e5'), '保留我的修改', in_region=(500, 800, 3120, 2000))
                    if pk0:
                        dev.click(*pk0); time.sleep(2.0)
    # 开关归 OFF + 死段清偿验证
    v_reset, _ = toggle_and_verify(dev, workdir, False, 'b0off')
    ok0 = v_reset is not None and 'brewtest' not in v_reset and v_reset.find('usr/local') < v_reset.find('.harmonybrew')
    record('B0', ok0, f"状态归零：无残留段+rank3: {(v_reset or '?')[:100]}")

    # B1 开关行就位
    cy = brew_page_switch(dev, workdir)
    record('B1', cy is not None, f"'PATH 优先' 行 y={cy}（brew 页包管理器卡）")

    # B2 开启 → 环境页 PATH 序
    v0 = read_path_value(dev, workdir, 'b2')
    iu, ib = (v0.find('usr/local'), v0.find('.harmonybrew/bin')) if v0 else (-1, -1)
    default_ok = v0 is not None and (iu < ib or 'usr/local' not in v0)
    print(f"开启前 PATH 值: {(v0 or '?')[:110]}")
    record('B2-0', v0 is not None, f"环境页可读 PATH 合并值（默认序 harmonybrew后置={default_ok}）")

    if cy is None or v0 is None:
        return report(results)
    v1, n1 = toggle_and_verify(dev, workdir, True, 'b2on')
    iu1, ib1 = (v1.find('usr/local'), v1.find('.harmonybrew/bin')) if v1 else (-1, -2)
    record('B2', v1 is not None and ib1 < iu1,
           f"开启后 idx(.harmonybrew)={ib1} < idx(usr/local)={iu1}（{n1} 次点击落地）: {(v1 or '?')[:90]}")

    # B3 关闭恢复
    v2, n2 = toggle_and_verify(dev, workdir, False, 'b3off')
    iu2, ib2 = (v2.find('usr/local'), v2.find('.harmonybrew/bin')) if v2 else (-1, -2)
    record('B3', v2 is not None and iu2 < ib2,
           f"关闭后 idx(usr/local)={iu2} < idx(.harmonybrew)={ib2}（{n2} 次点击，往返恢复）")

    # B4 冲突-保留：再开启 → 编辑 PATH 值造前置行 → 保存 → 弹窗 → 保留
    v4on, _ = toggle_and_verify(dev, workdir, True, 'b4on')
    if v4on is None or v4on.find('.harmonybrew/bin') > v4on.find('usr/local'):
        record('B4', False, '开启前置失败')
        return report(results)

    # 环境页：选中 PATH 行 → 编辑
    if not nav_sidebar(dev, workdir, '环境变量', 'b4'):
        record('B4', False, '环境页导航失败')
        return report(results)
    root = dump.fresh_dump(workdir, 'b4_sel')
    # 展开文件卡
    p = dump.find(root, '详细', in_region=(2900, 300, 3120, 800))
    if p:
        dev.click(*p); time.sleep(2.0)
    root = dump.fresh_dump(workdir, 'b4_sel2')
    prow = dump.find(root, 'PATH', in_region=(500, 400, 900, 2000))
    if not prow:
        record('B4', False, 'PATH 行未定位')
        return report(results)
    dev.click(*prow); time.sleep(1.0)   # 单击选中
    pedit = find_text_pos(workdir, 'b4_editbtn', '编辑', region=(2500, 750, 3120, 1200))
    if not pedit:
        root = dump.fresh_dump(workdir, 'b4_editbtn2')
        pedit = dump.find(root, '编辑', in_region=(2500, 750, 3120, 1200))
    if not pedit:
        record('B4', False, '编辑按钮未定位')
        return report(results)
    dev.click(*pedit); time.sleep(1.5)

    # 编辑对话框：第一个值行（含 .harmonybrew）清空改 brewtest
    vp = dialog_text_input(workdir, 'b4', '.harmonybrew')
    if not vp:
        record('B4', False, '对话框值行未定位（TextInput 含 .harmonybrew）')
        return report(results)
    clear_input(dev, *vp)
    input_at(dev, *vp, '$HOME/brewtest')
    time.sleep(0.6)
    # 对话框 '保存'（edit 模式；此时主页保存按钮未出现——hasUnsaved false）
    pdlg = find_text_pos(workdir, 'b4_dlgsave', '保存', region=(500, 700, 3120, 1900))
    if not pdlg:
        record('B4', False, '对话框保存按钮未定位')
        return report(results)
    dev.click(*pdlg); time.sleep(1.5)

    # 主页 '保存' → 冲突弹窗
    pmain = find_text_pos(workdir, 'b4_mainsave', '保存', region=(2500, 750, 3120, 1200))
    if not pmain:
        record('B4', False, '主页保存按钮未出现（hasUnsaved 未置位？）')
        return report(results)
    dev.click(*pmain); time.sleep(2.0)

    # 弹窗断言 + 点保留
    pdlgx = find_text_pos(workdir, 'b4_conflict', 'brew PATH 优先受影响', region=(500, 300, 3120, 1800))
    record('B4-弹窗', pdlgx is not None, '冲突弹窗出现' if pdlgx else '弹窗未出现（冲突检测未触发）')
    pkeep = find_text_pos(workdir, 'b4_keep', '保留我的修改', region=(500, 800, 3120, 2000))
    if not pkeep:
        record('B4', False, '保留按钮未定位')
        return report(results)
    dev.click(*pkeep); time.sleep(2.5)
    # 保留后：块行在前（managed 先合并）→ idx(.harmonybrew) < idx(brewtest)
    v4 = read_path_value(dev, workdir, 'b4kept')
    if v4:
        it, ihm = v4.find('brewtest'), v4.find('.harmonybrew')
        record('B4', it >= 0 and ihm < it,
               f"保留分支：idx(.harmonybrew)={ihm} < idx(brewtest)={it}（块行在前）")
    else:
        record('B4', False, '保留后读不到 PATH 值')

    # B5 冲突-调整：再编辑（值变更触发 hasUnsaved）→ 保存 → 调整
    # 行单击是 toggle 语义（B4 已选中 PATH，再点=反选；双击手势 uitest 不可靠）
    # ——selectedVar 在 B4 已置位且对话框流程不清除，直接点编辑按钮
    pedit = find_text_pos(workdir, 'b5_editbtn', '编辑', region=(2500, 750, 3120, 1200))
    if not pedit:
        record('B5', False, 'B5 编辑按钮未定位（选中态丢失？）')
        return report(results)
    dev.click(*pedit); time.sleep(1.8)
    vp = dialog_text_input(workdir, 'b5', 'brewtest')
    if not vp:
        record('B5', False, 'B5 对话框值行未定位')
        return report(results)
    clear_input(dev, *vp)
    input_at(dev, *vp, '$HOME/brewtest2')
    time.sleep(0.6)
    pdlg = find_text_pos(workdir, 'b5_dlgsave', '保存', region=(500, 700, 3120, 1900))
    if not pdlg:
        record('B5', False, 'B5 对话框保存未定位')
        return report(results)
    dev.click(*pdlg); time.sleep(1.5)
    pmain = find_text_pos(workdir, 'b5_mainsave', '保存', region=(2500, 750, 3120, 1200))
    if not pmain:
        record('B5', False, 'B5 主页保存未出现')
        return report(results)
    dev.click(*pmain); time.sleep(2.0)
    pdlgx = find_text_pos(workdir, 'b5_conflict', 'brew PATH 优先受影响', region=(500, 300, 3120, 1800))
    record('B5-弹窗', pdlgx is not None, '第二次冲突弹窗出现' if pdlgx else '弹窗未出现')
    padj = find_text_pos(workdir, 'b5_adj', '调整（brew 优先）', region=(500, 800, 3120, 2000))
    if not padj:
        record('B5', False, '调整按钮未定位')
        return report(results)
    dev.click(*padj); time.sleep(2.5)
    # 调整生效=行为级断言：用户行已移到块前 → 冲突消失 → 再次编辑保存【无弹窗】
    # （值断言不可用：B4 写入的用户行值本身以 brew 段开头（合并值快照），
    #   调整前后合并值都以 .harmonybrew 打头——行序反转在值里不可见）
    pedit2 = find_text_pos(workdir, 'b5_edit2', '编辑', region=(2500, 750, 3120, 1200))
    if not pedit2:
        record('B5', False, 'B5b 编辑按钮未定位（选中态丢失？）')
        return report(results)
    dev.click(*pedit2); time.sleep(1.8)
    vp2 = dialog_text_input(workdir, 'b5b', 'brewtestX')
    if not vp2:
        vp2 = dialog_text_input(workdir, 'b5b', 'brewtest')
    if not vp2:
        record('B5', False, 'B5b 对话框值行未定位')
        return report(results)
    clear_input(dev, *vp2)
    input_at(dev, *vp2, '$HOME/brewtestY')
    time.sleep(0.6)
    pdlg2 = find_text_pos(workdir, 'b5b_dlgsave', '保存', region=(500, 700, 3120, 1900))
    if not pdlg2:
        record('B5', False, 'B5b 对话框保存未定位')
        return report(results)
    dev.click(*pdlg2); time.sleep(1.5)
    pmain2 = find_text_pos(workdir, 'b5b_mainsave', '保存', region=(2500, 750, 3120, 1200))
    if not pmain2:
        record('B5', False, 'B5b 主页保存未出现')
        return report(results)
    dev.click(*pmain2); time.sleep(2.5)
    pdlgx2 = find_text_pos(workdir, 'b5b_conflict', 'brew PATH 优先受影响', region=(500, 300, 3120, 1800))
    # 无弹窗=用户行已在块前（调整生效）；有弹窗=调整没移动行
    record('B5', pdlgx2 is None,
           '调整后再次保存无冲突弹窗（用户行已移块前——调整生效）' if pdlgx2 is None
           else '再次保存仍弹冲突（调整未生效）')
    # 弹窗若在（异常路径）——点保留兜底继续
    if pdlgx2 is not None:
        pk = find_text_pos(workdir, 'b5b_keep', '保留我的修改', region=(500, 800, 3120, 2000))
        if pk:
            dev.click(*pk); time.sleep(2.0)

    # B6 清理：删除 PATH entry → 确认 → 保存 → 值回归纯托管
    # （B5 双击已置 selectedVar='PATH'——行单击是 toggle，再点会反选）
    pdel = find_text_pos(workdir, 'b6_del', '删除', region=(2500, 750, 3120, 1200))
    if pdel:
        dev.click(*pdel); time.sleep(1.5)
        # danger 确认弹窗的 '删除' 按钮（精确匹配——子串会命中标题'删除变量 PATH'）
        pconf = find_text_exact(workdir, 'b6_conf', '删除', region=(700, 700, 2600, 1900))
        if pconf:
            dev.click(*pconf); time.sleep(1.5)
        else:
            record('B6', False, '删除确认按钮未定位')
            return report(results)
    else:
        record('B6', False, '删除按钮未定位')
        return report(results)
    pmain = find_text_pos(workdir, 'b6_save', '保存', region=(2500, 750, 3120, 1200))
    if pmain:
        dev.click(*pmain); time.sleep(2.5)
    # B6a：用户行已删（值仍含块内历史收编段——死段清理在块重写时发生）
    v6a = read_path_value(dev, workdir, 'b6a')
    ok6a = v6a is not None and 'brewtestY' not in v6a
    record('B6a', ok6a, f"删除保存后无本轮用户行（brewtestY）: {(v6a or '?')[:80]}")

    # B7 收尾：开关切回默认关 → applyBrewPriority 重写块 → 死段过滤统一化
    # （$HOME/<seg> 无目录即滤——历史收编的 brewtest 系死段一并清出块）
    cy = brew_page_switch(dev, workdir)
    if cy is not None:
        click_switch(dev, cy)
        v7 = read_path_value(dev, workdir, 'b7off')
        ok7 = (v7 is not None and v7.find('usr/local') < v7.find('.harmonybrew')
               and 'brewtest' not in v7)
        record('B7', ok7, f"收尾恢复默认 rank3 + 死段全清: {(v7 or '?')[:100]}")
    else:
        record('B7', False, '收尾开关行未定位')

    return report(results)


def report(results) -> int:
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    rp = f'{ROOT}/reports/case_brew_priority_{ts}.md'
    os.makedirs(f'{ROOT}/reports', exist_ok=True)
    with open(rp, 'w', encoding='utf-8') as f:
        f.write(f'# brew PATH 优先用例 {ts}\n\n| 断言 | 结果 | 详情 |\n|---|---|---|\n')
        for aid, st, note in results:
            f.write(f'| {aid} | {st} | {note} |\n')
    fails = sum(1 for _, st, _ in results if st == 'FAIL')
    print(f'\n报告: {rp}\nPASS {len(results)-fails} / FAIL {fails}')
    return fails


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else '.'))
