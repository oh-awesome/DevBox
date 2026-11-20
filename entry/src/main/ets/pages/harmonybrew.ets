/**
 * HarmonyBrew —— 五 Tab 结构（新 UI：左列表右详情，BrewUI 模式 + DevTheme 配色）
 * Tab 1 包管理器：brew 本体安装/卸载/更新（三键互斥）
 * Tab 2 软件仓库：双固定源目录（官方 JWS 4714 + OHPCD 社区 JWS），
 *              热门排序（官方 stats 按日聚合）+ 搜索（防抖+50 上限）
 * Tab 3 已安装：brew list --json=v2 结构化（版本/安装时间/依赖引入）
 * Tab 4 可升级：brew outdated（brew 自己判，不做我们的版本比对）+ 批量升级
 *
 * 交互模式（BrewUI 借鉴）：行不放操作按钮（点行=选中，安装入口在右详情）；
 * selectedFormula 单一事实源 + 失效回落第一行（右侧永不出空白）；
 * 安装相位 running→reconciling（库存刷新空窗）→徽标翻转；
 * 错误内联在详情按钮下方（不弹 toast 一闪而过）；保留 DevPagination 分页。
 */
import { DevPageHeader, DevCard, DevChip, DevBtn, DevKVRow, DevInput, DevConfirm, DevToast, DevSegmentTabs, DevPagination, PageCalc, DevStatusDot, DevRowProgress, copyText } from '../common/component';
import { DevTheme } from '../common/DevTheme';
import { DevTask } from '../utils/DevTask';
import { DiscoveryService } from '../utils/DiscoveryService';
import { BrewTapService } from '../utils/BrewTapService';
import { BrewCatalogService, BrewFormulaInfo } from '../utils/BrewCatalogService';
import { BrewStatsService } from '../utils/BrewStatsService';
import { DevEnvPaths } from '../utils/DevEnvPaths';
import { BrewPathPrefs } from '../utils/McpPrefs';
import { AnsiClean } from '../utils/AnsiClean';
import { IBestSwitch, IBestStringNumber } from '@ibestservices/ibest-ui-v2';
import { BrewQueryService, InstalledPackage, OutdatedEntry } from '../utils/BrewQueryService';
import { BrewEnv } from '../utils/BrewEnv';
import { DevCommandBlock, BrewListRow } from '../common/brewcomponents';

const HOME = '/storage/Users/currentUser';
// brew 路径收编 BrewEnv（仓库实体——前缀软链会派生出残骸 Cellar，详见
// BrewEnv.brew() 注释；与 SEALED 同源消灭双份漂移）
const BREW = BrewEnv.brew();
const SEALED = BrewEnv.env();
/** 源切换键：'' = 官方源；'ohpcd' = 社区源 */
const SRC_CORE: string = '官方源';
const SRC_COMMUNITY: string = '社区源';
const KEY_OHPCD: string = 'ohpcd';
/** brew 行高（名称+desc+meta 三行，BrewListRow） */
const ROW_H: number = 66;

/** 空公式（详情占位——避免非空断言） */
const EMPTY_FORMULA: BrewFormulaInfo = {
  name: '', desc: '', version: '', tap: '', homepage: '', license: '',
  executables: [], dependencies: [], caveats: '', kegOnly: false, deprecated: false,
};

let cachedBrewScanned: boolean = false;
let cachedBrewInstalled: boolean = false;
let cachedBrewVersion: string = '';
let cachedBrewPackages: string[] = [];
let cachedInstalledPkgs: InstalledPackage[] = [];

@Component
export struct Harmonybrew {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @State tab: number = 0;
  // 包管理器状态
  @State brewInstalled: boolean = false;
  @State brewVersion: string = '';
  @State tapName: string = '';
  @State tapRepo: string = '';
  // 本体安装 busy 也入 AppStorage（修复 #2：切页回来按钮不显示"安装中"且可
  // 误触二次启动 install.sh——@State 切页即丢；回调发生在旧实例，写 StorageLink
  // 会同步到活实例）
  @StorageLink('brewInstallBusy') installBusy: boolean = false;
  @StorageLink('brewUpdateTarget') updateTarget: string = '';  // busy 时正在执行的操作（'check'|'update'|'uninstall'）——三键互斥 loading（持久化同 installBusy）
  @State installLog: string[] = [];
  @StorageLink('brewInstallPct') @Watch('onPctWatch') installPct: number = -1;
  @StorageLink('brewInstallStage') installStage: string = '';
  @State installDl: string = '';
  // 软件仓库（左列表右详情）
  @State formulas: BrewFormulaInfo[] = [];      // 官方源目录
  @State ohpcdRows: BrewFormulaInfo[] = [];     // 社区源目录
  @State formulasLoading: boolean = false;
  @State ohpcdLoading: boolean = false;
  // 源选择入 AppStorage（修复 #3：切大页回来源重置为默认官方源——与"定位
  // 恢复源"不对称；持久化后离开时的源即回来时的源，两条路径一致）
  @StorageLink('brewSelectedTap') selectedTap: string = '';  // ''=官方源；'ohpcd'=社区源
  @State search: string = '';                  // 输入框值
  @State searchApplied: string = '';           // 300ms 防抖后的生效词
  private searchTimer: number = -1;
  @State displayedRows: BrewFormulaInfo[] = [];  // 当前源×搜索×热门排序的显示集
  @State selectedFormula: string = '';           // 选中（单一事实源；失效渲染时回落第一行）
  @State currentPage: number = 1;
  @State pageSize: number = 12;
  // 已安装
  @State installedPkgs: InstalledPackage[] = [];
  @State installedLoading: boolean = false;
  @State installedSearch: string = '';
  private packages: string[] = [];
  // 可升级
  @State outdatedPkgs: OutdatedEntry[] = [];
  @State outdatedLoading: boolean = false;
  // 公共安装相位（'install:x' | 'uninstall:x' | 'upgrade:x' | 'upgradeAll' | 'reconciling:x'）
  // AppStorage 存储——页面切走再回来（aboutToAppear 重建），状态不丢（修复 #2/#6）
  // reconciling 段带包名：完成回调发生在旧实例（其 loadInstalled 写在死对象上活页
  // 无感）——@StorageLink 变化通知活实例，onPhaseWatch 在活页就地刷新库存
  @StorageLink('brewInstallPhase') @Watch('onPhaseWatch') installPhase: string = '';
  @StorageLink('brewInstallSource') installSource: string = '';
  @State inlineError: string = '';
  /** brew PATH 优先（EntryAbility 水化到 AppStorage，切页不丢；
   *  watch 同步静态位——水化晚于本页挂载时 rank 排序也能即时生效） */
  @StorageProp('brew_path_priority') @Watch('onBrewPriorityWatch') brewPriority: boolean = false;
  private lastPct: number = -1;
  private lastPhase: string = '';
  // 退出码纠偏（2026-11-13 真机实证：卸载级联依赖时退出码非零但实际成功——
  // 以列表查询为准）：失败分支后台跑 loadInstalled，查询结果若证明
  // "其实成功"（卸载的包没了 / 安装的包在了）则自动清 inlineError
  private pendingVerify: string = '';
  private pendingVerifyIsUninstall: boolean = false;

  /** 本体安装收尾（installPct 回落 -1）跨实例可见——活页就地刷新（修复 #2：安装完成后本页面不刷新） */
  private onPctWatch(): void {
    if (this.installPct < 0 && this.lastPct >= 0) { this.refresh(); }
    this.lastPct = this.installPct;
  }

  /** 公式安装相位推进——活实例就地刷新库存/升级集（旧实例回调写的死对象不再丢事件） */
  private onPhaseWatch(): void {
    if (this.installPhase !== this.lastPhase) {
      this.lastPhase = this.installPhase;
      if (this.installPhase.indexOf('reconciling') === 0) {
        this.loadInstalled();
        this.loadOutdated();
      }
    }
  }

  /** 优先位 AppStorage 变化（水化/别页切换）→ 同步 DevEnvPaths 静态 rank 位 */
  private onBrewPriorityWatch(): void {
    DevEnvPaths.brewPathPriority = this.brewPriority;
  }

  /** 勾选切换：置静态位 + 重写托管块（.harmonybrew 段前/后置） + 持久化 */
  private toggleBrewPriority(on: boolean): void {
    this.brewPriority = on;
    AppStorage.setOrCreate('brew_path_priority', on);
    DevEnvPaths.applyBrewPriority(on);
    const ctx = this.getUIContext().getHostContext();
    if (ctx) {
      BrewPathPrefs.set(ctx, on);
    }
    DevToast.ok(on ? '已开启 brew 优先：brew 安装的命令将优先于其他环境'
      : '已关闭 brew 优先');
  }

  aboutToAppear(): void {
    // tap 元信息：发现服务下发（包管理器卡片展示用）
    const cfg = DiscoveryService.latest();
    this.tapName = cfg.brewTapName;
    this.tapRepo = cfg.brewTapRepo;
    // 双源目录：磁盘缓存秒显 + TTL 过期后台刷新（stale-while-revalidate）
    this.formulas = BrewCatalogService.core();
    this.ohpcdRows = BrewCatalogService.tap();
    this.formulasLoading = this.formulas.length === 0;
    this.ohpcdLoading = this.ohpcdRows.length === 0 && BrewCatalogService.tapFetching();
    // 下载统计（热门排序数据源；官方 stats 按日文件聚合）
    BrewStatsService.init(this.getUIContext().getHostContext(), () => {
      this.rebuildRepoRows();   // 统计到达后重排热门
    });
    BrewCatalogService.init(this.getUIContext().getHostContext(), () => {
      this.formulas = BrewCatalogService.core();
      this.ohpcdRows = BrewCatalogService.tap();
      this.formulasLoading = this.formulas.length === 0 && BrewCatalogService.coreFetching();
      this.ohpcdLoading = this.ohpcdRows.length === 0 && BrewCatalogService.tapFetching();
      this.rebuildRepoRows();
    });
    BrewTapService.init(this.getUIContext().getHostContext());
    if (cachedBrewScanned) {
      // 缓存秒显（切页回来不白屏）——但仍需后台 refresh（终端装的新包要能看到）
      this.brewInstalled = cachedBrewInstalled;
      this.brewVersion = cachedBrewVersion;
      this.packages = cachedBrewPackages;
      this.installedPkgs = cachedInstalledPkgs;
      this.rebuildRepoRows();
    }
    this.refresh();  // 无论缓存状态都 refresh（修复：终端装的包不显示——缓存永不失效）
  }

  // ═══ 本体状态 + 已装列表（brew list --json=v2 结构化） ═══

  /** 安装进度推进（单调递增：里程碑与下载百分比永不倒退） */
  private bumpInstall(pct: number, stage: string): void {
    if (pct > this.installPct) { this.installPct = pct; }
    if (stage !== '') { this.installStage = stage; }
    this.installDl = '';
  }

  private refresh(): void {
    const lines: string[] = [];
    DevTask.shell(`${BREW} --version 2>/dev/null | head -1; echo '__END__'`,
      (t: string, _e: boolean) => lines.push(AnsiClean.clean(t)),
      (_ok: boolean, _d: string) => {
        const splitAt = lines.indexOf('__END__');
        const ver = (splitAt >= 0 ? lines.slice(0, splitAt).join('\n') : '').trim();
        this.brewInstalled = ver !== '';
        this.brewVersion = ver;
        if (!this.brewInstalled) {
          this.packages = [];
          this.installedPkgs = [];
        }
        cachedBrewScanned = true;
        cachedBrewInstalled = this.brewInstalled;
        cachedBrewVersion = this.brewVersion;
        // brew 装好后补社区 tap + 终端环境注册（均幂等）
        if (this.brewInstalled) {
          BrewTapService.ensureApplied();
          this.loadInstalled();
          this.syncBrewShellenv();
        }
      });
  }

  /**
   * brew 环境注册到终端（用户定案方案）：执行 brew shellenv 捕获真实输出
   * （HOMEBREW_PREFIX/CELLAR/REPOSITORY、MANPATH、INFOPATH 全量），非 PATH
   * 变量落 ohpcd devenv 托管块 + PATH 段进 rank 体系——用户新开终端 brew
   * 直接可用，替代官方"手动加 eval 行"姿势（静态、随块管理、卸载摘除）。
   */
  private syncBrewShellenv(): void {
    if (DevEnvPaths.brewEnvComplete()) { return; }   // 幂等守卫（自愈补漏）
    const lines: string[] = [];
    DevTask.shell(`${SEALED} '${BREW}' shellenv 2>/dev/null`,
      (t: string, _e: boolean) => { if (t.trim() !== '') { lines.push(t.trim()); } },
      (ok: boolean, _d: string) => {
        if (ok && lines.length > 0) {
          DevEnvPaths.ensureBrewShellenv(lines);
        }
      });
  }

  /** 结构化已装列表；--json 不被 fork 支持时退回裸名列表（兼容兜底） */
  private loadInstalled(): void {
    this.installedLoading = true;
    BrewQueryService.listInstalled((pkgs: InstalledPackage[] | null) => {
      this.installedLoading = false;
      if (pkgs !== null) {
        this.installedPkgs = pkgs;
        this.packages = pkgs.map((p: InstalledPackage): string => p.name);
      } else {
        this.fallbackListPlain();
        return;
      }
      cachedBrewPackages = this.packages;
      cachedInstalledPkgs = this.installedPkgs;
      this.settlePendingVerify();
      if (this.installPhase.indexOf('reconciling') === 0) { this.installPhase = ''; }
      this.rebuildRepoRows();
    });
  }

  /** 退出码纠偏：查询真值若与失败提示矛盾（级联卸载退出非零但已卸 /
   *  安装退出非零但已装）→ 清残留错误。loadInstalled 两条路径收尾必经 */
  private settlePendingVerify(): void {
    if (this.pendingVerify === '') { return; }
    const name: string = this.pendingVerify;
    const wasUninstall: boolean = this.pendingVerifyIsUninstall;
    this.pendingVerify = '';
    this.pendingVerifyIsUninstall = false;
    if (wasUninstall && !this.formulaInstalled(name)) {
      this.inlineError = '';   // 实际已卸载（退出码谎报）——撤销失败提示
    } else if (!wasUninstall && this.formulaInstalled(name)) {
      this.inlineError = '';   // 实际已安装（退出码谎报）——撤销失败提示
    }
  }

  /** 兜底：brew list 裸名（无版本/时间——OHOS fork 不支持 --json=v2） */
  private fallbackListPlain(): void {
    // 真机实测（2026-11-13）：fork 的裸 list 是列式空格分隔——
    // "==> Formulae" 段头 + "lz4  muslext  xz  zstd" 一行多包。
    // 按整行包名正则会把多包行整行丢弃 → 收集后逐行分词：
    // 段头行跳过、其余按空白切 token、包名格式校验（过滤进度条/统计行）、去重
    const chunks: string[] = [];
    DevTask.shell(`${SEALED} '${BREW}' list 2>/dev/null`,
      (t: string, _e: boolean) => {
        const clean: string = AnsiClean.clean(t);
        if (clean.trim() !== '') { chunks.push(clean); }
      },
      (_ok: boolean, _d: string) => {
        this.installedLoading = false;
        const names: string[] = [];
        const seen: Set<string> = new Set<string>();
        for (let i = 0; i < chunks.length; i++) {
          const line: string = chunks[i].trim();
          if (line === '' || line.indexOf('==>') === 0) { continue; }
          const toks: string[] = line.split(/\s+/);
          for (let j = 0; j < toks.length; j++) {
            const tk: string = toks[j];
            if (tk === '' || !/^[A-Za-z0-9][A-Za-z0-9@._+-]*$/.test(tk)) { continue; }
            if (!seen.has(tk)) { seen.add(tk); names.push(tk); }
          }
        }
        this.packages = names;
        this.installedPkgs = names.map((n: string): InstalledPackage => {
          return { name: n, version: '', installedOn: 0, asDependency: false, linked: false };
        });
        cachedBrewPackages = this.packages;
        cachedInstalledPkgs = this.installedPkgs;
        this.settlePendingVerify();
        if (this.installPhase.indexOf('reconciling') === 0) { this.installPhase = ''; }
        this.rebuildRepoRows();
      });
  }

  /** 可升级集合（brew outdated --json=v2；brew 自己判，不做我们的版本比对） */
  private loadOutdated(): void {
    this.outdatedLoading = true;
    BrewQueryService.listOutdated((entries: OutdatedEntry[] | null) => {
      this.outdatedLoading = false;
      if (entries !== null) { this.outdatedPkgs = entries; }
    });
  }

  private formulaInstalled(name: string): boolean {
    for (let i = 0; i < this.packages.length; i++) {
      if (this.packages[i] === name) { return true; }
    }
    return false;
  }

  // ═══ 包管理器操作 ═══

  private installBrew(): void {
    if (this.installBusy) { return; }
    this.installBusy = true;
    this.installLog = ['$ ' + DiscoveryService.latest().brewInstallScript];
    // 原样执行发现服务下发的命令（平台事实：系统 curl 可直接过 TLS——此前 (60) 是
    // 我们装的工具 curl 影子化 bare 命令；系统 /usr/bin/zsh 为真 zsh。环境钉死后
    // 命令内部所有解析都是系统版本）：
    //   export HOME + PATH='/usr/bin:/bin'（防已装工具影子化 zsh/curl——真机实证
    //   brew 自检 zsh 命中我们装的 bash → "Zsh is required"）
    //   成败按 refresh 实测状态判定（curl 失败时 zsh -c "" 退出码 0——直灌形态固有）
    const cmd: string = DiscoveryService.latest().brewInstallScript;
    this.installPct = 2;
    this.installStage = '准备下载…';
    this.installDl = '';
    DevTask.shell(
      `export HOME='${HOME}' PATH='/usr/bin:/bin'; ${cmd}`,
      (t: string, _e: boolean) => {
        const line: string = t.trim();
        if (line === '') { return; }
        this.installLog.push(line);
        if (this.installLog.length > 40) { this.installLog = this.installLog.slice(-30); }
        // ── 阶段里程碑（install.sh 的 ==> 行——真实装机日志逐行核对）──
        if (line.indexOf('==>') === 0) {
          if (line.indexOf('This script will install') >= 0) {
            this.bumpInstall(2, '准备安装…');
          } else if (line.indexOf('new directories will be created') >= 0
            || line.indexOf('/bin/install') >= 0 || line.indexOf('/bin/mkdir') >= 0) {
            this.bumpInstall(5, '创建目录…');
          } else if (line.indexOf('Downloading and installing Homebrew') >= 0) {
            this.bumpInstall(8, '下载 brew 本体（~123MB）…');
          } else if (line.indexOf('portable-git') >= 0) {
            if (line.indexOf('Downloading') >= 0) { this.bumpInstall(62, '下载 portable-git…'); }
            else if (line.indexOf('Pouring') >= 0) { this.bumpInstall(67, '解压 portable-git…'); }
          } else if (line.indexOf('Updating Homebrew') >= 0) {
            this.bumpInstall(72, '更新 Homebrew…');
          } else if (line.indexOf('portable-ruby') >= 0) {
            if (line.indexOf('Downloading') >= 0) { this.bumpInstall(80, '下载 portable-ruby…'); }
            else if (line.indexOf('Pouring') >= 0) { this.bumpInstall(85, '解压 portable-ruby…'); }
          } else if (line.indexOf('Installation successful') >= 0) {
            this.bumpInstall(98, '安装完成，配置环境…');
          }
          return;
        }
        // ── curl 汇总进度行（主下载大头；tty/非 tty 两种形态都覆盖）──
        //   形态：45  123M   45  55.8M ...（列1=%Total 列2=总量 列3=%已收）
        const curlMatch: RegExpMatchArray | null =
          line.match(/^(\d+)\s+([\d.]+[KMGT]?)\s+(\d+)\s+([\d.]+)/);
        if (curlMatch !== null) {
          const dlPct: number = parseInt(curlMatch[3]);
          const total: string = curlMatch[2];
          if (dlPct > 0 && dlPct <= 100 && this.installPct < 62) {
            // 主下载窗口 8→62%（后续 bottle 下载的 curl 行由里程碑压制不倒退）
            this.bumpInstall(8 + Math.round(dlPct * 0.54),
              total !== '' ? `下载 brew 本体 ${dlPct}%（共 ${total}）…` : `下载 brew 本体 ${dlPct}%…`);
            return;
          }
        }
        // ── bottle 哈希进度（####… 100.0%）——当前阶段小步推进 ──
        const barMatch: RegExpMatchArray | null = line.match(/^(#+)\s+([\d.]+)%/);
        if (barMatch !== null) {
          this.bumpInstall(this.installPct + 1, '');
          return;
        }
        // ── 收尾里程碑（非 ==> 行）──
        if (line.indexOf('unpaid volunteers') >= 0 || line.indexOf('Installing from the API') >= 0) {
          this.bumpInstall(88, '收尾…');
        } else if (line.indexOf('Already up-to-date') >= 0) {
          this.bumpInstall(93, '收尾…');
        } else if (line.indexOf('shellenv') >= 0 || line.indexOf('Next steps') >= 0) {
          this.bumpInstall(95, '配置终端环境…');
        }
      },
      (_ok: boolean, _d: string) => {
        this.installBusy = false;
        // 乐观翻转（反馈#2）：收尾里程碑≥88 → install.sh 确实走完——立即
        // 变"已安装"出全部 tab；refresh() 随后校准（失败路径会翻回 false）
        if (this.installPct >= 88) {
          this.brewInstalled = true;
          cachedBrewInstalled = true;
          cachedBrewScanned = true;
        }
        this.refresh();
        setTimeout(() => {
          if (this.brewInstalled) {
            this.installPct = 100; this.installStage = '安装完成';
            DevToast.ok($r('app.string.harmonybrew_1'));
            setTimeout(() => {
              this.installPct = -1; this.installStage = ''; this.installDl = '';
            }, 2000);
          } else {
            this.installPct = -1; this.installStage = ''; this.installDl = '';
            DevToast.show($r('app.string.harmonybrew_2'));
          }
        }, 600);
      });
  }

  private uninstallBrew(): void {
    DevConfirm.danger('卸载 HarmonyBrew', '将删除 ~/.harmonybrew 及全部已装包。', () => {
      this.installBusy = true;
      this.updateTarget = 'uninstall';
      DevTask.shell(`rm -rf '${HOME}/.harmonybrew' 2>&1; echo DONE`,
        (_t: string, _e: boolean) => {},
        (_ok: boolean, _d: string) => {
          this.installBusy = false;
          this.updateTarget = '';
          // 终端环境同步摘除（托管块的 HOMEBREW_*/MANPATH/INFOPATH 行 + PATH 段）
          DevEnvPaths.stripBrewEnv();
          // 审计 F-P0-2：重置 tap 信任标记（~/.harmonybrew 删了但标记还在
          // → 重装后 ensureApplied 早退 → 社区 tap 永不重建 → 社区源全灭）
          BrewTapService.reset();
          DevToast.ok($r('app.string.harmonybrew_3'));
          this.refresh();
        });
    }, '确认卸载');
  }

  // ═══ brew 常用操作 ═══

  /** 检查更新 / 全部升级 */
  private brewUpdate(doUpdate: boolean): void {
    if (this.installBusy) { return; }   // disabled 已拦截——防御双保险
    // 密封环境 + 绝对路径（DevTask shell 不读 .zshrc，裸调 brew 不在 PATH）；
    // 不接管道——tail 会吞退出码，失败也会被报成“已是最新”
    const verb: string = doUpdate ? 'upgrade' : 'update';
    const cmd: string = `export HOME='${HOME}' PATH='/usr/bin:/bin'; '${BREW}' ${verb} 2>&1`;
    this.installBusy = true;
    this.updateTarget = doUpdate ? 'update' : 'check';
    this.installLog = [`$ brew ${verb}`];
    DevTask.shell(cmd,
      (t: string, _e: boolean) => {
        if (t.trim() !== '') {
          this.installLog.push(t);
          if (this.installLog.length > 50) { this.installLog = this.installLog.slice(-30); }
        }
      },
      (ok: boolean, _d: string) => {
        this.installBusy = false;
        this.updateTarget = '';
        if (ok) { DevToast.ok(doUpdate ? '更新完成' : '已是最新'); }
        else { DevToast.show(doUpdate ? '更新失败' : '检查失败'); }
        this.refresh();
      });
  }
  // ═══ 软件仓库操作（相位模型：running→reconciling→徽标由库存刷新翻转） ═══

  /** formula/tap 名白名单（catalog 是远端数据，防注入进 shell） */
  private safePkgName(name: string): string {
    // 拒绝 -- 开头（选项注入）+ 字符白名单
    const clean: string = name.trim().replace(/[^a-zA-Z0-9@._+-]/g, '');
    if (clean.startsWith('-')) { return ''; }
    return clean;
  }

  private installFormulaByName(rawName: string): void {
    if (!this.brewInstalled) { DevToast.show($r('app.string.harmonybrew_4')); return; }
    if (this.installPhase !== '' || this.installBusy) { return; }
    const name: string = this.safePkgName(rawName);
    if (name === '') { return; }
    this.installPhase = `install:${name}`;
    this.installSource = this.selectedTap;   // 记住安装时所在源
    this.inlineError = '';
    this.installLog = [`$ brew install ${name}`];
    // 看门狗：300s 未完成标记超时（防 bottle 404 后 brew 回退源码编译无工具链永久卡）
    const t0: number = Date.now();
    const wdPhase: string = this.installPhase;
    setTimeout(() => {
      if (this.installPhase === wdPhase && Date.now() - t0 > 300000) {
        this.installPhase = '';
        this.installSource = '';
        this.inlineError = '安装超时（>300 秒）——bottle 可能不存在或无编译工具链';
      }
    }, 310000);
    // -y 预答：fork 对带依赖的安装弹 [y/n] 确认（真机实证 jq/oniguruma、
    // zstd+3依赖；无依赖包不弹）——app 侧 execAsync 无 stdin。BrewUI 对照：
    // macOS 官方 brew 无此提示、GUI 点击即确认（安装无弹窗）；fork 的 -y
    // 是官方机制（真机 2026-11-13 实证 `brew install zstd -y` 全程无交互）
    DevTask.shell(`${SEALED} '${BREW}' install ${name} -y 2>&1`,
      (t: string, _e: boolean) => {
        const clean: string = AnsiClean.clean(t);   // 剥 ANSI 色码（BrewUI ANSIParser 移植）
        // 诊断：安装输出打到 hilog（用户排查 lz4/zstd 安装问题）
        if (clean.trim() !== '') {
          console.info('[brew-install] ' + clean.substring(0, 200));
        }
        if (clean.trim() !== '') {
          this.installLog.push(clean);
          if (this.installLog.length > 120) { this.installLog = this.installLog.slice(-100); }
        }
      }, (ok: boolean, _d: string) => {
        console.info('[brew-install] DONE ok=' + ok + ' detail=' + _d + ' log_lines=' + this.installLog.length);
        if (ok) {
          // 乐观翻转（反馈#3）：brew 退出 0 = 已装（含依赖）——立即进已装集，
          // 详情按钮即切管理卡；reconciling 的 loadInstalled 随后校准真值
          if (!this.formulaInstalled(name)) {
            this.packages.push(name);
            this.installedPkgs.push({ name: name, version: '', installedOn: 0, asDependency: false, linked: false });
            cachedBrewPackages = this.packages;
            cachedInstalledPkgs = this.installedPkgs;
            this.rebuildRepoRows();
          }
          // reconciling：子进程已退出、库存未刷新完的空窗——徽标保持 busy
          this.installPhase = `reconciling:${name}`;
          this.installSource = '';
          this.loadInstalled();
        } else {
          this.installPhase = '';
          this.installSource = '';
          this.inlineError = this.installLog.length > 0 ? this.installLog[this.installLog.length - 1] : '安装失败';
          // 退出码非零≠真失败（级联/告警路径实测会谎报）——后台跑列表以查询
          // 为准：若包实际已装，settlePendingVerify 自动撤销这条失败提示
          this.pendingVerify = name;
          this.pendingVerifyIsUninstall = false;
          this.loadInstalled();
        }
      });
  }

  private uninstallFormula(pkg: string): void {
    if (this.installPhase !== '' || this.installBusy) { return; }
    const name: string = this.safePkgName(pkg);
    if (name === '') { return; }
    DevConfirm.danger(`卸载 ${name}`, '将从系统中移除此包。', () => {
      this.installPhase = `uninstall:${name}`;
      this.inlineError = '';
      this.installLog = [`$ brew uninstall ${name}`];
      DevTask.shell(`${SEALED} '${BREW}' uninstall ${name} 2>&1`,
        (t: string, _e: boolean) => {
          const clean: string = AnsiClean.clean(t);
          if (clean.trim() !== '') { this.installLog.push(clean); }
        },
        (ok: boolean, _d: string) => {
          if (ok) {
            // 乐观翻转：立即移出已装集（详情即切回安装卡）；loadInstalled 校准
            this.packages = this.packages.filter((n: string): boolean => n !== name);
            this.installedPkgs = this.installedPkgs.filter((p: InstalledPackage): boolean => p.name !== name);
            cachedBrewPackages = this.packages;
            cachedInstalledPkgs = this.installedPkgs;
            this.rebuildRepoRows();
            this.installPhase = `reconciling:${name}`;
            this.loadInstalled();
          } else {
            this.installPhase = '';
            this.inlineError = this.installLog.length > 0 ? this.installLog[this.installLog.length - 1] : '卸载失败';
            // 退出码非零≠真失败（级联依赖卸载实测退出非零但已卸）——后台
            // 列表校准：包已消失则 settlePendingVerify 清残留错误并刷新列表
            this.pendingVerify = name;
            this.pendingVerifyIsUninstall = true;
            this.loadInstalled();
          }
        });
    }, '确认卸载');
  }

  private upgradeFormula(pkg: string): void {
    if (this.installPhase !== '' || this.installBusy) { return; }
    const name: string = this.safePkgName(pkg);
    if (name === '') { return; }
    this.installPhase = `upgrade:${name}`;
    this.inlineError = '';
    this.installLog = [`$ brew upgrade ${name}`];
    DevTask.shell(`${SEALED} '${BREW}' upgrade ${name} -y 2>&1`,
      (t: string, _e: boolean) => {
        const clean: string = AnsiClean.clean(t);   // 剥 ANSI 色码（BrewUI ANSIParser 移植）
        // 诊断：安装输出打到 hilog（用户排查 lz4/zstd 安装问题）
        if (clean.trim() !== '') {
          console.info('[brew-install] ' + clean.substring(0, 200));
        }
        if (clean.trim() !== '') {
          this.installLog.push(clean);
          if (this.installLog.length > 120) { this.installLog = this.installLog.slice(-100); }
        }
      }, (ok: boolean, _d: string) => {
        if (ok) {
          this.installPhase = `reconciling:${name}`;
          this.installSource = '';
          this.loadInstalled();
          this.loadOutdated();
        } else {
          this.installPhase = '';
          this.inlineError = this.installLog.length > 0 ? this.installLog[this.installLog.length - 1] : '升级失败';
        }
      });
  }

  private upgradeAll(): void {
    if (this.installPhase !== '' || this.installBusy) { return; }
    if (this.outdatedPkgs.length === 0) { return; }
    DevConfirm.danger(`升级全部（${this.outdatedPkgs.length} 个）`, '将升级所有过时软件包。', () => {
      this.installPhase = 'upgradeAll';
      this.inlineError = '';
      this.installLog = ['$ brew upgrade'];
      DevTask.shell(`${SEALED} '${BREW}' upgrade -y 2>&1`,
        (t: string, _e: boolean) => {
          if (t.trim() !== '') {
            this.installLog.push(t);
            if (this.installLog.length > 120) { this.installLog = this.installLog.slice(-100); }
        }
        }, (ok: boolean, _d: string) => {
          if (ok) {
            this.installPhase = 'reconciling:all';
            this.loadInstalled();
            this.loadOutdated();
          } else {
            this.installPhase = '';
            this.inlineError = this.installLog.length > 0 ? this.installLog[this.installLog.length - 1] : '升级失败';
          }
        });
    }, '确认升级');
  }

  // ═══ Tab 切换（懒加载各 tab 数据） ═══

  private onTabEnter(idx: number): void {
    this.selectedFormula = '';   // 切 tab 清选中——右侧详情跟当前 tab 列表走（不残留上 tab 的选择）
    this.inlineError = '';      // 连带清错误（反馈#5：换上下文不留残）
    if (idx === 2) { this.loadInstalled(); }
    else if (idx === 3) { this.loadOutdated(); }
  }

  // ═══ 安装相位横幅（多页列表里"找得回"正在处理的包） ═══

  /** 当前相位的包名（'install:xz' → 'xz'） */
  private phasePkg(): string {
    const idx: number = this.installPhase.indexOf(':');
    return idx >= 0 ? this.installPhase.substring(idx + 1) : '';
  }

  private phaseLabel(): string {
    if (this.installPhase.indexOf('reconciling') === 0) { return '正在确认安装结果…'; }
    if (this.installPhase.indexOf('install:') === 0) { return `正在安装 ${this.phasePkg()}…`; }
    if (this.installPhase.indexOf('uninstall:') === 0) { return `正在卸载 ${this.phasePkg()}…`; }
    if (this.installPhase.indexOf('upgrade:') === 0) { return `正在升级 ${this.phasePkg()}…`; }
    if (this.installPhase === 'upgradeAll') { return `正在升级全部（${this.outdatedPkgs.length} 个）…`; }
    return '';
  }

  /** 选中公式（右侧详情跟随）。换选中即清上一轮操作错误（反馈#5：卸载
   * 失败的 inlineError 残留并显示到了下一个包的详情卡里） */
  private selectFormula(name: string): void {
    this.selectedFormula = name;
    this.inlineError = '';
  }

  /** 定位到正在处理的包（把列表过滤到它——400+ 页里一键找回） */
  private jumpToInstalling(): void {
    const name: string = this.phasePkg();
    if (name === '' || name === 'all') { return; }   // upgradeAll 无单包可定位
    // 无论当前在哪个 tab，都切回软件仓库（安装发起的地方）
    if (this.tab !== 1) { this.tab = 1; }
    // 源探测（修复 #3：卸载/升级相位不记源导致定位落到错误源——按包在
    // 目录中的实际归属探测；两源都有时优先安装发起源）
    this.selectedTap = this.pkgSourceOf(name);
    // 搜索定位
    this.search = name;
    this.searchApplied = name;
    this.rebuildRepoRows();
    this.currentPage = 1;
    this.selectFormula(name);
  }

  /** 包所在源：仅社区目录有→社区；仅官方目录有→官方；两源都有/都没有→安装发起源兜底 */
  private pkgSourceOf(name: string): string {
    let inCore: boolean = false;
    let inTap: boolean = false;
    for (let i = 0; i < this.formulas.length && !inCore; i++) {
      if (this.formulas[i].name === name) { inCore = true; }
    }
    for (let i = 0; i < this.ohpcdRows.length && !inTap; i++) {
      if (this.ohpcdRows[i].name === name) { inTap = true; }
    }
    if (inTap && !inCore) { return KEY_OHPCD; }
    if (inCore && !inTap) { return ''; }
    return this.installSource;
  }

  @Builder
  buildInstallingBanner() {
    if (this.installPhase !== '') {
      Row({ space: 8 }) {
        LoadingProgress().width(14).height(14).color(DevTheme.PRIMARY)
        Text(this.phaseLabel())
          .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.PRIMARY)
          .layoutWeight(1)
        Text($r('app.string.harmonybrew_5'))
          .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.PRIMARY)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(DevTheme.RADIUS_SM)
          .border({ width: 1, color: DevTheme.PRIMARY })
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(DevTheme.RADIUS_MD)
      .backgroundColor(DevTheme.BG_ACCENT_PRIMARY)
      .onClick(() => { this.jumpToInstalling(); })
    }
  }

  // ═══ 软件仓库：显示集构建（源 × 搜索 × 热门排序） ═══

  /** 搜索防抖 300ms（BrewUI 同款：新输入自动顶替旧计时） */
  private onSearchInput(v: string): void {
    this.search = v;
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); }
    this.searchTimer = setTimeout(() => {
      this.searchTimer = -1;
      this.searchApplied = this.search;
      this.currentPage = 1;
      this.rebuildRepoRows();
    }, 300);
  }

  /**
   * 显示集重建。无搜索：官方源按下载量降序（无统计字母序尾随）= 热门视图；
   * 有搜索：全量过滤限 50。社区源/官方源同构。
   */
  private rebuildRepoRows(): void {
    const rows: BrewFormulaInfo[] = this.selectedTap === '' ? this.formulas : this.ohpcdRows;
    const kw: string = this.searchApplied.trim().toLowerCase();
    if (kw !== '') {
      const out: BrewFormulaInfo[] = [];
      for (let i = 0; i < rows.length && out.length < 50; i++) {
        const f: BrewFormulaInfo = rows[i];
        if (f.name.toLowerCase().indexOf(kw) >= 0 || f.desc.toLowerCase().indexOf(kw) >= 0) {
          out.push(f);
        }
      }
      this.displayedRows = out;
    } else if (this.selectedTap === '' && BrewStatsService.hasData()) {
      // 热门排序：有统计的按量降序，无统计的按字母序尾随（稳定副本，不动源数组）
      const withStat: BrewFormulaInfo[] = [];
      const noStat: BrewFormulaInfo[] = [];
      for (let i = 0; i < rows.length; i++) {
        if (BrewStatsService.countOf(rows[i].name) > 0) { withStat.push(rows[i]); }
        else { noStat.push(rows[i]); }
      }
      withStat.sort((a: BrewFormulaInfo, b: BrewFormulaInfo): number =>
        BrewStatsService.countOf(b.name) - BrewStatsService.countOf(a.name));
      noStat.sort((a: BrewFormulaInfo, b: BrewFormulaInfo): number => a.name < b.name ? -1 : 1);
      this.displayedRows = withStat.concat(noStat);
    } else {
      this.displayedRows = rows.slice();
    }
    this.syncSelection();
  }

  /** 选中同步（BrewUI 规则）：选中不在显示集 → 置空（渲染回落第一行，右侧永不出空白） */
  private syncSelection(): void {
    if (this.selectedFormula === '') { return; }
    for (let i = 0; i < this.displayedRows.length; i++) {
      if (this.displayedRows[i].name === this.selectedFormula) { return; }
    }
    this.selectedFormula = '';
    this.inlineError = '';
  }

  /** 当前页行 */
  private pagedRows(): BrewFormulaInfo[] {
    const start: number = (this.currentPage - 1) * this.pageSize;
    return this.displayedRows.slice(start, start + this.pageSize);
  }

  /** 渲染用选中（空选中回落当前 tab 列表第一行——各 tab 用各自的列表） */
  private effectiveSelected(): string {
    if (this.selectedFormula !== '') { return this.selectedFormula; }
    if (this.tab === 2) {
      const rows: InstalledPackage[] = this.pagedInstalledRows();
      return rows.length > 0 ? rows[0].name : '';
    }
    if (this.tab === 3) {
      return this.outdatedPkgs.length > 0 ? this.outdatedPkgs[0].name : '';
    }
    const page: BrewFormulaInfo[] = this.pagedRows();
    return page.length > 0 ? page[0].name : '';
  }

  /** 详情对象（右列不自己加载数据——目录全集查 + 已装信息兜底；无选中=空对象） */
  private detailFormula(): BrewFormulaInfo {
    const name: string = this.effectiveSelected();
    if (name === '') { return EMPTY_FORMULA; }
    const f: BrewFormulaInfo | null = this.catalogOf(name);
    if (f !== null) { return f; }
    // 目录未收录（如用户终端装的包）——从已装信息构建最小详情
    for (let i = 0; i < this.installedPkgs.length; i++) {
      if (this.installedPkgs[i].name === name) {
        const inst: InstalledPackage = this.installedPkgs[i];
        return { name: inst.name, desc: '', version: inst.version, tap: '', homepage: '',
          license: '', executables: [], dependencies: [], caveats: '', kegOnly: false, deprecated: false };
      }
    }
    return EMPTY_FORMULA;
  }

  /** 是否有有效详情（空选中时 false——渲染占位） */
  private hasDetail(): boolean {
    return this.effectiveSelected() !== '';
  }

  private installedVersionOf(name: string): string {
    for (let i = 0; i < this.installedPkgs.length; i++) {
      if (this.installedPkgs[i].name === name) { return this.installedPkgs[i].version; }
    }
    return '';
  }

  private isOutdated(name: string): boolean {
    for (let i = 0; i < this.outdatedPkgs.length; i++) {
      if (this.outdatedPkgs[i].name === name) { return true; }
    }
    return false;
  }

  /** 标题（状态化：热门/搜索结果/无匹配） */
  private repoTitle(): string {
    if (this.searchApplied.trim() !== '') {
      const kw: string = this.searchApplied.trim();
      return this.displayedRows.length > 0 ? `“${kw}”的结果` : `“${kw}”无匹配`;
    }
    if (this.selectedTap !== '') { return '社区源目录'; }
    return BrewStatsService.hasData() ? `热门（近 ${BrewStatsService.statDays()} 天下载）` : '官方源目录';
  }

  private formatTime(ms: number): string {
    if (ms <= 0) { return ''; }
    const d: Date = new Date(ms);
    const mo: string = `${d.getMonth() + 1}`.padStart(2, '0');
    const da: string = `${d.getDate()}`.padStart(2, '0');
    return `${d.getFullYear()}-${mo}-${da}`;
  }

  // ═══ 源切换（双固定源） ═══

  private tapOptions(): string[] {
    return [SRC_CORE, SRC_COMMUNITY];
  }

  private tapIndex(): number {
    return this.selectedTap === '' ? 0 : 1;
  }

  private selectTap(label: string): void {
    this.selectedTap = label === SRC_CORE ? '' : KEY_OHPCD;
    this.currentPage = 1;
    this.selectedFormula = '';
    this.inlineError = '';
    this.rebuildRepoRows();
  }

  build() {
    Column() {
      DevPageHeader({ title: 'HarmonyBrew', subtitle: '鸿蒙版 Homebrew', showDivider: false })
        .margin({ bottom: 12 })

      DevSegmentTabs({
        options: this.brewInstalled ? ['包管理器', '软件仓库', '已安装', '可升级'] : ['包管理器'],
        active: this.brewInstalled ? this.tab : 0,
        onChange: (idx: number) => {
          if (this.brewInstalled) {
            this.tab = idx;
            this.onTabEnter(idx);
          }
        },
      })
      .margin({ bottom: 4 })

      Column({ space: 12 }) {
        if (!this.brewInstalled) {
          this.buildUninstalled()
        } else if (this.tab === 0) {
          this.buildManagerTab()
        } else if (this.tab === 1) {
          this.buildRepoTab()
        } else if (this.tab === 2) {
          this.buildInstalledTab()
        } else {
          this.buildUpgradesTab()
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 8, bottom: 16 })
  }

  // ═══ 未安装：简洁状态页 ═══

  @Builder
  buildUninstalled() {
    Column() {
      DevCard({ title: '', subtitle: '', accent: '', pad: 24 }) {
        Column({ space: 12 }) {
          Text($r('app.string.harmonybrew_6'))
            .fontSize(DevTheme.FS_H3).fontColor(DevTheme.TEXT_PRIMARY)
          Text($r('app.string.harmonybrew_7'))
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
          if (this.installPct >= 0 && this.installPct < 100) {
            // 进度条+阶段文本（与其他安装中行一致——DevRowProgress 公共组件）
            DevRowProgress({
              progress: this.installPct,
              trailingText: `${this.installPct}%`,
              trailingWidth: 40,
              subTrailingText: this.installDl,
              subTrailingWidth: 90,
            })
            Text(this.installStage)
              .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
          } else if (this.installPct === 100) {
            Text($r('app.string.harmonybrew_8'))
              .fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_PRIMARY)
          }
          DevBtn({
            text: this.installBusy ? '安装中…' : '安装',
            buttonSize: 'normal',
            // 反馈#1：本体安装中途不可再点（防误触二次启动 install.sh；
            // 本体安装是装机级操作，中途取消留半装状态风险高——先禁用，
            // 取消按钮留作后续增强，需 shellCancellable 改造）
            loading: this.installBusy,
            disabled: this.installBusy,
            onTap: () => { if (!this.installBusy) { this.installBrew(); } },
          }).margin({ top: 8 })
        }.width('100%').alignItems(HorizontalAlign.Center)
      }
    }.width('100%')
  }


  // ═══ Tab 1: 包管理器 ═══

  @Builder
  buildManagerTab() {
    Column({ space: 14 }) {
      DevCard({ title: 'HarmonyBrew', subtitle: '', accent: this.brewInstalled ? '' : DevTheme.DANGER, pad: 12 }) {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            DevStatusDot({ status: this.brewInstalled ? 1 : 3 })
            Text(this.brewInstalled ? '已安装' : '未安装')
              .fontSize(DevTheme.FS_BODY)
              .fontColor(this.brewInstalled ? DevTheme.TEXT_PRIMARY : DevTheme.DANGER)
          }.width('100%')
          if (!this.brewInstalled) {
            Text($r('app.string.harmonybrew_9'))
              .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
          }
          if (this.brewInstalled) {
            DevKVRow({ k: '版本', v: this.brewVersion, copyable: true, mono: true })
            DevKVRow({ k: '安装路径', v: '~/.harmonybrew', copyable: false, mono: true })
            DevKVRow({ k: 'Tap', v: this.tapName !== '' ? this.tapName : 'harmony/ohos', copyable: false, mono: true })
            if (this.tapRepo !== '') {
              DevKVRow({ k: 'Tap 仓库', v: this.tapRepo, copyable: true, mono: true })
            }
            // PATH 优先开关（brew 段前置——brew 安装的命令优先于其他环境命中）
            Row({ space: 10 }) {
              Text($r('app.string.harmonybrew_10'))
                .fontSize(DevTheme.FS_BODY)
                .fontColor(DevTheme.TEXT_PRIMARY)
              Text($r('app.string.harmonybrew_11'))
                .fontSize(DevTheme.FS_CAPTION)
                .fontColor(DevTheme.TEXT_TERTIARY)
                .layoutWeight(1)
              IBestSwitch({
                value: this.brewPriority,
                switchSize: 20,
                activeColor: DevTheme.SELECT,
                inactiveColor: DevTheme.BORDER_STRONG,
                onChange: (v: boolean | IBestStringNumber) => {
                  this.toggleBrewPriority(v as boolean);
                },
              })
            }
            .width('100%')
            .padding({ top: 2, bottom: 2 })
          }

          Row({ space: 8 }) {
            if (!this.brewInstalled) {
              DevBtn({
                text: this.installBusy ? '安装中…' : '安装',
                buttonSize: 'normal',
                loading: this.installBusy,
                disabled: this.installBusy,
                onTap: () => { if (!this.installBusy) { this.installBrew(); } },
              })
            } else {
              // 三键互斥：installBusy 时全部 disabled + 正在执行的那个 loading
              DevBtn({
                text: this.installBusy && this.updateTarget === 'check' ? '检查中…' : '检查更新',
                buttonSize: 'normal', plain: true,
                loading: this.installBusy && this.updateTarget === 'check',
                disabled: this.installBusy,
                onTap: () => { this.brewUpdate(false); },
              })
              DevBtn({
                text: this.installBusy && this.updateTarget === 'update' ? '更新中…' : '全部升级',
                buttonSize: 'normal', plain: true,
                loading: this.installBusy && this.updateTarget === 'update',
                disabled: this.installBusy,
                onTap: () => { this.brewUpdate(true); },
              })
              DevBtn({
                text: this.installBusy && this.updateTarget === 'uninstall' ? '卸载中…' : '卸载',
                buttonSize: 'normal', danger: true,
                loading: this.installBusy && this.updateTarget === 'uninstall',
                disabled: this.installBusy,
                onTap: () => { if (!this.installBusy) { this.uninstallBrew(); } },
              })
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      // ── 终端首次使用社区源提示（trust 割据：app 侧已自动信任；终端独立存储） ──
      if (this.tapName !== '') {
        DevCard({ title: '终端首次使用社区源', subtitle: '', accent: DevTheme.WARNING, pad: 10 }) {
          Column({ space: 8 }) {
            Text($r('app.string.harmonybrew_12'))
              .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
              .width('100%')
            DevCommandBlock({ command: `brew trust ${this.tapName}` })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
    }
    .width('100%')
  }
  // ═══ Tab 2: 软件仓库（左列表右详情） ═══

  @Builder
  buildRepoTab() {
    Column({ space: 8 }) {
      DevInput({ value: this.search, placeholder: '搜索软件包（名称/描述）…', mono: false,
        onChange: (v: string) => { this.onSearchInput(v); } })

      Row({ space: 6 }) {
        DevSegmentTabs({
          options: this.tapOptions(),
          active: this.tapIndex(),
          onChange: (idx: number) => {
            const names: string[] = this.tapOptions();
            this.selectTap(names[idx] ?? '');
          },
        }).layoutWeight(1)
      }.width('100%')

      this.buildInstallingBanner()

      // 状态化标题 + 计数
      Row() {
        Text(this.repoTitle())
          .fontSize(DevTheme.FS_H3).fontWeight(FontWeight.Medium).fontColor(DevTheme.TEXT_PRIMARY)
        Blank()
        if (this.selectedTap === '' && this.formulasLoading) {
          LoadingProgress().width(14).height(14).color(DevTheme.PRIMARY)
        } else if (this.selectedTap !== '' && this.ohpcdLoading) {
          LoadingProgress().width(14).height(14).color(DevTheme.PRIMARY)
        } else if (this.displayedRows.length > 0) {
          Text(`共 ${this.displayedRows.length} 个`)
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
        }
      }.width('100%')

      // ── 主区三分支（已安装/可升级/通用工具页同规）：列表未就绪→全宽
      // 加载/空态（无右侧详情——防切 tab 时列表没出来空详情卡先闪现）；
      // 有行→主从布局 ──
      if (this.displayedRows.length === 0) {
        Column({ space: 8 }) {
          if (this.selectedTap === '' && this.formulasLoading) {
            Row({ space: 8 }) {
              LoadingProgress().width(16).height(16).color(DevTheme.PRIMARY)
              Text($r('app.string.harmonybrew_13'))
                .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
            }
          } else if (this.selectedTap !== '' && this.ohpcdLoading) {
            Row({ space: 8 }) {
              LoadingProgress().width(16).height(16).color(DevTheme.PRIMARY)
              Text($r('app.string.harmonybrew_14')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
            }
          } else {
            Text(this.searchApplied.trim() !== '' ? '没有匹配的软件包'
              : (this.selectedTap !== '' && this.ohpcdRows.length === 0 ? '社区源暂无数据（服务筹备中）' : '没有匹配的软件包'))
              .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
          }
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Row({ space: 10 }) {
          Column({ space: 4 }) {
            Scroll() {
              Column({ space: 3 }) {
                ForEach(this.pagedRows(), (f: BrewFormulaInfo) => {
                  BrewListRow({
                    name: f.name, desc: f.desc, ver: f.version,
                    meta: this.repoRowMeta(f),
                    selected: f.name === this.effectiveSelected(),
                    installed: this.formulaInstalled(f.name),
                    canUpgrade: this.isOutdated(f.name),
                    installing: this.installPhase === `install:${f.name}`
                      || this.installPhase === `upgrade:${f.name}`,
                    deprecated: f.deprecated,
                    onRowClick: () => { this.selectFormula(f.name); },
                  })
                }, (f: BrewFormulaInfo) => `${f.name}_${this.formulaInstalled(f.name)}_${this.isOutdated(f.name)}`)
              }.width('100%')
            }
            .width('100%').layoutWeight(1)
            .align(Alignment.TopStart)

            if (this.displayedRows.length > this.pageSize) {
              DevPagination({
                currentPage: this.currentPage,
                totalItems: this.displayedRows.length,
                itemsPerPage: this.pageSize,
                onChange: (p: number) => { this.currentPage = p; },
              })
            }
          }
          .width('38%').height('100%')

          Scroll() {
            this.buildFormulaDetail()
          }
          .layoutWeight(1).height('100%')
          .align(Alignment.TopStart)
          .backgroundColor(DevTheme.BG_CARD)
          .borderRadius(DevTheme.RADIUS_MD)
          .border({ width: 1, color: DevTheme.BORDER })
          .padding({ bottom: 16 })   // 底部留白——不与应用底边贴死
        }
        .width('100%')
        .layoutWeight(1)
        .onAreaChange((_o: Area, n: Area) => {
          const h: number = n.height as number;
          if (h > 100) { this.pageSize = PageCalc.computePageSize(h, ROW_H); }
        })
      }
    }
    .width('100%').height('100%')
  }

  /** 列表行元信息副行（下载量；无统计不渲染） */
  private repoRowMeta(f: BrewFormulaInfo): string {
    const n: number = BrewStatsService.countOf(f.name);
    return n > 0 ? `近7天 ${n} 次` : '';
  }

  // ═══ 详情面板（右列；右列不自己加载数据——显示集查选中） ═══

  @Builder
  buildFormulaDetail() {
    Column({ space: 12 }) {
      if (!this.hasDetail()) {
        Column() {
          Text($r('app.string.harmonybrew_15'))
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
        }.width('100%').padding(24)
      } else {
        this.buildFormulaDetailBody()
      }
    }.width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 28 })   // 底部留白——不与应用底边贴死
  }

  @Builder
  buildFormulaDetailBody() {
    Column({ space: 14 }) {
      // ── Hero ──
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(this.detailFormula().name)
            .fontSize(DevTheme.FS_H1).fontWeight(FontWeight.Bold).fontColor(DevTheme.TEXT_PRIMARY)
            .layoutWeight(1)
          if (this.detailFormula().deprecated) {
            DevChip({ text: '已弃用', tone: 'danger', mono: false })
          }
          if (this.isOutdated(this.detailFormula().name)) {
            DevChip({ text: '可升级', tone: 'warning', mono: false })
          }
          if (this.formulaInstalled(this.detailFormula().name)) {
            DevChip({ text: '已装', tone: 'success', mono: false })
          } else {
            DevChip({ text: this.selectedTap !== '' ? '社区源' : '官方源', tone: 'neutral', mono: false })
          }
        }.width('100%')
        if (this.detailFormula().desc !== '') {
          Text(this.detailFormula().desc)
            .fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_TERTIARY)
            .width('100%')
        }
      }.width('100%')

      // ── 键值区（DevCard 分节——与应用主体规范一致） ──
      DevCard({ title: '详情', subtitle: '', accent: '', pad: 12 }) {
      Column({ space: 6 }) {
        DevKVRow({ k: '最新版本', v: this.detailFormula().version, copyable: true, mono: true })
        if (this.formulaInstalled(this.detailFormula().name)) {
          DevKVRow({ k: '已装版本', v: this.installedVersionOf(this.detailFormula().name) !== ''
            ? this.installedVersionOf(this.detailFormula().name) : '未知', copyable: true, mono: true })
        }
        if (BrewStatsService.countOf(this.detailFormula().name) > 0) {
          DevKVRow({ k: `近${BrewStatsService.statDays()}天下载`, v: `${BrewStatsService.countOf(this.detailFormula().name)}`,
            copyable: false, mono: false })
        }
        if (this.detailFormula().license !== '') {
          DevKVRow({ k: '许可证', v: this.detailFormula().license, copyable: true, mono: true })
        }
        if (this.detailFormula().tap !== '') {
          DevKVRow({ k: '来源', v: this.detailFormula().tap, copyable: true, mono: true })
        }
        if (this.detailFormula().homepage !== '') {
          DevKVRow({ k: '主页', v: this.detailFormula().homepage, copyable: true, mono: true })
        }
        if (this.detailFormula().kegOnly) {
          DevKVRow({ k: 'Keg-only', v: '不链接到 PATH（需手动引用）', copyable: false, mono: false })
        }
      }.width('100%')
      }

      // ── 依赖 ──
      if (this.detailFormula().dependencies.length > 0) {
        DevCard({ title: `依赖（${this.detailFormula().dependencies.length}）`, subtitle: '', accent: '', pad: 12 }) {
        Column({ space: 6 }) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.detailFormula().dependencies, (d: string) => {
              Text(d)
                .fontSize(DevTheme.FS_CAPTION).fontFamily(DevTheme.MONO_FONT).fontColor(DevTheme.TEXT_SECONDARY)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(DevTheme.RADIUS_SM)
                .backgroundColor(DevTheme.BG_ACCENT_PRIMARY)
                .margin({ right: 6, bottom: 6 })
            }, (d: string) => d)
          }.width('100%')
        }.width('100%')
        }
      }

      // ── 提供的命令（executables——免 shell 的"文件清单"数据源） ──
      if (this.detailFormula().executables.length > 0) {
        DevCard({ title: `提供命令（${this.detailFormula().executables.length}）`, subtitle: '', accent: '', pad: 12 }) {
        Column({ space: 6 }) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.detailFormula().executables, (e: string) => {
              Text(e)
                .fontSize(DevTheme.FS_CAPTION).fontFamily(DevTheme.MONO_FONT).fontColor(DevTheme.TEXT_SECONDARY)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(DevTheme.RADIUS_SM)
                .backgroundColor(DevTheme.BG_ACCENT_PRIMARY)
                .margin({ right: 6, bottom: 6 })
            }, (e: string) => e)
          }.width('100%')
        }.width('100%')
        }
      }

      // ── 安装提示（caveats） ──
      if (this.detailFormula().caveats !== '') {
        DevCard({ title: '安装提示', subtitle: '', accent: DevTheme.WARNING, pad: 10 }) {
          Text(this.detailFormula().caveats)
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_SECONDARY)
            .fontFamily(DevTheme.MONO_FONT)
            .width('100%')
        }
      }

      // ── 操作区（未装=安装；已装=升级/卸载；命令块可复制；按钮左对齐） ──
      if (!this.formulaInstalled(this.detailFormula().name)) {
        DevCard({ title: '安装', subtitle: '', accent: '', pad: 12 }) {
        Column({ space: 10 }) {
          DevCommandBlock({ command: `brew install ${this.detailFormula().name}`, footnote: '安装此软件包' })
            .width('100%')
          DevBtn({
            text: this.installPhase === `install:${this.detailFormula().name}` ? '安装中…'
              : this.installPhase.indexOf('reconciling') === 0 ? '确认安装结果…' : '安装',
            buttonSize: 'normal',
            loading: this.installPhase === `install:${this.detailFormula().name}`
              || this.installPhase.indexOf('reconciling') === 0,
            disabled: this.installPhase !== '' || this.installBusy,
            onTap: () => { this.installFormulaByName(this.detailFormula().name); },
          }).width('100%')
          if (this.inlineError !== '') {
            Text(this.inlineError)
              .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.DANGER)
              .width('100%').padding({ top: 4 })
              .onClick(() => { copyText(this.inlineError); })
          }
        }.width('100%')
        }
      } else {
        DevCard({ title: '管理', subtitle: '', accent: '', pad: 12 }) {
        Column({ space: 10 }) {
          if (this.isOutdated(this.detailFormula().name)) {
            DevCommandBlock({ command: `brew upgrade ${this.detailFormula().name}`, footnote: '升级此软件包' })
              .width('100%')
          }
          DevCommandBlock({ command: `brew uninstall ${this.detailFormula().name}`, footnote: '卸载此软件包' })
            .width('100%')
          Row({ space: 10 }) {
            if (this.isOutdated(this.detailFormula().name)) {
              DevBtn({
                text: this.installPhase === `upgrade:${this.detailFormula().name}` ? '升级中…' : '升级',
                buttonSize: 'normal', plain: true,
                loading: this.installPhase === `upgrade:${this.detailFormula().name}`,
                disabled: this.installPhase !== '' || this.installBusy,
                onTap: () => { this.upgradeFormula(this.detailFormula().name); },
              }).layoutWeight(1)
            }
            DevBtn({
              text: this.installPhase === `uninstall:${this.detailFormula().name}` ? '卸载中…' : '卸载',
              buttonSize: 'normal', danger: true,
              loading: this.installPhase === `uninstall:${this.detailFormula().name}`,
              disabled: this.installPhase !== '' || this.installBusy,
              onTap: () => { this.uninstallFormula(this.detailFormula().name); },
            }).layoutWeight(1)
          }.width('100%')
          if (this.inlineError !== '') {
            Text(this.inlineError)
              .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.DANGER)
              .width('100%').padding({ top: 4 })
              .onClick(() => { copyText(this.inlineError); })
          }
        }.width('100%')
        }
      }
    }.width('100%')
  }

  // ═══ Tab 3: 已安装（brew list --json=v2 结构化） ═══

  private filteredInstalled(): InstalledPackage[] {
    const kw: string = this.installedSearch.trim().toLowerCase();
    if (kw === '') { return this.installedPkgs; }
    const out: InstalledPackage[] = [];
    for (let i = 0; i < this.installedPkgs.length; i++) {
      if (this.installedPkgs[i].name.toLowerCase().indexOf(kw) >= 0) { out.push(this.installedPkgs[i]); }
    }
    return out;
  }

  private pagedInstalledRows(): InstalledPackage[] {
    const all: InstalledPackage[] = this.filteredInstalled();
    const start: number = (this.currentPage - 1) * this.pageSize;
    return all.slice(start, start + this.pageSize);
  }

  /** 已装包的目录信息（详情富化/行描述用；未收录返回 null） */
  /** 目录索引（懒建 Map——真机实证点击卡顿根因：线性扫 4721 formula ×
   *  详情 18 处 + 已装行 desc 12 处 ≈ 每渲染 14 万次比较）。签名 = 双目录
   *  长度：读长度即注册 @State 属性依赖——目录到达/更新自动失效重建，
   *  详情与行刷新语义不变 */
  private catalogIdx: Map<string, BrewFormulaInfo> = new Map<string, BrewFormulaInfo>();
  private idxFLen: number = -1;
  private idxOLen: number = -1;

  private catalogOf(name: string): BrewFormulaInfo | null {
    if (this.formulas.length !== this.idxFLen || this.ohpcdRows.length !== this.idxOLen) {
      this.idxFLen = this.formulas.length;
      this.idxOLen = this.ohpcdRows.length;
      const m: Map<string, BrewFormulaInfo> = new Map<string, BrewFormulaInfo>();
      for (let i = 0; i < this.formulas.length; i++) { m.set(this.formulas[i].name, this.formulas[i]); }
      for (let i = 0; i < this.ohpcdRows.length; i++) { m.set(this.ohpcdRows[i].name, this.ohpcdRows[i]); }
      this.catalogIdx = m;
    }
    const f: BrewFormulaInfo | undefined = this.catalogIdx.get(name);
    return f !== undefined ? f : null;
  }

  private installedDesc(name: string): string {
    const f: BrewFormulaInfo | null = this.catalogOf(name);
    return f !== null ? f.desc : '';
  }

  private installedRowMeta(p: InstalledPackage): string {
    const parts: string[] = [];
    if (p.installedOn > 0) { parts.push(this.formatTime(p.installedOn)); }
    if (p.asDependency) { parts.push('依赖引入'); }
    return parts.join(' · ');
  }

  @Builder
  buildInstalledTab() {
    Column({ space: 8 }) {
      DevInput({ value: this.installedSearch, placeholder: '搜索已安装的软件包…', mono: false,
        onChange: (v: string) => { this.installedSearch = v; this.currentPage = 1; } })

      this.buildInstallingBanner()

      // 空态提示行（非空时不渲染——tab 名已表达'已安装'语义）
      if (this.installedPkgs.length === 0 && !this.installedLoading) {
        Column({ space: 8 }) {
          Text($r('app.string.harmonybrew_16'))
            .fontSize(DevTheme.FS_H3).fontColor(DevTheme.TEXT_TERTIARY)
          Text($r('app.string.harmonybrew_17'))
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
        }
        .width('100%')
        .padding(24)
        .alignItems(HorizontalAlign.Center)
      } else if (this.installedLoading) {
        Row({ space: 8 }) {
          LoadingProgress().width(14).height(14).color(DevTheme.PRIMARY)
        }.padding(16)
      }

      // 主从布局只在有行时渲染（对齐可升级 tab 三分支）——加载中列表为空
      // 时不再渲染空详情面板（反馈：切到已安装先空白面板闪一会才隐藏——
      // 期望：一开始就隐藏，清单出来才显示；加载态由上方 spinner 表达）
      if (this.installedPkgs.length > 0) {
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Scroll() {
            Column({ space: 3 }) {
              ForEach(this.pagedInstalledRows(), (p: InstalledPackage) => {
                BrewListRow({
                  name: p.name, desc: this.installedDesc(p.name),
                  ver: p.version, meta: this.installedRowMeta(p),
                  selected: p.name === this.effectiveSelected(),
                  installed: true,
                  canUpgrade: this.isOutdated(p.name),
                  installing: this.installPhase === `install:${p.name}`
                    || this.installPhase === `upgrade:${p.name}`
                    || this.installPhase === `uninstall:${p.name}`,
                  deprecated: false,
                  onRowClick: () => { this.selectFormula(p.name); },
                })
              }, (p: InstalledPackage) => `${p.name}_${p.version}_${this.isOutdated(p.name)}`)
            }.width('100%')
          }
          .width('100%').layoutWeight(1)
          .align(Alignment.TopStart)

          if (this.filteredInstalled().length > 0) {
            DevPagination({
              currentPage: this.currentPage,
              totalItems: this.filteredInstalled().length,
              itemsPerPage: this.pageSize,
              onChange: (p: number) => { this.currentPage = p; },
            })
          }
        }
        .width('38%').height('100%')

        Scroll() {
          this.buildFormulaDetail()
        }
        .layoutWeight(1).height('100%')
        .align(Alignment.TopStart)
        .backgroundColor(DevTheme.BG_CARD)
        .borderRadius(DevTheme.RADIUS_MD)
        .border({ width: 1, color: DevTheme.BORDER })
        .padding({ bottom: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .onAreaChange((_o: Area, n: Area) => {
        const h: number = n.height as number;
        if (h > 100) { this.pageSize = PageCalc.computePageSize(h, ROW_H); }
      })
      }
    }
    .width('100%').height('100%')
  }

  // ═══ Tab 4: 可升级（brew outdated；brew 自己判） ═══

  @Builder
  buildUpgradesTab() {
    Column({ space: 8 }) {
      // 标题不渲染（tab 名已表达"可升级"语义——与已安装 tab 同规；计数已
      // 表达在"全部升级（N 个）"按钮上），此行退化为右对齐操作栏
      Row() {
        Blank()
        DevBtn({
          text: '刷新', buttonSize: 'mini', plain: true,
          loading: this.outdatedLoading,
          disabled: this.outdatedLoading || this.installPhase !== '' || this.installBusy,
          onTap: () => { this.loadOutdated(); },
        })
        DevBtn({
          text: this.installPhase === 'upgradeAll' ? '升级中…'
            : this.installPhase.indexOf('reconciling') === 0 ? '确认结果…'
            : (this.outdatedPkgs.length > 0 ? '全部升级（' + this.outdatedPkgs.length + '）' : '全部升级'),
          buttonSize: 'mini',
          disabled: this.outdatedPkgs.length === 0 || this.installPhase !== '' || this.installBusy,
          loading: this.installPhase === 'upgradeAll' || this.installPhase.indexOf('reconciling') === 0,
          onTap: () => { this.upgradeAll(); },
        }).margin({ left: 8 })
      }.width('100%')

      this.buildInstallingBanner()

      if (this.outdatedLoading) {
        Row({ space: 8 }) {
          LoadingProgress().width(16).height(16).color(DevTheme.PRIMARY)
          Text($r('app.string.harmonybrew_18')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
        }.padding(20)
      } else if (this.outdatedPkgs.length === 0) {
        Column({ space: 8 }) {
          Text($r('app.string.harmonybrew_19')).fontSize(DevTheme.FS_H3).fontColor(DevTheme.TEXT_PRIMARY)
          Text($r('app.string.harmonybrew_20')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
        }.width('100%').padding(24).alignItems(HorizontalAlign.Center)
      } else {
        DevCommandBlock({ command: 'brew upgrade', footnote: '升级全部 ' + this.outdatedPkgs.length + ' 个过时软件包' })

        Row({ space: 10 }) {
          Column({ space: 4 }) {
            Scroll() {
              Column({ space: 3 }) {
                ForEach(this.outdatedPkgs, (o: OutdatedEntry) => {
                  BrewListRow({
                    name: o.name, desc: this.installedDesc(o.name),
                    ver: o.currentVersion,
                    meta: o.installedVersion !== '' ? o.installedVersion + ' → ' + o.currentVersion : '',
                    selected: o.name === this.effectiveSelected(),
                    installed: true, canUpgrade: true,
                    installing: this.installPhase === 'upgrade:' + o.name || this.installPhase === 'upgradeAll',
                    deprecated: false,
                    onRowClick: () => { this.selectFormula(o.name); },
                  })
                }, (o: OutdatedEntry) => o.name + '_' + o.currentVersion)
              }.width('100%')
            }
            .width('100%').layoutWeight(1)
            .align(Alignment.TopStart)
          }
          .width('38%').height('100%')

          Scroll() {
            this.buildFormulaDetail()
          }
          .layoutWeight(1).height('100%')
          .align(Alignment.TopStart)
          .backgroundColor(DevTheme.BG_CARD)
          .borderRadius(DevTheme.RADIUS_MD)
          .border({ width: 1, color: DevTheme.BORDER })
          .padding({ bottom: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .onAreaChange((_o: Area, n: Area) => {
          const h: number = n.height as number;
          if (h > 100) { this.pageSize = PageCalc.computePageSize(h, ROW_H); }
        })
      }
    }
    .width('100%').height('100%')
  }
}
