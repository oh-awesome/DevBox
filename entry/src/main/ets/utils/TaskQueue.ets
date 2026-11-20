/**
 * TaskQueue —— 分组任务队列（P1：安装排队而非拒绝）
 *
 * 互斥组模型（按共享资源划分，组间真并发——见 2026-11-11 盘点）：
 *  - G1 运行时组（install/uninstall/switch）：共写 ~/usr/local 链接/PATH/shell_rc
 *  - G2 pip 组：并发写同 site-packages
 *  - G3 npm 组：并发写同全局 prefix
 * 队列内存态（重启清空）——安装幂等+断点续传在，可接受。
 */

import hilog from '@ohos.hilog';

export interface QueueTask {
  id: string;              // 唯一标识（展示/取消出队）
  label: string;           // 展示名（如 "安装 node 24.19.0"）
  group: string;           // 互斥组（'runtime'/'pip'/'npm'）
  run: () => void;         // 实际执行体（ claim 释放时由队列调度）
}

interface QueueState {
  running: QueueTask | null;
  pending: QueueTask[];
}

export class TaskQueue {

  private static groups: Map<string, QueueState> = new Map<string, QueueState>();

  /** 队列状态快照（顶栏面板渲染源；AppStorage 'task_queue_epoch' 变更通知） */
  static snapshot(): QueueTask[] {
    const out: QueueTask[] = [];
    TaskQueue.groups.forEach((st: QueueState, _k: string) => {
      if (st.running !== null) { out.push(st.running); }
      out.push(...st.pending);
    });
    return out;
  }

  /** 排队数（不含进行中） */
  static pendingCount(): number {
    let n: number = 0;
    TaskQueue.groups.forEach((st: QueueState, _k: string) => { n += st.pending.length; });
    return n;
  }

  /** 总任务数（进行中 + 排队）——badge 用：用户视角"队列中有几个任务" */
  static totalCount(): number {
    let n: number = 0;
    TaskQueue.groups.forEach((st: QueueState, _k: string) => {
      if (st.running !== null) { n += 1; }
      n += st.pending.length;
    });
    return n;
  }

  /** 入队/立即执行（组空闲时直跑）。返回排队位（0=立即执行） */
  static enqueue(task: QueueTask): number {
    const st = TaskQueue.state(task.group);
    // 同 id 去重（防连点重复排队/重复安装）：返回 -1 由调用方拒绝
    if (st.running !== null && st.running.id === task.id) { return -1; }
    for (let i = 0; i < st.pending.length; i++) {
      if (st.pending[i].id === task.id) { return -1; }
    }
    if (st.running === null) {
      st.running = task;
      TaskQueue.notify();
      hilog.info(0x0000, 'testTag', 'TaskQueue.run %{public}s (group=%{public}s)', task.id, task.group);
      task.run();
      return 0;
    }
    st.pending.push(task);
    TaskQueue.notify();
    hilog.info(0x0000, 'testTag', 'TaskQueue.queued %{public}s pos=%{public}d (group=%{public}s)',
      task.id, st.pending.length, task.group);
    return st.pending.length;
  }

  /** 当前任务完成（执行体 onDone 尾部调用：release 并调度队首） */
  static done(group: string): void {
    const st = TaskQueue.state(group);
    st.running = null;
    const next: QueueTask | undefined = st.pending.shift();
    if (next !== undefined) {
      st.running = next;
      TaskQueue.notify();
      hilog.info(0x0000, 'testTag', 'TaskQueue.advance %{public}s (group=%{public}s)', next.id, group);
      next.run();
    } else {
      TaskQueue.notify();
      hilog.info(0x0000, 'testTag', 'TaskQueue.idle (group=%{public}s)', group);
    }
  }

  /** 出队（排队中的任务取消；running 不受影响——运行中取消走各自 cancel 通道） */
  static dequeue(id: string): boolean {
    let removed = false;
    TaskQueue.groups.forEach((st: QueueState, _k: string) => {
      const before: number = st.pending.length;
      st.pending = st.pending.filter((t: QueueTask): boolean => t.id !== id);
      if (st.pending.length < before) { removed = true; }
    });
    if (removed) { TaskQueue.notify(); }
    return removed;
  }

  private static state(group: string): QueueState {
    let st: QueueState | undefined = TaskQueue.groups.get(group);
    if (st === undefined) {
      st = { running: null, pending: [] };
      TaskQueue.groups.set(group, st);
    }
    return st;
  }

  private static notify(): void {
    AppStorage.setOrCreate('task_queue_epoch', Date.now());
  }
}
