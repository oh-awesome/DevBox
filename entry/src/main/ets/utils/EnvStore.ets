/**
 * EnvStore —— 统一环境数据层（UI 与 MCP 共用；进程内单例，主/托盘进程各一份）
 *
 * 设计原则（2026-11-05 与用户对齐）：
 * 1. 远程数据（manifest/发现服务）——纯 ArkTS http 异步任务解析，零 shell
 * 2. 本地已装——安装账本（DevEnvRegistry）为源；shell 仅做纠正
 *    （active 链接读取 + 目录存在性 + 账本外目录补充），纠正走简单批量命令异步执行
 * 3. 二级包管理器清单（pip/npm/brew）——shell 获取（各一条简单命令，异步）
 * 4. 失效时机：首次访问 / 任务完成（runtime_epoch）/ 手动刷新 refreshAll()
 *
 * 消费方式：
 * - 同步快照：EnvStore.available(pkg) / EnvStore.installed(pkg)（缓存直读，切页零开销）
 * - 刷新入口：ensureRemote / ensureLocal / refreshEco / refreshAll（刷新完 bump envstore_epoch）
 */
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { resourceManager } from '@kit.LocalizationKit';
import { common } from '@kit.AbilityKit';
import { ArtifactsRepo, RepoVersion } from './ArtifactsRepo';
import { DiscoveryService, DiscoveryConfig } from './DiscoveryService';
import { DevEnvRegistry } from './DevEnvRegistry';
import { DevTask } from './DevTask';
import { BrewEnv } from './BrewEnv';
import { GunzipUtil } from './GunzipUtil';
import { PyCatalogService } from './PyCatalogService';
import { PyVersionsService } from './PyVersionsService';
import { NpmCatalogService } from './NpmCatalogService';
import { ConanCatalogService } from './ConanCatalogService';






import fs from '@ohos.file.fs';






const TAG = 'EnvStore';
const HOME: string = '/storage/Users/currentUser';
const MANIFEST_CACHE: string = 'manifest_cache.json';

/** 本地已装快照（账本为源 + 纠正结果） */
export interface InstalledSnapshot {
  vers: string[];      // 已装版本（降序）
  active: string;      // current 链接指向（空=无）
  updatedAt: number;
}

/** 运行时包族（语言页/总览用） */
const RUNTIME_PKGS: string[] = ['python', 'BiShengJDK', 'rust', 'node', 'lua', 'perl', 'php', 'go'];

export class EnvStore {

  // ── 远程目录（manifest 全量，一次拉取按包切片） ──
  private static remoteVersions: Record<string, RepoVersion[]> = {};
  private static remoteSummaries: Record<string, string> = {};
  // 包级元数据（manifest 提供但此前未解析——2026-11-14 审计反馈后接入）
  private static remoteHomepages: Record<string, string> = {};
  private static remoteLicenses: Record<string, string> = {};
  private static remoteMaintainers: Record<string, string> = {};
  private static remoteCategories: Record<string, string> = {};
  private static remoteAt: number = 0;
  private static remoteLoading: boolean = false;
  private static retried: boolean = false;

  // ── 种子目录（rawfile 构建期快照：离线/慢网首屏秒开，manifest 到达后补全版本） ──
  private static seedNames: string[] = [];
  private static seedSummaries: Record<string, string> = {};
  private static seedCategories: Record<string, string> = {};
  private static seedLoaded: boolean = false;

  // ── manifest 磁盘缓存（上次拉取的原文存应用数据；启动先用旧数据渲染，后台拉新覆盖刷新） ──
  private static filesDir: string = '';
  private static diskCacheTried: boolean = false;
  /** 本地缓存 manifest 对应的 CDN 指纹（两步协议零流量判定用） */
  private static cachedSha256: string = '';

  // ── 本地已装（账本 + 纠正缓存） ──
  private static installedCache: Record<string, InstalledSnapshot> = {};
  private static localAt: number = 0;
  private static correcting: boolean = false;

  // ── 二级包管理器清单 ──
  private static ecoPip: string[] = [];
  private static ecoNpm: string[] = [];
  private static ecoBrew: string[] = [];
  private static ecoAt: number = 0;

  /** 数据纪元：页面 @StorageProp('envstore_epoch') @Watch 响应刷新 */
  static bump(): void {
    AppStorage.setOrCreate('envstore_epoch', Date.now());
    // 数据更新同时通知 runtime_epoch：语言页监听的是它（⟳ 点击瞬间的 bump 早于
    // 异步数据到达，仅 envstore_epoch 无页面监听 → 新数据到达后页面不重取、
    // 持旧 repoVersions 对象 → 安装用旧条目缺 url——真机实证）
    AppStorage.setOrCreate('runtime_epoch', Date.now());
  }

  /** 加载种子目录（rawfile 构建期快照；Index/TrayAbility 启动时传入 context 调一次） */
  static loadSeed(ctx: common.Context): void {
    // 记录沙箱目录（manifest 持久化缓存用）
    if (EnvStore.filesDir === '') {
      EnvStore.filesDir = ctx.filesDir;
    }
    if (EnvStore.seedLoaded) { return; }
    EnvStore.seedLoaded = true;
    try {
      const rm: resourceManager.ResourceManager = ctx.resourceManager;
      const raw: Uint8Array = rm.getRawFileContentSync('tool_catalog_seed.json');
      const text: string = util.TextDecoder.create('utf-8').decodeToString(raw);
      const json: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      const arr: Object[] = (json['tools'] as Object[]) ?? [];
      for (let i = 0; i < arr.length; i++) {
        const t: Record<string, Object> = arr[i] as Record<string, Object>;
        if (t === undefined || t === null) { continue; }
        const name: string = (t['name'] as string) ?? '';
        if (name === '') { continue; }
        EnvStore.seedNames.push(name);
        EnvStore.seedSummaries[name] = (t['summary'] as string) ?? '';
        EnvStore.seedCategories[name] = (t['category'] as string) ?? '其他工具';
      }
      hilog.info(0x0000, TAG, 'seed catalog loaded: %{public}d tools', EnvStore.seedNames.length);
      EnvStore.bump();
    } catch (e) {
      hilog.error(0x0000, TAG, 'seed load failed: %{public}s', `${e}`);
    }
  }

  // ══════════════════ 远程（纯 ArkTS http） ══════════════════

  /** manifest 全量目录（runtime + tool，73 包族）。
   *  两步拉取协议（CDN 提速改造后）：
   *  ① GET discovery（4KB，0.3s）→ catalog_fingerprints["manifest.json"].sha256
   *  ② 与本地缓存指纹一致 → 零流量结束（磁盘缓存已在内存）；不一致 → 拉 manifest.json.gz（18KB）本地 gunzip
   *  禁令：不裸拉 .json 本体；不依赖 Accept-Encoding（该 CDN 不协商）；不请求已删除的 catalog/versions.json
   */
  static ensureRemote(force: boolean = false): void {
    // 启动时先读磁盘缓存（上次拉取的旧数据）：页面立即可用，后台再拉新覆盖刷新
    EnvStore.loadDiskCache();
    const fresh: boolean = Date.now() - EnvStore.remoteAt < 10 * 60 * 1000;
    const has: boolean = Object.keys(EnvStore.remoteVersions).length > 0;
    if (!force && has && fresh) { return; }
    if (EnvStore.remoteLoading) { return; }
    EnvStore.remoteLoading = true;
    // 第一步：发现文档（含 CDN 文件指纹）
    DiscoveryService.resolve(null, (cfg: DiscoveryConfig) => {
      const fp: string = cfg.fingerprintOf('manifest.json');
      if (!force && fp !== '' && fp === EnvStore.cachedSha256 && EnvStore.remoteReady()) {
        // 指纹一致：零流量，现有数据视为新鲜
        EnvStore.remoteAt = Date.now();
        EnvStore.remoteLoading = false;
        hilog.info(0x0000, TAG, 'manifest fingerprint unchanged, zero traffic');
        EnvStore.bump();
        return;
      }
      EnvStore.fetchManifestGz(fp);
    });
  }

  /** 第二步：拉 manifest.json.gz → GunzipUtil 原生 GZip 解压（零 shell 依赖） */
  private static fetchManifestGz(expectSha256: string): void {
    const url = DiscoveryService.latest().resolveCatalogUrl('manifest.json', 'manifest.json.gz');
    if (url === '') {
      // base 拼装通道已日落：manifest 无 blob_sha = 发现服务未提供 manifest 的
      // blob 直连——fail loud（已向平台提需求：manifest.json 纳入 catalog_fingerprints）；
      // 30s 后随发现刷新重试（平台补上指纹即自愈）
      hilog.error(0x0000, TAG, 'manifest 无 blob_sha（catalog_fingerprints 未覆盖 manifest.json）——跳过本次拉取');
      EnvStore.remoteLoading = false;
      EnvStore.scheduleRetry();
      return;
    }
    const tmpGz = `${EnvStore.filesDir}/manifest.tmp.gz`;

    GunzipUtil.downloadAndGunzip(url, tmpGz).then((text: string) => {
      EnvStore.remoteLoading = false;
      if (text === '') {
        hilog.error(0x0000, TAG, 'manifest download+gunzip failed');
        EnvStore.scheduleRetry();
        return;
      }
      if (EnvStore.applyManifest(text)) {
        EnvStore.remoteAt = Date.now();
        hilog.info(0x0000, TAG, 'manifest loaded: %{public}d packages',
          Object.keys(EnvStore.remoteVersions).length);
        EnvStore.persistManifest(text);
        if (expectSha256 !== '') {
          EnvStore.persistSha256(expectSha256);
        }
        EnvStore.bump();
      } else {
        EnvStore.scheduleRetry();
      }
    });
  }

  private static scheduleRetry(): void {
    if (EnvStore.retried || EnvStore.remoteReady()) { return; }
    EnvStore.retried = true;
    hilog.warn(0x0000, TAG, 'manifest fetch failed, retry in 30s (seed catalog in use)');
    setTimeout(() => {
      EnvStore.retried = false;
      if (!EnvStore.remoteReady()) {
        EnvStore.ensureRemote(true);
      }
    }, 30000);
  }

  /** 磁盘缓存 → 内存（启动时一次；解析失败静默，继续走种子/网络） */
  private static loadDiskCache(): void {
    if (EnvStore.diskCacheTried || EnvStore.filesDir === '' || EnvStore.remoteReady()) { return; }
    EnvStore.diskCacheTried = true;
    try {
      const path: string = `${EnvStore.filesDir}/${MANIFEST_CACHE}`;
      if (!fs.accessSync(path)) { return; }
      const text: string = fs.readTextSync(path);
      EnvStore.applyManifest(text);
      // 旧数据视为过期（remoteAt 保持 0）：立即渲染的同时后台拉新，新数据到达覆盖刷新
      // 同时读取缓存指纹（两步协议：指纹一致则后台比对零流量）
      try {
        const shaPath: string = `${EnvStore.filesDir}/${MANIFEST_CACHE}.sha256`;
        if (fs.accessSync(shaPath)) {
          EnvStore.cachedSha256 = fs.readTextSync(shaPath).trim();
        }
      } catch (_) {
      }
      hilog.info(0x0000, TAG, 'manifest disk cache loaded (%{public}d bytes, fp=%{public}s)',
        text.length, EnvStore.cachedSha256 !== '' ? 'hit' : 'none');
      EnvStore.bump();
    } catch (e) {
      hilog.warn(0x0000, TAG, 'manifest disk cache read failed: %{public}s', `${e}`);
    }
  }

  /** manifest 原文 → 内存结构（磁盘缓存与网络响应共用解析） */
  private static applyManifest(text: string): boolean {
    const versions: Record<string, RepoVersion[]> = {};
    const summaries: Record<string, string> = {};
    const homepages: Record<string, string> = {};
    const licenses: Record<string, string> = {};
    const maintainers: Record<string, string> = {};
    const categories: Record<string, string> = {};
    try {
      const json: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      const packages: Record<string, Object> = json['packages'] as Record<string, Object>;
      if (packages) {
        const names: string[] = Object.keys(packages);
        for (let i = 0; i < names.length; i++) {
          // H-3 安全白名单（审计修复）：manifest 是远程数据，包名/版本/sha256
          // 字符集受限——防 shell 注入/symlink 穿越（5 个汇入点统一在此收口）
          if (!/^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(names[i])) { continue; }
          const pkg: Record<string, Object> = packages[names[i]] as Record<string, Object>;
          if (pkg === undefined || pkg === null) { continue; }
          summaries[names[i]] = (pkg['summary'] as string) ?? '';
          categories[names[i]] = (pkg['category'] as string) ?? '';
          homepages[names[i]] = (pkg['homepage'] as string) ?? '';
          licenses[names[i]] = (pkg['license'] as string) ?? '';
          maintainers[names[i]] = (pkg['maintainer'] as string) ?? '';
          const list: RepoVersion[] = [];
          const versionsRaw: Record<string, Object> = pkg['versions'] as Record<string, Object>;
          if (versionsRaw) {
            const keys: string[] = Object.keys(versionsRaw);
            for (let j = 0; j < keys.length; j++) {
              const info: Record<string, Object> = versionsRaw[keys[j]] as Record<string, Object>;
              if (!info) { continue; }
              const seg: string[] = keys[j].split('/');
              const sizeBytes: number = Number(`${info['size']}`) || 0;
              // H-3：版本白名单（数字开头，字符集受限）
              const verClean: string = seg.length > 1 ? seg[seg.length - 1] : keys[j];
              if (!/^[0-9][0-9a-zA-Z._+-]*$/.test(verClean)) { continue; }
              // H-3：sha256 格式校验（64 位十六进制或空）
              const shaClean: string = (info['sha256'] as string) || '';
              if (shaClean !== '' && !/^[a-f0-9]{64}$/.test(shaClean)) { continue; }
              const rv: RepoVersion = {
                ver: verClean,
                kernel: seg.length > 1 ? seg[0] : '',
                sizeBytes: sizeBytes,
                sizeLabel: ArtifactsRepo.humanSize(sizeBytes),
                sha256: shaClean,
                path: (info['path'] as string) || '',
                provides: JSON.stringify(info['provides'] || []),
                // 审计 S-P2-2：url 过 validUrl 白名单（https+host+字符校验）——
                // 恶意 manifest 可指向任意主机装任意二进制
                url: DiscoveryService.validUrl(info['url'] as string ?? '')
                  ? (info['url'] as string) : '',
                installRaw: info['install'] !== undefined ? JSON.stringify(info['install']) : '',
                activateRaw: info['activate'] !== undefined ? JSON.stringify(info['activate']) : '',
                uninstallRaw: info['uninstall'] !== undefined ? JSON.stringify(info['uninstall']) : '',
              };
              list.push(rv);
            }
          }
          versions[names[i]] = list;
        }
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'manifest parse failed: %{public}s', `${e}`);
      return false;
    }
    EnvStore.remoteVersions = versions;
    EnvStore.remoteSummaries = summaries;
    EnvStore.remoteHomepages = homepages;
    EnvStore.remoteLicenses = licenses;
    EnvStore.remoteMaintainers = maintainers;
    EnvStore.remoteCategories = categories;
    return true;
  }

  /** manifest 原文落盘（应用数据；下次启动先用旧数据） */
  private static persistManifest(text: string): void {
    if (EnvStore.filesDir === '') { return; }
    try {
      const path: string = `${EnvStore.filesDir}/${MANIFEST_CACHE}`;
      const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(file.fd, text);
      fs.closeSync(file.fd);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'manifest persist failed: %{public}s', `${e}`);
    }
  }

  /** 缓存指纹落盘（与 manifest_cache.json 配套；两步协议零流量判定用） */
  private static persistSha256(sha: string): void {
    EnvStore.cachedSha256 = sha;
    if (EnvStore.filesDir === '') { return; }
    try {
      const path: string = `${EnvStore.filesDir}/${MANIFEST_CACHE}.sha256`;
      const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(file.fd, sha);
      fs.closeSync(file.fd);
    } catch (_) {
    }
  }

  /** 某包族可装版本（降序；远程未加载完成时为空数组，页面按需展示加载态） */
  static available(pkg: string): RepoVersion[] {
    const list: RepoVersion[] | undefined = EnvStore.remoteVersions[pkg];
    return list ?? [];
  }

  /** 某包摘要（manifest 优先，未就绪回退种子） */
  static summary(pkg: string): string {
    const live: string = EnvStore.remoteSummaries[pkg];
    if (live !== undefined && live !== '') { return live; }
    return EnvStore.seedSummaries[pkg] ?? '';
  }

  static homepageOf(pkg: string): string { return EnvStore.remoteHomepages[pkg] ?? ''; }
  static licenseOf(pkg: string): string { return EnvStore.remoteLicenses[pkg] ?? ''; }
  static maintainerOf(pkg: string): string { return EnvStore.remoteMaintainers[pkg] ?? ''; }

  /** 远程目录是否已加载（manifest live 到达） */
  static remoteReady(): boolean {
    return Object.keys(EnvStore.remoteVersions).length > 0;
  }

  /** manifest 某包分类（'tool' | 'runtime' | ''） */
  static categoryOf(pkg: string): string {
    return EnvStore.remoteCategories[pkg] ?? '';
  }

  /** 语言名 → 包族键。
   *  审计再修（2026-11-14）：'BiShengJDK'.toLowerCase()='bishengjdk'
   *  **不含 'java' 子串** → 此前模糊匹配永远失配 → Java 卡恒显灰灯。
   *  修法：显式别名关键词表（语言名 → 在包族键中搜索的关键词列表），
   *  'java' → ['jdk', 'java']——'bishengjdk' 含 'jdk' 命中。
   *  将来加 OpenJDK/Temurin 也含 'jdk' → 自动命中，无需改代码。
   */
  private static LANG_ALIASES: Record<string, string[]> = {
    'java': ['jdk', 'java'],
  };

  static langKeyOf(lang: string): string {
    // 1. 精确匹配（大多数语言键 = 语言名：python/rust/node/lua/perl/php/go）
    if (EnvStore.remoteVersions[lang] !== undefined) { return lang; }
    // 2. 别名关键词（'java' → ['jdk', 'java']）
    const lower: string = lang.toLowerCase();
    const keywords: string[] = EnvStore.LANG_ALIASES[lower] ?? [lower];
    // 3. 模糊匹配：runtime 类包族键包含任一关键词
    const names: string[] = Object.keys(EnvStore.remoteVersions);
    for (let i = 0; i < names.length; i++) {
      const cat: string = EnvStore.remoteCategories[names[i]] ?? '';
      if (cat !== 'runtime') { continue; }
      const keyLower: string = names[i].toLowerCase();
      for (let j = 0; j < keywords.length; j++) {
        if (keyLower.indexOf(keywords[j]) >= 0) { return names[i]; }
      }
    }
    return lang;  // 无匹配则原样返回
  }

  /** 全部 tool 类包名（manifest 优先；未就绪回退种子目录——离线/慢网首屏秒开） */
  static toolNames(): string[] {
    if (EnvStore.remoteReady()) {
      const out: string[] = [];
      const names: string[] = Object.keys(EnvStore.remoteVersions);
      for (let i = 0; i < names.length; i++) {
        if (EnvStore.remoteCategories[names[i]] === 'tool') {
          out.push(names[i]);
        }
      }
      if (out.length > 0) { return out; }
    }
    return EnvStore.seedNames;
  }

  /** 某工具展示分类（种子映射，manifest 无分类字段） */
  static seedCategoryOf(pkg: string): string {
    return EnvStore.seedCategories[pkg] ?? '';
  }

  // ══════════════════ 本地（账本为源 + shell 纠正） ══════════════════

  /**
   * 刷新本地已装：读账本（权威）→ 异步纠正（active 链接 + 目录扫描补充外部安装）。
   * 账本读取本身是一次小文件 cat（元数据级）；纠正为两条批量简单命令。
   */
  static ensureLocal(force: boolean = false): void {
    if (!force && Date.now() - EnvStore.localAt < 5000) { return; }
    EnvStore.localAt = Date.now();

    // 1) 账本（我们保存的安装信息——判断是否存在的第一事实源）
    const minePkgs: Set<string> = new Set<string>();
    try {
      const records = DevEnvRegistry.all();
      for (let i = 0; i < records.length; i++) {
        minePkgs.add(records[i].name);
        EnvStore.mergeInstalled(records[i].name, [records[i].ver]);
      }
    } catch (_) {
    }

    // 2) 纠正：运行时包族 ∪ 账本包族，两条批量命令（目录清单 + current 链接）
    const pkgs: string[] = [];
    for (let i = 0; i < RUNTIME_PKGS.length; i++) {
      pkgs.push(RUNTIME_PKGS[i]);
    }
    minePkgs.forEach((p: string) => {
      if (pkgs.indexOf(p) < 0) { pkgs.push(p); }
    });
    EnvStore.correct(pkgs);
  }

  /** shell 纠正：目录存在性/外部安装补充 + active 链接（异步批量，完成后 bump） */
  private static correct(pkgs: string[]): void {
    if (EnvStore.correcting || pkgs.length === 0) { return; }
    EnvStore.correcting = true;
    const parts: string[] = [];
    for (let i = 0; i < pkgs.length; i++) {
      parts.push(`echo "${pkgs[i]}|$(ls '${HOME}/usr/local/${pkgs[i]}' 2>/dev/null | tr '\\n' ' ')|$(readlink '${HOME}/usr/local/${pkgs[i]}/current' 2>/dev/null)"`);
    }
    const script: string = parts.join('; ');
    const lines: string[] = [];
    DevTask.shell(script, (t: string, _e: boolean) => {
      lines.push(t);
    }, (_ok: boolean, _d: string) => {
      EnvStore.correcting = false;
      for (let i = 0; i < lines.length; i++) {
        const t: string = lines[i];
        const bar: number = t.indexOf('|');
        if (bar <= 0) { continue; }
        const pkg: string = t.substring(0, bar);
        const rest: string = t.substring(bar + 1);
        const bar2: number = rest.indexOf('|');
        if (bar2 < 0) { continue; }
        const dirsRaw: string = rest.substring(0, bar2).trim();
        const linkRaw: string = rest.substring(bar2 + 1).trim();

        // 目录 → 版本集合（过滤 current/隐藏项）
        const vers: string[] = [];
        const toks: string[] = dirsRaw.split(/\s+/);
        for (let j = 0; j < toks.length; j++) {
          const tk: string = toks[j].trim();
          if (tk !== '' && tk !== 'current' && !tk.startsWith('.')) {
            vers.push(tk);
          }
        }
        // active = 链接目标最后一段；悬挂（目标目录不在 vers）视为无活跃
        let active: string = '';
        if (linkRaw !== '') {
          const seg: string[] = linkRaw.split('/');
          const target: string = seg[seg.length - 1];
          if (vers.indexOf(target) >= 0) {
            active = target;
          }
        }
        const snap: InstalledSnapshot = { vers: vers, active: active, updatedAt: Date.now() };
        EnvStore.installedCache[pkg] = snap;
      }
      EnvStore.bump();
    });
  }

  /** 账本记录合入缓存（仅补充，不覆盖纠正结果） */
  private static mergeInstalled(pkg: string, vers: string[]): void {
    let snap: InstalledSnapshot | undefined = EnvStore.installedCache[pkg];
    if (snap === undefined) {
      snap = { vers: [], active: '', updatedAt: Date.now() };
      EnvStore.installedCache[pkg] = snap;
    }
    for (let i = 0; i < vers.length; i++) {
      if (snap.vers.indexOf(vers[i]) < 0) {
        snap.vers.push(vers[i]);
      }
    }
  }

  /** 安装完成登记（快照无该版本则合入）：装完立即 install 同版本应被
   *  already-installed 短路——否则重复走全量下载解压 */
  static noteInstalled(pkg: string, ver: string): void {
    EnvStore.mergeInstalled(pkg, [ver]);
    EnvStore.bump();
  }

  /** 卸载完成失效单包快照：账本已删而 installedCache 残留旧版本时，
   *  随后的 install 会误判 already installed（MCP 卸载→安装连击实证）；
   *  置空快照（ArkTS 无 delete）→ 后续按未装处理，ensureLocal 异步重扫回写 */
  static invalidateInstalled(pkg: string): void {
    EnvStore.installedCache[pkg] = { vers: [], active: '', updatedAt: Date.now() };
    EnvStore.bump();
  }

  /** 本地已装快照（同步读缓存；未初始化时触发一次 ensureLocal） */
  static installed(pkg: string): InstalledSnapshot {
    const snap: InstalledSnapshot | undefined = EnvStore.installedCache[pkg];
    if (snap !== undefined) {
      return snap;
    }
    EnvStore.ensureLocal();
    const fallback: InstalledSnapshot | undefined = EnvStore.installedCache[pkg];
    return fallback ?? { vers: [], active: '', updatedAt: 0 };
  }

  // ══════════════════ 二级包管理器清单（shell 获取） ══════════════════

  /** pip/npm/brew 清单（各一条简单命令异步；5 分钟缓存） */
  static refreshEco(force: boolean = false): void {
    if (!force && Date.now() - EnvStore.ecoAt < 5 * 60 * 1000 && EnvStore.ecoAt > 0) { return; }
    EnvStore.ecoAt = Date.now();
    const pyBin: string = `${HOME}/usr/local/bin`;  // python 别名链目录（新制品 bin 仅版本化实体）

    const pipLines: string[] = [];
    DevTask.shell(`PATH='${pyBin}':$PATH pip list --format=freeze 2>/dev/null | head -50`,
      (t: string, _e: boolean) => { pipLines.push(t); },
      (_ok: boolean, _d: string) => {
        EnvStore.ecoPip = pipLines;
        EnvStore.bump();
      });

    const npmLines: string[] = [];
    // npm 入口统一 node + npm-cli.js（bin/npm 软链不可靠）
    const npmCmd = `'${HOME}/usr/local/node/current/bin/node' '${HOME}/usr/local/node/current/lib/node_modules/npm/bin/npm-cli.js'`;
    DevTask.shell(`${npmCmd} list -g --depth=0 2>/dev/null | tail -n +2 | head -100`,
      (t: string, _e: boolean) => { npmLines.push(t); },
      (_ok: boolean, _d: string) => {
        EnvStore.ecoNpm = npmLines;
        EnvStore.bump();
      });

    const brewLines: string[] = [];
    // 仓库实体路径+密封环境+--versions（此前前缀软链会派生残骸 Cellar 读出脏数据；
    // fork 参数事实见 BrewEnv.brew() 注释）
    DevTask.shell(`${BrewEnv.env()} '${BrewEnv.brew()}' list --versions --formulae 2>/dev/null`,
      (t: string, _e: boolean) => { brewLines.push(t); },
      (_ok: boolean, _d: string) => {
        EnvStore.ecoBrew = brewLines.map((s: string): string => s.trim()).filter((s: string): boolean => s !== '');
        EnvStore.bump();
      });
  }

  static ecoPipList(): string[] { return EnvStore.ecoPip; }
  static ecoNpmList(): string[] { return EnvStore.ecoNpm; }
  static ecoBrewList(): string[] { return EnvStore.ecoBrew; }

  // ══════════════════ 手动刷新 ══════════════════

  /** 全量刷新（顶栏刷新按钮）：远程目录 + 本地纠正 + 二级包清单 */
  static refreshAll(): void {
    EnvStore.ensureRemote(true);
    EnvStore.ensureLocal(true);
    EnvStore.refreshEco(true);
    // 生态 catalog 同刷（⟳ 语义补全：跳过 loaded 守卫强制重拉并落盘）
    PyCatalogService.refresh();
    PyVersionsService.refresh();
    NpmCatalogService.refresh();
    ConanCatalogService.refresh();
  }
}
