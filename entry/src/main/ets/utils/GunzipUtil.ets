/**
 * GunzipUtil —— 纯 ArkTS .gz 文件解压（零 shell 依赖）
 *
 * 使用 @ohos.zlib 的 GZip 流式 API（API 12+）：
 *   createGZipSync() → gzopen(path, 'rb') → gzread(buf) 循环 → gzeof() → gzclose()
 *
 * 注意：zlib.decompressFile 只支持 ZIP 格式，不支持 .gz；
 * 正确姿势是 GZip 流式逐块读取（与 C 的 gzread 一致）。
 */
import { zlib } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';

export class GunzipUtil {

  /**
   * 解压 .gz 文件为 UTF-8 字符串
   * @param gzPath 应用沙箱内的 .gz 文件路径
   * @returns 解压后的文本；失败返回空串
   */
  static async gunzipToString(gzPath: string): Promise<string> {
    // 非 gzip 内容（blob 端点对 .gz 后缀返回未压缩 JSON）：直接读文本，
    // 不赌 zlib 透明读行为（OHOS zlib.GZip 对非 gzip 文件行为未定义，失败即空串
    // → 新 manifest 永远应用不上，磁盘缓存永陈旧——真机实证）
    try {
      const fh: fs.File = fs.openSync(gzPath, fs.OpenMode.READ_ONLY);
      const head: ArrayBuffer = new ArrayBuffer(2);
      fs.readSync(fh.fd, head);
      fs.closeSync(fh.fd);
      const magic: Uint8Array = new Uint8Array(head);
      if (!(magic[0] === 0x1f && magic[1] === 0x8b)) {
        return fs.readTextSync(gzPath);
      }
    } catch (_) {
      return '';
    }
    const gz: zlib.GZip = zlib.createGZipSync();
    try {
      await gz.gzopen(gzPath, 'rb');

      const chunks: Uint8Array[] = [];
      const chunkSize: number = 65536; // 64KB
      let totalBytes: number = 0;

      while (true) {
        const buf: ArrayBuffer = new ArrayBuffer(chunkSize);
        const bytesRead: number = await gz.gzread(buf);
        if (bytesRead <= 0) { break; }
        // 拷贝（buf 会被下一轮复用）
        const copy: Uint8Array = new Uint8Array(bytesRead);
        copy.set(new Uint8Array(buf, 0, bytesRead));
        chunks.push(copy);
        totalBytes += bytesRead;
        const eof: number = await gz.gzeof();
        if (eof === 1) { break; }
      }

      await gz.gzclose();

      if (totalBytes === 0) { return ''; }

      // 拼接所有块
      const all: Uint8Array = new Uint8Array(totalBytes);
      let offset: number = 0;
      for (let i = 0; i < chunks.length; i++) {
        all.set(chunks[i], offset);
        offset += chunks[i].length;
      }

      return util.TextDecoder.create('utf-8').decodeToString(all);
    } catch (_) {
      try {
        await gz.gzclose();
      } catch (_) {
      }
      return '';
    }
  }

  /**
   * 便捷方法：下载 .gz → 解压 → 返回文本（http + gunzip 全程纯 ArkTS）
   * @param url .gz 文件 URL
   * @param tempGzPath 临时文件路径（应用沙箱）
   * @returns 解压后的文本；失败返回空串
   */
  static async downloadAndGunzip(url: string, tempGzPath: string): Promise<string> {
    try {
      // 下载
      const resp = await fetch(url);
      if (resp === null) { return ''; }
      // 写临时文件
      const f: fs.File = fs.openSync(tempGzPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(f.fd, resp);
      fs.closeSync(f.fd);
      // 解压
      return await GunzipUtil.gunzipToString(tempGzPath);
    } catch (_) {
      return '';
    }
  }
}

/** HTTP GET 二进制下载 */

async function fetch(url: string): Promise<ArrayBuffer | null> {
  return new Promise<ArrayBuffer | null>((resolve) => {
    try {
      const req = http.createHttp();
      req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 120000,
      }).then((data) => {
        req.destroy();
        if (data.responseCode === 200) {
          resolve(data.result as ArrayBuffer);
        } else {
          resolve(null);
        }
      }).catch(() => {
        req.destroy();
        resolve(null);
      });
    } catch (_) {
      resolve(null);
    }
  });
}
