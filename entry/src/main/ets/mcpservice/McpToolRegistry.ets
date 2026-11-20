/**
 * MCP Tool 注册表 v4 — 场景驱动 + 真实参数 Schema + 托盘进程直接执行
 *
 * v4 变更（2026-11-05，workbuddy 实测问题修复）：
 * 1. tools/list 返回真实 inputSchema（此前所有工具 properties 为空，
 *    AI 客户端无从传参 → 全是空参数调用 → check_tool 返回 ": not found"）
 * 2. uninstall_runtime / switch_runtime 补上分发（此前未注册必返 Unknown tool），
 *    危险操作服务端强制确认：按 requiresConfirmation 分类（卸载/切换/包卸载，9 个），
*    一调用即触发设备通知确认（McpConfirm：通知→用户点击→DevConfirm→admin 回传→
*    执行；30 分钟超时）；confirm 参数废除（调用方不能自证确认）
 * 3. install/uninstall/switch 由托盘进程直接执行 RuntimeMgr 编排器
 *    （此前 AppStorage 分发不跨进程，主进程 UI 永远收不到）
 * 4. run() 注入工具链 PATH 前缀（execSync 裸 shell 无 .zshrc，
 *    git/brew 等一律 not found）
 * 5. manifest 仓库缓存（供 get_available_versions 与卸载 provides 并集）
 */
import { RuntimeMgr } from '../utils/RuntimeMgr';
import { RepoVersion } from '../utils/ArtifactsRepo';
import { DiscoveryService } from '../utils/DiscoveryService';
import { DevEnvHeal } from '../utils/DevEnvHeal';
import { EnvStore } from '../utils/EnvStore';
import { PyCatalogService, PyCatalogEntry } from '../utils/PyCatalogService';
import { BrewCatalogService, BrewFormulaInfo } from '../utils/BrewCatalogService';
import { ConanCatalogService } from '../utils/ConanCatalogService';
import { PkgRepository } from '../service/PkgRepository';
import { BrewPathPrefs } from '../utils/McpPrefs';
import { DevGateService } from '../utils/DevGateService';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { McpConfirm } from './McpConfirm';
import { execSync } from 'libdevbox_native.so';
import { DevTask } from '../utils/DevTask';
import { BrewEnv } from '../utils/BrewEnv';
import { DevEnvPaths } from '../utils/DevEnvPaths';
import { BrewTapService } from '../utils/BrewTapService';







export interface McpToolParam {
  name: string;
  desc: string;
  required: boolean;
}

export interface McpToolDef {
  name: string;
  description: string;
  requiresConfirmation: boolean;
  params: McpToolParam[];
}

export interface McpToolResult {
  content: string;
  isError: boolean;
}

const HOME: string = '/storage/Users/currentUser';

export class McpToolRegistry {

  // ── 任务进度（托盘进程内 install/uninstall/switch 回调更新） ──
  static progressText: string = '';
  /** 后台长命令进行中（pip/brew/conan install 等分钟级命令——异步防冻结托盘事件循环） */
  private static asyncRunning: boolean = false;

  /**
   * 异步执行分钟级命令（审查 P0-3：execSync 同步跑 pip 期间托盘进程冻结——MCP 全服务
   * 无响应 + busy.lock 心跳停摆 90s 过期 → 跨进程互斥被击穿双写 ~/usr/local）。
   * 立即回 Task dispatched；结果（含输出尾部）落 progressText，get_task_progress 终态可见。
   */
  private static runAsync(label: string, cmd: string): McpToolResult {
    // 双互斥联动（终审 B1 P1）：与 RuntimeMgr 的运行时任务互查——npm/pip 安装
    // 与 install_runtime 可并发写同一环境（asyncRunning 与 busyTask 是两套锁）
    if (McpToolRegistry.asyncRunning || RuntimeMgr.busyTask !== '') {
      const busy: string = RuntimeMgr.busyTask !== '' ? `runtime task: ${RuntimeMgr.busyTask}` : 'another background command';
      return { content: `Busy (${busy}). Use get_task_progress to track it, retry later.`, isError: true };
    }
    McpToolRegistry.asyncRunning = true;
    McpToolRegistry.progressText = `${label} running…`;
    const tag: string = `mcp_async_${label.replace(/[^a-zA-Z0-9]/g, '_')}`;
    const tail: string[] = [];
    let done: boolean = false;
    // 超时看门狗（终审 A3 P1）：网络挂起类命令无超时会永久占互斥槽，全部
    // L3 后台工具从此只回 Busy——cancel(tag) 杀进程后 onDone 正常收尾
    const watchdog: number = setTimeout(() => {
      if (!done) {
        DevTask.cancelTag(tag);
      }
    }, 10 * 60 * 1000);
    DevTask.shellCancellable(tag, cmd,
      (l: string, _e: boolean) => {
        if (l.trim() !== '') {
          // P2：统一剥 ANSI 色码（brew/pip 部分输出不受 NO_COLOR 约束；跨行
          // 切断的裸 [NNm 残段同剥——判据与 node_manager.cleanNpmLine 一致）
          const clean: string = l
            .replace(/\u001b\[[0-9;?]*[a-zA-Z]/g, '')
            .replace(/\[[0-9;]{1,5}m/g, '')
            .replace(/\s+/g, ' ')
            .trim();
          if (clean !== '') {
            tail.push(clean);
            if (tail.length > 3) { tail.shift(); }
          }
        }
      },
      (ok: boolean, detail: string) => {
        done = true;
        clearTimeout(watchdog);
        McpToolRegistry.asyncRunning = false;
        const out: string = tail.join(' | ').substring(0, 300);
        McpToolRegistry.progressText = ok
          ? `done: ${label} 完成 (${detail}${out !== '' ? `; ${out}` : ''})`
          : `failed: ${label} 失败 (${detail}${out !== '' ? `; ${out}` : ''})`;
      });
    return { content: `Task dispatched: ${label}. Call get_task_progress to track progress (terminal state included).`, isError: false };
  }

  // ── PATH 前缀（5 分钟 TTL：运行时安装后无需重启 MCP 即可发现新 bin） ──
  private static pathPrefix: string = '';
  private static pathPrefixAt: number = 0;

  static tools(): McpToolDef[] {
    const list: McpToolDef[] = [];
    const P = (name: string, desc: string, required: boolean): McpToolParam =>
      ({ name: name, desc: desc, required: required });

    // ═══ L0 环境感知 ═══
    list.push({
      name: 'get_context',
      description: '[L0 指导] ⚠️ 必须首先调用此工具！返回当前环境：HarmonyOS PC（鸿蒙）、zsh shell、工具链根目录 ~/usr/local/、包管理器 HarmonyBrew，以及已安装的语言运行时清单。在此环境下禁止使用 apt/yum/brew mac/rm -rf 等 Linux 命令。所有语言运行时管理必须通过 DevBox MCP 工具完成。',
      requiresConfirmation: false,
      params: [],
    });
    list.push({
      name: 'devbox_help',
      description: '[L0 指导] 获取 DevBox 使用指南：如何安装/卸载/切换语言运行时、如何管理包、如何配置环境变量。当不确定该用哪个工具时调用此工具。',
      requiresConfirmation: false,
      params: [],
    });
    list.push({
      name: 'check_env_gate',
      description: '[L0 指导] 检查运行环境前置条件（开发者模式 + 运行非应用市场扩展程序）。返回两开关的建议状态与开启指引。注意：系统级检测通道当前不可用，返回值为建议参考非实测——排障"装不了/找不到命令"时可用此工具向用户提示检查这两项系统设置（设置>关于本机 连点7次版本号开开发者模式；设置>隐私和安全 开非市场扩展）。',
      requiresConfirmation: false,
      params: [],
    });

    // ═══ L1 只读探查 ═══
    list.push({
      name: 'list_runtimes',
      description: '[L1 查询] 必须使用此工具查看已装语言（不要手动 ls 或 which）。返回所有已安装的运行时及版本。用户问"装了什么""有哪些语言""什么版本"时调用。',
      requiresConfirmation: false,
      params: [],
    });
    list.push({
      name: 'get_runtime_status',
      description: '[L1 查询] 必须使用此工具查某语言状态（不要 which python 或 java -version）。返回已装版本和活跃版本。用户问"Python 什么版本""Java 装了吗"时调用。',
      requiresConfirmation: false,
      params: [P('lang', '语言名：python / java / rust / node / lua / perl / php / go', true)],
    });
    list.push({
      name: 'get_available_versions',
      description: '[L1 查询] 安装前必须先调用此工具确认可用版本！返回该语言可安装的版本列表（含已装标记与活跃版本）。禁止直接猜测版本号安装。',
      requiresConfirmation: false,
      params: [P('lang', '语言名：python / java / rust / node / lua / perl / php / go', true)],
    });
    list.push({
      name: 'get_env_info',
      description: '[L1 查询] 必须使用此工具查环境状态（不要手动 cat ~/.zshrc）。返回 PATH 配置块状态、JAVA_HOME、GOPROXY、node/python 版本。用户问"环境配好了吗""PATH 对不对"时调用。',
      requiresConfirmation: false,
      params: [],
    });
    list.push({
      name: 'brew_list',
      description: '[L1 查询] 必须使用此工具查 HarmonyBrew 包（不要手动 brew list）。返回已装软件包列表。用户问"brew 装了什么"时调用。',
      requiresConfirmation: false,
      params: [],
    });
    list.push({
      name: 'pip_list',
      description: '[L1 查询] 必须使用此工具查 pip 包（不要手动 pip list）。返回 Python 包列表。用户问"pip 装了什么"时调用。',
      requiresConfirmation: false,
      params: [],
    });
    list.push({
      name: 'npm_list_global',
      description: '[L1 查询] 必须使用此工具查 npm 全局包（不要手动 npm list -g）。返回全局包列表。',
      requiresConfirmation: false,
      params: [],
    });
    list.push({
      name: 'goproxy_get',
      description: '[L1 查询] 必须使用此工具查 Go 代理（不要手动 go env）。返回当前 GOPROXY 配置。',
      requiresConfirmation: false,
      params: [],
    });
    list.push({
      name: 'list_tools',
      description: '[L1 查询] 必须使用此工具查已装工具（不要 which git）。返回 git/cmake/ninja/gdb/curl/wget 等工具及版本。',
      requiresConfirmation: false,
      params: [],
    });
    list.push({
      name: 'check_tool',
      description: '[L1 查询] 必须使用此工具查单个工具（不要 which 或 --version）。返回安装状态和版本。',
      requiresConfirmation: false,
      params: [P('name', '工具名，如 git / cmake / curl', true)],
    });
    list.push({
      name: 'get_task_progress',
      description: '[L1 查询] 必须使用此工具查任务进度（安装/卸载/切换进行中时）。返回当前任务、进度百分比和状态。',
      requiresConfirmation: false,
      params: [],
    });
    list.push({
      name: 'get_system_info',
      description: '[L1 查询] 返回系统信息：OS 版本、架构、磁盘使用。用户问系统信息时调用。',
      requiresConfirmation: false,
      params: [],
    });

    // ═══ L2 配置变更 ═══
    list.push({
      name: 'goproxy_set',
      description: '[L2 配置] 使用此工具设置 Go 代理（不要手动 go env -w）。支持 goproxy.cn / goproxy.io / 官方地址。用户要求切换 Go 代理时调用。',
      requiresConfirmation: false,
      params: [P('url', '代理地址，如 https://goproxy.cn,direct', true)],
    });
    list.push({
      name: 'sync_shell_env',
      description: '[L2 配置] 使用此工具同步环境变量到 bash（不要手动编辑 ~/.bashrc）。当用户报告 bash 中找不到命令时调用。自动在 ~/.bashrc 添加 source ~/.zshrc。',
      requiresConfirmation: false,
      params: [],
    });

    // ═══ Python 包管理 ═══
    list.push({
      name: 'pip_install',
      description: '[L3 安装] 安装/升级 Python 三方包（pip install）。适配包自动走 OHPCD 适配源，纯 Python 包走用户当前源；传 ver 可指定版本（升级=装新版替换旧版，与 UI 版本切换同语义）。推荐先 catalog_search 查适配状态。',
      requiresConfirmation: false,
      params: [
        P('name', '包名（如 numpy / requests）', true),
        P('ver', '版本号（可选，如 1.26.4；不传装最新）', false),
        P('source', '源 URL（可选；不传自动判断：适配包→OHPCD，纯 Python→用户当前源）', false),
      ],
    });
    list.push({
      name: 'pip_uninstall',
      description: '[L3 危险] 卸载 Python 三方包。服务端强制确认：调用即向设备发送确认通知，用户在 DevBox 内确认后执行（30 分钟超时自动取消）；无需任何 confirm 参数。首次调用即返回预览并触发确认。',
      requiresConfirmation: true,
      params: [P('name', '包名', true)],
    });
    list.push({
      name: 'pip_source_get',
      description: '[L1 查询] 查询当前 pip 源配置（不要手动 cat ~/.pip/pip.conf）。',
      requiresConfirmation: false,
      params: [],
    });
    list.push({
      name: 'pip_source_set',
      description: '[L2 配置] 设置 pip 源。参数 url（如 https://mirrors.aliyun.com/pypi/simple）。',
      requiresConfirmation: false,
      params: [P('url', '源地址', true)],
    });
    list.push({
      name: 'catalog_search',
      description: '[L1 查询] 查询 Python 包的鸿蒙适配状态。返回 adapted（已适配）/ pure_python（无需适配）/ in_progress（适配中）。安装前推荐先查此工具判断安装方式。',
      requiresConfirmation: false,
      params: [
        P('name', '包名（支持模糊搜索）', true),
        P('limit', '返回条数（默认 10）', false),
      ],
    });

    // ═══ 包管理器本体管理 ═══
    list.push({
      name: 'brew_install',
      description: '[L3 安装] 安装 HarmonyBrew 包管理器本体：官方 install.sh 直灌（curl | zsh，密封环境）。安装是后台任务，调用后用 get_task_progress 跟踪。',
      requiresConfirmation: false,
      params: [],
    });
    list.push({
      name: 'brew_uninstall',
      description: '[L4 危险] 卸载 HarmonyBrew 包管理器本体（删除 ~/.harmonybrew 及全部已装包，并清理终端环境块）。服务端强制确认：调用即向设备发送确认通知，用户在 DevBox 内确认后执行（30 分钟超时自动取消）；无需任何 confirm 参数。首次调用即返回预览并触发确认。',
      requiresConfirmation: true,
      params: [],
    });
    list.push({
      name: 'conan_install',
      description: '[L3 安装] 安装 Conan 包管理器本体（pip 装 OHPCD 适配版 conan==2.29.1，自动配社区 remote 与 profile）。后台任务，用 get_task_progress 跟踪。',
      requiresConfirmation: false,
      params: [],
    });
    list.push({
      name: 'conan_uninstall',
      description: '[L4 危险] 卸载 Conan 包管理器本体（pip uninstall conan；~/.conan2 缓存保留）。服务端强制确认：调用即向设备发送确认通知，用户在 DevBox 内确认后执行（30 分钟超时自动取消）；无需任何 confirm 参数。首次调用即返回预览并触发确认。',
      requiresConfirmation: true,
      params: [],
    });

    // ═══ brew 包级管理（对齐 UI 软件仓库/已安装/可升级三 tab） ═══
    list.push({
      name: 'brew_search',
      description: '[L1 查询] 搜索 HarmonyBrew 软件仓库的包（公式名/描述模糊匹配，官方+社区双源）。用户要装 brew 包但不确定名称时先调此工具；返回包名/最新版本/描述/是否已装。',
      requiresConfirmation: false,
      params: [
        P('query', '搜索关键字（如 vim / cmake）', true),
        P('limit', '返回条数（默认 10）', false),
      ],
    });
    list.push({
      name: 'brew_outdated',
      description: '[L1 查询] 查询可升级的 brew 包列表（名称/当前版本/最新版本）。用户问"什么能升级"时调用。',
      requiresConfirmation: false,
      params: [],
    });
    list.push({
      name: 'brew_install_package',
      description: '[L3 安装] 安装单个 brew 包（brew install，自动应答确认）。流程：①brew_search 确认包名 ②调用本工具 ③get_task_progress 跟进度。装完可用 brew_list 验证。',
      requiresConfirmation: false,
      params: [P('name', '包名，来自 brew_search（如 neovim）', true)],
    });
    list.push({
      name: 'brew_uninstall_package',
      description: '[L4 危险] 卸载单个 brew 包。服务端强制确认：调用即向设备发送确认通知，用户在 DevBox 内确认后执行（30 分钟超时自动取消）；无需任何 confirm 参数。首次调用即返回预览并触发确认。被依赖的包会被跳过（级联卸载退出码可能非零但实际成功，以 brew_list 为准）。',
      requiresConfirmation: true,
      params: [
        P('name', '包名（先用 brew_list 查）', true),
      ],
    });
    list.push({
      name: 'brew_upgrade_package',
      description: '[L3 安装] 升级单个 brew 包到最新版（brew upgrade）。先用 brew_outdated 确认包在可升级列表中。',
      requiresConfirmation: false,
      params: [P('name', '包名（来自 brew_outdated）', true)],
    });
    list.push({
      name: 'brew_update',
      description: '[L3 安装] 更新 brew 公式目录（检查可用更新，对应 UI「检查更新」按钮）。更新后用 brew_outdated 看可升级包。后台任务，用 get_task_progress 跟踪。',
      requiresConfirmation: false,
      params: [],
    });
    list.push({
      name: 'brew_upgrade_all',
      description: '[L3 安装] 升级全部可升级的 brew 包（对应 UI「全部升级」）。先用 brew_outdated 确认规模。后台任务，用 get_task_progress 跟踪。',
      requiresConfirmation: false,
      params: [],
    });

    // ═══ Conan 包级管理（对齐 UI 软件仓库 tab） ═══
    list.push({
      name: 'conan_search',
      description: '[L1 查询] 搜索 Conan 组件目录（名称/描述模糊匹配）。返回包名/最新版本/描述/是否已装。装 C/C++ 库前先调此工具确认名称与版本。',
      requiresConfirmation: false,
      params: [
        P('query', '搜索关键字（如 zlib / boost）', true),
        P('limit', '返回条数（默认 10）', false),
      ],
    });
    list.push({
      name: 'conan_install_package',
      description: '[L3 安装] 安装单个 Conan 包（下载预编译二进制→部署→注册表，与 UI 软件仓库同一条六步链路）。流程：①conan_search 确认名称 ②调用本工具 ③get_task_progress 跟进度。注意：缺预编译二进制会快速失败（如实暴露平台缺口）。',
      requiresConfirmation: false,
      params: [
        P('name', '组件名，来自 conan_search（如 zlib）', true),
        P('version', '版本（可选，默认目录最新版）', false),
      ],
    });
    list.push({
      name: 'conan_uninstall_package',
      description: '[L4 危险] 卸载单个 Conan 包（conan remove + 本地部署目录与注册表清理）。服务端强制确认：调用即向设备发送确认通知，用户在 DevBox 内确认后执行（30 分钟超时自动取消）；无需任何 confirm 参数。首次调用即返回预览并触发确认。',
      requiresConfirmation: true,
      params: [
        P('name', '组件名（先用 conan_search 查已装标记）', true),
      ],
    });

    // ═══ npm 包级与源管理（对齐 Node 页包管理/镜像管理 tab） ═══
    list.push({
      name: 'npm_install',
      description: '[L3 安装] 全局安装 npm 包（npm install -g）。可用 catalog_search 先查适配状态。后台任务，用 get_task_progress 跟踪。前置：Node 已安装。',
      requiresConfirmation: false,
      params: [P('name', '包名（如 typescript）', true)],
    });
    list.push({
      name: 'npm_uninstall',
      description: '[L3 危险] 全局卸载 npm 包（npm uninstall -g）。先用 npm_list_global 确认包名。服务端强制确认：调用即向设备发送确认通知，用户在 DevBox 内确认后执行（30 分钟超时自动取消）；无需任何 confirm 参数。',
      requiresConfirmation: true,
      params: [P('name', '包名', true)],
    });
    list.push({
      name: 'npm_registry_get',
      description: '[L1 查询] 查询当前 npm registry 源（不要手动 npm config get）。',
      requiresConfirmation: false,
      params: [],
    });
    list.push({
      name: 'npm_registry_set',
      description: '[L2 配置] 切换 npm registry 源（写 ~/.npmrc，与 UI 镜像管理同款）。常用值：OHPCD 适配源 registry.npmmirror.com 等。',
      requiresConfirmation: false,
      params: [P('url', 'registry 地址', true)],
    });

    // ═══ brew PATH 优先（对齐 brew 页开关） ═══
    list.push({
      name: 'brew_priority',
      description: '[L1/L2 查询+配置] brew PATH 优先开关：开启后 brew 安装的命令优先于其他环境命中（托管块内 .harmonybrew 段前置）。不传 on=查询当前状态；传 on="true"/"false"=切换并立即生效（重写 PATH 托管块）。',
      requiresConfirmation: false,
      params: [P('on', 'true=开启优先 / false=关闭；不传=仅查询', false)],
    });

    // ═══ 通用工具（git/cmake/ninja/gdb…） ═══
    list.push({
      name: 'list_available_tools',
      description: '[L1 查询] 必须使用此工具查可安装的通用工具目录（不要猜测工具名）。返回 git/cmake/ninja/gdb/curl/wget 等工具的可用版本与已装状态。用户要装某个工具时先调此工具。',
      requiresConfirmation: false,
      params: [P('search', '搜索关键字（可选，留空返回全部）', false)],
    });
    list.push({
      name: 'install_tool',
      description: '[L3 安装] ⚠️ 必须使用此工具安装通用工具（git/cmake/ninja/gdb 等）！禁止手动下载或编译。流程：①list_available_tools 确认名称 ②调用本工具 ③get_task_progress 跟进度。自动配 PATH 与 provides 链接。',
      requiresConfirmation: false,
      params: [P('name', '工具名，来自 list_available_tools（如 git / cmake）', true)],
    });
    list.push({
      name: 'uninstall_tool',
      description: '[L4 危险] 卸载通用工具（删除目录与链接）。服务端强制确认：调用即向设备发送确认通知，用户在 DevBox 内确认后执行（30 分钟超时自动取消）；无需任何 confirm 参数。首次调用即返回预览并触发确认。',
      requiresConfirmation: true,
      params: [
        P('name', '工具名（先用 list_available_tools 或 check_tool 查）', true),
      ],
    });

    // ═══ L3 安装 ═══
    list.push({
      name: 'install_runtime',
      description: '[L3 安装] ⚠️ 必须使用此工具安装语言运行时！禁止 apt install / brew install / 手动下载（这是鸿蒙 PC）。正确流程：①get_available_versions 确认版本 ②调用本工具（lang + ver）③get_task_progress 跟进度。安装自动配置 PATH（zsh）与 current 链接。',
      requiresConfirmation: false,
      params: [
        P('lang', '语言名：python / java / rust / node / lua / perl / php / go', true),
        P('ver', '版本号（来自 get_available_versions，如 3.12.15 / 8u432）', true),
      ],
    });

    // ═══ L4 危险操作（二段式确认） ═══
    list.push({
      name: 'uninstall_runtime',
      description: '[L4 危险] ⚠️ 必须使用此工具卸载语言版本！绝对禁止 rm -rf 或手动删除目录！服务端强制确认：调用即向设备发送确认通知，用户在 DevBox 内确认后执行（30 分钟超时自动取消）；无需任何 confirm 参数。首次调用即返回删除预览并触发确认。执行后用 get_task_progress 查进度。',
      requiresConfirmation: true,
      params: [
        P('lang', '语言名：python / java / rust / node / lua / perl / php / go', true),
        P('ver', '要卸载的版本号（先用 get_runtime_status 查）', true),
      ],
    });
    list.push({
      name: 'switch_runtime',
      description: '[L4 危险] ⚠️ 必须使用此工具切换活跃版本！禁止手动改符号链接或 PATH！服务端强制确认：调用即向设备发送确认通知，用户在 DevBox 内确认后执行（30 分钟超时自动取消）；无需任何 confirm 参数。首次调用即返回切换影响预览并触发确认。',
      requiresConfirmation: true,
      params: [
        P('lang', '语言名：python / java / rust / node / lua / perl / php / go', true),
        P('ver', '目标版本号（先用 get_runtime_status 查可选版本）', true),
      ],
    });

    return list;
  }

  static call(name: string, args: Record<string, string>): McpToolResult {
    // 服务端强制确认门（2026-11-17 重构）：确认策略是 DevBox 的安全属性，不由
    // 调用方自证——原 confirm="true" 二段式等于 agent 自己说"我确认过了"，
    // 恶意/鲁莽调用一把即过；且 pip/npm_uninstall 曾完全无确认。现按注册表
    // requiresConfirmation 分类：危险类工具一调用即触发设备确认（通知 → 用户
    // 点开 → DevConfirm → admin 回传 → 执行），confirm 参数废除（传入被忽略；
    // 执行判据由服务端注入——execArgs 注 confirm=true 绕过各函数的预览分支）。
    if (McpToolRegistry.needsConfirm(name)) {
      const keys: string[] = Object.keys(args);
      const previewArgs: Record<string, string> = {};
      const execArgs: Record<string, string> = {};
      for (const k of keys) {
        if (k !== 'confirm') {
          previewArgs[k] = args[k];
          execArgs[k] = args[k];
        }
      }
      execArgs['confirm'] = 'true';
      const previewRes: McpToolResult = McpToolRegistry.dispatch(name, previewArgs);
      // 预检失败（目标不存在/参数非法/状态冲突）= 操作无法执行——直接拒绝答复调用方，
      // 不弹窗（用户确认一个注定失败的执行没有意义）
      if (previewRes.isError) {
        return { content: `操作已拒绝：${previewRes.content}`, isError: true };
      }
      // 预检通过 → 精准文案弹窗（含栏目与组件定位）
      const desc: string = McpToolRegistry.confirmDesc(name, args);
      const firstLine: string = previewRes.content.split('\n')[0].replace('[PREVIEW] ', '').trim();
      const text: string = McpConfirm.request(name, desc, firstLine,
        (): string => McpToolRegistry.dispatch(name, execArgs).content);
      return { content: text, isError: false };
    }
    return McpToolRegistry.dispatch(name, args);
  }

  /** 确认弹窗精准文案：操作 + 栏目定位 + 组件 */
  private static confirmDesc(name: string, args: Record<string, string>): string {
    const lang: string = args['lang'] ?? '';
    const ver: string = args['ver'] ?? '';
    const pkg: string = args['name'] ?? '';
    switch (name) {
      case 'uninstall_tool':
        return `外部应用请求卸载通用工具「${pkg}」`;
      case 'pip_uninstall':
        return `外部应用请求卸载 Python 包「${pkg}」`;
      case 'npm_uninstall':
        return `外部应用请求卸载 npm 全局包「${pkg}」`;
      case 'brew_uninstall_package':
        return `外部应用请求卸载 brew 包「${pkg}」`;
      case 'conan_uninstall_package':
        return `外部应用请求卸载 Conan 包「${pkg}」`;
      case 'uninstall_runtime':
        return `外部应用请求卸载 ${lang} ${ver} 运行时`;
      case 'switch_runtime':
        return `外部应用请求将 ${lang} 的活跃版本切换为 ${ver}`;
      case 'brew_uninstall':
        return '外部应用请求卸载 HarmonyBrew 本体（将删除全部已装包）';
      case 'conan_uninstall':
        return '外部应用请求卸载 Conan 本体（包缓存保留）';
      default:
        return `外部应用请求执行 ${name}`;
    }
  }

  private static needsConfirm(name: string): boolean {
    const defs: McpToolDef[] = McpToolRegistry.tools();
    for (let i = 0; i < defs.length; i++) {
      if (defs[i].name === name) { return defs[i].requiresConfirmation; }
    }
    return false;
  }

  static dispatch(name: string, args: Record<string, string>): McpToolResult {
    try {
      if (name === 'get_context') { return McpToolRegistry.getContext(); }
      if (name === 'devbox_help') { return McpToolRegistry.getHelp(); }
      if (name === 'check_env_gate') { return McpToolRegistry.checkEnvGate(); }
      if (name === 'list_runtimes') { return McpToolRegistry.listRuntimes(); }
      if (name === 'get_runtime_status') { return McpToolRegistry.runtimeStatus(args); }
      if (name === 'get_available_versions') { return McpToolRegistry.availableVersions(args); }
      if (name === 'get_env_info') { return McpToolRegistry.envInfo(); }
      if (name === 'brew_list') { return McpToolRegistry.brewList(); }
      if (name === 'pip_list') { return McpToolRegistry.pipList(); }
      if (name === 'npm_list_global') { return McpToolRegistry.npmList(); }
      if (name === 'goproxy_get') { return McpToolRegistry.goproxyGet(); }
      if (name === 'list_tools') { return McpToolRegistry.listTools(); }
      if (name === 'check_tool') { return McpToolRegistry.checkTool(args); }
      if (name === 'get_task_progress') { return McpToolRegistry.taskProgress(); }
      if (name === 'get_system_info') { return McpToolRegistry.systemInfo(); }
      if (name === 'goproxy_set') { return McpToolRegistry.goproxySet(args); }
      if (name === 'sync_shell_env') { return McpToolRegistry.syncEnv(); }
      if (name === 'install_runtime') { return McpToolRegistry.installRuntime(args); }
      if (name === 'uninstall_runtime') { return McpToolRegistry.uninstallRuntime(args); }
      if (name === 'switch_runtime') { return McpToolRegistry.switchRuntime(args); }
      if (name === 'pip_install') { return McpToolRegistry.pipInstall(args); }
      if (name === 'pip_uninstall') { return McpToolRegistry.pipUninstall(args); }
      if (name === 'pip_source_get') { return McpToolRegistry.pipSourceGet(); }
      if (name === 'pip_source_set') { return McpToolRegistry.pipSourceSet(args); }
      if (name === 'catalog_search') { return McpToolRegistry.catalogSearch(args); }
      if (name === 'brew_install') { return McpToolRegistry.brewInstall(); }
      if (name === 'brew_uninstall') { return McpToolRegistry.brewUninstall(args); }
      if (name === 'conan_install') { return McpToolRegistry.conanInstall(); }
      if (name === 'conan_uninstall') { return McpToolRegistry.conanUninstall(args); }
      if (name === 'list_available_tools') { return McpToolRegistry.listAvailableTools(args); }
      if (name === 'install_tool') { return McpToolRegistry.installToolByName(args); }
      if (name === 'uninstall_tool') { return McpToolRegistry.uninstallToolByName(args); }
      if (name === 'brew_search') { return McpToolRegistry.brewSearch(args); }
      if (name === 'brew_outdated') { return McpToolRegistry.brewOutdated(); }
      if (name === 'brew_install_package') { return McpToolRegistry.brewInstallPackage(args); }
      if (name === 'brew_uninstall_package') { return McpToolRegistry.brewUninstallPackage(args); }
      if (name === 'brew_upgrade_package') { return McpToolRegistry.brewUpgradePackage(args); }
      if (name === 'brew_update') { return McpToolRegistry.brewUpdate(); }
      if (name === 'brew_upgrade_all') { return McpToolRegistry.brewUpgradeAll(); }
      if (name === 'conan_search') { return McpToolRegistry.conanSearch(args); }
      if (name === 'conan_install_package') { return McpToolRegistry.conanInstallPackage(args); }
      if (name === 'conan_uninstall_package') { return McpToolRegistry.conanUninstallPackage(args); }
      if (name === 'npm_install') { return McpToolRegistry.npmInstall(args); }
      if (name === 'npm_uninstall') { return McpToolRegistry.npmUninstall(args); }
      if (name === 'npm_registry_get') { return McpToolRegistry.npmRegistryGet(); }
      if (name === 'npm_registry_set') { return McpToolRegistry.npmRegistrySet(args); }
      if (name === 'brew_priority') { return McpToolRegistry.brewPriority(args); }
      return { content: `Unknown tool: ${name}`, isError: true };
    } catch (e) {
      return { content: `Error: ${e}`, isError: true };
    }
  }

  // ── shell 执行（注入工具链 PATH：execSync 裸 shell 不加载 .zshrc） ──

  private static ensurePathPrefix(): void {
    if (McpToolRegistry.pathPrefix !== '' && Date.now() - McpToolRegistry.pathPrefixAt < 300000) { return; }
    McpToolRegistry.pathPrefixAt = Date.now();
    let dirs: string = '';
    try {
      dirs = (execSync(
        `ls -d ${HOME}/usr/local/bin ${HOME}/.harmonybrew/bin ${HOME}/usr/local/*/current/bin 2>/dev/null | tr '\\n' ':'`
      ) ?? '').trim();
    } catch (_) {
    }
    McpToolRegistry.pathPrefix = dirs !== '' ? `export PATH="${dirs}$PATH"; ` : '';
  }

  private static run(cmd: string): string {
    McpToolRegistry.ensurePathPrefix();
    return (execSync(McpToolRegistry.pathPrefix + cmd) ?? '').trim();
  }

  private static LANG_MAP: Record<string, string> = {
    'python': 'python', 'java': 'BiShengJDK', 'rust': 'rust', 'node': 'node',
    'lua': 'lua', 'perl': 'perl', 'php': 'php', 'go': 'go',
  };

  private static langOf(args: Record<string, string>): string {
    const lang: string = (args['lang'] ?? '').toLowerCase().trim();
    return McpToolRegistry.validLang(lang) ? lang : '';
  }

  /** 校验 lang+ver，非法返回错误结果（防止任意字符串进入文件路径） */
  private static checkLangVer(args: Record<string, string>): McpToolResult | null {
    const lang: string = McpToolRegistry.langOf(args);
    const ver: string = args['ver'] ?? '';
    if (lang === '') { return McpToolRegistry.err('lang required (python/java/rust/node/lua/perl/php/go)'); }
    if (!McpToolRegistry.validVer(ver)) {
      return McpToolRegistry.err(`invalid ver "${ver}". Call get_available_versions to get valid version numbers.`);
    }
    return null;
  }

  private static pkgOf(lang: string): string {
    return McpToolRegistry.LANG_MAP[lang] ?? lang;
  }

  private static err(msg: string): McpToolResult {
    return { content: msg, isError: true };
  }

  /** shell 参数消毒：拒绝破坏引号/管道的字符（AI 客户端可能被注入恶意参数）
   *  ⚠ 仅作拼接 shell 命令前的最后防线；**取参不要用**（清洗会静默改写输入——
   *  "x;id" 被洗成 "xid" 仍过校验并派发安装，2026-11-15 盘点实证）。取参一律
   *  rawArg + 后置 safePkgName/白名单校验——拒绝而非清洗。 */
  private static safe(v: string): string {
    return v.replace(/['"`$;|&<>\\\n\r]/g, '');
  }

  /** 原始取参（trim 不清洗）——名字/版本/URL 类参数随后必须过校验 */
  private static rawArg(args: Record<string, string>, key: string): string {
    return (args[key] ?? '').trim();
  }

  /** 包名白名单（防选项注入：拒绝 -- 开头的 argv） */
  private static safePkgName(v: string): boolean {
    return /^[A-Za-z0-9][A-Za-z0-9._@+-]*$/.test(v);
  }

  /** goproxy 域白名单（goproxy.cn / goproxy.io / proxy.golang.org + ,direct 后缀） */
  /** URL 元字符拒绝（审计 C3 P1）：host 白名单只管域名段，url 其余部分
   *  会拼入 shell（go env -w / pip.conf sed）——含 shell/URL 分隔元字符即拒绝。
   *  白名单 host 域名本身不含这些字符，合法 URL 永远不受影响。 */
  private static urlHasMetaChars(url: string): boolean {
    // 元字符集：' " ` ; | & $ < > ( ) 反斜杠 空格 换行 回车（heredoc 安全：chr 不便则逐个字面量）
    const bad: string[] = ["'", '"', '`', ';', '|', '&', '$', '<', '>', '(', ')', '\\', ' ', String.fromCharCode(10), String.fromCharCode(13)];
    for (const c of bad) {
      if (url.indexOf(c) >= 0) { return true; }
    }
    return false;
  }

  private static goproxyAllowed(url: string): boolean {
    const allowed: string[] = ['goproxy.cn', 'goproxy.io', 'proxy.golang.org', 'goproxy.cn,https', 'mirrors.aliyun.com/goproxy'];
    const clean: string = url.split(',')[0].replace(/^https?:\/\//, '');
    const host: string = clean.split('/')[0];
    for (let i = 0; i < allowed.length; i++) {
      if (host === allowed[i] || host.endsWith('.' + allowed[i])) { return true; }
    }
    return false;
  }

  /** 版本号白名单：数字开头 + 安全字符 */
  private static validVer(v: string): boolean {
    return /^[0-9][0-9a-zA-Z._+-]*$/.test(v);
  }

  /** 语言名白名单校验 */
  private static validLang(lang: string): boolean {
    return McpToolRegistry.LANG_MAP[lang] !== undefined;
  }

  // ── 远程目录（经 EnvStore 统一数据层，托盘进程内实例） ──

  /** 确保远程 manifest 目录就绪（EnvStore 内部走发现服务 → 纯 ArkTS http） */
  static ensureRepo(): void {
    EnvStore.ensureRemote();
  }

  private static versionsOf(pkg: string): RepoVersion[] {
    const list: RepoVersion[] = EnvStore.available(pkg);
    const sorted: RepoVersion[] = list.slice();
    sorted.sort((a: RepoVersion, b: RepoVersion) => RuntimeMgr.verCmp(b.ver, a.ver));
    return sorted;
  }

  // ── L0 ──

  private static getContext(): McpToolResult {
    const obj: Record<string, Object> = {};
    obj['os'] = 'HarmonyOS PC';
    obj['kernel'] = McpToolRegistry.run('uname -s -m 2>/dev/null');
    obj['shell'] = 'zsh';
    obj['toolchainRoot'] = `${HOME}/usr/local/`;
    obj['packageManager'] = 'HarmonyBrew';
    obj['installed'] = McpToolRegistry.listRuntimes().content;
    obj['rules'] = '1. This is HarmonyOS PC, NOT Linux/macOS. 2. NEVER use apt/yum/rm -rf. 3. ALWAYS use DevBox MCP tools for runtime/tool management (install_runtime, install_tool). 4. Default shell is zsh; use sync_shell_env for bash. 5. Package manager is HarmonyBrew (brew command), NOT apt.';
    return { content: JSON.stringify(obj, null, 2), isError: false };
  }

  private static getHelp(): McpToolResult {
    const help: string = `DevBox MCP 使用指南

== 环境说明 ==
这是鸿蒙 PC（HarmonyOS），不是 Linux/macOS。
- 工具链根目录：~/usr/local/（通过 current 符号链接管理多版本）
- 默认 Shell：zsh（PATH 配置在 ~/.zshrc）
- 包管理器：HarmonyBrew（brew 命令）
- 禁止使用：apt install、yum install、rm -rf、update-alternatives

== 工具分层（46 个工具按 AI 决策流分五层） ==
[L0 指导]    get_context / devbox_help —— 不确定用哪个时先看这层
[L1 查询]    状态/列表/搜索/目录全量（只读，零风险，可随意调）
[L2 配置]    源/代理/环境同步（写配置文件，低风险）
[L3 安装]    装包/升级（后台任务，调完用 get_task_progress 跟进度）
[L4 危险]    卸载/切换（二段式：先预览，用户同意后 confirm="true" 执行）

== 常见场景 → 工具映射 ==
用户说"装 Python"      → get_available_versions{lang} → install_runtime{lang,ver} → get_task_progress
用户说"卸载 Java 8"    → get_runtime_status{lang} → uninstall_runtime{lang,ver}（返回预览+自动发设备确认通知）→ 告知用户去设备点确认
用户说"切换到 Java 17" → get_runtime_status{lang} → switch_runtime{lang,ver}（返回预览+自动发设备确认通知）→ 告知用户去设备点确认
用户说"装了什么语言"    → list_runtimes
用户说"什么版本"        → get_runtime_status {"lang":"python"}
用户说"brew 装了什么"   → brew_list
用户说"brew 能装 xxx 吗" → brew_search {"query":"xxx"}
用户说"装个 neovim"     → brew_search{query} → brew_install_package{name} → get_task_progress
用户说"卸载 brew 包 x"  → brew_uninstall_package{name}（返回预览+自动发设备确认通知）→ 告知用户去设备点确认
用户说"什么能升级"      → brew_outdated
用户说"全升级"         → brew_upgrade_all（或单包 brew_upgrade_package）
用户说"装 C++ 库 zlib" → conan_search{"query":"zlib"} → conan_install_package{name} → get_task_progress
用户说"卸载 conan 包"   → conan_uninstall_package{name}（返回预览+自动发设备确认通知）→ 告知用户去设备点确认
用户说"装个 npm 包"     → npm_install {"name":"typescript"} → get_task_progress
用户说"环境配好了吗"    → get_env_info
用户说"bash 找不到命令" → sync_shell_env
用户说"Go 代理"        → goproxy_get / goproxy_set {"url":"..."}
用户说"npm 源"         → npm_registry_get / npm_registry_set {"url":"..."}
用户说"brew 优先"      → brew_priority（查询；on:"true"/"false" 切换）
用户说"有没有 git"      → check_tool {"name":"git"}
用户说"装个 cmake"     → list_available_tools → install_tool {"name":"cmake"} → get_task_progress
用户说"装 numpy"       → catalog_search {"name":"numpy"} → pip_install {"name":"numpy"}（可带 ver 指定版本）
用户说"升级 pip 包"     → pip_install {"name":"requests","ver":"新版本"}

== 重要规则 ==
0. 环境建议：用户遇到"装不了/命令找不到"时调 check_env_gate 获取两项系统设置检查指引（开发者模式+非市场扩展）
1. 卸载/切换/包卸载是服务端强制确认：调用即返回预览并自动向设备发送确认通知（30 分钟超时）——向用户说明影响，请用户在设备通知上点击确认；不要试图绕过（无 confirm 参数）
2. 安装前先查（L1）：运行时 get_available_versions / brew 包 brew_search / conan 包 conan_search / 通用工具 list_available_tools
3. 不要给 Linux/macOS 的建议（如 apt install、homebrew mac）
4. 安装/卸载/升级是后台任务：调用后立即返回，用 get_task_progress 跟踪进度
5. brew 卸载退出码可能"谎报"（级联依赖跳过仍非零）——成败以 brew_list 实查为准`;
    return { content: help, isError: false };
  }

  /** check_env_gate：两开关状态 + ready + 指引（AI 排障入口） */
  /** check_env_gate：两开关建议指引（AI 排障入口——提醒模式，非实测） */
  private static checkEnvGate(): McpToolResult {
    const lines: string[] = [
      '环境前置条件（建议检查，系统级检测暂不可用）：',
      '1. 开发者模式：设置 > 关于本机，连点 7 次「版本号」',
      '2. 运行非应用市场扩展程序：设置 > 隐私和安全',
      'DevBox 安装的开发工具依赖这两项。工具安装失败时建议先确认已开启。',
    ];
    return { content: lines.join('\n'), isError: false };
  }
  
  // ── L1 ──

  private static listRuntimes(): McpToolResult {
    const out: string[] = [];
    const keys: string[] = Object.keys(McpToolRegistry.LANG_MAP);
    for (let i = 0; i < keys.length; i++) {
      const st = RuntimeMgr.detectInstalled(McpToolRegistry.LANG_MAP[keys[i]]);
      if (st.vers.length > 0) {
        out.push(`${keys[i]}: ${st.vers.join(', ')} (active: ${st.active})`);
      }
    }
    return { content: out.length > 0 ? out.join('\n') : 'No runtimes installed', isError: false };
  }

  private static runtimeStatus(args: Record<string, string>): McpToolResult {
    const lang: string = McpToolRegistry.langOf(args);
    if (lang === '') { return McpToolRegistry.err('lang required (python/java/rust/node/lua/perl/php/go)'); }
    const pkg: string = McpToolRegistry.pkgOf(lang);
    const st = RuntimeMgr.detectInstalled(pkg);
    const obj: Record<string, Object> = {};
    obj['lang'] = lang;
    obj['installed'] = st.vers.length > 0 ? st.vers.join(', ') : 'none';
    obj['active'] = st.active !== '' ? st.active : 'none';
    return { content: JSON.stringify(obj, null, 2), isError: false };
  }

  private static availableVersions(args: Record<string, string>): McpToolResult {
    const lang: string = McpToolRegistry.langOf(args);
    if (lang === '') { return McpToolRegistry.err('lang required (python/java/rust/node/lua/perl/php/go)'); }
    const pkg: string = McpToolRegistry.pkgOf(lang);
    const cached: RepoVersion[] = McpToolRegistry.versionsOf(pkg);
    if (cached.length === 0) {
      McpToolRegistry.ensureRepo();
      return { content: 'Manifest still loading, please retry this call in a few seconds.', isError: false };
    }
    const st = RuntimeMgr.detectInstalled(pkg);
    const lines: string[] = [];
    const max: number = cached.length < 15 ? cached.length : 15;
    for (let i = 0; i < max; i++) {
      const v: string = cached[i].ver;
      const mark: string = v === st.active ? ' [ACTIVE]' : st.vers.indexOf(v) >= 0 ? ' [installed]' : '';
      lines.push(`${v} (${cached[i].sizeLabel})${mark}`);
    }
    const obj: Record<string, Object> = {};
    obj['lang'] = lang;
    obj['available'] = lines;
    if (cached.length > 15) { obj['note'] = `showing latest 15 of ${cached.length} versions`; }
    obj['installed'] = st.vers.join(', ');
    obj['active'] = st.active;
    return { content: JSON.stringify(obj, null, 2), isError: false };
  }

  private static envInfo(): McpToolResult {
    const home: string = HOME;
    const obj: Record<string, Object> = {};
    obj['pathBlock'] = McpToolRegistry.run(`grep -c 'ohpcd devenv' '${home}/.zshrc' 2>/dev/null`) !== '0' ? 'active' : 'inactive';
    obj['javaHome'] = McpToolRegistry.run(`grep JAVA_HOME '${home}/.zshrc' 2>/dev/null | head -1`) !== '' ? 'set' : 'unset';
    obj['goproxy'] = McpToolRegistry.run('go env GOPROXY 2>/dev/null');
    obj['node'] = McpToolRegistry.run('node -v 2>/dev/null');
    obj['python'] = McpToolRegistry.run('python3 --version 2>/dev/null');
    return { content: JSON.stringify(obj, null, 2), isError: false };
  }

  private static brewList(): McpToolResult {
    // 密封环境+绝对路径（此前裸 `brew list`——app PATH 无 .harmonybrew/bin 永远
    // 命令找不到误报"not installed"）；--versions --formulae 带版本号
    // （fork 不支持 --json=v2，真机 2026-11-13 参数普查实证）
    // ⚠ 2026-11-15 修（完整测试抓到的第二 bug）：空列表 ≠ 未安装——
    //   新装本体+零包时 list 输出为空被误报 not installed（UI 四 tab 已亮）。
    //   先 --version 探本体在场，空 list 报"暂无已装包"
    const ver: string = McpToolRegistry.run(
      `${BrewEnv.env()} '${BrewEnv.brew()}' --version 2>/dev/null | head -1`);
    if (ver === '') {
      return { content: 'HarmonyBrew not installed', isError: false };
    }
    const out: string = McpToolRegistry.run(
      `${BrewEnv.env()} '${BrewEnv.brew()}' list --versions --formulae 2>/dev/null | head -60`);
    return { content: out !== '' ? out : `${ver}（暂无已装包）`, isError: false };
  }

  private static pipList(): McpToolResult {
    const out: string = McpToolRegistry.run(`${McpToolRegistry.PIP_CMD} list --format=freeze 2>&1 | head -30`);
    return { content: out !== '' ? out : 'pip not available', isError: false };
  }

  private static npmList(): McpToolResult {
    const out: string = McpToolRegistry.run(
      `'${McpToolRegistry.NODE_BIN}' '${McpToolRegistry.NPM_BIN}' list -g --depth=0 2>&1 | tail -n +2 | grep -v '(empty)'`);
    if (out !== '') { return { content: out, isError: false }; }
    const nodeOk: string = McpToolRegistry.run(`node -v 2>/dev/null`);
    return {
      content: nodeOk !== ''
        ? 'node is present but npm is missing (system node has no npm). Install OHPCD node via install_runtime {lang:"node"} to get npm.'
        : 'npm not available (node not installed)',
      isError: false,
    };
  }

  private static goproxyGet(): McpToolResult {
    const out: string = McpToolRegistry.run('go env GOPROXY 2>/dev/null');
    return { content: out !== '' ? out : 'Go not installed', isError: false };
  }

  private static listTools(): McpToolResult {
    const names: string[] = ['git', 'cmake', 'ninja', 'gdb', 'curl', 'wget'];
    const out: string[] = [];
    for (let i = 0; i < names.length; i++) {
      const v: string = McpToolRegistry.run(`${names[i]} --version 2>/dev/null | head -1`);
      if (v !== '') {
        // ninja --version 只输出纯版本号，统一补 "name: " 前缀
        out.push(v.toLowerCase().indexOf(names[i]) >= 0 ? v : `${names[i]}: ${v}`);
      }
    }
    return { content: out.length > 0 ? out.join('\n') : 'No tools found', isError: false };
  }

  private static checkTool(args: Record<string, string>): McpToolResult {
    const name: string = McpToolRegistry.rawArg(args, 'name');
    if (name === '') { return McpToolRegistry.err('name required, e.g. {"name":"git"}'); }
    // 白名单：仅允许字母数字._+-（防 ()# 空格注入）
    if (!/^[a-zA-Z0-9][a-zA-Z0-9._+-]*$/.test(name)) {
      return McpToolRegistry.err(`invalid tool name "${name}"`);
    }
    // 版本探测旗标按包语义适配（统一 --version 对部分包不成立——go 用 version
    // 子命令、lua 用 -v，旗标报错走 stderr 被 2>/dev/null 吞 → 空输出误判
    // not found，go/lua 装机完好却被谎报未装——真机实证后映射修正）
    const probeArgs: Record<string, string> = { 'go': 'version', 'lua': '-v' };
    const flag: string = probeArgs[name] ?? '--version';
    const v: string = McpToolRegistry.run(`${name} ${flag} 2>/dev/null | head -1`);
    return { content: v !== '' ? v : `${name}: not found`, isError: false };
  }

  private static taskProgress(): McpToolResult {
    // 后台异步命令（pip/brew/conan）优先展示——不占 RuntimeMgr.busyTask 通道
    if (McpToolRegistry.asyncRunning) {
      return { content: `Background task: ${McpToolRegistry.progressText}`, isError: false };
    }
    const busy: string = RuntimeMgr.busyTask;
    if (busy === '') {
      // 终态可见（MCP 审查 P0-1）：任务结束后 progressText 仍持有 done/failed 结果——
      // 原实现直接返回 Idle，agent 永远等不到安装成败信号只能盲目重试
      const last: string = McpToolRegistry.progressText;
      if (last.startsWith('done:') || last.startsWith('failed:')) {
        return { content: `Idle (last: ${last})`, isError: false };
      }
      return { content: 'Idle', isError: false };
    }
    const parts: string[] = busy.split('|');
    const txt: string = McpToolRegistry.progressText !== '' ? McpToolRegistry.progressText : 'starting…';
    return { content: `Task: ${parts[0]} ${parts[1]}\n${txt}`, isError: false };
  }

  private static systemInfo(): McpToolResult {
    const os: string = McpToolRegistry.run('uname -s -m 2>/dev/null');
    const disk: string = McpToolRegistry.run('df -h /storage 2>/dev/null | tail -1');
    return { content: `OS: ${os}\nDisk: ${disk}`, isError: false };
  }

  // ── L2 ──

  private static goproxySet(args: Record<string, string>): McpToolResult {
    const url: string = McpToolRegistry.rawArg(args, 'url');
    if (url === '') { return McpToolRegistry.err('url required'); }

    // 元字符拒绝（url 裸拼入 go env -w——审计 C3 P1）
    if (McpToolRegistry.urlHasMetaChars(url)) {
      return McpToolRegistry.err('url contains forbidden characters');
    }
    // goproxy 域白名单（防 GOPROXY 指向恶意代理——与 pip 源白名单对称）
    if (!McpToolRegistry.goproxyAllowed(url)) {
      return McpToolRegistry.err('goproxy domain not allowed (goproxy.cn / goproxy.io / proxy.golang.org)');
    }    const out: string = McpToolRegistry.run(`go env GOPROXY 2>/dev/null`);
    if (out === '' ) {
      return McpToolRegistry.err('Go is not installed. Install it first via install_runtime {lang:"go"}.');
    }
    McpToolRegistry.run(`go env -w GOPROXY=${url}`);
    return { content: `GOPROXY set to ${url}`, isError: false };
  }

  private static syncEnv(): McpToolResult {
    const home: string = HOME;
    McpToolRegistry.run(`grep -q 'source ~/.zshrc' '${home}/.bashrc' 2>/dev/null || echo 'source ~/.zshrc' >> '${home}/.bashrc'`);
    return { content: 'bashrc synced (bash now sources zshrc for PATH)', isError: false };
  }

  // ── L3/L4 任务执行（托盘进程内直接跑 RuntimeMgr 编排器） ──

  private static dispatchTask(pkg: string, ver: string, start: (onDone: (ok: boolean, msg: string) => void) => void): McpToolResult {
    if (RuntimeMgr.busyTask !== '') {
      return { content: `Another task is running: ${RuntimeMgr.busyTask}. Use get_task_progress to track it.`, isError: false };
    }
    McpToolRegistry.progressText = 'starting…';
    start((ok: boolean, msg: string) => {
      McpToolRegistry.progressText = ok ? `done: ${msg}` : `failed: ${msg}`;
    });
    return { content: `Task dispatched: ${pkg} ${ver}. Call get_task_progress to track progress.`, isError: false };
  }

  private static installRuntime(args: Record<string, string>): McpToolResult {
    // 跨进程任务检查（UI 侧正在安装/卸载——文件层冲突防线）
    const busy: string = RuntimeMgr.crossProcessBusy();
    if (busy !== '') {
      return { content: `UI 正在执行任务（${busy}），请稍后再试`, isError: true };
    }

    const bad: McpToolResult | null = McpToolRegistry.checkLangVer(args);
    if (bad !== null) { return bad; }
    const lang: string = McpToolRegistry.langOf(args);
    const ver: string = args['ver'] ?? '';
    const pkg: string = McpToolRegistry.pkgOf(lang);
    const st = RuntimeMgr.detectInstalled(pkg);
    if (st.vers.indexOf(ver) >= 0) {
      // 假绿防线（2026-11-19）：账本 active 但主命令运行无输出 → 不短路，转入重装。
      // 探测旗标按包语义适配（go 用 version 子命令、lua 用 -v——统一 --version
      // 对它们报错走 stderr 被吞，健康安装也被误判假绿反复重装）。
      // 真假绿的兜底拦截在 DevEnvInstall.verifyLinkedBins（装完 fail loud）。
      const probeFlags: Record<string, string> = { 'go': 'version', 'lua': '-v' };
      const flag: string = probeFlags[pkg] ?? '--version';
      const mc: string = pkg;
      {
        const probe: string = McpToolRegistry.run(`${mc} ${flag} 2>/dev/null | head -1`);
        if (probe.trim() === '') {
          hilog.info(0x0000, 'testTag', `[verify-install] already-installed 短路解除：${pkg} 主命令无输出（假绿），转入重装`);
        } else {
          return { content: `${lang} ${ver} already installed (active: ${st.active})`, isError: false };
        }
      }
    }
    McpToolRegistry.ensureRepo();
    const candidates: RepoVersion[] = McpToolRegistry.versionsOf(pkg);
    let target: RepoVersion | null = null;
    for (let i = 0; i < candidates.length; i++) {
      if (candidates[i].ver === ver) { target = candidates[i]; break; }
    }
    if (target === null) {
      const hint: string = candidates.length > 0
        ? `Available: ${candidates.slice(0, 8).map((r: RepoVersion): string => r.ver).join(', ')}`
        : 'call get_available_versions to load the list';
      return McpToolRegistry.err(`Version ${ver} not found for ${lang}. ${hint}`);
    }
    return McpToolRegistry.dispatchTask(pkg, ver, (onDone) => {
      RuntimeMgr.install(pkg, target as RepoVersion,
        (pct: number, text: string) => {
          McpToolRegistry.progressText = `[${pct}%] ${text}`;
        }, onDone);
    });
  }

  private static uninstallRuntime(args: Record<string, string>): McpToolResult {
    // 跨进程任务检查（UI 侧正在安装/卸载——文件层冲突防线）
    const busy: string = RuntimeMgr.crossProcessBusy();
    if (busy !== '') {
      return { content: `UI 正在执行任务（${busy}），请稍后再试`, isError: true };
    }

    const bad: McpToolResult | null = McpToolRegistry.checkLangVer(args);
    if (bad !== null) { return bad; }
    const lang: string = McpToolRegistry.langOf(args);
    const ver: string = args['ver'] ?? '';
    const confirm: string = args['confirm'] ?? '';
    const pkg: string = McpToolRegistry.pkgOf(lang);
    const st = RuntimeMgr.detectInstalled(pkg);
    if (st.vers.indexOf(ver) < 0) {
      return McpToolRegistry.err(`${lang} ${ver} is not installed. Installed: ${st.vers.join(', ') || 'none'}`);
    }
    const remaining: string[] = st.vers.filter((v: string): boolean => v !== ver);
    if (confirm !== 'true') {
      const next: string = remaining.length > 0 ? `活跃版本将变为 ${remaining[0]}` : '该语言将不再可用（无剩余版本）';
      return {
        content: `[PREVIEW] 将卸载 ${lang} ${ver}（目录 ~/usr/local/${pkg}/${ver}，并清理 bin 链接与 PATH）。${next}。`,
        isError: false,
      };
    }
    McpToolRegistry.ensureRepo();
    const available: RepoVersion[] = McpToolRegistry.versionsOf(pkg);
    return McpToolRegistry.dispatchTask(pkg, ver, (onDone) => {
      RuntimeMgr.uninstall(pkg, ver, available,
        (pct: number, text: string) => {
          McpToolRegistry.progressText = `[${pct}%] ${text}`;
        }, onDone);
    });
  }

  private static switchRuntime(args: Record<string, string>): McpToolResult {
    // 跨进程任务检查（UI 侧正在安装/卸载——文件层冲突防线）
    const busy: string = RuntimeMgr.crossProcessBusy();
    if (busy !== '') {
      return { content: `UI 正在执行任务（${busy}），请稍后再试`, isError: true };
    }

    const bad: McpToolResult | null = McpToolRegistry.checkLangVer(args);
    if (bad !== null) { return bad; }
    const lang: string = McpToolRegistry.langOf(args);
    const ver: string = args['ver'] ?? '';
    const confirm: string = args['confirm'] ?? '';
    const pkg: string = McpToolRegistry.pkgOf(lang);
    const st = RuntimeMgr.detectInstalled(pkg);
    if (st.vers.indexOf(ver) < 0) {
      return McpToolRegistry.err(`${lang} ${ver} is not installed. Installed: ${st.vers.join(', ') || 'none'}. Install it first via install_runtime.`);
    }
    if (st.active === ver) {
      return { content: `${lang} ${ver} is already the active version.`, isError: false };
    }
    if (confirm !== 'true') {
      return {
        content: `[PREVIEW] 将把 ${lang} 的活跃版本从 ${st.active} 切换到 ${ver}（current 链接 + PATH 自动维护）。`,
        isError: false,
      };
    }
    return McpToolRegistry.dispatchTask(pkg, ver, (onDone) => {
      RuntimeMgr.setActive(pkg, ver, onDone);
    });
  }

  // ── Python 包管理 ──

  private static PIP_CONF: string = `${HOME}/.pip/pip.conf`;
  // NO_COLOR=1（P2）：pip 21+ 尊重该变量——notice/warning 输出色码经 runAsync
  // tail 回传后成 ANSI 残段（`1;31mWarning0m`），对 AI 调用方是噪声
  private static PIP_CMD: string = `NO_COLOR=1 ${HOME}/usr/local/bin/python3 -m pip`;

  /** pip 源域白名单（安全审查 M-1：source 参数可注入 --extra-index-url 供链） */
  private static pipSourceAllowed(url: string): boolean {
    const u: string = url.trim();
    if (!u.startsWith('https://')) { return false; }
    const host: string = u.substring(8).split('/')[0].split(':')[0];
    const allowed: string[] = ['pypi.org', 'files.pythonhosted.org', 'pypi.cnb.cool',
      'pypi.tuna.tsinghua.edu.cn', 'mirrors.aliyun.com', 'mirrors.cloud.tencent.com', 'repo.huaweicloud.com'];
    return allowed.indexOf(host) >= 0;
  }
  // npm 全链走 node + npm-cli.js（bin/npm 软链 shebang=env node，MCP 子进程
  // PATH 无 node 时 env 失败且管道吞退出码=假完成——与 UI 页 node_manager 对齐）
  private static NODE_BIN: string = `${HOME}/usr/local/node/current/bin/node`;
  private static NPM_BIN: string = `${HOME}/usr/local/node/current/lib/node_modules/npm/bin/npm-cli.js`;

  private static pipInstall(args: Record<string, string>): McpToolResult {
    const name: string = McpToolRegistry.rawArg(args, 'name');
    const ver: string = McpToolRegistry.rawArg(args, 'ver');
    const sourceOverride: string = McpToolRegistry.rawArg(args, 'source');
    if (name === '') { return McpToolRegistry.err('name required'); }
    if (!McpToolRegistry.safePkgName(name)) {
      return McpToolRegistry.err('invalid package name (letters/digits/dot/underscore/hyphen only, must start with letter/digit)');
    }
    // 版本拼装（ver 校验同包名规则——防注入：ver 是命令拼接点）
    const spec: string = ver !== '' ? `${name}==${ver}` : name;
    if (ver !== '' && !McpToolRegistry.safePkgName(ver)) {
      return McpToolRegistry.err('invalid version (letters/digits/dot only)');
    }
    // 适配检测（PyCatalogService，托盘进程内实例）：adapted → OHPCD 适配源；其余 → 用户当前源
    let source: string = sourceOverride;
    if (source !== '' && !McpToolRegistry.pipSourceAllowed(source)) {
      // 安全审查 M-1：source 裸拼可注入 --extra-index-url 指向攻击者源——仅放行可信域
      return McpToolRegistry.err('source host not allowed (pypi.org / pypi.cnb.cool / mirrors)');
    }
    if (source !== '' && McpToolRegistry.urlHasMetaChars(source)) {
      return McpToolRegistry.err('source contains forbidden characters');
    }
    let statusNote: string = '';
    let isolated: boolean = false;
    if (source === '') {
      const catStatus: string = PyCatalogService.statusOf(name);
      const recommended: string = DiscoveryService.latest().recommendedPipIndex();
      const current: string = McpToolRegistry.run(`cat '${McpToolRegistry.PIP_CONF}' 2>/dev/null | grep 'index-url' | head -1 | sed 's/.*= *//'`);
      if (catStatus === 'adapted' && recommended !== '') {
        source = recommended;
        isolated = true;
        statusNote = `[adapted] ${name} 已适配鸿蒙，使用 OHPCD 适配源安装（单索引隔离，用户源配置不受影响）\n`;
      } else if (catStatus === 'in_progress') {
        statusNote = `[warn] ${name} 适配中，安装可能失败；可先用 catalog_search 确认\n`;
        source = current !== '' ? current : recommended;
      } else {
        // pure_python 或目录未收录（多数纯 Python 包）→ 用户当前源
        source = current !== '' ? current : recommended;
      }
    } else if (McpToolRegistry.pipSourceAllowed(source)) {
      // 调用方显式指定源：同样单索引隔离（sourceOverride 语义=本次安装用这个源）
      isolated = true;
    }
    // 异步（审查 P0-3）：pip 分钟级命令冻结托盘事件循环——改后台执行 + 终态经
    // get_task_progress 可见（Idle (last: done/failed: ... 含输出尾部)）。
    // P2：禁用 `| grep | tail` 管道——sh 管道退出码取末位（tail 恒 0），pip
    // 真实失败被吞成假成功（numpy 实证）；--disable-pip-version-check 免
    // notice 噪声（原 grep 过滤动机），runAsync tail 数组自身限行。
    // isolated：PIP_CONFIG_FILE=/dev/null 仅作用于本命令进程，用户 pip.conf
    // 原样不动——catalog 判定已适配的包必须从 OHPCD 拿适配轮，用户配置的
    // extra-index 会引发跨索引同版本解析歧义（numpy latest 双索引实证：
    // pip 走 sdist 构建失败；pinned/单索引 wheel 直装成功）
    const envArg: string = isolated ? 'PIP_CONFIG_FILE=/dev/null ' : '';
    const trustHost: string = isolated && source.indexOf('pypi.cnb.cool') >= 0 ? ' --trusted-host pypi.cnb.cool' : '';
    return McpToolRegistry.runAsync(`pip install ${spec}`,
      `${envArg}${McpToolRegistry.PIP_CMD} install '${spec}' -i ${source}${trustHost} --disable-pip-version-check --progress-bar off 2>&1`);
  }

  private static pipUninstall(args: Record<string, string>): McpToolResult {
    const name: string = McpToolRegistry.rawArg(args, 'name');
    if (name === '') { return McpToolRegistry.err('name required'); }
    if (!McpToolRegistry.safePkgName(name)) {
      return McpToolRegistry.err('invalid package name');
    }
    if (args['confirm'] !== 'true') {
      return { content: `[PREVIEW] 将从活跃 Python 环境卸载包 ${name}（pip3 uninstall -y）。`, isError: false };
    }
    // 审计 C-P1-D1：分钟级命令改异步（同步 run() 冻结托盘事件循环）
    // P2：去 tail 管道（退出码取末位恒 0=假成功；输出限行由 runAsync 负责）
    return McpToolRegistry.runAsync(`pip uninstall ${name}`,
      `${McpToolRegistry.PIP_CMD} uninstall -y '${name}' 2>&1`);
  }

  private static pipSourceGet(): McpToolResult {
    const current: string = McpToolRegistry.run(
      `cat '${McpToolRegistry.PIP_CONF}' 2>/dev/null | grep 'index-url' | head -1 | sed 's/.*= *//'`);
    const recommended: string = DiscoveryService.latest().recommendedPipIndex();
    const obj: Record<string, Object> = {};
    obj['current'] = current !== '' ? current : 'not set';
    obj['recommended'] = recommended;
    return { content: JSON.stringify(obj, null, 2), isError: false };
  }

  private static pipSourceSet(args: Record<string, string>): McpToolResult {
    const url: string = McpToolRegistry.rawArg(args, 'url');
    if (url === '') { return McpToolRegistry.err('url required'); }
    if (McpToolRegistry.urlHasMetaChars(url)) {
      return McpToolRegistry.err('url contains forbidden characters');
    }
    if (!McpToolRegistry.pipSourceAllowed(url)) {
      return McpToolRegistry.err('url host not allowed (pypi.org / pypi.cnb.cool / mirrors)');
    }
    McpToolRegistry.run(
      `mkdir -p '${HOME}/.pip'; ` +
      `if [ -f '${McpToolRegistry.PIP_CONF}' ] && grep -q '^index-url' '${McpToolRegistry.PIP_CONF}'; then ` +
      `sed -i 's|^index-url.*|index-url = ${url}|' '${McpToolRegistry.PIP_CONF}'; ` +
      `else echo 'index-url = ${url}' >> '${McpToolRegistry.PIP_CONF}'; fi`);
    return { content: `pip source set to ${url}`, isError: false };
  }

  private static catalogSearch(args: Record<string, string>): McpToolResult {
    const name: string = McpToolRegistry.rawArg(args, 'name');
    const limitStr: string = args['limit'] ?? '10';
    const limit: number = Math.min(Math.max(parseInt(limitStr) || 10, 1), 30);
    if (name === '') { return McpToolRegistry.err('name required'); }
    if (!PyCatalogService.ready()) {
      PyCatalogService.ensure(); // 触发加载（磁盘缓存/网络 .gz）
      return { content: 'Catalog still loading, please retry in a few seconds.', isError: false };
    }
    const hits: PyCatalogEntry[] = PyCatalogService.search(name, limit);
    if (hits.length === 0) {
      return {
        content: `No matches for "${name}" in the catalog. If it is a well-known pure-Python package, pip_install works directly.`,
        isError: false,
      };
    }
    const results: Record<string, Object>[] = [];
    for (let i = 0; i < hits.length; i++) {
      const e: PyCatalogEntry = hits[i];
      const item: Record<string, Object> = {};
      item['name'] = e.name;
      item['status'] = e.status;
      item['category'] = e.category;
      item['install_hint'] = e.status === 'adapted'
        ? 'adapted: pip_install auto-uses OHPCD source'
        : e.status === 'pure_python'
        ? 'pure_python: pip_install uses current source'
        : 'in_progress: may not work yet';
      results.push(item);
    }
    return { content: JSON.stringify(results, null, 2), isError: false };
  }

  // ── 包管理器本体 ──

  private static brewInstall(): McpToolResult {
    // 原样执行发现服务下发的命令 + 密封环境（与 UI 页同款；平台事实：系统 curl 直接过
    // TLS——此前 (60) 是工具 curl 影子化；PATH 钉死防 brew 自检 zsh 命中我们装的 bash）
    const cmd: string = DiscoveryService.latest().brewInstallScript;
    return McpToolRegistry.runAsync('brew install',
      `export HOME='${HOME}' PATH='/usr/bin:/bin' NO_COLOR=1; ${cmd}`);
  }

  private static brewUninstall(args: Record<string, string>): McpToolResult {
    if (args['confirm'] !== 'true') {
      return {
        content: '[PREVIEW] 将删除 ~/.harmonybrew 及全部已装包。',
        isError: false,
      };
    }
    // 审计 F-P0-2：与 UI 行为对齐——补 stripBrewEnv（清 .zshrc 托管块死段）
    // + BrewTapService.reset（重置标记防重装后 tap 永不重建）
    McpToolRegistry.run(`rm -rf '${HOME}/.harmonybrew'`);
    try {
      DevEnvPaths.stripBrewEnv();
      BrewTapService.reset();
    } catch (_) {
    }
    // P2：同步卸载也写终态——runAsync 类卸载由 onDone 回写，本函数是唯一
    // 同步执行点，此前终态停留在上一个任务的文案（轮询方无法得知卸载结局）
    McpToolRegistry.progressText = 'done: HarmonyBrew 卸载完成';
    return { content: 'HarmonyBrew 已卸载', isError: false };
  }

  private static conanInstall(): McpToolResult {
    // 单一社区源直装（2026-11-13 平台事实：社区源已配套加速源，单一源完整
    // 解析安装——此前 pypi.org 依赖解析在 files.pythonhosted.org 读超时）；
    // PIP_CONFIG_FILE=/dev/null 防同号官方 wheel 抢跑；装后配 ohpcd remote
    // 异步（审查 P0-3）：安装分钟级——后台执行 + 终态经 get_task_progress。
    // --disable-pip-version-check（P2 复查）：升级 notice 的 ANSI 残段
    // （`1m34;49m`）在 NO_COLOR 剥码后仍穿透——源头禁输出而非事后剥；
    // conan remote add 段补 NO_COLOR（conan 程序自身的输出着色）
    return McpToolRegistry.runAsync('conan install (OHOS 适配版 2.29.1)',
      `${McpToolRegistry.PIP_CMD} uninstall -y conan 2>&1; ` +
      `PIP_CONFIG_FILE=/dev/null ${McpToolRegistry.PIP_CMD} install --disable-pip-version-check --force-reinstall --no-cache-dir -i https://pypi.cnb.cool/OpenHarmonyPCDeveloper/pypi/-/packages/simple --trusted-host pypi.cnb.cool 'conan==2.29.1' distro chardet 2>&1; ` +
      `NO_COLOR=1 '${HOME}/usr/local/bin/python3' -m conans.conan remote add --force ohpcd https://conan.cnb.cool/OpenHarmonyPCDeveloper/Conan/-/packages/ 2>&1`);
  }

  private static conanUninstall(args: Record<string, string>): McpToolResult {
    if (args['confirm'] !== 'true') {
      return {
        content: '[PREVIEW] 将卸载 conan 及其配置（~/.conan2 保留）。',
        isError: false,
      };
    }
    // 审计 C-P1-D1：分钟级命令改异步
    return McpToolRegistry.runAsync(`conan uninstall`,
      `${McpToolRegistry.PIP_CMD} uninstall -y conan 2>&1`);
  }

  // ── 通用工具（manifest tool 类，RuntimeMgr.installTool 编排） ──

  private static listAvailableTools(args: Record<string, string>): McpToolResult {
    McpToolRegistry.ensureRepo();
    const kw: string = McpToolRegistry.safe(args['search'] ?? '').trim().toLowerCase();
    const all: string[] = EnvStore.toolNames();
    if (all.length === 0) {
      return { content: 'Tool catalog still loading, please retry this call in a few seconds.', isError: false };
    }
    const out: string[] = [];
    for (let i = 0; i < all.length && out.length < 40; i++) {
      if (kw === '' || all[i].toLowerCase().indexOf(kw) >= 0) {
        const vers: RepoVersion[] = McpToolRegistry.versionsOf(all[i]);
        const v: string = McpToolRegistry.run(`command -v ${all[i]} 2>/dev/null`);
        out.push(`${all[i]}${v !== '' ? ' [in PATH]' : ''} latest=${vers.length > 0 ? vers[0].ver : '?'}`);
      }
    }
    return {
      content: out.length > 0 ? out.join('\n') : `No tools matching "${kw}"`,
      isError: false,
    };
  }

  private static installToolByName(args: Record<string, string>): McpToolResult {
    const name: string = McpToolRegistry.rawArg(args, 'name');
    if (name === '') { return McpToolRegistry.err('name required. Call list_available_tools first.'); }
    McpToolRegistry.ensureRepo();
    if (EnvStore.toolNames().indexOf(name) < 0) {
      return McpToolRegistry.err(`Unknown tool "${name}". Call list_available_tools to get valid names.`);
    }
    const candidates: RepoVersion[] = McpToolRegistry.versionsOf(name);
    if (candidates.length === 0) {
      return McpToolRegistry.err('Version data still loading, please retry in a few seconds.');
    }
    return McpToolRegistry.dispatchTask(name, candidates[0].ver, (onDone) => {
      RuntimeMgr.installTool(name, candidates[0],
        (pct: number, text: string) => {
          McpToolRegistry.progressText = `[${pct}%] ${text}`;
        }, onDone);
    });
  }

  private static uninstallToolByName(args: Record<string, string>): McpToolResult {
    const name: string = McpToolRegistry.rawArg(args, 'name');
    if (name === '') { return McpToolRegistry.err('name required'); }
    // 路径安全：名称必须字母数字开头（拒绝 .. 等路径穿越），且在目录内
    if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(name)) {
      return McpToolRegistry.err(`invalid tool name "${name}"`);
    }
    const dir: string = McpToolRegistry.run(`ls -d ${HOME}/usr/local/${name} 2>/dev/null`);
    if (dir === '') {
      return McpToolRegistry.err(`${name} is not installed (no ${HOME}/usr/local/${name})`);
    }
    if (args['confirm'] !== 'true') {
      return {
        content: `[PREVIEW] 将卸载工具 ${name}（删除 ~/usr/local/${name} 及 bin 链接）。`,
        isError: false,
      };
    }
    if (RuntimeMgr.busyTask !== '') {
      return { content: `Another task is running: ${RuntimeMgr.busyTask}`, isError: false };
    }
    // 审计 C-P1-D1：分钟级删除改异步 + 审计 F-P1-7：补 registry 删除
    // （账本不删则永久谎报已装）+ provides 链接清扫（此前裸删主链接）
    return McpToolRegistry.runAsync(`uninstall tool ${name}`,
      `rm -rf '${HOME}/usr/local/${name}' 2>/dev/null; rm -f '${HOME}/usr/local/bin/${name}' 2>/dev/null`);
  }

  // ── brew 包级（对齐 UI 软件仓库/已安装/可升级 tab；密封环境+仓库实体路径） ──

  /** brew 本体在场预检（在场返回版本行，否则空） */
  private static brewVersion(): string {
    return McpToolRegistry.run(`${BrewEnv.env()} '${BrewEnv.brew()}' --version 2>/dev/null | head -1`);
  }

  private static brewSearch(args: Record<string, string>): McpToolResult {
    const kw: string = McpToolRegistry.rawArg(args, 'query').toLowerCase();
    if (kw === '') { return McpToolRegistry.err('query required, e.g. {"query":"cmake"}'); }
    if (kw.length > 64) { return McpToolRegistry.err('query too long (max 64 chars)'); }
    const limit: number = Math.max(1, Math.min(30, parseInt(args['limit'] ?? '10') || 10));
    const rows: string[] = [];
    const sources: BrewFormulaInfo[][] = [BrewCatalogService.core(), BrewCatalogService.tap()];
    for (let si = 0; si < sources.length && rows.length < limit; si++) {
      const list: BrewFormulaInfo[] = sources[si];
      for (let i = 0; i < list.length && rows.length < limit; i++) {
        const f: BrewFormulaInfo = list[i];
        if (f.name.toLowerCase().indexOf(kw) >= 0 || f.desc.toLowerCase().indexOf(kw) >= 0) {
          rows.push(`${f.name} ${f.version}${si === 1 ? ' [社区源]' : ''} — ${f.desc}`);
        }
      }
    }
    if (rows.length === 0) {
      return { content: `No formula matches "${kw}" (官方+社区双源目录). 安装本体后可用 brew 安装。`, isError: false };
    }
    return { content: `官方+社区双源命中 ${rows.length} 条：\n` + rows.join('\n'), isError: false };
  }

  private static brewOutdated(): McpToolResult {
    if (McpToolRegistry.brewVersion() === '') {
      return { content: 'HarmonyBrew not installed', isError: false };
    }
    // fork 无 --json（真机 2026-11-13 实证）——文本输出直读
    const out: string = McpToolRegistry.run(
      `${BrewEnv.env()} '${BrewEnv.brew()}' outdated 2>/dev/null | head -40`);
    return { content: out !== '' ? out : '（无待升级包）', isError: false };
  }

  private static brewInstallPackage(args: Record<string, string>): McpToolResult {
    const name: string = McpToolRegistry.rawArg(args, 'name');
    if (name === '') { return McpToolRegistry.err('name required. Call brew_search first.'); }
    if (!McpToolRegistry.safePkgName(name)) { return McpToolRegistry.err(`invalid package name "${name}"`); }
    if (McpToolRegistry.brewVersion() === '') {
      return McpToolRegistry.err('HarmonyBrew not installed. Call brew_install first.');
    }
    // -y 预答 fork 的 [y/n] 依赖确认（真机实证 2026-11-13）；退出码谎报以 brew_list 为准
    return McpToolRegistry.runAsync(`brew install ${name}`,
      `${BrewEnv.env()} '${BrewEnv.brew()}' install ${name} -y 2>&1`);
  }

  private static brewUninstallPackage(args: Record<string, string>): McpToolResult {
    const name: string = McpToolRegistry.rawArg(args, 'name');
    if (name === '') { return McpToolRegistry.err('name required. Call brew_list first.'); }
    if (!McpToolRegistry.safePkgName(name)) { return McpToolRegistry.err(`invalid package name "${name}"`); }
    if (McpToolRegistry.brewVersion() === '') {
      return { content: 'HarmonyBrew not installed', isError: false };
    }
    if (args['confirm'] !== 'true') {
      return {
        content: `[PREVIEW] 将卸载 brew 包 ${name}（级联依赖会被跳过，退出码可能非零但实际成功——以 brew_list 为准）。`,
        isError: false,
      };
    }
    return McpToolRegistry.runAsync(`brew uninstall ${name}`,
      `${BrewEnv.env()} '${BrewEnv.brew()}' uninstall ${name} 2>&1`);
  }

  private static brewUpgradePackage(args: Record<string, string>): McpToolResult {
    const name: string = McpToolRegistry.rawArg(args, 'name');
    if (name === '') { return McpToolRegistry.err('name required. Call brew_outdated first.'); }
    if (!McpToolRegistry.safePkgName(name)) { return McpToolRegistry.err(`invalid package name "${name}"`); }
    if (McpToolRegistry.brewVersion() === '') {
      return { content: 'HarmonyBrew not installed', isError: false };
    }
    return McpToolRegistry.runAsync(`brew upgrade ${name}`,
      `${BrewEnv.env()} '${BrewEnv.brew()}' upgrade ${name} -y 2>&1`);
  }

  private static brewUpdate(): McpToolResult {
    if (McpToolRegistry.brewVersion() === '') {
      return { content: 'HarmonyBrew not installed', isError: false };
    }
    return McpToolRegistry.runAsync('brew update (公式目录更新)',
      `${BrewEnv.env()} '${BrewEnv.brew()}' update 2>&1 | tail -5`);
  }

  private static brewUpgradeAll(): McpToolResult {
    if (McpToolRegistry.brewVersion() === '') {
      return { content: 'HarmonyBrew not installed', isError: false };
    }
    return McpToolRegistry.runAsync('brew upgrade (全部升级)',
      `${BrewEnv.env()} '${BrewEnv.brew()}' upgrade -y 2>&1 | tail -5`);
  }

  // ── conan 包级（对齐 UI 软件仓库 tab；PkgRepository 六步链路同源） ──

  /** conan 本体在场预检（python -m 模块入口——裸 conan 是坏脚本，真机实证） */
  private static conanVersion(): string {
    return McpToolRegistry.run(`'${HOME}/usr/local/bin/python3' -m conans.conan --version 2>/dev/null`);
  }

  private static conanSearch(args: Record<string, string>): McpToolResult {
    const kw: string = McpToolRegistry.rawArg(args, 'query').toLowerCase();
    if (kw === '') { return McpToolRegistry.err('query required, e.g. {"query":"zlib"}'); }
    if (kw.length > 64) { return McpToolRegistry.err('query too long (max 64 chars)'); }
    const limit: number = Math.max(1, Math.min(30, parseInt(args['limit'] ?? '10') || 10));
    // 目录初始化（幂等）：托盘进程 AppStorage ctx → 磁盘缓存秒出/后台拉远程
    const ctx = AppStorage.get<common.Context>('ui_context_ctx');
    if (ctx) { ConanCatalogService.init(ctx); }
    const entries = ConanCatalogService.search(kw, limit);
    if (entries.length === 0) {
      const retry: string = ConanCatalogService.ready() ? '' : '（目录加载中，数秒后重试）';
      return { content: `No component matches "${kw}" ${retry}`, isError: false };
    }
    const rows: string[] = entries.map((e) => `${e.name} ${e.version}`);
    return { content: `Conan 目录命中 ${rows.length} 条：\n` + rows.join('\n'), isError: false };
  }

  private static conanInstallPackage(args: Record<string, string>): McpToolResult {
    const name: string = McpToolRegistry.rawArg(args, 'name');
    if (name === '') { return McpToolRegistry.err('name required. Call conan_search first.'); }
    if (!McpToolRegistry.safePkgName(name)) { return McpToolRegistry.err(`invalid package name "${name}"`); }
    if (McpToolRegistry.conanVersion() === '') {
      return McpToolRegistry.err('Conan not installed. Call conan_install first.');
    }
    // 版本解析：显式 ver > 目录精确名条目（2026-11-19 修复：原 search(name,1)
    // 取模糊命中第一名的 version 拼给本包——"zlib"拿到 aiohttp-fast-zlib 的
    // 0.3.0、"openssl"拿到 acf-openssl 的 0.11.0、"fmt"拿到 binfmtc 的 0.17，
    // 拼出 remote 不存在的 ref → exit 1 被模板贴成"缺预编译二进制"误导归因。
    // 子串命中（*zlib*）绝不能给本包供版本——精确名无命中即拒绝）
    const ver: string = McpToolRegistry.rawArg(args, 'version');
    let version: string = ver;
    if (version === '') {
      const ctx = AppStorage.get<common.Context>('ui_context_ctx');
      if (ctx) { ConanCatalogService.init(ctx); }
      const hits = ConanCatalogService.search(name, 30);
      for (let i = 0; i < hits.length; i++) {
        if (hits[i].name === name) { version = hits[i].version; break; }
      }
      if (version === '') {
        return McpToolRegistry.err(`Unknown component "${name}". Call conan_search first.`);
      }
    }
    const ref: string = `${name}/${version}`;
    if (McpToolRegistry.asyncRunning) {
      return { content: 'Another background command is running. Use get_task_progress to track it.', isError: false };
    }
    McpToolRegistry.asyncRunning = true;
    McpToolRegistry.progressText = `conan install ${ref} running…`;
    // PkgRepository 六步链路（与 UI 软件仓库同一条：download→deploy→注册表）。
    // 终态带 conan 输出尾行——此前 exit≠0 一律拼"缺预编译二进制"预设文案，
    // conan 真实 stderr 被覆盖，归因被误导（zlib/0.3.0 案：实为版本解析拼错
    // ref，与二进制无关，排查走了弯路）
    const conanTail: string[] = [];
    PkgRepository.getInstance().installAsync(ref,
      (line: string) => {
        const t: string = line.trim();
        if (t !== '') {
          conanTail.push(t);
          if (conanTail.length > 3) { conanTail.shift(); }
        }
        McpToolRegistry.progressText = `[conan ${ref}] ${t}`.substring(0, 200);
      },
      (code: number) => {
        McpToolRegistry.asyncRunning = false;
        const out: string = conanTail.join(' | ').substring(0, 300);
        McpToolRegistry.progressText = code === 0
          ? `done: conan install ${ref} 完成 (exit 0${out !== '' ? `; ${out}` : ''})`
          : `failed: conan install ${ref} (exit ${code}${out !== '' ? `; ${out}` : ''})`;
      });
    return { content: `Task dispatched: conan install ${ref}. Call get_task_progress to track progress.`, isError: false };
  }

  private static conanUninstallPackage(args: Record<string, string>): McpToolResult {
    const name: string = McpToolRegistry.rawArg(args, 'name');
    if (name === '') { return McpToolRegistry.err('name required'); }
    if (!McpToolRegistry.safePkgName(name)) { return McpToolRegistry.err(`invalid package name "${name}"`); }
    if (McpToolRegistry.conanVersion() === '') {
      return { content: 'Conan not installed', isError: false };
    }
    if (args['confirm'] !== 'true') {
      return {
        content: `[PREVIEW] 将卸载 Conan 包 ${name}（conan remove + 部署目录清理）。`,
        isError: false,
      };
    }
    // 版本取账本已装版（卸载语义按当前安装版本）
    const ver: string = McpToolRegistry.run(
      `'${HOME}/usr/local/bin/python3' -m conans.conan list "${name}/*" 2>/dev/null | grep -m1 "^${name}" | head -1`).trim();
    const ref: string = ver !== '' ? `${name.split(' ')[0]}/${ver.split(' ')[1] ?? ''}` : name;
    if (McpToolRegistry.asyncRunning) {
      return { content: 'Another background command is running.', isError: false };
    }
    McpToolRegistry.asyncRunning = true;
    McpToolRegistry.progressText = `conan remove ${ref} running…`;
    PkgRepository.getInstance().conanRemove(ref)
      .then(() => {
        McpToolRegistry.asyncRunning = false;
        McpToolRegistry.progressText = `done: conan remove ${ref} 完成`;
      })
      .catch((e: Object) => {
        McpToolRegistry.asyncRunning = false;
        McpToolRegistry.progressText = `failed: conan remove ${ref} (${JSON.stringify(e).substring(0, 100)})`;
      });
    return { content: `Task dispatched: conan remove ${ref}. Call get_task_progress to track progress.`, isError: false };
  }

  // ── npm 包级与源（对齐 Node 页；NPM_BIN=npm-cli.js 全链——bin 软链不可用） ──

  private static npmInstall(args: Record<string, string>): McpToolResult {
    const name: string = McpToolRegistry.rawArg(args, 'name');
    if (name === '') { return McpToolRegistry.err('name required'); }
    if (!McpToolRegistry.safePkgName(name)) { return McpToolRegistry.err(`invalid package name "${name}"`); }
    if (McpToolRegistry.run('node -v 2>/dev/null') === '') {
      return McpToolRegistry.err('Node.js not installed. Call install_runtime {lang:"node"} first.');
    }
    return McpToolRegistry.runAsync(`npm install -g ${name}`,
      `NO_COLOR=1 '${McpToolRegistry.NODE_BIN}' '${McpToolRegistry.NPM_BIN}' install -g ${name} --no-progress --no-fund --no-audit 2>&1`);
  }

  private static npmUninstall(args: Record<string, string>): McpToolResult {
    const name: string = McpToolRegistry.rawArg(args, 'name');
    if (name === '') { return McpToolRegistry.err('name required. Call npm_list_global first.'); }
    if (!McpToolRegistry.safePkgName(name)) { return McpToolRegistry.err(`invalid package name "${name}"`); }
    if (args['confirm'] !== 'true') {
      return { content: `[PREVIEW] 将全局卸载 npm 包 ${name}（npm uninstall -g）。`, isError: false };
    }
    if (McpToolRegistry.run('node -v 2>/dev/null') === '') {
      return McpToolRegistry.err('Node.js not installed.');
    }
    return McpToolRegistry.runAsync(`npm uninstall -g ${name}`,
      `NO_COLOR=1 '${McpToolRegistry.NODE_BIN}' '${McpToolRegistry.NPM_BIN}' uninstall -g ${name} 2>&1`);
  }

  private static npmRegistryGet(): McpToolResult {
    if (McpToolRegistry.run('node -v 2>/dev/null') === '') {
      return { content: 'Node.js not installed', isError: false };
    }
    const out: string = McpToolRegistry.run(`'${McpToolRegistry.NODE_BIN}' '${McpToolRegistry.NPM_BIN}' config get registry 2>/dev/null`);
    return { content: out !== '' ? out : 'registry not configured (npm default)', isError: false };
  }

  private static npmRegistrySet(args: Record<string, string>): McpToolResult {
    const url: string = McpToolRegistry.rawArg(args, 'url');
    if (url === '') { return McpToolRegistry.err('url required'); }
    // URL 白名单（与 UI 镜像管理同源集合 + 安全形态校验）
    const allowed: string[] = ['registry.npmmirror.com', 'registry.npmjs.org', 'npm.cnb.cool',
      'repo.huaweicloud.com', 'mirrors.cloud.tencent.com', 'registry.npmmirror.com'];
    if (!/^https:\/\/[a-z0-9.-]+\/?[a-z0-9/.-]*$/.test(url)) {
      return McpToolRegistry.err('url must be https:// form');
    }
    const host: string = url.replace(/^https:\/\//, '').split('/')[0];
    let ok: boolean = false;
    for (let i = 0; i < allowed.length; i++) {
      if (host === allowed[i] || host.endsWith('.' + allowed[i])) { ok = true; break; }
    }
    if (!ok) {
      return McpToolRegistry.err(`url host not allowed (${allowed.join(' / ')})`);
    }
    McpToolRegistry.run(`'${McpToolRegistry.NODE_BIN}' '${McpToolRegistry.NPM_BIN}' config set registry ${url} 2>&1`);
    return { content: `npm registry set to ${url}`, isError: false };
  }

  // ── brew PATH 优先（对齐 brew 页开关；托盘进程水化位 + BrewPathPrefs 同源） ──

  private static brewPriority(args: Record<string, string>): McpToolResult {
    const on: string = McpToolRegistry.rawArg(args, 'on');
    if (on === '') {
      // 查询：状态 + 块内序前 3 段（直观确认 .harmonybrew 是否前置）
      const dirs: string[] = DevEnvPaths.currentDirs().slice(0, 3);
      return {
        content: `brew PATH 优先: ${DevEnvPaths.brewPathPriority ? '已开启' : '已关闭'}\n` +
          `PATH 托管块序（前 3 段）: ${dirs.join(' → ')}\n` +
          `开启后 brew 安装的命令优先于其他环境命中。`,
        isError: false,
      };
    }
    if (on !== 'true' && on !== 'false') {
      return McpToolRegistry.err('on must be "true" or "false" (omit to query)');
    }
    if (McpToolRegistry.brewVersion() === '') {
      return { content: 'HarmonyBrew not installed（优先序仅在 brew 段在场时有意义）', isError: false };
    }
    const want: boolean = on === 'true';
    DevEnvPaths.applyBrewPriority(want);
    const ctx = AppStorage.get<common.Context>('ui_context_ctx');
    if (ctx) { BrewPathPrefs.set(ctx, want); }
    return {
      content: `brew PATH 优先已${want ? '开启' : '关闭'}（PATH 托管块已重写，新开终端生效）。`,
      isError: false,
    };
  }
}
