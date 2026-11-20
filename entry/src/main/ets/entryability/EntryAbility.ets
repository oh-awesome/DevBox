import { AbilityConstant, ConfigurationConstant, UIAbility, Want, StartOptions, contextConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { IBestInit, IBestSetUIBaseStyle } from '@ibestservices/ibest-ui-v2';
import dataPreferences from '@ohos.data.preferences';
import { DevTheme, ThemeMode } from '../common/DevTheme';
import { TrayService } from '../utils/TrayService';
import { McpPrefs, BrewPathPrefs } from '../utils/McpPrefs';
import { AdminClient } from '../utils/AdminServer';
import { DiscoveryService } from '../utils/DiscoveryService';
import { DevEnvPaths } from '../utils/DevEnvPaths';
import { DevGateService } from '../utils/DevGateService';

export default class EntryAbility extends UIAbility {
  private testMode: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
    AppStorage.setOrCreate('ui_context_ctx', this.context);
    // 管理通道认证：注入沙箱目录（AdminClient 懒加载 admin_token）
    AdminClient.setTokenDir(this.context.filesDir);
    // UI 自动化测试模式（aa start --ps test_mode true）：主窗口 maximize 锁定全屏，
    // 消除自由窗口位置/尺寸漂移（视觉测试坐标稳定的前提）。正常启动不受影响。
    const tp = want.parameters?.['test_mode'];
    this.testMode = `${tp}` === 'true';
    // 发现服务：唯一平台入口，所有数据源端点由它推导（live→缓存→种子降级）
    DiscoveryService.resolve(this.context);
    // 运行环境前置门（开发者模式 + 非应用市场扩展）：异步检测水化
    // AppStorage（env_gate/env_gate_ready）——总览页/侧栏/MCP 按此拦截
    DevGateService.check(this.context);
    // 按持久化的 MCP 开关状态决定本会话是否有托盘：
    // - 开 → 注册托盘图标（异步确认后）→ 拉起 TrayAbility 独立进程（MCP Server 宿主）
    // - 关 → 不注册图标、不拉起托盘进程（应用按普通窗口应用行为运行）
    McpPrefs.getMcpEnabled(this.context).then((on: boolean) => {
      AppStorage.setOrCreate('mcp_enabled', on);
      if (on) {
        TrayService.add(this.context, () => {
          this.launchTrayAbility('');
        });
      } else {
        hilog.info(0x0000, 'testTag', 'MCP off by preference: no tray this session');
      }
    });
    // brew PATH 优先水化（brew 页勾选项）：rank 排序 + 环境页冲突检测都读静态位
    // （审计 F7：水化异步竞态窗内 rewriteEnvBlock 会写出与开关态相反的块序——
    //  对 on=true 补一次幂等重写，顺带清掉"重启后开关亮但文件序旧"的残留态）
    BrewPathPrefs.get(this.context).then((on: boolean) => {
      DevEnvPaths.brewPathPriority = on;
      AppStorage.setOrCreate('brew_path_priority', on);
      if (on) {
        DevEnvPaths.rewriteEnvBlock([]);
      }
    });
  }

  /**
   * 拉起 TrayAbility（独立进程，生命周期绑定状态栏托盘图标，系统不回收）。
   * action 为空 = 启动；'action.mcp.start' / 'action.mcp.stop' = 开关 MCP Server。
   */
  private launchTrayAbility(action: string, retry: number = 0): void {
    try {
      const trayWant: Want = {
        bundleName: 'com.develop.opensource.devbox',
        abilityName: 'TrayAbility',
      };
      if (action !== '') {
        trayWant.action = action;
      }
      const options: StartOptions = {
        processMode: contextConstant.ProcessMode.NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM,
        startupVisibility: contextConstant.StartupVisibility.STARTUP_HIDE,
      };
      this.context.startAbility(trayWant, options).then(() => {
        hilog.info(0x0000, 'testTag', 'TrayAbility launched, action=%{public}s', action === '' ? '(boot)' : action);
      }).catch((e: BusinessError) => {
        // 16000067 = 状态栏图标尚未就绪：注册确认与系统侧生效之间仍有窗口，退避重试
        if (e.code === 16000067 && retry < 5) {
          hilog.warn(0x0000, 'testTag', 'StartOptions not ready, retry %{public}d in 500ms', retry);
          setTimeout(() => {
            this.launchTrayAbility(action, retry + 1);
          }, 500);
          return;
        }
        hilog.error(0x0000, 'testTag', 'TrayAbility launch FAILED: %{public}s %{public}s',
          `${e.code}`, `${e.message}`);
      });
    } catch (e) {
      hilog.error(0x0000, 'testTag', 'TrayAbility launch threw: %{public}s', `${e}`);
    }
  }

  onDestroy(): void {
    // 主进程销毁不影响托盘：TrayAbility 进程绑定状态栏图标，系统保持存活
    hilog.info(0x0000, 'testTag', 'Ability onDestroy (tray process survives)');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParam);
    // 热启动重入：强制显示主窗口（aa start/托盘恢复最小化窗口时不会自动置前）
    try {
      window.getLastWindow(this.context).then((w: window.Window) => {
        // 最小化/被压后台双兜底：restore 还原 + showWindow 显示（restore 对已显示窗口无害）
        w.restore().catch(() => {
        });
        w.showWindow().catch(() => {
        });
      }).catch(() => {});
    } catch (_) {
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 必须在 loadContent 之前恢复深浅色主题：
    // 否则首帧按默认浅色渲染（窗口/系统资源为白），深色令牌稍后才生效，
    // 出现“标题白色看不见、卡片颜色切换晚、页签文字发灰”的错配。
    // 托盘图标（鸿蒙 PC 状态栏）
    // Tray 由 TrayAbility 进程管理


    this.restoreTheme().then((mode: ThemeMode) => {
      windowStage.loadContent('pages/Index', (err) => {
        if (err.code) {
          hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
          return;
        }
        hilog.info(0x0000, 'testTag', 'Succeeded in loading the content.');
        // 供页面查询主窗口（三键区域避让等，见应用适配自由窗口指南）
        AppStorage.setOrCreate<window.WindowStage>('windowStage', windowStage);
        // 窗口尺寸：允许自由调整（用户需要非全屏窗口）
        // 建议最小宽度 1440vp（2880 物理像素）——brew 页左列表右详情+分页
        // 低于此宽会挤压变形；当前无 setWindowMinWindowSize API，依赖用户自律
        // IBest-UI-V2 组件库初始化 + DevBox Figma 深灰主题基础样式（DESIGN.md）
        IBestInit(windowStage, this.context);
        IBestSetUIBaseStyle({
          default: '#FFFFFF',
          primary: '#0B6FCC',
          success: '#14AE5C',
          warning: '#F5C518',
          danger: '#F24822',
          primaryOpacity: 'rgba(13,153,255,0.12)',
          successOpacity: 'rgba(20,174,92,0.12)',
          warningOpacity: 'rgba(245,197,24,0.12)',
          dangerOpacity: 'rgba(242,72,34,0.12)',
        });
      });
      windowStage.getMainWindow().then((myWindow: window.Window) => {
        if (this.testMode) {
          // 测试模式：铺满全屏（窗口位置/尺寸固定 → dump/截图/模板坐标全稳定）
          myWindow.maximize(window.MaximizePresentation.ENTER_IMMERSIVE).catch((e: BusinessError) => {
            hilog.error(0x0000, 'testTag', 'testMode maximize failed: %{public}s %{public}s', `${e.code}`, `${e.message}`);
          });
        }
        myWindow.setWindowDecorVisible(false);
        myWindow.setWindowDecorHeight(48);
        // 窗口控制按钮颜色随主题：深色底用亮按钮，浅色底用暗按钮
        myWindow.setDecorButtonStyle({
          colorMode: mode === 'dark'
            ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
            : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        });
      });
    });
  }

  /** 启动时恢复持久化主题：应用令牌 + AppStorage + 应用级 colorMode 三处对齐 */
  private async restoreTheme(): Promise<ThemeMode> {
    let mode: ThemeMode = 'light';
    try {
      const pref = await dataPreferences.getPreferences(this.context, 'first_use_pref');
      const saved = await pref.get('theme_mode', 'light') as string;
      mode = saved === 'dark' ? 'dark' : 'light';
    } catch (_) {
      // 读取失败按浅色处理
    }
    DevTheme.applyTheme(mode);
    AppStorage.setOrCreate('themeMode', mode);
    try {
      this.context.getApplicationContext().setColorMode(
        mode === 'dark'
          ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      );
    } catch (_) {
    }
    return mode;
  }

  onWindowStageDestroy(): void {
      // Main window is destroyed, release UI related resources
      hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  /**
   * 拦截窗口关闭：
   * - 有托盘（MCP 运行中）→ 保留进程（最小化到托盘），托盘进程继续保活 MCP；
   *   左键托盘 → TrayService 直接 showWindow 恢复窗口
   *   （注：hideAbility/showAbility 仅对状态栏绑定的 Ability 有效，主窗口恢复走窗口 API）
   * - 无托盘（MCP 关闭）→ 不拦截，正常退出
   */
  onPrepareToTerminate(): boolean {
    if (!TrayService.isAdded()) {
      hilog.info(0x0000, 'testTag', 'onPrepareToTerminate: no tray, normal exit');
      return false;
    }
    hilog.info(0x0000, 'testTag', 'onPrepareToTerminate: keep process (tray active)');
    return true;
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
