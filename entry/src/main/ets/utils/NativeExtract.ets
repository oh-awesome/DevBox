/**
 * NativeExtract —— native 层 tar/gzip/xz 解压（零 shell 依赖）
 *
 * 底层是 libdevbox_native.so 里的 C++ 实现（archive_extract.cpp）：
 *   - tar 解析器覆盖 POSIX ustar / GNU tar / BSD tar (pax)
 *   - gzip 用系统 zlib，xz 用内置 decode-only liblzma
 *   - 在 native 工作线程执行，不阻塞 UI，不受环境 PATH/沙箱干扰
 *
 * ArkTS 调用：
 *   import { NativeExtract } from '../utils/NativeExtract';
 *   const ok = await NativeExtract.extractTarGz('/path/to/a.tar.gz', destDir);
 *
 * 错误码见 archive_extract.h（EXTRACT_* 宏），0 表示成功。
 */
import { extract } from 'libdevbox_native.so';

export class NativeExtract {

  /** 解压 .tar.gz / .tgz，成功返回 true */
  static async extractTarGz(archivePath: string, destDir: string): Promise<boolean> {
    const code: number = await extract(archivePath, destDir, 'tar.gz');
    if (code !== 0) {
      console.error(`[NativeExtract] tar.gz failed code=${code} src=${archivePath}`);
    }
    return code === 0;
  }

  /** 解压 .tar.xz / .txz，成功返回 true（native 未编入 liblzma 时返回 code=8） */
  static async extractTarXz(archivePath: string, destDir: string): Promise<boolean> {
    const code: number = await extract(archivePath, destDir, 'tar.xz');
    if (code !== 0) {
      console.error(`[NativeExtract] tar.xz failed code=${code} src=${archivePath}`);
    }
    return code === 0;
  }

  /**
   * 通用解压：format 取 'tar.gz' | 'tgz' | 'tar.xz' | 'txz' | 'tar' | 'auto'
   * 返回 native 错误码（0=成功）；'auto' 按魔数自动识别 gzip/xz/裸 tar
   */
  static async extract(archivePath: string, destDir: string, format: string = 'auto'): Promise<number> {
    return await extract(archivePath, destDir, format);
  }

  /** 错误码转文案（与 native 侧 extractStrError 保持一致） */
  static errorText(code: number): string {
    const map: Map<number, string> = new Map<number, string>([
      [0, 'ok'],
      [1, 'invalid arguments or unknown format'],
      [2, 'cannot open archive'],
      [3, 'cannot create destination directory'],
      [4, 'corrupt archive (bad header or checksum)'],
      [5, 'archive is truncated'],
      [6, 'unsafe entry path (path traversal)'],
      [7, 'decompression stream error'],
      [8, 'xz support not compiled in'],
      [9, 'unsupported archive entry'],
      [10, 'filesystem write error'],
      [11, 'out of memory']
    ]);
    return map.get(code) ?? 'unknown error';
  }
}
