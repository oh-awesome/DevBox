/**
 * TrayService — 鸿蒙 PC 托盘服务（statusBarManager）
 *
 * 交互定义：
 * - 左键单击 → 显示主窗口（主路：直接 showWindow，不经过 startAbility，
 *   主进程存活时不受后台启动限制；回退：startAbility）
 * - 右键菜单（自定义项仅一个）：
 *   - 「MCP 服务」→ 打开主窗口并直达 MCP 配置弹窗（AppStorage 信号 tray_open_mcp）
 *   - 退出由系统托盘菜单自带，不自定义
 *
 * 技术约束：
 * - 托盘图标必须在主进程（EntryAbility）注册——这是
 *   NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM 启动模式的前置条件
 * - 一级菜单项挂 menuAction 时必须带 menuCode（notifyOnly 事件路由依赖它）
 * - addToStatusBar 注册是异步的，须在系统确认回调后再拉起 TrayAbility
 * - MCP 关闭状态启动的应用不注册托盘；首次开启 MCP 时按需注册并拉起
 */
import { statusBarManager } from '@kit.DeskTopExtensionKit';
import { image } from '@kit.ImageKit';
import { common, Want, StartOptions, contextConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AdminClient } from './AdminServer';

const TAG = 'TrayService';
const BUNDLE = 'com.develop.opensource.devbox';

export class TrayService {


  private static added: boolean = false;
  private static mainCtx: common.UIAbilityContext | null = null;

  /** 托盘是否已注册（决定 onPrepareToTerminate 保进程还是正常退出） */
  static isAdded(): boolean {
    return TrayService.added;
  }

  /** 添加托盘图标；onReady 在系统确认注册成功后回调（此时 NEW_PROCESS 模式前置条件才满足） */
  static add(ctx: common.UIAbilityContext, onReady: () => void): void {
    TrayService.mainCtx = ctx;
    if (TrayService.added) {
      onReady();
      return;
    }
    TrayService.addAsync(ctx, onReady);
  }

  private static async addAsync(ctx: common.UIAbilityContext, onReady: () => void): Promise<void> {
    try {
      // 读取图标（SVG 解码必须显式指定 desiredSize，否则默认尺寸超出状态栏限制）
      const rm = ctx.resourceManager;
      const whiteBuf = rm.getRawFileContentSync('tray-white.svg');
      const blackBuf = rm.getRawFileContentSync('tray-black.svg');
      const whiteSource = image.createImageSource(whiteBuf.buffer);
      const blackSource = image.createImageSource(blackBuf.buffer);
      const decodeOpts: image.DecodingOptions = {
        desiredSize: { width: 48, height: 48 },
      };
      const white = await whiteSource.createPixelMap(decodeOpts);
      const black = await blackSource.createPixelMap(decodeOpts);

      // 组装托盘项（菜单静态：MCP 服务 / 退出）
      const item: statusBarManager.StatusBarItem = {
        icons: { white: white as image.PixelMap, black: black as image.PixelMap },
        statusBarGroupMenu: TrayService.buildMenus(),
        quickOperation: TrayService.buildQuickOp(),
        hoverTips: 'DevBox 开发环境管理',
      };

      // 注册是异步的：必须等系统回调确认后，状态栏才真正有图标，
      // 此时 startAbility(NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM) 的前置条件才成立
      statusBarManager.addToStatusBar(ctx, item, (error: BusinessError) => {
        if (error) {
          hilog.error(0x0000, TAG, 'addToStatusBar callback error: %{public}s %{public}s',
            `${error.code}`, `${error.message}`);
          return;
        }
        TrayService.added = true;
        hilog.info(0x0000, TAG, 'Icon registered (system confirmed)');
        onReady();
      });

      // 左键点击 → 打开主窗口
      statusBarManager.on('statusBarIconClick', (evt) => {
        const data: Record<string, Object> = evt.data ?? {};
        const clickType: string = (data['iconClickType'] as string) ?? '';
        if (clickType === 'leftClick') {
          TrayService.showMainWindow(ctx);
        }
      });

      // 右键菜单点击（menuCode 路由）
      statusBarManager.on('rightMenuClick', (evt) => {
        const rdata: Record<string, Object> = evt.data ?? {};
        const code: string = (rdata['menuCode'] as string) ?? '';
        if (code === 'mcp-config') {
          TrayService.showMainWindow(ctx);
          AppStorage.setOrCreate('tray_open_mcp', Date.now());
        }
      });
    } catch (e) {
      hilog.error(0x0000, TAG, 'addToStatusBar FAILED: %{public}s', `${e}`);
    }
  }

  /** 左键快捷操作：abilityName 传空串，点击不弹系统面板，走 statusBarIconClick 监听 */
  private static buildQuickOp(): statusBarManager.QuickOperation {
    return {
      title: 'DevBox MCP',
      height: 1,
      abilityName: '',
      moduleName: 'entry',
    };
  }

  /**
   * 右键菜单：
   * - 「打开 DevBox」：非 notifyOnly 直接拉起（系统执行，不受应用后台启动限制——
   *   左键/事件路径在主进程后台时会被拦，此项保证可靠恢复窗口）
   * - 「MCP 服务」：notifyOnly 事件 → 显示窗口 + 直达 MCP 配置
   * - 退出用系统托盘自带项
   */
  private static buildMenus(): statusBarManager.StatusBarGroupMenu[] {
    const actOpen: statusBarManager.StatusBarMenuAction = {
      abilityName: 'EntryAbility',
      menuCode: 'open-main',
    };
    const itemOpen: statusBarManager.StatusBarMenuItem = {
      title: '打开 DevBox',
      menuAction: actOpen,
    };
    const actMcp: statusBarManager.StatusBarMenuAction = {
      abilityName: 'EntryAbility',
      notifyOnly: true,
      menuCode: 'mcp-config',
    };
    const itemMcp: statusBarManager.StatusBarMenuItem = {
      title: 'MCP 服务',
      menuAction: actMcp,
    };
    const group: statusBarManager.StatusBarGroupMenu = [itemOpen, itemMcp];
    return [group];
  }

  /**
   * 显示主窗口：
   * 主路 window.getLastWindow + showWindow —— 直接窗口操作，不经过 startAbility，
   * 主进程存活（窗口关闭但进程保活）时不受后台启动限制；
   * 回退 startAbility —— 主进程/窗口已销毁重建的场景。
   */
  private static showMainWindow(ctx: common.UIAbilityContext): void {
    window.getLastWindow(ctx).then((win: window.Window) => {
      return win.showWindow();
    }).then(() => {
      hilog.info(0x0000, TAG, 'Main window shown (showWindow)');
    }).catch(() => {
      try {
        const want: Want = {
          bundleName: BUNDLE,
          abilityName: 'EntryAbility',
          action: 'action.show',
        };
        ctx.startAbility(want).catch(() => {});
      } catch (_) {
      }
    });
  }

  /**
   * 开关 MCP Server。
   * - 托盘进程未起（MCP 关闭状态启动的应用，首次开启）：先注册图标（前台时机），
   *   系统确认后拉起托盘进程并启动 MCP
   * - 常规：管理通道 HTTP 直达托盘进程（主进程任意状态可用），
   *   送达失败回退 startAbility（仅前台有效）
   */
  static setMcpRunning(running: boolean): void {
    const ctx = AppStorage.get<common.UIAbilityContext>('ui_context_ctx');
    if (ctx === null || ctx === undefined) { return; }
    if (running && !TrayService.added) {
      TrayService.add(ctx, () => {
        TrayService.sendWant('action.mcp.start');
      });
      return;
    }
    AdminClient.post(running ? 'mcp.start' : 'mcp.stop').then((ok: boolean) => {
      if (!ok) {
        TrayService.sendWant(running ? 'action.mcp.start' : 'action.mcp.stop');
      }
    });
  }


  /** Want action 回退通道（冷启动拉起 / 管理通道不可达时） */
  private static sendWant(action: string): void {
    try {
      const ctx = AppStorage.get<common.UIAbilityContext>('ui_context_ctx');
      if (ctx === null || ctx === undefined) { return; }
      const want: Want = {
        bundleName: BUNDLE,
        abilityName: 'TrayAbility',
        action: action,
      };
      const options: StartOptions = {
        processMode: contextConstant.ProcessMode.NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM,
        startupVisibility: contextConstant.StartupVisibility.STARTUP_HIDE,
      };
      ctx.startAbility(want, options).catch(() => {});
    } catch (_) {
    }
  }
}
