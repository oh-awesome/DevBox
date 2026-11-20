/**
 * 包管理器页面 (Conan)
 *
 * 安装流程:
 *  1. 依赖解析 (拓扑排序 + 版本约束检查 + 冲突检测)
 *  2. conan install 拉取制品
 *  3. 定位 cache → 部署 bin/ 到按包隔离目录（HMDFS 逐文件补偿）
 *  4. chmod 770 设置可执行权限
 *  5. post-install hook + 生成命令 wrapper
 *  6. 更新本地注册表 registry.json
 *
 * 额外功能:
 *  - 仅下载按钮: 下载到 ~/Download/DevBox/
 *  - 一键添加 PATH 到环境变量管理器
 *  - 依赖管理: 安装时自动解析并安装依赖
 *  - 版本约束: semver 风格的版本匹配
 */
import { PkgItem, PkgDetail, PkgLoadState, PkgRequire, PkgCommand, PkgTestPhase, Registry, RegistryEntry, DepCheckResult, PkgUpgrade } from '../model/PkgModels';
import { PkgRepository } from '../service/PkgRepository';
import { DevCommandBlock } from '../common/brewcomponents';
import { BrewEnv } from '../utils/BrewEnv';
import { common, Want } from '@kit.AbilityKit';
import { DevTheme } from '../common/DevTheme';
import { DevTask } from '../utils/DevTask';
import fs from '@ohos.file.fs';
import { DevPageHeader, DevCard, DevSection, DevStatusDot, DevChip, DevTerm, DevEmpty, DevProgressSteps, DevCmdLine, DevKVRow, DevDialogPanel, DevConfirm, DevInput, DevToast, copyText, DevBtn, DevSegmentTabs, DevPagination, PageCalc, DevRowProgress } from '../common/component';
import { BrewListRow } from '../common/brewcomponents';
import { execSync as nativeExecSync, execAsync as nativeExecAsync, cancel as nativeCancel } from 'libdevbox_native.so';



import Logger from '../utils/Logger';





const TAG = 'PkgManager';
/** conan 统一执行入口：python -m 模块形式（console-script 落在 /data/app/bin 不可执行——真机实证） */
const CONAN_PY = '/storage/Users/currentUser/usr/local/bin/python3';
const INSTALL_DST = '$HOME/usr/local';
const PACKAGES_DIR = '$HOME/usr/local/packages';   // 按包隔离的部署根目录
const REGISTRY_PATH = '$HOME/usr/local/.devbox/registry.json';
const DOWNLOAD_DIR = '/storage/Users/currentUser/Download/DevBox';

/** 安装步骤常量 */
const STEP_IDLE: number = 0;
const STEP_DOWNLOADING: number = 1;
const STEP_EXTRACTING: number = 2;
const STEP_INSTALLING: number = 3;
const STEP_FIXING_PERM: number = 4;
const STEP_POST_HOOK: number = 5;
const STEP_REGISTRY: number = 6;
const STEP_DONE: number = 7;
const STEP_FAILED: number = 8;

/** 步骤标签 */
const STEP_LABELS: string[] = [
  '准备中', '下载中', '解压中', '安装中',
  '设置权限', '后处理', '注册', '完成', '失败',
];

/** 步骤条标签（安装 6 步） */
const PKG_STEPS: string[] = ['下载制品', '解压部署', '安装', '设置权限', '后处理', '写注册表'];

// ─── 版本比较工具 ──────────────────────────────────────────

/**
 * 比较两个版本号
 * 返回: 1 = a>b, 0 = a==b, -1 = a<b
 */
function compareVersion(a: string, b: string): number {
  const pa: number[] = a.split('.').map((s: string): number => parseInt(s) || 0);
  const pb: number[] = b.split('.').map((s: string): number => parseInt(s) || 0);
  const len: number = Math.max(pa.length, pb.length);
  for (let i = 0; i < len; i++) {
    const na: number = i < pa.length ? pa[i] : 0;
    const nb: number = i < pb.length ? pb[i] : 0;
    if (na > nb) return 1;
    if (na < nb) return -1;
  }
  return 0;
}

/**
 * 检查版本是否满足约束
 * constraint 格式: ">=3.0.0", "<2.0.0", ">=1.0.0,<2.0.0", "*", ""
 */
function satisfiesVersion(version: string, constraint: string): boolean {
  if (!constraint || constraint === '*' || constraint === '') return true;
  // 逗号分隔多个约束, 必须全部满足
  const parts: string[] = constraint.split(',');
  for (const part of parts) {
    const c: string = part.trim();
    if (c.startsWith('>=')) {
      if (compareVersion(version, c.substring(2)) < 0) return false;
    } else if (c.startsWith('>')) {
      if (compareVersion(version, c.substring(1)) <= 0) return false;
    } else if (c.startsWith('<=')) {
      if (compareVersion(version, c.substring(2)) > 0) return false;
    } else if (c.startsWith('<')) {
      if (compareVersion(version, c.substring(1)) >= 0) return false;
    } else {
      // 精确匹配
      if (compareVersion(version, c) !== 0) return false;
    }
  }
  return true;
}

/**
 * 解析 PTY ls 输出 (可能空格分隔或换行分隔)
 */
function parseLsOutput(raw: string): string[] {
  // ls -1 正常输出=每行恰好一个文件名。含空格/冒号/报错前缀的行是错误文本——
  // 原实现按空格分词把 ls 报错当二进制名（建出 or/not/found/sh: 等垃圾 wrapper——真机实证）
  const result: string[] = [];
  for (const line of raw.split('\n')) {
    const t: string = line.trim();
    if (t.length > 0 && t.indexOf(' ') < 0 && t.indexOf(':') < 0
      && !t.startsWith('ls') && !t.startsWith('sh')) {
      result.push(t);
    }
  }
  return result;
}


// ─── 包管理器主组件 ──────────────────────────────────────────────

@Component
export struct PkgManager {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @State pkgList: PkgItem[] = [];
  @State filteredList: PkgItem[] = [];
  @State currentPage: number = 1;
  private lastViewportH: number = 0;  // 动态实测行高
  @State pageSize: number = 24;
  @State searchKeyword: string = '';
  @State loadState: PkgLoadState = PkgLoadState.IDLE;
  @State statusMsg: string = '';
  @State selectedCategory: string = '';
  @State totalPackages: number = 0;

  // ─── 安装/下载状态 ────────────────────────────────────────────
  @State installStep: number = STEP_IDLE;
  @State installPkgName: string = '';
  @State installLog: string = '';         // 最近一条日志
  @State installProgress: string = '';    // 步骤进度文字
  @State installedPkgs: Set<string> = new Set(); // 已安装的包名
  // ─── 下载完成状态 ────────────────────────────────────────────
  @State downloadDone: boolean = false;
  @State downloadFailed: boolean = false;
  @State downloadRunning: boolean = false;
  @State refreshTick: number = 0;  // 卸载后强制刷新 ForEach
  // Tab 3/4 状态
  private currentHandle: object | null = null;

  // ─── 依赖弹窗状态 ────────────────────────────────────────────
  @State showDepConfirmDialog: boolean = false;
  @State depCheckResult: DepCheckResult = {
    toInstall: [], toUpgrade: [], conflicts: [], satisfied: [], installOrder: [],
  };
  private depDialogTarget: PkgItem = {} as PkgItem;


  private repo: PkgRepository = PkgRepository.getInstance();

  aboutToAppear() {
    this.repo.setContext(getContext(this));
    this.checkConan();

    // App 运行期间页面切换：内存缓存非空则直接复用 (进程级缓存)。
    // 冷启动或首次进入时 cachedPackages 为空 → 走完整加载流程。
    // 用户主动按刷新按钮 → 直接调 loadData() 强制重载 (绕过此分支)。
    if (this.repo.getPackages().length > 0) {
      Logger.info(TAG, 'in-memory cache present, skip conan env check + loadIndex');
      this.pkgList = this.repo.getPackages();
      this.totalPackages = this.pkgList.length;
      this.loadState = PkgLoadState.SUCCESS;
      this.statusMsg = `已加载 ${this.totalPackages} 个软件包`;
      this.applyFilter();
      this.loadRegistry();
      return;
    }

    this.loadState = PkgLoadState.LOADING;
    this.statusMsg = '正在检查 conan 环境…';
    // 异步检查 conan 环境，避免阻塞 UI 线程
    this.initConanEnv();
  }

  private async initConanEnv() {
    const ready: boolean = await this.repo.ensureConanReadyAsync();
    if (!ready) {
      // conan 本体缺失不再阻断浏览：loadIndex 内部回退 CDN 目录（发现服务 conan-packages.json）
      const reason: string = this.repo.lastConanError.length > 0
        ? this.repo.lastConanError
        : '未知原因';
      Logger.warn(TAG, `ensureConanReady failed (${reason}), falling back to CDN catalog`);
    }
    this.loadData();
    this.loadRegistry();
    this.checkPathConfigured();   // PATH 横幅显隐判定（已配置则不提示）
  }

  // ─── 数据操作 ────────────────────────────────────────────────

  async loadData() {
    this.loadState = PkgLoadState.LOADING;
    this.statusMsg = '正在加载…';
    const result = await this.repo.loadIndex();
    this.loadState = result.state;
    this.statusMsg = result.message;
    this.totalPackages = result.count;
    this.pkgList = this.repo.getPackages();
    this.applyFilter();
  }

  applyFilter() {
    let list = this.pkgList;
    if (this.selectedCategory === '__installed') {
      list = list.filter((p: PkgItem): boolean => this.isInstalled(p));
    } else if (this.selectedCategory.length > 0 && this.selectedCategory !== '') {
      list = list.filter((p: PkgItem): boolean => p.category === this.selectedCategory);
    }
    if (this.searchKeyword.trim().length > 0) {
      const kw = this.searchKeyword.trim().toLowerCase();
      list = list.filter((p: PkgItem): boolean =>
        p.name.toLowerCase().includes(kw) ||
        p.summary.toLowerCase().includes(kw)
      );
    }
    this.filteredList = list;
    this.currentPage = 1; // 过滤变化回到第一页
  }

  /** 当前页切片（10125 条全量 ForEach 会卡死主线程，必须分页） */
  private pagedList(): PkgItem[] {
    const start: number = (this.currentPage - 1) * this.pageSize;
    return this.filteredList.slice(start, start + this.pageSize);
  }


  /** 获取安装命令 (供复制/详情面板用)——Conan 2.x 无 channel（配方全不带
   *  user/channel 后缀，@ohpcd/stable 是历史残留已清） */
  getInstallCmd(pkg: PkgItem): string {
    return `conan install ${pkg.name}/${pkg.version} -r ohpcd`;
  }

  /** 获取下载 URL (异步，Conan 需要多步 API 获取) */
  async getDownloadUrlAsync(pkg: PkgItem): Promise<string> {
    return await this.repo.getConanDownloadUrl(pkg.name, pkg.version);
  }

  formatSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / 1048576).toFixed(1)} MB`;
  }

  // ─── 选中详情（brew 软件中心同款主从布局的右面板数据源） ───

  @State selectedPkgName: string = '';
  @State selectedPkgVer: string = '';   // 选中的版本（版本选择器可切换）
  @State pkgDetail: PkgDetail | null = null;
  @State detailLoading: boolean = false;
  // 二进制兼容矩阵（conan list "ref:*" --format=json——用户调研补充的信息源）
  @State binaryMatrix: Record<string, string>[] = [];
  // 选中项名字键缓存（万级过滤集 × 面板 ~15 处调用的性能护栏——实测同款坑）
  private selMemoFor: string = '\u0000';
  private selMemoItem: PkgItem | null = null;

  /** 选中（右详情跟随；conan show 异步拉详情） */
  private selectPkg(pkg: PkgItem): void {
    if (this.selectedPkgName === pkg.name) { return; }
    this.selectedPkgName = pkg.name;
    this.selectedPkgVer = pkg.version;   // 默认选中最新版
    this.pkgDetail = null;
    this.loadPkgDetail(pkg);
  }

  /** 版本切换（详情面板版本选择器） */
  private selectPkgVersion(ver: string): void {
    if (this.selectedPkgVer === ver) { return; }
    this.selectedPkgVer = ver;
    // 重拉详情（新版本的元数据可能不同）
    const item: PkgItem | null = this.selectedPkgItem();
    if (item !== null) {
      this.pkgDetail = null;
      this.loadPkgDetail({ name: item.name, version: ver, category: item.category,
        summary: item.summary, tags: item.tags, filename: item.filename, size_compressed: item.size_compressed });
    }
  }

  private loadPkgDetail(pkg: PkgItem): void {
    this.detailLoading = true;
    this.binaryMatrix = [];
    // 双源并行：conan show 元数据 + conan list "ref:*" 二进制矩阵（用户调研
    // 补充——Conan 2.x 官方推荐通道，取代旧 search --json）
    this.repo.getPackageDetail(pkg.name, pkg.version).then((d: PkgDetail | null) => {
      this.pkgDetail = d;
      this.detailLoading = false;
    }).catch(() => {
      this.pkgDetail = null;
      this.detailLoading = false;
    });
    this.repo.getBinaryMatrix(pkg.name, pkg.version).then((rows: Record<string, string>[]) => {
      this.binaryMatrix = rows;
    }).catch(() => {
      this.binaryMatrix = [];
    });
  }

  /** 选中项：显式选中优先（须在过滤集内），失效回落第一行；带名字键缓存 */
  private selectedPkgItem(): PkgItem | null {
    if (this.filteredList.length === 0) {
      this.selMemoFor = '\u0000';
      this.selMemoItem = null;
      return null;
    }
    let sel: string = this.selectedPkgName;
    let found: boolean = false;
    for (let i = 0; i < this.filteredList.length; i++) {
      if (this.filteredList[i].name === sel) { found = true; break; }
    }
    if (!found) { sel = this.filteredList[0].name; }
    if (this.selMemoFor === sel && this.selMemoItem !== null) { return this.selMemoItem; }
    this.selMemoFor = sel;
    this.selMemoItem = null;
    for (let i = 0; i < this.filteredList.length; i++) {
      if (this.filteredList[i].name === sel) { this.selMemoItem = this.filteredList[i]; break; }
    }
    return this.selMemoItem;
  }

  /** 行 desc：安装中显示步骤文案，失败标记，否则摘要 */
  private rowDescOf(pkg: PkgItem): string {
    if (this.installPkgName === pkg.name && this.installStep > STEP_IDLE && this.installStep < STEP_DONE) {
      return this.installProgress;
    }
    if (this.installPkgName === pkg.name && this.installStep === STEP_FAILED) {
      return '安装失败';
    }
    return pkg.summary;
  }

  /** 测试状态文字 → 状态点语义 */
  private testStatus(s: string): number {
    if (s === 'passed') { return 1; }
    if (s === 'failed') { return 3; }
    return 0;
  }

  /** 测试阶段文案 */
  private phaseLabel(phase: PkgTestPhase): string {
    if (phase.status === 'passed') {
      if (phase.total !== undefined && phase.total! > 0) { return `通过 ${phase.passed}/${phase.total}`; }
      return '通过';
    }
    if (phase.status === 'failed') { return '失败'; }
    return '未测试';
  }

  @Builder
  buildLinkRow(label: string, url: string) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_TERTIARY).width(90)
      Text(url)
        .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.INFO).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .decoration({ type: TextDecorationType.Underline })
        .onClick(() => {
          try {
            const context = getContext(this) as common.UIAbilityContext;
            const want: Want = {
              action: 'ohos.want.action.viewData',
              uri: url,
            };
            context.startAbility(want);
          } catch (e) {
            Logger.error(TAG, 'openUrl failed: ' + e);
          }
        })
      Text($r('app.string.brewcomponents_2'))
        .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(6)
        .backgroundColor(DevTheme.BG_MUTED)
        .onClick(() => {
          copyText(url);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // ─── 本地注册表 ──────────────────────────────────────────────

  /** 注册表缓存 (内存) */
  private registry: Registry = { format_version: 1, updated: '', packages: {} };

  /** 从文件加载注册表 */
  loadRegistry() {
    try {
      const raw: string = nativeExecSync(`cat ${REGISTRY_PATH} 2>/dev/null || echo '{}'`);
      const obj: Record<string, Object> = JSON.parse(raw.trim()) as Record<string, Object>;
      if (obj['packages']) {
        this.registry.packages = obj['packages'] as Record<string, RegistryEntry>;
      }
      Logger.info(TAG, `registry loaded: ${Object.keys(this.registry.packages).length} packages`);
    } catch (e) {
      Logger.info(TAG, `loadRegistry: ${e}, starting fresh`);
      this.registry = { format_version: 1, updated: '', packages: {} };
    }
    // 验证 registry 里的包目录确实存在（防残留假数据，异步防 UI 阻塞）
    const regKeys = Object.keys(this.registry.packages);
    if (regKeys.length === 0) {
      this.installedPkgs = new Set<string>();
      this.mergeConanCacheRefs();
      return;
    }
    const dirChecks: string = regKeys.map((k: string): string => {
      const entry: RegistryEntry = this.registry.packages[k];
      return `test -d '${PACKAGES_DIR}/${k}/${entry.version}' && echo '${k}'`;
    }).join(' || echo __NO__ ; ');
    const outLines: string[] = [];
    DevTask.shell(dirChecks,
      (t: string, _e: boolean) => { outLines.push(t); },
      (_ok: boolean, _d: string) => {
        const found: Set<string> = new Set<string>();
        for (let j = 0; j < outLines.length; j++) {
          const ln: string = outLines[j].trim();
          if (ln !== '' && ln !== '__NO__') { found.add(ln); }
        }
        let changed: boolean = false;
        const validPkgs: Record<string, RegistryEntry> = {};
        for (let k = 0; k < regKeys.length; k++) {
          if (found.has(regKeys[k])) {
            validPkgs[regKeys[k]] = this.registry.packages[regKeys[k]];
          } else {
            Logger.warn(TAG, `registry stale: ${regKeys[k]} removed`);
            changed = true;
          }
        }
        if (changed) { this.registry.packages = validPkgs; }
        this.installedPkgs = new Set(Object.keys(this.registry.packages));
        if (changed) { this.saveRegistry(); this.applyFilter(); }
        this.mergeConanCacheRefs();
      });
  }

  /**
   * conan 缓存真值并入已装集（2026-11-13 用户实证：终端 conan list 查得到
   * 的包 app 不显示已装——此前已装集仅来自部署 registry，终端装的/流程
   * 中断的缓存包不入集。conan 语义"缓存有 = 已安装"。两条轨独立：部署
   * 集落定后并入缓存集（时序防覆盖）
   */
  private mergeConanCacheRefs(): void {
    const out: string[] = [];
    DevTask.shell(
      `NO_COLOR=1 '/storage/Users/currentUser/usr/local/bin/python3' -m conans.conan list '*/*' --format=json 2>&1`,
      (t: string, _e: boolean) => { if (t.trim() !== '') { out.push(t); } },
      (_ok: boolean, _d: string) => {
        try {
          const raw: string = out.join('\n');
          const start: number = raw.indexOf('{');
          if (start >= 0) {
            const refs: Record<string, Object> = JSON.parse(raw.substring(start)) as Record<string, Object>;
            const names: string[] = Object.keys(refs);
            let merged: number = 0;
            for (let i = 0; i < names.length; i++) {
              const nm: string = names[i].split('/')[0];
              if (nm !== '' && !this.installedPkgs.has(nm)) { this.installedPkgs.add(nm); merged++; }
            }
            if (merged > 0) { this.applyFilter(); }
            Logger.info(TAG, `conan cache refs: ${names.length} (merged +${merged})`);
          }
        } catch (e) {
          Logger.warn(TAG, `conan cache list parse failed: ${e}`);
        }
      });
  }

  /** 写注册表到文件 */
  private saveRegistry() {
    try {
      this.registry.updated = new Date().toISOString();
      const json: string = JSON.stringify(this.registry, null, 2);
      const cmd: string =
        `mkdir -p ${INSTALL_DST}/.devbox && cat > ${REGISTRY_PATH} << 'REGEOF'\n${json}\nREGEOF`;
      nativeExecSync(cmd);
      Logger.info(TAG, `registry saved: ${Object.keys(this.registry.packages).length} packages`);
    } catch (e) {
      Logger.error(TAG, `saveRegistry: ${e}`);
    }
  }

  /** 注册一个已安装的包 */
  private registerPkg(pkg: PkgItem, files: string[], requires: PkgRequire[], commands?: PkgCommand[]) {
    const entry: RegistryEntry = {
      version: pkg.version,
      conan_ref: `${pkg.name}/${pkg.version}`,
      install_time: new Date().toISOString(),
      files: files,
      requires: requires,
    };
    if (commands && commands.length > 0) {
      entry.commands = commands;
    }
    this.registry.packages[pkg.name] = entry;
    this.installedPkgs = new Set(Object.keys(this.registry.packages));
    this.saveRegistry();
    this.applyFilter(); // 立即刷新已装/未装状态
  }

  /** 从注册表移除 */
  private unregisterPkg(name: string) {
    const newPackages: Record<string, RegistryEntry> = {};
    const keys = Object.keys(this.registry.packages);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i] !== name && this.registry.packages[keys[i]] !== undefined) {
        newPackages[keys[i]] = this.registry.packages[keys[i]];
      }
    }
    this.registry.packages = newPackages;
    this.installedPkgs = new Set(Object.keys(this.registry.packages));
    this.saveRegistry();
  }

  /** 获取已安装包版本 */
  private getInstalledVersion(name: string): string {
    const entry: RegistryEntry | undefined = this.registry.packages[name];
    return entry ? entry.version : '';
  }

  /** 卸载确认（统一危险确认弹窗） */
  askUninstallPkg(pkg: PkgItem): void {
    DevConfirm.danger(
      `卸载 ${pkg.name}`,
      `将删除 $HOME/usr/local/packages/${pkg.name} 下的已装文件与命令包装脚本，并同步清理 conan 缓存。`,
      () => {
        this.uninstallPkg(pkg);
      },
      '卸载',
    );
  }

  /** 卸载一个已安装的包 */
  uninstallPkg(pkg: PkgItem) {
    const entry: RegistryEntry | undefined = this.registry.packages[pkg.name];
    if (!entry) {
      // 无部署台账 = conan 缓存态包（终端装的/流程中断缓存残留）——
      // conan remove 清缓存（与合并进已装集的语义对齐），不再误报"未安装"
      this.repo.conanRemove(`${pkg.name}/${pkg.version}`).then(() => {
        DevToast.ok(`${pkg.name} 已从 conan 缓存移除`);
        this.loadRegistry();
      });
      return;
    }

    Logger.info(TAG, `Uninstalling ${pkg.name} v${entry.version}`);

    // 1. 清理 bin wrapper 脚本
    if (entry.commands && entry.commands.length > 0) {
      for (let i = 0; i < entry.commands.length; i++) {
        const cmd: PkgCommand = entry.commands[i];
        if (cmd.name.length > 0) {
          nativeExecSync(`rm -f $HOME/usr/local/bin/${cmd.name} 2>/dev/null`);
          Logger.info(TAG, `Removed wrapper: ${cmd.name}`);
        }
      }
    }

    // 2. 删除按包隔离的安装目录 (整个版本目录一次性清理)
    const pkgDir: string = `${PACKAGES_DIR}/${pkg.name}/${entry.version}`;
    nativeExecSync(`rm -rf ${pkgDir} 2>/dev/null`);
    Logger.info(TAG, `Removed install dir: ${pkgDir}`);

    // 2.1 同时从 conan cache 移除 (通过 proxy，后台执行)
    const ref: string = entry.conan_ref || `${pkg.name}/${entry.version}`;
    this.repo.conanRemove(ref);

    // 2.5 验证目录确实被删除（防假卸载）
    const checkResult: string = nativeExecSync(`test -d '${pkgDir}' && echo STILL_EXISTS || echo DELETED`) ?? '';
    if (checkResult.trim() === 'STILL_EXISTS') {
      Logger.warn(TAG, `uninstall: dir still exists, retrying: ${pkgDir}`);
      nativeExecSync(`rm -rf '${pkgDir}' 2>/dev/null`);
    }

    // 3. 从注册表移除
    this.unregisterPkg(pkg.name);

    // 5. 刷新列表（refreshTick 强制 ForEach 重评估 key）
    this.applyFilter();
    this.refreshTick++;

    DevToast.ok(`${pkg.name} 已卸载`);
    Logger.info(TAG, `Uninstalled ${pkg.name}`);
  }

  isInstalled(pkg: PkgItem): boolean {
    // 只信 registry Set（渲染路径禁止同步 shell）
    return this.installedPkgs.has(pkg.name);
  }

  // ─── 依赖解析 ──────────────────────────────────────────────

  /**
   * 解析包的完整依赖链
   * 返回: toInstall(需新装) + toUpgrade(需升级) + conflicts + installOrder(拓扑序)
   */
  async resolveDependencies(pkg: PkgItem): Promise<DepCheckResult> {
    const result: DepCheckResult = {
      toInstall: [],
      toUpgrade: [],
      conflicts: [],
      satisfied: [],
      installOrder: [],
    };

    const detail: PkgDetail | null = await this.repo.getPackageDetail(pkg.name, pkg.version);
    if (!detail || detail.requires.length === 0) {
      result.installOrder = [pkg.name];
      return result;
    }

    // 递归收集所有依赖
    const visited: Set<string> = new Set();
    const depMap: Map<string, PkgRequire> = new Map();

    const collectDeps = async (name: string, constraint: string, depth: number) => {
      if (depth > 10 || visited.has(name)) return;
      visited.add(name);

      depMap.set(name, { name: name, version: constraint });

      const subDetail: PkgDetail | null = await this.repo.getPackageDetail(name, constraint === '*' ? undefined : constraint);
      if (subDetail && subDetail.requires.length > 0) {
        for (const sub of subDetail.requires) {
          await collectDeps(sub.name, sub.version, depth + 1);
        }
      }
    };

    for (const req of detail.requires) {
      await collectDeps(req.name, req.version, 0);
    }

    // 分类
    depMap.forEach((req: PkgRequire, name: string) => {
      const installedVer: string = this.getInstalledVersion(name);
      if (installedVer.length === 0) {
        if (this.pkgList.some((p: PkgItem): boolean => p.name === name)) {
          result.toInstall.push(req);
        } else {
          result.conflicts.push(`依赖 ${name} 不在仓库中`);
        }
      } else if (satisfiesVersion(installedVer, req.version)) {
        result.satisfied.push(`${name} ${installedVer}`);
      } else {
        result.toUpgrade.push({
          name: name,
          currentVersion: installedVer,
          requiredVersion: req.version,
        });
      }
    });

    // 冲突检查
    if (detail.conflicts.length > 0) {
      for (const conflict of detail.conflicts) {
        if (this.installedPkgs.has(conflict.name)) {
          const ver: string = this.getInstalledVersion(conflict.name);
          result.conflicts.push(`与已安装的 ${conflict.name} ${ver} 冲突${conflict.reason ? ': ' + conflict.reason : ''}`);
        }
      }
    }

    // 版本冲突: 升级是否与其他已装包冲突
    for (const upgrade of result.toUpgrade) {
      for (const installedName of Object.keys(this.registry.packages)) {
        if (installedName === pkg.name) continue;
        const regEntry: RegistryEntry | undefined = this.registry.packages[installedName];
        if (regEntry === undefined) continue;
        for (const dep of regEntry.requires) {
          if (dep.name === upgrade.name && dep.version !== '*' &&
            !satisfiesVersion(upgrade.requiredVersion, dep.version)) {
            result.conflicts.push(
              `${installedName} 要求 ${upgrade.name} ${dep.version}, 但 ${pkg.name} 要求 ${upgrade.requiredVersion}`
            );
          }
        }
      }
    }

    // 拓扑排序: 底层依赖在前
    for (const req of result.toInstall) {
      if (!result.installOrder.includes(req.name)) result.installOrder.push(req.name);
    }
    for (const upgrade of result.toUpgrade) {
      if (!result.installOrder.includes(upgrade.name)) result.installOrder.push(upgrade.name);
    }
    if (!result.installOrder.includes(pkg.name)) result.installOrder.push(pkg.name);

    return result;
  }

  // ─── 安装流程 ──────────────────────────────────────────────

  private setStep(step: number, log: string) {
    this.installStep = step;
    this.installLog = log;
    if (step <= STEP_REGISTRY) {
      this.installProgress = `[${step + 1}/7] ${STEP_LABELS[step]}`;
    } else {
      this.installProgress = STEP_LABELS[step];
    }
    Logger.info(TAG, `install: ${this.installProgress} — ${log}`);
  }

  private failStep(log: string) {
    this.setStep(STEP_FAILED, log);
    setTimeout(() => {
      if (this.installStep === STEP_FAILED) {
        this.installStep = STEP_IDLE;
        this.installPkgName = '';
        this.installProgress = '';
        this.installLog = '';
      }
    }, 3000);
  }

  cancelInstall() {
    // 取消 conan install (在 PkgRepository 中)
    this.repo.cancelInstall();
    // 取消本地 runStepAsync
    if (this.currentHandle) {
      nativeCancel(this.currentHandle);
      this.currentHandle = null;
    }
    this.installStep = STEP_IDLE;
    this.installPkgName = '';
  }

  /** 执行单步命令 (sync) */
  private runStep(cmd: string): string {
    Logger.info(TAG, `runStep: ${cmd.substring(0, 120)}`);
    return nativeExecSync(cmd);
  }

  /** 执行单步命令 (async, 用于下载等耗时操作) */
  private runStepAsync(cmd: string, onLine: (line: string) => void, onDone: (code: number) => void): void {
    try {
      this.currentHandle = nativeExecAsync(
        cmd,
        (data: string, isErr: boolean) => {
          const lines: string[] = data.split('\n');
          for (const l of lines) {
            if (l.length > 0) onLine(l);
          }
        },
        (code: number) => { onDone(code); }
      );
    } catch (e) {
      onDone(-1);
    }
  }

  /**
   * 完整安装流程 (参照 install.sh)
   * Steps: 下载 → 解压 → 安装(先删旧文件再 cp) → HMDFS 补偿 → chmod → post-hook
   */
  execInstall(pkg: PkgItem) {
    if (this.installStep !== STEP_IDLE) {
      DevToast.show($r('app.string.pkg_manager_1'));
      return;
    }

    // 先做依赖解析, 再安装
    this.resolveDependencies(pkg).then((depResult: DepCheckResult) => {
      Logger.info(TAG, `dep resolve: install=[${depResult.toInstall.map((r: PkgRequire): string => r.name)}] ` +
        `upgrade=[${depResult.toUpgrade.map((u: PkgUpgrade): string => u.name)}] ` +
        `conflicts=[${depResult.conflicts}] ` +
        `order=[${depResult.installOrder}]`);

      if (depResult.conflicts.length > 0) {
        // 有冲突, 弹窗提示
        this.showDepDialog(pkg, depResult);
        return;
      }

      if (depResult.toInstall.length > 0 || depResult.toUpgrade.length > 0) {
        // 有缺失/需升级的依赖, 弹窗确认后安装
        this.showDepDialog(pkg, depResult);
        return;
      }

      // 无依赖或全部满足, 直接安装
      this.doInstall(pkg);
    });
  }

  /** 显示依赖确认弹窗 */
  private showDepDialog(pkg: PkgItem, depResult: DepCheckResult) {
    this.depCheckResult = depResult;
    this.depDialogTarget = pkg;
    this.showDepConfirmDialog = true;
  }

  /** 从依赖弹窗确认后执行 (按拓扑序安装) */
  async execInstallWithDeps() {
    this.showDepConfirmDialog = false;
    const depResult: DepCheckResult = this.depCheckResult;
    const order: string[] = depResult.installOrder;
    const mainPkg: PkgItem = this.depDialogTarget;

    // 按拓扑序逐个安装
    for (let i = 0; i < order.length; i++) {
      const depName: string = order[i];
      if (depName === mainPkg.name) {
        // 主包
        await this.doInstallAsync(mainPkg);
      } else {
        // 依赖包 — 从 pkgList 中找到
        const depPkg: PkgItem | undefined = this.pkgList.find((p: PkgItem): boolean => p.name === depName);
        if (depPkg) {
          this.installPkgName = depName;
          this.installProgress = `安装依赖 (${i + 1}/${order.length}) ${depName}...`;
          await this.doInstallAsync(depPkg);
        }
      }
      if (this.installStep === STEP_FAILED) return;
    }
  }

  /** 仅安装主包 (跳过依赖) */
  execInstallMainOnly() {
    this.showDepConfirmDialog = false;
    this.doInstall(this.depDialogTarget);
  }

  /** 同步触发安装 (无依赖场景) */
  private doInstall(pkg: PkgItem) {
    this.doInstallAsync(pkg);
  }

  /** 实际安装逻辑 (异步, 返回 Promise) — Phase 2: conan install + 隔离部署 */
  private async doInstallAsync(pkg: PkgItem): Promise<void> {
    // 装包前哨兵（2026-11-13 真机实证：页面内存包缓存命中会整段跳过 conan
    // 环境检查，用户清掉 ~/.conan2 后回来装包 → conan install 直报
    // "default build profile doesn't exist"）——磁盘校验 profile 存在且含
    // os=OHOS，缺失/损坏才触发幂等重建（全在时约 2s；正常路径 O(1) 零开销）
    const profileOk: string = (nativeExecSync(
      `test -f $HOME/.conan2/profiles/default && grep -q 'os=OHOS' $HOME/.conan2/profiles/default; echo $?`) ?? '').trim();
    if (profileOk !== '0') {
      this.setStep(STEP_DOWNLOADING, '准备 conan 环境（重建 profile）...');
      await this.repo.ensureConanReadyAsync();
    }
    return new Promise<void>((resolve: (v: void) => void) => {
      this.installPkgName = pkg.name;
      const ref: string = `${pkg.name}/${pkg.version}`;

      // 按包隔离的部署目录: $HOME/usr/local/packages/{name}/{version}/
      const pkgDir: string = `${PACKAGES_DIR}/${pkg.name}/${pkg.version}`;

      // ── Step 1: conan install (替代 curl 下载 + tar 解压 + 依赖解析) ──
      this.setStep(STEP_DOWNLOADING, `conan install ${ref} ...`);
      // 尾部输出缓存（失败归因用——区分"平台缺货"与其他错误）
      const tail: string[] = [];
      this.repo.installAsync(
        ref,
        (line: string) => {
          this.installLog = line;
          tail.push(line);
          if (tail.length > 40) { tail.shift(); }
          Logger.info(TAG, `[conan] ${line}`);
        },
        async (code: number) => {
          if (code !== 0) {
            // 缺预编译二进制（方案A 后的预期失败态）：缺货如实暴露而非挂死
            const joined: string = tail.join('\n').toLowerCase();
            if (joined.indexOf('missing prebuilt') >= 0
              || joined.indexOf('cannot be built') >= 0
              || joined.indexOf("can't find a binary") >= 0
              || joined.indexOf('was not found in remote') >= 0) {
              this.failStep('该包暂无预编译二进制（平台待补传）——设备不执行源码构建');
            } else {
              // 其他错误：带出最后一条 ERROR 行（比裸退出码可读）
              let lastErr: string = '';
              for (let i = 0; i < tail.length; i++) {
                if (tail[i].indexOf('ERROR') >= 0) { lastErr = tail[i]; }
              }
              this.failStep(lastErr !== '' ? `安装失败：${lastErr.substring(0, 80)}` : `安装失败（${code}）`);
            }
            resolve();
            return;
          }

          // ── Step 2: 定位 conan cache 中的产物 ──
          this.setStep(STEP_EXTRACTING, '定位已下载的组件…');
          const cachePath: string = await this.repo.getCachePath(ref);
          Logger.info(TAG, `cache path: ${cachePath.length > 0 ? cachePath : '(empty)'}`);
          if (cachePath.length === 0) {
            this.failStep('无法定位 conan cache 路径');
            resolve();
            return;
          }

          // ── Step 3: 部署到按包隔离目录 (只拷 bin/, 终端工具是静态链接自包含) ──
          this.setStep(STEP_INSTALLING, '部署到用户目录...');
          // 清理旧版本目录（同版本重装时）
          this.runStep(`rm -rf ${pkgDir} 2>/dev/null || true`);
          this.runStep(`mkdir -p ${pkgDir}/bin 2>/dev/null || true`);

          // 从 conan cache 只拷 bin/ 目录 (终端工具: 静态链接, 无 lib 依赖)
          const binsStr: string = this.runStep(
            `if [ -d ${cachePath}/bin ]; then ls -1 ${cachePath}/bin/ 2>/dev/null; fi`
          );
          const bins: string[] = parseLsOutput(binsStr);
          Logger.info(TAG, `conan cache bins: [${bins.join(', ')}]`);

          if (bins.length === 0) {
            // 纯开发库包 (无 bin/), 不部署可执行文件, 只记录到 registry
            Logger.info(TAG, `${pkg.name} is a library package (no bin/), skipping deployment`);
          }

          // HMDFS 补偿: 逐文件拷贝 (鸿蒙 cp -r 可能漏文件)
          const installedFiles: string[] = [];
          for (const bin of bins) {
            const relPath: string = `bin/${bin}`;
            // 先 rm 再 cp (绕过 HMDFS 缓存问题)
            this.runStep(`rm -f ${pkgDir}/${relPath} 2>/dev/null || true`);
            this.runStep(`cp ${cachePath}/bin/${bin} ${pkgDir}/${relPath} 2>/dev/null`);

            // HMDFS 补偿: 验证文件确实到位
            const check: string = this.runStep(`test -f ${pkgDir}/${relPath} && echo ok || echo missing`);
            if (check.trim() !== 'ok') {
              Logger.info(TAG, `HMDFS fix: retrying copy for ${bin}`);
              this.runStep(`cp -f ${cachePath}/bin/${bin} ${pkgDir}/${relPath} 2>/dev/null`);
              this.runStep(`test -f ${pkgDir}/${relPath} || cp ${cachePath}/bin/${bin} ${pkgDir}/${relPath}`);
            }
            installedFiles.push(relPath);
          }

          // ── Step 4: chmod ──
          this.setStep(STEP_FIXING_PERM, '设置可执行权限...');
          if (bins.length > 0) {
            const chmodCmd: string = bins.map(
              (b: string): string => `chmod 770 ${pkgDir}/bin/${b}`
            ).join(' && ');
            this.runStep(`${chmodCmd} 2>&1 || true`);
          }

          // ── Step 5: Post-install hook ──
          this.setStep(STEP_POST_HOOK, '检查后处理脚本...');
          const hook: string = `${pkgDir}/bin/post-install-${pkg.name}-${pkg.version}.sh`;
          const hookCheck: string = this.runStep(`test -f ${hook} && echo yes || echo no`);
          if (hookCheck.trim() === 'yes') {
            this.setStep(STEP_POST_HOOK, '运行后处理脚本...');
            this.runStep(`sh ${hook} ${pkgDir} 2>/dev/null || true`);
          }

          // ── Step 6: 生成 wrapper 脚本 (指向隔离目录中的二进制) ──
          this.setStep(STEP_POST_HOOK, '注册命令...');
          const binTargetDir: string = '$HOME/usr/local/bin';
          const savedCommands: PkgCommand[] = [];
          this.runStep(`mkdir -p ${binTargetDir}`);
          for (const bin of bins) {
            if (bin.startsWith('post-install')) continue;
            const cmd: PkgCommand = { name: bin, description: '' };
            cmd.bin = `bin/${bin}`;
            savedCommands.push(cmd);
            // wrapper 脚本: exec 指向按包隔离的绝对路径
            const linkTarget: string = `${pkgDir}/bin/${bin}`;
            this.runStep(
              `printf '#!/bin/sh\\nexec ${linkTarget} "$@"\\n' > ${binTargetDir}/${bin} && chmod +x ${binTargetDir}/${bin}`
            );
            Logger.info(TAG, `Created wrapper ${bin} -> ${linkTarget}`);
          }

          // ── Step 7: 更新注册表 ──
          this.setStep(STEP_REGISTRY, '更新安装记录...');
          const requires: PkgRequire[] = [];
          this.registerPkg(pkg, installedFiles, requires, savedCommands);

          // ── Step 8: 完成 ──
          this.setStep(STEP_DONE, `${pkg.name} v${pkg.version} 安装完成`);
          setTimeout(() => {
            if (this.installStep === STEP_DONE) {
              this.installStep = STEP_IDLE;
              this.installPkgName = '';
              this.applyFilter();
            }
          }, 3000);
          resolve();
        }
      );
    });
  }

  // ─── 仅下载功能 ────────────────────────────────────────────────

  async execDownload(pkg: PkgItem) {
    if (this.downloadRunning) {
      DevToast.show($r('app.string.pkg_manager_2'));
      return;
    }

    this.downloadRunning = true;
    this.downloadDone = false;
    this.downloadFailed = false;
    this.installPkgName = pkg.name;
    this.installProgress = '下载中…';
    this.installLog = `下载 ${pkg.name} v${pkg.version}`;

    Logger.info(TAG, `execDownload: ${pkg.name}/${pkg.version}, fetching download URL...`);
    const url: string = await this.getDownloadUrlAsync(pkg);
    Logger.info(TAG, `execDownload: got URL = ${url.length > 0 ? url : '(empty)'}`);
    if (url.length === 0) {
      this.downloadRunning = false;
      this.downloadFailed = true;
      this.installLog = '获取下载地址失败';
      return;
    }
    const filename: string = `${pkg.name}-${pkg.version}.tgz`;
    const cmd: string = `mkdir -p ${DOWNLOAD_DIR} && curl -fsSL --retry 3 --retry-delay 2 -o ${DOWNLOAD_DIR}/${filename} '${url}'`;

    this.runStepAsync(cmd,
      (line: string) => { this.installLog = line; },
      (code: number) => {
        this.downloadRunning = false;
        if (code === 0) {
          this.downloadDone = true;
          DevToast.ok(`已下载到 ${DOWNLOAD_DIR}/${pkg.filename}`);
          this.installProgress = '下载完成';
        } else {
          this.downloadFailed = true;
          DevToast.fail(`下载失败（${code}）`);
          this.installProgress = '下载失败';
        }
        setTimeout(() => {
          this.downloadDone = false;
          this.downloadFailed = false;
          this.installPkgName = '';
          this.installProgress = '';
          this.installLog = '';
        }, 3000);
      }
    );
  }

  // ─── 一键添加 PATH ─────────────────────────────────────────────

  @State pathConfigured: boolean = false;

  /** 检查 PATH 是否已配置（.zshrc 有 devbox 标记块或 usr/local/bin 在 PATH 行） */
  private checkPathConfigured(): void {
    const out: string = (nativeExecSync(
      `grep -q '# >>> devbox base >>>' /storage/Users/currentUser/.zshrc 2>/dev/null && echo YES || echo NO`) ?? '').trim();
    this.pathConfigured = out === 'YES';
  }

  addPathToEnv() {
    const home: string = '/storage/Users/currentUser';
    const rcFile: string = `${home}/.zshrc`;
    try {
      nativeExecSync(`touch ${rcFile}`);

      // 检查是否已有 devbox 基础 PATH 标记块
      const hasBlock: string = nativeExecSync(
        `grep -c '# >>> devbox base >>>' ${rcFile} 2>/dev/null || echo 0`
      );
      if (hasBlock.trim() !== '0') {
        DevToast.show($r('app.string.pkg_manager_3'));
        return;
      }

      // 写入统一的 devbox 基础 PATH 标记块
      nativeExecSync(`echo '' >> ${rcFile}`);
      nativeExecSync(`echo '# >>> devbox base >>>' >> ${rcFile}`);
      nativeExecSync(`echo 'export PATH="$HOME/usr/local/bin:$PATH"' >> ${rcFile}`);
      nativeExecSync(`echo 'export LD_LIBRARY_PATH="$HOME/usr/local/lib:$LD_LIBRARY_PATH"' >> ${rcFile}`);
      nativeExecSync(`echo '# <<< devbox base <<<' >> ${rcFile}`);

      Logger.info(TAG, 'addPath: base PATH block added to .zshrc');
      DevToast.ok($r('app.string.pkg_manager_4'));
    } catch (e) {
      Logger.error(TAG, `addPath error: ${e}`);
      DevToast.fail('添加失败');
    }
  }

  // ─── UI 辅助（纯数据变换） ─────────────────────────────────────

  /** 任务输出 → DevTerm 行数组 */
  private termLines(): string[] {
    const out: string[] = [];
    if (this.installProgress.length > 0) {
      out.push(this.installProgress);
    }
    if (this.installLog.length > 0) {
      out.push(this.installLog);
    }
    return out;
  }

  /** 安装步骤条已完成数 */
  private stepsCurrent(): number {
    if (this.installStep >= STEP_DONE) {
      return PKG_STEPS.length;
    }
    if (this.installStep <= STEP_IDLE) {
      return 0;
    }
    return this.installStep - 1;
  }

  /** 分类筛选选项（含“全部”） */

  // ─── 依赖确认弹窗 ──────────────────────────────────────────

  @Builder
  buildDepConfirmDialog() {
    Column() {
      DevDialogPanel({
        title: '依赖解析结果',
        dialogWidth: 520,
        dialogHeight: 480,
        paddingValueLeft: 24,
        paddingValueRight: 24,
        paddingValueTop: 16,
        paddingValueBottom: 24,
      }) {
        Column({ space: 12 }) {
          // 需要安装的依赖
          if (this.depCheckResult.toInstall.length > 0) {
            Column({ space: 6 }) {
              Text(`需要安装 ${this.depCheckResult.toInstall.length} 个依赖:`)
                .fontSize(DevTheme.FS_BODY).fontWeight(FontWeight.Medium).fontColor(DevTheme.TEXT_PRIMARY)
              ForEach(this.depCheckResult.toInstall, (req: PkgRequire) => {
                Row({ space: 8 }) {
                  Text(req.name)
                    .fontSize(DevTheme.FS_BODY).fontFamily(DevTheme.MONO_FONT).fontColor(DevTheme.TEXT_SECONDARY)
                  if (req.version && req.version !== '*') {
                    DevChip({ text: req.version, tone: 'neutral', mono: true })
                  }
                  DevChip({ text: '未安装', tone: 'danger', mono: false })
                }.width('100%')
              }, (req: PkgRequire) => req.name)
            }.width('100%').alignItems(HorizontalAlign.Start)
          }

          // 需要升级的依赖
          if (this.depCheckResult.toUpgrade.length > 0) {
            Column({ space: 6 }) {
              Text($r('app.string.pkg_manager_5'))
                .fontSize(DevTheme.FS_BODY).fontWeight(FontWeight.Medium).fontColor(DevTheme.WARNING)
              ForEach(this.depCheckResult.toUpgrade, (u: PkgUpgrade) => {
                Row({ space: 8 }) {
                  Text(u.name)
                    .fontSize(DevTheme.FS_BODY).fontFamily(DevTheme.MONO_FONT).fontColor(DevTheme.TEXT_SECONDARY)
                  DevChip({ text: `${u.currentVersion} → ${u.requiredVersion}`, tone: 'warning', mono: true })
                }.width('100%')
              }, (u: PkgUpgrade) => u.name)
            }.width('100%').alignItems(HorizontalAlign.Start)
          }

          // 已满足的依赖
          if (this.depCheckResult.satisfied.length > 0) {
            Column({ space: 6 }) {
              Text($r('app.string.pkg_manager_6'))
                .fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_MUTED)
              ForEach(this.depCheckResult.satisfied, (s: string) => {
                Row({ space: 8 }) {
                  Text(s)
                    .fontSize(DevTheme.FS_BODY).fontFamily(DevTheme.MONO_FONT).fontColor(DevTheme.TEXT_SECONDARY)
                }.width('100%')
              }, (s: string) => s)
            }.width('100%').alignItems(HorizontalAlign.Start)
          }

          // 冲突
          if (this.depCheckResult.conflicts.length > 0) {
            Column({ space: 6 }) {
              Text($r('app.string.pkg_manager_7'))
                .fontSize(DevTheme.FS_BODY).fontWeight(FontWeight.Medium).fontColor(DevTheme.DANGER)
              ForEach(this.depCheckResult.conflicts, (c: string) => {
                Text(`· ${c}`)
                  .fontSize(DevTheme.FS_BODY).fontColor(DevTheme.DANGER).width('100%')
              }, (c: string) => c)
            }.width('100%').alignItems(HorizontalAlign.Start)
          }

          // 按钮
          Row({ space: 10 }) {
            if (this.depCheckResult.conflicts.length === 0) {
              DevBtn({
                text: '安装全部',
                buttonSize: 'small',
                  onTap: () => {
                  this.execInstallWithDeps();
                  },
                })
            }
            DevBtn({
              text: '仅安装主包',
              buttonSize: 'small',
              plain: true,
                onTap: () => {
                this.execInstallMainOnly();
                },
              })
            DevBtn({
              text: '取消',
              buttonSize: 'small',
              plain: true,
                onTap: () => {
                this.showDepConfirmDialog = false;
                },
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
        }
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(DevTheme.BG_OVERLAY)
    .onClick(() => { this.showDepConfirmDialog = false; })
  }

  // ─── 主构建 ──────────────────────────────────────────────────

  @State managerTab: number = 0;

  build() {
    Stack() {
      Column() {
        // 页面标题栏
        this.buildPageHeader()

        // 两 Tab：包管理器 / 软件仓库（远程仓库/配置两页已砍——只读原样
        // dump 无管理能力且 DevTask 通道不通（历史遗留），有用信息折叠进
        // 包管理器卡的 KV 行：远程仓 + profile）
        DevSegmentTabs({
          options: this.conanInstalled ? ['包管理器', '软件仓库'] : ['包管理器'],
          active: this.conanInstalled ? this.managerTab : 0,
          onChange: (idx: number) => {
            this.managerTab = idx;
          },
        })
        .margin({ bottom: 4 })

        if (this.managerTab === 0) {
          // ── Tab 1: 包管理器（conan 本体装卸 + 远程设置） ──
          this.buildManagerTab()
        } else if (this.managerTab === 1) {
          // ── Tab 2: 软件仓库（组件目录 + 安装管理） ──
          // PATH 提示（安装中不显示；已有标记块也不显示——审计反馈：
          // PATH 已配置的用户不需要再看到提示）
          if (this.installedPkgs.size > 0 && this.installStep === STEP_IDLE
            && !this.downloadRunning && !this.pathConfigured) {
            this.buildPathBanner()
          }
          // 内容区
          this.buildBrowseView()
        }
      }
      .width('100%')
      .height('100%')

      // 依赖确认弹窗 (覆盖层)
      if (this.showDepConfirmDialog) {
        this.buildDepConfirmDialog()
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 8, bottom: 16 })
  }

  @Builder
  buildManagerTab() {
    Scroll() {
      Column({ space: 14 }) {
        DevCard({ title: 'Conan', subtitle: 'C/C++ 包管理器（通过 pip 安装）', accent: '', pad: 12 }) {
          Column({ space: 10 }) {
            DevKVRow({ k: '状态', v: this.conanInstalled ? '已安装' : '未安装', copyable: false, mono: false })
            DevKVRow({ k: '安装方式', v: 'pip install conan', copyable: true, mono: true })
            DevKVRow({ k: '远程仓', v: 'ohpcd (conan.cnb.cool)', copyable: false, mono: true })
            DevKVRow({ k: 'Profile', v: 'ohos-aarch64（自动管理）', copyable: false, mono: false })

            if (this.conanBusy) {
              Row({ space: 8 }) {
                LoadingProgress().width(14).height(14).color(DevTheme.PRIMARY)
                Text($r('app.string.pkg_manager_8')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
              }.width('100%')
            }

            Row({ space: 10 }) {
              if (!this.conanInstalled) {
                DevBtn({
                  text: this.conanBusy ? '安装中…' : '安装 Conan',
                  buttonSize: 'normal',
                  // busy 即禁用+loading（反馈#1：安装中仍可点不满足互斥；
                  // onTap 守卫防双击是二道防线）
                  loading: this.conanBusy,
                  disabled: this.conanBusy,
                  onTap: () => { if (!this.conanBusy) { this.installConan(); } },
                })
              } else {
                DevBtn({
                  text: this.conanBusy ? '卸载中…' : '卸载',
                  buttonSize: 'normal',
                  danger: true,
                  loading: this.conanBusy,
                  disabled: this.conanBusy,
                  onTap: () => { if (!this.conanBusy) { this.uninstallConan(); } },
                })
              }
            }
            .width('100%')
            .justifyContent(FlexAlign.End)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width('100%')
      .padding({ top: 8, bottom: 32 })
    }
    .layoutWeight(1)
    .align(Alignment.TopStart)
  }

  // ─── 页面标题栏 ──────────────────────────────────────────────

  /** Conan 本体安装状态卡片（安装/卸载 conan 本身，via pip） */
  @State conanInstalled: boolean = false;
  @State conanChecking: boolean = true;
  @State conanBusy: boolean = false;


  private checkConan(): void {
    // 根治双坑（真机实证 sh: /data/app/bin/conan: Permission denied）：
    // ①pip 的 console-script 落在 /data/app/bin（python 构建期前缀）且不可执行——
    //   统一绕开坏脚本走 python -m conans.conan 模块入口；
    // ②原 `conan --version | head -1` 管道吞退出码（126 也报 ok）→ 假"已安装"——
    //   改 grep -q 作最末命令（管道退出码=判定信号）
    DevTask.shell(`${CONAN_PY} -m conans.conan --version 2>&1 | grep -q 'Conan version'`,
      (t: string, _e: boolean) => {},
      (ok: boolean, _d: string) => {
        this.conanInstalled = ok;
        this.conanChecking = false;
      });
  }

  private installConan(): void {
    if (this.conanBusy) { return; }
    // Python 前置引导（2026-11-13）：CONAN_PY 是 conan 全链（pip 装/版本查/
    // 运行）唯一执行体——python 未装时命令链全空转，且命令里的 | tail 管道
    // 吞真实退出码 → 假"安装完成"秒回（真机实证）。点击安装时前置拦截：
    // 弹窗说明依赖 + 引导跳 Python 页；用户装完 Python 自行切回本页再点安装
    try {
      if (!fs.accessSync(CONAN_PY)) {
        DevConfirm.ask('需要先安装 Python',
          'Conan 依赖 Python 环境，当前未检测到可用的 python3。\n\n点击「前往安装」转到 Python 页面完成安装后，返回本页再点击「安装 Conan」。',
          () => { AppStorage.setOrCreate('nav_request', 'python'); },
          '前往安装');
        return;
      }
    } catch (_) {
      // 探测异常不阻断（走原流程让真实失败浮出）
    }
    this.conanBusy = true;
    // 单一社区源直装（2026-11-13 平台事实，用户真机实证）：社区源
    // pypi.cnb.cool 已配套加速源——只指定这一个源即可完整解析安装 conan
    // 及全部依赖（requests/PyYAML 等）。此前两步法（社区源下 wheel +
    // pypi.org 解析依赖）在 files.pythonhosted.org 读超时挂死（hilog 实证：
    // PyYAML/MarkupSafe 拿到 sdist 现场构建 + 国际源读超时）。
    // ⚠ distro 必须附带（真机再实证 2026-11-13 晚）：社区 conan wheel 未
    // 声明它，但 conan 运行时 load_global_conf 硬 import（conan_api.py:152）
    // ——DevBox 自装 python 没有它（HNP python 预装所以终端"看似"不需要）
    // → conan --version 直接 ModuleNotFoundError。纯 python 小包，社区源有。
    // ⚠ chardet 附带（2026-11-13 晚实证）：社区 charset_normalizer-ohos 轮
    // 的 C 扩展 DT_NEEDED libpython3.12.so.1.0——静态 libpython 的发行版
    // （制品仓 python）加载必败 → import charset_normalizer ImportError →
    // requests 每次打 RequestsDependencyWarning。chardet 纯 python，requests
    // 探测同样接受 → 告警消失 + 自动编码探测能力恢复。平台修轮后冗余无害。
    // PIP_CONFIG_FILE=/dev/null：隔离 pip.conf 的 extra-index-url（用户终端
    // 实证：aliyun extra 会让同号官方包抢跑——conan 本体/charset_normalizer
    // 都被换成官方版）
    const pipBin = `${CONAN_PY} -m pip`;
    const OHPCD_IDX = 'https://pypi.cnb.cool/OpenHarmonyPCDeveloper/pypi/-/packages/simple';
    DevTask.shell(
      `${pipBin} uninstall -y conan 2>&1; ` +
      `PIP_CONFIG_FILE=/dev/null ${pipBin} install --force-reinstall --no-cache-dir -i ${OHPCD_IDX} --trusted-host pypi.cnb.cool 'conan==2.29.1' distro chardet 2>&1`,
      (t: string, _e: boolean) => { if (t.trim() !== '') { Logger.info(TAG, `[conan-pip] ${t}`); } },
      (ok: boolean, _d: string) => {
        this.conanBusy = false;
        if (ok) {
          DevToast.ok($r('app.string.pkg_manager_9'));
          // 装后立即完成 conan 侧配置：ohpcd remote（源）+ ohos-aarch64 profile +
          // settings.yml 陈旧刷新（ensureConanReadyAsync 幂等，见 PkgRepository）
          this.repo.ensureConanReadyAsync().then((_ready: boolean) => { this.checkConan(); });
        } else {
          DevToast.show($r('app.string.pkg_manager_10'));
        }
      });
  }

  private uninstallConan(): void {
    if (this.conanBusy) { return; }
    DevConfirm.danger('卸载 Conan', '将卸载 conan 命令（~/.conan2 缓存保留）。', () => {
      this.conanBusy = true;
  const pipBin = `${CONAN_PY} -m pip`;
      DevTask.shell(`${pipBin} uninstall -y conan 2>&1`,
        (_t: string, _e: boolean) => {},
        (ok: boolean, _d: string) => {
          this.conanBusy = false;
          if (ok) { DevToast.ok($r('app.string.pkg_manager_11')); this.checkConan(); }
          else { DevToast.show($r('app.string.pkg_manager_12')); }
        });
    }, '确认卸载');
  }

  @Builder
  buildPageHeader() {
    DevPageHeader({
      title: 'Conan 组件库',
      subtitle: '鸿蒙 C/C++ 组件库',
      showDivider: false,
    })
    .margin({ bottom: 12 })
  }

  // ─── 安装进度条 ──────────────────────────────────────────────


  // ─── PATH 提示横幅 ──────────────────────────────────────────

  @Builder
  buildPathBanner() {
    Row({ space: 10 }) {
      DevChip({ text: '提示', tone: 'info', mono: false })
      Text($r('app.string.pkg_manager_13'))
        .fontSize(DevTheme.FS_BODY)
        .fontColor(DevTheme.TEXT_SECONDARY)
        .layoutWeight(1)
      DevBtn({
        text: '一键添加 PATH',
        buttonSize: 'small',
        plain: true,
          onTap: () => {
          this.addPathToEnv();
          },
        })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .borderRadius(DevTheme.RADIUS_LG)
    .backgroundColor(DevTheme.BG_ACCENT_INFO)
    .border({ width: 1, color: DevTheme.BORDER })
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 12 })
  }

  // ─── 浏览视图 ────────────────────────────────────────────────

  // ═══ Tab 3: 远程仓库（conan remote 管理——cruiz 核心功能适配） ═══


  // ═══ Tab 4: 配置（conan profile + 环境概览） ═══



  @Builder
  buildBrowseView() {
    Column() {
      // 搜索框（tab 下方——brew/tools 同位同款）
      DevInput({
        value: this.searchKeyword,
        placeholder: '搜索组件（名称/描述）…',
        mono: false,
        onChange: (v: string) => {
          this.searchKeyword = v;
          this.applyFilter();
        },
      })
      .margin({ bottom: 8 })

      // 已装 chips + 检查更新（右侧——brew 顶行操作栏同构）
      Row() {
        this.buildInstalledFilter()
        Blank()
        DevBtn({
          text: '刷新', buttonSize: 'mini', plain: true,
          onTap: () => { this.loadData(); },
        })
      }.width('100%').margin({ bottom: 8 })

      // ── 三分支（brew/工具页同规）：加载/错误 → 原有态；空集 → 全宽空态
      //（无右侧面板防闪现）；有行 → 主从布局 ──
      if (this.loadState === PkgLoadState.LOADING) {
        this.buildLoadingState()
      } else if (this.loadState === PkgLoadState.ERROR) {
        this.buildErrorState()
      } else if (this.filteredList.length === 0) {
        Column({ space: 8 }) {
          Text($r('app.string.pkg_manager_14'))
            .fontSize(DevTheme.FS_H3).fontColor(DevTheme.TEXT_TERTIARY)
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Row({ space: 10 }) {
          // ── 左列表（38%）：BrewListRow 行 + 分页 ──
          Column({ space: 4 }) {
            Scroll() {
              Column({ space: 3 }) {
                ForEach(this.pagedList(), (pkg: PkgItem) => {
                  BrewListRow({
                    name: pkg.name,
                    desc: this.rowDescOf(pkg),
                    ver: pkg.version,
                    meta: pkg.category,
                    selected: pkg.name === this.selectedPkgName,
                    installed: this.isInstalled(pkg),
                    canUpgrade: false,
                    installing: this.installPkgName === pkg.name
                      && this.installStep > STEP_IDLE && this.installStep < STEP_DONE,
                    deprecated: false,
                    onRowClick: () => { this.selectPkg(pkg); },
                  })
                }, (pkg: PkgItem, idx: number) =>
                  `${idx}_${pkg.name}_${this.isInstalled(pkg)}_${this.refreshTick}_${this.installPkgName === pkg.name}`)
              }.width('100%')
            }
            .width('100%').layoutWeight(1)
            .align(Alignment.TopStart)

            // ── 分页（左列内——brew 同款） ──
            Column({ space: 2 }) {
              Text(`共 ${this.filteredList.length} 个`)
                .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
              DevPagination({
                currentPage: this.currentPage,
                totalItems: this.filteredList.length,
                itemsPerPage: this.pageSize,
                onChange: (p: number) => { this.currentPage = p; },
              })
            }.width('100%').alignItems(HorizontalAlign.Center).padding({ top: 4, bottom: 8 })
          }
          .width('38%').height('100%')

          // ── 右详情卡（brew 详情面板同款样式） ──
          Scroll() {
            this.buildPkgDetailPanel()
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
          if (h > 80) { this.pageSize = PageCalc.computePageSize(h); }
        })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  /** 右详情面板——brew 详情设计语言完全对齐（Hero / DevCard 分节 / KV 行 /
   *  mono 芯片 / DevCommandBlock / 操作卡；间距 14/6、底距 28 同款） */
  @Builder
  buildPkgDetailPanel() {
    if (this.selectedPkgItem() !== null) {
      Column({ space: 12 }) {
        if (this.detailLoading) {
          // brew 风格骨架屏（三段占位——Hero + KV 行 + 卡片骨架，比 spinner 有感）
          Column({ space: 14 }) {
            Column({ space: 6 }) {
              Text(this.selectedPkgItem() !== null ? this.selectedPkgItem()!.name : '加载中…')
                .fontSize(DevTheme.FS_H1).fontWeight(FontWeight.Bold)
                .fontColor(DevTheme.TEXT_PRIMARY).width('100%')
              Text($r('app.string.pkg_manager_15'))
                .fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_TERTIARY).width('100%')
            }.width('100%')
            DevCard({ title: '', subtitle: '', accent: '', pad: 12 }) {
              Column({ space: 8 }) {
                ForEach([0, 1, 2], (i: number) => {
                  Row({ space: 8 }) {
                    Circle({ width: 6, height: 6 }).fill(DevTheme.TEXT_TERTIARY)
                    Rect({ width: i === 0 ? '120' : '80', height: 12 })
                      .fill(DevTheme.BG_MUTED).borderRadius(4)
                  }.width('100%').padding({ top: 4 })
                }, (i: number) => `${i}`)
              }.width('100%')
            }
          }
          .width('100%')
          .padding({ top: 12 })
        } else if (this.pkgDetail !== null) {
          Column({ space: 14 }) {
            // ── Hero（brew 同款：FS_H1 标题 + 状态 chips + desc） ──
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                Text(this.pkgDetail!.name)
                  .fontSize(DevTheme.FS_H1).fontWeight(FontWeight.Bold).fontColor(DevTheme.TEXT_PRIMARY)
                  .layoutWeight(1)
                if (this.isInstalled(this.selectedPkgItem()!)) {
                  DevChip({ text: '已装', tone: 'success', mono: false })
                }
                if (this.pkgDetail!.install && this.pkgDetail!.install.mode === 'independent') {
                  DevChip({ text: '独立安装', tone: 'neutral', mono: false })
                }
              }.width('100%')
              if (this.pkgDetail!.description.length > 0) {
                Text(this.pkgDetail!.description)
                  .fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_TERTIARY)
                  .width('100%')
              }
            }.width('100%')

            // ── 版本选择器（多版本时显示——brew/tools 页同规；单版本不渲染） ──
            if (this.selectedPkgItem() !== null) {
              if (PkgRepository.versionsOf(this.selectedPkgItem()!.name).length > 1) {
                Column({ space: 6 }) {
                  Text($r('app.string.pkg_manager_16'))
                    .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
                  Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                    ForEach(PkgRepository.versionsOf(this.selectedPkgItem()!.name), (ver: string) => {
                      DevChip({
                        text: ver,
                        tone: this.selectedPkgVer === ver ? 'primary' : 'neutral',
                        mono: true,
                      })
                        .margin({ right: 6, bottom: 6 })
                        .onClick(() => { this.selectPkgVersion(ver); })
                    }, (ver: string) => `${ver}_${this.selectedPkgVer === ver}`)
                  }.width('100%')
                }.width('100%')
              }
            }

            // ── 键值区（DevCard 分节 + DevKVRow） ──
            DevCard({ title: '详情', subtitle: '', accent: '', pad: 12 }) {
              Column({ space: 6 }) {
                DevKVRow({ k: '最新版本', v: this.pkgDetail!.version, copyable: true, mono: true })
                if (this.pkgDetail!.license.length > 0) {
                  DevKVRow({ k: '许可证', v: this.pkgDetail!.license, copyable: true, mono: true })
                }
                DevKVRow({ k: '分类', v: this.pkgDetail!.category, copyable: false, mono: false })
                DevKVRow({ k: '包大小', v: this.formatSize(this.pkgDetail!.size_compressed), copyable: false, mono: true })
              }.width('100%')
            }

            // ── 依赖（brew 同款：mono 芯片 + BG_ACCENT_PRIMARY 底色） ──
            if (this.pkgDetail!.requires.length > 0) {
              DevCard({ title: `依赖（${this.pkgDetail!.requires.length}）`, subtitle: '', accent: '', pad: 12 }) {
                Column({ space: 6 }) {
                  Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                    ForEach(this.pkgDetail!.requires, (req: PkgRequire) => {
                      Text(req.version && req.version !== '*' ? `${req.name} ${req.version}` : req.name)
                        .fontSize(DevTheme.FS_CAPTION).fontFamily(DevTheme.MONO_FONT)
                        .fontColor(DevTheme.TEXT_SECONDARY)
                        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        .borderRadius(DevTheme.RADIUS_SM)
                        .backgroundColor(DevTheme.BG_ACCENT_PRIMARY)
                        .margin({ right: 6, bottom: 6 })
                    }, (req: PkgRequire) => `${req.name}_${req.version ?? ''}`)
                  }.width('100%')
                }.width('100%')
              }
            }

            // ── 提供的命令（brew 同款 mono 芯片） ──
            if (this.pkgDetail!.commands.length > 0) {
              DevCard({ title: `提供命令（${this.pkgDetail!.commands.length}）`, subtitle: '', accent: '', pad: 12 }) {
                Column({ space: 6 }) {
                  Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                    ForEach(this.pkgDetail!.commands, (cmd: PkgCommand) => {
                      Text(cmd.name)
                        .fontSize(DevTheme.FS_CAPTION).fontFamily(DevTheme.MONO_FONT)
                        .fontColor(DevTheme.TEXT_SECONDARY)
                        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        .borderRadius(DevTheme.RADIUS_SM)
                        .backgroundColor(DevTheme.BG_ACCENT_PRIMARY)
                        .margin({ right: 6, bottom: 6 })
                    }, (cmd: PkgCommand) => cmd.name)
                  }.width('100%')
                }.width('100%')
              }
            }

            // ── 二进制兼容矩阵（conan list "ref:*"——Conan 2.x 官方通道，
            //    取代旧 search --json；显示远端有哪些 settings 组合的预编译包） ──
            if (this.binaryMatrix.length > 0) {
              DevCard({ title: `二进制兼容（${this.binaryMatrix.length} 个预编译配置）`, subtitle: '', accent: '', pad: 12 }) {
                Column({ space: 6 }) {
                  ForEach(this.binaryMatrix, (row: Record<string, string>, idx: number) => {
                    Row({ space: 6 }) {
                      DevChip({ text: `${row['os'] ?? '—'}/${row['arch'] ?? '—'}`, tone: 'info', mono: false })
                      DevChip({ text: `${row['compiler'] ?? '—'} ${row['compiler.version'] ?? ''}`, tone: 'neutral', mono: true })
                      if (row['build_type'] !== undefined) {
                        DevChip({ text: row['build_type'], tone: 'neutral', mono: false })
                      }
                      if (row['shared'] !== undefined) {
                        DevChip({ text: `shared=${row['shared']}`, tone: 'neutral', mono: true })
                      }
                    }
                    .width('100%').padding({ top: 2, bottom: 2 })
                  }, (row: Record<string, string>, idx: number) => `${idx}_${row['os']}_${row['arch']}`)
                  if (this.binaryMatrix.length > 6) {
                    Text(`仅显示前 6 个（共 ${this.binaryMatrix.length} 个配置）`)
                      .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
                      .width('100%').padding({ top: 4 })
                  }
                }.width('100%')
              }
            }

            // ── 构建溯源（DevCard KV 行） ──
            if (this.pkgDetail!.build_trace) {
              DevCard({ title: '构建溯源', subtitle: '', accent: '', pad: 12 }) {
                Column({ space: 6 }) {
                  if (this.pkgDetail!.build_trace!.compiler && this.pkgDetail!.build_trace!.compiler!.length > 0) {
                    DevKVRow({ k: '编译器', v: this.pkgDetail!.build_trace!.compiler!, copyable: false, mono: true })
                  }
                  if (this.pkgDetail!.build_trace!.system && this.pkgDetail!.build_trace!.system!.length > 0) {
                    DevKVRow({ k: '构建系统', v: this.pkgDetail!.build_trace!.system!, copyable: false, mono: true })
                  }
                  if (this.pkgDetail!.build_trace!.timestamp && this.pkgDetail!.build_trace!.timestamp!.length > 0) {
                    DevKVRow({ k: '构建时间', v: this.pkgDetail!.build_trace!.timestamp!, copyable: false, mono: true })
                  }
                }.width('100%')
              }
            }

            // ── 测试报告（DevStatusDot 行——brew 详详情卡同构） ──
            if (this.pkgDetail!.test_report) {
              DevCard({ title: '测试报告', subtitle: '', accent: '', pad: 12 }) {
                Column({ space: 8 }) {
                  DevStatusDot({
                    status: this.testStatus(this.pkgDetail!.test_report!.status),
                    label: this.pkgDetail!.test_report!.status === 'passed' ? '全部通过' :
                      (this.pkgDetail!.test_report!.status === 'failed' ? '存在失败' : '未测试'),
                    dotSize: 8,
                  })
                  if (this.pkgDetail!.test_report!.official_test) {
                    DevStatusDot({
                      status: this.testStatus(this.pkgDetail!.test_report!.official_test!.status),
                      label: `官方：${this.phaseLabel(this.pkgDetail!.test_report!.official_test!)}`,
                      dotSize: 7,
                    })
                  }
                  if (this.pkgDetail!.test_report!.platform_test) {
                    DevStatusDot({
                      status: this.testStatus(this.pkgDetail!.test_report!.platform_test!.status),
                      label: `平台：${this.phaseLabel(this.pkgDetail!.test_report!.platform_test!)}`,
                      dotSize: 7,
                    })
                  }
                  if (this.pkgDetail!.test_report!.baseline_test) {
                    DevStatusDot({
                      status: this.testStatus(this.pkgDetail!.test_report!.baseline_test!.status),
                      label: `基线：${this.phaseLabel(this.pkgDetail!.test_report!.baseline_test!)}`,
                      dotSize: 7,
                    })
                  }
                  if (this.pkgDetail!.test_report!.security_scan) {
                    DevStatusDot({
                      status: this.testStatus(this.pkgDetail!.test_report!.security_scan!.status),
                      label: `安全：${this.phaseLabel(this.pkgDetail!.test_report!.security_scan!)}`,
                      dotSize: 7,
                    })
                  }
                }.width('100%')
              }
            }

            // ── 相关链接（brew 主页 KV 行同构） ──
            if ((this.pkgDetail!.source_url && this.pkgDetail!.source_url.length > 0)
              || (this.pkgDetail!.adaptation_url && this.pkgDetail!.adaptation_url.length > 0)) {
              DevCard({ title: '相关链接', subtitle: '', accent: '', pad: 12 }) {
                Column({ space: 6 }) {
                  if (this.pkgDetail!.source_url && this.pkgDetail!.source_url.length > 0) {
                    DevKVRow({ k: '源码地址', v: this.pkgDetail!.source_url, copyable: true, mono: true })
                  }
                  if (this.pkgDetail!.adaptation_url && this.pkgDetail!.adaptation_url.length > 0) {
                    DevKVRow({ k: '适配代码', v: this.pkgDetail!.adaptation_url, copyable: true, mono: true })
                  }
                }.width('100%')
              }
            }
          }.width('100%')
        } else {
          // 详情不可用（conan show 失败/超时）：降级基础信息——brew 空态同构
          Column({ space: 12 }) {
            Text(this.selectedPkgItem()!.name)
              .fontSize(DevTheme.FS_H1).fontWeight(FontWeight.Bold).fontColor(DevTheme.TEXT_PRIMARY)
              .width('100%')
            DevChip({ text: `v${this.selectedPkgItem()!.version}`, tone: 'neutral', mono: true })
            Text($r('app.string.pkg_manager_17'))
              .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
              .width('100%').padding({ top: 4 })
          }.width('100%')
        }

        // ── 操作区（brew 安装/管理卡同构：命令块+全宽按钮+错误行+进度条） ──
        if (this.selectedPkgItem() !== null) {
          if (!this.isInstalled(this.selectedPkgItem()!)) {
            DevCard({ title: '安装', subtitle: '', accent: '', pad: 12 }) {
              Column({ space: 10 }) {
                DevCommandBlock({
                  command: this.getInstallCmd(this.selectedPkgItem()!),
                  footnote: '安装此组件',
                }).width('100%')
                if (this.installPkgName === this.selectedPkgItem()!.name
                  && this.installStep > STEP_IDLE && this.installStep < STEP_DONE) {
                  DevRowProgress({
                    progress: Math.round(((this.installStep + 1) / 7) * 100),
                    trailingText: `${Math.round(((this.installStep + 1) / 7) * 100)}%`,
                    trailingWidth: 40,
                    subTrailingText: this.installProgress,
                    subTrailingWidth: 90,
                  })
                  DevBtn({
                    text: '取消安装', buttonSize: 'normal', plain: true, danger: true,
                    onTap: () => { this.cancelInstall(); },
                  }).width('100%')
                } else if (this.installPkgName === this.selectedPkgItem()!.name
                  && this.installStep === STEP_FAILED) {
                  DevBtn({
                    text: '重试安装', buttonSize: 'normal',
                    onTap: () => { this.execInstall(this.selectedPkgItem()!); },
                  }).width('100%')
                } else {
                  DevBtn({
                    text: '安装', buttonSize: 'normal',
                    onTap: () => { this.execInstall(this.selectedPkgItem()!); },
                  }).width('100%')
                }
                DevBtn({
                  text: '仅下载到本地', buttonSize: 'normal', plain: true,
                  onTap: () => { this.execDownload(this.selectedPkgItem()!); },
                }).width('100%')
                if (this.installPkgName === this.selectedPkgItem()!.name && this.installStep === STEP_FAILED) {
                  Text(this.installProgress)
                    .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.DANGER)
                    .width('100%').padding({ top: 4 })
                }
              }.width('100%')
            }
          } else {
            DevCard({ title: '管理', subtitle: '', accent: '', pad: 12 }) {
              Column({ space: 10 }) {
                DevCommandBlock({
                  command: this.getInstallCmd(this.selectedPkgItem()!),
                  footnote: '安装此组件',
                }).width('100%')
                DevCommandBlock({
                  command: `conan remove ${this.selectedPkgItem()!.name}/${this.selectedPkgItem()!.version} -c -f`,
                  footnote: '从 conan 缓存和本地部署中移除',
                }).width('100%')
                if (this.installPkgName === this.selectedPkgItem()!.name
                  && this.installStep > STEP_IDLE && this.installStep < STEP_DONE) {
                  DevRowProgress({
                    progress: Math.round(((this.installStep + 1) / 7) * 100),
                    trailingText: `${Math.round(((this.installStep + 1) / 7) * 100)}%`,
                    trailingWidth: 40,
                    subTrailingText: this.installProgress,
                    subTrailingWidth: 90,
                  })
                } else {
                  DevBtn({
                    text: '卸载', buttonSize: 'normal', danger: true,
                    onTap: () => { this.uninstallPkg(this.selectedPkgItem()!); },
                  }).width('100%')
                }
              }.width('100%')
            }
          }
        }
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 28 })
    }
  }

  // ─── 分类标签栏 ──────────────────────────────────────────────

  @Builder
  buildInstalledFilter() {
    // 只留 全部/已安装 两选项（"未安装"冗余——brew/tools 页同规精简后
    // 的形态；点"全部"已涵盖未装）
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      DevChip({ text: '全部', tone: this.selectedCategory === '' ? 'primary' : 'neutral', mono: false })
        .margin({ right: 6, bottom: 6 })
        .onClick(() => { this.selectedCategory = ''; this.applyFilter(); })
      DevChip({ text: '已安装', tone: this.selectedCategory === '__installed' ? 'primary' : 'neutral', mono: false })
        .margin({ right: 6, bottom: 6 })
        .onClick(() => { this.selectedCategory = '__installed'; this.applyFilter(); })
    }.width('auto').layoutWeight(1)
  }


  @Builder
  buildLoadingState() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color(DevTheme.PRIMARY)
      Text($r('app.string.pkg_manager_18'))
        .fontSize(DevTheme.FS_BODY)
        .fontColor(DevTheme.TEXT_MUTED)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildErrorState() {
    Column() {
      DevEmpty({
        text: '组件列表加载失败',
        hint: this.statusMsg,
        image: 'default',
      }) {
        DevBtn({
          text: '重新加载',
          buttonSize: 'small',
          plain: true,
            onTap: () => {
            this.loadData();
            },
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
}
