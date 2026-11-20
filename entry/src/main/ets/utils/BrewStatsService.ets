/**
 * BrewStatsService —— HarmonyBrew 官方下载统计客户端（热门榜数据源）
 *
 * 端点形态（2026-11-12 实测）：`{base}/stats-{YYYYMMDD}.json` 按日文件，
 * 内容 = { formula名: 当日下载量 }（~539 个有记录，官方 /stats/ 网页同源，
 * 其自身就是 fetch 最近 7/30 天合并求和）。当日文件未生成时 404 → 跳过。
 *
 * 两级读取（发现服务指南精神）：发现文档暂无 stats 字段——种子 base 先行，
 * 将来平台下发（如 stats_base）后自动接管。
 * 聚合：默认 7 天（7 个 ~12KB 请求），可切 30 天；结果落盘缓存 + 24h TTL，
 * 失败保留旧数据（stale-while-revalidate）。
 */
import fs from '@ohos.file.fs';
import http from '@ohos.net.http';
import { common } from '@kit.AbilityKit';
import Logger from './Logger';

const TAG = 'BrewStats';
const STATS_SEED_BASE: string = 'https://harmonybrew.atomgit.com/stats/';
const CACHE_FILE = 'brew_stats_cache.json';   // {"ts":0,"days":7,"counts":{...}}
const TTL_MS: number = 24 * 60 * 60 * 1000;

export interface StatEntry {
  name: string;
  count: number;
}

export class BrewStatsService {
  private static counts: Record<string, number> = {};
  private static days: number = 7;
  private static ts: number = 0;
  private static fetching: boolean = false;
  private static filesDir: string = '';

  static init(ctx: common.Context | null | undefined, onReady?: () => void): void {
    if (ctx === null || ctx === undefined) { return; }
    BrewStatsService.filesDir = ctx.filesDir;
    BrewStatsService.readCache();
    if (onReady !== undefined && BrewStatsService.ts > 0) { onReady(); }
    if (BrewStatsService.needRefresh()) {
      BrewStatsService.refresh(BrewStatsService.days, onReady);
    }
  }

  /** 热门榜（下载量降序）；无统计时返回空数组（UI 隐藏热门视图） */
  static top(): StatEntry[] {
    const out: StatEntry[] = [];
    for (const k of Object.keys(BrewStatsService.counts)) {
      out.push({ name: k, count: BrewStatsService.counts[k] });
    }
    out.sort((a: StatEntry, b: StatEntry): number => b.count - a.count);
    return out;
  }

  static countOf(name: string): number {
    return BrewStatsService.counts[name] ?? 0;
  }

  static statDays(): number {
    return BrewStatsService.days;
  }

  static hasData(): boolean {
    return BrewStatsService.ts > 0 && Object.keys(BrewStatsService.counts).length > 0;
  }

  /** 切换 7/30 天回看（聚合口径变化 → 重拉） */
  static setDays(days: number, onDone?: () => void): void {
    if (days !== 7 && days !== 30) { return; }
    if (days === BrewStatsService.days && BrewStatsService.ts > 0) {
      if (onDone !== undefined) { onDone(); }
      return;
    }
    BrewStatsService.refresh(days, onDone);
  }

  private static needRefresh(): boolean {
    return BrewStatsService.ts === 0 || Date.now() - BrewStatsService.ts > TTL_MS;
  }

  private static readCache(): void {
    if (BrewStatsService.filesDir === '') { return; }
    try {
      const path: string = `${BrewStatsService.filesDir}/${CACHE_FILE}`;
      if (!fs.accessSync(path)) { return; }
      const m: Record<string, Object> = JSON.parse(fs.readTextSync(path)) as Record<string, Object>;
      BrewStatsService.ts = (m['ts'] as number) ?? 0;
      BrewStatsService.days = (m['days'] as number) ?? 7;
      BrewStatsService.counts = (m['counts'] as Record<string, number>) ?? {};
      Logger.info(TAG, `cache loaded: ${Object.keys(BrewStatsService.counts).length} formulas, ${BrewStatsService.days}d`);
    } catch (e) {
      Logger.warn(TAG, `readCache failed: ${e}`);
    }
  }

  /** 拉最近 N 天按日文件并聚合（404 日跳过；全部失败保留旧数据） */
  static refresh(days: number, onDone?: () => void): void {
    if (BrewStatsService.fetching || BrewStatsService.filesDir === '') {
      if (onDone !== undefined) { onDone(); }
      return;
    }
    BrewStatsService.fetching = true;
    const dates: string[] = [];
    const now: number = Date.now();
    for (let i = 1; i <= days; i++) {   // 当日文件未生成，从昨天起步（官方页面同逻辑）
      const d: Date = new Date(now - i * 24 * 60 * 60 * 1000);
      const y: number = d.getFullYear();
      const mo: string = String(d.getMonth() + 1).padStart(2, '0');
      const da: string = String(d.getDate()).padStart(2, '0');
      dates.push(`${y}${mo}${da}`);
    }
    const merged: Record<string, number> = {};
    let done: number = 0;
    let okDays: number = 0;
    for (let i = 0; i < dates.length; i++) {
      const url: string = `${STATS_SEED_BASE}stats-${dates[i]}.json`;
      try {
        const req = http.createHttp();
        req.request(url, {
          method: http.RequestMethod.GET,
          connectTimeout: 6000,
          readTimeout: 15000,
          expectDataType: http.HttpDataType.STRING,
        }).then((data: http.HttpResponse) => {
          req.destroy();
          done++;
          if (data.responseCode === 200) {
            try {
              const day: Record<string, Object> = JSON.parse(data.result as string) as Record<string, Object>;
              for (const k of Object.keys(day)) {
                merged[k] = (merged[k] ?? 0) + ((day[k] as number) ?? 0);
              }
              okDays++;
            } catch (_) {
            }
          }
          BrewStatsService.maybeFinish(done, dates.length, okDays, merged, days, onDone);
        }).catch(() => {
          req.destroy();
          done++;
          BrewStatsService.maybeFinish(done, dates.length, okDays, merged, days, onDone);
        });
      } catch (_) {
        done++;
        BrewStatsService.maybeFinish(done, dates.length, okDays, merged, days, onDone);
      }
    }
  }

  private static maybeFinish(done: number, total: number, okDays: number,
    merged: Record<string, number>, days: number, onDone?: () => void): void {
    if (done < total) { return; }
    BrewStatsService.fetching = false;
    if (okDays > 0 && Object.keys(merged).length > 0) {
      BrewStatsService.counts = merged;
      BrewStatsService.days = days;
      BrewStatsService.ts = Date.now();
      BrewStatsService.saveCache();
      Logger.info(TAG, `stats merged: ${Object.keys(merged).length} formulas over ${okDays}/${total} days (${days}d)`);
    } else {
      Logger.warn(TAG, 'stats all days failed, keep stale data');
    }
    if (onDone !== undefined) { onDone(); }
  }

  private static saveCache(): void {
    if (BrewStatsService.filesDir === '') { return; }
    try {
      const path: string = `${BrewStatsService.filesDir}/${CACHE_FILE}`;
      const body: Record<string, Object> = {};
      body['ts'] = BrewStatsService.ts;
      body['days'] = BrewStatsService.days;
      body['counts'] = BrewStatsService.counts;
      const f = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      try {
        fs.writeSync(f.fd, JSON.stringify(body));
      } finally {
        fs.closeSync(f.fd);
      }
    } catch (e) {
      Logger.warn(TAG, `saveCache failed: ${e}`);
    }
  }
}
