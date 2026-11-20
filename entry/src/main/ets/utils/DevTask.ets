/**
 * DevTask —— 工具链任务统一执行器（唯一机制，所有语言共用）
 *
 * 铁律（防主线程 6s 看门狗）：
 *  1. 凡触碰 /storage/Users 工具链卷的 IO（rm/tar/chmod/cp/下载）→ 一律 shell() 异步子进程
 *  2. 仅元数据探测（readlink/ls/test/cat 小文件）允许 probe() 同步（<50ms 级）
 * 装卸切换全部经 RuntimeMgr → DevEnvInstall/Uninstall/Switch → DevTask，
 * 任何语言不得自建同步 IO 通道。
 *
 * ⚠️ 句柄持有（关键修复 2026-11-05）：execAsync 返回的 napi_external 句柄被 GC 回收时
 * native 侧会立即 cancel 并 join 执行线程——不持有句柄的长命令（brew list/批量探测）
 * 会在 GC 时被中途杀掉，回调永不触发（页面无数据的根因）。必须持有到 onDone。
 */
import { execSync, execAsync, cancel } from 'libdevbox_native.so';

export class DevTask {

  /** 在途命令句柄集合（防 GC 取消，命令结束移除） */
  private static handles: Set<Object> = new Set<Object>();

  /** 可取消任务登记（tag → 句柄；P0b 包安装取消用：native cancel 杀进程 → onDone code≠0 收尾） */
  private static cancellables: Map<string, Object> = new Map<string, Object>();

  /** 异步执行卷上 IO（唯一允许执行写操作/大 IO 的通道） */
  static shell(cmd: string, onLine: (t: string, isErr: boolean) => void = (_t, _e) => {
  }, onDone: (ok: boolean, detail: string) => void): void {
    try {
      const handle: Object = execAsync(cmd, onLine, (code: number) => {
        DevTask.handles.delete(handle);
        onDone(code === 0, `exit ${code}`);
      });
      DevTask.handles.add(handle);
    } catch (e) {
      onDone(false, `${e}`);
    }
  }

  /** 可取消异步执行（tag 登记；cancel(tag) 杀进程；同一 tag 重跑自动顶替旧登记） */
  static shellCancellable(tag: string, cmd: string,
    onLine: (t: string, isErr: boolean) => void = (_t, _e) => {
    }, onDone: (ok: boolean, detail: string) => void): void {
    try {
      const handle: Object = execAsync(cmd, onLine, (code: number) => {
        DevTask.handles.delete(handle);
        DevTask.cancellables.delete(tag);
        onDone(code === 0, `exit ${code}`);
      });
      DevTask.handles.add(handle);
      DevTask.cancellables.set(tag, handle);
    } catch (e) {
      onDone(false, `${e}`);
    }
  }

  /** 取消登记过的任务（native cancel 杀进程；onDone 以 code≠0 收尾走取消文案） */
  static cancelTag(tag: string): boolean {
    const h: Object | undefined = DevTask.cancellables.get(tag);
    if (h === undefined) { return false; }
    DevTask.cancellables.delete(tag);
    try {
      cancel(h);
      return true;
    } catch (_) {
      return false;
    }
  }

  /** 同步探测（只读小操作专用；禁止用于写/大 IO） */
  static probe(cmd: string): string {
    try {
      return execSync(cmd) ?? '';
    } catch (_) {
      return '';
    }
  }
}
