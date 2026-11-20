/**
 * TrayAbility — 后台保活 Ability（NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM 模式）
 *
 * 运行在独立进程，生命周期与状态栏托盘图标强绑定，系统不回收。
 * MCP Server 在本进程运行，主窗口关闭 / 主进程销毁后持续服务。
 *
 * 托盘图标由主进程（EntryAbility）添加——这是 NEW_PROCESS 模式的前置条件；
 * 本 Ability 只托管 MCP Server，不重复注册图标。
 *
 * 命令通道（双路）：
 * 1. 管理通道（主路）：AdminServer :18766，主进程任意状态（含后台）HTTP 直达
 *    —— startAbility 在主进程后台时会被系统拦截，管理通道不受限
 * 2. Want action（回退/冷启动）：action.mcp.start / action.mcp.stop / action.exit
 *
 * 开关状态持久化（McpPrefs）：本进程是唯一写入方；
 * 启动时读取上次状态，关闭状态不会在下次启动时自动拉起。
 */
import { UIAbility, Want, AbilityConstant, ConfigurationConstant, wantAgent, WantAgent } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { McpServer } from '../mcpservice/McpServer';
import { McpToolRegistry } from '../mcpservice/McpToolRegistry';
import { McpConfirm } from '../mcpservice/McpConfirm';
import { McpPrefs, BrewPathPrefs } from '../utils/McpPrefs';
import { EnvStore } from '../utils/EnvStore';
import { PyCatalogService } from '../utils/PyCatalogService';
import { AdminServer, AdminHandler } from '../utils/AdminServer';
import { DevEnvPaths } from '../utils/DevEnvPaths';
import { DevGateService } from '../utils/DevGateService';
import { BrewCatalogService } from '../utils/BrewCatalogService';
import { ConanCatalogService } from '../utils/ConanCatalogService';











const TAG = 'TrayAbility';

/** 管理通道命令处理器（ArkTS 方法型接口须用类实现） */
class TrayAdminHandler implements AdminHandler {
  private readonly owner: TrayAbility;

  constructor(owner: TrayAbility) {
    this.owner = owner;
  }

  onCommand(cmd: string): string {
    return this.owner.handleCommand(cmd);
  }
}

export default class TrayAbility extends UIAbility {

  private mcp: McpServer | null = null;
  private admin: AdminServer | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'onCreate: tray-bound background process starting');
    AppStorage.setOrCreate('ui_context_ctx', this.context);
    AppStorage.setOrCreate('tray_context_ctx', this.context);

    // 管理通道常驻（即使 MCP 未启动，主进程也能通过它拉起服务）
    AdminServer.initToken(this.context.filesDir);
    this.admin = new AdminServer(18766, new TrayAdminHandler(this));
    this.admin.start();

    // MCP 敏感操作确认中心（通知+WantAgent 拉前台确认；McpToolRegistry 确认门依赖）
    McpConfirm.init(this.context);

    // 长时任务（数据传输）：防退后台网络冻结——窗口附着只保证进程存活，
    // 不保证网络不被挂起；后台下载/MCP 服务连续性依赖此任务（KEEP_BACKGROUND_RUNNING）
    this.startContinuousTask();



    // 预热统一数据层（EnvStore：种子目录 + 远程 manifest + 本地账本纠正，MCP 首调即有数据）
    EnvStore.loadSeed(this.context);
    McpToolRegistry.ensureRepo();
    EnvStore.ensureLocal(true);

    // 目录预热（brew/conan 搜索工具首调即命中，不再"加载中"空回）
    // ——磁盘缓存秒出（TTL 过期后台刷新，stale-while-revalidate 同 UI 页）
    BrewCatalogService.init(this.context);
    ConanCatalogService.init(this.context);
    ConanCatalogService.ensure();

    // brew PATH 优先位水化（审计 F2）：本进程独立于主进程——MCP uninstall_runtime
    // 等任务经本进程调 DevEnvPaths.rewriteEnvBlock，静态位不水化会用 rank 3
    // 静默回写块序（UI 开关仍亮的假象）。镜像 EntryAbility 的水化语义。
    BrewPathPrefs.get(this.context).then((on: boolean) => {
      DevEnvPaths.brewPathPriority = on;
    });
    // 环境前置门水化：MCP call() 入口按 DevGateService.gate 拦截——
    // 本进程不查则恒 'unknown'（拦截条件 gate!=='ok' 会误伤全量工具）
    DevGateService.check(this.context);

    // Python 适配目录（catalog_search / pip_install 适配检测依赖；磁盘缓存→网络 .gz）
    PyCatalogService.init(this.context);
    PyCatalogService.ensure();

    // 冷启动带 action.mcp.start（UI 首次开启 MCP 的拉起路径）：直接启动并持久化
    const action: string = want.action ?? '';
    if (action === 'action.mcp.start') {
      this.startMcp();
      McpPrefs.setMcpEnabled(this.context, true);
      return;
    }
    // 常规启动：按上次持久化的开关状态决定是否拉起 MCP Server（默认关闭，用户主动开启后才持久化为开）
    McpPrefs.getMcpEnabled(this.context).then((on: boolean) => {
      if (on) {
        this.startMcp();
      } else {
        hilog.info(0x0000, TAG, 'MCP disabled by user preference, server not started');
      }
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const action: string = want.action ?? '';
    hilog.info(0x0000, TAG, 'onNewWant: action=%{public}s', action);
    if (action === 'action.mcp.start') {
      this.startMcp();
      McpPrefs.setMcpEnabled(this.context, true);
    } else if (action === 'action.mcp.stop') {
      this.stopMcp();
      McpPrefs.setMcpEnabled(this.context, false);
    } else if (action === 'action.exit') {
      this.stopMcp();
      this.context.terminateSelf();
    }
  }

  /** 管理通道命令处理（返回 JSON 响应体） */
  handleCommand(cmd: string): string {
    hilog.info(0x0000, TAG, 'admin cmd: %{public}s', cmd);
    // MCP 敏感操作确认回传（主进程 DevConfirm 的用户决定）
    if (cmd.startsWith('confirm.approve:')) {
      const opId: string = cmd.substring('confirm.approve:'.length);
      const result: string = McpConfirm.approve(opId);
      return JSON.stringify({ 'ok': true, 'result': result });
    }
    if (cmd.startsWith('confirm.reject:')) {
      const opId: string = cmd.substring('confirm.reject:'.length);
      return JSON.stringify({ 'ok': true, 'result': McpConfirm.reject(opId) });
    }
    if (cmd === 'confirm.pending') {
      return JSON.stringify({ 'pending': McpConfirm.count() });
    }
    if (cmd === 'mcp.start') {
      this.startMcp();
      McpPrefs.setMcpEnabled(this.context, true);
      return '{"ok":true,"mcp":true}';
    }
    if (cmd === 'mcp.stop') {
      this.stopMcp();
      McpPrefs.setMcpEnabled(this.context, false);
      return '{"ok":true,"mcp":false}';
    }
    if (cmd === 'status') {
      const running: boolean = this.mcp !== null && this.mcp.isRunning();
      return running ? '{"mcp":true}' : '{"mcp":false}';
    }
    if (cmd === 'ui.show') {
      // 拉起/前置主窗口（托盘远程路径；startAbility 后由 EntryAbility onStart 的 show 兜底）
      this.context.startAbility({
        bundleName: 'com.develop.opensource.devbox',
        abilityName: 'EntryAbility',
      } as Want).catch(() => {});
      return '{"ok":true}';
    }
    if (cmd === 'exit') {
      this.stopMcp();
      this.context.terminateSelf();
      return '{"ok":true}';
    }
    return '{"ok":false}';
  }

  private startMcp(): void {
    if (this.mcp === null) {
      this.mcp = new McpServer(18765);
    }
    this.mcp.start();
    hilog.info(0x0000, TAG, 'MCP Server started on :18765');
  }

  private stopMcp(): void {
    if (this.mcp !== null) {
      this.mcp.stop();
      this.mcp = null;
    }
    hilog.info(0x0000, TAG, 'MCP Server stopped');
  }

  /** 长时任务（DATA_TRANSFER）：进程存活期间持续申请，防退后台网络挂起。
   *  wantAgent 指向主应用（点击系统长时任务通知回到 DevBox）。 */
  private startContinuousTask(): void {
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: 'com.develop.opensource.devbox',
          abilityName: 'EntryAbility',
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      };
      wantAgent.getWantAgent(wantAgentInfo).then((agent: WantAgent) => {
        backgroundTaskManager.startBackgroundRunning(
          this.context,
          backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
          agent,
        ).then(() => {
          hilog.info(0x0000, TAG, 'ContinuousTask started (DATA_TRANSFER)');
        }).catch((e: BusinessError) => {
          hilog.error(0x0000, TAG, 'startBackgroundRunning FAIL: %{public}d %{public}s', e.code, e.message);
        });
      }).catch((e: BusinessError) => {
        hilog.error(0x0000, TAG, 'getWantAgent FAIL: %{public}d', e.code);
      });
    } catch (e) {
      hilog.error(0x0000, TAG, 'startContinuousTask exception: %{public}s', JSON.stringify(e) ?? '');
    }
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'onDestroy (process exits, tray icon removed by system)');
    try {
      backgroundTaskManager.stopBackgroundRunning(this.context);
    } catch (_) {
    }
    this.stopMcp();
    if (this.admin !== null) {
      this.admin.stop();
      this.admin = null;
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // STARTUP_HIDE 模式启动，不显示窗口
    hilog.info(0x0000, TAG, 'onWindowStageCreate (hidden mode)');
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
  }

  onBackground(): void {
  }
}
