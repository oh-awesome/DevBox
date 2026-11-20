/**
 * BrewEnv —— brew 命令密封环境工厂（唯一构造点）
 *
 * 统一前缀：HOME + PATH 钉死系统目录（防已装工具影子化——真机实证 brew
 * 自检 zsh 命中我们装的 bash → "Zsh is required"）。所有 brew 命令
 * 一律经此构造（绝对路径 + 固定 PATH，无管道保真实退出码）。
 *
 * 注：trust store 演进（2026-11-13 终版）：不 unset XDG——app 进程被
 * hishell 注入的 XDG_CONFIG_HOME 指向本 app 沙箱（属主=app uid），brew
 * 的 trust 读写都在沙箱内自足（写路径 uid 检查通过）；~/.homebrew 旧位
 * 仅作 writeTrustFile 的双落点兜底。此前 unset 把 trust 钉到 FUSE 卷
 * （stat uid 恒 20001006）导致卸载触发 trust 写入时报错退出非零。
 */
export class BrewEnv {
  private static readonly HOME: string = '/storage/Users/currentUser';

  /**
   * 密封环境前缀（所有 brew 命令统一使用）。
   * XDG 不钉死（2026-11-13 修正）：hishell 注入的 XDG_CONFIG_HOME 指向
   * 本应用自己的沙箱（/data/storage/el2/base/...，每应用各自的虚拟路径，
   * 属主=本 app uid）——trust store 解析到沙箱后 brew 的**写路径** uid 检查
   * 也能通过（此前 unset 把 trust 钉到 ~/.homebrew 的 FUSE 卷上，stat uid
   * 恒 20001006≠app euid → 卸载路径触发 trust 写入时报 "Refusing to write
   * insecure trust store" 且退出非零，实测 2026-11-13）。与用户终端同构：
   * 终端 brew 的 trust 也落在终端自己沙箱——per-app 割据是平台现实。
   * writeTrustFile 预写双落点（沙箱+~/.homebrew）对齐读路径。
   */
  static env(): string {
    // HOMEBREW_NO_AUTO_UPDATE：brew install 默认触发 auto-update（git fetch
    // 整个 123MB 仓库）——app 密封环境里首次 install 实测卡 10 分钟+（真机）；
    // 更新走我们的"检查更新"按钮，安装永不隐式更新
    //
    // HOMEBREW 三件套：与用户终端 shellenv 输出逐字一致（真机杀手测试同款
    // 配置——仓库实体路径+三件套安装 jq 成功）。注意三件套并不改写 fork 的
    // 路径自派生（见 brew() 注释），真正根因是调用路径；三件套的作用是与
    // 终端环境完全对齐，杜绝其他环境敏感行为分叉。
    // HOMEBREW_NO_COLOR：查询/安装输出少一层 ANSI（AnsiClean 仍兜底）。
    return `export HOME='${BrewEnv.HOME}' PATH='/usr/bin:/bin' HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_COLOR=1 ` +
      `HOMEBREW_PREFIX='${BrewEnv.HOME}/.harmonybrew' ` +
      `HOMEBREW_REPOSITORY='${BrewEnv.HOME}/.harmonybrew/Homebrew' ` +
      `HOMEBREW_CELLAR='${BrewEnv.HOME}/.harmonybrew/Cellar';`;
  }

  /** brew 可执行绝对路径——必须用仓库内实体，不能用前缀软链！
   *  fork 按 argv[0]（被调用路径）所在目录自派生 Repository/Cellar：
   *  不 realpath 软链、不认 HOMEBREW_* 环境变量改写派生（真机 2026-11-13
   *  对照实证：三件套环境完全相同的两次调用，只换可执行路径即翻盘）。
   *    .harmonybrew/bin/brew（install.sh 造的软链）→ 把前缀当仓库 → 用
   *    .harmonybrew/Cellar——前缀路径调用留下的残骸 keg 让 install 前置
   *    扫描报 "is not a valid keg"，app 内所有安装全灭；
   *    Homebrew/bin/brew（仓库实体）→ 用 Homebrew/Cellar——与用户终端
   *    PATH 第一位解析到的是同一二进制、同一 Cellar，安装互通。
   *  （附带实证：fork 的 [y/n] 安装确认提示不阻塞 stdin——无 TTY 不卡死）
   */
  static brew(): string {
    return `${BrewEnv.HOME}/.harmonybrew/Homebrew/bin/brew`;
  }

  /** 用户 HOME（trust 等全局文件定位用） */
  static home(): string {
    return BrewEnv.HOME;
  }
}
