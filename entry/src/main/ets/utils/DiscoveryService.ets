/**
 * DiscoveryService — OHPCD 生态发现服务客户端
 *
 * 唯一平台入口：GET https://ohpcd.atomgit.com/api/discovery（4KB 静态化，网关挂了也活着）
 * 其余一切（manifest/制品/包源/目录）都从这份文档推导 + CDN 直连。
 *
 * 契约（DISCOVERY-INTEGRATION-GUIDE.md / DISCOVERY-PROTOCOL-SPEC）：
 * - protocol_version = 2；<2 拒收；>2 消费子集；未知字段/条目忽略
 * - 所有 URL 必须 https + host 后缀白名单；非法字段弃用回退
 * - 降级链：live → 上次缓存（preferences 持久化，带 updated_at）→ 种子快照（构建期已知值）
 * - ttl_seconds（3600）为建议刷新间隔；非 fresh 数据允许使用（带 stale 标记）
 *
 * 用法：EntryAbility/TrayAbility 启动时 resolve() 一次（各进程独立缓存）；
 * 消费方同步读 DiscoveryService.latest()（resolve 完成前返回种子值）。
 */
import { http } from '@kit.NetworkKit';
import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'Discovery';
const ENDPOINT: string = 'https://ohpcd.atomgit.com/api/discovery';
const PREF_FILE: string = 'discovery_prefs';
const PREF_KEY_DOC: string = 'doc';

/** host 后缀白名单（客户端永久硬编码仅此 + 发现端点 URL 本身；volces.com
 * 随 base 拼装通道日落移除 2026-11-13——blob 直连/发现字段均不指向 volces） */
const HOST_WHITELIST: string[] = [
  'cnb.cool', 'atomgit.com', 'npmjs.org', 'npmmirror.com',
  'pypi.org', 'tuna.tsinghua.edu.cn', 'aliyun.com', 'huaweicloud.com', 'tencent.com',
];

/** 单个包源（repositories 条目，仅保留 DevBox 用到的字段） */
export class DiscoveryRepo {
  id: string = '';
  kind: string = '';            // pip / npm / conan / maven / brew
  role: string = '';            // adapted / general / mirror
  recommended: boolean = false;
  registry: string = '';        // npm / maven
  remote: string = '';          // conan
  index: string = '';           // pip
  scope: string = '';           // npm scope（如 @ohos-ports）
  installScript: string = '';   // brew 安装脚本 URL（本地拼装 curl，S-P1-1 拒收完整命令）
  tapRepo: string = '';         // brew tap 仓库地址
  tapName: string = '';         // brew tap 名（如 harmony/ohos）
  tapCatalog: string = '';      // brew tap 目录 API
  corePackagesApi: string = ''; // brew 核心包目录 API（4714 个 formula，JWS）
  corePackagesUrl: string = ''; // brew 核心包网页浏览地址
  tapPackagesApi: string = '';  // 社区源 JWS 目录（平台上线后下发，与 core 同构）
  tapPackagesUrl: string = '';  // 社区源网页浏览地址
  trustedHost: string = '';     // pip trusted-host
}

/** 解析后的发现配置（种子值 = 2026-11-05 生产实测快照） */
export class DiscoveryConfig {
  // base 拼装通道已日落（2026-11-13）：发现服务承诺不再提供 base——
  // artifactBase/manifestPath 及 volces CDN 回落拼装一并移除，CDN 文件
  // 唯一取法 = catalog_fingerprints 的 blob_sha 直连（见 resolveCatalogUrl）
  bootstrapPath: string = 'bootstrap.sh';
  conanRemote: string = 'https://conan.cnb.cool/OpenHarmonyPCDeveloper/Conan/-/packages';
  brewInstallScript: string = "curl -fsSL 'https://harmonybrew.atomgit.com/install.sh' | zsh";
  brewCatalog: string = 'https://ohpcd.atomgit.com/api/brew/catalog';
  brewTapRepo: string = 'https://gitcode.com/OpenHarmonyPCDeveloper/ohpcd-brew.git';
  brewTapName: string = 'harmony/ohos';
  brewCoreApi: string = 'https://harmonybrew.atomgit.com/api/formula.jws.json';
  brewCoreUrl: string = 'https://harmonybrew.atomgit.com/packages/';
  /** 社区源 JWS 目录（发现字段 tap_packages_api 上线后自动接管；空=用种子） */
  tapPackagesApi: string = '';
  tapPackagesUrl: string = '';
  /** 社区源种子（降级兜底语义：发现服务不可达时用；发现字段永远优先） */
  tapPackagesSeed: string = 'https://ohpcd.atomgit.com/api/ohpcd-brew/formula.jws.json';
  /** 推荐序包源（runtimes 场景用） */
  pipRepos: DiscoveryRepo[] = [];
  npmRepos: DiscoveryRepo[] = [];
  mavenRegistry: string = 'https://maven.cnb.cool/openharmonypcdeveloper/maven';
  /** CDN 文件指纹（catalog_fingerprints：文件名 → sha256；两步拉取协议用） */
  fingerprints: Record<string, string> = {};
  /** blob SHA（catalog_fingerprints.blob_sha：有值 → raw.atomgit.com 新路径，快 100 倍） */
  blobShas: Record<string, string> = {};
  updatedAt: string = '1970-01-01T00:00:00Z';
  /** false = 种子/过期缓存（非本次 live 抓取） */
  fresh: boolean = false;

  recommendedPipIndex(): string {
    for (let i = 0; i < this.pipRepos.length; i++) {
      if (this.pipRepos[i].recommended && this.pipRepos[i].index !== '') {
        return this.pipRepos[i].index;
      }
    }
    return '';
  }

  recommendedPipTrustedHost(): string {
    for (let i = 0; i < this.pipRepos.length; i++) {
      if (this.pipRepos[i].recommended && this.pipRepos[i].trustedHost !== '') {
        return this.pipRepos[i].trustedHost;
      }
    }
    return '';
  }

  recommendedNpmRegistry(): string {
    for (let i = 0; i < this.npmRepos.length; i++) {
      if (this.npmRepos[i].recommended && this.npmRepos[i].registry !== '') {
        return this.npmRepos[i].registry;
      }
    }
    return '';
  }

  /** CDN 文件指纹（无该区块/未解析时返回空串 → 调用方走全量 .gz 拉取） */
  fingerprintOf(file: string): string {
    return this.fingerprints[file] ?? '';
  }

  /** blob SHA（有值 → raw.atomgit.com 新路径，快 100 倍；无值 → 旧路径） */
  blobShaOf(file: string): string {
    return this.blobShas[file] ?? '';
  }

  /**
   * 解析清单/目录文件的下载 URL（唯一取法 = blob_sha 直连）：
   * - 有 blob_sha → https://raw.atomgit.com/OpenHarmonyPCDeveloper/distro/blobs/{sha}/{filename}
   * - 无 blob_sha → 返回空串，调用方 fail loud（发现服务已承诺不再提供 base
   *   拼装通道——旧 volces CDN 回落路径已日落 2026-11-13）
   * 键名双试：discovery 的 catalog_fingerprints 键带 .gz 后缀（python-status.json.gz），
   * 调用方 fileKey 不带（python-status.json）。
   */
  resolveCatalogUrl(fileKey: string, filename: string): string {
    const sha = this.blobShas[fileKey] ?? this.blobShas[`${fileKey}.gz`] ?? '';
    if (sha !== '') {
      return `https://raw.atomgit.com/OpenHarmonyPCDeveloper/distro/blobs/${sha}/${filename}`;
    }
    return '';
  }
}

export class DiscoveryService {

  private static cfg: DiscoveryConfig = new DiscoveryConfig();
  private static resolvedAt: number = 0;
  private static resolving: boolean = false;
  private static readonly TTL_MS: number = 3600 * 1000;
  // resolve 在途时挂起的回调（完成时统一触发——不能用陈旧 cfg 立即回调：
  // 陈旧 blob_sha/字段会拉错文件污染磁盘缓存，真机实证：重装后 3.12.9
  // 常驻不消失、⟳ 才刷新）
  private static pending: ((cfg: DiscoveryConfig) => void)[] = [];

  /** 当前配置（resolve 完成前 = 种子值；带内存缓存，零开销） */
  static latest(): DiscoveryConfig {
    return DiscoveryService.cfg;
  }

  /**
   * 解析发现文档：内存新鲜 → 直接返回；否则 live 拉取 → 校验 → 更新内存 + 持久化；
   * 失败 → preferences 上次缓存；再失败 → 种子。onDone 可选（fire-and-forget 也合法）。
   */
  static resolve(ctx: common.Context | null, onDone: (cfg: DiscoveryConfig) => void = (_c) => {
  }): void {
    if (Date.now() - DiscoveryService.resolvedAt < DiscoveryService.TTL_MS && DiscoveryService.cfg.fresh) {
      onDone(DiscoveryService.cfg);
      return;
    }
    if (DiscoveryService.resolving) {
      DiscoveryService.pending.push(onDone);
      return;
    }
    DiscoveryService.resolving = true;
    try {
      const req: http.HttpRequest = http.createHttp();
      req.request(ENDPOINT, {
        method: http.RequestMethod.GET,
        connectTimeout: 8000,
        readTimeout: 10000,
      }).then((data: http.HttpResponse) => {
        DiscoveryService.resolving = false;
        req.destroy();
        if (data.responseCode !== 200) {
          DiscoveryService.fallback(ctx, onDone);
          return;
        }
        const parsed: DiscoveryConfig | null = DiscoveryService.parse(data.result as string);
        if (parsed === null) {
          DiscoveryService.fallback(ctx, onDone);
          return;
        }
        parsed.fresh = true;
        DiscoveryService.cfg = parsed;
        DiscoveryService.resolvedAt = Date.now();
        hilog.info(0x0000, TAG, 'discovery live OK (updated_at=%{public}s)', parsed.updatedAt);
        DiscoveryService.persist(ctx, data.result as string);
        onDone(parsed);
        DiscoveryService.flushPending(parsed);
      }).catch(() => {
        DiscoveryService.resolving = false;
        req.destroy();
        DiscoveryService.fallback(ctx, onDone);
      });
    } catch (_) {
      DiscoveryService.resolving = false;
      DiscoveryService.fallback(ctx, onDone);
    }
  }

  /** live 失败：读上次缓存；无缓存保持种子 */
  private static fallback(ctx: common.Context | null, onDone: (cfg: DiscoveryConfig) => void): void {
    if (ctx === null) {
      hilog.warn(0x0000, TAG, 'discovery live failed, using %{public}s', 'seed/memory');
      onDone(DiscoveryService.cfg);
      DiscoveryService.flushPending(DiscoveryService.cfg);
      return;
    }
    try {
      dataPreferences.getPreferences(ctx, PREF_FILE).then((pref: dataPreferences.Preferences) => {
        const raw: string = (pref.getSync(PREF_KEY_DOC, '') as string) ?? '';
        if (raw !== '') {
          const parsed: DiscoveryConfig | null = DiscoveryService.parse(raw);
          if (parsed !== null) {
            parsed.fresh = false;
            DiscoveryService.cfg = parsed;
            hilog.warn(0x0000, TAG, 'discovery using cached doc (updated_at=%{public}s)', parsed.updatedAt);
          }
        }
        onDone(DiscoveryService.cfg);
        DiscoveryService.flushPending(DiscoveryService.cfg);
      }).catch(() => {
        onDone(DiscoveryService.cfg);
        DiscoveryService.flushPending(DiscoveryService.cfg);
      });
    } catch (_) {
      onDone(DiscoveryService.cfg);
      DiscoveryService.flushPending(DiscoveryService.cfg);
    }
  }

  /** 触发在途期间挂起的回调（成功/fallback 终态后调用；防重入） */
  private static flushPending(cfg: DiscoveryConfig): void {
    const cbs = DiscoveryService.pending;
    DiscoveryService.pending = [];
    for (let i = 0; i < cbs.length; i++) {
      try { cbs[i](cfg); } catch (_) {
      }
    }
  }

  private static persist(ctx: common.Context | null, raw: string): void {
    if (ctx === null) {
      return;
    }
    try {
      dataPreferences.getPreferences(ctx, PREF_FILE).then((pref: dataPreferences.Preferences) => {
        pref.put(PREF_KEY_DOC, raw).then(() => {
          pref.flush();
        }).catch(() => {
        });
      }).catch(() => {
      });
    } catch (_) {
    }
  }

  /** 解析 + 契约校验；任何非法字段弃用（保留字段默认/种子值） */
  private static parse(raw: string): DiscoveryConfig | null {
    try {
      const doc: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      const ver: number = Number(`${doc['protocol_version']}`) || 0;
      if (ver < 2) {
        hilog.error(0x0000, TAG, 'protocol_version %{public}d < 2, reject', ver);
        return null;
      }
      const cfg: DiscoveryConfig = new DiscoveryConfig();
      cfg.updatedAt = (doc['updated_at'] as string) ?? cfg.updatedAt;

      // artifact_repo（base/manifest 拼装已日落——不再解析；bootstrap 保留）
      const ar: Record<string, Object> = (doc['artifact_repo'] as Record<string, Object>) ?? {};
      const bootstrap: string = (ar['bootstrap'] as string) ?? '';
      if (bootstrap !== '') {
        cfg.bootstrapPath = bootstrap.replace(/^\/+/, '');
      }

      // catalog_fingerprints（CDN 文件指纹：sha256 零流量 + blob_sha 新路径双轨）
      const fpsRaw: Record<string, Object> = (doc['catalog_fingerprints'] as Record<string, Object>) ?? {};
      const fpKeys: string[] = Object.keys(fpsRaw);
      for (let i = 0; i < fpKeys.length; i++) {
        const entry: Record<string, Object> = fpsRaw[fpKeys[i]] as Record<string, Object>;
        if (entry !== undefined && entry !== null) {
          cfg.fingerprints[fpKeys[i]] = (entry['sha256'] as string) ?? '';
          cfg.blobShas[fpKeys[i]] = (entry['blob_sha'] as string) ?? '';
        }
      }

      // repositories（数组）
      const reposRaw: Object[] = (doc['repositories'] as Object[]) ?? [];
      for (let i = 0; i < reposRaw.length; i++) {
        const r: Record<string, Object> = reposRaw[i] as Record<string, Object>;
        if (r === undefined || r === null) {
          continue;
        }
        const repo: DiscoveryRepo = new DiscoveryRepo();
        repo.id = (r['id'] as string) ?? '';
        repo.kind = (r['kind'] as string) ?? '';
        repo.role = (r['role'] as string) ?? '';
        repo.recommended = r['recommended'] === true;
        repo.registry = DiscoveryService.pickUrl(r, 'registry');
        repo.remote = DiscoveryService.pickUrl(r, 'remote');
        repo.index = DiscoveryService.pickUrl(r, 'index');
        repo.scope = (r['scope'] as string) ?? '';
        repo.installScript = DiscoveryService.pickUrl(r, 'install_script');
        // install_command 字段已拒收（审计 S-P1-1：完整 shell 命令绕过白名单）
        repo.tapRepo = DiscoveryService.pickUrl(r, 'tap_repo');
        repo.tapName = (r['tap_name'] as string) ?? '';
        repo.tapCatalog = DiscoveryService.pickUrl(r, 'tap_catalog');
        repo.corePackagesApi = DiscoveryService.pickUrl(r, 'core_packages_api');
        repo.corePackagesUrl = DiscoveryService.pickUrl(r, 'core_packages_url');
        repo.tapPackagesApi = DiscoveryService.pickUrl(r, 'tap_packages_api');
        repo.tapPackagesUrl = DiscoveryService.pickUrl(r, 'tap_packages_url');
        repo.trustedHost = (r['trusted_host'] as string) ?? '';
        if (repo.kind === 'pip') {
          cfg.pipRepos.push(repo);
        } else if (repo.kind === 'npm') {
          cfg.npmRepos.push(repo);
        } else if (repo.kind === 'conan' && repo.remote !== '' && cfg.conanRemote === '') {
          cfg.conanRemote = repo.remote;
        } else if (repo.kind === 'maven' && repo.recommended && repo.registry !== '') {
          cfg.mavenRegistry = repo.registry;
        } else if (repo.kind === 'brew') {
          // 安全（审计 S-P1-1）：install_command 是完整 shell 命令——发现服务
          // 被投毒可注入任意命令。改为只接受 install_script URL（过 validUrl
          // 白名单），由本地拼装 curl 命令——install_command 字段拒收
          // ⚠ S-P1-1 落地补完（2026-11-15 MCP brew_install 实测 exit 127 暴露）：
          //   此前只赋值裸 URL → sh "https://…" 文件不存在全灭。本地拼装
          //   curl 管道喂 zsh（brew 自检要求 zsh；密封 PATH 由调用方钉死）
          if (repo.installScript !== '') {
            cfg.brewInstallScript = `curl -fsSL '${repo.installScript}' | zsh`;
          }
          const catalog: string = DiscoveryService.pickUrl(r, 'catalog');
          if (catalog !== '') {
            cfg.brewCatalog = catalog; // catalog 优先，tap_catalog 兜底
          } else if (repo.tapCatalog !== '') {
            cfg.brewCatalog = repo.tapCatalog;
          }
          if (repo.tapRepo !== '') { cfg.brewTapRepo = repo.tapRepo; }
          if (repo.tapName !== '') { cfg.brewTapName = repo.tapName; }
          if (repo.corePackagesApi !== '') { cfg.brewCoreApi = repo.corePackagesApi; }
          if (repo.corePackagesUrl !== '') { cfg.brewCoreUrl = repo.corePackagesUrl; }
          if (repo.tapPackagesApi !== '') { cfg.tapPackagesApi = repo.tapPackagesApi; }
          if (repo.tapPackagesUrl !== '') { cfg.tapPackagesUrl = repo.tapPackagesUrl; }
        }
      }
      return cfg;
    } catch (e) {
      hilog.error(0x0000, TAG, 'parse failed: %{public}s', `${e}`);
      return null;
    }
  }

  /** 取字段值并做 https + 白名单校验，非法返回空串 */
  private static pickUrl(obj: Record<string, Object>, key: string): string {
    const v: string = (obj[key] as string) ?? '';
    return DiscoveryService.validUrl(v) ? v : '';
  }

  /** 契约：全 URL 必须 https + host 后缀在白名单内 + 路径字符白名单
   *  安全（审计 S-P1-2）：此前只查 scheme+host——路径部分可含空格/引号/
   *  shell 元字符逃逸（3 条注入链实证：pip -i / pip.conf 回环 / conan
   *  remote add）。追加全串字符校验：只允许 URL 安全字符集 */
  static validUrl(url: string): boolean {
    if (!url.startsWith('https://')) {
      return false;
    }
    // 全串字符白名单（URL 安全子集——拒绝空格/引号/分号/管道/反引号/美元符）
  if (!/^[A-Za-z0-9:/._?&=%,#\-]+$/.test(url)) {
      return false;
    }
    const noScheme: string = url.substring('https://'.length);
    const host: string = noScheme.split('/')[0].split(':')[0].toLowerCase();
    for (let i = 0; i < HOST_WHITELIST.length; i++) {
      if (host === HOST_WHITELIST[i] || host.endsWith('.' + HOST_WHITELIST[i])) {
        return true;
      }
    }
    return false;
  }
}
