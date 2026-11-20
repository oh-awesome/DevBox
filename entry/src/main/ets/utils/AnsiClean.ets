/**
 * AnsiClean —— brew 命令输出 ANSI 转义序列剥离器
 *
 * 参照 BrewUI ANSIParser.swift 设计（Swift → ArkTS 移植）：
 * - CSI 序列（ESC[...m/j/k/etc）：消费 SGR 色码，保留纯文本
 * - OSC 序列（ESC]...BEL/ESC\）：整段跳过（窗口标题等）
 * - 二字节转义（ESC( / ESC= 等）：丢弃
 * - \r 回车符：剥离（brew 进度条刷新用）
 * 
 * 使用场景：brew install/uninstall/update 的 stdout/stderr 输出
 * 进入 inlineError / installLog 前统一清洗——否则用户看到的是乱码。
 */
export class AnsiClean {
  /** 剥离 ANSI 转义序列 + 回车符，返回纯文本 */
  static clean(input: string): string {
    if (input === '') { return ''; }
    let out: string = '';
    let i: number = 0;
    const ESC: string = '\u001B';
    while (i < input.length) {
      const ch: string = input[i];
      if (ch !== ESC) {
        if (ch !== '\r') { out += ch; }
        i++;
        continue;
      }
      // ESC 后面
      if (i + 1 >= input.length) { break; }
      const next: string = input[i + 1];
      if (next === '[') {
        // CSI 序列：找到 final byte (0x40-0x7E)
        i += 2;
        while (i < input.length) {
          const code: number = input.charCodeAt(i);
          if (code >= 0x40 && code <= 0x7E) { i++; break; }
          i++;
        }
      } else if (next === ']') {
        // OSC 序列：跳到 BEL(0x07) 或 ESC\
        i += 2;
        while (i < input.length) {
          if (input[i] === '\u0007') { i++; break; }
          if (input[i] === ESC && i + 1 < input.length && input[i + 1] === '\\') { i += 2; break; }
          i++;
        }
      } else {
        // 二字节转义：跳过 ESC + 下一字节
        i += 2;
      }
    }
    return out;
  }
}
