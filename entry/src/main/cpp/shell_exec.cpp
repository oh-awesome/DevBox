/**
 * shell_exec.cpp
 * 基于 forkpty 的命令执行器 (独立模式)
 *
 * 每次 forkpty 创建独立子进程: sh -c "command"
 * PTY 提供完整终端环境，但子进程执行完即退出
 * 输出干净无 MARKER 污染
 */
#include "shell_exec.h"

#include <cstdlib>
#include <cstring>
#include <vector>
#include <sstream>
#include <sys/stat.h>
#include <fcntl.h>
#include <pty.h>
#include <poll.h>
#include <hilog/log.h>
#include <csignal>
#include <algorithm>
#include <chrono>

#undef LOG_TAG
#define LOG_TAG "DevBox-Shell"

#define LOGI(fmt, ...) OH_LOG_INFO(LOG_APP, fmt, ##__VA_ARGS__)
#define LOGW(fmt, ...) OH_LOG_WARN(LOG_APP, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) OH_LOG_ERROR(LOG_APP, fmt, ##__VA_ARGS__)

/**
 * 清理 ANSI 转义序列
 */
static std::string cleanAnsi(const std::string& input) {
    std::string result;
    result.reserve(input.size());
    bool inEscape = false;

    for (size_t i = 0; i < input.size(); i++) {
        unsigned char c = input[i];
        if (inEscape) {
            if (c >= 0x40 && c <= 0x7E) inEscape = false;
            continue;
        }
        if (c == 0x1b) { inEscape = true; continue; }
        if (c < 0x20 && c != '\t' && c != '\n' && c != '\r') continue;
        result += c;
    }
    return result;
}

/**
 * 子进程环境设置
 */
static void setupChild(const char* home) {
    setenv("HOME", home, 1);
    setenv("PWD", home, 1);
    chdir(home);
}

// ─── 同步执行 ─────────────────────────────────────────

/**
 * 直接执行二进制（不经过 /bin/sh），绕过沙箱对 sh 执行的限制
 */
ExecResult shellExecDirectSync(const std::string& binary,
                                const std::vector<std::string>& argv) {
    ExecResult result;
    result.exitCode = -1;

    LOGI("direct: %{public}s", binary.c_str());

    int masterFd;
    struct winsize ws = {};
    ws.ws_col = 120;
    ws.ws_row = 40;

    pid_t pid = forkpty(&masterFd, nullptr, nullptr, &ws);
    if (pid == -1) {
        LOGE("direct: forkpty failed, errno=%{public}d", errno);
        result.output = "forkpty() failed";
        return result;
    }

    if (!pid) {
        // 子进程
        setupChild("/storage/Users/currentUser");

        // 构造 execv 参数数组
        std::vector<char*> cargs;
        // argv[0] 通常是程序名
        if (argv.empty()) {
            cargs.push_back(const_cast<char*>(binary.c_str()));
        } else {
            for (size_t i = 0; i < argv.size(); i++) {
                cargs.push_back(const_cast<char*>(argv[i].c_str()));
            }
        }
        cargs.push_back(nullptr);

        execv(binary.c_str(), cargs.data());
        _exit(127);
    }

    LOGI("direct: pid=%{public}d, fd=%{public}d", pid, masterFd);

    // 读取全部输出: 与 shellExecSync 相同的 poll 逻辑
    std::string rawOutput;
    char buf[4096];
    struct pollfd pfd;
    pfd.fd = masterFd;
    pfd.events = POLLIN;

    while (true) {
        int status;
        int wret = waitpid(pid, &status, WNOHANG);
        if (wret == pid) {
            while (true) {
                int ret = poll(&pfd, 1, 100);
                if (ret <= 0) break;
                ssize_t n = read(masterFd, buf, sizeof(buf) - 1);
                if (n <= 0) break;
                buf[n] = '\0';
                rawOutput += std::string(buf, n);
            }
            if (WIFEXITED(status)) result.exitCode = WEXITSTATUS(status);
            break;
        }

        int ret = poll(&pfd, 1, 500);
        if (ret < 0) break;
        if (ret > 0) {
            ssize_t n = read(masterFd, buf, sizeof(buf) - 1);
            if (n <= 0) continue;
            buf[n] = '\0';
            rawOutput += std::string(buf, n);
        }
    }

    close(masterFd);

    rawOutput = cleanAnsi(rawOutput);
    std::vector<std::string> lines;
    std::istringstream iss(rawOutput);
    std::string line;
    while (std::getline(iss, line)) {
        while (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty()) continue;
        lines.push_back(line);
    }

    std::stringstream ss;
    for (size_t i = 0; i < lines.size(); i++) {
        if (i > 0) ss << "\n";
        ss << lines[i];
    }
    result.output = ss.str();

    LOGI("direct: exitCode=%{public}d, outputLen=%{public}d",
         result.exitCode, (int)result.output.size());

    return result;
}

ExecResult shellExecSync(const std::string& command) {
    ExecResult result;
    result.exitCode = -1;

    LOGI("sync: %{public}s", command.c_str());

    int masterFd;
    struct winsize ws = {};
    ws.ws_col = 120;
    ws.ws_row = 40;

    pid_t pid = forkpty(&masterFd, nullptr, nullptr, &ws);
    if (pid == -1) {
        LOGE("sync: forkpty failed, errno=%{public}d", errno);
        result.output = "forkpty() failed";
        return result;
    }

    if (!pid) {
        setupChild("/storage/Users/currentUser");
        execl("/bin/sh", "sh", "-c", command.c_str(), nullptr);
        _exit(127);
    }

    LOGI("sync: pid=%{public}d, fd=%{public}d", pid, masterFd);

    // 读取全部输出: poll 直到子进程退出
    std::string rawOutput;
    char buf[4096];
    struct pollfd pfd;
    pfd.fd = masterFd;
    pfd.events = POLLIN;

    while (true) {
        // 先检查子进程是否已退出
        int status;
        int wret = waitpid(pid, &status, WNOHANG);
        if (wret == pid) {
            // 子进程已退出，最后读一次剩余输出
            while (true) {
                int ret = poll(&pfd, 1, 100);
                if (ret <= 0) break;
                ssize_t n = read(masterFd, buf, sizeof(buf) - 1);
                if (n <= 0) break;
                buf[n] = '\0';
                rawOutput += std::string(buf, n);
            }
            if (WIFEXITED(status)) result.exitCode = WEXITSTATUS(status);
            break;
        }

        // 子进程仍在运行，等输出
        int ret = poll(&pfd, 1, 500);
        if (ret < 0) break;
        if (ret > 0) {
            ssize_t n = read(masterFd, buf, sizeof(buf) - 1);
            if (n <= 0) continue;
            buf[n] = '\0';
            rawOutput += std::string(buf, n);
        }
    }

    close(masterFd);

    // 清理输出: 去 ANSI + 去 \r + 只保留有内容的行
    rawOutput = cleanAnsi(rawOutput);
    std::vector<std::string> lines;
    std::istringstream iss(rawOutput);
    std::string line;
    while (std::getline(iss, line)) {
        while (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty()) continue;
        lines.push_back(line);
    }

    std::stringstream ss;
    for (size_t i = 0; i < lines.size(); i++) {
        if (i > 0) ss << "\n";
        ss << lines[i];
    }
    result.output = ss.str();

    LOGI("sync: exitCode=%{public}d, outputLen=%{public}d",
         result.exitCode, (int)result.output.size());

    return result;
}

// ─── 异步执行 ─────────────────────────────────────────

std::thread shellExecAsync(const std::string& command,
                           OutputCallback onOutput,
                           std::function<void(int)> onExit,
                           std::shared_ptr<std::atomic<bool>> cancel) {
    LOGI("async: %{public}s", command.c_str());

    return std::thread([command, onOutput, onExit, cancel]() {
        int masterFd;
        struct winsize ws = {};
        ws.ws_col = 120;
        ws.ws_row = 40;

        pid_t pid = forkpty(&masterFd, nullptr, nullptr, &ws);
        if (pid == -1) {
            LOGE("async: forkpty failed, errno=%{public}d", errno);
            onOutput("forkpty() failed", true);
            onExit(-1);
            return;
        }

        if (!pid) {
            setupChild("/storage/Users/currentUser");
            execl("/bin/sh", "sh", "-c", command.c_str(), nullptr);
            _exit(127);
        }

        LOGI("async: pid=%{public}d, fd=%{public}d", pid, masterFd);

        // 按行读取
        char buf[4096];
        std::string leftover;
        struct pollfd pfd;
        pfd.fd = masterFd;
        pfd.events = POLLIN;
        int totalLines = 0;
        int savedExitCode = -1;
        bool childExited = false;

        while (true) {
            if (cancel && cancel->load()) {
                LOGI("async: cancelled");
                kill(pid, SIGTERM);
                break;
            }

            // 检查子进程是否退出
            if (!childExited) {
                int wStatus;
                int wret = waitpid(pid, &wStatus, WNOHANG);
                if (wret == pid) {
                    childExited = true;
                    if (WIFEXITED(wStatus)) savedExitCode = WEXITSTATUS(wStatus);
                    // 子进程退出后，最后读一次剩余输出
                    while (true) {
                        int pret = poll(&pfd, 1, 200);
                        if (pret <= 0) break;
                        ssize_t n = read(masterFd, buf, sizeof(buf) - 1);
                        if (n <= 0) break;
                        buf[n] = '\0';
                        std::string chunk(buf, n);
                        chunk = cleanAnsi(chunk);
                        leftover += chunk;
                        // 处理行
                        size_t pos;
                        while ((pos = leftover.find_first_of("\r\n")) != std::string::npos) {
                            std::string line = leftover.substr(0, pos);
                            leftover.erase(0, pos + 1);
                            while (!line.empty() && line.back() == '\r') line.pop_back();
                            if (line.empty()) continue;
                            totalLines++;
                            onOutput(line, false);
                        }
                    }
                    break;
                }
            }

            int ret = poll(&pfd, 1, 200);
            if (ret < 0) break;
            if (ret == 0) continue;

            ssize_t n = read(masterFd, buf, sizeof(buf) - 1);
            if (n <= 0) continue;

            buf[n] = '\0';
            std::string chunk(buf, n);
            chunk = cleanAnsi(chunk);
            leftover += chunk;

            size_t pos;
            while ((pos = leftover.find_first_of("\r\n")) != std::string::npos) {
                std::string line = leftover.substr(0, pos);
                leftover.erase(0, pos + 1);
                while (!line.empty() && line.back() == '\r') line.pop_back();
                if (line.empty()) continue;
                totalLines++;
                onOutput(line, false);
            }
        }

        // 剩余行
        if (!leftover.empty()) {
            while (!leftover.empty() && leftover.back() == '\r') leftover.pop_back();
            if (!leftover.empty()) {
                totalLines++;
                onOutput(leftover, false);
            }
        }

        close(masterFd);

        int status;
        if (!childExited) waitpid(pid, &status, 0);
        int exitCode = (savedExitCode >= 0) ? savedExitCode : -1;

        LOGI("async: done, exitCode=%{public}d, lines=%{public}d", exitCode, totalLines);
        onExit(exitCode);
    });
}
