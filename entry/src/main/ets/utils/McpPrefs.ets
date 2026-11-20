/**
 * McpPrefs — MCP Server 开关持久化
 *
 * 记录用户上次的 MCP 服务开关状态：
 * - 写入方：TrayAbility（实际执行启停的进程，单一写入源）
 * - 读取方：EntryAbility 启动时水化 AppStorage（UI 指示灯）；
 *           TrayAbility 启动时决定是否拉起 MCP Server
 *
 * 默认值：false（首次安装不自动启动——本地网络服务应由用户主动开启；
 * 未写入过开关的新装/清数据设备读到 false，EntryAbility 也就不拉托盘）
 */
import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';

const PREF_FILE = 'devbox_prefs';
const KEY_MCP_ENABLED = 'mcp_enabled';

export class McpPrefs {

  static async getMcpEnabled(ctx: common.Context): Promise<boolean> {
    try {
      const pref = await dataPreferences.getPreferences(ctx, PREF_FILE);
      const v = await pref.get(KEY_MCP_ENABLED, false);
      return v === true || v === 'true';
    } catch (_) {
      return false;
    }
  }

  static async setMcpEnabled(ctx: common.Context, enabled: boolean): Promise<void> {
    try {
      const pref = await dataPreferences.getPreferences(ctx, PREF_FILE);
      await pref.put(KEY_MCP_ENABLED, enabled);
      await pref.flush();
    } catch (_) {
    }
  }
}

/** brew PATH 优先（brew 页勾选项）：写入方 brew 页切换，读取方 EntryAbility 启动水化 → DevEnvPaths.brewPathPriority */
const KEY_BREW_PATH_PRIORITY = 'brew_path_priority';

export class BrewPathPrefs {

  static async get(ctx: common.Context): Promise<boolean> {
    try {
      const pref = await dataPreferences.getPreferences(ctx, PREF_FILE);
      const v = await pref.get(KEY_BREW_PATH_PRIORITY, false);
      return v === true || v === 'true';
    } catch (_) {
      return false;
    }
  }

  static async set(ctx: common.Context, on: boolean): Promise<void> {
    try {
      const pref = await dataPreferences.getPreferences(ctx, PREF_FILE);
      await pref.put(KEY_BREW_PATH_PRIORITY, on);
      await pref.flush();
    } catch (_) {
    }
  }
}
