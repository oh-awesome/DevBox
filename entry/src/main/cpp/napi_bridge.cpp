/**
 * napi_bridge.cpp
 * NAPI 桥接: 将 shell_exec 暴露给 ArkTS
 *
 * ArkTS 调用方式:
 *   import { execSync, execAsync, cancel, extract } from 'libdevbox_native.so'
 *   execAsync(cmd, onOutput, onExit) -> handle
 *   cancel(handle)
 *   execSync(cmd) -> { exitCode, output }
 *   extract(archivePath, destDir, format) -> Promise<number> (0=成功)
 */
#include "shell_exec.h"
#include "archive_extract.h"

#include <napi/native_api.h>
#include <string>
#include <memory>
#include <atomic>
#include <thread>

/**
 * 异步执行上下文, 跨线程共享
 */
struct AsyncContext {
    std::shared_ptr<std::atomic<bool>> cancel;
    std::thread worker;
    napi_threadsafe_function tsfn;
    napi_env env;
    napi_ref onOutputRef;
    napi_ref onExitRef;
};

/**
 * 传递给主线程的回调数据
 */
struct CallbackData {
    std::string text;
    bool isErr;
    int exitCode;
    bool isExit;  // true = onExit, false = onOutput
};

/**
 * 线程安全函数的 JS 主线程回调
 */
static void CallJsCallback(napi_env env, napi_value js_cb, void* context, void* data) {
    if (env == nullptr || data == nullptr) return;

    CallbackData* cbd = static_cast<CallbackData*>(data);
    AsyncContext* ctx = static_cast<AsyncContext*>(context);

    if (cbd->isExit) {
        napi_value onExitFn;
        napi_get_reference_value(env, ctx->onExitRef, &onExitFn);
        napi_value codeVal;
        napi_create_int32(env, cbd->exitCode, &codeVal);
        napi_call_function(env, nullptr, onExitFn, 1, &codeVal, nullptr);
    } else {
        napi_value onOutputFn;
        napi_get_reference_value(env, ctx->onOutputRef, &onOutputFn);
        napi_value args[2];
        napi_create_string_utf8(env, cbd->text.c_str(), cbd->text.length(), &args[0]);
        napi_get_boolean(env, cbd->isErr, &args[1]);
        napi_call_function(env, nullptr, onOutputFn, 2, args, nullptr);
    }

    delete cbd;
}

/**
 * 清理上下文 (GC 回调)
 */
static void FinalizeContext(napi_env env, void* hint, void*) {
    auto* ctx = static_cast<AsyncContext*>(hint);
    if (ctx) {
        ctx->cancel->store(true);
        if (ctx->worker.joinable()) {
            ctx->worker.join();
        }
        napi_delete_reference(env, ctx->onOutputRef);
        napi_delete_reference(env, ctx->onExitRef);
        napi_release_threadsafe_function(ctx->tsfn, napi_tsfn_release);
        delete ctx;
    }
}

/**
 * execAsync(command: string, onOutput: (data, isErr) => void, onExit: (code) => void) => handle
 */
static napi_value ExecAsync(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // 获取命令字符串
    size_t cmdLen = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &cmdLen);
    std::string command(cmdLen, '\0');
    napi_get_value_string_utf8(env, args[0], &command[0], cmdLen + 1, &cmdLen);

    // 创建上下文
    auto* ctx = new AsyncContext();
    ctx->env = env;
    ctx->cancel = std::make_shared<std::atomic<bool>>(false);

    // 持久化引用回调函数
    napi_create_reference(env, args[1], 1, &ctx->onOutputRef);
    napi_create_reference(env, args[2], 1, &ctx->onExitRef);

    // 创建线程安全函数
    napi_value workName;
    napi_create_string_utf8(env, "ShellExecTSFN", NAPI_AUTO_LENGTH, &workName);
    napi_create_threadsafe_function(
        env,
        nullptr,       // func (用 CallJsCallback 替代)
        nullptr,       // async_resource
        workName,      // async_resource_name
        0,             // max_queue_size (0 = 无限)
        1,             // initial_thread_count
        nullptr,       // thread_finalize_data
        nullptr,       // thread_finalize_cb
        ctx,           // context
        CallJsCallback,// call_js_cb
        &ctx->tsfn
    );

    // 启动子进程线程
    ctx->worker = shellExecAsync(
        command,
        [ctx](const std::string& data, bool isErr) {
            auto* cbd = new CallbackData();
            cbd->text = data;
            cbd->isErr = isErr;
            cbd->isExit = false;
            napi_acquire_threadsafe_function(ctx->tsfn);
            napi_call_threadsafe_function(ctx->tsfn, cbd, napi_tsfn_nonblocking);
            napi_release_threadsafe_function(ctx->tsfn, napi_tsfn_release);
        },
        [ctx](int exitCode) {
            auto* cbd = new CallbackData();
            cbd->exitCode = exitCode;
            cbd->isExit = true;
            napi_acquire_threadsafe_function(ctx->tsfn);
            napi_call_threadsafe_function(ctx->tsfn, cbd, napi_tsfn_nonblocking);
            napi_release_threadsafe_function(ctx->tsfn, napi_tsfn_release);
        },
        ctx->cancel
    );

    // 返回上下文指针, 用于 cancel
    napi_value external;
    napi_create_external(env, ctx, FinalizeContext, ctx, &external);
    return external;
}

/**
 * cancel(handle: object) => void
 */
static napi_value Cancel(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value arg;
    napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);

    AsyncContext* ctx = nullptr;
    napi_get_value_external(env, arg, reinterpret_cast<void**>(&ctx));
    if (ctx) {
        ctx->cancel->store(true);
    }
    return nullptr;
}

/**
 * execSync(command: string) => string
 * 直接返回命令输出文本 (兼容旧接口)
 */
static napi_value ExecSync(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value arg;
    napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);

    size_t cmdLen = 0;
    napi_get_value_string_utf8(env, arg, nullptr, 0, &cmdLen);
    std::string command(cmdLen, '\0');
    napi_get_value_string_utf8(env, arg, &command[0], cmdLen + 1, &cmdLen);

    ExecResult result = shellExecSync(command);

    napi_value output;
    napi_create_string_utf8(env, result.output.c_str(), result.output.length(), &output);

    return output;
}

/**
 * execDirectSync(binary: string, args: string[]) => string
 * 直接执行二进制（不经过 /bin/sh），绕过沙箱限制
 */
static napi_value ExecDirectSync(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // 第一个参数: 二进制路径
    size_t binLen = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &binLen);
    std::string binary(binLen, '\0');
    napi_get_value_string_utf8(env, args[0], &binary[0], binLen + 1, &binLen);

    // 第二个参数: 参数数组
    uint32_t arrLen = 0;
    napi_get_array_length(env, args[1], &arrLen);
    std::vector<std::string> argv;
    for (uint32_t i = 0; i < arrLen; i++) {
        napi_value elem;
        napi_get_element(env, args[1], i, &elem);
        size_t elemLen = 0;
        napi_get_value_string_utf8(env, elem, nullptr, 0, &elemLen);
        std::string s(elemLen, '\0');
        napi_get_value_string_utf8(env, elem, &s[0], elemLen + 1, &elemLen);
        argv.push_back(s);
    }

    ExecResult result = shellExecDirectSync(binary, argv);

    std::string combined = "[exit=" + std::to_string(result.exitCode) + "] " + result.output;
    napi_value output;
    napi_create_string_utf8(env, combined.c_str(), combined.length(), &output);

    return output;
}

/**
 * extract(archivePath: string, destDir: string, format: string) => Promise<number>
 * native 层 tar/gzip/xz 解压 (libuv 工作线程执行, 不阻塞 UI)
 * format: "tar.gz" | "tgz" | "tar.xz" | "txz" | "tar" | "auto" (缺省 auto)
 * resolve: 0=成功, 非0=错误码 (见 archive_extract.h)
 */
namespace {

struct ExtractWork {
    napi_async_work work;
    napi_deferred deferred;
    std::string archivePath;
    std::string destDir;
    std::string format;
    int result;
};

void ExtractExecute(napi_env env, void* data) {
    auto* w = static_cast<ExtractWork*>(data);
    w->result = extractArchive(w->archivePath.c_str(), w->destDir.c_str(), w->format.c_str());
}

void ExtractComplete(napi_env env, napi_status status, void* data) {
    auto* w = static_cast<ExtractWork*>(data);
    napi_value code;
    napi_create_int32(env, w->result, &code);
    if (status == napi_ok) {
        napi_resolve_deferred(env, w->deferred, code);
    } else {
        napi_reject_deferred(env, w->deferred, code);
    }
    napi_delete_async_work(env, w->work);
    delete w;
}

napi_value Extract(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // 读取三个字符串参数 (format 可省略, 缺省 "auto")
    const char* defaults[3] = {"", "", "auto"};
    std::string strs[3];
    for (size_t i = 0; i < 3; i++) {
        if (i < argc) {
            size_t len = 0;
            napi_get_value_string_utf8(env, args[i], nullptr, 0, &len);
            strs[i].resize(len);
            napi_get_value_string_utf8(env, args[i], &strs[i][0], len + 1, &len);
        } else {
            strs[i] = defaults[i];
        }
    }

    auto* w = new ExtractWork();
    w->archivePath = std::move(strs[0]);
    w->destDir = std::move(strs[1]);
    w->format = std::move(strs[2]);

    napi_value promise;
    napi_create_promise(env, &w->deferred, &promise);

    napi_value workName;
    napi_create_string_utf8(env, "DevBoxExtract", NAPI_AUTO_LENGTH, &workName);
    napi_create_async_work(env, nullptr, workName, ExtractExecute, ExtractComplete,
                           w, &w->work);
    napi_queue_async_work(env, w->work);
    return promise;
}

} // namespace

// 模块注册 (与 DevBox1.0 保持一致)
EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor props[] = {
        { "execSync", nullptr, ExecSync, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "execDirectSync", nullptr, ExecDirectSync, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "execAsync", nullptr, ExecAsync, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "cancel", nullptr, Cancel, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "extract", nullptr, Extract, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(props) / sizeof(props[0]), props);

    // 初始化 PTY 持久会话
    shellInit();

    return exports;
}
EXTERN_C_END

static napi_module devboxModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "devbox_native",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterDevBoxModule(void) {
    napi_module_register(&devboxModule);
}
