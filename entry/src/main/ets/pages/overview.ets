/**
 * DevBox 首页（环境总览）
 * 设计来源：Pixso 10 快速开始 / 11 环境状态 / 32 体检结果，zinc 单色系
 * 结构：产品介绍 Hero（沉浸光感）→ 快速开始（未装时）→ 模块网格
 */
import { DevTheme } from '../common/DevTheme';
import { DevSectionTitle, DevModuleCard, DevCard, DevBtn, DevStatusDot } from '../common/component';
import { DevGateService } from '../utils/DevGateService';
import { execSync as nativeExecSync } from 'libdevbox_native.so';
import { DevTask } from '../utils/DevTask';
import { DevEnvPaths } from '../utils/DevEnvPaths';
import { RuntimeMgr, RuntimeInstalled } from '../utils/RuntimeMgr';
import { EnvStore } from '../utils/EnvStore';
import { BrewEnv } from '../utils/BrewEnv';
import fs from '@ohos.file.fs';







const HOME_PATH = '/storage/Users/currentUser';

/** 环境卡片模型 */
interface LangSpec {
  key: string;
  mono: string;
  color: string;
  title: string;
  head: string;
}

interface EnvCard {
  key: string;
  title: string;
  main: string;
  detail: string;
  status: number;
}

/** 连续光场参数（百分比中心 + AARRGGBB 颜色） */

/** 体检问题模型 */
/** 开发套件模型 */

// ── 探测结果进程级缓存：切页直接复用，不重新扫描 ──
// 失效时机：应用重启（自然失效）/ 安装卸载切换完成（runtime_epoch 变化）
let cachedCards: EnvCard[] = [];
let cachedHasAnyEnv: boolean = false;
let cachedInstalledCount: number = 0;

@Component
export struct OverviewPage {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @StorageProp('runtime_epoch') @Watch('onEpoch') runtimeEpoch: number = 0;
  @State cards: EnvCard[] = [];
  @State probing: boolean = true;
  @State hasAnyEnv: boolean = false;
  @State installedCount: number = 0;
  // 运行环境前置门（未就绪时 gate 卡置顶、子卡与探测全部隐藏）
  @StorageProp('env_gate') @Watch('onGateChange') envGate: string = 'unknown';
  @State gateChecking: boolean = true;
  onNavigate: (page: string) => void = () => {
  };
  private probedOnce: boolean = false;

  aboutToAppear(): void {
    // 前置门强制重查（用户从设置开启后切回本页要立刻反映；checking 期间
    // gateChecking 占位，避免闪烁——DevGateService 内部有幂等/并发保护）
    const ctx = this.getUIContext().getHostContext();
    if (ctx) {
      this.gateChecking = true;
      DevGateService.check(ctx, true).then(() => {
        this.gateChecking = false;
      });
    }
    if (cachedCards.length > 0) {
      // 有缓存：立即渲染旧数据，不再扫描（数据在首扫/任务完成/手动刷新时更新）
      this.cards = cachedCards;
      this.hasAnyEnv = cachedHasAnyEnv;
      this.installedCount = cachedInstalledCount;
      this.probing = false;
      this.probedOnce = true;
      return;
    }
    this.probeAll();
  }

  /** gate 状态变化（检测完成/重查）→ ok 时若从未探测则启动探测 */
  private onGateChange(): void {
    if (this.envGate === 'ok' && this.cards.length === 0 && !this.probing && !this.probedOnce) {
      this.probeAll();
    }
  }

  /** gate 卡的「去开启」按钮 */
  private openGateSetting(which: string): void {
    const ctx = this.getUIContext().getHostContext();
    if (!ctx) { return; }
    if (which === 'dev') {
      DevGateService.openDeveloperModeSettings(ctx);
    } else {
      DevGateService.openLocalPluginSettings(ctx);
    }
  }

  /** gate 卡重查按钮 */
  private recheckGate(): void {
    const ctx = this.getUIContext().getHostContext();
    if (!ctx) { return; }
    this.gateChecking = true;
    DevGateService.check(ctx, true).then(() => {
      this.gateChecking = false;
    });
  }

  /** 安装/卸载/切换任务完成 → 后台重扫（当前界面无阻塞） */
  private onEpoch(): void {
    this.probeAll();
  }

  /** 安全执行探测命令，失败返回空串 */
  private run(cmd: string): string {
    try {
      const r: string = nativeExecSync(cmd);
      return r === null || r === undefined ? '' : r;
    } catch (_) {
      return '';
    }
  }

  private firstLine(out: string): string {
    const lines = out.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const t = lines[i].trim();
      if (t.length > 0) {
        return t;
      }
    }
    return '';
  }

  private verOf(out: string): string {
    const l = this.firstLine(out);
    if (l === '' || l.indexOf('not found') >= 0 || l.indexOf('inaccessible') >= 0 || l.indexOf('sh:') === 0) {
      return ''; // 未安装/错误不上 UI
    }
    const m = l.match(/(\d+[\d.]*[a-z0-9_.-]*)/i);
    return m !== null ? m[0] : '';
  }

  private hasBlock(marker: string, dirs: string[]): boolean {
    // 统一管理器探测（协议对齐：读 ohpcd devenv 块）
    if (marker.indexOf('python') >= 0) {
      return dirs.some(d => d.indexOf('python') >= 0);
    }
    if (marker.indexOf('java') >= 0) {
      return dirs.some(d => d.indexOf('BiShengJDK') >= 0);
    }
    if (marker.indexOf('rust') >= 0) {
      return dirs.some(d => d.indexOf('rust') >= 0);
    }
    if (marker.indexOf('node') >= 0) {
      return dirs.some(d => d.indexOf('node') >= 0);
    }
    if (marker.indexOf('base') >= 0) {
      return dirs.some(d => d === 'usr/local/bin');
    }
    return false;
  }

  /**
   * 批量环境探测（异步单命令）。
   * 原实现 15 个同步 execSync 在 UI 线程逐个 spawn（数百 ms~秒级阻塞，切页卡顿主因），
   * 现合并为一条带 KEY| 前缀标记的命令，DevTask.shell 异步执行，回调后构建卡片。
   * 首个非空行 = grep -v '^$' | head -1（设备精简 shell 无 awk，只用具名验证过的命令）。
   */
  probeAll(): void {
    this.probing = true;
    const H = HOME_PATH;
    const FL = `| grep -v '^$' | head -1`;
    // 语言版本/PYREG 不再 shell 探测——改走页面同源数据层（RuntimeMgr.detectInstalled：
    // 账本+current 链接），纵览卡与各语言页状态严格一致（shell PATH 探测会与页面显示不一致）
    const script: string =
      `echo "CREG|$( (cat ${H}/usr/local/.devbox/registry.json 2>/dev/null || echo '{}') | tr -d '\\n' | tr -d '\\r')"; ` +
      `echo "BRV|$(${BrewEnv.brew()} --version 2>/dev/null ${FL})"; ` +
      `echo "GITV|$(git --version 2>/dev/null ${FL})"; ` +
      `echo "CMV|$(cmake --version 2>/dev/null ${FL})"; ` +
      `echo "ZSHRC|__BEGIN__"; cat ${H}/.zshrc 2>/dev/null; echo "__END__"`;
    const out: string[] = [];
    DevTask.shell(script, (t: string, _e: boolean) => {
      out.push(t);
    }, (_ok: boolean, _d: string) => {
      this.applyProbeOutput(out);
    });
  }

  /** 解析批量探测输出并构建环境卡片 */
  private applyProbeOutput(lines: string[]): void {
    const map: Record<string, string> = {};
    let zshrc: string = '';
    let inZsh: boolean = false;
    for (let i = 0; i < lines.length; i++) {
      const t: string = lines[i];
      if (inZsh) {
        if (t.trim() === '__END__') {
          inZsh = false;
        } else {
          zshrc += t + '\n';
        }
        continue;
      }
      const bar: number = t.indexOf('|');
      if (bar > 0) {
        const key: string = t.substring(0, bar);
        const val: string = t.substring(bar + 1);
        if (key === 'ZSHRC' && val.trim() === '__BEGIN__') {
          inZsh = true;
        } else {
          map[key] = val;
        }
      }
    }
    const dirs: string[] = DevEnvPaths.currentDirsFrom(zshrc);
    const list: EnvCard[] = [];

    // ── 语言卡：与各语言页同源（RuntimeMgr.detectInstalled=账本+current 链接），
    //    状态灯/版本/活跃与页面严格一致；描述按商用范围收敛（不再提已裁剪的生态功能） ──
    const langSpecs: LangSpec[] = [
      // 副题与各语言页 DevPageHeader subtitle 严格一致（ECO_TABS=false 裁剪后
      // 只有运行时 tab 的页面写"运行时版本管理"——不提被裁掉的包管理功能）
      { key: 'python', mono: 'Py', color: '#4B8BBE', title: 'Python', head: 'Python · 版本管理 · pip 源 · 包管理' },
      { key: 'java', mono: 'Jv', color: '#E76F00', title: 'Java', head: 'Java · 运行时版本管理' },
      { key: 'rust', mono: 'Rs', color: '#CE422B', title: 'Rust', head: 'Rust · 运行时版本管理' },
      { key: 'node', mono: 'Nd', color: '#5FA04E', title: 'Node.js', head: 'Node.js · 版本管理 · npm 源 · 全局包管理' },
      { key: 'lua', mono: 'Lu', color: '#2D4C7C', title: 'Lua', head: 'Lua · 运行时版本管理' },
      { key: 'perl', mono: 'Pl', color: '#6B6FA0', title: 'Perl', head: 'Perl · 运行时版本管理' },
      { key: 'php', mono: 'Ph', color: '#777BB4', title: 'PHP', head: 'PHP · 运行时版本管理' },
      { key: 'go', mono: 'Go', color: '#00ADD8', title: 'Go', head: 'Go · 运行时版本管理' },
    ];
    for (let i = 0; i < langSpecs.length; i++) {
      const sp: LangSpec = langSpecs[i];
      // 语言名 → 包族键（EnvStore.langKeyOf 模糊匹配：java→BiShengJDK）
      const detectKey: string = EnvStore.langKeyOf(sp.key);
      const st: RuntimeInstalled = RuntimeMgr.detectInstalled(detectKey);
      const ok: boolean = st.vers.length > 0;
      const main: string = st.active !== '' ? `${sp.title} ${st.active}`
        : ok ? `${sp.title} ${st.vers[0]}` : '未安装';
      // detail：严格镜像语言页语义（版本数+活跃——页面不展示 PATH 状态，纵览不越位；
      // zshrc 块解析对统一 ohpcd 块判不准，旧文案会误报"未纳入托管"）
      let detail: string;
      if (!ok) {
        detail = sp.head;
      } else if (st.active !== '') {
        detail = st.vers.length > 1 ? `活跃 ${st.active} · 共 ${st.vers.length} 个版本` : '唯一版本 · 当前活跃';
      } else {
        detail = `共 ${st.vers.length} 个版本 · 未设置活跃版本`;
      }
      list.push({
        key: sp.key, title: sp.title,
        main: main, detail: detail, status: ok ? 1 : 0,
      });
    }

    const pkgCount = this.countKeys(map['CREG'] ?? '{}');
    list.push({
      key: 'conan', title: 'Conan',
      main: pkgCount > 0 ? `${pkgCount} 个 C/C++ 组件` : '暂无组件',
      detail: pkgCount > 0 ? '注册表一致 · 点击查看' : 'C/C++ 组件库发现与安装',
      status: pkgCount > 0 ? 1 : 0,
    });

    const bv = this.verOf(map['BRV'] ?? '');
    list.push({
      key: 'brew', title: 'HarmonyBrew',
      main: bv !== '' ? `Homebrew ${bv}` : '未安装',
      detail: bv !== '' ? '软件包目录 · 已装包管理 · 终端可用' : '鸿蒙版 Homebrew',
      status: bv !== '' ? 1 : 0,
    });

    // ── 工具卡：与通用工具页同判据（fs 扫 usr/local 目录），状态灯=已装工具数 ──
    const gitv = this.verOf(map['GITV'] ?? '');
    const cmakev = this.verOf(map['CMV'] ?? '');
    // 审计一致性修复：排除表 java→BiShengJDK（实际目录名）+ 补 go/packages/lib/share；
    // 加空壳深检（与 common_tools 页同判据——空目录不算已装）
    const runtimeDirs: Set<string> = new Set<string>(['python', 'BiShengJDK', 'rust', 'node', 'lua', 'perl', 'php', 'go', 'ruby', 'bun', 'bin', 'current', 'packages', 'lib', 'share', 'include']);
    let toolCount = 0;
    try {
      const entries: string[] = fs.listFileSync(`${HOME_PATH}/usr/local`);
      for (let i = 0; i < entries.length; i++) {
        const e: string = entries[i];
        if (!e.startsWith('.') && !runtimeDirs.has(e)) {
          // 空壳深检：目录内容非空才算（与通用工具页 probeAll 同判据）
          try {
            const sub: string[] = fs.listFileSync(`${HOME_PATH}/usr/local/${e}`);
            if (sub.length > 0) { toolCount++; }
          } catch (_) {
            // 非目录（文件）也计入
            toolCount++;
          }
        }
      }
    } catch (_) {
    }
    list.push({
      key: 'tools', title: '通用工具',
      main: toolCount > 0 ? `已装 ${toolCount} 个基础工具` : (gitv !== '' ? `未安装（检测到系统 git ${gitv}）` : '未安装'),
      detail: toolCount > 0
        ? (gitv !== '' ? `git ${gitv}${cmakev !== '' ? ` · cmake ${cmakev}` : ''} · 点击管理` : '基础工具 · 点击管理')
        : '提供基础工具 · 一键安装',
      status: toolCount > 0 ? 1 : 0,
    });

    const exportCount = this.countExports(zshrc);
    list.push({
      key: 'env', title: '环境变量',
      main: `~/.zshrc · ${exportCount} 个 export`,
      detail: this.hasBlock('# >>> devbox base >>>', dirs) ? 'devbox PATH 块已生效' : 'devbox PATH 块未配置',
      status: this.hasBlock('# >>> devbox base >>>', dirs) ? 1 : (exportCount > 0 ? 2 : 0),
    });

    let any = false;
    let installed = 0;
    for (let i = 0; i < list.length; i++) {
      if (list[i].status > 0) {
        any = true;
        installed++;
      }
    }
    this.hasAnyEnv = any;
    this.installedCount = installed;
    this.cards = list;
    this.probing = false;
    // 写入进程级缓存（下次切页直接复用）
    cachedCards = list;
    cachedHasAnyEnv = any;
    cachedInstalledCount = installed;
  }



  private countKeys(src: string): number {
    const idx = src.indexOf('"packages"');
    if (idx < 0) {
      return 0;
    }
    const rest = src.substring(idx);
    const m = rest.match(/"conan_ref"/g);
    return m === null ? 0 : m.length;
  }

  private countExports(src: string): number {
    if (src === '') {
      return 0;
    }
    const lines = src.split('\n');
    let n = 0;
    for (let i = 0; i < lines.length; i++) {
      const t = lines[i].trim();
      if (t.indexOf('export ') === 0 && t.indexOf('=') > 0) {
        n++;
      }
    }
    return n;
  }

  /** 模块卡三列分组（末行不足补空占位） */
  /** 连续光场参数：按卡片栅格位置计算（两张大"虚拟光源"铺满整个网格，每张卡呈现所在局部） */

  private cardRows(): EnvCard[][] {
    const rows: EnvCard[][] = [];
    const per = 3;
    for (let i = 0; i < this.cards.length; i += per) {
      const row: EnvCard[] = this.cards.slice(i, i + per);
      while (row.length < per) {
        row.push({ key: `pad_${i}_${row.length}`, title: '', main: '', detail: '', status: -1 });
      }
      rows.push(row);
    }
    return rows;
  }


  /**
   * 运行环境提示横幅（2026-11-16 终版）：一句话说明 + 【详细指导】按钮
   * 跳关于页的环境准备指南。不拦截任何功能。
   */
  @Builder
  buildEnvTipBanner() {
    Row({ space: 10 }) {
      Text('ℹ')
        .fontSize(DevTheme.FS_H2)
        .fontColor(DevTheme.INFO)
      Column({ space: 2 }) {
        Text($r('app.string.overview_1'))
          .fontSize(DevTheme.FS_CAPTION)
          .fontColor(DevTheme.TEXT_SECONDARY)
          .maxLines(2)
          .lineHeight(16)
        Text($r('app.string.overview_2'))
          .fontSize(DevTheme.FS_CAPTION)
          .fontColor(DevTheme.TEXT_MUTED)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      DevBtn({
        text: '详细指导',
        buttonSize: 'small',
        plain: true,
        onTap: () => { this.onNavigate('about'); },
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .borderRadius(DevTheme.RADIUS_LG)
    .backgroundColor(DevTheme.BG_ACCENT_INFO)
    .border({ width: 1, color: DevTheme.BORDER })
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        // ─── Hero：产品介绍（纯底色渐变） ───
        Stack({ alignContent: Alignment.TopStart }) {
          Column() {
            Row({ space: 10 }) {
              Text('DevBox')
                .fontSize(DevTheme.FS_H1 + 4)
                .fontWeight(FontWeight.Bold)
                .fontColor(DevTheme.TEXT_PRIMARY)
                .letterSpacing(0.5)
            }

            Text($r('app.string.overview_3'))
              .fontSize(DevTheme.FS_H2 - 2)
              .fontColor(DevTheme.TEXT_SECONDARY)
              .margin({ top: 8 })
            Text($r('app.string.overview_4'))
              .fontSize(DevTheme.FS_BODY)
              .fontColor(DevTheme.TEXT_TERTIARY)
              .lineHeight(19)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 4 })
          }
          .width('100%')
          .padding(22)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .borderRadius(DevTheme.RADIUS_LG)
        .clip(true)
        .backgroundColor(DevTheme.BG_CARD)
        .border({ width: 1, color: DevTheme.BORDER })

        // ─── [统计区已移除] ───

        // ─── 运行环境提示（2026-11-16 终版：只提醒不检查——检测通道均不可用）───
        this.buildEnvTipBanner()

        // ─── 首次探测中：加载动效（复访/缓存路径直接渲染卡片） ───
        if (this.probing) {
          Column({ space: 10 }) {
            LoadingProgress().width(36).height(36).color(DevTheme.PRIMARY)
            Text($r('app.string.overview_5'))
              .fontSize(DevTheme.FS_CAPTION)
              .fontColor(DevTheme.TEXT_MUTED)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 32, bottom: 16 })
        }


        // ─── 模块网格 ───
        if (!this.probing) {
          Column({ space: 10 }) {
            DevSectionTitle({ title: '环境与工具', actionLabel: '', onAction: () => {} })
            Column({ space: 12 }) {
              ForEach(this.cardRows(), (row: EnvCard[], ri: number) => {
                Row({ space: 12 }) {
                  ForEach(row, (c: EnvCard, ci: number) => {
                    Column() {
                      if (c.title !== '') {
                        DevModuleCard({
                          title: c.title,
                          main: c.main,
                          detail: c.detail,
                          status: c.status,
                            onTap: () => {
                            this.onNavigate(c.key);
                          },
                        })
                      }
                    }
                    .layoutWeight(1)
                  }, (c: EnvCard) => `${c.key}_${c.status}_${c.main}`)
                }
                .width('100%')
              }, (row: EnvCard[], ri: number) => `row_${ri}_${row.length}_${row[0].status}`)
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8, bottom: 32 })
    }
    .scrollBarWidth(DevTheme.SCROLL_BAR_WIDTH)
    .scrollBarColor(DevTheme.SCROLL_BAR_COLOR)
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
  }
}
