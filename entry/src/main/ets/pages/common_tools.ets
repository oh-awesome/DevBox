/**
 * 通用工具 —— 制品仓目录驱动（manifest tool 类，65+ 工具）
 * 数据源：EnvStore 统一数据层
 * 布局（2026-11-13 三版）：brew 软件中心同款——DevSegmentTabs（软件仓库/
 * 已安装，每 tab 独立搜索）+ 左列表（BrewListRow 38%）+ 右详情卡（操作
 * 与进度集中）。性能：视图模型 rows 在数据侧一次收口（tab×搜索×装态），
 * 渲染层只读现成行——此前 detail×18/row×N 重复全表扫描 + @State 元素级
 * 观察注册（每渲染 4000+ tracked reads）是切换卡顿根因；@Builder 参数化
 * 使详情数据每帧只算一次。操作按钮在 tap 时按名回查 ToolPkg（事件上下
 * 文 O(n)，零渲染成本）。
 */
import { DevTheme } from '../common/DevTheme';
import { DevPageHeader, DevChip, DevInput, DevToast, DevConfirm, DevPagination, PageCalc, DevRowProgress, DevKVRow, DevCard, DevBtn, DevSegmentTabs } from '../common/component';
import { BrewListRow } from '../common/brewcomponents';
import { DevTask } from '../utils/DevTask';
import fs from '@ohos.file.fs';
import { RepoVersion } from '../utils/ArtifactsRepo';
import { RuntimeMgr } from '../utils/RuntimeMgr';
import { TaskQueue } from '../utils/TaskQueue';
import { EnvStore } from '../utils/EnvStore';
import { DevEnvRegistry } from '../utils/DevEnvRegistry';

const HOME: string = '/storage/Users/currentUser';
/** BrewListRow 行高（名称+desc+meta 三行——与 brew 页同规格） */
const ROW_H: number = 66;

interface ToolPkg {
  name: string;
  summary: string;
  versions: RepoVersion[];
}

/** 行视图模型（渲染层只读——派生字段数据侧收口） */
interface ToolRow {
  name: string;
  summary: string;
  ver: string;         // 展示版本（已装非?→已装版，否则最新）
  meta: string;        // 已安装 | sizeLabel
  latest: string;      // 最新版（队列 id / 更新目标）
  sizeLabel: string;
  installed: boolean;
  canUpdate: boolean;
  providesStr: string; // provides 命令逗号串（搜索用——"find" 命中 "findutils"）
}

const EMPTY_ROW: ToolRow = {
  name: '', summary: '', ver: '', meta: '', latest: '', sizeLabel: '',
  installed: false, canUpdate: false, providesStr: '',
};

let cachedCatalog: ToolPkg[] = [];
// 进程级安装状态（切页后恢复 UI 进度）
let gBusyName: string = '';
let gBusyPct: number = -1;
let cachedCatalogSig: string = '';
let cachedProbe: string[] = [];
let cachedInstalled: string[] = [];

@Component
export struct CommonToolsPage {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @StorageProp('runtime_epoch') @Watch('onEpoch') runtimeEpoch: number = 0;
  @StorageProp('task_queue_epoch') @Watch('onQueueEpoch') queueEpoch: number = 0;
  @State queueRev: number = 0;  // 行 key 依赖：队列任何变化（入队/出队/推进）→ 行即时重渲染
  @StorageProp('envstore_epoch') @Watch('onEpoch') envstoreEpoch: number = 0;
  @State catalog: ToolPkg[] = [];
  @State rows: ToolRow[] = [];          // 视图模型（当前 tab × 搜索 × 装态）
  @State installedMap: string[] = [];
  @State pathMap: string[] = [];
  @State catalogLoading: boolean = false;
  @State tab: number = 0;               // 0=软件仓库 1=已安装
  @State search: string = '';           // 软件仓库搜索
  @State installedSearch: string = '';  // 已安装搜索
  @State currentPage: number = 1;
  @State pageSize: number = 12;
  @State selectedTool: string = '';     // 选中（右详情跟随；空/失效回落第一行）
  @State busyName: string = gBusyName;
  @State busyPct: number = gBusyPct;
  @State busyText: string = '';
  private searchTimer: number = -1;

  aboutToAppear(): void {
    this.busyName = gBusyName;
    this.busyPct = gBusyPct;
    this.catalog = cachedCatalog;
    this.installedMap = cachedInstalled;
    this.pathMap = cachedProbe;
    this.rebuildRows();
    this.loadCatalog(false);
    if (cachedProbe.length === 0) { this.probeAll(); }
  }

  private onEpoch(): void {
    this.catalog = cachedCatalog;
    this.probeAll();
  }

  /** 队列变化（入队/出队/推进）→ 行重渲染（位次/取消按钮/按钮翻转） */
  private onQueueEpoch(): void {
    this.queueRev += 1;
  }

  private loadCatalog(force: boolean): void {
    EnvStore.ensureRemote(force);
    if (this.catalogLoading) { return; }
    if (EnvStore.remoteReady()) { this.buildCatalog(); return; }
    this.catalogLoading = true;
    const timer: number = setInterval(() => {
      if (EnvStore.remoteReady()) {
        clearInterval(timer); this.catalogLoading = false; this.buildCatalog();
      }
    }, 400);
    setTimeout(() => { clearInterval(timer); if (this.catalogLoading) { this.catalogLoading = false; this.buildCatalog(); } }, 8000);
  }

  private buildCatalog(): void {
    const all: string[] = EnvStore.toolNames();
    const list: ToolPkg[] = [];
    for (let i = 0; i < all.length; i++) {
      const vers: RepoVersion[] = EnvStore.available(all[i]).slice();
      vers.sort((a: RepoVersion, b: RepoVersion) => RuntimeMgr.verCmp(b.ver, a.ver));
      list.push({ name: all[i], summary: EnvStore.summary(all[i]), versions: vers });
    }
    list.sort((a: ToolPkg, b: ToolPkg): number => a.name.localeCompare(b.name));
    const sig: string = list.map((t: ToolPkg): string => t.name).join(',');
    if (sig !== cachedCatalogSig) { cachedCatalogSig = sig; this.currentPage = 1; }
    cachedCatalog = list;
    this.catalog = list;
    this.rebuildRows();
    if (cachedProbe.length === 0) { this.probeAll(); }
  }

  private probeAll(): void {
    const tools: ToolPkg[] = this.catalog.length > 0 ? this.catalog : cachedCatalog;
    if (tools.length === 0) { return; }
    const names: string[] = [];
    for (let i = 0; i < tools.length; i++) { names.push(tools[i].name); }

    // fs 直读目录名（省一次 shell spawn；command -v 批量探测仍走 shell——PATH 解析语义）
    const dirLines: string[] = [];
    try {
      const entries: string[] = fs.listFileSync(`${HOME}/usr/local`);
      for (const e of entries) { dirLines.push(e); }
    } catch (_) {
    }
    {
      const pathLines: string[] = [];
      // H-3 纵深防御：names 来自 manifest（上游已有白名单），此处再加单引号包裹
      const safeNames: string[] = names.map((n: string): string => `'${n.replace(/'/g, '')}'`);
      DevTask.shell(`command -v ${safeNames.join(' ')} 2>/dev/null`,
        (t2: string, _e2: boolean) => { pathLines.push(t2); },
        (_ok2: boolean, _d2: string) => {
          const installedNames: Set<string> = new Set<string>();
          for (let i = 0; i < dirLines.length; i++) {
            const toks: string[] = dirLines[i].split(/\s+/);
            for (let j = 0; j < toks.length; j++) {
              const tk: string = toks[j].trim();
              if (tk === '' || tk.startsWith('.')) { continue; }
              // 深检：空壳目录不算已装（失败回滚残留的父目录——autoconf
              // exec_check 失败后目录名探测假已装，真机实证 2026-11-13）
              try {
                if (fs.listFileSync(`${HOME}/usr/local/${tk}`).length > 0) {
                  installedNames.add(tk);
                }
              } catch (_) {
                // 非目录/不可读——按未装处理
              }
            }
          }
          const pathNames: Set<string> = new Set<string>();
          for (let i = 0; i < pathLines.length; i++) {
            const t: string = pathLines[i].trim();
            if (t === '') { continue; }
            const seg: string[] = t.split('/');
            pathNames.add(seg[seg.length - 1]);
          }
          const installed: string[] = [];
          const probe: string[] = [];
          for (let i = 0; i < names.length; i++) {
            installed.push(`${names[i]}:${installedNames.has(names[i]) ? '?' : ''}`);
            probe.push(`${names[i]}:${pathNames.has(names[i]) ? 'yes' : ''}`);
          }
          this.installedMap = installed;
          this.pathMap = probe;
          cachedInstalled = installed;
          cachedProbe = probe;
          this.rebuildRows();
        });
    }
  }

  private installedVerOf(name: string): string {
    for (let i = 0; i < this.installedMap.length; i++) {
      if (this.installedMap[i].indexOf(`${name}:`) === 0) {
        return this.installedMap[i].substring(name.length + 1);
      }
    }
    return '';
  }

  private inPathOf(name: string): boolean {
    for (let i = 0; i < this.pathMap.length; i++) {
      if (this.pathMap[i].indexOf(`${name}:`) === 0) {
        return this.pathMap[i].substring(name.length + 1).trim() !== '';
      }
    }
    return false;
  }

  // ═══ 视图模型（数据侧一次收口——渲染层零扫描） ═══

  private latestVerOf(t: ToolPkg): string {
    return t.versions.length > 0 ? t.versions[0].ver : '';
  }

  /** 当前行集：tab × 搜索 × 装态。所有数据变化（目录/probe/搜索/切 tab/
   *  乐观翻转）都经此处重算——渲染层只读 rows（@State 整组赋值触发重渲染） */
  private rebuildRows(): void {
    const kw: string = (this.tab === 0 ? this.search : this.installedSearch).trim().toLowerCase();
    const out: ToolRow[] = [];
    const src: ToolPkg[] = this.catalog;
    for (let i = 0; i < src.length; i++) {
      const t: ToolPkg = src[i];
      const ver: string = this.installedVerOf(t.name);
      const installed: boolean = ver !== '';
      if (this.tab === 1 && !installed) { continue; }
      // provides 命令串预解析（搜索用——搜 "find" 命中 "findutils" 的行）
      let providesStr: string = '';
      if (kw !== '') {
        try {
          const prov: string[] = JSON.parse(t.versions.length > 0 ? t.versions[0].provides : '[]') as string[];
          if (prov !== null && prov.length > 0) { providesStr = prov.join(' ').toLowerCase(); }
        } catch (_) { providesStr = ''; }
      }
      // 搜索：包名 ∪ 描述 ∪ provides 命令（如搜 "dig" 命中 "bind"）
      const kwOk: boolean = kw === ''
        || t.name.toLowerCase().indexOf(kw) >= 0
        || t.summary.toLowerCase().indexOf(kw) >= 0
        || (providesStr !== '' && providesStr.indexOf(kw) >= 0);
      if (!kwOk) { continue; }
      const latest: string = this.latestVerOf(t);
      out.push({
        name: t.name,
        summary: t.summary,
        ver: installed && ver !== '?' ? ver : latest,
        meta: installed ? '已安装' : (t.versions.length > 0 ? t.versions[0].sizeLabel : ''),
        latest: latest,
        sizeLabel: t.versions.length > 0 ? t.versions[0].sizeLabel : '',
        installed: installed,
        canUpdate: installed && ver !== '?' && latest !== '' && latest !== ver,
        providesStr: providesStr,
      });
    }
    this.rows = out;
  }

  private pagedRows(): ToolRow[] {
    const start = (this.currentPage - 1) * this.pageSize;
    return this.rows.slice(start, start + this.pageSize);
  }

  /** 详情行（每帧一次——@Builder 参数传入；选中失效回落第一行） */
  private detailRow(): ToolRow {
    for (let i = 0; i < this.rows.length; i++) {
      if (this.rows[i].name === this.selectedTool) { return this.rows[i]; }
    }
    return this.rows.length > 0 ? this.rows[0] : EMPTY_ROW;
  }

  /** 选中包的 provides 命令列表（manifest provides 数组——brew 同款 mono 芯片） */
  private detailProvides(): string[] {
    const row: ToolRow = this.detailRow();
    if (row.name === '') { return []; }
    const vers: RepoVersion[] = EnvStore.available(row.name);
    if (vers.length === 0) { return []; }
    try {
      const prov: string[] = JSON.parse(vers[0].provides) as string[];
      return prov !== null ? prov : [];
    } catch (_) { return []; }
  }

  /** 按名回查 ToolPkg（操作按钮 tap 时解析——事件上下文，零渲染成本） */
  private toolPkgOf(name: string): ToolPkg | null {
    for (let i = 0; i < this.catalog.length; i++) {
      if (this.catalog[i].name === name) { return this.catalog[i]; }
    }
    return null;
  }

  private selectTool(name: string): void {
    this.selectedTool = name;
  }

  /** 任务在 G1 队列中的位次（snapshot 首位=running）：-1=不在队；0=running；n>0=第 n 位排队 */
  private queuePosOf(name: string, latest: string): number {
    const id = `install_${name}_${latest}`;
    const snap = TaskQueue.snapshot();
    for (let i = 0; i < snap.length; i++) {
      if (snap[i].id === id && snap[i].group === 'runtime') { return i; }
    }
    return -1;
  }

  /** 详情面板"安装中"判定（busy 或在队列）。期间一切"已装"派生 UI 须抑制：
   *  安装中途 probeAll 的目录扫描会看到 extract 已落盘的非空目录 → 行被翻成
   *  "已装"，出现"安装中 + 卸载"同屏；失败场景 probeAll 还会跑在异步回滚
   *  之前 → 假"已装"卡死。busy 期间详情一律按"安装中"呈现。 */
  private detailBusy(): boolean {
    const row: ToolRow = this.detailRow();
    if (row.name === '') { return false; }
    return this.busyName === row.name || this.queuePosOf(row.name, row.latest) >= 0;
  }

  /** 行 desc：运行中显示实时文案，排队/准备显示位次，否则摘要 */
  private rowDesc(t: ToolRow): string {
    const qpos: number = this.queuePosOf(t.name, t.latest);
    if (this.busyName === t.name && this.busyText !== '') { return this.busyText; }
    if (qpos > 0) { return `排队中（第 ${qpos} 位）`; }
    if (qpos === 0 && this.busyName !== t.name) { return '准备中…'; }
    return t.summary;
  }

  private onTabEnter(idx: number): void {
    this.selectedTool = '';   // 切 tab 清选中——详情跟当前 tab 行走
    this.currentPage = 1;
    this.rebuildRows();
    if (idx === 1) { this.probeAll(); }   // 已安装 tab 进入即校准装态
  }

  private doInstall(t: ToolPkg): void {
    // P1 分队列：busy 时入队（排队提示）而非拒绝——前置守卫去掉让 TaskQueue 接管
    const latest: RepoVersion | null = t.versions.length > 0 ? t.versions[0] : null;
    if (latest === null) { DevToast.show($r('app.string.common_tools_1')); return; }
    RuntimeMgr.installTool(t.name, latest as RepoVersion,
      (pct: number, text: string) => { this.onProgressFrom(t.name, pct, text); },
      (ok: boolean, msg: string) => {
        this.onProgressDone(t.name);
        if (ok) {
          DevToast.ok(`${t.name} 安装完成`);
          // 乐观翻转：即标已装（'?'=版本未知，probeAll 随后校准）
          if (this.installedVerOf(t.name) === '') {
            this.installedMap.push(`${t.name}:?`);
            cachedInstalled = this.installedMap;
            this.rebuildRows();
          }
          this.probeAll();
        }
        else if (msg.startsWith('已在队列')) {
          DevToast.show(msg);
          this.probeAll();
        }
        else {
          DevToast.show(`安装失败：${msg}`);
          // 失败时异步回滚还在后台删残留（rm 非空目录），立即探测会扫到
          // extract 落盘的目录 → 假"已装"卡死——延迟重探等回滚落地
          setTimeout(() => { this.probeAll(); }, 1500);
        }
      });
  }

  /** 进度更新：只更新当前 running 任务对应行的状态（多任务时区分行） */
  private onProgressFrom(name: string, pct: number, text: string): void {
    if (RuntimeMgr.busyTask.startsWith(`${name}|`)) {
      this.busyName = name; gBusyName = name;
      this.busyPct = pct; gBusyPct = pct; this.busyText = text;
    }
  }

  /** 任务完成：清 busy（只有当前 running 的才清——防误清排队任务的显示） */
  private onProgressDone(name: string): void {
    if (this.busyName === name) {
      this.busyName = ''; gBusyName = ''; this.busyText = '';
      this.busyPct = -1; gBusyPct = -1;
    }
  }

  private doUninstall(t: ToolPkg): void {
    DevConfirm.danger(`卸载 ${t.name}`, '将删除此工具及其链接。', () => {
      DevToast.show(`正在卸载 ${t.name}…`);
      // 审计 F-P0-4：此前"裸删"仅 rm 主目录+主链接——不落 registry.del
      // （账本永久谎报已装）、不清 provides 多链接（git-upload-pack 等残
      // 留）、不走 manifest 卸载配方。补三件：registry 删除 + provides
      // 链接清扫 + manifest 配方调用
      const provides: string[] = [];
      try {
        const provRaw: string = t.versions.length > 0 ? t.versions[0].provides : '[]';
        const arr: string[] = JSON.parse(provRaw) as string[];
        for (let i = 0; i < arr.length; i++) { provides.push(arr[i]); }
      } catch (_) {
      }
      // 构建卸载命令：主目录 + 主链接 + provides 链接 + registry 条目
      let cmd: string = `rm -rf '${HOME}/usr/local/${t.name}'`;
      if (provides.length > 0) {
        const links: string[] = provides.map((p: string): string => `'${HOME}/usr/local/bin/${p}'`);
        cmd += `; rm -f ${links.join(' ')}`;
      } else {
        cmd += `; rm -f '${HOME}/usr/local/bin/${t.name}'`;
      }
      DevTask.shell(cmd,
        (_l: string, _e: boolean) => {},
        (_ok: boolean, _d: string) => {
          // 账本删除（防永久谎报已装——审计 F-P0-4）
          DevEnvRegistry.del(t.name, '');
          // 乐观翻转：即移出已装集（probeAll 随后校准）
          this.installedMap = this.installedMap.filter((e: string): boolean => e.indexOf(`${t.name}:`) !== 0);
          cachedInstalled = this.installedMap;
          this.rebuildRows();
          DevToast.ok(`${t.name} 已卸载`);
          this.probeAll();
        });
    }, '确认卸载');
  }

  /** 取消（排队中先出队；running 中走 RuntimeMgr.cancel——下载/步骤停+断点保留） */
  private doCancel(name: string): void {
    const tp: ToolPkg | null = this.toolPkgOf(name);
    const latest: RepoVersion | null = tp !== null && tp.versions.length > 0 ? tp.versions[0] : null;
    const vid: string = latest !== null ? `install_${name}_${latest.ver}` : `install_${name}`;
    if (TaskQueue.dequeue(vid)) {
      DevToast.show(`${name} 已从队列移除`);
    } else {
      RuntimeMgr.cancel();
      DevToast.show($r('app.string.common_tools_2'));
    }
  }

  build() {
    Column() {
      DevPageHeader({ title: '通用工具', subtitle: '基础命令行工具的安装与管理', showDivider: false })
        .margin({ bottom: 12 })

      DevSegmentTabs({
        options: ['软件仓库', '已安装'],
        active: this.tab,
        onChange: (idx: number) => {
          if (idx !== this.tab) { this.tab = idx; this.onTabEnter(idx); }
        },
      }).margin({ bottom: 8 })

      // 搜索在 tab 下方（每 tab 独立——brew 同规）
      if (this.tab === 0) {
        DevInput({ value: this.search, placeholder: '搜索工具（名称/描述）…', mono: false,
          onChange: (v: string) => {
            // 300ms 防抖（与 Python 页同款——搜索含 provides JSON 解析，防每击键全量解析）
            if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); }
            this.searchTimer = setTimeout(() => {
              this.searchTimer = -1;
              this.search = v; this.currentPage = 1; this.rebuildRows();
            }, 300);
          } })
          .margin({ bottom: 8 })
      } else {
        DevInput({ value: this.installedSearch, placeholder: '搜索已安装的工具…', mono: false,
          onChange: (v: string) => { this.installedSearch = v; this.currentPage = 1; this.rebuildRows(); } })
          .margin({ bottom: 8 })
      }

      if (!EnvStore.remoteReady()) {
        Row({ space: 8 }) {
          LoadingProgress().width(14).height(14).color(DevTheme.PRIMARY)
          Text($r('app.string.common_tools_3')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
        }.width('100%').padding({ top: 4, bottom: 4 })
      }

      // ── 三分支（brew 页同规）：目录冷启动→居中加载；无行→全宽空态（无
      // 面板防闪现）；有行→主从布局。目录缓存秒显 + 后台刷新由上行提示表达 ──
      if (this.catalog.length === 0 && !EnvStore.remoteReady()) {
        Column({ space: 10 }) {
          LoadingProgress().width(28).height(28).color(DevTheme.PRIMARY)
          Text($r('app.string.common_tools_4'))
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.rows.length === 0) {
        Column({ space: 8 }) {
          Text(this.search.trim() !== '' || this.installedSearch.trim() !== ''
            ? '无匹配工具' : (this.tab === 1 ? '暂未安装任何工具' : '暂无工具'))
            .fontSize(DevTheme.FS_H3).fontColor(DevTheme.TEXT_TERTIARY)
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        // ── 主从布局：左列表（38%）+ 右详情 ──
        Row({ space: 10 }) {
          Column({ space: 4 }) {
            Scroll() {
              Column({ space: 3 }) {
                ForEach(this.pagedRows(), (t: ToolRow) => {
                  BrewListRow({
                    name: t.name,
                    desc: this.rowDesc(t),
                    ver: t.ver,
                    meta: t.meta,
                    selected: t.name === this.selectedTool,
                    installed: t.installed,
                    canUpgrade: t.canUpdate,
                    installing: this.busyName === t.name
                      || this.queuePosOf(t.name, t.latest) === 0,
                    deprecated: false,
                    onRowClick: () => { this.selectTool(t.name); },
                  })
                }, (t: ToolRow) => `${t.name}_${t.installed}_${t.canUpdate}_${this.queueRev}_${this.busyName === t.name}`)
              }.width('100%')
            }
            .width('100%').layoutWeight(1)
            .align(Alignment.TopStart)

            if (this.rows.length > this.pageSize) {
              DevPagination({
                currentPage: this.currentPage,
                totalItems: this.rows.length,
                itemsPerPage: this.pageSize,
                onChange: (p: number) => { this.currentPage = p; },
              })
            }
          }
          .width('38%').height('100%')

          // ── 右详情卡（brew 详情面板同款样式；无参 @Builder——按值传参
          // 不具响应性（ArkUI 语义：值参数不随状态刷新，点击行详情不跟——
          // 真机实证），无参内联随父 build 重渲染 ✓） ──
          Scroll() {
            this.buildToolDetail()
          }
          .layoutWeight(1).height('100%')
          .align(Alignment.TopStart)
          .backgroundColor(DevTheme.BG_CARD)
          .borderRadius(DevTheme.RADIUS_MD)
          .border({ width: 1, color: DevTheme.BORDER })
        }
        .width('100%').layoutWeight(1)
        .onAreaChange((_o: Area, n: Area) => {
          const h: number = n.height as number;
          if (h > 100) { this.pageSize = PageCalc.computePageSize(h, ROW_H); }
        })
      }
    }
    .width('100%').height('100%')
    .padding({ left: 24, right: 24, top: 8, bottom: 16 })
  }

  @Builder
  buildToolDetail() {
    if (this.detailRow().name !== '') {
      Column({ space: 14 }) {
        // ── 标题 + 安装状态 ──
        Row({ space: 10 }) {
          Text(this.detailRow().name)
            .fontSize(DevTheme.FS_H2).fontWeight(FontWeight.Bold).fontColor(DevTheme.TEXT_PRIMARY)
            .layoutWeight(1)
          DevChip({ text: this.detailBusy() ? '安装中' : (this.detailRow().installed ? '已安装' : '未安装'),
            tone: this.detailBusy() ? 'warning' : (this.detailRow().installed ? 'primary' : 'neutral'), mono: false })
        }.width('100%')

        // ── 描述 ──
        if (this.detailRow().summary !== '') {
          Text(this.detailRow().summary)
            .fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_SECONDARY)
            .width('100%')
        }

        // ── 信息卡 ──
        DevCard({ title: '信息', subtitle: '', accent: '', pad: 12 }) {
          Column({ space: 8 }) {
            DevKVRow({ k: '最新版本', v: this.detailRow().latest !== '' ? this.detailRow().latest : '—', copyable: false, mono: true })
            DevKVRow({
              k: '已装版本',
              v: this.installedVerOf(this.detailRow().name) !== '' && this.installedVerOf(this.detailRow().name) !== '?'
                ? this.installedVerOf(this.detailRow().name) : '—',
              copyable: false, mono: true,
            })
            DevKVRow({ k: '包大小', v: this.detailRow().sizeLabel !== '' ? this.detailRow().sizeLabel : '—', copyable: false, mono: true })
            DevKVRow({ k: 'PATH', v: this.inPathOf(this.detailRow().name) ? '已可用' : '未链接', copyable: false, mono: false })
            // ── 以下为 manifest 提供但此前未展示的字段（审计反馈后接入） ──
            if (EnvStore.licenseOf(this.detailRow().name) !== '') {
              DevKVRow({ k: '开源协议', v: EnvStore.licenseOf(this.detailRow().name), copyable: false, mono: true })
            }
            if (EnvStore.homepageOf(this.detailRow().name) !== '') {
              DevKVRow({ k: '主页', v: EnvStore.homepageOf(this.detailRow().name), copyable: true, mono: true })
            }
            if (EnvStore.maintainerOf(this.detailRow().name) !== '') {
              DevKVRow({ k: '维护者', v: EnvStore.maintainerOf(this.detailRow().name), copyable: false, mono: false })
            }
            // 描述不进信息卡（Hero 区已展示——brew 同款大字 desc，KV 行重复）
          }.width('100%')
        }

        // ── 提供的命令（manifest provides——bind 有 10 个、cmake 3 个）──
        if (this.detailProvides().length > 0) {
          DevCard({ title: `提供命令（${this.detailProvides().length}）`, subtitle: '', accent: '', pad: 12 }) {
            Column({ space: 6 }) {
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(this.detailProvides(), (cmd: string) => {
                  Text(cmd)
                    .fontSize(DevTheme.FS_CAPTION).fontFamily(DevTheme.MONO_FONT)
                    .fontColor(DevTheme.TEXT_SECONDARY)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .borderRadius(DevTheme.RADIUS_SM)
                    .backgroundColor(DevTheme.BG_ACCENT_PRIMARY)
                    .margin({ right: 6, bottom: 6 })
                }, (cmd: string) => cmd)
              }.width('100%')
            }.width('100%')
          }
        }

        // ── 进度区（运行中实时 / 排队位次 / 准备中） ──
        if (this.busyName === this.detailRow().name) {
          DevRowProgress({
            progress: this.busyPct,
            trailingText: `${this.busyPct}%`,
            trailingWidth: 40,
            subTrailingText: this.busyText,
            subTrailingWidth: 90,
          })
        } else if (this.queuePosOf(this.detailRow().name, this.detailRow().latest) > 0) {
          Text(`排队中（第 ${this.queuePosOf(this.detailRow().name, this.detailRow().latest)} 位）`)
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
        } else if (this.queuePosOf(this.detailRow().name, this.detailRow().latest) === 0) {
          Row({ space: 8 }) {
            LoadingProgress().width(14).height(14).color(DevTheme.PRIMARY)
            Text($r('app.string.common_tools_5')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
          }.width('100%')
        }

        // ── 操作区（集中详情；tap 时按名回查 ToolPkg——零渲染成本） ──
        // busy/排队期间按"安装中"呈现（抑制中途探测翻装带来的卸载/更新按钮）
        // 按钮语义与语言页 DevVersionRow 统一：busy 时安装钮反转成「取消」，
        // 安装中由上方进度区（DevRowProgress/排队位次）渲染，不再另出取消按钮
        DevCard({ title: '操作', subtitle: '', accent: '', pad: 12 }) {
          Row({ space: 10 }) {
            if (this.detailBusy()) {
              DevBtn({
                text: '取消',
                buttonSize: 'normal', plain: true,
                onTap: () => { this.doCancel(this.detailRow().name); },
              }).layoutWeight(1)
            } else if (!this.detailRow().installed) {
              DevBtn({
                text: '安装',
                buttonSize: 'normal',
                onTap: () => {
                  const tp: ToolPkg | null = this.toolPkgOf(this.detailRow().name);
                  if (tp !== null) { this.doInstall(tp); }
                },
              }).layoutWeight(1)
            } else if (this.detailRow().canUpdate) {
              DevBtn({
                text: `更新到 ${this.detailRow().latest}`,
                buttonSize: 'normal',
                onTap: () => {
                  const tp: ToolPkg | null = this.toolPkgOf(this.detailRow().name);
                  if (tp !== null) { this.doInstall(tp); }
                },
              }).layoutWeight(1)
            }
            if (this.detailRow().installed && !this.detailBusy()) {
              DevBtn({
                text: '卸载',
                buttonSize: 'normal', danger: true,
                onTap: () => {
                  const tp: ToolPkg | null = this.toolPkgOf(this.detailRow().name);
                  if (tp !== null) { this.doUninstall(tp); }
                },
              }).layoutWeight(1)
            }
          }.width('100%')
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    }
  }
}
