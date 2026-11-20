/**
 * DevEnvPaths —— 统一 PATH/环境变量块管理器
 *
 * 协议对齐：PolarisTerm DEVENV-SPEC §5（rewriteEnvBlock 语义）
 * 红线 R1：zshrc 块标记沿用 `ohpcd devenv`（双兼容读 `devbox` 旧标记）
 * 红线 R2：所有装卸操作必须经本模块写块（唯一写块入口）
 *
 * 布局协议 §0：
 *   ~/usr/local/bin/               ← 全局命令链接
 *   ~/usr/local/<name>/<version>/  ← 每工具多版本目录
 *   ~/usr/local/<name>/current     ← 相对符号链接 → 当前版本
 */

import fs from '@ohos.file.fs';
import { execSync } from 'libdevbox_native.so';

const HOME = '/storage/Users/currentUser';
const ZSHRC = `${HOME}/.zshrc`;
const BLOCK_START = '# >>> ohpcd devenv >>>';
const BLOCK_END = '# <<< ohpcd devenv <<<';
/** 双兼容：读时匹配旧标记（写入永远用新标记） */
const BLOCK_START_RE = /^#\s*>>>\s*(devbox|ohpcd devenv)/;
const BLOCK_END_RE = /^#\s*<<<\s*(devbox|ohpcd devenv)/;

/** PATH 段 rank（固定优先级排序，越小越前） */
const RANK_ORDER: string[][] = [
  ['usr/local/bin'],                              // rank 0
  [],                                              // rank 1 通用工具（动态填充）
  ['python', 'BiShengJDK', 'node', 'lua', 'perl', 'php', 'rust'],  // rank 2 运行时
  ['.harmonybrew'],                                // rank 3
];

/** lib 目录后缀（LD_LIBRARY_PATH 段用） */
const LIB_SUFFIX = '/current/lib';

interface PathSegment {
  dir: string;         // 相对于 HOME 的路径段（如 usr/local/bin）
  rank: number;
}

export class DevEnvPaths {

  /**
   * brew PATH 优先（用户勾选项，持久化于 devbox_prefs，EntryAbility 启动水化）：
   * 开启时 .harmonybrew 段 rank 提为 -1（先于 rank 0 的 usr/local/bin）——
   * brew 安装的命令优先于其他环境命中。块内序，与块位置无关（块恒在文件尾）。
   */
  static brewPathPriority: boolean = false;

  /** 应用优先设置：置位并重写块（段即刻前/后置；brew 未装时死段过滤自然忽略） */
  static applyBrewPriority(on: boolean): void {
    DevEnvPaths.brewPathPriority = on;
    DevEnvPaths.rewriteEnvBlock([]);
  }

  // ─── 路径段解析 ───────────────────────────────────────────

  /** 给定目录路径段计算 rank */
  static rank(dir: string): number {
    const d = dir.replace(/^\$?HOME\/?/, '').replace(/\/$/, '');
    // brew 优先须在 RANK_ORDER 表查找之前判（表内 .harmonybrew 固定 rank 3）
    if (DevEnvPaths.brewPathPriority && d.startsWith('.harmonybrew')) {
      return -1;
    }
    for (let r = 0; r < RANK_ORDER.length; r++) {
      if (RANK_ORDER[r].indexOf(d) >= 0) {
        return r;
      }
    }
    // usr/local/<name>/current/bin → 运行时 rank 2（默认）
    if (d.startsWith('usr/local/') && d.endsWith('/current/bin')) {
      return 2;
    }
    // .harmonybrew → rank 3
    if (d.startsWith('.harmonybrew')) {
      return 3;
    }
    return 1; // 通用工具
  }

  /** 排序：rank 优先，同 rank 字典序 */
  private static sortDirs(dirs: string[]): string[] {
    const segs: PathSegment[] = [];
    for (const d of dirs) {
      const seg: PathSegment = { dir: d, rank: DevEnvPaths.rank(d) };
      segs.push(seg);
    }
    segs.sort((a, b) => a.rank !== b.rank ? a.rank - b.rank : a.dir < b.dir ? -1 : 1);
    const out: string[] = [];
    for (const s of segs) {
      out.push(s.dir);
    }
    return out;
  }

  // ─── 文件操作 ─────────────────────────────────────────────

  private static readFile(path: string): string {
    try {
      return fs.readTextSync(path);
    } catch (_) {
      return '';
    }
  }

  private static writeFile(path: string, content: string): void {
    try {
      // fs 直写（原 heredoc 方案有引号转义陷阱；保持"文件以换行收尾"的旧语义）
      const out: string = content.endsWith('\n') || content === '' ? content : content + '\n';
      const f = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(f.fd, out);
      fs.closeSync(f.fd);
    } catch (e) {
      console.error(`[DevEnvPaths] write ${path} failed: ${e}`);
    }
  }

  private static backup(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.copyFileSync(path, `${path}.bak-devenv`);
      }
    } catch (_) {
    }
  }

  private static dirExists(path: string): boolean {
    try {
      return fs.statSync(path).isDirectory();
    } catch (_) {
      return false;
    }
  }

  // ─── zshrc 标记块读写（唯一写块入口） ─────────────────────

  /**
   * rewriteEnvBlock —— 协议核心
   *
   * 语义：
   * 1. 收编：zshrc 内所有匹配 legacyManagedLine 的目录并入
   * 2. 合并去重：Set(dirsIn ∪ 收编) − {''，'$PATH'} − exclude
   * 3. 死段过滤：$HOME/usr/local/... 段必须目录存在
   * 4. 固定序 rank 排序
   * 5. LD_LIBRARY_PATH 同步（有 lib 目录的段导出）
   * 6. 写回：删旧块+清受管散行 → 块追加文件尾（先备份）
   *
   * @param dirsIn   期望目录集（相对 HOME，如 'usr/local/bin'）
   * @param exclude  强制剔除集（卸载用，收编后统一过滤——不能前置过滤！）
   */
  static rewriteEnvBlock(dirsIn: string[], exclude: string[] = []): void {
    const content = DevEnvPaths.readFile(ZSHRC);
    if (content === '') {
      // 无文件，创建并只写新块
      DevEnvPaths.writeBlock(dirsIn, []);
      return;
    }

    const lines = content.split('\n');

    // 1. 提取旧块内行 + 识别受管散行（legacyManagedLine）
    //    两源分计（审计 F6）：块内段 vs 块外散行段——死滤只作用于前者（自愈
    //    块内死链）；后者是用户自定义段（目录可能后建），无条件保留防数据丢失
    const collected: Set<string> = new Set();
    const collectedScattered: Set<string> = new Set();
    let inBlock = false;
    const outputLines: string[] = [];
    // 块内非 PATH 变量行（透传保留，见 inBlock 分支注释）
    const extraBlockLines: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (BLOCK_START_RE.test(line.trim())) {
        inBlock = true;
        continue; // 不保留旧块标记
      }
      if (BLOCK_END_RE.test(line.trim())) {
        inBlock = false;
        continue;
      }
      if (inBlock) {
        // 旧块内行：PATH/LD 段由段机制重建；其余行（值型变量如 JAVA_HOME/
        // HOMEBREW_*）保留透传——否则任何 PATH 段重写都会抹掉它们
        if (line.indexOf('export PATH=') >= 0) {
          DevEnvPaths.parsePathSegments(line, collected);
          continue;
        }
        if (line.indexOf('export LD_LIBRARY_PATH=') >= 0) {
          continue; // lib 段由 rank 排序自动重建
        }
        if (line.trim() !== '') { extraBlockLines.push(line); }
        continue;
      }
      // 块外：匹配受管散行（含 usr/local/<x>/current/bin 或 .harmonybrew/bin）
      if (DevEnvPaths.isManagedLine(line)) {
        DevEnvPaths.parsePathSegments(line, collectedScattered);
        continue; // 清除受管散行
      }
      // 用户自引用前置行（含 ${）跳过解析但保留
      outputLines.push(line);
    }

    // 2. 合并去重
    const merged: Set<string> = new Set();
    for (const d of dirsIn) {
      merged.add(d);
    }
    for (const d of collected) {
      merged.add(d);
    }
    for (const d of collectedScattered) {
      merged.add(d);
    }
    merged.delete('');
    merged.delete('$PATH');
    // exclude 收编后统一滤（红线 #5：不能前置滤——收编会加回来）
    for (const e of exclude) {
      merged.delete(e);
    }

    // 3. 死段过滤：块内来源段 + 调用方传入段统一验证 $HOME/<seg> 目录存在
    //    （到段去 bin 级）——块内不留死链（自愈历史污染段）；块外散行收编的
    //    用户自定义段（collectedScattered）无条件保留（目录可能后建——审计 F6
    //    误杀：用户先配 PATH 后建目录的段曾被静默删除）
    const valid: string[] = [];
    for (const d of merged) {
      if (collectedScattered.has(d) && !collected.has(d)) {
        valid.push(d);
        continue;
      }
      const checkPath = `${HOME}/${d.replace(/\/bin$/, '')}`;
      if (DevEnvPaths.dirExists(checkPath)) {
        valid.push(d);
      }
    }

    // 4-6. 写回
    DevEnvPaths.backup(ZSHRC);
    const sorted = DevEnvPaths.sortDirs(valid);
    DevEnvPaths.writeBlockWithBody(sorted, outputLines.filter(l => l.trim() !== '').join('\n'), extraBlockLines);
  }

  /** 识别受管 PATH 行（legacyManagedLine 协议）
   *  引号行排除：env 页保存的用户行恒为单引号包裹（export PATH='…'）——
   *  是用户主权表达（brew 优先冲突调整会把它移到块前），收编会吞掉它。
   *  历史受管散行是裸值形态（export PATH=$HOME/...），不受影响。 */
  private static isManagedLine(line: string): boolean {
    const t = line.trim();
    if (!t.startsWith('export PATH=')) {
      return false;
    }
    if (t.indexOf("'") >= 0 || t.indexOf('"') >= 0) {
      return false;
    }
    // 含 usr/local/<x>/current/bin 或 .harmonybrew/bin 的 export PATH 行
    return /usr\/local\/[^\/]+\/current\/bin|\.harmonybrew\/bin/.test(t) ||
           /usr\/local\/bin/.test(t);
  }

  /** 从 export PATH=... 行中提取目录段（相对 HOME） */
  private static parsePathSegments(line: string, out: Set<string>): void {
    // 匹配 $HOME/<path> 或 ~/ <path> 形式
    const re = /\$HOME\/([^\s:;]+)|~\/([^\s:;]+)/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(line)) !== null) {
      const seg = m[1] || m[2];
      if (seg && seg !== '') {
        out.add(seg);
      }
    }
  }

  /** 写标记块（只含 dirsIn，无收编） */
  private static writeBlock(dirsIn: string[], existingLines: string[]): void {
    const sorted = DevEnvPaths.sortDirs(dirsIn);
    DevEnvPaths.writeBlockWithBody(sorted, existingLines.join('\n'), []);
  }

  /**
   * 构建并写入完整 zshrc。
   * extraLines：块内非 PATH 变量行（JAVA_HOME/HOMEBREW_* 等），透传保留。
   */
  private static writeBlockWithBody(sortedDirs: string[], restOfFile: string, extraLines: string[]): void {
    // 构建 PATH 值
    const pathSegs = sortedDirs.map(d => `$HOME/${d}`);
    pathSegs.push('$PATH');
    const pathLine = `export PATH=${pathSegs.join(':')}`;

    // 构建 LD_LIBRARY_PATH（有 lib 目录的段）
    const libDirs: string[] = [];
    for (const d of sortedDirs) {
      const libPath = d.replace(/\/bin$/, LIB_SUFFIX);
      const fullLib = `${HOME}/${libPath}`;
      if (DevEnvPaths.dirExists(fullLib)) {
        libDirs.push(`$HOME/${libPath}`);
      }
    }
    let libLine = '';
    if (libDirs.length > 0) {
      libLine = `export LD_LIBRARY_PATH=${libDirs.join(':')}\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}`;
    }

    const block = [
      BLOCK_START,
      pathLine,
      ...(libLine !== '' ? [libLine] : []),
      ...extraLines,
      BLOCK_END,
    ].join('\n');

    const content = restOfFile.trim() !== '' ? `${restOfFile.trim()}\n\n${block}\n` : `${block}\n`;
    DevEnvPaths.writeFile(ZSHRC, content);
  }

  // ─── 便捷操作 ─────────────────────────────────────────────

  /** ensurePathLine：确保某工具的 current/bin 在 PATH 块中 */
  static ensurePathLine(toolName: string): void {
    const dir = `usr/local/${toolName}/current/bin`;
    DevEnvPaths.rewriteEnvBlock([dir]);
  }

  /** ensureBrewPathLine：确保 .harmonybrew/bin 在块中 */
  static ensureBrewPathLine(): void {
    const dir = '.harmonybrew/bin';
    DevEnvPaths.rewriteEnvBlock([dir, 'usr/local/bin']);
  }

  /** stripPathLine：从块中剔除指定目录（卸载用） */
  static stripPathLine(dirToRemove: string): void {
    DevEnvPaths.rewriteEnvBlock([], [dirToRemove]);
  }

  /** ensureBasePaths：初始化基础块（首次安装任何工具时调） */
  static ensureBasePaths(): void {
    DevEnvPaths.rewriteEnvBlock(['usr/local/bin']);
  }

  /** 读取当前块内所有目录（探测用，不修改） */
  static currentDirs(): string[] {
    return DevEnvPaths.currentDirsFrom(DevEnvPaths.readFile(ZSHRC));
  }

  /** 基于 zshrc 文本解析块内目录（批量探测场景传入一次读好的文本，避免重复 IO） */
  static currentDirsFrom(content: string): string[] {
    const dirs: Set<string> = new Set();
    let inBlock = false;
    for (const line of content.split('\n')) {
      if (BLOCK_START_RE.test(line.trim())) {
        inBlock = true;
        continue;
      }
      if (BLOCK_END_RE.test(line.trim())) {
        inBlock = false;
        continue;
      }
      if (inBlock && line.indexOf('export PATH=') >= 0) {
        DevEnvPaths.parsePathSegments(line, dirs);
      }
    }
    return Array.from(dirs);
  }

  // ─── brew 优先 × 用户 PATH 行冲突（环境页保存前检测） ──────

  /**
   * 冲突检测：托管块之后出现"前置式"用户 PATH 行（$PATH 引用之前有目录段，
   * 或整行无 $PATH 引用）——shell 顺序语义上该行会压制块内 .harmonybrew 段，
   * 破坏 brew 优先原则。返回首个冲突行下标（-1 无冲突）。
   * 前置条件：brewPriority 开 + 块存在且含 .harmonybrew 段（未装/无块恒 -1）。
   * 注意入参是"保存后的完整行数组"（环境页 saveToFile 的 outputLines——
   * 托管块原样透传语义下块位置不变，块后行即用户编辑结果）。
   * 认的行形态（审计 F4/F5）：export PATH=… / 裸赋值 PATH=…（zsh 标准两行式
   * PATH=/foo:$PATH + export PATH）；$PATH 引用匹配 ${PATH}/$PATH/$path 变体。
   */
  static brewPriorityConflict(lines: string[]): number {
    const all: number[] = DevEnvPaths.brewPriorityConflicts(lines);
    return all.length > 0 ? all[0] : -1;
  }

  /** 块范围扫描（首 START 与最后 END；startIdx>endIdx=标记病理，恒判无冲突——
   *  宁可不修不挂死：孤立尾标记在首标记之前时 resolve 会死循环，见审计 F1） */
  private static blockRange(lines: string[]): number[] {
    let startIdx = -1;
    let endIdx = -1;
    let inBlock = false;
    let hasBrewSeg = false;
    for (let i = 0; i < lines.length; i++) {
      const t = lines[i].trim();
      if (BLOCK_START_RE.test(t)) {
        if (startIdx < 0) {
          startIdx = i;
        }
        inBlock = true;
        continue;
      }
      if (BLOCK_END_RE.test(t)) {
        inBlock = false;
        endIdx = i;
        continue;
      }
      if (inBlock && t.startsWith('export PATH=') && t.indexOf('.harmonybrew') >= 0) {
        hasBrewSeg = true;
      }
    }
    if (startIdx < 0 || endIdx < 0 || !hasBrewSeg || startIdx > endIdx) {
      return [-1, -1];
    }
    return [startIdx, endIdx];
  }

  /** 全部冲突行下标（升序）——检测语义见 brewPriorityConflict 注释 */
  private static brewPriorityConflicts(lines: string[]): number[] {
    if (!DevEnvPaths.brewPathPriority) {
      return [];
    }
    const range: number[] = DevEnvPaths.blockRange(lines);
    const endIdx = range[1];
    if (endIdx < 0) {
      return [];
    }
    const out: number[] = [];
    for (let i = endIdx + 1; i < lines.length; i++) {
      const t = lines[i].trim();
      // 前缀形态：export PATH=…（含双空格变体）/ 裸赋值 PATH=…（两行式之一）/ path=…
      const v: string = t.startsWith('export PATH=')
        ? t.substring('export PATH='.length)
        : (/^(PATH|path)=/.test(t) ? t.substring(t.indexOf('=') + 1) : '');
      if (v === '' || t.indexOf('=') < 0) {
        continue;
      }
      // $PATH 引用位置（${PATH}/$PATH 大小写变体）；引用前的段=前置段（压制块内序），
      // 无引用=整行替换更冲突
      const m: RegExpMatchArray | null = v.match(/\$\{?(PATH|path)\}?/);
      const head = m !== null && m.index !== undefined ? v.substring(0, m.index) : v;
      const headClean = head.replace(/['" ]/g, '').replace(/[:;]+$/, '');
      if (headClean !== '') {
        out.push(i);
      }
    }
    return out;
  }

  /**
   * 冲突调整：把块后所有前置式用户 PATH 行移到块标记之前——
   * 块恒在文件尾重写后必然再后置，brew 恢复最前（优先原则重建）。
   * 标记病理（孤立尾标记在首标记前）不调整原样返回（审计 F1：逐轮 splice
   * 会与输入同构 → 死循环 ANR）。多行冲突按原序保持相对优先级（审计 F3：
   * 倒序遍历+同位插入，后移的先插、先移的后插——文件序不变）。
   */
  static resolveBrewPriorityConflict(lines: string[]): string[] {
    const out: string[] = [...lines];
    const range: number[] = DevEnvPaths.blockRange(out);
    const startIdx = range[0];
    if (startIdx < 0) {
      return out;
    }
    const conflicts: number[] = DevEnvPaths.brewPriorityConflicts(out);
    if (conflicts.length === 0) {
      return out;
    }
    // 两段式（边写边插会使后续原始下标漂移——pop 错行，复刻对拍实证）：
    // ① 倒序逐条 pop（尾部先取，前面下标不漂移）+ 头插恢复文件序
    const movedLines: string[] = [];
    for (let k = conflicts.length - 1; k >= 0; k--) {
      movedLines.unshift(out.splice(conflicts[k], 1)[0]);
    }
    // ② 游标递增插入（startIdx, startIdx+1, …）——保持冲突行之间的相对优先级
    for (let k = 0; k < movedLines.length; k++) {
      out.splice(startIdx + k, 0, movedLines[k]);
    }
    return out;
  }

  // ─── current 符号链接管理（R3） ───────────────────────────

  /** Java 特例：ohpcd devenv 块内维护 JAVA_HOME（幂等：已有则原位更新，无则插到块首） */
  static ensureJavaHome(): void {
    try {
      const dir = `${HOME}/usr/local/BiShengJDK/current`;
      const line = `export JAVA_HOME=${HOME}/usr/local/BiShengJDK/current`;
      const zshrc = `${HOME}/.zshrc`;
      // 块内已有 JAVA_HOME 行 → 原位替换；否则插到块标记之后
      execSync(
        `if grep -q '^export JAVA_HOME=' '${zshrc}'; then ` +
        `sed -i 's|^export JAVA_HOME=.*|${line}|' '${zshrc}'; ` +
        `else sed -i '/# >>> ohpcd devenv >>>/a ${line}' '${zshrc}'; fi`);
    } catch (e) {
      console.error(`[DevEnvPaths] ensureJavaHome: ${e}`);
    }
  }

  /**
   * brew 环境注册（捕获 shellenv 输出落块）：
   * 非 PATH 变量（HOMEBREW_PREFIX/CELLAR/REPOSITORY、MANPATH、INFOPATH）
   * 逐行幂等写入托管块（ensureJavaHome 同款姿势；rewriteEnvBlock 已改为
   * 透传保留块内额外行，不会被 PATH 段重写抹掉）；PATH 走段机制
   * （.harmonybrew/bin + .harmonybrew/Homebrew/bin，rank 3）。
   * 静态化但保真——值由 brew shellenv 现算捕获，不硬编码。
   */
  static ensureBrewShellenv(shellenvLines: string[]): void {
    try {
      const zshrc = `${HOME}/.zshrc`;
      // PATH 段（段机制统一管理——块内只保留一条 PATH 行，避免解析歧义）
      DevEnvPaths.rewriteEnvBlock(['.harmonybrew/bin', '.harmonybrew/Homebrew/bin']);
      // 非 PATH 变量：逐行幂等（已有→原位替换；没有→插到块标记之后）
      for (let i = 0; i < shellenvLines.length; i++) {
        const line: string = shellenvLines[i].trim();
        if (line === '' || line.indexOf('export ') !== 0) { continue; }
        if (line.indexOf('export PATH=') === 0) { continue; }   // PATH 走段机制
        const eq: number = line.indexOf('=');
        const key: string = line.substring(7, eq);
        if (key === '' || line.indexOf("'") >= 0 || line.indexOf('|') >= 0 || line.indexOf('&') >= 0) {
          continue;  // sed 替换安全防线（shellenv 输出不含这些，防御性）
        }
        const cmd: string =
          `if grep -q '^export ${key}=' '${zshrc}'; then ` +
          `sed -i 's|^export ${key}=.*|${line}|' '${zshrc}'; ` +
          `else sed -i '/# >>> ohpcd devenv >>>/a ${line}' '${zshrc}'; fi`;
        execSync(cmd);
      }
    } catch (e) {
      console.error(`[DevEnvPaths] ensureBrewShellenv: ${e}`);
    }
  }

  /** brew 环境注册是否完整（块内有 HOMEBREW_PREFIX 且 PATH 段含 .harmonybrew/bin） */
  static brewEnvComplete(): boolean {
    try {
      const content: string = DevEnvPaths.readFile(ZSHRC);
      if (content.indexOf('export HOMEBREW_PREFIX=') < 0) { return false; }
      const dirs: string[] = DevEnvPaths.currentDirs();
      return dirs.indexOf('.harmonybrew/bin') >= 0;
    } catch (_) {
      return false;
    }
  }

  /** 卸载：摘除 brew 环境注册（非 PATH 变量行仅删托管块内 + PATH 段） */
  static stripBrewEnv(): void {
    try {
      const zshrc = `${HOME}/.zshrc`;
      execSync(
        `sed -i '/# >>> ohpcd devenv >>>/,/# <<< ohpcd devenv <<</ ` +
        `{ /^export HOMEBREW_/d; /^export MANPATH=/d; /^export INFOPATH=/d; }' '${zshrc}'`);
      DevEnvPaths.stripPathLine('.harmonybrew/bin');
      DevEnvPaths.stripPathLine('.harmonybrew/Homebrew/bin');
    } catch (e) {
      console.error(`[DevEnvPaths] stripBrewEnv: ${e}`);
    }
  }

  /** 创建/更新 current 相对符号链接 */
  static updateCurrentLink(toolName: string, version: string): boolean {
    const linkPath = `${HOME}/usr/local/${toolName}/current`;
    const target = version; // 相对链接（红线 #1：不用绝对路径）
    try {
      // 清旧节点（三形态兼容）：软链/文件 → unlink；实体目录（历史 cp 降级残留）→ rmdir 递归
      try {
        fs.unlinkSync(linkPath);
      } catch (_) {
      }
      try {
        execSync(`rm -rf '${linkPath}' 2>/dev/null`);
      } catch (_) {
      }
      // 主通道：file 服务（fs.symlinkSync）——实证可在 FUSE 用户卷建链；
      // shell ln 在该卷被拒（PolarisTerm 靠 CUSTOM_SANDBOX ACL，我们待 AGC 审批）
      fs.symlinkSync(target, linkPath);
      // fs 无 readLink API，保留 shell readlink
      const back: string = execSync(`readlink '${linkPath}' 2>/dev/null`) ?? '';
      if (back.trim() === target) {
        // 协议：活跃版本仅由 current 链接表达——清理历史注册表残留（不再允许第二份记录）
        try { fs.unlinkSync(`${HOME}/usr/local/${toolName}/.devbox/${toolName}-registry.json`); } catch (_) {
        }
        return true;
      }
      console.error(`[DevEnvPaths] current 校验不符: ${back}`);
      return false;
    } catch (e) {
      console.error(`[DevEnvPaths] updateCurrentLink ${toolName} -> ${version}: ${e}`);
      return false;
    }
  }


  /** 删除 current 链接 */
  static removeCurrentLink(toolName: string): void {
    const linkPath = `${HOME}/usr/local/${toolName}/current`;
    try {
      try {
        fs.unlinkSync(linkPath);
      } catch (_) {
      }
      try {
        execSync(`rm -rf '${linkPath}' 2>/dev/null`);
      } catch (_) {
      }
      try { fs.unlinkSync(`${HOME}/usr/local/${toolName}/.devbox/${toolName}-registry.json`); } catch (_) {
      }
    } catch (_) {
    }
  }

  /** 读取 current 指向的版本（空串 = 无 current） */
  static readCurrentVersion(toolName: string): string {
    const linkPath = `${HOME}/usr/local/${toolName}/current`;
    try {
      // fs 无 readLink API，保留 shell
      return (execSync(`readlink '${linkPath}' 2>/dev/null || echo ''`) ?? '').trim();
    } catch (_) {
    }
    return '';
  }

  /** current 链接存在且指向的版本目录真实存在（= 已有有效活跃版本） */
  static hasValidCurrent(toolName: string): boolean {
    const ver: string = DevEnvPaths.readCurrentVersion(toolName);
    if (ver === '') { return false; }
    try {
      return fs.accessSync(`${HOME}/usr/local/${toolName}/${ver}`);
    } catch (_) {
      return false;
    }
  }
}
