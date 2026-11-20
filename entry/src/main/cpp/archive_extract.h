/**
 * archive_extract.h
 * C++ native 层 tar/gzip/xz 解压 (零 shell 依赖)
 *
 * 核心接口:
 *   extractArchive(archivePath, destDir, format) -> 0 成功 / 非0 错误码
 *
 * format 取值:
 *   "tar.gz" | "tgz"  -> gzip 流 (系统 zlib)
 *   "tar.xz" | "txz"  -> xz/lzma 流 (内置 decode-only liblzma)
 *   "tar"             -> 未压缩 tar
 *   "auto" | "" | NULL-> 按魔数嗅探 (1f 8b / FD 37 7A 58 5A)
 *
 * tar 解析器覆盖 POSIX ustar / GNU tar / BSD tar (pax) 常见产物:
 *   - 512 字节头 + octal size + 512 对齐填充
 *   - ustar prefix[155] 长路径拼接
 *   - GNU 长文件名/长链接 ('L'/'K') 与 pax 扩展头 ('x'/'g': path/linkpath/size)
 *   - 普通文件 / 目录 / 符号链接 / 硬链接, 跳过 fifo 与设备节点
 *   - GNU base-256 超大 size 字段
 *   - 路径安全: 拒绝 ".." 穿越与绝对路径, 拒绝经符号链接写逃逸
 */
#ifndef ARCHIVE_EXTRACT_H
#define ARCHIVE_EXTRACT_H

#ifdef __cplusplus
extern "C" {
#endif

/* extractArchive() 返回码 */
#define EXTRACT_OK 0                 /* 成功 */
#define EXTRACT_E_ARGS 1             /* 参数非法 / 未知格式 */
#define EXTRACT_E_OPEN 2             /* 打不开压缩包 */
#define EXTRACT_E_DEST 3             /* 创建目标目录失败 */
#define EXTRACT_E_FORMAT 4           /* 压缩包损坏 (校验和/头部/魔数) */
#define EXTRACT_E_TRUNCATED 5        /* 压缩包被截断 */
#define EXTRACT_E_PATH 6             /* 检测到不安全路径 (.. 穿越) */
#define EXTRACT_E_DECOMP 7           /* 解压流错误 (zlib/lzma data error) */
#define EXTRACT_E_XZ_UNSUPPORTED 8   /* 编译时未启用 liblzma, 不支持 tar.xz */
#define EXTRACT_E_ENTRY_UNSUPPORTED 9/* 条目不支持 (GNU 旧式稀疏文件等) */
#define EXTRACT_E_IO 10              /* 文件系统写入错误 */
#define EXTRACT_E_MEM 11             /* 内存不足 */

/**
 * 解压 tar/tar.gz/tar.xz 到 destDir (目录不存在则递归创建)
 *
 * @param archivePath 压缩包绝对路径
 * @param destDir     目标目录 (自动 mkdir -p)
 * @param format      见文件头注释, NULL 等同 "auto"
 * @return EXTRACT_OK 或错误码 (extractStrError 可转文案)
 */
int extractArchive(const char* archivePath, const char* destDir, const char* format);

/** 错误码转可读文案 (静态字符串) */
const char* extractStrError(int code);

/** 是否编译了 xz 支持 (liblzma) */
int extractXzSupported(void);

#ifdef __cplusplus
}
#endif

#endif // ARCHIVE_EXTRACT_H
