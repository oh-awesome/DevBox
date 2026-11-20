/**
 * shell_exec.h
 * 基于 forkpty 的命令执行器 (独立模式)
 *
 * 每次调用 forkpty 创建独立子进程执行命令
 * 不使用持久会话，输出干净无污染
 */
#ifndef SHELL_EXEC_H
#define SHELL_EXEC_H

#include <string>
#include <functional>
#include <thread>
#include <atomic>
#include <unistd.h>
#include <sys/wait.h>

struct ExecResult {
    int exitCode;
    std::string output;
};

using OutputCallback = std::function<void(const std::string& data, bool isErr)>;

ExecResult shellExecSync(const std::string& command);

/**
 * 直接执行二进制（不经过 /bin/sh）
 * binary: 可执行文件路径
 * argv: 参数列表（第一个通常为程序名）
 */
ExecResult shellExecDirectSync(const std::string& binary,
                               const std::vector<std::string>& argv);

std::thread shellExecAsync(const std::string& command,
                           OutputCallback onOutput,
                           std::function<void(int)> onExit,
                           std::shared_ptr<std::atomic<bool>> cancel);

static inline void shellInit() {}
static inline void shellDestroy() {}

#endif // SHELL_EXEC_H
