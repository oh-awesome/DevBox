/**
 * OHPCD 制品仓客户端（数据层仅剩 URL 决策与展示格式化）。
 * 2026-11 起 manifest 全条目 url 化（3acec75）：制品下载唯一取法 = 条目 url 字段直连
 * （存量包为 volces 完整直链，已迁移包为 AtomGit Release 链接）。
 * base+manifest / base+path 拼装已移除（迁移前孤儿数据通道，真机实证拉到过旧配方）。
 */
export interface RepoVersion {
  ver: string;         // '24.19.0'（已剥 kernel 前缀）
  kernel: string;      // 'kernel-1.13.0'
  sizeBytes: number;
  sizeLabel: string;   // '53 MB'
  sha256: string;
  path: string;        // 'pkg/kernel-1.13.0/node/24.19.0/node-...tar.gz'（追溯用，不再拼 URL）
  provides: string;    // JSON 数组字符串 '["node","npm"]'
  url: string;         // 直链 URL（条目 url 字段；空 = 条目违规，安装时 fail loud）
  installRaw: string;      // install 段 JSON 原文
  activateRaw: string;     // activate 段 JSON 原文
  uninstallRaw: string;    // uninstall 段 JSON 原文
}

export class ArtifactsRepo {
  /** 制品 URL：条目 url 直连（唯一取法；空条目返回空，download 步 fail loud） */
  static resolveUrl(rv: RepoVersion): string {
    return rv.url;
  }

  static humanSize(bytes: number): string {
    if (bytes <= 0) {
      return '';
    }
    const kb: number = bytes / 1024;
    const mb: number = kb / 1024;
    if (mb >= 1024) {
      return `${(mb / 1024).toFixed(1)} GB`;
    }
    if (mb >= 10) {
      return `${Math.round(mb)} MB`;
    }
    if (mb >= 1) {
      return `${mb.toFixed(1)} MB`;
    }
    return `${Math.max(1, Math.round(kb))} KB`;
  }
}
