import { IBestSetUIBaseStyle } from '@ibestservices/ibest-ui-v2';
/**
 * DevBox 主页面（应用壳）
 * 壳职责：导航状态 / 首用提示 / 反馈提交 / 页面路由。
 * 所有 UI 组件来自 common/component.ets 与 IBest-UI-V2。
 */
import dataPreferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { DevDownload } from '../utils/DevDownload';
import { EnvStore } from '../utils/EnvStore';
import { TaskQueue, QueueTask } from '../utils/TaskQueue';
import { PyCatalogService } from '../utils/PyCatalogService';
import { NpmCatalogService } from '../utils/NpmCatalogService';
import { PyVersionsService } from '../utils/PyVersionsService';
import { BusinessError } from '@ohos.base';
import { bundleManager, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { http } from '@kit.NetworkKit';
import { PkgManager } from './pkg_manager';
import { AboutPage } from './about';
import { EnvManager } from './env_manager';
import { Harmonybrew } from './harmonybrew';
import { PythonManager } from './python_manager';
import { OverviewPage } from './overview';
import { JavaManager } from './java_manager';
import { RustManager } from './rust_manager';
import { NodeManager } from './node_manager';
import { GoManager } from './go_manager';
import { PhpManager } from './php_manager';
import { LuaManager } from './lua_manager';
import { PerlManager } from './perl_manager';
import { RubyManager } from './ruby_manager';
import { BunManager } from './bun_manager';
import { CommonToolsPage } from './common_tools';
import { DevTheme, ThemeMode } from '../common/DevTheme';
import { DevConfirm, DevSideNav, DevThemeSwitch, DevTipsDialog, DevFeedbackDialog, DevToast, DevBtn } from '../common/component';
import { execSync as nativeExecSync } from 'libdevbox_native.so';
import { McpConfigDialog } from '../common/component';
/**
 * DevBox 主页面（应用壳）
 * 壳职责：导航状态 / 首用提示 / 反馈提交 / 页面路由。
 * 所有 UI 组件来自 common/component.ets 与 IBest-UI-V2。
 */

































const FEEDBACK_API = 'https://sd8f60kr13dl1693i3lcg.apigateway-cn-beijing.volceapi.com/';

enum NavPage { OVERVIEW, PYTHON, JAVA, RUST, NODE, LUA, PERL, GO, PHP, RUBY, BUN, CONAN, TOOLS, HOMEBREW, ENV, ABOUT }

@Entry
@Component
struct Index {
  @StorageProp('task_queue_epoch') @Watch('onQueueChange') queueEpoch: number = 0;
  /** 跨页导航请求（如 python 配源弹窗在任意页触发「立即配置」）——消费即清 */
  @StorageProp('nav_request') @Watch('onNavRequest') navReq: string = '';

  private onNavRequest(): void {
    if (this.navReq !== '') {
      const target: string = this.navReq;
      AppStorage.setOrCreate('nav_request', '');
      this.navigateByString(target);
    }
  }
  @State queueBadge: number = 0;
  @State queueRows: QueueTask[] = [];        // 面板内容源（快照进 @State——打开期间实时增删）
  @State runningIds: string[] = [];          // 各组进行中的任务 id（面板「进行中」徽标判定）
  @State queueVisible: boolean = false;
  @State currentPage: NavPage = NavPage.OVERVIEW;
  @State appVersion: string = '';
  @StorageLink('themeMode') @Watch('onThemeChange') storageThemeMode: string = 'dark';
  @StorageProp('mcp_enabled') mcpEnabledStatus: boolean = true;
  // 托盘菜单「MCP 服务」信号：打开主窗口 + 直达 MCP 配置弹窗
  @StorageProp('tray_open_mcp') @Watch('onTrayOpenMcp') trayOpenMcp: number = 0;
  private pref: dataPreferences.Preferences | null = null;

  // ─── 窗口三键避让（官方 getTitleButtonRect，单位 vp） ─────────
  @State btnAvoidRight: number = 0;
  @State btnAvoidWidth: number = 158;
  @State btnAvoidTop: number = 6;
  @State btnAvoidHeight: number = 40;
  private mainWindow: window.Window | null = null;

  private refreshTitleButtonRect(): void {
    if (this.mainWindow === null) {
      return;
    }
    try {
      const rect = this.mainWindow.getTitleButtonRect();
      this.btnAvoidRight = rect.right;
      this.btnAvoidWidth = rect.width;
      this.btnAvoidTop = rect.top;
      this.btnAvoidHeight = rect.height;
      hilog.info(0x0000, 'DevBox', '%{public}s', `titleButtonRect r=${rect.right} w=${rect.width} t=${rect.top} h=${rect.height}`);
    } catch (_) {
      // 取不到时使用兜底值
    }
  }

  mcpDialogController: CustomDialogController = new CustomDialogController({
    builder: McpConfigDialog(),
    alignment: DialogAlignment.Center,
    customStyle: true,
    autoCancel: true,
    maskColor: DevTheme.BG_OVERLAY,
  });

  /** 最近一次反馈成功的 issue 链接（函数服务返回——弹反馈弹窗展示可复制/打开） */
  @State lastIssueUrl: string = '';
  @State issueLinkVisible: boolean = false;

  tipsController: CustomDialogController = new CustomDialogController({
    builder: DevTipsDialog({
      onDone: (noLongerTip: boolean) => {
        this.markTipsUsed(noLongerTip);
      },
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    customStyle: true,
    maskColor: DevTheme.BG_OVERLAY,
  });

  async aboutToAppear() {
    // 供全局弹窗（DevConfirm/ComponentContent）获取 UIContext；供 DevDownload 获取 context
    AppStorage.setOrCreate('ui_context', this.getUIContext());
    DevDownload.init(this.getUIContext().getHostContext() as common.UIAbilityContext);
    // 预热统一数据层：种子目录（秒开兜底）→ 远程 manifest → 本地账本纠正
    // （refreshEco 暂无消费者且 pip/npm/brew 三条慢命令，改为按需触发）
    EnvStore.loadSeed(this.getUIContext().getHostContext() as common.UIAbilityContext);
    EnvStore.ensureRemote();
    EnvStore.ensureLocal(true);
    // Python 适配目录（48K 包三态）+ npm 适配目录（48K 包两类）
    PyCatalogService.init(this.getUIContext().getHostContext() as common.UIAbilityContext);
    PyCatalogService.ensure();
    NpmCatalogService.init(this.getUIContext().getHostContext() as common.UIAbilityContext);
    NpmCatalogService.ensure();
    PyVersionsService.init(this.getUIContext().getHostContext() as common.UIAbilityContext);
    PyVersionsService.ensure();
    // 查询主窗口三键区域，动态避让；getLastWindow 异步获取（AppStorage 时序不可靠，曾导致读到兜底值仍重叠）
    const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    window.getLastWindow(hostCtx).then((win: window.Window) => {
      this.mainWindow = win;
      this.refreshTitleButtonRect();
      win.on('windowTitleButtonRectChange', () => {
        this.refreshTitleButtonRect();
      });
      win.on('windowSizeChange', () => {
        this.refreshTitleButtonRect();
      });
    }).catch(() => {
      const ws = AppStorage.get<window.WindowStage>('windowStage');
      if (ws !== undefined) {
        this.mainWindow = ws.getMainWindowSync();
        this.refreshTitleButtonRect();
      }
    });
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.pref = await dataPreferences.getPreferences(context, 'first_use_pref');
      const isFirstUse = await this.pref.get('needTips', 'need');
      if (isFirstUse === 'need') {
        this.tipsController.open();
      }
      const appInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.appVersion = `v${appInfo.versionName}`;
      // 主题已在 EntryAbility 启动阶段（loadContent 前）恢复，此处不再重复应用，避免首帧后再闪切
    } catch (err) {
      const error = err as BusinessError;
      console.error(`init failed, err code is ${error?.code}, message is ${error?.message}`);
    }
  }

  // ─── 首用提示 ─────────────────────────────────────────────

  private async markTipsUsed(noLongerTip: boolean): Promise<void> {
    if (!noLongerTip || this.pref === null) {
      return;
    }
    try {
      await this.pref.put('needTips', 'noneed');
      await this.pref.flush();
    } catch (_) {
    }
  }

  // ─── 主题切换 ─────────────────────────────────────────────

  private toggleTheme(): void {
    const newMode: ThemeMode = DevTheme.toggle();
    this.storageThemeMode = newMode;
    // IBest 组件库基础色板随主题切换（Toast/分页等仍在用库组件）
    if (newMode === 'dark') {
      IBestSetUIBaseStyle({
        default: '#1E1E1E',
        primary: '#0B6FCC',
        success: '#22C55E',
        warning: '#F5C518',
        danger: '#F87171',
      });
    } else {
      IBestSetUIBaseStyle({
        default: '#FFFFFF',
        primary: '#0B6FCC',
        success: '#14AE5C',
        warning: '#F5C518',
        danger: '#F24822',
      });
    }
    if (this.pref) {
      this.pref.put('theme_mode', newMode);
      this.pref.flush();
    }
    const context = getContext(this) as common.UIAbilityContext;
    try {
      context.getApplicationContext().setColorMode(
        newMode === 'dark'
          ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      );
    } catch (_) {
    }
    // 系统三键配色随主题同步（深色底=亮图标，浅色底=暗图标），否则切换后三键隐形
    if (this.mainWindow !== null) {
      try {
        this.mainWindow.setDecorButtonStyle({
          colorMode: newMode === 'dark'
            ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
            : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        });
      } catch (_) {
      }
    }
  }

  // 注：MCP install/uninstall/switch 已由 TrayAbility 进程直接执行（v4 工具注册表），
  // 不再经 AppStorage 跨进程调度（AppStorage 不跨进程，原路径已失效并移除）。







  private onThemeChange(): void {
    DevTheme.applyTheme(this.storageThemeMode === 'light' ? 'light' : 'dark');
  }

  /** 托盘菜单「MCP 服务」→ 打开 MCP 配置弹窗（主窗口由托盘侧同时唤起） */
  private onTrayOpenMcp(): void {
    this.mcpDialogController.open();
  }

  // ─── 导航 ─────────────────────────────────────────────────

  private activeKey(): string {
    if (this.currentPage === NavPage.OVERVIEW) {
      return 'overview';
    }
    if (this.currentPage === NavPage.PYTHON) {
      return 'python';
    }
    if (this.currentPage === NavPage.JAVA) {
      return 'java';
    }
    if (this.currentPage === NavPage.RUST) {
      return 'rust';
    }
    if (this.currentPage === NavPage.NODE) {
      return 'node';
    }
    if (this.currentPage === NavPage.LUA) {
      return 'lua';
    }
    if (this.currentPage === NavPage.PERL) {
      return 'perl';
    }
    if (this.currentPage === NavPage.GO) {
      return 'go';
    }
    if (this.currentPage === NavPage.PHP) {
      return 'php';
    }
    if (this.currentPage === NavPage.RUBY) {
      return 'ruby';
    }
    if (this.currentPage === NavPage.BUN) {
      return 'bun';
    }
    if (this.currentPage === NavPage.CONAN) {
      return 'conan';
    }
    if (this.currentPage === NavPage.TOOLS) {
      return 'tools';
    }
    if (this.currentPage === NavPage.HOMEBREW) {
      return 'brew';
    }
    if (this.currentPage === NavPage.ENV) {
      return 'env';
    }
    if (this.currentPage === NavPage.ABOUT) {
      return 'about';
    }
        return 'about';
  }

  private navigateByString(page: string): void {
    if (page === 'python') {
      this.currentPage = NavPage.PYTHON;
    } else if (page === 'java') {
      this.currentPage = NavPage.JAVA;
    } else if (page === 'rust') {
      this.currentPage = NavPage.RUST;
    } else if (page === 'node') {
      this.currentPage = NavPage.NODE;
    } else if (page === 'lua') {
      this.currentPage = NavPage.LUA;
    } else if (page === 'perl') {
      this.currentPage = NavPage.PERL;
    } else if (page === 'go') {
      this.currentPage = NavPage.GO;
    } else if (page === 'php') {
      this.currentPage = NavPage.PHP;
    } else if (page === 'ruby') {
      this.currentPage = NavPage.RUBY;
    } else if (page === 'bun') {
      this.currentPage = NavPage.BUN;
    } else if (page === 'conan') {
      this.currentPage = NavPage.CONAN;
    } else if (page === 'tools') {
      this.currentPage = NavPage.TOOLS;
    } else if (page === 'brew') {
      this.currentPage = NavPage.HOMEBREW;
    } else if (page === 'env') {
      this.currentPage = NavPage.ENV;
        } else if (page === 'about') {
      this.currentPage = NavPage.ABOUT;
    } else {
      this.currentPage = NavPage.OVERVIEW;
    }
  }

  // ─── 反馈提交（UI 在 component.ets，网络在这里） ───────────

  private getEnvInfo(): string {
    let info = '';
    try {
      info += '\n\n--- 环境信息 ---\n';
      info += `DevBox 版本: ${this.appVersion}\n`;
      const kernel: string = nativeExecSync('uname -r 2>/dev/null || echo unknown');
      info += `内核: ${kernel.trim()}\n`;
      const arch: string = nativeExecSync('uname -m 2>/dev/null || echo unknown');
      info += `架构: ${arch.trim()}\n`;
      const regContent: string = nativeExecSync('cat $HOME/usr/local/.devbox/registry.json 2>/dev/null || echo {}');
      try {
        const reg = JSON.parse(regContent) as Record<string, Object>;
        const pkgs = reg['packages'] as Record<string, Object>;
        if (pkgs && Object.keys(pkgs).length > 0) {
          info += `已安装组件: ${Object.keys(pkgs).join(', ')}\n`;
        }
      } catch (_) {
      }
      const pyVer: string = nativeExecSync('$HOME/usr/local/bin/python3 --version 2>/dev/null || echo none');
      if (pyVer.trim() !== 'none') {
        info += `Python: ${pyVer.trim()}\n`;
      }
    } catch (_) {
      info += '(环境信息采集失败)\n';
    }
    return info;
  }

  private submitFeedback(typeIdx: number, title: string, body: string): boolean {
    const typeLabel = ['Bug 反馈', '功能建议', '使用疑问'][typeIdx];
    const fullBody = `## ${typeLabel}\n\n${body}${this.getEnvInfo()}`;
    const httpRequest = http.createHttp();
    httpRequest.request(FEEDBACK_API, {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/json' },
      extraData: JSON.stringify({ repo: 'DevBox', title: `[DevBox] ${title}`, content: fullBody }),
      connectTimeout: 15000,
      readTimeout: 15000,
    }).then((response) => {
      httpRequest.destroy();
      if (response.responseCode === 200) {
        // 解析返回的 issue_url（函数服务下发 GitCode issue 链接）
        try {
          const res = JSON.parse(response.result as string) as Record<string, Object>;
          const url = res['issue_url'];
          if (typeof url === 'string' && url !== '') {
            this.lastIssueUrl = url;
            this.issueLinkVisible = true;
          }
        } catch (_) {
          // 解析失败不影响成功提示
        }
        DevToast.ok($r('app.string.Index_1'));
      } else {
        DevToast.fail(`提交失败（${response.responseCode})`);
      }
    }).catch(() => {
      httpRequest.destroy();
      DevToast.fail('网络错误，请稍后重试');
    });
    return true; // 异步提交，立即关窗
  }

  private onQueueChange(): void {
    this.queueBadge = TaskQueue.totalCount();   // 总数（进行中+排队）——与面板内容一致
    // 快照进 @State：sheet 的 ForEach 源变化才重渲染（原来直调 snapshot() 无状态依赖，
    // 打开后永不刷新——真机实证：面板移除/新增无反应，切页才变）
    const snap: QueueTask[] = TaskQueue.snapshot();
    const seen: Set<string> = new Set<string>();
    const runIds: string[] = [];
    for (let i = 0; i < snap.length; i++) {
      const g: string = snap[i].group;
      if (!seen.has(g)) { seen.add(g); runIds.push(snap[i].id); }
    }
    this.runningIds = runIds;
    this.queueRows = snap;
  }

  /** 队列面板（bindSheet：进行中+各队列排队项+单项出队） */
  @Builder
  queueSheet(): void {
    Column({ space: 10 }) {
      Text($r('app.string.Index_2')).fontSize(DevTheme.FS_H3).fontWeight(FontWeight.Medium)
        .fontColor(DevTheme.TEXT_PRIMARY).width('100%')
      Text($r('app.string.Index_3'))
        .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY).width('100%')

      Scroll() {
        Column({ space: 8 }) {
          // 右侧让位 14：滚动条贴右缘会压住行尾「移除」按钮（用户反馈重叠）
          ForEach(this.queueRows, (t: QueueTask, idx: number) => {
            Row({ space: 10 }) {
              Column({ space: 2 }) {
                Text(t.label).fontSize(DevTheme.FS_BODY)
                  .fontColor(DevTheme.TEXT_PRIMARY)
                Text(t.group === 'runtime' ? '运行时队列' : t.group === 'pip' ? 'pip 队列' : 'npm 队列')
                  .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)

              if (this.runningIds.includes(t.id)) {
                Text($r('app.string.Index_4')).fontSize(DevTheme.FS_BADGE)
                  .fontColor(DevTheme.PRIMARY)
              } else {
                DevBtn({
                  text: '移除',
                  buttonSize: 'mini',
                  plain: true,
                  onTap: () => { TaskQueue.dequeue(t.id); },
                })
              }
            }.width('100%').padding({ top: 4, bottom: 4, right: 14 })   // 右让位：滚动条压住「移除」
          }, (t: QueueTask, idx: number) => `${t.id}_${idx}`)
        }.width('100%')
      }.layoutWeight(1).scrollBar(BarState.Auto)
      .align(Alignment.TopStart)
    }
    .width('100%').height('100%').padding({ left: 20, right: 20, top: 16, bottom: 16 })
    .alignItems(HorizontalAlign.Start)
  }


  private openFeedback(): void {
    const ctrl: CustomDialogController = new CustomDialogController({
      builder: DevFeedbackDialog({
        appVersion: this.appVersion,
        issueUrl: this.lastIssueUrl,
        issueLinkVisible: this.issueLinkVisible,
        onSubmit: (typeIdx: number, title: string, body: string) => {
          this.issueLinkVisible = false;   // 重新提交时先隐藏旧链接
          return this.submitFeedback(typeIdx, title, body);
        },
      }),
      alignment: DialogAlignment.Center,
      autoCancel: true,
      customStyle: true,
      maskColor: DevTheme.BG_OVERLAY,
    });
    ctrl.open();
  }

  // ─── 页面路由 ─────────────────────────────────────────────

  @Builder
  pageContent() {
    if (this.currentPage === NavPage.OVERVIEW) {
      OverviewPage({
        onNavigate: (page: string) => {
          this.navigateByString(page);
        },
      })
    } else if (this.currentPage === NavPage.PYTHON) {
      PythonManager()
    } else if (this.currentPage === NavPage.JAVA) {
      JavaManager()
    } else if (this.currentPage === NavPage.RUST) {
      RustManager()
    } else if (this.currentPage === NavPage.NODE) {
      NodeManager()
    } else if (this.currentPage === NavPage.LUA) {
      LuaManager()
    } else if (this.currentPage === NavPage.PERL) {
      PerlManager()
    } else if (this.currentPage === NavPage.GO) {
      GoManager()
    } else if (this.currentPage === NavPage.PHP) {
      PhpManager()
    } else if (this.currentPage === NavPage.RUBY) {
      RubyManager()
    } else if (this.currentPage === NavPage.BUN) {
      BunManager()
    } else if (this.currentPage === NavPage.CONAN) {
      PkgManager()
    } else if (this.currentPage === NavPage.HOMEBREW) {
      Harmonybrew()
    } else if (this.currentPage === NavPage.TOOLS) {
      CommonToolsPage()
    } else if (this.currentPage === NavPage.ENV) {
      EnvManager()
    } else if (this.currentPage === NavPage.ABOUT) {
      AboutPage()
    }
  }

  /** 顶栏右侧避让系统三键的内边距（getTitleButtonRect 实测值 + 安全间距） */
  private avoidInset(): number {
    return this.btnAvoidRight + this.btnAvoidWidth + 2;
  }

  build() {
    Row() {
      DevSideNav({
        active: this.activeKey(),
        onNavigate: (page: string) => {
          this.navigateByString(page);
        },
        onFeedback: () => {
          this.openFeedback();
        },
      })

      Column() {
        // ── 顶栏：MCP 状态按钮 + 手动刷新 + 主题滑块（三按钮统一规格/间隔） ──
        Row({ space: 10 }) {
          Blank()
          // MCP 状态胶囊
          Row({ space: 5 }) {
            Circle({ width: 6, height: 6 })
              .fill(this.mcpEnabledStatus ? DevTheme.SUCCESS : DevTheme.TEXT_MUTED)
            Text('MCP')
              .fontSize(DevTheme.FS_LABEL)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.mcpEnabledStatus ? DevTheme.TEXT_SECONDARY : DevTheme.TEXT_MUTED)
          }
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(DevTheme.RADIUS_FULL)
          .backgroundColor(DevTheme.BG_HOVER)
          .border({ width: 1, color: DevTheme.BORDER })
          .onClick(() => {
            this.mcpDialogController.open();
          })
          // 任务队列（badge=排队数；点开面板看出队/进行中）
          Stack({ alignContent: Alignment.TopEnd }) {
            Text('≡')
              .fontSize(18)
              .fontColor(DevTheme.TEXT_SECONDARY)
              .width(32)
              .height(32)
              .textAlign(TextAlign.Center)
              .onClick(() => { this.queueVisible = true; })
            if (this.queueBadge > 0) {
              // badge：右上偏移的数字圆——offset 居中问题用绝对定位代替
              Text(this.queueBadge > 9 ? '9+' : `${this.queueBadge}`)
                .fontSize(10).fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
                .backgroundColor(DevTheme.DANGER)
                .borderRadius(7)
                .constraintSize({ minWidth: 14, minHeight: 14 })
                .padding({ left: 2, right: 2 })
                .textAlign(TextAlign.Center)
                .margin({ top: -4, right: -4 })
            }
          }
          .bindSheet($$this.queueVisible, this.queueSheet(), {
            detents: [SheetSize.MEDIUM, SheetSize.LARGE],
            dragBar: true,
            showClose: false,
            enableOutsideInteractive: false,
            // 正确关闭 API（MCP 调研：shouldDismiss 是 Popup 的不是 Sheet 的）：
            // onWillDismiss 在任何 dismiss 手势（ESC/拖下/点 mask）触发——
            // 直接调 dismiss() 允许关闭
            onWillDismiss: ((dismissSheetAction: DismissSheetAction) => {
              dismissSheetAction.dismiss();
              this.queueVisible = false;
            }),
          })
          // 手动刷新（纯图标，无背景，与主题按钮同规格）
          Text('⟳')
            .fontSize(18)
            .fontColor(DevTheme.TEXT_SECONDARY)
            .width(32)
            .height(32)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              DevToast.show($r('app.string.Index_5'));
              EnvStore.refreshAll();
              // 运行时态全局重检（bump 后各语言页重扫本地安装态；Python 页联动重查 pip 列表）
              AppStorage.setOrCreate('runtime_epoch', Date.now());
            })
          DevThemeSwitch({
            onToggle: () => {
              this.toggleTheme();
            },
          })
        }
        .width('100%')
        .height(48)
        .padding({ left: 24, right: this.avoidInset() })
        .alignItems(VerticalAlign.Center)

        // ── 内容区 ──
        Column() {
          this.pageContent()
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ top: 28 })
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DevTheme.BG)
  }
}
