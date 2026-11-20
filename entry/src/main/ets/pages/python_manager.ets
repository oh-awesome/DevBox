/**
 * Python 管理 —— 四 Tab 全功能页
 * Tab 0 运行时 | Tab 1 镜像管理 | Tab 2 包管理（四视图：安装中/已安装/适配/兼容） | Tab 3 项目管理
 */
import { LangRuntimePage, LangRuntimeConfig, DevCard, DevChip, DevBtn, DevInput, DevToast, DevConfirm, DevEmpty, DevDialogPanel, DevPkgRow, DevPkgData, DevPagination, PageCalc, termLineColor } from '../common/component';
import { DevTheme } from '../common/DevTheme';
import fs from '@ohos.file.fs';
import { DevTask } from '../utils/DevTask';
import { DiscoveryService } from '../utils/DiscoveryService';
import { PkgInstallFlow, InstallingPkg } from '../utils/PkgInstallFlow';
import { PyCatalogService, PyCatalogEntry } from '../utils/PyCatalogService';
import { PyVersionsService } from '../utils/PyVersionsService';
import { FeatureScope } from '../utils/FeatureScope';








const HOME = '/storage/Users/currentUser';
const PIP_CONF = `${HOME}/.pip/pip.conf`;
const PIP_CMD = `${HOME}/usr/local/bin/python3 -m pip`;  // 别名链（版本无关，跟 current 切换）

interface PipSource {
  name: string;
  url: string;
  trustedHost: string;
  custom: boolean;
  enabled: boolean;
}

function pyCfg(): LangRuntimeConfig {
  return {
    langKey: 'python',
    title: 'Python',
    subtitle: 'Python · 版本管理 · pip 源 · 包管理',
    sourceLabel: 'OHPCD 制品仓',
    sourcePending: false,
    installed: [],
    available: [],
    ecoTabs: [],
    tabLabels: FeatureScope.PROJECT_TAB ? ['运行时', '镜像管理', '包管理', '项目管理'] : ['运行时', '镜像管理', '包管理'],   // 商用范围开关（utils/FeatureScope.ets）
  };
}

let cachedPipSources: PipSource[] = [];
let cachedPipPkgs: string[] = [];

@CustomDialog
struct AddPipSourceDialog {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @State name: string = '';
  @State url: string = '';
  @State trustedHost: string = '';
  controller?: CustomDialogController;
  onAdd: (name: string, url: string, trustedHost: string) => void = () => {};

  build() {
    DevDialogPanel({
      title: '添加自定义源', dialogWidth: 500,
      paddingValueLeft: 20, paddingValueRight: 20, paddingValueTop: 8, paddingValueBottom: 20,
    }) {
      Column({ space: 14 }) {
        Column({ space: 6 }) {
          Text($r('app.string.python_manager_1')).fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_SECONDARY)
          DevInput({ value: this.name, placeholder: '如：公司内网', mono: false,
            onChange: (v: string) => { this.name = v; } })
        }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 6 }) {
          Text($r('app.string.python_manager_2')).fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_SECONDARY)
          DevInput({ value: this.url, placeholder: '如：pypi.company.com/simple', mono: true,
            onChange: (v: string) => { this.url = v; } })
        }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 6 }) {
          Text($r('app.string.python_manager_3')).fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_SECONDARY)
          DevInput({ value: this.trustedHost, placeholder: '如需跳过 HTTPS 校验填此项', mono: true,
            onChange: (v: string) => { this.trustedHost = v; } })
        }.width('100%').alignItems(HorizontalAlign.Start)
        Row({ space: 12 }) {
          Blank()
          DevBtn({ text: '取消', buttonSize: 'small', plain: true,
            onTap: () => { this.controller?.close(); } })
          DevBtn({ text: '添加', buttonSize: 'small',
            onTap: () => {
              if (this.name.trim() !== '' && this.url.trim() !== '') {
                this.onAdd(this.name, this.url, this.trustedHost);
                this.controller?.close();
              }
            } })
        }.width('100%')
      }.width('100%')
    }
  }
}


// ─── 版本选择器弹窗（居中 CustomDialog，数据从 AppStorage 读取） ───

@CustomDialog
struct VersionPickerDialog {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @StorageProp('vp_pkg') pkgName: string = '';
  @StorageProp('vp_versions') versionsStr: string = '';
  @StorageProp('vp_selected') selectedVer: string = '';
  @StorageProp('vp_loading') vpLoading: boolean = false;
  controller?: CustomDialogController;
  onSelect: (ver: string) => void = () => {};

  private versions(): string[] {
    return this.versionsStr.split(',').filter((s: string): boolean => s.trim() !== '');
  }

  build() {
    DevDialogPanel({
      title: `选择版本 — ${this.pkgName}`,
      dialogWidth: 420,
      paddingValueLeft: 16, paddingValueRight: 16, paddingValueTop: 8, paddingValueBottom: 16,
    }) {
      if (this.vpLoading) {
        // 版本清单网络拉取中（onPyVersionsReady 完成后自动替换为列表）
        Column({ space: 10 }) {
          LoadingProgress().width(36).height(36).color(DevTheme.PRIMARY)
          Text($r('app.string.python_manager_4')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
        }.width('100%').padding({ top: 40, bottom: 40 }).justifyContent(FlexAlign.Center)
      } else {
      Scroll() {
        Column({ space: 2 }) {
          ForEach(this.versions(), (ver: string, idx: number) => {
            Row({ space: 8 }) {
              Text(ver)
                .fontSize(DevTheme.FS_BODY)
                .fontFamily(DevTheme.MONO_FONT)
                .fontColor(DevTheme.TEXT_PRIMARY)
                .layoutWeight(1)
              if (idx === 0) {
                DevChip({ text: 'latest', tone: 'success', mono: false })
              }
              if (this.selectedVer === ver) {
                Text('✓')
                  .fontSize(14)
                  .fontColor(DevTheme.PRIMARY)
              }
            }
            .width('100%')
            .padding({ top: 8, bottom: 8, left: 12, right: 12 })
            .borderRadius(DevTheme.RADIUS_SM)
            .backgroundColor(this.selectedVer === ver ? DevTheme.BG_HOVER : Color.Transparent)
            .onClick(() => {
              this.onSelect(ver);
              this.controller?.close();
            })
          }, (ver: string, idx: number) => `${ver}_${idx}_${this.selectedVer === ver}`)
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 320 })
      }
    }
  }
}

@Component
export struct PythonManager {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @State pipSources: PipSource[] = [];
  @State dragSrcIdx: number = -1;
  @State pressedArrow: string = '';  // 行内按钮按下态  // 源列表拖拽起始索引
  @State pkgTab: number = 0;
  @State pipPkgs: string[] = [];
  @State pkgSearch: string = '';
  @State catalogPage: number = 1;
  private lastViewportH: number = 0;  // 动态实测行高
  @State pkgViewportH: number = 0;    // 包列表视口高度（分页计算）
  @State pyRuntimeOk: boolean = false; // DevBox Python 运行时可用
  @State pageSize: number = 15;
  @State catalogReady: boolean = false;
  @State installingList: InstallingPkg[] = [];
  @StorageProp('task_queue_epoch') @Watch('onQueueEpoch') queueEpoch: number = 0;
  // pip 安装流日志窗（bindSheet 半屏 + 终端风格）：净化原始输出全量实时查看
  @State logVisible: boolean = false;
  @State logName: string = '';
  @State logLines: string[] = [];
  private logScroller: Scroller = new Scroller();
  @StorageProp('pycatalog_epoch') @Watch('onCatalogReady') pycatalogEpoch: number = 0;
  // 版本选择
  @State selectedVersions: Record<string, string> = {};  // 包名 → 用户选择的版本
  @State showVersionPicker: boolean = false;
  @State versionPickerPkg: string = '';
  @State versionPickerVersions: string[] = [];
  // 已安装列表 = 活跃版本的 site-packages（PIP_CMD 永远走 current 链接）
  @State pipLoading: boolean = false;
  private pipQuerySeq: number = 0;  // 查询序号：丢弃过期响应，防旧结果覆盖新查询
  // 活跃运行时变化（安装/切换/卸载后延迟 800ms bump）→ 解释器换了，pip 列表必须重查
  @StorageProp('runtime_epoch') @Watch('onRuntimeEpoch') runtimeEpoch: number = 0;
  // 版本清单网络拉取完成（磁盘缓存不触发）→ 刷新版本选择器与行级多版本标记
  @StorageProp('pyversions_epoch') @Watch('onPyVersionsReady') pyversionsEpoch: number = 0;

  // 包安装流引擎（utils/PkgInstallFlow.ets）：去重/爬升/补间/三分支/队列/取消单份实现；
  // 本页只注入差异——pip 命令模板（版本参数+适配源）、白名单净化、pip 里程碑与
  // 阶段文案表、'pip' 互斥组、pip_install_ tag、日志窗实时追加、收尾立即重查
  private flow: PkgInstallFlow = new PkgInstallFlow({
    queueGroup: 'pip',
    tagPrefix: 'pip_install_',
    command: (name: string, adapted: boolean): string => {
      // 用户选择的版本 > catalog latest > 不指定（pip 默认最新）
      const selectedVer = this.selectedVersions[name];
      const verArg = selectedVer !== undefined && selectedVer !== '' ? `==${selectedVer}` : '';
      const source = adapted ? DiscoveryService.latest().recommendedPipIndex() : '';
      // adapted：单索引隔离——PIP_CONFIG_FILE=/dev/null 只作用于本命令进程，
      // 用户 pip.conf 原样不动；catalog 判定已适配的包必须从 OHPCD 拿适配轮，
      // 用户配置的 extra-index 会引发跨索引同版本解析歧义（numpy latest 实证：
      // 双索引下 pip 走 sdist 构建失败；pinned/单索引 wheel 直装成功）
      const recHost = DiscoveryService.latest().recommendedPipTrustedHost();
      const hostArg = recHost !== '' ? ` --trusted-host ${recHost}` : '';
      const envArg = adapted ? 'PIP_CONFIG_FILE=/dev/null ' : '';
      const sourceArg = source !== '' ? ` -i ${source}${hostArg}` : '';
      // --progress-bar off：禁下载进度条（ANSI 乱码源头）；不再 tail 截断（要流式读全部行）
      return `${envArg}${PIP_CMD} install ${name}${verArg}${sourceArg} --progress-bar off 2>&1`;
    },
    cleanLine: (raw: string): string => PythonManager.cleanPipLine(raw),
    phasePct: (line: string): number => PythonManager.pipPhasePct(line),
    stageLabel: (p: number): string => PythonManager.stageLabel(p),
    getInstalling: (): InstallingPkg[] => this.installingList,
    setInstalling: (list: InstallingPkg[]): void => { this.installingList = list; },
    onEnqueued: (): void => { this.pkgTab = 3; },
    onLogAppend: (name: string, logs: string[]): void => {
      if (this.logVisible && this.logName === name) {
        this.logLines = [...logs];   // 日志窗开着：实时追加
      }
    },
    refreshInstalled: (): void => { this.refreshPipPkgs(); },
  });

  versionPickerController: CustomDialogController = new CustomDialogController({
    builder: VersionPickerDialog({
      onSelect: (ver: string): void => {
        this.handleVersionSelect(ver);
      },
    }),
    alignment: DialogAlignment.Center,
    customStyle: true,
    autoCancel: true,
    maskColor: DevTheme.BG_OVERLAY,
  });

  addSourceController: CustomDialogController = new CustomDialogController({
    builder: AddPipSourceDialog({
      onAdd: (name: string, url: string, trustedHost: string): void => {
        this.doAddCustomSource(name, url, trustedHost);
      },
    }),
    alignment: DialogAlignment.Center,
    customStyle: true,
    autoCancel: true,
    maskColor: DevTheme.BG_OVERLAY,
  });

  aboutToAppear(): void {
    this.checkPyRuntime();
    this.pipSources = cachedPipSources;
    this.pipPkgs = cachedPipPkgs;
    if (cachedPipSources.length === 0) { this.initPipSources(); }
    if (cachedPipPkgs.length === 0) { this.refreshPipPkgs(); }
    this.catalogReady = PyCatalogService.ready();
  }

  private onCatalogReady(): void {
    this.catalogReady = PyCatalogService.ready();
  }

  /** 活跃运行时变化：解释器已切换 → 已安装包列表归属新 site-packages，异步重查（含全局刷新） */
  private onRuntimeEpoch(): void {
    this.checkPyRuntime();
    this.refreshPipPkgs();
  }

  /** 版本清单网络就绪：若版本选择器开着则补内容；行级多版本标记随重赋重算 */
  private onPyVersionsReady(): void {
    if (this.versionPickerPkg !== '') {
      const versions = PyVersionsService.versionsOf(this.versionPickerPkg);
      this.versionPickerVersions = versions;
      AppStorage.setOrCreate('vp_versions', versions.join(','));
      AppStorage.setOrCreate('vp_loading', false);
    }
    this.pipPkgs = [...this.pipPkgs];  // 触发整页重渲染（versionsOf 在渲染期同步读取）
  }

  // ══════════════ Tab 1: 镜像管理 ══════════════

  private checkPyRuntime(): void {
    // 用 DevBox 管理的 python 路径（current 链接），不用系统 PATH（避免系统 python 误判）
    const lines: string[] = [];
    DevTask.shell(`'${HOME}/usr/local/bin/python3' --version 2>&1 | head -1`,
      (t: string, _e: boolean) => { lines.push(t); },
      (ok: boolean, _d: string) => {
        const out: string = lines.join('').trim();
        this.pyRuntimeOk = ok && out.startsWith('Python');
      });
  }


  private initPipSources(): void {
    // fs 直读 pip.conf（小文件同步读，省一次 shell spawn）
    let content: string = '';
    try {
      content = fs.readTextSync(PIP_CONF);
    } catch (_) {
      content = '';
    }
    const enabledUrls: string[] = [];
    for (const line of content.split('\n')) {
      const t = line.trim();
      if (t.startsWith('index-url') || t.startsWith('extra-index-url')) {
        const eq = t.indexOf('=');
        if (eq > 0) { const u = t.substring(eq + 1).trim(); if (u !== '') { enabledUrls.push(u); } }
      }
    }
    const list: PipSource[] = [];
    const rec = DiscoveryService.latest().recommendedPipIndex();
    const recHost = DiscoveryService.latest().recommendedPipTrustedHost();
    if (rec !== '') { list.push({ name: 'OHPCD 适配源', url: rec, trustedHost: recHost, custom: false, enabled: false }); }
    list.push({ name: '阿里云', url: 'https://mirrors.aliyun.com/pypi/simple', trustedHost: '', custom: false, enabled: false });
    list.push({ name: '腾讯云', url: 'https://mirrors.cloud.tencent.com/pypi/simple', trustedHost: '', custom: false, enabled: false });
    list.push({ name: '华为云', url: 'https://mirrors.huaweicloud.com/repository/pypi/simple', trustedHost: '', custom: false, enabled: false });
    list.push({ name: '清华', url: 'https://pypi.tuna.tsinghua.edu.cn/simple/', trustedHost: '', custom: false, enabled: false });
    list.push({ name: 'PyPI 官方', url: 'https://pypi.org/simple', trustedHost: '', custom: false, enabled: false });
    const enabled: PipSource[] = [];
    const disabled: PipSource[] = [];
    for (const s of list) {
      if (enabledUrls.indexOf(s.url) >= 0) { s.enabled = true; enabled.push(s); } else { disabled.push(s); }
    }
    this.pipSources = enabled.concat(disabled);
    cachedPipSources = this.pipSources;
  }

  private savePipConf(): void {
    // fs 直写 pip.conf（组装完整内容一次落盘，替代多条 echo 追加）
    const enabled = this.pipSources.filter((s: PipSource): boolean => s.enabled);
    const out: string[] = ['[global]'];
    if (enabled.length > 0) {
      out.push(`index-url = ${enabled[0].url}`);
      for (let i = 1; i < enabled.length; i++) {
        out.push(`extra-index-url = ${enabled[i].url}`);
      }
      const hosts: string[] = [];
      for (const s of enabled) {
        if (s.trustedHost !== '' && hosts.indexOf(s.trustedHost) < 0) { hosts.push(s.trustedHost); }
      }
      if (hosts.length > 0) { out.push(`trusted-host = ${hosts.join(' ')}`); }
    }
    try {
      try {
        if (!fs.accessSync(`${HOME}/.pip`)) { fs.mkdirSync(`${HOME}/.pip`, true); }
      } catch (_) {
        fs.mkdirSync(`${HOME}/.pip`, true);
      }
      const f = fs.openSync(PIP_CONF, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(f.fd, out.join('\n') + '\n');
      fs.closeSync(f.fd);
    } catch (e) {
      DevToast.show($r('app.string.python_manager_5'));
    }
  }

  private enableSource(src: PipSource): void {
    src.enabled = true;
    const enabled = this.pipSources.filter((s: PipSource): boolean => s.enabled);
    const disabled = this.pipSources.filter((s: PipSource): boolean => !s.enabled);
    this.pipSources = enabled.concat(disabled);
    cachedPipSources = this.pipSources;
    this.savePipConf();
  }

  private disableSource(src: PipSource): void {
    src.enabled = false;
    const enabled = this.pipSources.filter((s: PipSource): boolean => s.enabled);
    const disabled = this.pipSources.filter((s: PipSource): boolean => !s.enabled);
    this.pipSources = enabled.concat(disabled);
    cachedPipSources = this.pipSources;
    this.savePipConf();
  }

  private moveEnabledSource(idx: number, dir: number): void {
    const enabled = this.pipSources.filter((s: PipSource): boolean => s.enabled);
    const target = idx + dir;
    if (target < 0 || target >= enabled.length) { return; }
    const gA = this.pipSources.indexOf(enabled[idx]);
    const gB = this.pipSources.indexOf(enabled[target]);
    const tmp = this.pipSources[gA];
    this.pipSources[gA] = this.pipSources[gB];
    this.pipSources[gB] = tmp;
    cachedPipSources = this.pipSources;
    this.savePipConf();
  }

  /** 拖拽换位：当前源列表内 from → to（保持在启用组内） */
  private dropEnabledSource(to: number): void {
    const from: number = this.dragSrcIdx;
    this.dragSrcIdx = -1;
    if (from < 0 || from === to) { return; }
    const enabled = this.pipSources.filter((s: PipSource): boolean => s.enabled);
    if (from >= enabled.length || to >= enabled.length) { return; }
    const gA = this.pipSources.indexOf(enabled[from]);
    const item = this.pipSources.splice(gA, 1)[0];
    const gTo = to > from
      ? this.pipSources.indexOf(enabled[to]) + 1
      : this.pipSources.indexOf(enabled[to]);
    this.pipSources.splice(gTo, 0, item);
    cachedPipSources = this.pipSources;
    this.savePipConf();
  }

  private clearAndRebuild(): void {
    DevTask.shell(`echo '[global]' > '${PIP_CONF}'`, (_t, _e) => {}, (_ok, _d) => {
      for (const s of this.pipSources) { s.enabled = false; }
      cachedPipSources = this.pipSources;
      DevToast.ok($r('app.string.python_manager_6'));
    });
  }

  private doAddCustomSource(name: string, url: string, trustedHost: string): void {
    const fullUrl = url.trim().startsWith('http') ? url.trim() : `https://${url.trim()}`;
    this.pipSources.push({ name: name.trim(), url: fullUrl, trustedHost: trustedHost.trim(), custom: true, enabled: false });
    cachedPipSources = this.pipSources;
    DevToast.ok($r('app.string.python_manager_7'));
  }

  private enabledSources(): PipSource[] { return this.pipSources.filter((s: PipSource): boolean => s.enabled); }
  private disabledSources(): PipSource[] { return this.pipSources.filter((s: PipSource): boolean => !s.enabled); }

  @Builder
  buildMirrorTab() {
    Column({ space: 12 }) {
      DevCard({ title: '当前源', subtitle: '', accent: '', pad: 12 }) {
        Column({ space: 4 }) {
          if (this.enabledSources().length === 0) {
            Text($r('app.string.python_manager_8')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY).padding(4)
          } else {
            ForEach(this.enabledSources(), (src: PipSource, idx: number) => {
              Row({ space: 8 }) {
                Text(`${idx + 1}.`).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY).width(20)
                Column({ space: 1 }) {
                  Text(idx === 0 ? `${src.name}（主源）` : src.name).fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_PRIMARY)
                  Text(src.url).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
                    .fontFamily(DevTheme.MONO_FONT).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                if (idx > 0) {
                Text('↑').fontSize(16).fontColor(DevTheme.TEXT_TERTIARY).width(26).height(26)
                  .textAlign(TextAlign.Center).borderRadius(4)
                  .hoverEffect(HoverEffect.Scale)
                  .scale({ x: this.pressedArrow === '↑' ? 0.85 : 1, y: this.pressedArrow === '↑' ? 0.85 : 1 })
                  .animation({ duration: 100, curve: Curve.EaseOut })
                  .onTouch((e: TouchEvent) => {
                    this.pressedArrow = e.type === TouchType.Down ? '↑' : '';
                  })
                  .onClick(() => { this.moveEnabledSource(idx, -1); })
                }
                if (idx < this.enabledSources().length - 1) {
                Text('↓').fontSize(16).fontColor(DevTheme.TEXT_TERTIARY).width(26).height(26)
                  .textAlign(TextAlign.Center).borderRadius(4)
                  .hoverEffect(HoverEffect.Scale)
                  .scale({ x: this.pressedArrow === '↓' ? 0.85 : 1, y: this.pressedArrow === '↓' ? 0.85 : 1 })
                  .animation({ duration: 100, curve: Curve.EaseOut })
                  .onTouch((e: TouchEvent) => {
                    this.pressedArrow = e.type === TouchType.Down ? '↓' : '';
                  })
                  .onClick(() => { this.moveEnabledSource(idx, 1); })
                }
                DevBtn({ text: '禁用', buttonSize: 'mini', plain: true, onTap: () => { this.disableSource(src); } })
              }.width('100%')
        .padding({ top: 4, bottom: 4 })
              .onDragStart(() => {
                this.dragSrcIdx = idx;
                return undefined;
              })
              .onDrop(() => { this.dropEnabledSource(idx); })
            }, (src: PipSource, idx: number) => `${src.name}_${idx}_${src.enabled}`)
          }
          Row({ space: 8 }) {
            Text(PIP_CONF).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
              .fontFamily(DevTheme.MONO_FONT).layoutWeight(1)
            DevBtn({ text: '清理重建', buttonSize: 'mini', plain: true, danger: true,
              onTap: () => { this.clearAndRebuild(); } })
          }.width('100%').padding({ top: 6 })
        }.width('100%')
      }

      DevCard({ title: `可用源（${this.disabledSources().length})`, subtitle: '', accent: '', pad: 12 }) {
        Column() {
          if (this.disabledSources().length === 0) {
            Text($r('app.string.python_manager_9')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY).padding(4)
          } else {
            ForEach(this.disabledSources(), (src: PipSource) => {
              Row({ space: 10 }) {
                Column({ space: 1 }) {
                  Text(src.name).fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_PRIMARY)
                  Text(src.url).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
                    .fontFamily(DevTheme.MONO_FONT).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                if (src.custom) {
                  DevBtn({ text: '删除', buttonSize: 'mini', plain: true, danger: true,
                    onTap: () => {
                      const idx = this.pipSources.indexOf(src);
                      if (idx >= 0) { this.pipSources.splice(idx, 1); }
                      cachedPipSources = this.pipSources;
                    } })
                }
                DevBtn({ text: '启用', buttonSize: 'mini', onTap: () => { this.enableSource(src); } })
              }.width('100%').padding({ top: 5, bottom: 5 })
            }, (src: PipSource) => `${src.name}_${src.enabled}_${src.custom}`)
          }
          DevBtn({ text: '+ 添加自定义源', buttonSize: 'mini', plain: true,
            onTap: () => { this.addSourceController.open(); } }).margin({ top: 6 })
        }.width('100%')
      }
    }.width('100%')
  }

  // ══════════════ Tab 2: 包管理 ══════════════

  private refreshPipPkgs(): void {
    this.pipLoading = true;
    const seq: number = ++this.pipQuerySeq;
    const lines: string[] = [];
    DevTask.shell(`${PIP_CMD} list --format=freeze 2>&1 | head -80`,
      (t: string, _e: boolean) => lines.push(t),
      (_ok: boolean, _d: string) => {
        if (seq !== this.pipQuerySeq) { return; }  // 过期响应（期间又切了版本），丢弃
        this.pipPkgs = lines.filter((s: string): boolean => {
          const t = s.trim();
          return t !== '' && t.indexOf('==') > 0 && !t.startsWith('WARNING')
            && !t.startsWith('ERROR') && !t.startsWith('DEPRECATION');
        });
        cachedPipPkgs = this.pipPkgs;
        this.pipLoading = false;
      });
  }

  private installPkg(name: string, adapted: boolean): void {
    // 实时检测（fs 判存在，不依赖缓存的 pyRuntimeOk——安装运行时后 epoch 延迟 800ms 才触发）
    let ok: boolean = false;
    try { ok = fs.accessSync(`${HOME}/usr/local/bin/python3`); } catch (_) {
    }
    if (!ok) { DevToast.show($r('app.string.python_manager_10')); return; }
    this.flow.install(name, adapted);
  }

  /** pip 输出净化（终端窗渲染前置）——白名单法根治乱码：
   *  逐个黑名单屏蔽残缺转义产物（[1m/[0;34m 等）无法穷举（用户实证）；
   *  改为只保留可打印 ASCII(0x20-0x7E) + 中文(CJK)/全角/常用符号——
   *  其余（控制字符/残缺 ANSI 产物/盲文/私用区）一次全清。
   *  \r 取最后段（pip 单行刷新）；tab 转空格（ASCII 对齐）。 */
  private static cleanPipLine(raw: string): string {
    let s: string = raw;
    const cr: number = s.lastIndexOf('\r');
    if (cr >= 0) {
      s = s.substring(cr + 1);
    }
    // 先剥完整 ANSI 转义（防参数数字被误留），tab 转空格
    s = s
      .replace(/\u001b\[[0-9;?]*[a-zA-Z]/g, '')
      .replace(/\t/g, '    ');
    // 白名单：可打印 ASCII + 中文/全角/常用标点——其余全清
    s = s.replace(/[^\u0020-\u007e\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]/g, '');
    return s.replace(/ +/g, ' ').trim();
  }

  /** pip 输出 → 进度里程碑（pip 无全局百分比；关键字映射 + 时间爬升兜底） */
  private static pipPhasePct(line: string): number {
    if (line.startsWith('Successfully installed') || line.startsWith('Successfully uninstalled')) { return 92; }
    if (line.indexOf('Installing collected packages') >= 0) { return 72; }
    if (line.indexOf('Downloading') >= 0 || line.indexOf('Using cached') >= 0) { return 40; }
    if (line.indexOf('Collecting') >= 0) { return 15; }
    return 0;
  }

  /** 进度档位 → 阶段文案（显示层不再透出 pip 原始输出行） */
  private static stageLabel(p: number): string {
    if (p >= 100) { return '完成'; }
    if (p >= 92) { return '写入完成'; }
    if (p >= 72) { return '安装文件…'; }
    if (p >= 40) { return '下载包…'; }
    if (p >= 15) { return '解析依赖…'; }
    return '准备安装…';
  }

  /** 队列变化（epoch）→ 更新所有排队行的位次文案（入队时只写一次，
   *  前面任务完成/出队后位次变化——真机实证"排队位次不变"） */
  private onQueueEpoch(): void {
    this.flow.onQueueEpoch();
  }

  /** 取消包安装：双路——排队中先出队（TaskQueue.dequeue）；
   *  running 中杀进程（cancelTag）+ 标记取消（onDone 区分取消/失败） */
  private cancelPkgInstall(name: string): void {
    this.flow.cancelInstall(name);
  }

  /** 切换已安装包的版本 */
  /** 打开安装流日志窗（bindSheet 半屏，终端风格） */
  private openLog(name: string): void {
    this.logName = name;
    this.logLines = [...this.flow.logsOf(name)];
    this.logVisible = true;
  }

  private switchVersion(name: string): void {
    this.openVersionPicker(name);
  }

  private uninstallPkg(pkgLine: string): void {
    const name = pkgLine.split('==')[0];
    DevToast.show(`正在卸载 ${name}…`);
    DevTask.shell(`${PIP_CMD} uninstall -y ${name} 2>&1`,
      (_t: string, _e: boolean) => {},
      (ok: boolean, _d: string) => {
        if (ok) {
          DevToast.ok(`${name} 已卸载`);
          this.refreshPipPkgs();
        } else {
          DevToast.show(`${name} 卸载失败`);
        }
      });
  }

  private installedPkgData(line: string): DevPkgData {
    const parts = line.split('==');
    const name = parts[0].trim();
    const ver = parts.length > 1 ? parts[1].trim() : '';
    const catStatus = PyCatalogService.statusOf(name);
    const desc = catStatus === 'adapted' ? '适配包' : catStatus === 'pure_python' ? '兼容包' : '';
    const latest = PyVersionsService.latestOf(name);
    const canUpdate = latest !== '' && latest !== ver;
    const allVers = PyVersionsService.versionsOf(name);
    return { name: name, ver: ver, desc: desc, sizeLabel: '',
      installed: true, inPath: false, canUpdate: canUpdate, progress: -1, showInstall: false,
      isLatest: latest === ver, hasMultiVer: allVers.length > 1 };
  }

  private static CATEGORY_MAP: Record<string, string> = {
    'database': '数据库', 'web-network': '网络', 'data-science': '数据科学',
    'testing': '测试', 'dev-tools': '开发工具', 'cli': '命令行',
    'security': '安全', 'system': '系统', 'other': '',
  };

  private catalogPkgData(e: PyCatalogEntry): DevPkgData {
    const cat = PythonManager.CATEGORY_MAP[e.category] ?? '';
    const isInstalled = this.isPkgInstalled(e.name);
    const displayVer = this.displayVersion(e.name, e.version);
    const verCount = PyVersionsService.versionsOf(e.name).length;
    const allVers = PyVersionsService.versionsOf(e.name);
    const hasMulti = allVers.length > 1;
    const isLatest = displayVer === allVers[0] || displayVer === e.version;
    return { name: e.name, ver: displayVer, desc: cat,
      sizeLabel: '', installed: isInstalled, inPath: false, canUpdate: false, progress: -1,
      showInstall: !isInstalled, isLatest: isLatest, hasMultiVer: true };
  }

  private isPkgInstalled(name: string): boolean {
    for (const line of this.pipPkgs) {
      if (line.split('==')[0].trim().toLowerCase() === name.toLowerCase()) { return true; }
    }
    return false;
  }

  /** 获取包的已装版本 */
  private installedVerOfPkg(name: string): string {
    for (const line of this.pipPkgs) {
      const parts = line.split('==');
      if (parts[0].trim().toLowerCase() === name.toLowerCase()) {
        return parts.length > 1 ? parts[1].trim() : '';
      }
    }
    return '';
  }

  /** 打开版本选择器（清单未就绪时先转圈，网络就绪后由 onPyVersionsReady 补内容） */
  private openVersionPicker(name: string): void {
    const versions = PyVersionsService.versionsOf(name);
    if (versions.length === 1) {
      DevToast.show($r('app.string.python_manager_11'));
      return;
    }
    this.versionPickerPkg = name;
    this.versionPickerVersions = versions;
    this.showVersionPicker = true;
    // CustomDialog 数据通过 AppStorage 传递（@CustomDialog builder 参数不可动态更新）
    AppStorage.setOrCreate('vp_pkg', name);
    AppStorage.setOrCreate('vp_versions', versions.join(','));
    AppStorage.setOrCreate('vp_selected', this.selectedVersions[name] ?? '');
    const loading: boolean = versions.length === 0;
    AppStorage.setOrCreate('vp_loading', loading);
    if (loading) { PyVersionsService.ensure(); }  // 有缓存秒回；无缓存触发网络（完成 bump pyversions_epoch）
    this.versionPickerController.open();
  }

  /** 选择版本后的处理（含二次确认） */
  private handleVersionSelect(ver: string): void {
    const name = this.versionPickerPkg;
    if (name === '') { return; }
    const isInstalled = this.isPkgInstalled(name);
    const oldVer = this.installedVerOfPkg(name);

    if (isInstalled && oldVer !== '' && oldVer !== ver) {
      // 已安装不同版本 → 延迟弹确认（CustomDialog 回调中直接弹新 Dialog 会崩溃）
      this.selectedVersions[name] = ver;
      setTimeout(() => {
        DevConfirm.ask(
          `切换 ${name} 版本`,
          `将替换 ${oldVer} → ${ver}，确认切换？`,
          () => {
            this.installPkg(name, false);
          },
          '确认切换',
        );
      }, 200);
    } else {
      this.selectedVersions[name] = ver;
    }
  }

  /** 选择版本 */

  /** 获取包的显示版本（用户选择 > catalog latest） */
  private displayVersion(name: string, catalogVer: string): string {
    const selected = this.selectedVersions[name];
    return selected !== undefined && selected !== '' ? selected : catalogVer;
  }

  private installingPkgData(item: InstallingPkg): DevPkgData {
    return { name: item.name, ver: '', desc: item.phase !== '' ? item.phase : this.flow.stageLabel(item.progress), sizeLabel: '',
      installed: false, inPath: false, canUpdate: false, progress: item.progress,
      showInstall: false, isLatest: true, hasMultiVer: false };
  }

  private pagedInstalled(): string[] {
    const all = this.filteredInstalled();
    const start = (this.catalogPage - 1) * this.pageSize;
    return all.slice(start, start + this.pageSize);
  }

  private filteredInstalled(): string[] {
    const kw = this.pkgSearch.trim().toLowerCase();
    if (kw === '') { return this.pipPkgs; }
    return this.pipPkgs.filter((s: string): boolean => s.toLowerCase().indexOf(kw) >= 0);
  }

  // 审计 C-P1-E1：搜索结果缓存（此前每帧 3-4 次 48K 条目全量扫描）
  private cachedResults: Record<string, PyCatalogEntry[]> = {};
  private cachedTotal: Record<string, number> = {};
  private cachedSearchKey: string = '\u0000';
  private searchTimer: number = -1;

  /** 搜索结果缓存收口（搜索词/状态变化时重算一次；渲染层零扫描） */
  private searchResults(status: string): PyCatalogEntry[] {
    const key: string = `${this.pkgSearch}|${status}`;
    if (this.cachedSearchKey !== key || this.cachedResults[status] === undefined) {
      this.cachedSearchKey = key;
      const all: PyCatalogEntry[] = PyCatalogService.searchByStatus(this.pkgSearch, status, 999999);
      this.cachedResults[status] = all;
      this.cachedTotal[status] = all.length;
    }
    return this.cachedResults[status];
  }

  private pagedCatalog(status: string): PyCatalogEntry[] {
    const all = this.searchResults(status);
    const start = (this.catalogPage - 1) * this.pageSize;
    return all.slice(start, start + this.pageSize);
  }

  private catalogTotal(status: string): number {
    this.searchResults(status);   // 触发缓存
    return this.cachedTotal[status] ?? 0;
  }

  @Builder
  buildPkgTab() {
    Column({ space: 10 }) {
      DevInput({ value: this.pkgSearch, placeholder: '搜索包名…', mono: false,
        onChange: (v: string) => {
          // 审计 C-P1-E1：300ms 防抖（此前每击键同步过滤 48K 条目）
          if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); }
          this.searchTimer = setTimeout(() => {
            this.searchTimer = -1;
            this.pkgSearch = v;
            this.catalogPage = 1;
          }, 300);
        } })

      // 四视图 chip
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(['已安装', '适配包', '兼容包'], (label: string, idx: number) => {
          DevChip({ text: label, tone: this.pkgTab === idx ? 'primary' : 'neutral', mono: false })
            .margin({ right: 6, bottom: 6 })
            .onClick(() => { this.pkgTab = idx; this.catalogPage = 1; })
        }, (label: string, idx: number) => `${label}_${this.pkgTab === idx}`)

        DevChip({
          text: this.installingList.length > 0 ? `安装中（${this.installingList.length})` : '安装中',
          tone: this.pkgTab === 3 ? 'primary' : 'neutral',
          mono: false,
        })
        .margin({ right: 6, bottom: 6 })
        .onClick(() => { this.pkgTab = 3; })
      }.width('100%')

      // ── 视图内容 ──
      if (this.pkgTab === 0) {
        // 已安装（= 活跃版本 site-packages，切版本后自动重查）
        if (this.pipLoading && this.filteredInstalled().length === 0) {
          Column({ space: 8 }) {
            LoadingProgress().width(36).height(36).color(DevTheme.PRIMARY)
            Text($r('app.string.python_manager_12')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
        Scroll() {
          Column({ space: 2 }) {
            if (this.filteredInstalled().length === 0) {
              Text($r('app.string.python_manager_13')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY).padding(16)
            } else {
              ForEach(this.pagedInstalled(), (line: string) => {
                DevPkgRow({ data: this.installedPkgData(line),
                  onInstall: () => { this.openVersionPicker(line.split('==')[0].trim()); },
                  onUninstall: () => { this.uninstallPkg(line); },
                  onVersionClick: () => { this.openVersionPicker(line.split('==')[0].trim()); },
                  versions: PyVersionsService.versionsOf(line.split('==')[0].trim()),
                  onVersionSelect: (ver: string): void => { this.handleVersionSelect(ver); } })
              }, (line: string) => line)
            }
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
          Text(this.pipLoading
            ? `共 ${this.filteredInstalled().length} 个 · 刷新中…`
            : `共 ${this.filteredInstalled().length} 个`)
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
          DevPagination({ currentPage: this.catalogPage, totalItems: this.filteredInstalled().length,
            itemsPerPage: this.pageSize, onChange: (p: number) => { this.catalogPage = p; } })
        }.width('100%')
        .alignItems(HorizontalAlign.Center).padding({ top: 4, bottom: 4 })
        }

      } else if (this.pkgTab === 1) {
        // 适配包
        if (!this.catalogReady) {
          Column({ space: 8 }) {
            LoadingProgress().width(36).height(36).color(DevTheme.PRIMARY)
            Text($r('app.string.env_manager_4')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 2 }) {
            ForEach(this.pagedCatalog('adapted'), (e: PyCatalogEntry) => {
              DevPkgRow({ data: this.catalogPkgData(e),
                onInstall: () => { this.installPkg(e.name, true); },
                onUninstall: () => { this.uninstallPkg(e.name); },
                onVersionClick: () => { this.openVersionPicker(e.name); },
                versions: PyVersionsService.versionsOf(e.name),
                onVersionSelect: (ver: string): void => { this.handleVersionSelect(ver); } })
            }, (e: PyCatalogEntry) => e.name)
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
            Text(`共 ${this.catalogTotal('adapted')} 个`).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
            DevPagination({ currentPage: this.catalogPage, totalItems: this.catalogTotal('adapted'),
              itemsPerPage: this.pageSize, onChange: (p: number) => { this.catalogPage = p; } })
          }.width('100%')
        .alignItems(HorizontalAlign.Center).padding({ top: 4, bottom: 4 })
        }

      } else if (this.pkgTab === 2) {
        // 兼容包
        if (!this.catalogReady) {
          Column({ space: 8 }) {
            LoadingProgress().width(36).height(36).color(DevTheme.PRIMARY)
            Text($r('app.string.env_manager_4')).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 2 }) {
              ForEach(this.pagedCatalog('pure_python'), (e: PyCatalogEntry) => {
                DevPkgRow({ data: this.catalogPkgData(e),
                  onInstall: () => { this.installPkg(e.name, false); },
                  onUninstall: () => { this.uninstallPkg(e.name); },
                  onVersionClick: () => { this.openVersionPicker(e.name); },
                  versions: PyVersionsService.versionsOf(e.name),
                  onVersionSelect: (ver: string): void => { this.handleVersionSelect(ver); } })
              }, (e: PyCatalogEntry) => e.name)
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
            Text(`共 ${this.catalogTotal('pure_python')} 个`).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
            DevPagination({ currentPage: this.catalogPage, totalItems: this.catalogTotal('pure_python'),
              itemsPerPage: this.pageSize, onChange: (p: number) => { this.catalogPage = p; } })
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
          }
          .width('100%').layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Scroll() {
            Column({ space: 4 }) {
              ForEach(this.installingList, (item: InstallingPkg) => {
                DevPkgRow({ data: this.installingPkgData(item),
                  onInstall: () => {}, onUninstall: () => {},
                  onLogClick: () => { this.openLog(item.name); },
                  hasCancelInstall: true, onCancelInstall: (n: string): void => { this.cancelPkgInstall(n); } })
              }, (item: InstallingPkg) => item.name)
            }.width('100%')
          }
          .width('100%').layoutWeight(1)
          .align(Alignment.TopStart)
        }
      }
    }
    .width('100%').height('100%').padding({ bottom: 16 })
    .onAreaChange((_o: Area, n: Area) => {
      // pageSize 由列表容器 onAreaChange 精确计算，这里不处理
    })
  }


  @Builder
  buildProjectTab() {
    DevEmpty({ text: '项目管理', hint: '虚拟环境与项目识别将随后续版本提供', image: 'default' })
  }

  build() {
    Stack() {
      LangRuntimePage({
        cfg: pyCfg(),
        tab1Content: (): void => { this.buildMirrorTab(); },
        tab2Content: (): void => { this.buildPkgTab(); },
        tab3Content: (): void => { this.buildProjectTab(); },
      })
    }
    .width('100%').height('100%')
    .bindSheet($$this.logVisible, this.logSheet(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],   // 默认偏矮（用户：高度小一点），可拖大
      dragBar: true,
      showClose: false,
      backgroundColor: DevTheme.BG_TERM,   // 面板整体终端深底——无标题区（用户：全终端）
    })
  }

  /** 终端风格日志面板：深底/红绿点/mono/行色；双向自由滚动——纵向历史、
   *  单行 maxLines(1) 不换行横向滚（长 URL/依赖链保终端观感）；tab 已净化层转空格 */
  @Builder
  logSheet(): void {
    Column() {
      Row({ space: 5 }) {
        Text(`pip install ${this.logName}`)
          .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
          .layoutWeight(1).textAlign(TextAlign.Start)
        Text(`${this.logLines.length} 行`)
          .fontSize(DevTheme.FS_BADGE).fontColor(DevTheme.TEXT_MUTED)
      }
      .width('100%').padding({ left: 12, right: 12, top: 10, bottom: 6 })

      // 嵌套双 Scroll：外层横向（长行不换行滚动）+ 内层纵向（历史）——
      // sheet 环境下 ScrollDirection.Free 不生效（真机实证），拆两层各自专向
      Scroll() {
        Scroll(this.logScroller) {
          Column() {
            ForEach(this.logLines, (l: string, idx: number) => {
              Text(l === '' ? ' ' : l)
                .fontSize(12)
                .lineHeight(17)
                .fontFamily(DevTheme.MONO_FONT)
                .fontColor(termLineColor(l))
                .maxLines(1)
            }, (l: string, idx: number) => `${idx}_${l.length}`)
          }
          .constraintSize({ minHeight: '100%' })
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 12, right: 12, top: 4, bottom: 12 })
          .onAreaChange(() => {
            this.logScroller.scrollEdge(Edge.Bottom);
          })
        }
        .scrollable(ScrollDirection.Vertical)
        .layoutWeight(1)
        .align(Alignment.TopStart)   // ArkTS Scroll 内容默认居中——顶对齐（真机实证"从中间出现"根因）
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.None)
      }
      .scrollable(ScrollDirection.Horizontal)   // 外层横向：长 URL/依赖链不换行横向滚
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.None)
    }
    .width('100%').height('100%')
    .backgroundColor(DevTheme.BG_TERM)
  }
}
