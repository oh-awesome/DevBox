/**
 * McpConfirm —— MCP 敏感操作设备确认中心（通知 + WantAgent 拉起前台确认）
 *
 * 背景：危险工具（卸载类）原为二段式参数确认（confirm="true" 即执行）——
 * 全靠调用方（AI agent）自觉先问用户，恶意/鲁莽调用直接带 confirm 即绕过，
 * 且托盘进程（MCP 宿主）无窗口、无法弹任何对话框。
 *
 * 流程（鸿蒙后台敏感操作确认的标准形态）：
 * 1. call() 拦截 requiresConfirmation 工具的 confirm=true → 本中心登记 pending
 * 2. 发系统通知（LEVEL_HIGH slot，绑定 WantAgent：点击拉起 EntryAbility 带参）
 * 3. MCP 响应立即返回"等待设备确认"（请求-响应不等用户，结果经 get_task_progress 查询）
 * 4. 用户点通知 → 应用前台弹 DevConfirm → 经 AdminServer(:18766) 回传
 *    confirm.approve:<opId> / confirm.reject:<opId>
 * 5. TrayAbility 执行/丢弃 pending，撤通知；5 分钟未确认自动过期
 *
 * 通知授权：publish 前不单独授权检查（publish 失败即回文本引导）——
 * requestEnableNotification 需前台上下文，后台进程调不可靠；用户在系统
 * 设置开启"DevBox 通知"后自然生效。
 */
import { notificationManager } from '@kit.NotificationKit';
// ⚠️ NotificationRequest 的 contentType/slotType 字段类型来自 @ohos.notification
// （与 notificationManager 的同名枚举是两个模块——直接用 manager 枚举会跨模块
// 类型冲突，即当年搁置通知栏的 SDK 双模块坑；request 字段用本模块枚举）
import notification from '@ohos.notification';
import { wantAgent, WantAgent, common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import Logger from '../utils/Logger';
import { McpToolRegistry } from './McpToolRegistry';

const TAG = 'McpConfirm';
const BUNDLE = 'com.develop.opensource.devbox';
const EXPIRE_MS = 30 * 60 * 1000;   // 用户看完对话再回设备可能要几分钟——5 分钟实测不够（2026-11-17 首次 E2E 即撞过期）
const NOTIF_ID_BASE = 21000;

interface PendingOp {
  opId: string;
  title: string;
  body: string;
  detail: string;
  notifId: number;
  createdAt: number;
  expiresAt: number;
  executor: () => string;   // 返回执行结果文本（异常安全由调用方保证）
}

export class McpConfirm {

  /** 工具名 → 用户可读操作名（确认弹窗文案） */
  private static friendlyName(name: string): string {
    const map: Record<string, string> = {
      'uninstall_tool': '卸载通用工具',
      'uninstall_runtime': '卸载语言运行时',
      'switch_runtime': '切换活跃版本',
      'brew_uninstall': '卸载 HarmonyBrew',
      'conan_uninstall': '卸载 Conan',
      'brew_uninstall_package': '卸载 brew 包',
      'conan_uninstall_package': '卸载 Conan 包',
      'pip_uninstall': '卸载 pip 包',
      'npm_uninstall': '卸载 npm 包',
    };
    return map[name] ?? name;
  }

  private static ctx: common.Context | null = null;
  private static pending: Map<string, PendingOp> = new Map<string, PendingOp>();
  private static serial: number = 0;
  private static sweeper: number = -1;

  /** TrayAbility onCreate 注入（发通知前调用；启动过期清扫） */
  static init(ctx: common.Context): void {
    McpConfirm.ctx = ctx;
    if (McpConfirm.sweeper === -1) {
      McpConfirm.sweeper = setInterval(() => { McpConfirm.sweep(); }, 60 * 1000);
    }
  }

  /** pending 数量（诊断用） */
  static count(): number {
    return McpConfirm.pending.size;
  }

  /**
   * 登记待确认操作并发通知。返回 MCP 响应文本（不阻塞等用户）。
   * executor 为真正的执行闭包（绕过确认门直接 dispatch）。
   */
  static request(name: string, desc: string, detail: string, executor: () => string): string {
    const opId = `${Date.now()}_${McpConfirm.serial}`;
    McpConfirm.serial += 1;
    // 主行 desc（调用方构造的标准中文句）/副行 detail（预览原文或预检详情）
    const title = 'DevBox 需要您的确认';
    const body = desc;
    const op: PendingOp = {
      opId: opId,
      title: title,
      body: body,
      detail: detail,
      notifId: NOTIF_ID_BASE + (McpConfirm.serial % 1000),
      createdAt: Date.now(),
      expiresAt: Date.now() + EXPIRE_MS,
      executor: executor,
    };
    McpConfirm.pending.set(opId, op);
    McpConfirm.publish(op);
    Logger.info(TAG, `pending confirm ${name} opId=${opId}（等待设备确认）`);
    return `${detail}\n\n` +
      `该操作已提交设备确认（操作 ID ${opId}）：用户在 DevBox 内同意后才会执行。\n` +
      `通知 ${EXPIRE_MS / 60000} 分钟内有效，超时未确认自动取消。\n` +
      `请提醒用户查看设备通知，并用 get_task_progress 查询执行结果`;
  }

  /** 用户确认（admin 通道 confirm.approve:<opId>）→ 执行并撤通知 */
  static approve(opId: string): string {
    const op: PendingOp | undefined = McpConfirm.pending.get(opId);
    if (op === undefined) {
      return `操作 ${opId} 不存在或已过期`;
    }
    McpConfirm.pending.delete(opId);
    McpConfirm.cancelNotif(op.notifId);
    Logger.info(TAG, `confirm approved opId=${opId}，执行`);
    try {
      return op.executor();
    } catch (e) {
      Logger.error(TAG, `executor failed opId=${opId}: ${JSON.stringify(e)}`);
      return `执行异常：${JSON.stringify(e)}`.slice(0, 200);
    }
  }

  /** 用户拒绝（admin 通道 confirm.reject:<opId>）——写入终态文案供
   *  get_task_progress 查询（终审 P1：取消/超时盲区——轮询方此前只见 Idle） */
  static reject(opId: string): string {
    const op: PendingOp | undefined = McpConfirm.pending.get(opId);
    if (op === undefined) {
      return `操作 ${opId} 不存在或已过期`;
    }
    McpConfirm.pending.delete(opId);
    McpConfirm.cancelNotif(op.notifId);
    McpToolRegistry.progressText = `failed: 确认被用户取消（${op.title}，opId=${opId}）`;
    Logger.info(TAG, `confirm rejected opId=${opId}`);
    return `用户已取消该操作（${opId}）`;
  }

  /** 过期清扫：撤通知 + 丢弃（终态文案同步写入，与用户取消可区分） */
  private static sweep(): void {
    const now: number = Date.now();
    const dead: string[] = [];
    McpConfirm.pending.forEach((op: PendingOp, k: string) => {
      if (now > op.expiresAt) { dead.push(k); }
    });
    for (const k of dead) {
      const op: PendingOp | undefined = McpConfirm.pending.get(k);
      McpConfirm.pending.delete(k);
      if (op !== undefined) {
        McpConfirm.cancelNotif(op.notifId);
        McpToolRegistry.progressText = `failed: 确认超时自动取消（${op.title}，opId=${k}）`;
        Logger.info(TAG, `confirm expired opId=${k}`);
      }
    }
  }

  private static publish(op: PendingOp): void {
    if (McpConfirm.ctx === null) {
      Logger.error(TAG, 'ctx 未注入（init 未调用）');
      return;
    }
    try {
      // WantAgent：点击通知 → 拉起确认专用小窗（独立 entry——不唤醒主应用）
      const wantObj: Want = {
        bundleName: BUNDLE,
        abilityName: 'ConfirmAbility',
        parameters: {
          'mcp_confirm_op': op.opId,
          'mcp_confirm_title': op.title,
          'mcp_confirm_body': op.body,
          'mcp_confirm_detail': op.detail,
        },
      };
      const agentInfo: wantAgent.WantAgentInfo = {
        wants: [wantObj],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      };
      wantAgent.getWantAgent(agentInfo).then((agent: WantAgent) => {
        const req: notificationManager.NotificationRequest = {
          id: op.notifId,
          // 类别用"其他"（UNKNOWN_TYPE）——非通信类应用。级别由类别决定（API 26 的
          // addSlot 仅枚举形态，自定义 level 不可编程）；横幅/响铃由用户在
          // 设置→通知管理→DevBox 中按类别开启，MCP 开启时 requestEnableNotification 引导
          // 类别用 SOCIAL_COMMUNICATION（系统唯一对应 LEVEL_HIGH：横幅+响铃；用户已在
          // 设置开启该类别。注：类别名只是系统分组名，不影响应用定位——通知标题即我们的文案）
          slotType: notification.SlotType.SOCIAL_COMMUNICATION,
          content: {
            contentType: notification.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
            normal: {
              title: op.title,
              // 通知为纯文本（无加粗）——「」标记剥除并补空格（页面侧按标记渲染加粗）
              text: op.body.replace(/「/g, ' ').replace(/」/g, ''),
              additionalText: `点击处理 · ${EXPIRE_MS / 60000} 分钟内有效`,
            },
          },
          wantAgent: agent,
        };
        notificationManager.publish(req).then(() => {
          Logger.info(TAG, `确认通知已发布 notifId=${op.notifId}`);
        }).catch((e: BusinessError) => {
          // 常见：通知未授权（用户未开启 DevBox 通知）——pending 保留，
          // 用户开启通知后下次操作可触达；MCP 响应已提示查看设备
          Logger.error(TAG, `通知发布失败（检查 DevBox 通知授权）: ${e.code} ${e.message}`);
        });
      }).catch((e: BusinessError) => {
        Logger.error(TAG, `getWantAgent failed: ${e.code} ${e.message}`);
      });
    } catch (e) {
      Logger.error(TAG, `publish 异常: ${JSON.stringify(e)}`);
    }
  }

  private static cancelNotif(notifId: number): void {
    try {
      notificationManager.cancel(notifId).catch((_e: BusinessError) => {});
    } catch (_) {
    }
  }
}
