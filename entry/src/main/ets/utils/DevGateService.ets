/**
 * DevGateService —— 运行环境前置门（开发者模式 + 非应用市场扩展程序）
 *
 * 应用要求：两个系统开关均开启才可用（DevBox 安装/运行的开发工具属
 * 非应用市场二进制，需系统放行；开发者模式是调试与 ACL 权限生态的前提）。
 *
 * 检测通道（2026-11-16 官方文档调研实证）：
 * 1. 开发者模式：DeviceSecurityKit SafetyDetect.queryRiskFactors
 *    （API 26.0.0+，RiskFactorType.IS_DEVELOPER_MODE，无需权限，JWS 解 payload）
 * 2. 非应用市场扩展程序：权限法（checkAccessToken ohos.permission.kernel.
 *    SUPPORT_PLUGIN）——开发者模式下 debug 安装经 bm -g 自动授予
 *    manual_settings 权限；开关与权限的联动关系留真机对照位（PROBE 策略
 *    可替换，见 checkLocalPlugin 注释）。
 *
 * UI/MCP 消费：AppStorage 'env_gate'（'ok' | 'blocked_dev' | 'blocked_plugin' |
 * 'blocked_both' | 'unknown'）+ env_gate_ready 布尔；MCP call() 入口按
 * 白名单放行检测类工具，其余统一拦截。
 */
import { BusinessError, settings } from '@kit.BasicServicesKit';
import { common, Want } from '@kit.AbilityKit';
import Logger from './Logger';

const TAG = 'DevGateService';


export type EnvGate = 'ok' | 'blocked_dev' | 'blocked_plugin' | 'blocked_both' | 'unknown';

interface GateState {
  developerMode: boolean;
  localPlugin: boolean;
  gate: EnvGate;
}

export class DevGateService {

  private static state: GateState = { developerMode: false, localPlugin: false, gate: 'unknown' };
  private static checking: boolean = false;
  private static checkedOnce: boolean = false;

  static get gate(): EnvGate {
    return DevGateService.state.gate;
  }

  static get ready(): boolean {
    return DevGateService.state.gate === 'ok';
  }

  static get developerMode(): boolean {
    return DevGateService.state.developerMode;
  }

  static get localPlugin(): boolean {
    return DevGateService.state.localPlugin;
  }

  /** 检测两条件并水化 AppStorage（幂等；checking 中直接返回当前态） */
  /**
   * 检测（2026-11-16 终版：只提醒不检查——所有检测通道实测均不可用）：
   * - isDeveloperMode()：API 26 SDK/运行时均不存在
   * - queryRiskFactors：需 AGC 开通 Device Security Kit（1010800004）
   * - settings.getValue：三方 app Promise 永久 pending
   * - debug 签名自证：release 上架后失效
   * → gate 恒 'ok'（放行），两条件以"温馨提示"展示在总览页（用户自行确认）。
   * 保留 EnvGate 架构：后续检测通道可用时恢复 checkDeveloperMode 即可。
   */
  static async check(ctx: common.Context, force: boolean = false): Promise<GateState> {
    const state: GateState = { developerMode: true, localPlugin: true, gate: 'ok' };
    DevGateService.state = state;
    AppStorage.setOrCreate('env_gate', 'ok');
    AppStorage.setOrCreate('env_gate_ready', true);
    return state;
  }

  private static gateOf(dev: boolean, plugin: boolean): EnvGate {
    if (dev && plugin) { return 'ok'; }
    if (!dev && !plugin) { return 'blocked_both'; }
    return dev ? 'blocked_plugin' : 'blocked_dev';
  }

  /** 开发者模式：safetyDetect.queryRiskFactors（API 26+，本地因子，无需权限）
   *  API 26 SDK 原生声明直接调用；低 API 设备抛异常 → fail-closed
   *  （误拦截比误放行安全）。 */
  // 检测通道存档（2026-11-16 实测全不可用——恢复条件见 check() 注释）
  private static async checkDeveloperMode(): Promise<boolean> {
    return true;
  }

  // ─── 设置深链（真机对照位：设置 ability 名与参数形态以实测为准） ───

  /**
   * 拉起设置 > 关于本机（开发者模式开启路径：连点 7 次版本号）。
   * 官方 API：settings.openAboutDeviceSettingsPage（PC 26+，无权限要求）。
   */
  static openDeveloperModeSettings(ctx: common.Context): void {
    try {
      settings.openAboutDeviceSettingsPage(ctx);
      return;
    } catch (e) {
      Logger.error(TAG, `openAboutDeviceSettingsPage failed: ${JSON.stringify(e)}`);
    }
    DevGateService.openSettingsHome(ctx);
  }

  /**
   * 拉起设置 > 隐私和安全（非应用市场扩展程序开关路径）。
   * 实测命令：aa start -a com.huawei.hmos.settings.MainAbility
   *   -b com.huawei.hmos.settings -U "privacy_settings"（用户 2026-11-16 确认）
   * → 显式 Want（bundle+ability+uri 三要素齐全，避免隐式路由弹应用选择器）。
   * 失败兜底拉设置主页，用户自行进 隐私和安全 > 高级。
   */
  static openLocalPluginSettings(ctx: common.Context): void {
    const actx: common.UIAbilityContext = ctx as common.UIAbilityContext;
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'privacy_settings',
    };
    actx.startAbility(want).catch((e: BusinessError) => {
      Logger.error(TAG, `privacy_settings deep link failed: ${e.code} ${e.message}（fallback 主页）`);
      DevGateService.openSettingsHome(ctx);
    });
  }

  /** 兜底：拉设置主页（PC 设置应用实体：com.huawei.hmos.settings/MainAbility） */
  private static openSettingsHome(ctx: common.Context): void {
    const actx: common.UIAbilityContext = ctx as common.UIAbilityContext;
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
    };
    actx.startAbility(want).catch((e: BusinessError) => {
      Logger.error(TAG, `open settings home failed: ${e.code} ${e.message}`);
    });
  }
}
