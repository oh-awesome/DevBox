/**
 * archive_extract.cpp
 * C++ native 层 tar/gzip/xz 解压 (零 shell 依赖)
 *
 * 架构:
 *   DecompressStream: FILE* -> (zlib inflate / liblzma auto_decoder) -> 字节队列
 *   tar 解析器从字节队列顺序读取 512 字节头 + 数据块 (流式, 不整包缓存)
 *
 * 支持的 tar 方言:
 *   - POSIX ustar (含 prefix[155] 长路径)
 *   - GNU tar (magic "ustar ", 'L'/'K' 长名, base-256 大 size)
 *   - BSD tar / pax ('x'/'g' 扩展头: path/linkpath/size)
 *
 * 安全:
 *   - 拒绝 ".." 路径穿越, 剥离前导 '/'
 *   - 写文件用 O_NOFOLLOW; 目录组件被符号链接劫持时删除重建
 *   - 权限位只保留 0777 (剥离 setuid/setgid/sticky)
 */
#include "archive_extract.h"

#include <zlib.h>
#ifndef DEVBOX_HAVE_LZMA
#define DEVBOX_HAVE_LZMA 0
#endif
#if DEVBOX_HAVE_LZMA
#include <lzma.h>
#endif

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <map>
#include <string>
#include <vector>

#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <hilog/log.h>

#undef LOG_TAG
#define LOG_TAG "DevBox-Extract"

#define LOGI(fmt, ...) OH_LOG_INFO(LOG_APP, fmt, ##__VA_ARGS__)
#define LOGW(fmt, ...) OH_LOG_WARN(LOG_APP, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) OH_LOG_ERROR(LOG_APP, fmt, ##__VA_ARGS__)

namespace {

constexpr size_t kBlockSize = 512;       // tar 块大小
constexpr size_t kIoBufSize = 64 * 1024; // 解压读缓冲
constexpr size_t kMaxMetaSize = 1 << 20; // 'x'/'g'/'L'/'K' 扩展数据上限
constexpr size_t kMaxPath = 4096;

// ---------------------------------------------------------------------------
// 字节队列: 解压器产出 -> tar 解析器消费
// ---------------------------------------------------------------------------
class ByteQueue {
public:
    size_t size() const { return tail_ - head_; }
    bool empty() const { return head_ == tail_; }

    // 申请一段可写空间 (生产者)
    uint8_t* reserve(size_t n) {
        if (head_ > 0 && buf_.size() - tail_ < n) {
            compact();
        }
        if (buf_.size() - tail_ < n) {
            buf_.resize(tail_ + n);
        }
        return buf_.data() + tail_;
    }

    void commit(size_t n) { tail_ += n; }

    // 取出最多 n 字节 (消费者)
    size_t read(uint8_t* out, size_t n) {
        size_t k = std::min(n, size());
        if (k > 0) {
            memcpy(out, buf_.data() + head_, k);
            head_ += k;
            if (head_ == tail_) {
                head_ = tail_ = 0;
            }
        }
        return k;
    }

private:
    void compact() {
        size_t s = size();
        if (s > 0 && head_ > 0) {
            memmove(buf_.data(), buf_.data() + head_, s);
        }
        head_ = 0;
        tail_ = s;
    }

    std::vector<uint8_t> buf_;
    size_t head_ = 0;
    size_t tail_ = 0;
};

// ---------------------------------------------------------------------------
// 解压流: 原始压缩字节 -> 未压缩 tar 字节
// ---------------------------------------------------------------------------
class DecompressStream {
public:
    enum Comp { PLAIN, GZIP, XZ };

    ~DecompressStream() { deinit(); }

    bool init(FILE* f, Comp comp) {
        f_ = f;
        comp_ = comp;
        inBuf_.resize(kIoBufSize);
        if (comp == GZIP) {
            memset(&zs_, 0, sizeof(zs_));
            // windowBits 15+32: 自动识别 gzip / zlib 包装
            if (inflateInit2(&zs_, 15 + 32) != Z_OK) {
                fail(EXTRACT_E_MEM);
                return false;
            }
            zsInit_ = true;
#if DEVBOX_HAVE_LZMA
        } else if (comp == XZ) {
            memset(&ls_, 0, sizeof(ls_));
            // auto_decoder 同时接受 .xz 与 .lzma(alone); LZMA_CONCATENATED 支持多流拼接
            if (lzma_auto_decoder(&ls_, UINT64_MAX, LZMA_CONCATENATED) != LZMA_OK) {
                fail(EXTRACT_E_MEM);
                return false;
            }
            lsInit_ = true;
#endif
        }
        return true;
    }

    void deinit() {
        if (zsInit_) {
            inflateEnd(&zs_);
            zsInit_ = false;
        }
#if DEVBOX_HAVE_LZMA
        if (lsInit_) {
            lzma_end(&ls_);
            lsInit_ = false;
        }
#endif
    }

    /** 读最多 want 字节; 返回 >=0 实际字节数 (0=EOF), -1=错误 */
    ssize_t read(uint8_t* out, size_t want) {
        if (failed_) {
            return -1;
        }
        if (q_.empty() && !eof_) {
            pump();
        }
        if (failed_) {
            return -1;
        }
        return static_cast<ssize_t>(q_.read(out, want));
    }

    bool failed() const { return failed_; }
    int err() const { return err_; }

private:
    void fail(int code) {
        if (!failed_) {
            failed_ = true;
            err_ = code;
        }
    }

    void pump() { // 直到队列非空 / EOF / 出错
        int stall = 0;
        while (q_.empty() && !eof_ && !failed_) {
            fillOnce();
            if (!failed_ && q_.empty() && !eof_) {
                if (++stall > 64) { // 理论上不可达, 防御性兜底
                    fail(EXTRACT_E_DECOMP);
                    return;
                }
            } else {
                stall = 0;
            }
        }
    }

    void refillInput() {
        if (inEof_) {
            return;
        }
        size_t n = fread(inBuf_.data(), 1, inBuf_.size(), f_);
        if (n > 0) {
#if DEVBOX_HAVE_LZMA
            if (comp_ == XZ) {
                ls_.next_in = inBuf_.data();
                ls_.avail_in = n;
            } else
#endif
            if (comp_ == GZIP) {
                zs_.next_in = inBuf_.data();
                zs_.avail_in = static_cast<uInt>(n);
            }
        } else if (feof(f_)) {
            inEof_ = true;
        } else {
            fail(EXTRACT_E_IO); // 读错误
        }
    }

    void fillOnce() {
        if (comp_ == PLAIN) {
            uint8_t* dst = q_.reserve(kIoBufSize);
            size_t n = fread(dst, 1, kIoBufSize, f_);
            q_.commit(n);
            if (n == 0) {
                if (feof(f_)) {
                    eof_ = true;
                } else {
                    fail(EXTRACT_E_IO);
                }
            }
            return;
        }

        if (comp_ == GZIP) {
            if (zs_.avail_in == 0) {
                refillInput();
                if (failed_) {
                    return;
                }
                if (zs_.avail_in == 0 && inEof_ && !sawStreamEnd_) {
                    fail(EXTRACT_E_TRUNCATED); // 输入耗尽但 gzip 流未结束
                    return;
                }
            }
            uint8_t* dst = q_.reserve(kIoBufSize);
            zs_.next_out = dst;
            zs_.avail_out = static_cast<uInt>(kIoBufSize);
            int rc = inflate(&zs_, Z_NO_FLUSH);
            q_.commit(kIoBufSize - zs_.avail_out);

            if (rc == Z_OK || rc == Z_BUF_ERROR) {
                return; // 继续泵
            }
            if (rc == Z_STREAM_END) {
                sawStreamEnd_ = true;
                // 支持多成员 gzip (cat a.gz b.gz): 结束后若还有下个 gzip 魔数则重置
                if (zs_.avail_in == 0) {
                    refillInput();
                    if (failed_) {
                        return;
                    }
                }
                if (zs_.avail_in >= 2 && zs_.next_in != nullptr &&
                    zs_.next_in[0] == 0x1f && zs_.next_in[1] == 0x8b) {
                    if (inflateReset(&zs_) != Z_OK) {
                        fail(EXTRACT_E_DECOMP);
                        return;
                    }
                    sawStreamEnd_ = false;
                    return; // 继续解下一成员
                }
                eof_ = true; // 尾部零填充/垃圾视为结束
                return;
            }
            if (rc == Z_MEM_ERROR) {
                fail(EXTRACT_E_MEM);
            } else {
                // Z_DATA_ERROR / Z_NEED_DICT 等: 数据损坏
                fail(EXTRACT_E_DECOMP);
            }
            return;
        }

#if DEVBOX_HAVE_LZMA
        if (comp_ == XZ) {
            if (ls_.avail_in == 0) {
                refillInput();
                if (failed_) {
                    return;
                }
                if (ls_.avail_in == 0 && inEof_ && !sawStreamEnd_) {
                    fail(EXTRACT_E_TRUNCATED);
                    return;
                }
            }
            uint8_t* dst = q_.reserve(kIoBufSize);
            ls_.next_out = dst;
            ls_.avail_out = kIoBufSize;
            lzma_action action = (inEof_ && ls_.avail_in == 0) ? LZMA_FINISH : LZMA_RUN;
            lzma_ret rc = lzma_code(&ls_, action);
            q_.commit(kIoBufSize - ls_.avail_out);

            switch (rc) {
                case LZMA_OK:
                    return;
                case LZMA_STREAM_END:
                    sawStreamEnd_ = true;
                    eof_ = true; // CONCATENATED 模式下此即最终结束
                    return;
                case LZMA_BUF_ERROR:
                    if (ls_.avail_in == 0 && inEof_) {
                        fail(EXTRACT_E_TRUNCATED);
                    } else {
                        fail(EXTRACT_E_DECOMP);
                    }
                    return;
                case LZMA_FORMAT_ERROR:
                    fail(EXTRACT_E_FORMAT);
                    return;
                case LZMA_OPTIONS_ERROR:
                    // 使用了未编译的 filter (BCJ/delta 等)
                    fail(EXTRACT_E_ENTRY_UNSUPPORTED);
                    return;
                case LZMA_DATA_ERROR:
                    fail(EXTRACT_E_DECOMP);
                    return;
                case LZMA_MEM_ERROR:
                    fail(EXTRACT_E_MEM);
                    return;
                default:
                    fail(EXTRACT_E_DECOMP);
                    return;
            }
        }
#endif
        fail(EXTRACT_E_DECOMP); // 不可达
    }

    FILE* f_ = nullptr;
    Comp comp_ = PLAIN;
    std::vector<uint8_t> inBuf_;
    ByteQueue q_;
    bool inEof_ = false;      // 压缩输入已到 EOF
    bool eof_ = false;        // 解压输出已到 EOF
    bool sawStreamEnd_ = false;
    bool failed_ = false;
    int err_ = EXTRACT_OK;

    z_stream zs_{};
    bool zsInit_ = false;
#if DEVBOX_HAVE_LZMA
    lzma_stream ls_{};
    bool lsInit_ = false;
#endif
};

// ---------------------------------------------------------------------------
// tar 头部字段解析 (POSIX ustar + GNU 扩展)
// ---------------------------------------------------------------------------

/** 取 NUL 结尾字段 (返回时剥离填充 NUL) */
std::string fieldStr(const uint8_t* p, size_t len) {
    size_t n = 0;
    while (n < len && p[n] != 0) {
        n++;
    }
    return std::string(reinterpret_cast<const char*>(p), n);
}

/**
 * 解析数值字段: 八进制 (跳过前导空格/NUL);
 * 若首字节最高位为 1 则按 GNU base-256 大端解析 (支持 >8GB size)
 */
uint64_t parseTarNum(const char* p, size_t len) {
    if (len == 0) {
        return 0;
    }
    if ((static_cast<uint8_t>(p[0]) & 0x80) != 0) {
        uint64_t v = static_cast<uint8_t>(p[0]) & 0x7F;
        for (size_t i = 1; i < len; i++) {
            v = (v << 8) | static_cast<uint8_t>(p[i]);
        }
        return v;
    }
    uint64_t v = 0;
    size_t i = 0;
    while (i < len && (p[i] == ' ' || p[i] == '\0')) {
        i++;
    }
    for (; i < len; i++) {
        if (p[i] < '0' || p[i] > '7') {
            break; // 尾部空格/NUL/非法一律截断
        }
        v = v * 8 + static_cast<uint64_t>(p[i] - '0');
    }
    return v;
}

/** 校验头部长度 (chksum 字段按空格 0x20 计, 兼容 unsigned/signed 两种历史算法) */
bool verifyChecksum(const uint8_t* h) {
    uint64_t stored = parseTarNum(reinterpret_cast<const char*>(h) + 148, 8);
    if (stored == 0) {
        return false;
    }
    uint64_t uSum = 0;
    int64_t sSum = 0;
    for (size_t i = 0; i < kBlockSize; i++) {
        uint32_t b = (i >= 148 && i < 156) ? 32u : h[i];
        uSum += b;
        sSum += (i >= 148 && i < 156) ? 32 : static_cast<int8_t>(h[i]);
    }
    return stored == uSum || stored == static_cast<uint64_t>(sSum);
}

/** ustar 名字: POSIX (version "00") 才拼 prefix; GNU "ustar " 不用 prefix */
std::string ustarName(const uint8_t* h) {
    std::string name = fieldStr(h, 100);
    std::string magic = fieldStr(h + 257, 6);
    std::string version(reinterpret_cast<const char*>(h + 263), 2);
    bool posixUstar = (magic == "ustar") && (version == "00" || version == "01");
    if (posixUstar) {
        std::string prefix = fieldStr(h + 345, 155);
        if (!prefix.empty()) {
            name = prefix + "/" + name;
        }
    }
    return name;
}

// ---------------------------------------------------------------------------
// 路径安全
// ---------------------------------------------------------------------------

enum class PathKind { SAFE, ROOT, UNSAFE };

/**
 * 归一化 tar 条目名 -> 相对路径
 *   - 剥离前导 '/' (tar 惯例)
 *   - 丢弃空组件与 "." 组件
 *   - 拒绝 ".." 穿越与内嵌 NUL
 * 返回 ROOT 表示名字归一化后为根 ("." / "/" / "./"), 该条目跳过数据即可
 */
PathKind sanitizeRelPath(const std::string& raw, std::string& out) {
    out.clear();
    if (raw.empty() || raw.size() > kMaxPath) {
        return PathKind::UNSAFE;
    }
    if (raw.find('\0') != std::string::npos) {
        return PathKind::UNSAFE;
    }
    std::string joined;
    size_t start = 0;
    size_t n = raw.size();
    bool any = false;
    while (start <= n) {
        size_t slash = raw.find('/', start);
        if (slash == std::string::npos) {
            slash = n;
        }
        if (slash > start) {
            std::string comp = raw.substr(start, slash - start);
            if (comp == "..") {
                return PathKind::UNSAFE;
            }
            if (comp != ".") {
                if (any) {
                    joined += "/";
                }
                joined += comp;
                any = true;
            }
        }
        if (slash == n) {
            break;
        }
        start = slash + 1;
    }
    if (!any) {
        return PathKind::ROOT;
    }
    out = joined;
    return PathKind::SAFE;
}

// ---------------------------------------------------------------------------
// 文件系统操作 (POSIX)
// ---------------------------------------------------------------------------

bool writeAll(int fd, const uint8_t* buf, size_t n) {
    size_t off = 0;
    while (off < n) {
        ssize_t w = ::write(fd, buf + off, n - off);
        if (w < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        off += static_cast<size_t>(w);
    }
    return true;
}

/**
 * 递归 mkdir. 已存在组件必须是真实目录 (lstat 判断):
 * 若是符号链接/普通文件则删除重建, 防止解压内容经符号链接写出目标目录.
 */
bool makeDirs(const std::string& path) {
    if (path.empty()) {
        return false;
    }
    std::string cur;
    size_t i = 0;
    size_t n = path.size();
    if (path[0] == '/') {
        cur = "/";
        i = 1;
    }
    while (i <= n) {
        size_t slash = path.find('/', i);
        if (slash == std::string::npos) {
            slash = n;
        }
        if (slash > i) {
            if (!cur.empty() && cur != "/") {
                cur += "/";
            }
            cur += path.substr(i, slash - i);
            if (mkdir(cur.c_str(), 0755) != 0) {
                if (errno != EEXIST) {
                    return false;
                }
                struct stat st;
                if (lstat(cur.c_str(), &st) != 0) {
                    return false;
                }
                if (S_ISDIR(st.st_mode)) {
                    // 真实目录, 继续下一层
                } else if (unlink(cur.c_str()) == 0 && mkdir(cur.c_str(), 0755) == 0) {
                    // 符号链接/文件劫持 -> 重建为目录
                } else {
                    return false;
                }
            }
        }
        if (slash == n) {
            break;
        }
        i = slash + 1;
    }
    return true;
}

/** O_NOFOLLOW 打开 (目标已是符号链接则先删再开, 防逃逸写) */
int openFileNoSymlink(const std::string& path) {
    int flags = O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW;
    int fd = ::open(path.c_str(), flags, 0600);
    if (fd < 0 && (errno == ELOOP || errno == EMLINK)) {
        if (unlink(path.c_str()) == 0) {
            fd = ::open(path.c_str(), flags, 0600);
        }
    }
    return fd;
}

void setMtime(const std::string& path, uint64_t mtime, bool nofollow) {
    if (mtime > 0x3FFFFFFFFFULL) { // ~公元 55844 年, 防溢出
        mtime = 0;
    }
    struct timespec ts[2];
    ts[0].tv_sec = static_cast<time_t>(mtime);
    ts[0].tv_nsec = 0;
    ts[1] = ts[0];
    utimensat(AT_FDCWD, path.c_str(), ts, nofollow ? AT_SYMLINK_NOFOLLOW : 0);
}

/** 普通文件权限: 只保留 0777, 0 时给默认 0644 */
inline mode_t entryFileMode(uint32_t rawMode) {
    mode_t m = static_cast<mode_t>(rawMode & 0777); // 剥离 setuid/setgid/sticky
    return m != 0 ? m : static_cast<mode_t>(0644);
}

/** 目录权限: 只保留 0777, 0 时给默认 0755 */
inline mode_t entryDirMode(uint32_t rawMode) {
    mode_t m = static_cast<mode_t>(rawMode & 0777);
    return m != 0 ? m : static_cast<mode_t>(0755);
}

// ---------------------------------------------------------------------------
// tar 条目数据处理
// ---------------------------------------------------------------------------

/** 从流中读满 n 字节; 返回 0=OK 1=起始即EOF 2=截断 -1=流错误 */
int readFull(DecompressStream& s, uint8_t* buf, size_t n, size_t* got) {
    *got = 0;
    while (*got < n) {
        ssize_t r = s.read(buf + *got, n - *got);
        if (r < 0) {
            return -1;
        }
        if (r == 0) {
            return *got == 0 ? 1 : 2;
        }
        *got += static_cast<size_t>(r);
    }
    return 0;
}

/** 丢弃 512 对齐填充 (size 之后); 最后一个条目允许直接 EOF, 宽容收尾 */
bool skipPad(DecompressStream& s, uint64_t size, int& err) {
    uint64_t pad = (kBlockSize - (size % kBlockSize)) % kBlockSize;
    uint8_t buf[kBlockSize];
    while (pad > 0) {
        ssize_t r = s.read(buf, static_cast<size_t>(pad));
        if (r < 0) {
            err = s.err();
            return false;
        }
        if (r == 0) {
            break; // 最后一个条目后无填充直接 EOF: 宽容
        }
        pad -= static_cast<uint64_t>(r);
    }
    return true;
}

/** 丢弃 size 字节数据 + 512 对齐填充 */
bool skipEntryDataAndPad(DecompressStream& s, uint64_t size, int& err) {
    uint64_t rem = size;
    uint8_t buf[kIoBufSize];
    while (rem > 0) {
        size_t want = rem > sizeof(buf) ? sizeof(buf) : static_cast<size_t>(rem);
        ssize_t r = s.read(buf, want);
        if (r < 0) {
            err = s.err();
            return false;
        }
        if (r == 0) {
            err = EXTRACT_E_TRUNCATED;
            return false;
        }
        rem -= static_cast<uint64_t>(r);
    }
    return skipPad(s, size, err);
}

/** 流式写出普通文件 (数据从解压流读取, 不缓存整文件) */
bool writeEntryFile(DecompressStream& s, const std::string& target, uint64_t size,
                    uint32_t rawMode, uint64_t mtime, int& err) {
    int fd = openFileNoSymlink(target);
    if (fd < 0) {
        err = EXTRACT_E_IO;
        return false;
    }
    uint64_t rem = size;
    uint8_t buf[kIoBufSize];
    while (rem > 0) {
        size_t want = rem > sizeof(buf) ? sizeof(buf) : static_cast<size_t>(rem);
        ssize_t r = s.read(buf, want);
        if (r < 0) {
            err = s.err();
            ::close(fd);
            return false;
        }
        if (r == 0) {
            err = EXTRACT_E_TRUNCATED;
            ::close(fd);
            return false;
        }
        if (!writeAll(fd, buf, static_cast<size_t>(r))) {
            err = EXTRACT_E_IO;
            ::close(fd);
            return false;
        }
        rem -= static_cast<uint64_t>(r);
    }
    ::close(fd);
    chmod(target.c_str(), entryFileMode(rawMode));
    setMtime(target, mtime, false);
    return true;
}

/** 解析 pax 记录 "len key=value\n" */
void parsePaxRecords(const uint8_t* d, size_t n, std::map<std::string, std::string>& kv) {
    size_t pos = 0;
    while (pos < n) {
        size_t digStart = pos;
        size_t digEnd = pos;
        while (digEnd < n && d[digEnd] >= '0' && d[digEnd] <= '9') {
            digEnd++;
        }
        if (digEnd == digStart || digEnd >= n || d[digEnd] != ' ') {
            return; // 尾部残缺记录: 忽略
        }
        uint64_t len = 0;
        for (size_t i = digStart; i < digEnd; i++) {
            len = len * 10 + static_cast<uint64_t>(d[i] - '0');
        }
        if (len < (digEnd - digStart) + 2 || digStart + len > n) {
            return; // 非法长度: 忽略剩余
        }
        size_t bodyStart = digEnd + 1;
        size_t bodyEnd = digStart + static_cast<size_t>(len) - 1; // 末尾 '\n'
        std::string rec(reinterpret_cast<const char*>(d) + bodyStart, bodyEnd - bodyStart);
        size_t eq = rec.find('=');
        if (eq != std::string::npos) {
            kv[rec.substr(0, eq)] = rec.substr(eq + 1);
        }
        pos = digStart + static_cast<size_t>(len);
    }
}

std::string trimNul(const std::vector<uint8_t>& v) {
    size_t n = 0;
    while (n < v.size() && v[n] != 0) {
        n++;
    }
    return std::string(reinterpret_cast<const char*>(v.data()), n);
}

// ---------------------------------------------------------------------------
// tar 主循环
// ---------------------------------------------------------------------------
struct ExtractStats {
    uint64_t files = 0;
    uint64_t dirs = 0;
    uint64_t links = 0;
    uint64_t skipped = 0;
};

int extractTarStream(DecompressStream& s, const std::string& destRoot, ExtractStats& st) {
    std::string gPath, gLink;        // pax 全局覆盖 ('g')
    std::string ePath, eLink, eSize; // pax 单条覆盖 ('x')
    std::string longName, longLink;  // GNU 'L'/'K'
    std::vector<uint8_t> meta;
    uint8_t hdr[kBlockSize];

    for (;;) {
        size_t got = 0;
        int rc = readFull(s, hdr, kBlockSize, &got);
        if (rc == 1) {
            break; // 干净 EOF
        }
        if (rc == -1) {
            return s.err();
        }
        if (rc == 2) {
            return EXTRACT_E_TRUNCATED;
        }

        // 全零块 = 归档结束标记; 连续吞零块.
        // 若零块之后还有有效头 (拼接归档 cat a.tar.gz b.tar.gz / --ignore-zeros 语义)
        // 则继续解压; EOF 或垃圾则干净结束.
        bool allZero = true;
        for (size_t i = 0; i < kBlockSize; i++) {
            if (hdr[i] != 0) {
                allZero = false;
                break;
            }
        }
        if (allZero) {
            bool haveMore = false;
            for (;;) {
                int r2 = readFull(s, hdr, kBlockSize, &got);
                if (r2 != 0) {
                    break; // EOF: 干净结束
                }
                bool z2 = true;
                for (size_t i = 0; i < kBlockSize; i++) {
                    if (hdr[i] != 0) {
                        z2 = false;
                        break;
                    }
                }
                if (!z2) {
                    if (verifyChecksum(hdr)) {
                        haveMore = true; // 拼接成员的有效头, 已读入 hdr
                    }
                    break; // 无效头 (尾部垃圾): 结束
                }
                // 零块: 继续吞
            }
            if (!haveMore) {
                break;
            }
        }

        if (!verifyChecksum(hdr)) {
            LOGE("tar header checksum mismatch");
            return EXTRACT_E_FORMAT;
        }

        char typeflag = static_cast<char>(hdr[156]);
        uint64_t size = parseTarNum(reinterpret_cast<const char*>(hdr) + 124, 12);
        uint32_t rawMode = static_cast<uint32_t>(
            parseTarNum(reinterpret_cast<const char*>(hdr) + 100, 8));
        uint64_t mtime = parseTarNum(reinterpret_cast<const char*>(hdr) + 136, 12);

        // ---- 元数据头: 处理后继续读真实条目 ----
        if (typeflag == 'L' || typeflag == 'K' || typeflag == 'x' || typeflag == 'g') {
            if (size > kMaxMetaSize) {
                return EXTRACT_E_FORMAT;
            }
            meta.resize(static_cast<size_t>(size));
            rc = readFull(s, meta.data(), meta.size(), &got);
            if (rc != 0) {
                return rc == -1 ? s.err() : EXTRACT_E_TRUNCATED;
            }
            // 消耗 512 对齐填充
            {
                int padErr = EXTRACT_OK;
                if (!skipPad(s, size, padErr)) {
                    return padErr;
                }
            }

            if (typeflag == 'L') {
                longName = trimNul(meta);
            } else if (typeflag == 'K') {
                longLink = trimNul(meta);
            } else {
                std::map<std::string, std::string> kv;
                parsePaxRecords(meta.data(), meta.size(), kv);
                for (const auto& it : kv) {
                    if (it.first.rfind("GNU.sparse.", 0) == 0 ||
                        it.first.rfind("SCHILY.sparse.", 0) == 0) {
                        LOGE("sparse entries unsupported: %{public}s", it.first.c_str());
                        return EXTRACT_E_ENTRY_UNSUPPORTED;
                    }
                }
                if (typeflag == 'x') {
                    ePath = kv.count("path") != 0 ? kv["path"] : "";
                    eLink = kv.count("linkpath") != 0 ? kv["linkpath"] : "";
                    eSize = kv.count("size") != 0 ? kv["size"] : "";
                } else { // 'g'
                    if (kv.count("path") != 0) {
                        gPath = kv["path"];
                    }
                    if (kv.count("linkpath") != 0) {
                        gLink = kv["linkpath"];
                    }
                }
            }
            continue;
        }

        // ---- 组装最终名字/链接目标 (优先级: pax x > GNU L > pax g > 头部) ----
        std::string name = !ePath.empty() ? ePath
                          : !longName.empty() ? longName
                          : !gPath.empty() ? gPath
                          : ustarName(hdr);
        std::string link = !eLink.empty() ? eLink
                           : !longLink.empty() ? longLink
                           : !gLink.empty() ? gLink
                           : fieldStr(hdr + 157, 100);
        if (!eSize.empty()) {
            size = strtoull(eSize.c_str(), nullptr, 10); // pax 覆盖 (>8GB)
        }

        // ---- 路径安全 ----
        std::string rel;
        PathKind pk = sanitizeRelPath(name, rel);
        if (pk == PathKind::UNSAFE) {
            LOGE("unsafe entry path rejected: %{public}s", name.c_str());
            return EXTRACT_E_PATH;
        }
        if (pk == PathKind::ROOT) {
            // "./" 之类根条目: 只吞数据
            int err = EXTRACT_OK;
            if (!skipEntryDataAndPad(s, size, err)) {
                return err;
            }
            st.skipped++;
            ePath.clear(); eLink.clear(); eSize.clear();
            longName.clear(); longLink.clear();
            continue;
        }
        std::string target = destRoot + "/" + rel;
        if (target.size() >= kMaxPath) {
            LOGE("entry path too long: %{public}s", rel.c_str());
            return EXTRACT_E_PATH;
        }

        int err = EXTRACT_OK;
        bool ok = true;
        bool dataConsumed = false;

        switch (typeflag) {
            case '0':   // 普通文件
            case '\0':
            case '7': { // contiguous (当普通文件)
                std::string parent = target.substr(0, target.rfind('/'));
                if (!makeDirs(parent)) {
                    ok = false;
                    err = EXTRACT_E_IO;
                    break;
                }
                ok = writeEntryFile(s, target, size, rawMode, mtime, err);
                dataConsumed = true;
                if (ok) {
                    st.files++;
                }
                break;
            }
            case '5': { // 目录
                if (!makeDirs(target)) {
                    ok = false;
                    err = EXTRACT_E_IO;
                    break;
                }
                chmod(target.c_str(), entryDirMode(rawMode));
                setMtime(target, mtime, false);
                st.dirs++;
                break;
            }
            case '2': { // 符号链接
                std::string parent = target.substr(0, target.rfind('/'));
                if (!makeDirs(parent)) {
                    ok = false;
                    err = EXTRACT_E_IO;
                    break;
                }
                struct stat stt;
                if (lstat(target.c_str(), &stt) == 0 && unlink(target.c_str()) != 0) {
                    ok = false;
                    err = EXTRACT_E_IO;
                    break;
                }
                if (link.empty() || symlink(link.c_str(), target.c_str()) != 0) {
                    LOGE("symlink create failed: %{public}s -> %{public}s",
                         target.c_str(), link.c_str());
                    ok = false;
                    err = EXTRACT_E_IO;
                    break;
                }
                setMtime(target, mtime, true);
                st.links++;
                break;
            }
            case '1': { // 硬链接
                std::string parent = target.substr(0, target.rfind('/'));
                if (!makeDirs(parent)) {
                    ok = false;
                    err = EXTRACT_E_IO;
                    break;
                }
                std::string lrel;
                if (sanitizeRelPath(link, lrel) != PathKind::SAFE) {
                    LOGE("unsafe hardlink target rejected: %{public}s", link.c_str());
                    ok = false;
                    err = EXTRACT_E_PATH;
                    break;
                }
                std::string src = destRoot + "/" + lrel;
                if (::link(src.c_str(), target.c_str()) == 0) {
                    setMtime(target, mtime, false);
                    st.links++;
                    break;
                }
                int lerr = errno;
                struct stat stt;
                if (lerr == EEXIST && lstat(target.c_str(), &stt) == 0 &&
                    unlink(target.c_str()) == 0 && ::link(src.c_str(), target.c_str()) == 0) {
                    setMtime(target, mtime, false);
                    st.links++;
                    break;
                }
                if (size > 0 && (lerr == ENOENT || lerr == EPERM || lerr == EXDEV ||
                                 lerr == EMLINK)) {
                    // 个别打包器给硬链接附带数据: 落盘为普通文件
                    ok = writeEntryFile(s, target, size, rawMode, mtime, err);
                    dataConsumed = true;
                    if (ok) {
                        st.files++;
                    }
                    break;
                }
                LOGE("hardlink create failed (errno=%{public}d): %{public}s", lerr, rel.c_str());
                ok = false;
                err = EXTRACT_E_IO;
                break;
            }
            case 'S': // GNU 旧式稀疏文件: 布局复杂, 明确不支持
                LOGE("GNU old-style sparse entry unsupported: %{public}s", rel.c_str());
                return EXTRACT_E_ENTRY_UNSUPPORTED;
            case '3': // char 设备
            case '4': // block 设备
            case '6': // FIFO (沙箱内无法 mknod, 跳过)
            case 'V': // 卷标
            case 'M': // 多卷延续
            default:  // 未知类型: 容忍并跳过
                st.skipped++;
                break;
        }

        if (!ok) {
            return err;
        }
        if (dataConsumed) {
            // writeEntryFile 只消费了 size 字节, 还需吞掉 512 对齐填充
            if (!skipPad(s, size, err)) {
                LOGE("entry padding truncated: %{public}s", rel.c_str());
                return err;
            }
        } else {
            if (!skipEntryDataAndPad(s, size, err)) {
                LOGE("entry data truncated: %{public}s", rel.c_str());
                return err;
            }
        }

        // 单条覆盖用完即弃, GNU L/K 同样一次性
        ePath.clear();
        eLink.clear();
        eSize.clear();
        longName.clear();
        longLink.clear();
    }
    return EXTRACT_OK;
}

// ---------------------------------------------------------------------------
// 对外接口
// ---------------------------------------------------------------------------

std::string toLower(const char* s) {
    std::string r = s != nullptr ? s : "";
    std::transform(r.begin(), r.end(), r.begin(),
                   [](unsigned char c) { return static_cast<char>(tolower(c)); });
    return r;
}

DecompressStream::Comp sniffFormat(FILE* f) {
    uint8_t m[6] = {0};
    size_t n = fread(m, 1, sizeof(m), f);
    fseeko(f, 0, SEEK_SET);
    if (n >= 2 && m[0] == 0x1f && m[1] == 0x8b) {
        return DecompressStream::GZIP;
    }
    if (n >= 6 && m[0] == 0xfd && m[1] == '7' && m[2] == 'z' && m[3] == 'X' && m[4] == 'Z' &&
        m[5] == 0x00) {
        return DecompressStream::XZ;
    }
    // .lzma (alone): props 字节 (通常 0x5D, 合法范围 0x00-0xE0) + 4 字节小端字典大小
    // (通常为 2 的幂 / 0xFFFFFFFF / 0). 保守识别常见值.
    if (n >= 5 && m[0] <= 0xE0 && ((m[0] & 0x01) == 0 || m[0] == 0x5D)) {
        uint32_t dict = static_cast<uint32_t>(m[1]) | (static_cast<uint32_t>(m[2]) << 8) |
                        (static_cast<uint32_t>(m[3]) << 16) |
                        (static_cast<uint32_t>(m[4]) << 24);
        bool pow2 = dict != 0 && (dict & (dict - 1)) == 0;
        if (m[0] == 0x5D && (pow2 || dict == 0xFFFFFFFF)) {
            return DecompressStream::XZ; // lzma_auto_decoder 接受 alone 格式
        }
    }
    return DecompressStream::PLAIN;
}

} // namespace

int extractArchive(const char* archivePath, const char* destDir, const char* format) {
    if (archivePath == nullptr || destDir == nullptr || archivePath[0] == '\0' ||
        destDir[0] == '\0') {
        return EXTRACT_E_ARGS;
    }

    FILE* f = fopen(archivePath, "rb");
    if (f == nullptr) {
        LOGE("open archive failed: %{public}s", archivePath);
        return EXTRACT_E_OPEN;
    }

    DecompressStream::Comp comp;
    std::string fmt = toLower(format);
    if (fmt == "tar.gz" || fmt == "tgz" || fmt == "gz") {
        comp = DecompressStream::GZIP;
    } else if (fmt == "tar.xz" || fmt == "txz" || fmt == "xz" || fmt == "tar.lzma" ||
               fmt == "lzma") {
        comp = DecompressStream::XZ;
    } else if (fmt == "tar") {
        comp = DecompressStream::PLAIN;
    } else if (fmt.empty() || fmt == "auto") {
        comp = sniffFormat(f);
    } else {
        fclose(f);
        return EXTRACT_E_ARGS;
    }

    if (comp == DecompressStream::XZ && extractXzSupported() == 0) {
        fclose(f);
        LOGE("xz not compiled in (DEVBOX_HAVE_LZMA=0)");
        return EXTRACT_E_XZ_UNSUPPORTED;
    }

    // 目标目录: 递归创建 + 规范化
    std::string destRoot = destDir;
    while (destRoot.size() > 1 && destRoot.back() == '/') {
        destRoot.pop_back();
    }
    if (!makeDirs(destRoot)) {
        fclose(f);
        LOGE("mkdir dest failed: %{public}s", destDir);
        return EXTRACT_E_DEST;
    }
    char* rp = realpath(destRoot.c_str(), nullptr);
    if (rp == nullptr) {
        fclose(f);
        return EXTRACT_E_DEST;
    }
    destRoot = rp;
    free(rp);

    DecompressStream s;
    if (!s.init(f, comp)) {
        fclose(f);
        return s.err();
    }

    ExtractStats st;
    int rc = extractTarStream(s, destRoot, st);
    s.deinit();
    fclose(f);

    if (rc == EXTRACT_OK) {
        LOGI("extract ok: files=%{public}llu dirs=%{public}llu links=%{public}llu skipped=%{public}llu",
             static_cast<unsigned long long>(st.files),
             static_cast<unsigned long long>(st.dirs),
             static_cast<unsigned long long>(st.links),
             static_cast<unsigned long long>(st.skipped));
    } else {
        LOGE("extract failed rc=%{public}d (%{public}s): %{public}s", rc,
             extractStrError(rc), archivePath);
    }
    return rc;
}

const char* extractStrError(int code) {
    switch (code) {
        case EXTRACT_OK: return "ok";
        case EXTRACT_E_ARGS: return "invalid arguments or unknown format";
        case EXTRACT_E_OPEN: return "cannot open archive";
        case EXTRACT_E_DEST: return "cannot create destination directory";
        case EXTRACT_E_FORMAT: return "corrupt archive (bad header or checksum)";
        case EXTRACT_E_TRUNCATED: return "archive is truncated";
        case EXTRACT_E_PATH: return "unsafe entry path (path traversal)";
        case EXTRACT_E_DECOMP: return "decompression stream error";
        case EXTRACT_E_XZ_UNSUPPORTED: return "xz support not compiled in";
        case EXTRACT_E_ENTRY_UNSUPPORTED: return "unsupported archive entry";
        case EXTRACT_E_IO: return "filesystem write error";
        case EXTRACT_E_MEM: return "out of memory";
        default: return "unknown error";
    }
}

int extractXzSupported(void) {
#if DEVBOX_HAVE_LZMA
    return 1;
#else
    return 0;
#endif
}
