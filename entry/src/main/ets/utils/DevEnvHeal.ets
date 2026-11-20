/**
 * DevEnvHeal —— 自愈链（两应用启动/探测时各自执行的幂等操作）
 *
 * 协议对齐：PolarisTerm DEVENV-SPEC（§4.1-§4.3 / §5 / §7.3）
 * 红线 R7：任一方装卸后必须跑完整自愈链，保证对方探测到的环境自洽
 *
 * 自愈链（dvDetect 后按此顺序执行）：
 * 1. python 裸名别名（§4.1）
 * 2. pip console-scripts 补链（§4.2）
 * 3. npm/npx shim（§4.3）
 * 4. ensureConanEnv()（§7.3）
 * 5. ensureBrewPathLine()（§5）
 *
 * CA bundle 维护已移除（2026-11-17 产品决策）：~/.ohpcd-ca-bundle.pem 不再生成——
 * DevBox 自身 HTTPS 走系统 curl（-fsS 原生验证）与 request.agent，不依赖该文件；
 * 存量文件不删不动。
 */

import fs from '@ohos.file.fs';
import { DevEnvPaths } from './DevEnvPaths';
import { DiscoveryService } from './DiscoveryService';
import { execSync } from 'libdevbox_native.so';

const HOME = '/storage/Users/currentUser';

export class DevEnvHeal {

  private static startupRan: boolean = false;

  // ─── 1. Python 裸名别名（§4.1） ──────────────────────────

  /**
   * python3 → python3.12、pip3 → pip3.12
   * dvDetect 侧幂等补链：python 已装但裸名缺 → 补
   */
  // ─── 2. pip console-scripts 补链（§4.2） ─────────────────

  // ─── 3. npm/npx shim（§4.3） ─────────────────────────────

  /**
   * npm/npx 是 JS 脚本无 shebang 处理（toybox sh 经 PATH 调用时 $0 无路径）
   * 安装 node 后幂等写 shim：
   *   #!/system/bin/sh
   *   exec "<nodeBin>/node" "<npm-cli.js 绝对路径>" "$@"
   */
  // ─── 4. Conan2 三件套（§7.3） ────────────────────────────

  /**
   * detect 后幂等自愈 conan2 配置
   * settings_user.yml → "os:\n  HarmonyOS: null"（null！非 sub_systems）
   * profiles/default → HarmonyOS armv8 clang 12
   * remotes → ohpcd remote（无才加）
   */
  static ensureConanEnv(): void {
    const conanDir = `${HOME}/.conan2`;
    // 只在 conan 已装时才自愈
    if (!DevEnvHeal.fileExists(`${HOME}/usr/local/bin/conan`)) {
      return;
    }

    // settings_user.yml
    const settingsPath = `${conanDir}/settings_user.yml`;
    const settingsContent = `os:\n  HarmonyOS: null\n`;
    DevEnvHeal.idempotentWrite(settingsPath, settingsContent);

    // profiles/default
    const profileDir = `${conanDir}/profiles`;
    DevEnvHeal.ensureDir(profileDir);
    const profilePath = `${profileDir}/default`;
    const profileContent = `[settings]\nos=HarmonyOS\narch=armv8\ncompiler=clang\ncompiler.version=12\nbuild_type=Release\n`;
    DevEnvHeal.idempotentWrite(profilePath, profileContent);

    // remotes（conan remote add ohpcd ...）
    try {
      const r: string = execSync('conan remote list 2>/dev/null || echo ""');
      if (r.indexOf('ohpcd') < 0) {
        execSync(`conan remote add ohpcd ${DiscoveryService.latest().conanRemote} 2>/dev/null || true`);
      }
    } catch (_) {
    }
  }

  // ─── 工具方法 ─────────────────────────────────────────────

  private static dirExists(path: string): boolean {
    try {
      return fs.statSync(path).isDirectory();
    } catch (_) {
      return false;
    }
  }

  private static fileExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (_) {
      return false;
    }
  }

  private static ensureDir(path: string): void {
    try {
      if (!fs.accessSync(path)) {
        fs.mkdirSync(path, true);
      }
    } catch (_) {
    }
  }

  /** 链接有效性：自身存在（lstat 不跟链）且目标可达（stat 跟链）——悬空链接判 false */
  private static linkValid(path: string): boolean {
    try {
      fs.lstatSync(path);   // 自身存在（含悬空链接）
    } catch (_) {
      return false;         // 不存在
    }
    try {
      fs.statSync(path);    // 跟随链接：悬空会抛
      return true;
    } catch (_) {
      return false;         // 悬空
    }
  }

  private static createLink(target: string, linkPath: string): void {
    try {
      // 确保父目录存在
      const parent = linkPath.substring(0, linkPath.lastIndexOf('/'));
      DevEnvHeal.ensureDir(parent);
      // 已存在（含悬空链接）则先删——accessSync 跟链，悬空返回 false 会漏删导致 symlink EEXIST
      try {
        fs.lstatSync(linkPath);
        fs.unlinkSync(linkPath);
      } catch (_) {
      }
      fs.symlinkSync(target, linkPath);
    } catch (e) {
      console.error(`[DevEnvHeal] createLink ${linkPath} -> ${target}: ${e}`);
    }
  }

  private static chmodExecutable(path: string): void {
    // fs 无 chmod API，保留 shell
    try {
      execSync(`chmod +x '${path}'`);
    } catch (_) {
    }
  }

  /** 先读后写幂等（内容一致跳过，不整体覆盖对方写入的） */
  private static idempotentWrite(path: string, content: string): void {
    try {
      if (fs.accessSync(path)) {
        const existing: string = fs.readTextSync(path);
        if (existing.trim() === content.trim()) {
          return;
        }
      }
    } catch (_) {
    }
    DevEnvHeal.ensureDir(path.substring(0, path.lastIndexOf('/')));
    try {
      const wf = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(wf.fd, content);
      fs.closeSync(wf);
    } catch (e) {
      console.error(`[DevEnvHeal] idempotentWrite ${path}: ${e}`);
    }
  }

  /**
   * 构建子进程环境变量（dvSpawn 协议 §5.3）
   * 所有 GUI 任务通道统一使用
   */
  static buildChildEnv(): Record<string, string> {
    const env: Record<string, string> = {};
    // HOME 强制真实 HOME
    env['HOME'] = HOME;
    // PATH：brew + usr/local/bin + 动态扫描 current/bin
    const dirs: string[] = [`${HOME}/.harmonybrew/bin`, `${HOME}/usr/local/bin`];
    try {
      const localDir = `${HOME}/usr/local`;
      const entries = fs.listFileSync(localDir);
      for (const e of entries) {
        const currentBin = `${localDir}/${e}/current/bin`;
        if (DevEnvHeal.dirExists(currentBin)) {
          dirs.push(currentBin);
        }
      }
    } catch (_) {
    }
    env['PATH'] = dirs.join(':') + ':/usr/bin:/bin';
    // LD_LIBRARY_PATH 动态扫描
    const libDirs: string[] = [];
    try {
      const localDir = `${HOME}/usr/local`;
      const entries = fs.listFileSync(localDir);
      for (const e of entries) {
        const currentLib = `${localDir}/${e}/current/lib`;
        if (DevEnvHeal.dirExists(currentLib)) {
          libDirs.push(currentLib);
        }
      }
    } catch (_) {
    }
    if (libDirs.length > 0) {
      env['LD_LIBRARY_PATH'] = libDirs.join(':');
    }
    // HOMEBREW_USER_CONFIG_HOME 重定向（§5.3 第 5 条）
    env['HOMEBREW_USER_CONFIG_HOME'] = `${HOME}/.harmonybrew/config`;
    return env;
  }

}
