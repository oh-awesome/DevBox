/**
 * 包管理器数据模型定义 (v3 — Conan CLI 前端)
 * 数据源: CNB Conan 制品仓 (https://conan.cnb.cool/OpenHarmonyPCDeveloper/Conan)
 * 规范: docs/PKG_METADATA_SPEC.md
 */

/** 包分类常量 */
export const PkgCategories: string[] = [
  '语言运行时', '开发工具', '网络工具',
  '压缩/解压', '数据库', '加密/安全',
  '文本处理', '多媒体', '系统工具',
  '三方库', '其他',
];

/** 版本约束依赖条目 */
export interface PkgRequire {
  name: string;
  /** 版本约束, 如 ">=3.0.0", "<2.0.0", "*" */
  version: string;
}

/** 冲突条目 */
export interface PkgConflict {
  name: string;
  reason: string;
}

/** 命令条目 */
export interface PkgCommand {
  name: string;
  description: string;
  /** 命令在安装目录下的相对路径，提供时安装后自动创建 $HOME/usr/local/bin/{name} 软链接 */
  bin?: string;
}

/** 源码溯源 */
export interface PkgSourceTrace {
  url: string;
  sha256: string;
  adaptation_url?: string;
  adaptation_commit?: string;
}

/** 构建溯源 */
export interface PkgBuildTrace {
  system: string;
  compiler: string;
  linker?: string;
  runner?: string;
  os?: string;
  timestamp?: string;
  duration_sec?: number;
  patches_applied?: string[];
}

/** 测试阶段结果 */
export interface PkgTestPhase {
  status: string;
  total?: number;
  passed?: number;
  failed?: number;
  skipped?: number;
}

/** 测试报告摘要 */
export interface PkgTestReport {
  status: string;
  total?: number;
  passed?: number;
  failed?: number;
  skipped?: number;
  official_test?: PkgTestPhase;
  platform_test?: PkgTestPhase;
  baseline_test?: PkgTestPhase;
  security_scan?: PkgTestPhase;
}

/** 产物清单 */
export interface PkgArtifacts {
  bins?: string[];
  libs?: string[];
  includes?: string[];
}

/** 包列表展示用的精简模型 */
export interface PkgItem {
  name: string;
  version: string;
  category: string;
  summary: string;
  tags: string[];
  filename: string;
  size_compressed: number;
}

/** 包完整详情 (来自 conan show + ci-metadata.json) */
export interface PkgDetail {
  name: string;
  version: string;
  summary: string;
  description: string;
  homepage: string;
  license: string;
  category: string;
  tags: string[];
  arch: string[];
  maintainer: string;

  /** 硬依赖, 缺少则无法运行 */
  requires: PkgRequire[];
  /** 推荐依赖 */
  recommends: PkgRequire[];
  /** 冲突包 */
  conflicts: PkgConflict[];
  /** 替换的旧包名 */
  replaces: string[];
  /** 提供的虚拟包/能力名 */
  provides: string[];

  /** 源码地址 */
  source_url: string;
  /** 适配代码地址 */
  adaptation_url: string;

  /** 安装后的可执行命令 */
  commands: PkgCommand[];
  download_url: string;
  sha256: string;
  size_compressed: number;
  size_installed: number;

  /** 安装配置 */
  install: PkgInstall;

  changelog: PkgChangelog[];

  /** 源码溯源 */
  source_trace?: PkgSourceTrace;
  /** 构建溯源 */
  build_trace?: PkgBuildTrace;
  /** 测试报告摘要 */
  test_report?: PkgTestReport;
  /** 产物清单 */
  artifacts?: PkgArtifacts;
}

/** 安装配置 */
export interface PkgInstall {
  /** 安装模式: "standard" (默认) 或 "independent" */
  mode: string;
  /** independent 模式的安装路径模板, {version} 占位符 */
  prefix: string;
  /** independent 模式的活跃版本符号链接路径 */
  symlink: string;
  /** 安装后脚本路径 */
  post_script: string;
}

/** 变更日志条目 */
export interface PkgChangelog {
  version: string;
  date: string;
  message: string;
}

/** 包列表加载状态 */
export enum PkgLoadState {
  IDLE = 'idle',
  LOADING = 'loading',
  SUCCESS = 'success',
  ERROR = 'error',
}

// ─── 本地注册表模型 ──────────────────────────────────────────

/** 注册表中的单个已安装包记录 */
export interface RegistryEntry {
  version: string;
  /** Conan 引用: name/version@ohpcd/stable */
  conan_ref: string;
  install_time: string;
  /** 安装的文件列表 (相对于 INSTALL_DST) */
  files: string[];
  /** 依赖 */
  requires: PkgRequire[];
  /** 安装时从元数据保存的 commands，用于卸载时清理 bin 链接 */
  commands?: PkgCommand[];
}

/** 本地注册表 ($HOME/usr/local/.devbox/registry.json) */
export interface Registry {
  format_version: number;
  updated: string;
  packages: Record<string, RegistryEntry>;
}

// ─── 依赖解析结果 ──────────────────────────────────────────

/** 依赖检查结果 */
export interface DepCheckResult {
  /** 需要新安装的包 (name + version constraint) */
  toInstall: PkgRequire[];
  /** 需要升级的包 (name + current + required) */
  toUpgrade: PkgUpgrade[];
  /** 版本冲突列表 */
  conflicts: string[];
  /** 已满足的依赖 */
  satisfied: string[];
  /** 拓扑排序后的安装顺序 (包名列表, 依赖在前) */
  installOrder: string[];
}

/** 升级信息 */
export interface PkgUpgrade {
  name: string;
  currentVersion: string;
  requiredVersion: string;
}
