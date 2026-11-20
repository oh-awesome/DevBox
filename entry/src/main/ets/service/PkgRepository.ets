/**
 * 包管理器数据源服务 (v4 — Conan 代理脚本前端)
 *
 * 所有 conan 操作直接执行 conan 命令（PATH 注入），输出在 ArkTS 中解析；
 * 由 python ELF 执行 (exec-allowed 目录)，proxy/conan 脚本只被读取 (绕过 noexec)。
 * 对 detail/ready 等需多次 conan 调用的操作，proxy 在进程内复用 sys.modules，
 * 只冷启动一次 Python 解释器。
 */
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { PkgItem, PkgDetail, PkgLoadState, PkgRequire, PkgTestPhase } from '../model/PkgModels';
import { DevTask } from '../utils/DevTask';
import { execAsync as nativeExecAsync, execSync as nativeExecSync, cancel as nativeCancel } from 'libdevbox_native.so';
import { DiscoveryService } from '../utils/DiscoveryService';
import { ConanCatalogService, ConanCatalogEntry } from '../utils/ConanCatalogService';




import Logger from '../utils/Logger';






const TAG = 'PkgRepository';
const CACHE_DIR = 'pkg_cache';
const INDEX_CACHE = 'conan_index.json';

/** CNB Conan 制品仓 REST API 基础路径 (仅 getConanDownloadUrl 使用，Phase 2 后移除)——发现服务驱动 */
const conanBase = (): string => DiscoveryService.latest().conanRemote;

/** conan 远程仓别名 (DevBox 本地配置，与 CONAN_BUNDLE.md 一致) */
const HOME = '/storage/Users/currentUser';
const CONAN_REMOTE = 'ohpcd';

const conanMissingHint = (raw: string): string => {
  const t: string = raw.trim();
  if (t === '' || t.indexOf('not found') >= 0 || t.indexOf('inaccessible') >= 0) {
    return 'conan 未安装（可在 Python 页安装 conan，或先浏览 CDN 目录）';
  }
  return `conan 环境检查失败: ${t.slice(-200)}`;
};


/** 加载结果 */
class LoadResult {
  state: PkgLoadState = PkgLoadState.IDLE;
  count: number = 0;
  message: string = '';
}

/** Conan 搜索结果中单条引用的解析结构: "name/version@user/channel" */
class ConanRef {
  name: string = '';
  version: string = '';
  user: string = '';
  channel: string = '';
}

export class PkgRepository {
  /** 全局单例 (跨页面共享 cachedPackages / conan 环境) */
  private static instance: PkgRepository | null = null;

  static getInstance(): PkgRepository {
    if (!PkgRepository.instance) {
      PkgRepository.instance = new PkgRepository();
    }
    return PkgRepository.instance;
  }

  private context: Context | null = null;
  private cachedPackages: PkgItem[] = [];
  private currentInstallHandle: object | null = null;
  /** 最近一次 conan 环境检查的失败原因 (UI 可读取展示) */
  lastConanError: string = '';

  setContext(ctx: Context): void {
    this.context = ctx;
    // CDN 目录（无 conan/python 本体时的浏览兜底）
    ConanCatalogService.init(ctx);
    ConanCatalogService.ensure();
  }

  getPackages(): PkgItem[] {
    return this.cachedPackages;
  }

  // ─── conan 直连基础设施（无 python 代理；conan 在 PATH 中） ───

  /** shell 单引号包裹 (参数安全转义: ' -> '\'' ，refs 含 / @ 不受影响) */
  private quote(arg: string): string {
    return "'" + arg.replace(/'/g, "'\\''") + "'";
  }

  /**
   * 异步执行 conan 命令并收集全部输出（DevTask.shell 有 PATH 注入且句柄防 GC）。
   */
  private conanRunAsync(args: string): Promise<string> {
    return new Promise<string>((resolve: (out: string) => void) => {
      let out: string = '';
      // python -m 模块入口：绕开 /data/app/bin/conan 坏脚本（Permission denied——真机实证）
      // NO_COLOR=1：禁用 conan 彩色输出——ANSI 转义码嵌入 JSON 会让 JSON.parse
      // 失败（真机实证 2026-11-14：conan list/show 的 --format=json 输出带
      // \x1b[35m 等色码 → SyntaxError: Unexpected Text in JSON → 详情全灭）
      DevTask.shell(`NO_COLOR=1 '${HOME}/usr/local/bin/python3' -m conans.conan ${args} 2>&1`,
        (line: string, _e: boolean) => { out += line + '\n'; },
        (_ok: boolean, _detail: string) => { resolve(out); });
    });
  }

  /** 执行 conan 命令并解析输出中的 JSON 对象（conan 日志可能混入 warning 行） */
  private async conanJsonAsync(args: string): Promise<Object | null> {
    const out: string = await this.conanRunAsync(args);
    return this.extractJson(out);
  }

  /** 二进制兼容矩阵（conan list "ref:*" -r ohpcd --format=json）——哪些
   *  settings/options 组合在远端有预编译包（Conan 2.x 官方推荐通道，
   *  取代旧 conan search --json。settings 含 os/arch/compiler/build_type/
   *  cppstd 等；options 含 shared/fPIC 等配方级选项） */
  async getBinaryMatrix(name: string, version: string): Promise<Record<string, string>[]> {
    try {
      const ref = `${name}/${version}`;
      const out: Object | null = await this.conanJsonAsync(
        `list ${this.quote(`${ref}:*`)} -r ${CONAN_REMOTE} --format=json`);
      if (out === null) { return []; }
      // 解析嵌套：{ "ref#rrev": { "revisions": { "rrev": { "packages":
      //  { "pkg_id": { "info": { "settings": {...}, "options": {...} } } } } } }
      const outer: Record<string, Object> = out as Record<string, Object>;
      const rows: Record<string, string>[] = [];
      for (const refKey of Object.keys(outer)) {
        const revisions: Record<string, Object> | undefined =
          (outer[refKey] as Record<string, Object>)['revisions'] as Record<string, Object> | undefined;
        if (revisions === undefined) { continue; }
        for (const revKey of Object.keys(revisions)) {
          const packages: Record<string, Object> | undefined =
            (revisions[revKey] as Record<string, Object>)['packages'] as Record<string, Object> | undefined;
          if (packages === undefined) { continue; }
          for (const pkgId of Object.keys(packages)) {
            const info: Record<string, Object> | undefined =
              (packages[pkgId] as Record<string, Object>)['info'] as Record<string, Object> | undefined;
            if (info === undefined) { continue; }
            const settings: Record<string, Object> | undefined =
              info['settings'] as Record<string, Object> | undefined;
            const options: Record<string, Object> | undefined =
              info['options'] as Record<string, Object> | undefined;
            const row: Record<string, string> = {};
            if (settings !== undefined) {
              for (const k of Object.keys(settings)) {
                row[k] = `${settings[k]}`;
              }
            }
            if (options !== undefined) {
              for (const k of Object.keys(options)) {
                row[k] = `${options[k]}`;
              }
            }
            row['pkgId'] = pkgId;
            rows.push(row);
          }
        }
      }
      Logger.info(TAG, `getBinaryMatrix ${ref}: ${rows.length} binaries`);
      return rows;
    } catch (e) {
      Logger.error(TAG, `getBinaryMatrix failed for ${name}/${version}: ${e}`);
      return [];
    }
  }

  /**
   * 确保本地 conan 环境就绪：conan --version + ohpcd remote 存在（缺则自动添加）。
   * 失败原因写入 this.lastConanError (UI 可读取展示)。
   */
  async ensureConanReadyAsync(): Promise<boolean> {
    this.lastConanError = '';
    const verOut: string = await this.conanRunAsync('--version');
    const verMatch: RegExpMatchArray | null = verOut.match(/Conan version (\S+)/);
    if (verMatch === null) {
      this.lastConanError = conanMissingHint(verOut);
      Logger.error(TAG, `ensureConanReady failed: ${this.lastConanError}`);
      return false;
    }
    // remote 检查 + 缺则添加（幂等）
    const remotes: string = await this.conanRunAsync('remote list');
    if (remotes.indexOf(CONAN_REMOTE) < 0) {
      await this.conanRunAsync(`remote add ${CONAN_REMOTE} ${conanBase()} --force`);
      Logger.info(TAG, `conan remote added: ${CONAN_REMOTE} -> ${conanBase()}`);
    }
    // ⚠ charset 修复（2026-11-14 真机实证根因）：社区 charset_normalizer-ohos 轮
    // 的 .so 依赖 libpython3.12.so.1.0（静态 python 无此库）→ import 失败 →
    // requests 无可用字符检测 → conan show/install 返回空（321 字符纯告警，
    // 零 conan 输出）。检测 chardet（纯 python 零 ABI 风险）缺则从社区源补装
    const charsetOut: string = (nativeExecSync(
      `'${HOME}/usr/local/bin/python3' -c 'import chardet' 2>&1`) ?? '');
    if (charsetOut.indexOf('ModuleNotFoundError') >= 0 || charsetOut.indexOf('ImportError') >= 0) {
      Logger.warn(TAG, 'chardet missing (conan show returns empty), installing...');
      const chardetOut: string = (nativeExecSync(
        `NO_COLOR=1 PIP_CONFIG_FILE=/dev/null '${HOME}/usr/local/bin/python3' -m pip install ` +
        `-i https://pypi.cnb.cool/OpenHarmonyPCDeveloper/pypi/-/packages/simple ` +
        `--trusted-host pypi.cnb.cool chardet 2>&1`) ?? '');
      Logger.info(TAG, `chardet install: ${chardetOut.trim().substring(0, 200)}`);
    }
    // 默认 profile 缺则写入生态权威 ohos-aarch64（build_in_harmonyos ci/conan/profiles 同款）：
    // os=OHOS 是适配版 conan 的枚举（官方版无此值→Invalid setting）；package_id 与 CI
    // 产物对齐才能命中预编译二进制。buildenv 的 hnp 工具链路径用于源码构建（设备存在即生效）
    // settings.yml 陈旧刷新（生态 setup.sh 1b 同款）：官方版 conan 首跑会把无 OHOS 枚举的
    // settings.yml 缓存到 ~/.conan2——升级适配版后残留会导致 Invalid setting 'OHOS'
    // （真机实证：适配版 2.29.1 + 正确 profile 仍报错），删除后从适配包重生成。
    // 注意：探测/写文件必须走裸 shell——conanRunAsync 会把参数拼到 conan 子命令后
    // （conan test/cat 报错短路，rm 永不执行——真机实证）
    // 精确匹配枚举行（宽松 grep 'OHOS' 会被注释/其他字段误命中 → 跳过刷新 → 持续报错）
    const hasOhos: string = (nativeExecSync(
      `test -f $HOME/.conan2/settings.yml && grep -q 'OHOS:' $HOME/.conan2/settings.yml; echo $?`) ?? '').trim();
    if (hasOhos !== '0') {
      nativeExecSync(`rm -f $HOME/.conan2/settings.yml $HOME/.conan2/settings.yml.orig`);
      Logger.info(TAG, 'conan stale settings.yml refreshed (OHOS enum)');
    }
    // 内容校验（非"缺失才写"）：早期版本写过 os=Linux 的 profile 会长期驻留，
    // recipe 的 OHOS 分支（--host 注入）不触发 → configure build-type 猜测失败（真机实证）
    const profileOut: string = await this.conanRunAsync('profile show 2>&1 | head -3');
    const profileBody: string = (nativeExecSync(`cat $HOME/.conan2/profiles/default 2>/dev/null`) ?? '');
    if (profileOut.indexOf('ERROR') >= 0 || profileBody.indexOf('os=OHOS') < 0) {
      const prof: string = `[settings]
os=OHOS
os.version=6.0
arch=armv8
compiler=clang
compiler.version=15
compiler.libcxx=libc++
compiler.cppstd=17
build_type=Release

[conf]
tools.build:compiler_executables={"c": "/data/service/hnp/bin/clang", "cpp": "/data/service/hnp/bin/clang++"}

[buildenv]
PATH=+(path)/storage/Users/currentUser/usr/local/bin
PATH=+(path)/data/service/hnp/bin
`;
      // 裸 shell 写入（2026-11-13 晚真机实证：此前走 conanRunAsync——mkdir
      // 被粘成 "conan mkdir" 报错被 2>/dev/null 吞掉 → 目录从未创建 → printf
      // 重定向到不存在目录静默失败 → "profile written" 无条件打日志——文件
      // 从未落盘，conan install 永远报 default build profile doesn't exist）
      nativeExecSync(
        `mkdir -p $HOME/.conan2/profiles 2>/dev/null; printf '%s' ${this.quote(prof)} > $HOME/.conan2/profiles/default 2>&1`);
      // 落盘校验（不信无条件日志——写失败要如实报）
      const written: string = (nativeExecSync(
        `test -f $HOME/.conan2/profiles/default && grep -q 'os=OHOS' $HOME/.conan2/profiles/default; echo $?`) ?? '').trim();
      if (written === '0') {
        Logger.info(TAG, 'conan default profile written (ohos-aarch64, ecosystem-aligned)');
      } else {
        Logger.error(TAG, 'conan default profile write FAILED (check/落盘校验未通过)');
      }
    }
    Logger.info(TAG, `conan environment ready (Conan version ${verMatch[1]})`);
    return true;
  }

  /**
   * 异步执行 conan install，流式输出日志
   * @param ref     Conan 引用: name/version
   * @param onLine  每行输出回调
   * @param onDone  完成回调 (exit code, 0=成功)
   */
  /**
   * 异步执行 conan install (直接 conan 命令，流式输出)。
   * @param ref     Conan 引用: name/version
   * @param onLine  每行输出回调
   * @param onDone  完成回调 (exit code, 0=成功)
   */
  installAsync(
    ref: string,
    onLine: (line: string) => void,
    onDone: (code: number) => void
  ): void {
    Logger.info(TAG, `conan install: ${ref} (direct)`);
    // 环境前置（2026-11-19）：ensureConanReadyAsync 此前仅 UI 页调用——MCP
    // conan_install_package 直奔本函数，conan 本体重装后 ~/.conan2 profile
    // 缺失即 "default build profile doesn't exist" 报错（本轮设备重置实证）。
    // ensure 幂等（profile 缺则写/陈旧 settings.yml 刷新/chardet 探测），就绪后再装
    this.ensureConanReadyAsync().then((_ready: boolean): void => {
      this.dispatchInstall(ref, onLine, onDone);
    }).catch((_e: Object): void => {
      // ensure 异常不吞安装——继续直跑（保持旧行为，conan 自身报错带回真实 stderr）
      this.dispatchInstall(ref, onLine, onDone);
    });
  }

  private dispatchInstall(
    ref: string,
    onLine: (line: string) => void,
    onDone: (code: number) => void
  ): void {
    // python -m 模块入口：裸 conan 解析到 /data/app/bin/conan 坏脚本（Permission denied→126，真机实证）
    // conan 2 语义：install <path> 是装本地 conanfile——远程包必须 --requires=<ref>
    // （真机实证 ERROR: Conanfile not found at $HOME/2048.c/...——ref 被当路径拼接）
    // --deployer=direct_deploy：包内容（bin/ 等）直接解到 deployFolder——绕开 conan cache
    // 的 DB 化布局（p/<hash> 目录猜布局永远猜不对——真机实证 2048 已 Cache 命中却无 bin 目录）
    const deployFolder: string = `${HOME}/.cache/conan-deploy`;
    // 不带 --build=missing（2026-11-13 方案A定稿）：设备非编译农场——缺预编译
    // 二进制时快速失败（如实暴露平台发布缺口），不再触发源码下载/构建
    // （真机实证：glpk/5.0 服务器零二进制 → --build=missing 走 source() 从
    // 国际源拉源码挂死，CPU≈0 无超时）。上游命令保留 </dev/null 防交互挂起
    this.currentInstallHandle = nativeExecAsync(
      `rm -rf ${this.quote(deployFolder)}; ` +
      `NO_COLOR=1 '${HOME}/usr/local/bin/python3' -m conans.conan install --requires=${this.quote(ref)} -r ${CONAN_REMOTE} --deployer=direct_deploy --deployer-folder=${this.quote(deployFolder)} 2>&1 </dev/null`,
      (line: string) => { onLine(line); },
      (code: number) => {
        this.currentInstallHandle = null;
        onDone(code);
      }
    );
  }

  /** 从 conan cache 移除一个包 (异步，直接 conan 命令) */
  async conanRemove(ref: string): Promise<void> {
    Logger.info(TAG, `conan remove: ${ref} (direct)`);
    const out: string = await this.conanRunAsync(`remove ${this.quote(ref)} -c -f`);
    Logger.info(TAG, `conan remove ${ref} -> ${out.trim().split('\n').pop() ?? ''}`);
  }

  /** 取消正在执行的 conan install */
  cancelInstall(): void {
    if (this.currentInstallHandle) {
      nativeCancel(this.currentInstallHandle);
      this.currentInstallHandle = null;
      Logger.info(TAG, 'conan install cancelled');
    }
  }

  /**
   * 获取包在 conan 本地 cache 中的二进制产物路径。
   * recipe: ~/.conan2/p/<hash>/s → binary: 同级 p/<hash>/p/<pkgid>
   * @param ref Conan 引用: name/version
   * @returns 二进制产物绝对路径，失败返回空串
   */
  async getCachePath(ref: string): Promise<string> {
    // 优先 direct_deploy 部署目录（installAsync 落盘；结构自含无布局歧义）
    // 审计 F-P0-3：direct_deploy 会把依赖一并解到同一 deployFolder——
    // `head -1` 取第一个 bin 目录可能是**依赖**而非所装包。改为按 ref
    // 名定位（deployFolder 下按包名子树过滤）
    const pkgName: string = ref.split('/')[0];
    const deployBin: string = (nativeExecSync(
      `find ${this.quote(`${HOME}/.cache/conan-deploy`)} -type d -name bin 2>/dev/null | ` +
      `while read B; do echo "$B" | grep -q '/${pkgName}/' && echo "$B" && break; done`) ?? '').trim();
    if (deployBin !== '') {
      const pkgDir: string = (nativeExecSync(`dirname ${this.quote(deployBin)}`) ?? '').trim();
      Logger.info(TAG, `binary from deployer: ${pkgDir}`);
      return pkgDir;
    }
    const out: string = await this.conanRunAsync(`cache path ${this.quote(ref)}`);
    // 剥 ANSI 色码（conan 2 输出带色，尾行常是 '0m' 残渣——真机实证路径解析为垃圾）；
    // 只认含 / 的行（错误行/空行排除）
    const clean: string = out.replace(/\x1b\[[0-9;]*m/g, '');
    const lines: string[] = clean.trim().split('\n').filter((l: string): boolean => l.trim().indexOf('/') >= 0);
    const recipePath: string = lines.length > 0 ? lines[lines.length - 1].trim() : '';
    if (recipePath === '' || recipePath.indexOf('ERROR') >= 0) {
      Logger.warn(TAG, `cache path not found for ${ref}`);
      return '';
    }
    // 二进制定位：裸 shell + find 直查 bin 目录（原实现两重 dirname 猜 conan2 布局，
    // 且 probe 经 conanRunAsync 拼到 conan 子命令后报错——错误文本被当路径 → ls 报错
    // 单词被当二进制名建垃圾 wrapper，真机实证）。找不到 bin/ 回退 recipe 目录（库包）
    const probe: string = (nativeExecSync(
      `__d=\$(dirname ${this.quote(recipePath)}); ` +
      `__b=\$(find "\$__d" -maxdepth 5 -type d -name bin 2>/dev/null | head -1); ` +
      `if [ -n "\$__b" ]; then dirname "\$__b"; else echo "\$__d"; fi`) ?? '').trim();
    let binary: string = probe;
    if (binary === '') {
      binary = recipePath; // 纯 header-only 回退
    }
    Logger.info(TAG, `binary cache path: ${binary}`);
    return binary;
  }

  /** 从 conan 混合输出中提取 JSON（conan 可能在 JSON 前打印日志） */
  private extractJson(output: string): Object | null {
    if (!output || output.trim().length === 0) return null;
    // 剥 ANSI 转义码（\x1b[...m 等——NO_COLOR=1 的二道防线；真机实证
    // conan --format=json 输出仍可能混色码 → JSON.parse 失败）
    const clean: string = output.replace(/\x1b\[[0-9;]*[A-Za-z]/g, '');
    const start = clean.indexOf('{');
    const end = clean.lastIndexOf('}');
    if (start < 0 || end < 0 || end <= start) return null;
    try {
      return JSON.parse(clean.substring(start, end + 1)) as Object;
    } catch (e) {
      Logger.warn(TAG, `extractJson parse failed: ${e}`);
      return null;
    }
  }

  // ─── 引用解析 ─────────────────────────────────────────────────

  /** conan graph info 的 JSON 依赖图 → 顶层 requires 列表（排除 root 自身） */

  /** 解析 Conan 引用字符串: "hello/1.0.0" */
  private parseConanRef(ref: string): ConanRef {
    const result = new ConanRef();
    const atIndex = ref.indexOf('@');
    if (atIndex < 0) {
      const parts = ref.split('/');
      if (parts.length >= 2) {
        result.name = parts[0];
        result.version = parts[1];
      }
      return result;
    }
    const nameVer = ref.substring(0, atIndex);
    const userChannel = ref.substring(atIndex + 1);
    const slashIdx = userChannel.indexOf('/');
    result.user = slashIdx >= 0 ? userChannel.substring(0, slashIdx) : userChannel;
    result.channel = slashIdx >= 0 ? userChannel.substring(slashIdx + 1) : '';
    const nameVerParts = nameVer.split('/');
    if (nameVerParts.length >= 2) {
      result.name = nameVerParts[0];
      result.version = nameVerParts[1];
    }
    return result;
  }

  /** 解析 conan list JSON -> PkgItem[]
   *  格式: {"ohpcd": {"hello/1.0.0": {...}, ...}} */
  private parseConanListResult(json: Object): PkgItem[] {
    const packages: PkgItem[] = [];
    try {
      const data = json as Record<string, Object>;
      const remoteData = data[CONAN_REMOTE] as Record<string, Object>;
      if (!remoteData) {
        // 遍历所有 remote key（远程仓别名可能不同）
        const keys = Object.keys(data);
        for (const k of keys) {
          const refs = data[k] as Record<string, Object>;
          if (refs) {
            this.collectRefs(refs, packages);
          }
        }
      } else {
        this.collectRefs(remoteData, packages);
      }
    } catch (e) {
      Logger.error(TAG, `parseConanListResult failed: ${e}`);
    }
    Logger.info(TAG, `parseConanListResult: found ${packages.length} packages`);
    return packages;
  }

  private collectRefs(refs: Record<string, Object>, out: PkgItem[]): void {
    // 审计一致性修复：同一包名多版本 → 只保留最新版本（列表不重复）。
    // 全量版本存 versionMap 供详情面板版本选择器用
    const seen: Record<string, PkgItem> = {};
    const allVersions: Record<string, string[]> = {};
    for (const ref of Object.keys(refs)) {
      const parsed = this.parseConanRef(ref);
      if (parsed.name.length > 0) {
        // 收集全量版本
        if (allVersions[parsed.name] === undefined) { allVersions[parsed.name] = []; }
        allVersions[parsed.name].push(parsed.version);
        // 只保留最高版本做列表行（版本比较取 max）
        const existing: PkgItem | undefined = seen[parsed.name];
        if (existing === undefined || this.verGt(parsed.version, existing.version)) {
          seen[parsed.name] = {
            name: parsed.name,
            version: parsed.version,
            category: '三方库',
            summary: '',
            tags: [],
            filename: '',
            size_compressed: 0,
          };
        }
      }
    }
    // 写入 versionMap 供详情用
    PkgRepository.versionMap = allVersions;
    const names: string[] = Object.keys(seen);
    for (let i = 0; i < names.length; i++) { out.push(seen[names[i]]); }
  }

  /** 版本号比较：a > b 返回 true */
  private verGt(a: string, b: string): boolean {
    const pa: string[] = a.split('.');
    const pb: string[] = b.split('.');
    const n: number = Math.max(pa.length, pb.length);
    for (let i = 0; i < n; i++) {
      const x: number = Number(pa[i]) || 0;
      const y: number = Number(pb[i]) || 0;
      if (x > y) { return true; }
      if (x < y) { return false; }
    }
    return false;
  }

  /** 包名 → 全量可选版本列表（详情面板版本选择器数据源） */
  static versionMap: Record<string, string[]> = {};

  /** 某包的全量版本（降序） */
  static versionsOf(name: string): string[] {
    const list: string[] = PkgRepository.versionMap[name] ?? [];
    return list.slice().sort((a: string, b: string): number => {
      return PkgRepository.getInstance().verCmp(b, a);
    });
  }

  private verCmp(a: string, b: string): number {
    const pa: string[] = a.split('.');
    const pb: string[] = b.split('.');
    const n: number = Math.max(pa.length, pb.length);
    for (let i = 0; i < n; i++) {
      const x: number = Number(pa[i]) || 0;
      const y: number = Number(pb[i]) || 0;
      if (x !== y) { return x - y; }
    }
    return 0;
  }

  // ─── 浏览/搜索 ────────────────────────────────────────────────

  async loadIndex(): Promise<LoadResult> {
    const result = new LoadResult();
    try {
      const dataObj: Object | null = await this.conanJsonAsync(`list '*/*' -r ${CONAN_REMOTE} --format=json`);
      if (dataObj) {
        // 缓存原始 list 数据 (结构 {"ohpcd": {...}})，离线时复用
        await this.saveCache(INDEX_CACHE, JSON.stringify(dataObj));
        const packages = this.parseConanListResult(dataObj);
        if (packages.length > 0) {
          this.cachedPackages = packages;
          result.state = PkgLoadState.SUCCESS;
          result.count = packages.length;
          result.message = `已加载 ${packages.length} 个软件包`;
          return result;
        }
      }
      Logger.warn(TAG, 'conan list returned no packages, trying cache');
      const cached = await this.loadCachedIndex();
      if (cached.length > 0) {
        this.cachedPackages = cached;
        result.state = PkgLoadState.SUCCESS;
        result.count = cached.length;
        result.message = `使用缓存，共 ${cached.length} 个软件包`;
        return result;
      }
      return this.loadFromCatalog();
    } catch (e) {
      const cached = await this.loadCachedIndex();
      if (cached.length > 0) {
        this.cachedPackages = cached;
        result.state = PkgLoadState.SUCCESS;
        result.count = cached.length;
        result.message = `异常，使用缓存 ${cached.length} 个包`;
        return result;
      }
      return this.loadFromCatalog(`${e}`);
    }
  }

  /**
   * CDN 目录兜底：无 conan/python 本体时（或代理链路异常）用发现服务
   * conan-packages.json 提供浏览能力；安装/下载操作仍需 conan 本体。
   */
  private async loadFromCatalog(reason: string = ''): Promise<LoadResult> {
    const result = new LoadResult();
    const entries: ConanCatalogEntry[] = ConanCatalogService.all();
    if (entries.length === 0) {
      result.state = PkgLoadState.ERROR;
      result.message = reason !== ''
        ? `conan 不可用（${reason}），CDN 目录加载中，请稍后刷新`
        : 'conan 不可用，CDN 目录加载中，请稍后刷新';
      return result;
    }
    const items: PkgItem[] = [];
    for (let i = 0; i < entries.length; i++) {
      items.push({
        name: entries[i].name,
        version: entries[i].version,
        category: '三方库',
        summary: 'CDN 目录（安装需 conan）',
        tags: [],
        filename: '',
        size_compressed: 0,
      });
    }
    this.cachedPackages = items;
    result.state = PkgLoadState.SUCCESS;
    result.count = items.length;
    result.message = `CDN 目录，共 ${items.length} 个包（安装需 conan）`;
    return result;
  }

  async searchConan(query: string): Promise<PkgItem[]> {
    if (query.trim().length === 0) {
      return this.cachedPackages;
    }
    try {
      // conan list "query/*" 服务端过滤
      const dataObj: Object | null = await this.conanJsonAsync(
        `list ${this.quote(`${query}/*`)} -r ${CONAN_REMOTE} --format=json`);
      if (dataObj) {
        return this.parseConanListResult(dataObj);
      }
    } catch (e) {
      Logger.error(TAG, `searchConan failed: ${e}`);
    }
    // 代理不可用 → 客户端过滤当前缓存（含 CDN 目录兜底数据）
    const kw: string = query.trim().toLowerCase();
    return this.cachedPackages.filter((p: PkgItem): boolean => p.name.toLowerCase().indexOf(kw) >= 0);
  }

  // ─── 包详情 ──────────────────────────────────────────────────

  /** 获取包详情: proxy.detail 一次返回 show + cache_path + ci-metadata.json */
  async getPackageDetail(name: string, version?: string): Promise<PkgDetail | null> {
    try {
      let pkgVersion = version || '';
      if (!pkgVersion) {
        const pkg = this.cachedPackages.find((p: PkgItem): boolean => p.name === name);
        if (pkg) {
          pkgVersion = pkg.version;
        }
      }
      if (!pkgVersion) {
        return null;
      }

      const ref = `${name}/${pkgVersion}`;
      // ⚠ Conan 2.29.1：`show` 不存在；`inspect` 要**路径**不是引用（真机实证
      // "Conanfile not found at /storage/.../name/version"——把引用当相对路径
      // 了）。标准三步：① download --only-recipe → ② cache path 取本地路径
      // → ③ inspect <路径> --format=json
      const dlOut: string = await this.conanRunAsync(
        `download ${this.quote(ref)} --only-recipe -r ${CONAN_REMOTE}`);
      Logger.info(TAG, `getPackageDetail(${ref}) download: ${dlOut.trim().substring(0, 200)}`);
      // 取缓存路径（inspect 用路径不用引用）
      const cpOut: string = await this.conanRunAsync(`cache path ${this.quote(ref)}`);
      const cpClean: string = cpOut.replace(/\x1b\[[0-9;]*m/g, '');
      const cpLines: string[] = cpClean.trim().split('\n')
        .filter((l: string): boolean => l.trim().indexOf('/') >= 0 && l.indexOf('ERROR') < 0);
      const recipePath: string = cpLines.length > 0 ? cpLines[cpLines.length - 1].trim() : '';
      Logger.info(TAG, `getPackageDetail(${ref}) cache path: ${recipePath}`);
      let inspectOut: string = '';
      if (recipePath !== '') {
        inspectOut = await this.conanRunAsync(
          `inspect ${this.quote(recipePath)} --format=json`);
      }
      Logger.info(TAG, `getPackageDetail(${ref}) inspect len=${inspectOut.length} head=${inspectOut.trim().substring(0, 120)}`);
      const inspectObj: Object | null = this.extractJson(inspectOut);
      Logger.info(TAG, `getPackageDetail(${ref}) inspect extractJson: ${inspectObj !== null ? 'JSON found' : 'NO JSON'}`);

      let detail: PkgDetail | null = null;

      if (inspectObj !== null) {
        const inspectRec: Record<string, Object> = inspectObj as Record<string, Object>;
        if (Object.keys(inspectRec).length > 0) {
          detail = this.parseConanShow(name, pkgVersion, inspectObj);
          Logger.info(TAG, `getPackageDetail(${ref}) inspect parsed: ${detail !== null ? 'OK' : 'NULL'} requires=${detail !== null ? detail.requires.length : -1}`);
        }
      }

      // ③ conan graph info（完整依赖树——inspect 读不到 def requirements()
      // 声明的依赖，graph info 解析全图。⚠ 此 Conan 版本 graph info 不支持
      // --format=json（26KB 纯文本）——改为解析文本输出的 Requirements 段）
      if (detail !== null && detail.requires.length === 0) {
        const graphDir = `${HOME}/.conan2/graph-tmp`;
        nativeExecSync(
          `mkdir -p ${this.quote(graphDir)} && echo '[requires]' > ${this.quote(graphDir)}/conanfile.txt && echo '${ref}' >> ${this.quote(graphDir)}/conanfile.txt`);
        const graphOut: string = await this.conanRunAsync(
          `graph info ${this.quote(graphDir)} -r ${CONAN_REMOTE}`);
        // 文本解析：找 "Requirements:" 段，提取 "    name/version#rrev" 行
        const lines: string[] = graphOut.split('\n');
        let inReq: boolean = false;
        for (let li = 0; li < lines.length; li++) {
          const ln: string = lines[li].trim();
          if (ln.startsWith('Requirements')) { inReq = true; continue; }
          if (inReq && ln === '') { break; }   // 空行 = 段落结束
          if (inReq && ln.length > 0) {
            // 行格式："    4ti2/1.6.10.1#rrev - Downloaded (ohpcd)"
            const refMatch: RegExpMatchArray | null = ln.match(/^([A-Za-z0-9][\w.+-]*\/[\w.+-]*)/);
            if (refMatch !== null) {
              const depRef: string = refMatch[1];
              const parsed = this.parseConanRef(depRef);
              if (parsed.name.length > 0 && parsed.name !== name) {
                detail.requires.push({ name: parsed.name, version: parsed.version });
              }
            }
          }
        }
        Logger.info(TAG, `getPackageDetail(${ref}) graph info text: ${detail.requires.length} deps`);
      }

      // 2) ci-metadata.json 溯源（本地 cache 内 recipe/binary 目录下——复用
      // 上方已取的 recipePath，不再重复跑 cache path 命令）
      let metaObj: Record<string, Object> | null = null;
      if (recipePath !== '' && recipePath.indexOf('ERROR') < 0) {
        const metaRaw: string = await this.conanRunAsync(
          `for d in ${this.quote(recipePath)} ${this.quote(recipePath)}p/*/; do [ -f \$d/ci-metadata.json ] && cat \$d/ci-metadata.json && break; done 2>/dev/null`);
        const metaJson: Object | null = this.extractJson(metaRaw);
        if (metaJson !== null) {
          metaObj = metaJson as Record<string, Object>;
        }
      }

      if (metaObj !== null) {
        const hasMeta: boolean = Object.keys(metaObj).length > 0;
        if (!detail && hasMeta) {
          detail = this.buildMinimalDetail(name, pkgVersion);
        }
        if (detail && hasMeta) {
          this.applyMetadataToDetail(detail, metaObj);
        }
      }

      if (!detail) {
        Logger.warn(TAG, `detail failed for ${ref} (no show/metadata)`);
        return null;
      }
      return detail;
    } catch (e) {
      Logger.error(TAG, `getPackageDetail failed for ${name}: ${e}`);
    }
    return null;
  }

  /** 解析 conan show JSON -> PkgDetail */
  private parseConanShow(name: string, version: string, showJson: Object): PkgDetail {
    const d = showJson as Record<string, Object>;
    const description = (d['description'] as string) || '';
    const license = (d['license'] as string) || '';
    const homepage = (d['homepage'] as string) || '';
    const topics = d['topics'] as string[];
    const label = (d['label'] as string) || `${name}/${version}`;

    // 解析 requires——conan inspect 返回**列表**（非 show 的字典）：
    // 空列表 = 无依赖或 recipe 用 def requirements() 方法声明（inspect 静态
    // 读不到方法体，需 graph info 才能解析完整树）
    const requires: PkgRequire[] = [];
    const reqRaw: Object | undefined = d['requires'];
    if (reqRaw !== undefined && reqRaw !== null) {
      const reqStr: string = JSON.stringify(reqRaw);
      if (reqStr.startsWith('[')) {
        // 列表形态（conan inspect）：["zlib/1.3", ...] 或 [{"ref": "zlib/1.3", ...}, ...]
        const reqList: Object[] = reqRaw as Object[];
        for (let i = 0; i < reqList.length; i++) {
          const item: Object = reqList[i];
          if (typeof item === 'string') {
            const parsed = this.parseConanRef(item);
            if (parsed.name.length > 0) requires.push({ name: parsed.name, version: parsed.version });
          } else {
            const reqObj: Record<string, Object> = item as Record<string, Object>;
            const refStr: string = (reqObj['ref'] as string) ?? (reqObj['name'] as string) ?? '';
            if (refStr !== '') {
              const parsed = this.parseConanRef(refStr);
              if (parsed.name.length > 0) {
                requires.push({ name: parsed.name, version: parsed.version });
              }
            }
          }
        }
      } else if (reqStr.startsWith('{')) {
        // 字典形态（conan show 兼容）：{"zlib/1.3": {...}, ...}
        const reqData = reqRaw as Record<string, Object>;
        for (const reqRef of Object.keys(reqData)) {
          const parsed = this.parseConanRef(reqRef);
          if (parsed.name.length > 0) requires.push({ name: parsed.name, version: parsed.version });
        }
      }
    }

    // ── inspect 额外字段（2026-11-14 用户反馈：只显示版本太少）──
    // package_type: library / application / header-only
    const pkgType: string = (d['package_type'] as string) || '';
    const category: string = pkgType === 'application' ? '命令行工具' :
      pkgType === 'library' ? '三方库' : '三方库';
    // languages: ["C"] / ["C++"]
    const languages: string[] = (d['languages'] as string[]) ?? [];
    // deprecated
    const isDeprecated: boolean = d['deprecated'] === true;

    // settings / options（构建矩阵——conan inspect 静态读出）
    const optionsMap: Record<string, Object> = (d['options'] as Record<string, Object>) ?? {};
    const optionNames: string[] = Object.keys(optionsMap);
    // settings: {"os": [...], "arch": [...], "compiler": [...], ...}
    const settingsMap: Record<string, Object> = (d['settings'] as Record<string, Object>) ?? {};
    const settingNames: string[] = Object.keys(settingsMap);

    return {
      name: name,
      version: version,
      summary: description,
      description: description,
      homepage: homepage,
      license: license,
      category: category,
      tags: topics ? topics : [],
      arch: ['aarch64'],
      maintainer: 'ohpcd',
      requires: requires,
      recommends: [],
      conflicts: [],
      replaces: [],
      provides: [],
      source_url: '',
      adaptation_url: '',
      commands: [],
      download_url: '',
      sha256: '',
      size_compressed: 0,
      size_installed: 0,
      install: { mode: 'standard', prefix: '', symlink: '', post_script: '' },
      changelog: [],
    };
  }

  /** 构建最小壳详情 (show 失败但有 ci-metadata 时使用) */
  private buildMinimalDetail(name: string, version: string): PkgDetail {
    return {
      name: name,
      version: version,
      summary: '',
      description: '',
      homepage: '',
      license: '',
      category: '三方库',
      tags: [],
      arch: ['aarch64'],
      maintainer: 'ohpcd',
      requires: [],
      recommends: [],
      conflicts: [],
      replaces: [],
      provides: [],
      source_url: '',
      adaptation_url: '',
      commands: [],
      download_url: '',
      sha256: '',
      size_compressed: 0,
      size_installed: 0,
      install: { mode: 'standard', prefix: '', symlink: '', post_script: '' },
      changelog: [],
      source_trace: undefined,
      build_trace: undefined,
      test_report: undefined,
    };
  }

  /** 把 ci-metadata.json 的溯源信息应用到 PkgDetail */
  private applyMetadataToDetail(detail: PkgDetail, meta: Record<string, Object>): void {
    try {
      const st = meta['source_trace'] as Record<string, Object>;
      if (st) {
        detail.source_trace = {
          url: (st['url'] as string) || '',
          sha256: (st['sha256'] as string) || '',
          adaptation_url: st['adaptation_url'] as string,
          adaptation_commit: st['adaptation_commit'] as string,
        };
        detail.source_url = detail.source_trace.url;
        detail.adaptation_url = detail.source_trace.adaptation_url || '';
        detail.sha256 = detail.source_trace.sha256;
      }
      const bt = meta['build_trace'] as Record<string, Object>;
      if (bt) {
        detail.build_trace = {
          system: (bt['build_system'] as string) || '',
          compiler: (bt['compiler'] as string) || '',
          os: bt['os'] as string,
          timestamp: bt['build_time'] as string,
          patches_applied: bt['patches_applied'] as string[],
        };
      }
      const tr = meta['test_report'] as Record<string, Object>;
      if (tr) {
        detail.test_report = {
          status: (tr['status'] as string) || '',
          official_test: tr['l1_official'] as PkgTestPhase,
          platform_test: tr['l2_matrix'] as PkgTestPhase,
          baseline_test: tr['l5_baseline'] as PkgTestPhase,
          security_scan: tr['l4_security'] as PkgTestPhase,
        };
      }
    } catch (e) {
      Logger.warn(TAG, `applyMetadataToDetail failed: ${e}`);
    }
  }

  // ─── 二进制下载 URL (Phase 2 改为 conan install 后移除) ─────────

  /**
   * 异步获取 Conan 包的二进制下载 URL (REST，Phase 2 后移除)
   * 链路: /latest → revision → /search → package_id → pkg_revision → URL
   */
  async getConanDownloadUrl(name: string, version: string): Promise<string> {
    try {
      // Step 1: recipe revision
      let username = 'ohpcd';
      let channel = 'stable';
      let revUrl = `${conanBase()}/v2/conans/${name}/${version}/${username}/${channel}/latest`;
      Logger.info(TAG, `[ConanDL] Step1: GET ${revUrl}`);
      let revJson = await this.fetchJsonRest(revUrl);
      if (!revJson) {
        username = '_';
        channel = '_';
        revUrl = `${conanBase()}/v2/conans/${name}/${version}/${username}/${channel}/latest`;
        revJson = await this.fetchJsonRest(revUrl);
      }
      if (!revJson) {
        Logger.error(TAG, `[ConanDL] Step1 FAILED: no revision for ${name}/${version}`);
        return '';
      }
      const d = revJson as Record<string, Object>;
      const revision = (d['revision'] as string) || '';
      if (!revision) return '';

      // Step 2: search binaries
      const searchUrl = `${conanBase()}/v2/conans/${name}/${version}/${username}/${channel}` +
        `/revisions/${revision}/search?list_only=False`;
      const searchResult = await this.fetchJsonRest(searchUrl);
      if (!searchResult) return '';
      const sr = searchResult as Record<string, Object>;
      const pkgKeys = Object.keys(sr);
      if (pkgKeys.length === 0) return '';
      const pkgId = pkgKeys[0];
      const pkgInfo = sr[pkgId] as Record<string, string>;
      const pkgRevision = (pkgInfo['package_revision'] as string) || '';

      // Step 3: download URL
      const downloadUrl = `${conanBase()}/v2/conans/${name}/${version}/${username}/${channel}` +
        `/revisions/${revision}/packages/${pkgId}/revisions/${pkgRevision}` +
        `/files/conan_package.tgz`;
      return downloadUrl;
    } catch (e) {
      Logger.error(TAG, `getConanDownloadUrl: ${e}`);
      return '';
    }
  }

  /** HTTP GET 获取 JSON (仅 getConanDownloadUrl 使用，Phase 2 后移除) */
  private async fetchJsonRest(url: string): Promise<Object | null> {
    const req = http.createHttp();
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        header: { 'Accept': 'application/json, */*' },
        connectTimeout: 15000,
        readTimeout: 30000,
      });
      if (resp.responseCode === 200 && resp.result) {
        if (typeof resp.result === 'string') {
          return JSON.parse(resp.result as string) as Object;
        } else {
          const decoder = new util.TextDecoder('utf-8');
          const text = decoder.decode(new Uint8Array(resp.result as ArrayBuffer));
          return JSON.parse(text) as Object;
        }
      }
      return null;
    } catch (e) {
      Logger.error(TAG, `fetchJsonRest: ${e}`);
      return null;
    } finally {
      req.destroy();
    }
  }

  // ─── 缓存 ──────────────────────────────────────────────────

  private async saveCache(filename: string, content: string): Promise<void> {
    if (!this.context) return;
    try {
      const dir = `${this.context.cacheDir}/${CACHE_DIR}`;
      const fullPath = `${dir}/${filename}`;
      const lastSlash = fullPath.lastIndexOf('/');
      const dirPath = fullPath.substring(0, lastSlash);
      await fileIo.mkdir(dirPath, true);
      // CREATE | TRUNC | WRITE_ONLY：文件不存在则创建，存在则截断覆盖
      // 单独 CREATE 在文件已存在时会抛 "File exists"
      const file = await fileIo.open(
        fullPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY
      );
      await fileIo.write(file.fd, content);
      await fileIo.close(file.fd);
      Logger.info(TAG, `cache saved: ${filename}`);
    } catch (e) {
      Logger.error(TAG, `saveCache: ${e}`);
    }
  }

  private async loadCacheFile(filename: string): Promise<string | null> {
    if (!this.context) return null;
    try {
      const fullPath = `${this.context.cacheDir}/${CACHE_DIR}/${filename}`;
      const file = await fileIo.open(fullPath, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(file.fd);
      const buf = new ArrayBuffer(stat.size);
      await fileIo.read(file.fd, buf);
      await fileIo.close(file.fd);
      return new util.TextDecoder('utf-8').decode(new Uint8Array(buf));
    } catch (e) {
      return null;
    }
  }

  private async loadCachedIndex(): Promise<PkgItem[]> {
    const content = await this.loadCacheFile(INDEX_CACHE);
    if (content !== null) {
      const json = this.extractJson(content);
      if (json) {
        return this.parseConanListResult(json);
      }
    }
    return [];
  }
}
