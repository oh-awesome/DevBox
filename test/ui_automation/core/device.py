"""
device.py —— hdc 设备控制层（截图/点击/输入/应用生命周期）

实证约束（2026-11-10 真机标定）：
- snapshot_display 是活的（force-stop 立即反映）；dumpLayout 换页后会卡幽灵帧 → 不用
- 窗口失焦后 uiInput click 全无效（像素 diff=0 判定）→ 交互前 forceStop+start 夺焦
- python subprocess 走 cmd.exe：`>/dev/null` 与 `MSYS_NO_PATHCONV=1` 前缀语法都不可用
  → 路径转换用正斜杠目标名规避；一律不带重定向
- 屏幕分辨率 3120×2080；DevBox 窗口 [76,76]-[2166,1470]
"""

import subprocess
import time
from PIL import Image

SCREEN_W, SCREEN_H = 3120, 2080
WIN = (76, 76, 2166, 1470)          # DevBox 主窗口 bbox
PKG = 'com.develop.opensource.devbox'


def _sh(cmd: str, timeout: float = 40) -> str:
    r = subprocess.run(cmd, shell=True, capture_output=True, timeout=timeout)
    return r.stdout.decode('utf-8', errors='replace')


class Device:
    def __init__(self, workdir: str):
        self.workdir = workdir
        self._shot_seq = 0

    # ── 截图 ─────────────────────────────────────────────
    def screenshot(self, name: str = '') -> Image.Image:
        """全屏截图 → 返回 PIL Image（设备端暂存 + 回收 PC）"""
        self._shot_seq += 1
        n = name or f'shot{self._shot_seq}'
        dev = f'/data/local/tmp/ui_{n}.jpeg'
        _sh(f'hdc shell "snapshot_display -f {dev}"', 60)
        pc = f'{self.workdir}/{n}.jpeg'
        _sh(f'hdc file recv {dev} {pc}', 40)
        return Image.open(pc).convert('RGB')

    def window(self, img: Image.Image) -> Image.Image:
        """裁剪 DevBox 主窗口区域"""
        return img.crop(WIN)

    # ── 输入 ─────────────────────────────────────────────
    def click(self, x: int, y: int, settle: float = 1.2) -> None:
        _sh(f'hdc shell "uitest uiInput click {x} {y}"')
        time.sleep(settle)

    def key(self, k: str) -> None:
        _sh(f'hdc shell "uitest uiInput keyEvent {k}"')

    def input_text(self, x: int, y: int, text: str) -> None:
        _sh(f'hdc shell "uitest uiInput inputText {x} {y} {text}"')

    # ── 应用生命周期 ─────────────────────────────────────
    def restart_app(self, wait: float = 9.0, test_mode: bool = True) -> None:
        """强杀+冷启（夺回输入焦点 + 重置 UI 状态机；失焦后点击全无效的可靠恢复手段）
        test_mode：--ps test_mode true → 应用主窗口 maximize 全屏锁定
        （窗口位置/尺寸漂移是视觉测试坐标失稳的根源——鸿蒙自由窗口特性）"""
        _sh(f'hdc shell "aa force-stop {PKG}"', 30)
        time.sleep(1.5)
        ps = ' --ps test_mode true' if test_mode else ''
        _sh(f'hdc shell "aa start -b {PKG} -a EntryAbility{ps}"', 30)
        time.sleep(wait)

    def front_app(self) -> str:
        out = _sh('hdc shell "dumpsys window | grep -E \'mFocusedWindow\'"', 20)
        return out
