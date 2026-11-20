/**
 * DevDownload —— 下载专用通道（@ohos.request.agent 系统托管）
 *
 * 官方大文件下载方案：系统托管任务（退后台继续跑）、原生 Range 断点续传、
 * 真实进度回调（processed + sizes 字节级，不再解析 curl 终端输出）。
 * saveas 仅支持应用沙箱路径——先下到 cacheDir，完成后再由安装流程 cp 到工具链卷。
 */
import { request } from '@kit.BasicServicesKit';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';

interface SpeedSample {
  at: number;
  bytes: number;
}

export class DevDownload {

  /** 当前活跃下载的任务句柄（取消入口用：UI 取消→remove agent 任务→finish 链路走起来） */
  private static activeTid: string = '';
  /** 活跃下载的看门狗 timer（取消时清除——不清则 45s 后 stallAbort 重试，
   *  retry 的 attempt 闭包引用旧 DevEnvInstall 状态（op 已 null）→ null 断言崩溃——真机实证） */
  private static activeWatchdog: number = -1;
  /** 下载代际（每次 cancelCurrent/新 download 递增——旧代闭包检测到过时不再 retry，
   *  否则快速 取消→重装 时旧 retry 和新下载并行写同一文件 → 进度忽大忽小/文件损坏） */
  private static generation: number = 0;

  /** 取消当前下载（remove agent 任务；finish(false,'已取消') 经 completed/failed 之外路径
   *  由 attempt 的 onDone 触发——agent remove 后任务态查询见 cancelCurrent 实现） */
  static cancelCurrent(): boolean {
    // 代际+1：旧代 attempt 闭包的 retry/stallAbort 检测到过时即放弃（防并行下载）
    DevDownload.generation += 1;
    // 清看门狗（不清则 45s 后 stallAbort 重试→attempt 闭包 op=null→崩溃）
    if (DevDownload.activeWatchdog >= 0) {
      clearInterval(DevDownload.activeWatchdog);
      DevDownload.activeWatchdog = -1;
    }
    if (DevDownload.activeTid !== '') {
      const tid = DevDownload.activeTid;
      DevDownload.activeTid = '';
      try {
        request.agent.remove(tid);
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  private static ctx(): common.UIAbilityContext | null {
    const c = AppStorage.get<common.UIAbilityContext>('ui_context_ctx');
    return c ?? null;
  }

  static init(context: common.UIAbilityContext): void {
    AppStorage.setOrCreate('ui_context_ctx', context);
  }

  /**
   * 系统托管下载（断点续传 + 停滞看门狗 + 自动重试）。
   * onProgress(processed, total)：真实字节；onDone(ok, path)：完成（文件在 cacheDir 下）。
   *
   * 实证问题：request.agent 对部分 CDN 大文件会在数 MB 处静默挂起——
   * 无 failed 回调、无超时、任务永不结束（busyTask 卡死只能重启应用）。
   * 看门狗：进度停滞 N 秒 → remove 任务 → 自动重试（同 saveas 断点续传），
   * 连续 M 次停滞才报失败。所有路径保证 onDone 恰好一次。
   */
  static download(url: string, fileName: string,
    onProgress: (processed: number, total: number, etaSec: number) => void,
    onDone: (ok: boolean, msg: string) => void): void {
    DevDownload.generation += 1;   // 新一轮下载：旧代全部过时
    const STALL_TIMEOUT_MS = 45000;      // 进度停滞判定
    const MAX_RETRIES = 4;               // 停滞重试上限
    const RETRY_DELAY_MS = 2000;
    DevDownload.attempt(url, fileName, onProgress, onDone,
      0, 0, STALL_TIMEOUT_MS, MAX_RETRIES, RETRY_DELAY_MS);
  }

  private static attempt(url: string, fileName: string,
    onProgress: (processed: number, total: number, etaSec: number) => void,
    onDone: (ok: boolean, msg: string) => void,
    retry: number, lastProcessed: number,
    stallMs: number, maxRetries: number, retryDelay: number): void {
    const ctx = DevDownload.ctx();
    if (ctx === null) {
      onDone(false, '上下文未初始化');
      return;
    }
    const saveas = `${ctx.cacheDir}/${fileName}`;
    const config: request.agent.Config = {
      action: request.agent.Action.DOWNLOAD,
      url: url,
      saveas: saveas,
      gauge: true,        // 周期性进度通知（否则仅状态变化通知）
      overwrite: false,   // 断点续传：停滞重试时从上次字节继续
    };
    let finished = false;
    const myGen: number = DevDownload.generation;   // 闭包捕获当代——retry 前比对
    let processed = lastProcessed;
    const speedWindow: SpeedSample[] = [];   // ETA 滑动窗口
    let lastTick = Date.now();
    let watchdog: number = -1;

    const cleanupWatchdog = (): void => {
      if (watchdog >= 0) {
        clearInterval(watchdog);
        watchdog = -1;
      }
    };
    const finish = (ok: boolean, msg: string): void => {
      if (finished) { return; }
      finished = true;
      DevDownload.activeTid = '';
      DevDownload.activeWatchdog = -1;
      cleanupWatchdog();
      onDone(ok, msg);
    };
    const stallAbort = (): void => {
      // 先停自己的看门狗：interval 不清则每 5s 再触发 stallAbort → 每次都再生一个重试
      // attempt（各自又带新看门狗）→ agent 指数堆积——并行写同一 saveas → 进度横跳、
      // 文件损坏、某 attempt 触发 finish 清了 op/队列而其余 agent 成孤儿继续下载（真机实证：
      // 2GB 包停滞重试风暴 + 34ms 内 3 个进度值交错 + 取消后 UI 无任务但 Requestkit 仍在跑）
      cleanupWatchdog();
      if (task !== null) {
        try { request.agent.remove(task.tid); } catch (_) {
        }
      }
      if (retry < maxRetries && myGen === DevDownload.generation) {
        setTimeout(() => {
          if (myGen !== DevDownload.generation) { return; }   // 旧代：不再 retry
          DevDownload.attempt(url, fileName, onProgress, onDone,
            retry + 1, processed, stallMs, maxRetries, retryDelay);
        }, retryDelay);
      } else {
        finish(false, `下载停滞重试 ${maxRetries} 次仍无进展（已下载 ${(processed / 1048576).toFixed(1)}M）`);
      }
    };
    // 先声明再赋值（attempt 内 task 在 create 回调后可用）
    let task: request.agent.Task | null = null;

    // request.agent.create 在 saveas 已存在且 overwrite:false 时**同步抛** 13400001
    // （取消后残留断点文件等场景）→ 未 catch = JS crash = 闪退（faultlog 栈实证本行）。
    // .catch 只捕 promise 链异常，同步异常必须 try-catch
    try {
      request.agent.create(ctx, config).then((t: request.agent.Task) => {
      if (finished) {
        try { request.agent.remove(t.tid); } catch (_) {
        }
        return;
      }
      task = t;
      DevDownload.activeTid = `${t.tid}`;
      task.start((err) => {
        if (err) {
          finish(false, `启动失败 ${err.code}`);
          return;
        }
        // 停滞看门狗：STALL_TIMEOUT 无新字节 → 中止重试
        watchdog = setInterval(() => {
          if (Date.now() - lastTick > stallMs) {
            stallAbort();
          }
        }, 5000);
        DevDownload.activeWatchdog = watchdog;
      });
      t.on('progress', (pg: request.agent.Progress) => {
        if (finished) { return; }
        let total: number = 0;
        if (pg.sizes && pg.sizes.length > 0) {
          total = pg.sizes[0];
        }
        // ETA：3s 滑动窗口速率 → 剩余秒（eta 透传给调用方文案用）
        if (pg.processed > processed) {
          const sample: SpeedSample = { at: Date.now(), bytes: pg.processed };
          speedWindow.push(sample);
          while (speedWindow.length > 2 && Date.now() - speedWindow[0].at > 3000) {
            speedWindow.shift();
          }
          processed = pg.processed;
          lastTick = Date.now();
        }
        let etaSec: number = -1;
        if (total > 0 && speedWindow.length >= 2) {
          const span: number = speedWindow[speedWindow.length - 1].at - speedWindow[0].at;
          const bytes: number = speedWindow[speedWindow.length - 1].bytes - speedWindow[0].bytes;
          if (span > 300 && bytes > 0) {
            etaSec = Math.round((total - processed) / (bytes / (span / 1000)));
          }
        }
        onProgress(pg.processed, total, etaSec);
      });
      t.on('completed', () => {
        try { request.agent.remove(t.tid); } catch (_) {
        }
        finish(true, saveas);
      });
      t.on('failed', (pg: request.agent.Progress) => {
        try { request.agent.remove(t.tid); } catch (_) {
        }
        finish(false, `下载失败 state=${pg.state}（已下载 ${(processed / 1048576).toFixed(1)}M）`);
      });
    }).catch((e: object) => {
      finish(false, `创建任务失败 ${e}`);
    });
    } catch (e) {
      // create 同步异常（13400001 文件已存在等）——清残留后自动重试一次
      // （不重试则用户每次都报"缓存残留"——清完残留再 create 即通过）
      const saveas: string = config.saveas ?? '';
      if (saveas !== '') {
        try { fs.unlinkSync(saveas); } catch (_) {
        }
      }
      if (retry < maxRetries && myGen === DevDownload.generation) {
        setTimeout(() => {
          if (myGen !== DevDownload.generation) { return; }   // 旧代：不再 retry
          DevDownload.attempt(url, fileName, onProgress, onDone,
            retry + 1, 0, stallMs, maxRetries, retryDelay);
        }, retryDelay);
      } else {
        finish(false, `下载任务创建失败（${e}）——已清理缓存，请重试`);
      }
    }
  }
}
