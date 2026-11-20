/**
 * Node.js 管理 —— 四 Tab 全功能页（与 Python 页同架构）
 * Tab 0 运行时 | Tab 1 镜像管理（npm registry） | Tab 2 包管理 | Tab 3 项目管理
 */
import { common } from '@kit.AbilityKit';
import { LangRuntimePage, LangRuntimeConfig, DevCard, DevChip, DevInput, DevToast, DevEmpty, DevPkgRow, DevPkgData } from '../common/component';
import { DevPagination, PageCalc } from '../common/component';
import { DevTheme } from '../common/DevTheme';
import fs from '@ohos.file.fs';
import { DevTask } from '../utils/DevTask';
import { PkgInstallFlow, InstallingPkg } from '../utils/PkgInstallFlow';
import { DiscoveryService } from '../utils/DiscoveryService';
import { NpmCatalogService, NpmCatalogEntry } from '../utils/NpmCatalogService';
import { FeatureScope } from '../utils/FeatureScope';








const HOME = '/storage/Users/currentUser';
const NODE_BIN = `${HOME}/usr/local/node/current/bin/node`;
// npm 入口不依赖 bin/npm 符号链接（tarball 内是相对软链，解压后不可靠）：
// 统一 node + npm-cli.js 绝对路径，均经 current 链接跟随活跃版本
const NPM_CLI = `${HOME}/usr/local/node/current/lib/node_modules/npm/bin/npm-cli.js`;
const NPM_CMD = `'${NODE_BIN}' '${NPM_CLI}'`;

interface NpmSource {
  name: string;
  url: string;
}

function nodeCfg(): LangRuntimeConfig {
  return {
    langKey: 'node',
    title: 'Node.js',
    subtitle: 'Node.js · 版本管理 · npm 源 · 全局包管理',
    sourceLabel: 'OHPCD 制品仓',
    sourcePending: false,
    installed: [],
    available: [],
    ecoTabs: [],
    tabLabels: FeatureScope.PROJECT_TAB ? ['运行时', '镜像管理', '包管理', '项目管理'] : ['运行时', '镜像管理', '包管理'],   // 商用范围开关（utils/FeatureScope.ets）
  };
}

let cachedNpmSources: NpmSource[] = [];
let cachedNpmActive: string = '';
let cachedNpmPkgs: string[] = [];

@Component
export struct NodeManager {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @State npmSources: NpmSource[] = [];
  @State npmActive: string = '';
  @State pkgTab: number = 0;
  @State npmPkgs: string[] = [];
  @State pkgSearch: string = '';
  @State catalogReady: boolean = false;
  @State catalogPage: number = 1;
  @State pageSize: number = 15;
  private pkgViewportH: number = 0;
  @State nodeRuntimeOk: boolean = false;
  @State installingList: InstallingPkg[] = [];
  @StorageProp('npmcatalog_epoch') @Watch('onCatalogReady') npmEpoch: number = 0;
  @StorageProp('task_queue_epoch') @Watch('onQueueEpoch') queueEpoch: number = 0;  // 队列位次实时刷新
  // 已安装列表 = 活跃版本的 lib/node_modules（npm 入口经 current 链接跟随活跃版本）
  @State npmLoading: boolean = false;
  private npmQuerySeq: number = 0;  // 查询序号：丢弃过期响应
  // 活跃运行时变化（装/切/卸版本后 800ms bump、全局刷新）→ 解释器换了，npm 列表与镜像状态必须重查
  @StorageProp('runtime_epoch') @Watch('onRuntimeEpoch') runtimeEpoch: number = 0;

  // 包安装流引擎（utils/PkgInstallFlow.ets）：去重/爬升/补间/三分支/队列/取消单份实现；
  // 本页只注入差异——npm 命令模板（-g --no-fund 等参数）、盲文 spinner 剥除净化、
  // npm 里程碑与阶段文案表、'npm' 互斥组、npm_install_ tag、无日志窗、收尾 2s 延迟重查
  private flow: PkgInstallFlow = new PkgInstallFlow({
    queueGroup: 'npm',
    tagPrefix: 'npm_install_',
    // --no-progress：禁 TTY spinner（乱码源头）；--no-fund/--no-audit：去噪声行
    // NO_COLOR=1：源头禁 ANSI 色码——npm 错误行色码被行分割切断后残片会漏净化进失败 toast
    command: (name: string, _adapted: boolean): string =>
      `NO_COLOR=1 ${NPM_CMD} install -g ${name} --no-progress --no-fund --no-audit 2>&1`,
    cleanLine: (raw: string): string => NodeManager.cleanNpmLine(raw),
    phasePct: (line: string): number => NodeManager.npmPhasePct(line),
    stageLabel: (p: number): string => NodeManager.stageLabel(p),
    getInstalling: (): InstallingPkg[] => this.installingList,
    setInstalling: (list: InstallingPkg[]): void => { this.installingList = list; },
    onEnqueued: (): void => { this.pkgTab = 3; },
    // npm 落盘有延迟：收尾 2s 后再重查（pip 侧立即重查——语义差异保留）
    refreshInstalled: (): void => { setTimeout(() => { this.refreshNpmPkgs(); }, 2000); },
  });

  aboutToAppear(): void {
    NpmCatalogService.init(getContext(this) as common.UIAbilityContext);
    NpmCatalogService.ensure();

    this.npmSources = cachedNpmSources;
    this.npmActive = cachedNpmActive;
    this.checkNodeRuntime();
    this.npmPkgs = cachedNpmPkgs;
    if (cachedNpmSources.length === 0) { this.refreshNpmSources(); }
    if (cachedNpmPkgs.length === 0) { this.refreshNpmPkgs(); }

    this.catalogReady = NpmCatalogService.ready();
  }

  private onCatalogReady(): void {
    this.catalogReady = NpmCatalogService.ready();
  }

  /** 活跃运行时变化：npm -g 归属新 node_modules，重查列表与镜像生效状态 */
  private onRuntimeEpoch(): void {
    this.checkNodeRuntime();
    this.refreshNpmPkgs();
    this.refreshNpmSources();
  }

  private checkNodeRuntime(): void {
    // fs 判存在（npm 入口=node+npm-cli.js，bin/npm 软链不可靠不作为判据）
    let ok: boolean = false;
    try { ok = fs.accessSync(NODE_BIN); } catch (_) {
    }
    this.nodeRuntimeOk = ok;
  }

  // ══════════════ Tab 1: 镜像管理 ══════════════

  private refreshNpmSources(): void {
    const lines: string[] = [];
    DevTask.shell(`${NPM_CMD} config get registry 2>/dev/null`,
      (t: string, _e: boolean) => lines.push(t),
      (_ok: boolean, _d: string) => {
        this.npmActive = lines.join('\n').trim();
        cachedNpmActive = this.npmActive;
        const list: NpmSource[] = [];
        const rec = DiscoveryService.latest().recommendedNpmRegistry();
        if (rec !== '') { list.push({ name: 'OHPCD 推荐', url: rec }); }
        list.push({ name: 'npmmirror（淘宝）', url: 'https://registry.npmmirror.com' });
        list.push({ name: 'CNB', url: 'https://npm.cnb.cool/openharmonypcdeveloper/npm' });
        list.push({ name: '华为云', url: 'https://repo.huaweicloud.com/repository/npm/' });
        list.push({ name: '腾讯云', url: 'https://mirrors.cloud.tencent.com/npm/' });
        list.push({ name: 'npm 官方', url: 'https://registry.npmjs.org' });
        this.npmSources = list;
        cachedNpmSources = list;
      });
  }

  /** registry 归一化比对（容忍尾斜杠差异：华为云/腾讯云预置带 /，npm 实际返回不带） */
  private sameRegistry(a: string, b: string): boolean {
    const norm = (u: string): string => u.trim().replace(/\/+$/, '');
    return norm(a) === norm(b);
  }

  private activateSource(src: NpmSource): void {
    DevTask.shell(`${NPM_CMD} config set registry '${src.url}'`,
      (_t: string, _e: boolean) => {},
      (_ok: boolean, _d: string) => {
        this.npmActive = src.url;
        cachedNpmActive = src.url;
        DevToast.ok(`已切换到 ${src.name}`);
      });
  }

  @Builder
  buildMirrorTab() {
    Column({ space: 12 }) {
      DevCard({ title: '当前源', subtitle: '', accent: '', pad: 12 }) {
        Column({ space: 6 }) {
          Text(this.npmActive !== '' ? this.npmActive : '未配置')
            .fontSize(DevTheme.FS_BODY)
            .fontFamily(DevTheme.MONO_FONT)
            .fontColor(DevTheme.TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text($r('app.string.node_manager_1'))
            .fontSize(DevTheme.FS_CAPTION)
            .fontColor(DevTheme.TEXT_TERTIARY)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      DevCard({ title: `可用源 (${this.npmSources.length})`, subtitle: '点击切换', accent: '', pad: 12 }) {
        Column() {
          ForEach(this.npmSources, (src: NpmSource, idx: number) => {
            Row({ space: 8 }) {
              Circle({ width: 6, height: 6 })
                .fill(this.sameRegistry(this.npmActive, src.url) ? DevTheme.SUCCESS : DevTheme.BORDER)
              Column({ space: 1 }) {
                Text(src.name)
                  .fontSize(DevTheme.FS_BODY)
                  .fontColor(DevTheme.TEXT_PRIMARY)
                Text(src.url)
                  .fontSize(DevTheme.FS_CAPTION)
                  .fontColor(DevTheme.TEXT_TERTIARY)
                  .fontFamily(DevTheme.MONO_FONT)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 6, bottom: 6 })
            .onClick(() => { this.activateSource(src); })
          }, (src: NpmSource, idx: number) => `${src.name}_${this.sameRegistry(this.npmActive, src.url)}_${idx}`)
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  // ══════════════ Tab 2: 包管理 ══════════════

  /** 树行 → 包名（scoped 安全：@scope/pkg@1.0 → @scope/pkg；无版本原样） */
  private pkgNameOf(line: string): string {
    const clean = line.replace(/[├└─│\s]+/g, '');
    const idx = clean.lastIndexOf('@');
    return idx > 0 ? clean.substring(0, idx) : clean;
  }

  /** 树行 → 版本（末段 @ 之后；无版本返回空） */
  private pkgVerOf(line: string): string {
    const clean = line.replace(/[├└─│\s]+/g, '');
    const idx = clean.lastIndexOf('@');
    return idx > 0 ? clean.substring(idx + 1) : '';
  }

  private isNpmPkgInstalled(name: string): boolean {
    for (const line of this.npmPkgs) {
      if (this.pkgNameOf(line).toLowerCase() === name.toLowerCase()) { return true; }
    }
    return false;
  }

  private installedNpmVer(name: string): string {
    for (const line of this.npmPkgs) {
      if (this.pkgNameOf(line).toLowerCase() === name.toLowerCase()) {
        return this.pkgVerOf(line);
      }
    }
    return '';
  }

  private refreshNpmPkgs(): void {
    this.npmLoading = true;
    const seq: number = ++this.npmQuerySeq;
    const lines: string[] = [];
    DevTask.shell(`${NPM_CMD} list -g --depth=0 2>&1 | tail -n +2 | head -300`,
      (t: string, _e: boolean) => lines.push(t),
      (_ok: boolean, _d: string) => {
        if (seq !== this.npmQuerySeq) { return; }  // 过期响应（期间又切了版本），丢弃
        // 过滤 npm 树输出噪声："(empty)"（零包占位行）与无版本号的提示行
        this.npmPkgs = lines.filter((s: string): boolean => {
          const t: string = s.trim();
          return t !== '' && t.indexOf('(empty)') < 0 && t.indexOf('npm ERR') < 0 && /@[0-9]/.test(t);
        });
        cachedNpmPkgs = this.npmPkgs;
        this.npmLoading = false;
        // fail loud：npm 实际报错时不能静默显示"暂无全局包"（有输出但全被过滤 ≈ stderr 报错）。
        // 排除正常空列表态：零包时 npm ls -g 输出仅一行树根目录路径（无 @版本），
        // 不含 ERR/error 才静默（真机实证：node 装完未装包时误报「查询异常」）
        if (this.npmPkgs.length === 0) {
          const rawLines: string[] = lines.map((s: string): string => s.trim())
            .filter((s: string): boolean => s !== '');
          const errLine: string | undefined = rawLines.find((l: string): boolean =>
            /ERR|error|not found|denied|EACCES/i.test(l));
          if (errLine !== undefined) { DevToast.show(`npm 列表查询异常：${errLine.slice(0, 60)}`); }
        }
      });
  }

  private installPkg(name: string): void {
    // fs 判存在守卫（省一次 shell spawn）
    let ok: boolean = false;
    try { ok = fs.accessSync(NODE_BIN); } catch (_) {
    }
    if (!ok) { DevToast.show($r('app.string.node_manager_2')); return; }
    this.flow.install(name, false);
  }

  /** npm 输出净化：ANSI 转义序列/盲文 spinner/控制字符 → 干净单行（乱码根因；仅用于关键字匹配） */
  private static cleanNpmLine(s: string): string {
    return s
      .replace(/\u001b\[[0-9;?]*[a-zA-Z]/g, '')
      // 跨行切断的色码残片（裸 [NNm——无 ESC 前缀）：只剥 纯数字/分号+m 形态，不误伤普通 [标签]
      .replace(/\[[0-9;]{1,5}m/g, '')
      .replace(/[\u2800-\u28ff]/g, '')
      .replace(/[\u0000-\u001f]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  /** npm 输出 → 进度里程碑（npm 无全局百分比；关键字映射 + 时间爬升兜底） */
  private static npmPhasePct(line: string): number {
    if (line.startsWith('added') || line.startsWith('removed')) { return 92; }
    if (line.indexOf('reify:') >= 0) { return 45; }
    if (line.indexOf('link:') >= 0 || line.indexOf('build:') >= 0) { return 68; }
    if (line.indexOf('idealTree') >= 0 || line.indexOf('resolve') >= 0) { return 18; }
    return 0;   // 不识别 → 不动（靠时间爬升推进）
  }

  /** 进度档位 → 阶段文案（显示层不再透出 npm 原始输出行） */
  private static stageLabel(p: number): string {
    if (p >= 100) { return '完成'; }
    if (p >= 92) { return '写入完成'; }
    if (p >= 68) { return '链接与构建…'; }
    if (p >= 45) { return '下载并解包…'; }
    if (p >= 18) { return '解析依赖…'; }
    return '准备安装…';
  }

  /** 取消包安装（npm 幂等，重装恢复） */
  /** 队列位次实时更新（引擎单份实现；排队行位次随队列推进/出队刷新） */
  private onQueueEpoch(): void {
    this.flow.onQueueEpoch();
  }

  /** 取消双路（引擎单份实现）：排队中先出队；running 杀进程 + 取消标记 */
  private cancelPkgInstall(name: string): void {
    this.flow.cancelInstall(name);
  }

  private uninstallPkg(line: string): void {
    const name = this.pkgNameOf(line);
    if (name === '') { return; }
    DevToast.show(`正在卸载 ${name}…`);
    DevTask.shell(`${NPM_CMD} uninstall -g ${name} 2>&1`,
      (_t: string, _e: boolean) => {},
      (ok: boolean, _d: string) => {
        if (ok) {
          DevToast.ok(`${name} 已卸载`);
          this.refreshNpmPkgs();
        } else {
          DevToast.show(`${name} 卸载失败`);
        }
      });
  }

  private pkgData(line: string): DevPkgData {
    return {
      name: this.pkgNameOf(line), ver: this.pkgVerOf(line), desc: '', sizeLabel: '',
      installed: true, inPath: false, canUpdate: false, progress: -1, showInstall: false, isLatest: true, hasMultiVer: false,
    };
  }

  private catalogData(e: NpmCatalogEntry): DevPkgData {
    const installed = this.isNpmPkgInstalled(e.name);
    const ver = installed ? this.installedNpmVer(e.name) : e.version;
    return {
      name: e.name, ver: ver,
      desc: e.type === 'adapted' ? '适配包' : '兼容',
      sizeLabel: '',
      installed: installed, inPath: false, canUpdate: false, progress: -1, showInstall: !installed, isLatest: true, hasMultiVer: false,
    };
  }

  @Builder
  buildPkgTab() {
    Column({ space: 10 }) {
      DevInput({ value: this.pkgSearch, placeholder: '搜索包名…', mono: false,
        onChange: (v: string) => { this.pkgSearch = v; this.catalogPage = 1; } })
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(['已安装', '适配包', '兼容包'], (label: string, idx: number) => {
          DevChip({ text: label, tone: this.pkgTab === idx ? 'primary' : 'neutral', mono: false })
            .margin({ right: 6, bottom: 6 })
            .onClick(() => { this.pkgTab = idx; this.catalogPage = 1; })
        }, (label: string, idx: number) => `${label}_${this.pkgTab === idx}`)
        DevChip({
          text: this.installingList.length > 0 ? `安装中 (${this.installingList.length})` : '安装中',
          tone: this.pkgTab === 3 ? 'primary' : 'neutral',
          mono: false,
        })
        .margin({ right: 6, bottom: 6 })
        .onClick(() => { this.pkgTab = 3; })
      }.width('100%')

      if (this.pkgTab === 0) {
        // 已安装 = 活跃版本的 lib/node_modules（切版本后自动重查）
        if (this.npmLoading && this.filteredNpmPkgs().length === 0) {
          Column({ space: 8 }) {
            LoadingProgress().width(36).height(36).color(DevTheme.PRIMARY)
            Text($r('app.string.node_manager_3')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (!this.nodeRuntimeOk && this.filteredNpmPkgs().length === 0) {
          Column({ space: 8 }) {
            Text($r('app.string.node_manager_4')).fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_TERTIARY)
            Text($r('app.string.node_manager_5')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
        Scroll() {
          Column({ space: 2 }) {
          if (this.filteredNpmPkgs().length === 0) {
            Text($r('app.string.node_manager_6')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY).padding(16)
          } else {
            ForEach(this.pagedNpmPkgs(), (line: string) => {
              DevPkgRow({ data: this.pkgData(line), onInstall: () => {}, onUninstall: () => { this.uninstallPkg(line); } })
            }, (line: string) => line)
          }
          }.width('100%')

        }
        .width('100%').layoutWeight(1)
        .align(Alignment.TopStart)
        .onAreaChange((_o: Area, n: Area) => {
            const h: number = n.height as number;
            if (h > 80) { this.pageSize = PageCalc.computePageSize(h, PageCalc.ITEM_HEIGHT_COMPACT); }
          })
        Column({ space: 2 }) {
          Text(this.npmLoading
            ? `共 ${this.filteredNpmPkgs().length} 个 · 刷新中…`
            : `共 ${this.filteredNpmPkgs().length} 个`)
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
          DevPagination({ currentPage: this.catalogPage, totalItems: this.filteredNpmPkgs().length,
            itemsPerPage: this.pageSize, onChange: (page: number) => { this.catalogPage = page; } })
        }.width('100%')
        .alignItems(HorizontalAlign.Center).padding({ top: 4, bottom: 4 })
        }
      } else if (this.pkgTab === 1) {
        if (!this.catalogReady) {
          Column({ space: 8 }) { LoadingProgress().width(36).height(36).color(DevTheme.PRIMARY)
            Text($r('app.string.env_manager_4')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 2 }) {
            ForEach(this.pagedCatalog('adapted'), (e: NpmCatalogEntry) => {
              DevPkgRow({ data: this.catalogData(e), onInstall: () => { this.installPkg(e.name); }, onUninstall: () => { this.uninstallPkg(e.name); } })
            }, (e: NpmCatalogEntry) => `${e.name}_${this.isNpmPkgInstalled(e.name)}`)
            }.width('100%')
        
          }
          .width('100%').layoutWeight(1)
          .align(Alignment.TopStart)
          .onAreaChange((_o: Area, n: Area) => {
            const h: number = n.height as number;
            this.pkgViewportH = h;
        if (h > 80) { this.pageSize = PageCalc.computePageSize(h); }
          })
          Column({ space: 2 }) {
            Text(`共 ${NpmCatalogService.searchByType(this.pkgSearch, 'adapted', 999999).length} 个`).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
            DevPagination({ currentPage: this.catalogPage,
              totalItems: NpmCatalogService.searchByType(this.pkgSearch, 'adapted', 999999).length,
              itemsPerPage: this.pageSize, onChange: (page: number) => { this.catalogPage = page; } })
          }.width('100%')
        .alignItems(HorizontalAlign.Center).padding({ top: 4, bottom: 4 })
        }
      } else if (this.pkgTab === 2) {
        if (!this.catalogReady) {
          Column({ space: 8 }) { LoadingProgress().width(36).height(36).color(DevTheme.PRIMARY)
            Text($r('app.string.env_manager_4')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 2 }) {
            ForEach(this.pagedCatalog('compatible'), (e: NpmCatalogEntry) => {
              DevPkgRow({ data: this.catalogData(e), onInstall: () => { this.installPkg(e.name); }, onUninstall: () => { this.uninstallPkg(e.name); } })
            }, (e: NpmCatalogEntry) => `${e.name}_${this.isNpmPkgInstalled(e.name)}`)
            }.width('100%')
        
          }
          .width('100%').layoutWeight(1)
          .align(Alignment.TopStart)
          .onAreaChange((_o: Area, n: Area) => {
            const h: number = n.height as number;
            this.pkgViewportH = h;
        if (h > 80) { this.pageSize = PageCalc.computePageSize(h); }
          })
          Column({ space: 2 }) {
            Text(`共 ${NpmCatalogService.searchByType(this.pkgSearch, 'compatible', 999999).length} 个`).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
            DevPagination({ currentPage: this.catalogPage,
              totalItems: NpmCatalogService.searchByType(this.pkgSearch, 'compatible', 999999).length,
              itemsPerPage: this.pageSize, onChange: (page: number) => { this.catalogPage = page; } })
          }.width('100%')
        .alignItems(HorizontalAlign.Center).padding({ top: 4, bottom: 4 })
        }
      } else {
        // 安装中
        if (this.installingList.length === 0) {
          Column({ space: 12 }) {
            Text('⊘').fontSize(32).fontColor(DevTheme.TEXT_MUTED)
            Text($r('app.string.node_manager_7')).fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_TERTIARY)
            Text($r('app.string.node_manager_8')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else {
          Scroll() {
            Column({ space: 4 }) {
              ForEach(this.installingList, (item: InstallingPkg) => {
                DevPkgRow({
                  data: { name: item.name, ver: '', desc: item.phase !== '' ? item.phase : this.flow.stageLabel(item.progress), sizeLabel: '',
                    installed: false, inPath: false, canUpdate: false, progress: item.progress, showInstall: false, isLatest: true, hasMultiVer: false },
                  onInstall: () => {}, onUninstall: () => {},
                  hasCancelInstall: true, onCancelInstall: (n: string): void => { this.cancelPkgInstall(n); } })
              }, (item: InstallingPkg) => item.name)
            }.width('100%')
          }
          .width('100%').layoutWeight(1)
          .align(Alignment.TopStart)
        }
      }
    }.width('100%').height('100%').padding({ bottom: 16 })
    .onAreaChange((_o: Area, n: Area) => {
      const h: number = n.height as number;
      // pageSize 由列表容器精确计算
    })
  }

  private filteredNpmPkgs(): string[] {
    const kw = this.pkgSearch.trim().toLowerCase();
    if (kw === '') { return this.npmPkgs; }
    return this.npmPkgs.filter((s: string): boolean => s.toLowerCase().indexOf(kw) >= 0);
  }

  private pagedNpmPkgs(): string[] {
    const all = this.filteredNpmPkgs();
    const start = (this.catalogPage - 1) * this.pageSize;
    return all.slice(start, start + this.pageSize);
  }
  private pagedCatalog(type: string): NpmCatalogEntry[] {
    const all = NpmCatalogService.searchByType(this.pkgSearch, type, 999999);
    const start = (this.catalogPage - 1) * this.pageSize;
    return all.slice(start, start + this.pageSize);
  }

  @Builder
  buildProjectTab() {
    DevEmpty({ text: '项目管理', hint: 'Node.js 项目识别与 npm scripts 将随后续版本提供', image: 'default' })
  }

  build() {
    LangRuntimePage({
      cfg: nodeCfg(),
      tab1Content: (): void => { this.buildMirrorTab(); },
      tab2Content: (): void => { this.buildPkgTab(); },
      tab3Content: (): void => { this.buildProjectTab(); },
    })
  }
}
