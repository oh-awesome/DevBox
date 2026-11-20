/**
 * DevBox 全局主题 —— DESIGN.md 实现（Figma 桌面端 UI 基准）
 * 深色（默认）+ 浅色双模式可切换；12px 正文 / 圆角 2-4-6-8 / 无投影无边框卡
 */

export class DarkPalette {
  static readonly BG: string = '#1E1E1E';
  static readonly BG_PANEL: string = '#2A2A2A';
  static readonly BG_ELEVATED: string = '#3E3E3E';
  static readonly BG_HOVER: string = '#404040';
  static readonly BORDER: string = '#4A4A4A';
  static readonly BORDER_STRONG: string = '#555555';
  static readonly TEXT_PRIMARY: string = '#FFFFFF';
  static readonly TEXT_SECONDARY: string = '#C8C8C8';
  static readonly TEXT_TERTIARY: string = '#9A9A9A';
  // 审计 U-P0-5：#707070 在 BG_CARD #2A2A2A 上对比度 2.9:1（WCAG AA 失败）
  // → 对齐 TEXT_TERTIARY #9A9A9A（对比度 5.8:1）
  static readonly TEXT_MUTED: string = '#9A9A9A';
  static readonly ACCENT_SELECT: string = '#FF7A00';
  static readonly ACCENT_ACTION: string = '#0B6FCC';  // 审计 P1：原 #0D99FF 白字 3.0<4.5 → 加深至 4.6:1
  static readonly SUCCESS: string = '#22C55E';
  static readonly WARNING: string = '#FACC15';
  static readonly DANGER: string = '#F87171';
  static readonly TERM_BG: string = '#181818';
  static readonly TERM_FG: string = '#C8C8C8';
  static readonly TERM_GREEN: string = '#22C55E';
  static readonly TERM_ORANGE: string = '#FB923C';
  static readonly TERM_CYAN: string = '#38BDF8';
  static readonly TERM_RED: string = '#F87171';
  static readonly SHADOW: string = 'rgba(0,0,0,0.5)';
  static readonly SCROLLBAR: string = '#555555';
  static readonly SELECT_SOFT: string = 'rgba(255,122,0,0.15)';
  static readonly ACTION_SOFT: string = 'rgba(13,153,255,0.15)';
  static readonly SUCCESS_SOFT: string = 'rgba(34,197,94,0.12)';
  static readonly WARNING_SOFT: string = 'rgba(250,204,21,0.12)';
  static readonly DANGER_SOFT: string = 'rgba(248,113,113,0.12)';
}

export class LightPalette {
  static readonly BG: string = '#F4F4F5';
  static readonly BG_PANEL: string = '#FFFFFF';
  static readonly BG_ELEVATED: string = '#E4E4E7';
  static readonly BG_HOVER: string = '#D4D4D8';
  static readonly BORDER: string = '#C4C4CC';
  static readonly BORDER_STRONG: string = '#71717A';
  static readonly TEXT_PRIMARY: string = '#18181B';
  static readonly TEXT_SECONDARY: string = '#3F3F46';
  static readonly TEXT_TERTIARY: string = '#71717A';
  // 审计 U-P0-5：#71717A 在 #FFFFFF 上对比度 4.33:1（略低于 AA 4.5）
  // → 降至 #64646B（对比度 5.2:1）
  static readonly TEXT_MUTED: string = '#64646B';
  static readonly ACCENT_SELECT: string = '#EA580C';
  static readonly ACCENT_ACTION: string = '#2563EB';
  static readonly SUCCESS: string = '#16A34A';
  static readonly WARNING: string = '#A16207';  // 审计 P1：原 #CA8A04 2.9<4.5 → 加深至 4.8:1
  static readonly DANGER: string = '#DC2626';
  static readonly TERM_BG: string = '#18181B';
  static readonly TERM_FG: string = '#A1A1AA';
  static readonly TERM_GREEN: string = '#22C55E';
  static readonly TERM_ORANGE: string = '#FB923C';
  static readonly TERM_CYAN: string = '#38BDF8';
  static readonly TERM_RED: string = '#F87171';
  static readonly SHADOW: string = 'rgba(0,0,0,0.12)';
  static readonly SCROLLBAR: string = '#C4C4CC';
  static readonly SELECT_SOFT: string = 'rgba(234,88,12,0.10)';
  static readonly ACTION_SOFT: string = 'rgba(37,99,235,0.10)';
  static readonly SUCCESS_SOFT: string = 'rgba(22,163,74,0.10)';
  static readonly WARNING_SOFT: string = 'rgba(202,138,4,0.10)';
  static readonly DANGER_SOFT: string = 'rgba(220,38,38,0.10)';
}

export type ThemeMode = 'dark' | 'light';

export class DevTheme {
  static mode: ThemeMode = 'light';
  static BG: string = DarkPalette.BG;
  static BG_SIDEBAR: string = DarkPalette.BG_PANEL;
  static BG_CARD: string = DarkPalette.BG_PANEL;
  static BG_SUBTLE: string = DarkPalette.BG_ELEVATED;
  static BG_MUTED: string = DarkPalette.BG_ELEVATED;
  static BG_DIALOG: string = DarkPalette.BG_ELEVATED;
  static BG_INPUT: string = DarkPalette.BG_PANEL;
  static BG_TABLE_HEADER: string = DarkPalette.BG_ELEVATED;
  static BG_HOVER: string = DarkPalette.BG_HOVER;
  static BG_TERM: string = DarkPalette.TERM_BG;
  static BG_OVERLAY: string = 'rgba(0,0,0,0.55)';
  static BORDER: string = DarkPalette.BORDER;
  static BORDER_STRONG: string = DarkPalette.BORDER_STRONG;
  static BORDER_INPUT: string = DarkPalette.BORDER;
  static DIALOG_BORDER: string = DarkPalette.BORDER;
  static TEXT_PRIMARY: string = DarkPalette.TEXT_PRIMARY;
  static TEXT_SECONDARY: string = DarkPalette.TEXT_SECONDARY;
  static TEXT_TERTIARY: string = DarkPalette.TEXT_TERTIARY;
  static TEXT_MUTED: string = DarkPalette.TEXT_MUTED;
  static TEXT_INVERSE: string = DarkPalette.BG;
  static PRIMARY: string = DarkPalette.ACCENT_ACTION;
  static PRIMARY_FG: string = '#FFFFFF';
  static SELECT: string = DarkPalette.ACCENT_SELECT;
  static SUCCESS: string = DarkPalette.SUCCESS;
  static WARNING: string = DarkPalette.WARNING;
  static DANGER: string = DarkPalette.DANGER;
  static INFO: string = DarkPalette.ACCENT_ACTION;
  static BG_ACCENT_PRIMARY: string = DarkPalette.ACTION_SOFT;
  static BG_ACCENT_SUCCESS: string = DarkPalette.SUCCESS_SOFT;
  static BG_ACCENT_WARNING: string = DarkPalette.WARNING_SOFT;
  static BG_ACCENT_DANGER: string = DarkPalette.DANGER_SOFT;
  static BG_ACCENT_INFO: string = DarkPalette.ACTION_SOFT;
  static BG_ACCENT_SELECT: string = DarkPalette.SELECT_SOFT;
  static SIDEBAR_ACTIVE_BG: string = DarkPalette.SELECT_SOFT;
  static SIDEBAR_ACTIVE_BORDER: string = DarkPalette.ACCENT_SELECT;
  static DIALOG_SHADOW_COLOR: string = DarkPalette.SHADOW;
  static SCROLL_BAR_COLOR: string = DarkPalette.SCROLLBAR;
  static TERM_GREEN: string = DarkPalette.TERM_GREEN;
  static TERM_WHITE: string = DarkPalette.TERM_FG;
  static TERM_ORANGE: string = DarkPalette.TERM_ORANGE;
  static TERM_CYAN: string = DarkPalette.TERM_CYAN;
  static TERM_RED: string = DarkPalette.TERM_RED;
  static BG_ACCENT_BLUE: string = DarkPalette.ACTION_SOFT;
  static BG_ACCENT_GREEN: string = DarkPalette.SUCCESS_SOFT;
  static BG_ACCENT_RED: string = DarkPalette.DANGER_SOFT;
  static BG_ACCENT_AMBER: string = DarkPalette.WARNING_SOFT;
  static BG_ACCENT_CYAN: string = DarkPalette.ACTION_SOFT;
  static BG_ACCENT_PURPLE: string = DarkPalette.ACTION_SOFT;

  // ── 组件级派生色（打磨批次收敛——此前硬编码在组件内） ──
  // DevBtn hover
  static BTN_HOVER_DANGER_LIGHT: string = '#FBE9E5';
  static BTN_HOVER_DANGER_DARK: string = '#3A1F1B';
  static BTN_HOVER_PLAIN_LIGHT: string = '#E6F2FC';
  static BTN_HOVER_PLAIN_DARK: string = '#243444';
  static BTN_HOVER_DANGER: string = '#F56A45';
  static BTN_HOVER_PRIMARY: string = '#33A3FF';
  // DevRowProgress 渐变
  static PROGRESS_GRADIENT_START_LIGHT: string = '#33A3FF';
  static PROGRESS_GRADIENT_END: string = '#0D99FF';
  static PROGRESS_GRADIENT_START_DARK: string = '#5CB8FF';
  static PROGRESS_GLOW_LIGHT: string = '#660D99FF';
  static PROGRESS_GLOW_DARK: string = '#800D99FF';
  // MCP JSON 底色
  static CODE_BG_LIGHT: string = '#EEEEF0';
  static CODE_BG_DARK: string = '#161618';
  static CODE_COPIED_LIGHT: string = '#E8F5E9';
  static CODE_COPIED_DARK: string = '#1B2E1F';
  // applyTheme 写入的语义色别名（静态声明——无声明赋值会报不存在）
  static ACCENT_BLUE: string = DarkPalette.ACCENT_ACTION;
  static ACCENT_CYAN: string = DarkPalette.ACCENT_ACTION;
  static ACCENT_CYAN_DARK: string = DarkPalette.TEXT_TERTIARY;
  static ACCENT_BLUE600: string = DarkPalette.ACCENT_ACTION;
  static ACCENT_BLUE500: string = DarkPalette.ACCENT_ACTION;
  static ACCENT_GREEN: string = DarkPalette.SUCCESS;
  static ACCENT_PURPLE: string = DarkPalette.TEXT_TERTIARY;
  static ACCENT_RED: string = DarkPalette.DANGER;
  static ACCENT_AMBER: string = DarkPalette.WARNING;
  static TEXT_SLATE300: string = DarkPalette.TEXT_SECONDARY;
  static TEXT_SLATE400: string = DarkPalette.TEXT_TERTIARY;
  static TEXT_SLATE500: string = DarkPalette.TEXT_MUTED;
  static TEXT_SLATE600: string = DarkPalette.TEXT_MUTED;
  static currentThemeId: string = 'figma_dark';
  static readonly FS_H1: number = 16;
  static readonly FS_H2: number = 13;
  static readonly FS_H3: number = 12;
  static readonly FS_BODY: number = 12;
  static readonly FS_LABEL: number = 11;
  static readonly FS_CAPTION: number = 11;
  static readonly FS_BADGE: number = 11;
  static readonly FS_STAT: number = 20;
  static readonly MONO_FONT: string = 'JetBrains Mono';
  static readonly RADIUS_XS: number = 2;
  static readonly RADIUS_SM: number = 4;
  static readonly RADIUS_MD: number = 6;
  static readonly RADIUS_LG: number = 8;
  static readonly RADIUS_XL: number = 8;
  static readonly RADIUS_FULL: number = 999;
  static readonly SCROLL_BAR_WIDTH: number = 4;
  static readonly SIDEBAR_WIDTH: number = 248;
  static readonly CONTENT_PAD: number = 24;
  static readonly GRID_GAP: number = 16;
  static readonly SHADOW_SM: ShadowOptions = { radius: 0, offsetX: 0, offsetY: 0, color: 'rgba(0,0,0,0)' };
  static readonly SHADOW_MD: ShadowOptions = { radius: 24, offsetX: 0, offsetY: 8, color: 'rgba(0,0,0,0.45)' };

  static applyTheme(mode: ThemeMode): void {
    DevTheme.mode = mode;
    const p = mode === 'light' ? LightPalette : DarkPalette;
    DevTheme.BG = p.BG; DevTheme.BG_SIDEBAR = p.BG_PANEL; DevTheme.BG_CARD = p.BG_PANEL;
    DevTheme.BG_SUBTLE = p.BG_ELEVATED; DevTheme.BG_MUTED = p.BG_ELEVATED; DevTheme.BG_DIALOG = p.BG_ELEVATED;
    DevTheme.BG_INPUT = p.BG_PANEL; DevTheme.BG_TABLE_HEADER = p.BG_ELEVATED; DevTheme.BG_HOVER = p.BG_HOVER;
    DevTheme.BG_TERM = p.TERM_BG; DevTheme.BG_OVERLAY = mode === 'light' ? 'rgba(0,0,0,0.3)' : 'rgba(0,0,0,0.55)';
    DevTheme.BORDER = p.BORDER; DevTheme.BORDER_STRONG = p.BORDER_STRONG; DevTheme.BORDER_INPUT = p.BORDER; DevTheme.DIALOG_BORDER = p.BORDER;
    DevTheme.TEXT_PRIMARY = p.TEXT_PRIMARY; DevTheme.TEXT_SECONDARY = p.TEXT_SECONDARY;
    DevTheme.TEXT_TERTIARY = p.TEXT_TERTIARY; DevTheme.TEXT_MUTED = p.TEXT_MUTED; DevTheme.TEXT_INVERSE = p.BG;
    DevTheme.PRIMARY = p.ACCENT_ACTION; DevTheme.SELECT = p.ACCENT_SELECT;
    DevTheme.SUCCESS = p.SUCCESS; DevTheme.WARNING = p.WARNING; DevTheme.DANGER = p.DANGER; DevTheme.INFO = p.ACCENT_ACTION;
    DevTheme.BG_ACCENT_PRIMARY = p.ACTION_SOFT; DevTheme.BG_ACCENT_SUCCESS = p.SUCCESS_SOFT;
    DevTheme.BG_ACCENT_WARNING = p.WARNING_SOFT; DevTheme.BG_ACCENT_DANGER = p.DANGER_SOFT;
    DevTheme.BG_ACCENT_INFO = p.ACTION_SOFT; DevTheme.BG_ACCENT_SELECT = p.SELECT_SOFT;
    DevTheme.SIDEBAR_ACTIVE_BG = p.SELECT_SOFT; DevTheme.SIDEBAR_ACTIVE_BORDER = p.ACCENT_SELECT;
    DevTheme.DIALOG_SHADOW_COLOR = p.SHADOW; DevTheme.SCROLL_BAR_COLOR = p.SCROLLBAR;
    DevTheme.TERM_GREEN = p.TERM_GREEN; DevTheme.TERM_WHITE = p.TERM_FG;
    DevTheme.TERM_ORANGE = p.TERM_ORANGE; DevTheme.TERM_CYAN = p.TERM_CYAN; DevTheme.TERM_RED = p.TERM_RED;
    DevTheme.BG_ACCENT_BLUE = p.ACTION_SOFT; DevTheme.BG_ACCENT_GREEN = p.SUCCESS_SOFT;
    DevTheme.BG_ACCENT_RED = p.DANGER_SOFT; DevTheme.BG_ACCENT_AMBER = p.WARNING_SOFT;
    DevTheme.BG_ACCENT_CYAN = p.ACTION_SOFT; DevTheme.BG_ACCENT_PURPLE = p.ACTION_SOFT;
    DevTheme.ACCENT_BLUE = p.ACCENT_ACTION; DevTheme.ACCENT_CYAN = p.ACCENT_ACTION;
    DevTheme.ACCENT_CYAN_DARK = p.TEXT_TERTIARY; DevTheme.ACCENT_BLUE600 = p.ACCENT_ACTION;
    DevTheme.ACCENT_BLUE500 = p.ACCENT_ACTION; DevTheme.ACCENT_GREEN = p.SUCCESS;
    DevTheme.ACCENT_PURPLE = p.TEXT_TERTIARY; DevTheme.ACCENT_RED = p.DANGER; DevTheme.ACCENT_AMBER = p.WARNING;
    DevTheme.TEXT_SLATE300 = p.TEXT_SECONDARY; DevTheme.TEXT_SLATE400 = p.TEXT_TERTIARY;
    DevTheme.TEXT_SLATE500 = p.TEXT_MUTED; DevTheme.TEXT_SLATE600 = p.TEXT_MUTED;
    DevTheme.currentThemeId = mode === 'light' ? 'figma_light' : 'figma_dark';
  }

  static toggle(): ThemeMode {
    const newMode: ThemeMode = DevTheme.mode === 'dark' ? 'light' : 'dark';
    DevTheme.applyTheme(newMode);
    return newMode;
  }

}
