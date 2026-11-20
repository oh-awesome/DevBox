/**
 * ConfirmAbility —— MCP 敏感操作确认专用小窗（独立 entry）
 *
 * McpConfirm 的确认通知点击后由 WantAgent 拉起本 Ability（而非主 EntryAbility：
 * 不唤醒整个应用）。窗口为锁死尺寸的紧凑确认卡（用户决定后自毁）。
 *
 * 窗口规范与主应用一致（EntryAbility 同款时序：getMainWindow 与 loadContent 并行）：
 * - setWindowDecorVisible(false) + setWindowDecorHeight(48)：隐藏系统标题栏、
 *   保留系统窗口三键区；三键配色随主题（setDecorButtonStyle）
 * - setResizeByDragEnabled(false) + resize(W, H)：尺寸锁死（module.json5 同时声明
 *   minWindowWidth/Height 同值——系统默认最小尺寸会压过 resize，不声明则窗口偏大）
 * - 主题恢复（DevTheme.applyTheme + colorMode）在 loadContent 前完成，防首帧错配
 *
 * - 与主进程同进程（默认 processMode）→ AppStorage 传参给页面
 * - singleton：连续多条通知点击复用窗口，onNewWant 更新内容（ts 进 JSON 保证变更触发）
 * - 未决关闭（用户直接关窗）兜底：onDestroy 回传 reject，不留悬挂 pending
 */
import { AbilityConstant, UIAbility, Want, ConfigurationConstant, common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import dataPreferences from '@ohos.data.preferences';
import { DevTheme, ThemeMode } from '../common/DevTheme';
import { AdminClient } from '../utils/AdminServer';

const TAG = 'ConfirmAbility';
const WINDOW_W = 520;
const WINDOW_H = 340;

export default class ConfirmAbility extends UIAbility {

  private windowStageRef: window.WindowStage | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'onCreate（敏感操作确认小窗）');
    AppStorage.setOrCreate('ui_context_ctx', this.context);
    // 独立拉起时本进程可能是首个宿主——同样注入 tokenDir（与 EntryAbility 幂等）
    AdminClient.setTokenDir(this.context.filesDir);
    AppStorage.setOrCreate('mcp_confirm_decided', false);
    this.bridge(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParam);
    hilog.info(0x0000, TAG, 'onNewWant（更新确认内容）');
    this.bridge(want);
    // singleton 复用窗口：规格重申（否则窗口沿用旧尺寸/旧三键态，页面内容却是新的）
    if (this.windowStageRef !== null) {
      this.applyWindowSpec(this.windowStageRef, 'onNewWant');
    }
  }

  /** Want 参数（mcp_confirm_op/title/body）→ AppStorage，页面直读。
   *  每次写入新 op 同步重置 decided 标记——singleton 复用窗口时若沿用上一次
   *  的 decided=true，onDestroy 兜底 reject 将永久失效（审计 6-1）。 */
  private bridge(want: Want): void {
    const op = `${want.parameters?.['mcp_confirm_op'] ?? ''}`;
    if (op === '') { return; }
    AppStorage.setOrCreate('mcp_confirm_decided', false);
    AppStorage.setOrCreate('mcp_confirm', JSON.stringify({
      op: op,
      title: `${want.parameters?.['mcp_confirm_title'] ?? 'DevBox 敏感操作确认'}`,
      body: `${want.parameters?.['mcp_confirm_body'] ?? ''}`,
      detail: `${want.parameters?.['mcp_confirm_detail'] ?? ''}`,
      ts: Date.now(),
    }));
  }

  private lastColorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, TAG, 'onWindowStageCreate');
    this.windowStageRef = windowStage;
    // 主题先于 loadContent 恢复（防首帧明暗错配——主应用同款教训）
    this.restoreTheme().then((mode: ThemeMode) => {
      this.lastColorMode = mode === 'dark'
        ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      this.applyWindowSpec(windowStage, 'early');
      windowStage.loadContent('pages/mcp_confirm_page', (err) => {
        if (err.code) {
          hilog.error(0x0000, TAG, 'loadContent failed: %{public}s', JSON.stringify(err) ?? '');
          return;
        }
        this.applyWindowSpec(windowStage, 'loaded');
        windowStage.getMainWindow().then((w: window.Window) => {
          w.showWindow().catch((_e: object) => {});
        }).catch((_e: object) => {});
        setTimeout(() => { this.applyWindowSpec(windowStage, 'shown600'); }, 600);
        setTimeout(() => { this.applyWindowSpec(windowStage, 'shown1600'); }, 1600);
      });
    });
  }

  /** 窗口规格（多时机重申——系统门控时机不定）：decor 隐藏+三键区 0+锁尺寸+透明底。
   *  每调用独立防护 + Promise catch（此前 resize/resizeByDrag 静默失败不可见）。 */
  private applyWindowSpec(stage: window.WindowStage, label: string): void {
    stage.getMainWindow().then((w: window.Window) => {
      const pc = (name: string, p: Promise<void>): void => {
        p.then(() => {
          hilog.info(0x0000, TAG, '%{public}s ok@%{public}s', name, label);
        }).catch((e: BusinessError) => {
          hilog.error(0x0000, TAG, '%{public}s FAIL@%{public}s: %{public}d %{public}s', name, label, e.code, e.message);
        });
      };
      try {
        w.setWindowDecorVisible(false);
        // 三键隐藏：官方 API（API 14+ PC 专属）——参数顺序（最大化,最小化,关闭）
        w.setWindowTitleButtonVisible(false, false, false);
        w.setWindowDecorHeight(0);
        w.setDecorButtonStyle({ colorMode: this.lastColorMode });
        // 尺寸由 module.json5 min=max 静态锁死（官方方案，系统禁拖拽）——不调 resize
        // 窗口背景透明：卡片圆角外四角透出桌面（setWindowBackgroundColor 为同步 void）
        w.setWindowBackgroundColor('#00000000');
        hilog.info(0x0000, TAG, 'spec applied@%{public}s', label);
      } catch (e) {
        hilog.error(0x0000, TAG, 'spec sync failed@%{public}s: %{public}s', label, JSON.stringify(e) ?? '');
      }
    }).catch((e: BusinessError) => {
      hilog.error(0x0000, TAG, 'getMainWindow failed@%{public}s: %{public}s', label, e.message);
    });
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'onDestroy');
    // 未决关闭（用户直接关窗/系统回收）兜底作废，不留悬挂 pending（30 分钟等过期太长）
    const decided: boolean = AppStorage.get<boolean>('mcp_confirm_decided') ?? false;
    if (decided) { return; }
    const raw: string = AppStorage.get<string>('mcp_confirm') ?? '';
    if (raw === '') { return; }
    try {
      const req: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      const op: string = `${req['op'] ?? ''}`;
      if (op !== '') {
        AdminClient.post(`confirm.reject:${op}`).then((_ok: boolean) => {});
      }
    } catch (_) {
    }
  }

  /** 启动时恢复持久化主题（主应用 restoreTheme 同款，读取同一偏好键） */
  private async restoreTheme(): Promise<ThemeMode> {
    let mode: ThemeMode = 'light';
    try {
      const pref = await dataPreferences.getPreferences(this.context, 'first_use_pref');
      const saved = await pref.get('theme_mode', 'light') as string;
      mode = saved === 'dark' ? 'dark' : 'light';
    } catch (_) {
    }
    DevTheme.applyTheme(mode);
    AppStorage.setOrCreate('themeMode', mode);
    try {
      const ctx = this.context as common.Context;
      ctx.getApplicationContext().setColorMode(
        mode === 'dark'
          ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT,
      );
    } catch (_) {
    }
    return mode;
  }
}
