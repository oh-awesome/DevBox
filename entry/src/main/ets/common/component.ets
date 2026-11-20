/**
 * DevBox 统一组件库（唯一 UI 组件居所）
 *
 * 规则：
 * 1. 页面（pages/*.ets）不允许定义任何 struct 组件或 @Builder 画 UI，
 *    只允许组合本文件导出的 Dev* 组件与 IBest-UI-V2 原子组件；
 * 2. 所有颜色一律取 DevTheme 令牌，禁止硬编码色值；
 * 3. 交互动原子件优先用 IBest：按钮 IBestButton / 开关 IBestSwitch /
 *    标签 IBestTag / 分段 IBestSegmented / 进度 IBestProgress /
 *    空态 IBestEmpty / 折叠 IBestCollapse / 数字滚动 IBestCountTo；
 * 4. 提示统一 DevToast，二次确认统一 DevConfirm.ask()。
 */

import { pasteboard } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { common, Want } from '@kit.AbilityKit';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import { DevTheme } from './DevTheme';
import { RuntimeMgr } from '../utils/RuntimeMgr';
import { TaskQueue } from '../utils/TaskQueue';
import { FeatureScope } from '../utils/FeatureScope';
import { TrayService } from '../utils/TrayService';
import { promptAction } from '@kit.ArkUI';
import { RepoVersion } from '../utils/ArtifactsRepo';
import fs from '@ohos.file.fs';
import { IBestToast, IBestCountTo, IBestEmpty, IBestSwitch, IBestProgress, IBestStringNumber, IBestPagination } from '@ibestservices/ibest-ui-v2';









// ─── 空插槽默认值 ───────────────────────────────────────────

@Builder
function devNoop() {
}

// ─── 工具函数 ───────────────────────────────────────────────

/** 复制文本到剪贴板并提示 */
export function copyText(text: string): void {
  try {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data);
    DevToast.ok($r('app.string.component_1'));
  } catch (_) {
  }
}

/** 统一 Toast（message 支持 string 与 Resource——文案资源化后 $r 引用可直接传入） */
export class DevToast {
  static show(message: string | Resource): void {
    IBestToast.show({ message: message, duration: 1800, position: 'center' });
  }

  static ok(message: string | Resource): void {
    IBestToast.show({ type: 'success', message: message, duration: 1800, position: 'center' });
  }

  static fail(message: string | Resource): void {
    IBestToast.show({ type: 'fail', message: message, duration: 2400, position: 'center' });
  }
}

/** 二次确认（全局，无需 controller） */

/** DevConfirm.choice 的选项（ArkTS 严格模式：对象字面量类型须显式接口） */
export interface DevConfirmChoice {
  text: string;
  danger?: boolean;
}

export class DevConfirm {
  /** 系统级确认弹窗（AlertDialog 声明式：按钮横排 buttonDirection 可控——
   *  原 promptAction.showDialog 竖线排布固定不可改，用户要横排；API 形态不变调用方零改动） */
  static show(title: string, message: string, confirmText: string, danger: boolean, onOk: () => void): void {
    AlertDialog.show({
      title: title,
      message: message,
      buttonDirection: DialogButtonDirection.HORIZONTAL,
      buttons: [
        { value: '取消', fontColor: DevTheme.TEXT_TERTIARY, action: (): void => {} },
        { value: confirmText, fontColor: danger ? DevTheme.DANGER : DevTheme.PRIMARY, action: onOk },
      ],
    } as AlertDialogParamWithOptions);
  }

  static ask(title: string, message: string, onOk: () => void, confirmText: string = '确定'): void {
    DevConfirm.show(title, message, confirmText, false, onOk);
  }

  /** 危险操作确认（卸载/删除/覆盖） */
  static danger(title: string, message: string, onOk: () => void, confirmText: string = '确认执行'): void {
    DevConfirm.show(title, message, confirmText, true, onOk);
  }

  /**
   * 多选项确认（系统原生三按钮竖线形态，与 show/danger 同一视觉规范——
   * 自绘 CustomDialog 做多选项曾致风格不一致，用户反馈统一到系统弹窗）。
   * choices：[{text, danger}]（最多 3 项，系统 showDialog 上限）；onChoice 回调所选下标（-1=取消/关闭）
   */
  static choice(title: string, message: string,
    choices: DevConfirmChoice[],
    onChoice: (idx: number) => void): void {
    const buttons: AlertDialogButtonOptions[] = [];
    for (let i = 0; i < choices.length && i < 3; i++) {
      const idx: number = i;
      buttons.push({
        value: choices[i].text,
        fontColor: choices[i].danger === true ? DevTheme.DANGER : DevTheme.PRIMARY,
        action: (): void => { onChoice(idx); },
      });
    }
    AlertDialog.show({
      title: title,
      message: message,
      buttonDirection: DialogButtonDirection.HORIZONTAL,
      buttons: buttons,
    } as AlertDialogParamWithOptions);
  }
}


/** 终端行着色规则 */
export function termLineColor(line: string): string {
  if (line.indexOf('DEVBOX_FAIL') >= 0 || line.indexOf('✗') >= 0 || line.indexOf('error') >= 0
    || line.indexOf('Error') >= 0 || line.indexOf('失败') >= 0) {
    return DevTheme.TERM_RED;
  }
  if (line.indexOf('DEVBOX_OK') >= 0 || line.indexOf('✓') >= 0 || line.indexOf('成功') >= 0
    || line.indexOf('done') >= 0 || line.indexOf('Done') >= 0) {
    return DevTheme.TERM_GREEN;
  }
  if (line.indexOf('$') === 0 || line.indexOf('#') === 0) {
    return DevTheme.TERM_CYAN;
  }
  if (line.indexOf('%') >= 0 && line.indexOf('|') >= 0) {
    return DevTheme.TERM_ORANGE;
  }
  return DevTheme.TERM_WHITE;
}

/** 状态 → 语义色（0 未装 1 正常 2 警告 3 异常） */
export function statusColor(s: number): string {
  if (s === 1) {
    return DevTheme.SUCCESS;
  }
  if (s === 2) {
    return DevTheme.WARNING;
  }
  if (s === 3) {
    return DevTheme.DANGER;
  }
  return DevTheme.TEXT_MUTED;
}

// ─── 1. 页头 ────────────────────────────────────────────────

@Component
export struct DevPageHeader {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop title: string;
  @Prop subtitle: string;
  @Prop showDivider: boolean;
  @BuilderParam actions: () => void = devNoop;

  build() {
    Column() {
      Row() {
        Column({ space: 4 }) {
          Text(this.title)
            .fontSize(DevTheme.FS_H1)
            .fontWeight(FontWeight.Medium)
            .fontColor(DevTheme.TEXT_PRIMARY)
            .lineHeight(26)
          if (this.subtitle !== '') {
            Text(this.subtitle)
              .fontSize(DevTheme.FS_BODY)
              .fontColor(DevTheme.TEXT_TERTIARY)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        this.actions()
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (this.showDivider) {
        Divider()
          .color(DevTheme.BORDER)
          .margin({ top: 14 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

// ─── 2. 区块标题 ────────────────────────────────────────────

@Component
export struct DevSectionTitle {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop title: string;
  @Prop actionLabel: string;
  onAction: () => void = () => {
  };

  build() {
    Row() {
      Text(this.title)
        .fontSize(DevTheme.FS_H3)
        .fontWeight(FontWeight.Medium)
        .fontColor(DevTheme.TEXT_PRIMARY)
        .layoutWeight(1)
      if (this.actionLabel !== '') {
        Text(this.actionLabel)
          .fontSize(DevTheme.FS_H3)
          .fontColor(DevTheme.TEXT_TERTIARY)
          .onClick(() => {
            this.onAction();
          })
      }
    }
    .width('100%')
  }
}

// ─── 3. 通用卡片 ────────────────────────────────────────────

@Component
export struct DevCard {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop title: string;
  @Prop subtitle: string;
  /** 左侧强调竖条颜色；'' 不显示 */
  @Prop accent: string;
  @Prop pad: number;
  icon: Resource | null = null;
  @BuilderParam content: () => void = devNoop;

  build() {
    Column() {
      if (this.title !== '' || this.icon !== null || this.accent !== '') {
        Row({ space: 10 }) {
          if (this.accent !== '') {
            Column()
              .width(3)
              .height(16)
              .borderRadius(2)
              .backgroundColor(this.accent)
          }
          if (this.icon !== null) {
            Image(this.icon)
              .width(20)
              .height(20)
              .fillColor(DevTheme.TEXT_PRIMARY)
          }
          Column({ space: 2 }) {
            if (this.title !== '') {
              Text(this.title)
                .fontSize(DevTheme.FS_H3)
                .fontWeight(FontWeight.Medium)
                .fontColor(DevTheme.TEXT_PRIMARY)
            }
            if (this.subtitle !== '') {
              Text(this.subtitle)
                .fontSize(DevTheme.FS_CAPTION)
                .fontColor(DevTheme.TEXT_TERTIARY)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .margin({ bottom: 14 })
      }
      this.content()
    }
    .width('100%')
    .padding(this.pad)
    .borderRadius(DevTheme.RADIUS_LG)
    .backgroundColor(DevTheme.BG_CARD)
    .border(DevTheme.mode === 'light'
      ? { width: 1, color: DevTheme.BORDER }
      : { width: 0 })
    .alignItems(HorizontalAlign.Start)
  }
}

// ─── 3B. 弹窗内分节（无框无底，弹窗内禁用嵌套卡片） ──────────

@Component
export struct DevSection {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop title: string;
  @Prop subtitle: string;
  @Prop showDivider: boolean;
  @BuilderParam content: () => void = devNoop;

  build() {
    Column() {
      if (this.title !== '') {
        Text(this.title)
          .fontSize(DevTheme.FS_H3)
          .fontWeight(FontWeight.Medium)
          .fontColor(DevTheme.TEXT_PRIMARY)
          .width('100%')
          .margin({ bottom: 6 })
      }
      if (this.subtitle !== '') {
        Text(this.subtitle)
          .fontSize(DevTheme.FS_CAPTION)
          .fontColor(DevTheme.TEXT_TERTIARY)
          .width('100%')
          .margin({ bottom: 8 })
      }
      this.content()
      if (this.showDivider) {
        Divider()
          .color(DevTheme.BORDER)
          .margin({ top: 12 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

// ─── 13B. 多行输入（与 DevInput 同规格） ────────────────────

@Component
export struct DevArea {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop value: string;
  @Prop placeholder: string;
  @Prop areaHeight: number;
  @Prop mono: boolean;
  onChange: (v: string) => void = () => {
  };

  build() {
    TextArea({ text: this.value, placeholder: this.placeholder })
      .fontSize(DevTheme.FS_BODY)
      .fontFamily(this.mono ? DevTheme.MONO_FONT : '')
      .fontColor(DevTheme.TEXT_PRIMARY)
      .caretColor(DevTheme.PRIMARY)
      .placeholderColor(DevTheme.TEXT_MUTED)
      .backgroundColor(DevTheme.BG_INPUT)
      .borderRadius(DevTheme.RADIUS_XS)
      .border({ width: 1, color: DevTheme.BORDER_INPUT })
      .padding(8)
      .width('100%')
      .height(this.areaHeight > 0 ? this.areaHeight : 96)
      .onChange((v: string) => {
        this.onChange(v);
      })
  }
}

// ─── 4. 状态点 ──────────────────────────────────────────────

@Component
export struct DevStatusDot {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop status: number;
  @Prop label: string;
  @Prop dotSize: number;

  build() {
    Row({ space: 6 }) {
      Circle({ width: this.dotSize, height: this.dotSize })
        .fill(statusColor(this.status))
      if (this.label !== '') {
        Text(this.label)
          .fontSize(DevTheme.FS_LABEL)
          .fontWeight(FontWeight.Medium)
          .fontColor(statusColor(this.status))
      }
    }
    .alignItems(VerticalAlign.Center)
  }
}

// ─── 5. 语义 Chip ───────────────────────────────────────────

/** tone: primary / success / warning / danger / info / neutral */
@Component
export struct DevChip {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop text: string;
  @Prop tone: string;
  @Prop mono: boolean;

  private toneColor(): string {
    if (this.tone === 'success') {
      return DevTheme.SUCCESS;
    }
    if (this.tone === 'warning') {
      return DevTheme.WARNING;
    }
    if (this.tone === 'danger') {
      return DevTheme.DANGER;
    }
    if (this.tone === 'info') {
      return DevTheme.INFO;
    }
    if (this.tone === 'primary') {
      return DevTheme.PRIMARY;
    }
    return DevTheme.TEXT_TERTIARY;
  }

  private toneBg(): string {
    if (this.tone === 'success') {
      return DevTheme.BG_ACCENT_SUCCESS;
    }
    if (this.tone === 'warning') {
      return DevTheme.BG_ACCENT_WARNING;
    }
    if (this.tone === 'danger') {
      return DevTheme.BG_ACCENT_DANGER;
    }
    if (this.tone === 'info') {
      return DevTheme.BG_ACCENT_INFO;
    }
    if (this.tone === 'primary') {
      return DevTheme.BG_ACCENT_PRIMARY;
    }
    return DevTheme.BG_MUTED;
  }

  build() {
    Text(this.text)
      .fontSize(this.mono ? DevTheme.FS_CAPTION : DevTheme.FS_BADGE)
      .fontWeight(FontWeight.Medium)
      .fontFamily(this.mono ? DevTheme.MONO_FONT : '')
      .fontColor(this.toneColor())
      .height(32)   // 触控目标 ≥32vp（审计 U-P1-1 统一提升）
      .padding({ left: 8, right: 8 })
      .borderRadius(DevTheme.RADIUS_XS)
      .backgroundColor(this.toneBg())
      .maxLines(1)
  }
}

// ─── 6. 终端输出块 ──────────────────────────────────────────

@Component
export struct DevTerm {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop lines: string[];
  @Prop title: string;
  @Prop busy: boolean;
  @Prop termHeight: number;
  onClear: () => void = () => {
  };
  private scroller: Scroller = new Scroller();

  build() {
    Column() {
      Row() {
        Row({ space: 5 }) {
          Circle({ width: 6, height: 6 }).fill(DevTheme.BORDER_STRONG)
          Circle({ width: 6, height: 6 }).fill(DevTheme.BORDER_STRONG)
          Circle({ width: 6, height: 6 }).fill(DevTheme.BORDER_STRONG)
        }
        Text(this.title !== '' ? this.title : '终端')
          .fontSize(DevTheme.FS_CAPTION)
          .fontColor(DevTheme.TEXT_TERTIARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        if (this.busy) {
          Text($r('app.string.component_2'))
            .fontSize(DevTheme.FS_BADGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(DevTheme.WARNING)
        }
        if (this.lines.length > 0) {
          Text($r('app.string.component_3'))
            .fontSize(DevTheme.FS_CAPTION)
            .fontColor(DevTheme.TEXT_TERTIARY)
            .onClick(() => {
              this.onClear();
            })
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 6 })

      Scroll(this.scroller) {
        Column() {
          ForEach(this.lines, (l: string, idx: number) => {
            Text(l === '' ? ' ' : l)
              .fontSize(DevTheme.FS_CAPTION)
              .fontFamily(DevTheme.MONO_FONT)
              .fontColor(termLineColor(l))
              .width('100%')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }, (l: string, idx: number) => `${idx}`)
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 12 })
        .alignItems(HorizontalAlign.Start)
        .onAreaChange(() => {
          this.scroller.scrollEdge(Edge.Bottom);
        })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .scrollBarColor(DevTheme.SCROLL_BAR_COLOR)
      .scrollBarWidth(DevTheme.SCROLL_BAR_WIDTH)
    }
    .width('100%')
    .height(this.termHeight)
    .borderRadius(DevTheme.RADIUS_MD)
    .backgroundColor(DevTheme.BG_TERM)
    .alignItems(HorizontalAlign.Start)
  }
}

// ─── 7. 命令行展示（含复制） ─────────────────────────────────

@Component
export struct DevCmdLine {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop cmd: string;
  @Prop label: string;

  build() {
    Row({ space: 8 }) {
      Text(this.label !== '' ? this.label : '$')
        .fontSize(DevTheme.FS_CAPTION)
        .fontFamily(DevTheme.MONO_FONT)
        .fontColor(DevTheme.SUCCESS)
      Text(this.cmd)
        .fontSize(DevTheme.FS_CAPTION)
        .fontFamily(DevTheme.MONO_FONT)
        .fontColor(DevTheme.TEXT_SECONDARY)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text($r('app.string.brewcomponents_2'))
        .fontSize(DevTheme.FS_CAPTION)
        .fontColor(DevTheme.TEXT_TERTIARY)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(DevTheme.RADIUS_XS)
        .backgroundColor(DevTheme.BG_MUTED)
        .onClick(() => {
          copyText(this.cmd);
        })
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 8, bottom: 8 })
    .borderRadius(DevTheme.RADIUS_MD)
    .backgroundColor(DevTheme.BG_TERM)
  }
}

// ─── 8. 键值行 ──────────────────────────────────────────────

@Component
export struct DevKVRow {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop k: string;
  @Prop v: string;
  @Prop copyable: boolean;
  @Prop mono: boolean;

  build() {
    Row() {
      Text(this.k)
        .fontSize(DevTheme.FS_LABEL)
        .fontColor(DevTheme.TEXT_TERTIARY)
        .width(110)
      Text(this.v === '' ? '—' : this.v)
        .fontSize(DevTheme.FS_BODY)
        .fontFamily(this.mono ? DevTheme.MONO_FONT : '')
        .fontColor(DevTheme.TEXT_SECONDARY)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.copyable && this.v !== '') {
        Text($r('app.string.brewcomponents_2'))
          .fontSize(DevTheme.FS_CAPTION)
          .fontColor(DevTheme.TEXT_TERTIARY)
          .onClick(() => {
            copyText(this.v);
          })
      }
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }
}

// ─── 9. 统计卡（数字滚动） ───────────────────────────────────

// ─── 10. 模块卡（Figma 网格单元：纯面板色块，选中态橙） ─────────

@Component
export struct DevModuleCard {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop title: string;
  @Prop main: string;
  @Prop detail: string;
  @Prop status: number;
  @Prop selected: boolean;
  @State pressed: boolean = false;
  @State hovered: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      // ── 背景：纯色平面卡（P0 修复——DESIGN.md"用户已明确否决"光晕/渐变/投影） ──
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(DevTheme.BG_CARD)

      // ── 前景信息（浮在光影上）：标题/主文案/注释三级层级 ──
      Column({ space: 5 }) {
        Row({ space: 10 }) {
          Text(this.title)
            .fontSize(DevTheme.FS_H1)
            .fontWeight(FontWeight.Medium)
            .fontColor(DevTheme.TEXT_PRIMARY)
            .layoutWeight(1)
          if (this.selected) {
            Circle({ width: 7, height: 7 }).fill(DevTheme.SELECT)
          } else {
            DevStatusDot({ status: this.status, label: '', dotSize: 7 })
          }
        }
        .width('100%')

        Text(this.main)
          .fontSize(DevTheme.FS_BODY + 1)
          .fontColor(DevTheme.TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.detail)
          .fontSize(DevTheme.FS_CAPTION)
          .fontColor(DevTheme.TEXT_TERTIARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding(12)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .aspectRatio(2.3)
    .borderRadius(DevTheme.RADIUS_LG)
    .clip(true)
    .border(DevTheme.mode === 'light'
      ? { width: 1, color: this.selected ? DevTheme.SELECT : DevTheme.BORDER }
      : { width: 0 })
    .scale(this.pressed ? { x: 1.02, y: 1.02 } : (this.hovered ? { x: 1.035, y: 1.035 } : { x: 1, y: 1 }))
    .translate({ y: this.hovered ? -3 : 0 })
    
    .animation({ duration: 160, curve: Curve.Friction })
    .onHover((isHover: boolean) => {
      this.hovered = isHover;
    })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      this.onTap();
    })
  }
}

// ─── 11. 套件卡（快速开始） ─────────────────────────────────


// ─── 12. 通用列表行 ─────────────────────────────────────────


// ─── 13. 输入框 ─────────────────────────────────────────────

@Component
export struct DevInput {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop value: string;
  @Prop placeholder: string;
  @Prop mono: boolean;
  @State focused: boolean = false;
  onChange: (v: string) => void = () => {
  };

  build() {
    TextInput({ text: this.value, placeholder: this.placeholder })
      .fontSize(DevTheme.FS_BODY)
      .height(36)
      .fontFamily(this.mono ? DevTheme.MONO_FONT : '')
      .fontColor(DevTheme.TEXT_PRIMARY)
      .caretColor(DevTheme.PRIMARY)
      .placeholderColor(DevTheme.TEXT_MUTED)
      .backgroundColor(DevTheme.BG_INPUT)
      .borderRadius(DevTheme.RADIUS_SM)
      .border({ width: 1, color: this.focused ? DevTheme.PRIMARY : DevTheme.BORDER_INPUT })
      .padding({ left: 12, right: 12 })
      .width('100%')
      .onFocus(() => {
        this.focused = true;
      })
      .onBlur(() => {
        this.focused = false;
      })
      .onChange((v: string) => {
        this.onChange(v);
      })
  }
}

// ─── 14. 空状态 ─────────────────────────────────────────────

@Component
export struct DevEmpty {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop text: string;
  @Prop hint: string;
  @Prop image: string;
  @BuilderParam action: () => void = devNoop;

  build() {
    Column({ space: 6 }) {
      IBestEmpty({
        description: this.text,
        imageSize: 90,
      })
      if (this.hint !== '') {
        Text(this.hint)
          .fontSize(DevTheme.FS_CAPTION)
          .fontColor(DevTheme.TEXT_TERTIARY)
      }
      this.action()
    }
    .width('100%')
    .padding({ top: 24, bottom: 24 })
    .alignItems(HorizontalAlign.Center)
  }
}

// ─── 15. 分段 Tab（设计规格：26 高 r4 chip 组 · 间距 8） ───

@Component
export struct DevSegmentTabs {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop options: string[];
  @Prop active: number;
  @State focusedIdx: number = -1;
  /** Enter 激活防抖时间戳（按住 Enter 的自动重复会连发 Down） */
  private lastKeyTs: number = 0;
  onChange: (idx: number) => void = () => {
  };

  /** 键盘激活：自定义组件的 onClick 不会自动映射 Enter（Button 组件内部行为），
   *  需 onKeyEvent 手动触发；300ms 抑制按住不放的连发 */
  private keyActivate(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down
      || (event.keyCode !== KeyCode.KEYCODE_ENTER && event.keyCode !== KeyCode.KEYCODE_NUMPAD_ENTER)) {
      return false;
    }
    const now = Date.now();
    if (now - this.lastKeyTs < 300) {
      return false;
    }
    this.lastKeyTs = now;
    return true;
  }

  build() {
    Row({ space: 8 }) {
      ForEach(this.options, (label: string, idx: number) => {
        Text(label)
          .fontSize(DevTheme.FS_BODY)
          .fontWeight(this.active === idx ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.active === idx ? DevTheme.TEXT_PRIMARY : DevTheme.TEXT_TERTIARY)
          .height(32)
          .padding({ left: 12, right: 12 })
          .borderRadius(DevTheme.RADIUS_SM)
          .backgroundColor(this.active === idx ? DevTheme.BG_SUBTLE
            : (this.focusedIdx === idx ? DevTheme.BG_HOVER : Color.Transparent))
          .focusable(true)
          .onFocus(() => {
            this.focusedIdx = idx;
          })
          .onBlur(() => {
            if (this.focusedIdx === idx) {
              this.focusedIdx = -1;
            }
          })
          .onKeyEvent((event: KeyEvent) => {
            if (this.keyActivate(event) && this.active !== idx) {
              this.onChange(idx);
            }
          })
          .onClick(() => {
            if (this.active !== idx) {
              this.onChange(idx);
            }
          })
      }, (label: string, idx: number) => `${idx}_${label}_${this.active === idx}`)
    }
    .width('100%')
  }
}

// ─── 15B. 按钮（设计规格：mini 22 / small 26 / normal 30 · r6） ──

@Component
export struct DevBtn {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop text: string;
  /** mini | small | normal */
  @Prop buttonSize: string;
  /** plain = 透明底 + 边框 */
  @Prop plain: boolean;
  /** danger = 红（plain 时红字红边） */
  @Prop danger: boolean;
  @Prop loading: boolean;
  /** 禁用态：半透明、点击无效 */
  @Prop disabled: boolean;
  @State hovered: boolean = false;
  @State focused: boolean = false;
  @State pressed: boolean = false;
  /** Enter 激活防抖时间戳（按住 Enter 的自动重复会连发 Down） */
  private lastKeyTs: number = 0;
  onTap: () => void = () => {
  };

  /** 键盘激活：自定义组件的 onClick 不会自动映射 Enter（Button 组件内部行为），
   *  需 onKeyEvent 手动触发；300ms 抑制按住不放的连发 */
  private keyActivate(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down
      || (event.keyCode !== KeyCode.KEYCODE_ENTER && event.keyCode !== KeyCode.KEYCODE_NUMPAD_ENTER)) {
      return false;
    }
    const now = Date.now();
    if (now - this.lastKeyTs < 300) {
      return false;
    }
    this.lastKeyTs = now;
    return true;
  }

  private h(): number {
    // 审计 U-P1-1：触控目标 PC 底线 32vp（主操作≥40）——mini/small 此前
    // 26/28 低于自定 ≥28 规则，统一提升
    if (this.buttonSize === 'mini') {
      return 32;
    }
    if (this.buttonSize === 'small') {
      return 32;
    }
    return 40;
  }

  /** hover 态底色：实体按钮提亮一档，plain 换悬浮底 */
  private btnBg(): ResourceColor {
    if (this.disabled) {
      // 禁用态冻结 hover 变色，仅靠整体半透明表达
      if (this.plain) {
        return this.danger ? DevTheme.BG_ACCENT_DANGER : DevTheme.BG_HOVER;
      }
      return this.danger ? DevTheme.DANGER : DevTheme.PRIMARY;
    }
    if (this.plain) {
      if (!this.hovered) {
        return this.danger ? DevTheme.BG_ACCENT_DANGER : DevTheme.BG_HOVER;
      }
      return this.danger
        ? (this.themeReact === 'light' ? DevTheme.BTN_HOVER_DANGER_LIGHT : DevTheme.BTN_HOVER_DANGER_DARK)
        : (this.themeReact === 'light' ? DevTheme.BTN_HOVER_PLAIN_LIGHT : DevTheme.BTN_HOVER_PLAIN_DARK);
    }
    if (!this.hovered) {
      return this.danger ? DevTheme.DANGER : DevTheme.PRIMARY;
    }
    return this.danger ? DevTheme.BTN_HOVER_DANGER : DevTheme.BTN_HOVER_PRIMARY;
  }

  build() {
    Row({ space: 6 }) {
      if (this.loading) {
        LoadingProgress()
          .width(this.buttonSize === 'mini' ? 12 : 14)
          .height(this.buttonSize === 'mini' ? 12 : 14)
          .color(this.plain ? (this.danger ? DevTheme.DANGER : DevTheme.PRIMARY) : DevTheme.PRIMARY_FG)
      }
      Text(this.text)
        .fontSize(this.buttonSize === 'mini' ? DevTheme.FS_LABEL : DevTheme.FS_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.plain
          ? (this.danger ? DevTheme.DANGER : DevTheme.TEXT_SECONDARY)
          : DevTheme.PRIMARY_FG)
    }
    .height(this.h())
    .padding({ left: 12, right: 12 })
    .justifyContent(FlexAlign.Center)
    .borderRadius(DevTheme.RADIUS_MD)
    .backgroundColor(this.btnBg())
    .border(this.plain && (this.hovered || this.focused) && !this.disabled
      ? { width: 1, color: this.danger ? DevTheme.DANGER : DevTheme.PRIMARY }
      : { width: 0 })
    .opacity(this.disabled ? 0.45 : 1)
    .animation({ duration: 120, curve: Curve.EaseOut })
    .focusable(true)
    .onHover((isHover: boolean) => {
      this.hovered = isHover;
    })
    .onFocus(() => {
      this.focused = true;
    })
    .onBlur(() => {
      this.focused = false;
    })
    .onKeyEvent((event: KeyEvent) => {
      if (this.keyActivate(event) && !this.loading && !this.disabled) {
        this.onTap();
      }
    })
    .onTouch((event: TouchEvent) => {
      this.pressed = event.type === TouchType.Down;
    })
    .scale({ x: this.pressed && !this.disabled ? 0.96 : 1, y: this.pressed && !this.disabled ? 0.96 : 1 })
    .onClick(() => {
      if (!this.loading && !this.disabled) {
        this.onTap();
      }
    })
  }
}

// ─── 16. 安装进度步骤条 ─────────────────────────────────────

/** current: 已完成的步骤数（=steps.length 表示全部成功）；failIdx: 失败步骤下标，-1 无 */
@Component
export struct DevProgressSteps {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop steps: string[];
  @Prop current: number;
  @Prop failIdx: number;

  build() {
    Column({ space: 8 }) {
      Row() {
        ForEach(this.steps, (s: string, i: number) => {
          Row() {
            Column() {
              if (this.failIdx === i) {
                Text('✗')
                  .fontSize(DevTheme.FS_CAPTION)
                  .fontColor(DevTheme.DANGER)
              } else if (i < this.current) {
                Text('✓')
                  .fontSize(DevTheme.FS_CAPTION)
                  .fontColor(DevTheme.PRIMARY_FG)
              } else {
                Text(`${i + 1}`)
                  .fontSize(DevTheme.FS_CAPTION)
                  .fontColor(i === this.current ? DevTheme.PRIMARY_FG : DevTheme.TEXT_TERTIARY)
              }
            }
            .width(16)
            .height(16)
            .borderRadius(8)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(
              this.failIdx === i ? DevTheme.BG_ACCENT_DANGER
                : (i < this.current ? DevTheme.SUCCESS
                  : (i === this.current ? DevTheme.PRIMARY : DevTheme.BG_MUTED)))
            .border({
              width: 1,
              color: this.failIdx === i ? DevTheme.DANGER
                : (i <= this.current ? Color.Transparent : DevTheme.BORDER_STRONG),
            })

            if (i < this.steps.length - 1) {
              Column()
                .height(2)
                .layoutWeight(1)
                .backgroundColor(i < this.current ? DevTheme.SUCCESS : DevTheme.BG_MUTED)
                .margin({ left: 6, right: 6 })
            }
          }
          .layoutWeight(i < this.steps.length - 1 ? 1 : 0)
          .alignItems(VerticalAlign.Center)
        }, (s: string, i: number) => `${i}_${s}_${this.current}_${this.failIdx}`)
      }
      .width('100%')

      Row() {
        ForEach(this.steps, (s: string, i: number) => {
          Text(s)
            .fontSize(DevTheme.FS_CAPTION)
            .fontColor(this.failIdx === i ? DevTheme.DANGER
              : (i <= this.current ? DevTheme.TEXT_SECONDARY : DevTheme.TEXT_MUTED))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .maxLines(1)
        }, (s: string, i: number) => `${i}_l_${this.current}_${this.failIdx}`)
      }
      .width('100%')
    }
    .width('100%')
  }
}

// ─── 17. 弹窗容器（吸收自 DevDialogPanel，zinc 化） ──────────

@Component
export struct DevDialogPanel {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop title: string;
  @Prop dialogWidth: number;
  @Prop dialogHeight: number;
  @Prop paddingValueLeft: number;
  @Prop paddingValueRight: number;
  @Prop paddingValueTop: number;
  @Prop paddingValueBottom: number;
  @BuilderParam content: () => void = devNoop;

  build() {
    Column() {
      if (this.title.length > 0) {
        Row() {
          Text(this.title)
            .fontSize(DevTheme.FS_H3)
            .fontWeight(FontWeight.Medium)
            .fontColor(DevTheme.TEXT_PRIMARY)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 18, bottom: 12 })

        Divider().color(DevTheme.BORDER)
      }

      if (this.dialogHeight > 0) {
        Scroll() {
          Column() {
            this.content();
          }
          .padding({
            left: this.paddingValueLeft,
            right: this.paddingValueRight,
            top: this.paddingValueTop,
            bottom: this.paddingValueBottom,
          })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .scrollBarColor(DevTheme.SCROLL_BAR_COLOR)
        .scrollBarWidth(DevTheme.SCROLL_BAR_WIDTH)
      } else {
        Column() {
          this.content();
        }
        .padding({
          left: this.paddingValueLeft,
          right: this.paddingValueRight,
          top: this.paddingValueTop,
          bottom: this.paddingValueBottom,
        })
      }
    }
    .width(this.dialogWidth)
    .height(this.dialogHeight > 0 ? this.dialogHeight : undefined)
    .borderRadius(DevTheme.RADIUS_LG)
    .backgroundColor(DevTheme.BG_DIALOG)
    .border({ width: 1, color: DevTheme.DIALOG_BORDER })
    .shadow(DevTheme.SHADOW_MD)
  }
}

// ─── 18. 侧边导航（应用壳） ─────────────────────────────────

interface NavEntry {
  key: string;
  label: string;
}

@Component
export struct DevSideNav {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop active: string;
  @State focusedKey: string = '';
  /** Enter 激活防抖时间戳（按住 Enter 的自动重复会连发 Down） */
  private lastKeyTs: number = 0;
  onNavigate: (page: string) => void = () => {
  };
  onFeedback: () => void = () => {
  };

  /** 键盘激活：自定义组件的 onClick 不会自动映射 Enter（Button 组件内部行为），
   *  需 onKeyEvent 手动触发；300ms 抑制按住不放的连发 */
  private keyActivate(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down
      || (event.keyCode !== KeyCode.KEYCODE_ENTER && event.keyCode !== KeyCode.KEYCODE_NUMPAD_ENTER)) {
      return false;
    }
    const now = Date.now();
    if (now - this.lastKeyTs < 300) {
      return false;
    }
    this.lastKeyTs = now;
    return true;
  }

  private langItems(): NavEntry[] {
    const items: NavEntry[] = [
      { key: 'python', label: 'Python' },
      { key: 'java', label: 'Java' },
      { key: 'rust', label: 'Rust' },
      { key: 'node', label: 'Node.js' },
      { key: 'lua', label: 'Lua' },
      { key: 'perl', label: 'Perl' },
      { key: 'go', label: 'Go' },
      { key: 'php', label: 'PHP' },
    ];
    // Ruby/Bun 商用发布不带（FeatureScope.RUBY_BUN=true 即恢复；2026-11-11 范围决策）
    if (FeatureScope.RUBY_BUN) {
      items.push({ key: 'ruby', label: 'Ruby' });
      items.push({ key: 'bun', label: 'Bun' });
    }
    return items;
  }

  private toolItems(): NavEntry[] {
    return [
      { key: 'tools', label: '通用工具' },
      { key: 'env', label: '环境变量' },
    ];
  }

  private pkgItems(): NavEntry[] {
    return [
      { key: 'brew', label: 'HarmonyBrew' },
      { key: 'conan', label: 'Conan' },
    ];
  }

  @Builder
  groupCaption(label: string) {
    Text(label)
      .fontSize(DevTheme.FS_CAPTION)
      .fontColor(DevTheme.TEXT_MUTED)
      .padding({ left: 10, top: 16, bottom: 4 })
      .width('100%')
  }

  @Builder
  navItem(entry: NavEntry, indent: boolean) {
    // P0 修复：选中态字号/字重/行高不变——仅文字转 PRIMARY + 橙底
    // （原 13→16+Bold 跳变导致下方条目位移 7px，DESIGN.md sidebar-item 规范）
    Text(entry.label)
      .fontSize(DevTheme.FS_H2)
      .fontWeight(this.active === entry.key ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.active === entry.key ? DevTheme.TEXT_PRIMARY : DevTheme.TEXT_SECONDARY)
      .width('100%')
      .textAlign(TextAlign.Start)
      .padding({ top: 8, bottom: 8, left: 10 })
      .borderRadius(DevTheme.RADIUS_SM)
      .backgroundColor(this.active === entry.key ? DevTheme.SIDEBAR_ACTIVE_BG
        : (this.focusedKey === entry.key ? DevTheme.BG_HOVER : Color.Transparent))
      .focusable(true)
      .onFocus(() => {
        this.focusedKey = entry.key;
      })
      .onBlur(() => {
        if (this.focusedKey === entry.key) {
          this.focusedKey = '';
        }
      })
      .onKeyEvent((event: KeyEvent) => {
        if (this.keyActivate(event)) {
          this.onNavigate(entry.key);
        }
      })
      .onClick(() => {
        this.onNavigate(entry.key);
      })
  }

  build() {
    Column() {
      // 图标 + 名称（单行，稍大）
      Row({ space: 9 }) {
        Image($r('app.media.DevBoxLogo'))
          .width(22)
          .height(22)
          .borderRadius(5)
        Text('DevBox')
          .fontSize(DevTheme.FS_H2)
          .fontWeight(FontWeight.Bold)
          .fontColor(DevTheme.TEXT_PRIMARY)
          .letterSpacing(0.3)
      }
      .width('100%')
      .margin({ bottom: 16 })

      // 导航菜单
      Scroll() {
        Column() {
          this.navItem({ key: 'overview', label: '总览' }, false)

          this.groupCaption('实用工具')
          ForEach(this.toolItems(), (e: NavEntry) => {
            this.navItem(e, true)
          }, (e: NavEntry) => e.key)

          this.groupCaption('语言环境')
          ForEach(this.langItems(), (e: NavEntry) => {
            this.navItem(e, true)
          }, (e: NavEntry) => e.key)

          this.groupCaption('通用包管理')
          ForEach(this.pkgItems(), (e: NavEntry) => {
            this.navItem(e, true)
          }, (e: NavEntry) => e.key)
        }
      .align(Alignment.TopStart)
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBarWidth(DevTheme.SCROLL_BAR_WIDTH)
      .scrollBarColor(DevTheme.SCROLL_BAR_COLOR)

      // 底部：应用项 + 反馈
      Column({ space: 2 }) {
        this.navItem({ key: 'about', label: '关于' }, true)

        Text($r('app.string.component_4'))
          .fontSize(DevTheme.FS_LABEL)
          .fontColor(DevTheme.TEXT_TERTIARY)
          .width('100%')
          .padding({ top: 10, bottom: 6, left: 10 })
          .borderRadius(DevTheme.RADIUS_SM)
          .backgroundColor(this.focusedKey === 'feedback' ? DevTheme.BG_HOVER : Color.Transparent)
          .focusable(true)
          .onFocus(() => {
            this.focusedKey = 'feedback';
          })
          .onBlur(() => {
            if (this.focusedKey === 'feedback') {
              this.focusedKey = '';
            }
          })
          .onKeyEvent((event: KeyEvent) => {
            if (this.keyActivate(event)) {
              this.onFeedback();
            }
          })
          .onClick(() => {
            this.onFeedback();
          })
      }
      .width('100%')
      .margin({ top: 8 })
      .border({ width: { top: 1 }, color: DevTheme.BORDER })
      .padding({ top: 8 })
    }
    .width(DevTheme.SIDEBAR_WIDTH)
    .height('100%')
    .padding({ top: 24, bottom: 20, left: 16, right: 16 })
    .backgroundColor(DevTheme.BG_SIDEBAR)
    .border({ width: { right: 1 }, color: DevTheme.BORDER })
    .alignItems(HorizontalAlign.Start)
  }
}

// ─── 18b. 主题滑块开关（iOS/macOS 式：滑块 + 目标模式图标） ──

@Component
export struct DevThemeSwitch {
  @StorageProp('themeMode') @Watch('onModeChanged') themeReact: string = 'dark';
  @State isLight: boolean = false;
  onToggle: () => void = () => {
  };

  aboutToAppear(): void {
    this.isLight = this.themeReact === 'light';
  }

  onModeChanged(): void {
    this.isLight = this.themeReact === 'light';
  }

  build() {
    // 与系统三键同规格：纯图标、无底色无边框、点击切换；颜色随主题（深色亮图标/浅色暗图标）
    Stack({ alignContent: Alignment.Center }) {
      if (this.isLight) {
        Stack() {
          Rect({ width: 1.5, height: 14 }).fill(DevTheme.TEXT_SECONDARY)
          Rect({ width: 14, height: 1.5 }).fill(DevTheme.TEXT_SECONDARY)
          Rect({ width: 1.5, height: 14 }).fill(DevTheme.TEXT_SECONDARY)
            .rotate({ angle: 45, centerX: '50%', centerY: '50%' })
          Rect({ width: 1.5, height: 14 }).fill(DevTheme.TEXT_SECONDARY)
            .rotate({ angle: -45, centerX: '50%', centerY: '50%' })
          Circle({ width: 8.5, height: 8.5 }).fill(DevTheme.BG)
          Circle({ width: 5, height: 5 }).fill(DevTheme.TEXT_SECONDARY)
        }
        .width(14)
        .height(14)
      } else {
        Stack() {
          Circle({ width: 13, height: 13 }).fill(DevTheme.TEXT_SECONDARY).offset({ x: -1.5 })
          Circle({ width: 11, height: 11 }).fill(DevTheme.BG).offset({ x: 3, y: -2 })
        }
        .width(16)
        .height(16)
      }
    }
    .width(46)
    .height(46)
    .borderRadius(DevTheme.RADIUS_MD)
    .onClick(() => {
      this.onToggle();
    })
  }
}

// ─── 19. 首次使用提示弹窗 ───────────────────────────────────

@CustomDialog
export struct DevTipsDialog {
  @State noLongerTip: boolean = false;
  controller?: CustomDialogController;
  onDone: (noLongerTip: boolean) => void = () => {
  };

  build() {
    DevDialogPanel({
      title: '开始使用',
      dialogWidth: 420,
      paddingValueLeft: 24,
      paddingValueRight: 24,
      paddingValueTop: 20,
      paddingValueBottom: 24,
    }) {
      Column({ space: 16 }) {
        Column({ space: 8 }) {
          Text($r('app.string.component_5'))
            .fontSize(DevTheme.FS_H3)
            .fontWeight(FontWeight.Medium)
            .fontColor(DevTheme.WARNING)
          Column({ space: 4 }) {
            Text($r('app.string.component_6'))
              .fontSize(DevTheme.FS_BODY)
              .fontColor(DevTheme.TEXT_SECONDARY)
            Text($r('app.string.component_7'))
              .fontSize(DevTheme.FS_BODY)
              .fontColor(DevTheme.TEXT_SECONDARY)
            Text($r('app.string.component_8'))
              .fontSize(DevTheme.FS_CAPTION)
              .fontColor(DevTheme.TEXT_MUTED)
              .lineHeight(16)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .borderRadius(DevTheme.RADIUS_MD)
        .backgroundColor(DevTheme.BG_ACCENT_WARNING)
        .alignItems(HorizontalAlign.Start)

        Text($r('app.string.component_9'))
          .fontSize(DevTheme.FS_CAPTION)
          .fontColor(DevTheme.INFO)
          .width('100%')
          .textAlign(TextAlign.Center)

        Row() {
          Row({ space: 8 }) {
            Checkbox()
              .select(this.noLongerTip)
              .shape(CheckBoxShape.ROUNDED_SQUARE)
              .selectedColor(DevTheme.PRIMARY)
              .onChange((value: boolean) => {
                this.noLongerTip = value;
              })
            Text($r('app.string.component_10'))
              .fontSize(DevTheme.FS_H2)
              .fontColor(DevTheme.TEXT_TERTIARY)
          }

          DevBtn({
            text: '知道了',
            buttonSize: 'small',
            onTap: () => {
              this.onDone(this.noLongerTip);
              this.controller?.close();
            },
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
    }
  }
}

// ─── 20. 在线反馈弹窗 ───────────────────────────────────────

@CustomDialog
export struct DevFeedbackDialog {
  @Prop appVersion: string;
  /** 反馈成功后的 issue 链接（父 Index 传入——提交成功即展示） */
  @Prop issueUrl: string;
  @Prop issueLinkVisible: boolean;
  @State typeIdx: number = 0;
  @State title: string = '';
  @State body: string = '';
  @State submitting: boolean = false;
  controller?: CustomDialogController;
  onSubmit: (typeIdx: number, title: string, body: string) => boolean = () => true;

  build() {
    DevDialogPanel({
      title: '在线反馈',
      dialogWidth: 460,
      paddingValueLeft: 24,
      paddingValueRight: 24,
      paddingValueTop: 20,
      paddingValueBottom: 24,
    }) {
      Column({ space: 14 }) {
        Row({ space: 8 }) {
          Text($r('app.string.component_11'))
            .fontSize(DevTheme.FS_H2)
            .fontColor(DevTheme.TEXT_TERTIARY)
          ForEach(['Bug', '建议', '疑问'], (label: string, idx: number) => {
            DevChip({
              text: label,
              tone: this.typeIdx === idx ? 'primary' : 'neutral',
              mono: false,
            })
              .onClick(() => {
                this.typeIdx = idx;
              })
          }, (label: string, idx: number) => `${label}_${this.typeIdx === idx}`)
        }
        .width('100%')

        DevInput({
          value: this.title,
          placeholder: '一句话描述问题',
          mono: false,
          onChange: (v: string) => {
            this.title = v;
          },
        })

        DevArea({
          value: this.body,
          placeholder: '详细描述您遇到的问题或建议…（环境信息将自动附加）',
          areaHeight: 120,
          mono: false,
          onChange: (v: string) => {
            this.body = v;
          },
        })

        Column({ space: 4 }) {
          Text($r('app.string.component_12'))
            .fontSize(DevTheme.FS_CAPTION)
            .fontColor(DevTheme.TEXT_MUTED)
            .width('100%')
          Text($r('app.string.component_13'))
            .fontSize(DevTheme.FS_CAPTION)
            .fontColor(DevTheme.TEXT_TERTIARY)
            .lineHeight(14)
            .width('100%')
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(DevTheme.RADIUS_MD)
        .backgroundColor(DevTheme.BG_SUBTLE)
        .alignItems(HorizontalAlign.Start)

        if (this.issueLinkVisible && this.issueUrl !== '') {
          Row({ space: 8 }) {
            Text($r('app.string.component_14'))
              .fontSize(DevTheme.FS_CAPTION)
              .fontColor(DevTheme.TEXT_TERTIARY)
            Text(this.issueUrl)
              .fontSize(DevTheme.FS_CAPTION)
              .fontColor(DevTheme.INFO)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => {
                try {
                  const ctx = getContext(this) as common.UIAbilityContext;
                  ctx.startAbility({
                    action: 'ohos.want.action.viewData',
                    uri: this.issueUrl,
                  } as Want);
                } catch (_) {
                }
              })
            Text($r('app.string.brewcomponents_2'))
              .fontSize(DevTheme.FS_CAPTION)
              .fontColor(DevTheme.INFO)
              .onClick(() => {
                const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.issueUrl);
                pasteboard.getSystemPasteboard().setData(data);
                DevToast.ok($r('app.string.component_15'));
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(DevTheme.RADIUS_MD)
          .backgroundColor(DevTheme.BG_ACCENT_SUCCESS)
        }

        Column() {
          DevBtn({
            text: this.submitting ? '提交中…' : '提交反馈',
            buttonSize: 'normal',
            loading: this.submitting,
            onTap: () => {
              if (this.title.trim().length === 0) {
                DevToast.show($r('app.string.component_16'));
                return;
              }
              if (this.body.trim().length === 0) {
                DevToast.show($r('app.string.component_17'));
                return;
              }
              this.submitting = true;
              const ok = this.onSubmit(this.typeIdx, this.title.trim(), this.body.trim());
              this.submitting = false;
              if (ok) {
                this.controller?.close();
              }
            },
          })
        }
        .width('100%')
      }
      .width('100%')
    }
  }
}

// ─── 21. 屏保覆盖层 ─────────────────────────────────────────



// ─── 22. 全局搜索面板 ───────────────────────────────────────


// ─── 23. 版本行（FlyEnv 对齐 A2-A6） ────────────────────────

// ─── 23-0. 行内进度公共组件（DevVersionRow / DevPkgRow 共用；组件审查重构①） ──
// 视觉以 DevVersionRow 现版为准：Loading + 4 高全圆角轨道 + 渐变填充 +
// 发光 shadow + 200ms EaseOut 宽度动画——抽取后语言行/包行视觉永久对齐
// （此前 PkgRow 注释写"同款"实则缺 shadow/动画，两处 ~70 行逐行重复）。

@Component
export struct DevRowProgress {
  /** 当前进度 0-100（显隐由调用方 busy 判定控制，组件只管画） */
  @Prop progress: number = 0;
  /** 尾部百分比文本槽（如 '78%'；空则不渲染） */
  @Prop trailingText: string = '';
  /** 尾部百分比槽固定宽度（防布局抖动：VersionRow 110 / PkgRow 36） */
  @Prop trailingWidth: number = 36;
  /** 第二尾部槽：已下载/总量（如 '78.1M/173M'，VersionRow 专用；空则不渲染） */
  @Prop subTrailingText: string = '';
  /** 第二尾部槽固定宽度（VersionRow 70） */
  @Prop subTrailingWidth: number = 70;
  @StorageProp('themeMode') themeReact: string = 'dark';

  build() {
    Row({ space: 8 }) {
      LoadingProgress()
        .width(12)
        .height(12)
        .color(DevTheme.PRIMARY)
      Stack({ alignContent: Alignment.Start }) {
        Column()
          .width('100%')
          .height(4)
          .borderRadius(DevTheme.RADIUS_FULL)
          .backgroundColor(DevTheme.BG_MUTED)
        Column()
          .width(`${Math.max(2, this.progress)}%`)
          .height(4)
          .borderRadius(DevTheme.RADIUS_FULL)
          .linearGradient({
            angle: 90,
            colors: this.themeReact === 'light'
              ? [[DevTheme.PROGRESS_GRADIENT_START_LIGHT, 0.0], [DevTheme.PROGRESS_GRADIENT_END, 1.0]]
              : [[DevTheme.PROGRESS_GRADIENT_START_DARK, 0.0], [DevTheme.PROGRESS_GRADIENT_END, 1.0]],
          })
          .shadow(this.themeReact === 'light'
            ? { radius: 6, color: DevTheme.PROGRESS_GLOW_LIGHT, offsetX: 0, offsetY: 0 }
            : { radius: 8, color: DevTheme.PROGRESS_GLOW_DARK, offsetX: 0, offsetY: 0 })
          .animation({ duration: 200, curve: Curve.EaseOut })
      }
      .layoutWeight(1)
      if (this.trailingText !== '') {
        Text(this.trailingText)
          .fontSize(DevTheme.FS_CAPTION)
          .fontColor(DevTheme.TEXT_TERTIARY)
          .width(this.trailingWidth)
          .textAlign(TextAlign.End)
      }
      if (this.subTrailingText !== '') {
        Text(this.subTrailingText)
          .fontSize(DevTheme.FS_CAPTION)
          .fontColor(DevTheme.TEXT_TERTIARY)
          .width(this.subTrailingWidth)
          .textAlign(TextAlign.End)
      }
    }
    .width('100%')
  }
}

export interface DevVersionData {
  ver: string;              // 版本号
  verLabel?: string;        // 展示用标签（如 'BiShengJDK 17.0.13'；空则用 ver）
  sizeLabel: string;        // 体积（可装区）
  installed: boolean;       // 已装
  active: boolean;          // 当前活跃
  alias: string;            // 别名（A3，桩展示）
  progress: number;         // 行内进度 0-100（A6；-1 无进度）
  downloadedLabel?: string; // 已下载字节数（人读格式，如 78.1M；安装中才有值）
  busyAction?: string;      // busy 行的动作类型（'install'|'uninstall'——卸载中真红/取消灰的分据）
}

@Component
export struct DevVersionRow {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop data: DevVersionData;
  @Prop sourcePending: boolean;
  @Prop dlText: string;
  @Prop isActive: boolean;
  onInstall: () => void = () => {
  };
  onSetActive: () => void = () => {
  };
  /** 安装/卸载进行中取消（P0：大包 2GB 下载半路可停，断点保留） */
  onCancel: () => void = () => {
  };
  onUninstall: () => void = () => {
  };

  private busy(): boolean {
    return this.data.progress >= 0 && this.data.progress < 100;
  }

  private busyLabel(): string {
    if (this.data.progress >= 0 && this.data.progress < 100) {
      return `${this.data.progress}%`;
    }
    return '';
  }

  /** 已下载/总量（如 78.1M/173M；安装中才有值） */
  private downloadLabel(): string {
    if (!this.busy() || this.dlText === undefined || this.dlText === '') {
      return '';
    }
    return this.dlText;
  }

  build() {
    Column({ space: 6 }) {
      // 单行布局：所有元素垂直居中（修复按钮偏上）
      Row({ space: 8 }) {
        Text(this.data.verLabel ?? this.data.ver)
          .fontSize(DevTheme.FS_H3)
          .fontWeight(FontWeight.Medium)
          .fontFamily(DevTheme.MONO_FONT)
          .fontColor(this.data.installed ? DevTheme.TEXT_PRIMARY : DevTheme.TEXT_SECONDARY)
        if (this.data.alias !== '') {
          DevChip({ text: this.data.alias, tone: 'neutral', mono: true })
        }
        if (this.isActive) {
          DevChip({ text: '活跃', tone: 'primary', mono: false })
        }
        Blank()
        if (!this.data.installed && this.data.sizeLabel !== '') {
          Text(this.data.sizeLabel)
            .fontSize(DevTheme.FS_CAPTION)
            .fontColor(DevTheme.TEXT_TERTIARY)
        }
        if (this.data.installed) {
          // 活跃行：仅徽章+卸载（唯一版本安装即活跃，自然无"设为活跃"）；
          // 非活跃行：设为活跃（修复/多版本切换）；全局任务中全部禁用灰显
          if (!this.isActive) {
            DevBtn({
              text: '设为活跃',
              buttonSize: 'mini',
              plain: true,
                            onTap: () => {
                this.onSetActive();
              },
            })
          }
          DevBtn({
            text: '卸载',
            buttonSize: 'mini',
            plain: true,
            danger: true,
                        onTap: () => {
              this.onUninstall();
            },
          })
        } else if (this.busy()) {
          // 进行中：可取消（大包耗时半路可停；断点保留重装续传——按钮反转成取消）
          // 显式动作类型判定（busyLabel 是百分比数字，含'卸载'判定为死代码——组件审查 P0-1）
          DevBtn({
            text: this.data.busyAction === 'uninstall' ? '卸载中…' : '取消',
            buttonSize: 'mini',
            loading: this.data.busyAction === 'uninstall',
            plain: true,
            danger: this.data.busyAction === 'uninstall',   // 卸载中=红（破坏性）；安装取消=中性
            onTap: () => {
              if (this.data.busyAction !== 'uninstall') {
                this.onCancel();   // 卸载不可取消（rm 半路目录状态不可控）；安装可取消（断点保留）
              }
            },
          })
        } else if (this.sourcePending) {
          DevChip({ text: '源待接入', tone: 'neutral', mono: false })
        } else {
          DevBtn({
            text: '安装',
            buttonSize: 'mini',
                        onTap: () => {
              this.onInstall();
            },
          })
        }
      }
      .width('100%')

      // 行内进度（对应版本行下方；百分比固定宽度防布局抖动）
      if (this.busy()) {
        DevRowProgress({
          progress: this.data.progress,
          trailingText: this.busyLabel(),
          trailingWidth: 110,
          subTrailingText: this.downloadLabel(),
          subTrailingWidth: 70,
        })
      }
    }
    .width('100%')
    .padding({ top: 8, bottom: 8, left: 10, right: 10 })
    .borderRadius(DevTheme.RADIUS_SM)
    .backgroundColor(this.isActive ? DevTheme.BG_ACCENT_SELECT : Color.Transparent)
    .alignItems(HorizontalAlign.Start)
    // 仅背景色过渡（全局 animation 会把子布局 reflow 也动画化，引发周期跳动）
    .transition(TransitionEffect.OPACITY.animation({ duration: 240 }).combine(TransitionEffect.translate({ y: 12 })))
  }
}

// ─── 23B. 软件包行（DevVersionRow 变形：名称+版本+描述+状态/操作） ──
// 通用工具 / HarmonyBrew / Conan 包管理共用；安装进度动效与语言页同款

export interface DevPkgData {
  name: string;           // 软件名（如 git / bun / zlib）
  ver: string;            // 当前版本（已装或可装最新）
  desc: string;           // 描述（自适应截断）
  sizeLabel: string;      // '4.9 MB'（可装时显示）
  installed: boolean;     // devbox 已装
  inPath: boolean;        // PATH 可用（外部安装）
  canUpdate: boolean;     // 已装旧版可更新
  progress: number;       // -1=空闲，0-99 安装中，100 完成
  showInstall: boolean;   // 是否显示安装按钮（已装的在目录列表中隐藏）
  isLatest: boolean;       // 当前版本是否为 latest（badge 逻辑）
  hasMultiVer: boolean;    // 是否有多个版本（版本号显示可点击样式）
}

@Component
export struct DevPkgRow {
  /** 行高参考值 62vp（名称+desc+padding，对齐 BrewListRow 规格）；pageSize 计算基于此 */
  static readonly ROW_HEIGHT: number = 62;
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop data: DevPkgData;
  @Prop progressText: string;
  onInstall: () => void = () => {
  };
  onUninstall: () => void = () => {
  };
  onVersionClick: () => void = () => {
  };
  /** 安装流日志查看（busy 行显示「日志」按钮；未传则不显示——node 页等不接） */
  onLogClick: () => void = () => {
  };
  /** 包安装取消（busy 行显示「取消」按钮；由页面设 true 才显示——通用工具等无取消通道的页不显示） */
  hasCancelInstall: boolean = false;
  onCancelInstall: (name: string) => void = (_n) => {
  };
  versions: string[] = [];  // 可选版本列表（供下拉选择）
  onVersionSelect: (ver: string) => void = () => {
  };
  /** 选中态（与 BrewListRow 对齐——组件统一） */
  @Prop selected: boolean = false;
  @Prop showBorder: boolean = true;  // 行视觉框（BrewListRow 同款圆角+描边）
  onRowClick: () => void = () => {
  };

  private busy(): boolean {
    return this.data.progress >= 0 && this.data.progress < 100;
  }


  build() {
    Column({ space: 2 }) {
      Row({ space: 8 }) {
        // ── 左：名称（审计 P1：加 maxLines+Ellipsis 防长名被固定行高裁切） ──
        Text(this.data.name)
          .fontSize(DevTheme.FS_H3)
          .fontWeight(FontWeight.Medium)
          .fontFamily(DevTheme.MONO_FONT)
          .fontColor(DevTheme.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        // ── 中：弹性填充 ──
        Blank()

        // ── 右：latest badge + 分类 + 版本 + 操作 ──
        if (this.data.hasMultiVer && this.data.isLatest) {
          Text('latest')
            .fontSize(DevTheme.FS_CAPTION)
            .fontColor(DevTheme.SUCCESS)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .borderRadius(4)
            .border({ width: 1, color: DevTheme.SUCCESS })
        } else if (this.data.hasMultiVer && !this.data.isLatest && !this.data.installed) {
          Text($r('app.string.component_18'))
            .fontSize(DevTheme.FS_CAPTION)
            .fontColor(DevTheme.WARNING)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .borderRadius(4)
            .border({ width: 1, color: DevTheme.WARNING })
        }

        if (this.data.desc !== '') {
          Text(this.data.desc)
            .fontSize(DevTheme.FS_CAPTION)
            .maxLines(1)
            .fontColor(DevTheme.TEXT_TERTIARY)
        }

        if (this.data.ver !== '' && !this.data.installed) {
          if (this.data.hasMultiVer) {
            // 多版本：虚线红框 + 下拉选择（bindContextMenu 在点击位置弹出）
            Text((this.data.ver) + ' ▾')
              .fontSize(DevTheme.FS_CAPTION)
              .fontColor(DevTheme.DANGER)
              .fontFamily(DevTheme.MONO_FONT)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .border({
                width: 1,
                color: DevTheme.DANGER,
                style: BorderStyle.Dashed
              })
              .borderRadius(4)
              .onClick(() => { this.onVersionClick(); })
          } else {
            Text(this.data.ver)
              .fontSize(DevTheme.FS_CAPTION)
              .fontColor(DevTheme.TEXT_TERTIARY)
              .fontFamily(DevTheme.MONO_FONT)
          }
        }

        if (this.data.installed && this.data.ver !== '') {
          if (this.data.hasMultiVer) {
            // 已装 + 多版本：版本号可点切换（装了 latest 想换其它版本不必卸载重装——用户反馈）
            Text(`已装 ${this.data.ver} ▾`)
              .fontSize(DevTheme.FS_CAPTION)
              .fontColor(DevTheme.DANGER)
              .fontFamily(DevTheme.MONO_FONT)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .border({
                width: 1,
                color: DevTheme.DANGER,
                style: BorderStyle.Dashed
              })
              .borderRadius(4)
              .onClick(() => { this.onVersionClick(); })
          } else {
            Text(`已装 ${this.data.ver}`)
              .fontSize(DevTheme.FS_CAPTION)
              .fontColor(DevTheme.TEXT_MUTED)
              .fontFamily(DevTheme.MONO_FONT)
          }
        }

        if (this.busy()) {
          // 安装中只显示「取消」（按钮反转成取消——与 DevVersionRow 统一；
          // 进度条本身已表达"安装中"，loading 按钮冗余）
          if (this.hasCancelInstall) {
            DevBtn({
              text: '取消',
              buttonSize: 'mini',
              plain: true,
              danger: false,   // 中性描边——与红色卸载按钮区分
              onTap: () => {
                this.onCancelInstall(this.data.name);
              },
            })
          } else {
            // 无取消通道的（通用工具等）：保持 loading 态
            DevBtn({
              text: '安装中…',
              buttonSize: 'mini',
              loading: true,
              onTap: () => {
              },
            })
          }
        } else if (this.data.installed) {
          if (this.data.canUpdate) {
            DevBtn({
              text: '更新',
              buttonSize: 'mini',
              onTap: () => {
                this.onInstall();
              },
            })
          }
          DevBtn({
            text: '卸载',
            buttonSize: 'mini',
            plain: true,
            danger: true,
            onTap: () => {
              this.onUninstall();
            },
          })
        } else if (this.data.showInstall) {
          DevBtn({
            text: '安装',
            buttonSize: 'mini',
            onTap: () => {
              this.onInstall();
            },
          })
        }
      }
      .width('100%')

      // 行内进度（DevRowProgress 公共组件——与 DevVersionRow 视觉永久对齐：
      // 此前缺发光 shadow 与 200ms 宽度动画，注释却写"同款"）
      if (this.busy()) {
        DevRowProgress({
          progress: this.data.progress,
          trailingText: `${this.data.progress}%`,
          trailingWidth: 36,
        })
      }
    }
    .width('100%')
    .padding({ top: 8, bottom: 8, left: 10, right: 10 })
    .borderRadius(DevTheme.RADIUS_MD)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.selected ? DevTheme.BG_ACCENT_PRIMARY : DevTheme.BG_CARD)
    .border({ width: 1, color: this.selected ? DevTheme.PRIMARY : DevTheme.BORDER })
    .onClick(() => { this.onRowClick(); })
    .transition(TransitionEffect.OPACITY.animation({ duration: 240 }).combine(TransitionEffect.translate({ y: 12 })))
  }
}

// ─── 23C. 可折叠包分组（已安装/未安装区域共用；折叠按钮在顶部标题行） ──

// ─── 24. 语言运行时页模板（FlyEnv 对齐 A1 四分栏 + A5 源；新语言配置化打桩） ──

export interface LangTabSpec {
  label: string;
  hint: string;
}

export interface LangRuntimeConfig {
  langKey: string;
  title: string;
  subtitle: string;
  sourceLabel: string;
  sourcePending: boolean;
  installed: DevVersionData[];
  available: DevVersionData[];
  ecoTabs: LangTabSpec[];
  pkgName?: string;    // manifest 包族键（如 java = BiShengJDK）；缺省取 langKey
  pkgNames?: string[]; // 多发行版（预留：manifest 出现 OpenJDK 等时启用分组）
  /** 自定义 Tab 标题（4 个；缺省 ['运行时', '包与工具', '项目', '设置']） */
  tabLabels?: string[];
}

@Component
export struct LangRuntimePage {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop cfg: LangRuntimeConfig;
  @State tab: number = 0;
  /** 页面自定义生态内容（npm 源/GOPROXY/pip 等；不传则 DevEmpty 占位） */
  @BuilderParam ecoContent: () => void;
  /** 自定义 Tab 1 内容（如 Python 镜像管理）；不传则用 ecoContent 卡片模式 */
  @BuilderParam tab1Content: () => void = devNoop;
  /** 自定义 Tab 2 内容（如 Python 包管理） */
  @BuilderParam tab2Content: () => void = devNoop;
  /** 自定义 Tab 3 内容（如 Python 项目管理） */
  @BuilderParam tab3Content: () => void = devNoop;
  // ── live 模式：真实数据源（ArtifactsRepo manifest + 本地目录/账本） ──
  @State liveInstalled: DevVersionData[] = [];
  @State liveAvailable: DevVersionData[] = [];
  @State repoVersions: RepoVersion[] = [];
  @State loadingSource: boolean = true;
  @State sourceReady: boolean = false;
  @State busyVer: string = '';        // 任务中的版本（镜像自全局 RuntimeMgr.busyTask）
  @State busyAction: string = '';     // 任务动作（'install'|'uninstall'——行按钮红/灰分据）
  @State busyPct: number = -1;
  @State busyText: string = '';
  @State busyDl: string = '';  // 已下载/总量（安装中实时更新）
  @StorageProp('runtime_epoch') @Watch('onEpoch') runtimeEpoch: number = 0;
  @StorageProp('runtime_busy') @Watch('onBusyChange') runtimeBusy: string = '';
  @StorageProp('task_queue_epoch') @Watch('onQueueEpoch') queueEpoch: number = 0;
  @State queueRev: number = 0;  // key 依赖：队列变化（入队/出队/推进）→ 行即时重渲染
  /** 跨页跳转提示（格式 pkg|mirror）：python 配源弹窗在任意页触发→Index 导航→本组件切 tab */
  @StorageProp('lang_tab_hint') @Watch('onTabHint') tabHint: string = '';

  private pkgKey(): string {
    return this.cfg.pkgName ?? this.cfg.langKey;
  }

  aboutToAppear(): void {
    this.syncBusy();
    this.refresh();
    this.onTabHint();   // 挂载前已有待处理跳转（跨页导航后本页新建的场景）
  }

  /** 消费跨页跳转提示（pkg|mirror）——命中本语言才切 tab，消费即清 */
  private onTabHint(): void {
    if (this.tabHint.startsWith(`${this.pkgKey()}|`)) {
      this.tab = this.mirrorTabIndex();
      AppStorage.setOrCreate('lang_tab_hint', '');
    }
  }

  /** 任意页面实例触发的任务完成（epoch 变化）→ 本实例刷新（修复跨实例回调失联导致的状态不同步） */
  private onEpoch(): void {
    this.syncBusy();
    this.refresh();
  }

  private onBusyChange(): void {
    this.syncBusy();
  }

  private syncBusy(): void {
    const b: string = this.runtimeBusy ?? '';
    if (b === '') {
      this.busyVer = '';
      this.busyPct = -1;
      this.busyText = '';
      this.busyDl = '';
      this.busyAction = '';
      return;
    }
    const seg: string[] = b.split('|');
    if (seg.length === 2 && seg[0] === this.pkgKey() && this.busyVer === '') {
      this.busyVer = seg[1];
      this.busyPct = this.busyPct < 0 ? 2 : this.busyPct;
    }
  }

  /** 队列变化（入队/出队/推进）→ 行重渲染（排队位次/取消按钮/按钮翻转） */
  private onQueueEpoch(): void {
    this.queueRev += 1;
  }

  /** 本版本任一动作（install/activate/uninstall）在 G1 队列的位次：-1 不在队；0 running；n>0 第 n 位 */
  private queuePosOf(v: DevVersionData): number {
    const ids: string[] = [
      `install_${this.pkgKey()}_${v.ver}`,
      `activate_${this.pkgKey()}_${v.ver}`,
      `uninstall_${this.pkgKey()}_${v.ver}`,
    ];
    const snap = TaskQueue.snapshot();
    for (let i = 0; i < snap.length; i++) {
      if (snap[i].group === 'runtime' && ids.indexOf(snap[i].id) >= 0) { return i; }
    }
    return -1;
  }

  private refreshGen: number = 0;

  /** 刷新：本地已装检测（即时）+ manifest 可装列表（异步）；带代际守卫，过期回调不落地（修复并发刷新竞态导致的已装/可装重复行） */
  private refresh(): void {
    const gen: number = ++this.refreshGen;
    const st = RuntimeMgr.detectInstalled(this.pkgKey());
    void gen;
    const rows: DevVersionData[] = [];
    for (let i = 0; i < st.vers.length; i++) {
      const distro = this.cfg.langKey !== this.pkgKey() ? `${this.pkgKey()} ` : '';
      rows.push({
        ver: st.vers[i], verLabel: `${distro}${st.vers[i]}`,
        sizeLabel: this.sizeOf(st.vers[i]), installed: true,
        active: st.vers[i] === st.active, alias: '', progress: -1, downloadedLabel: '',
      });
    }
    this.liveInstalled = rows;
    this.loadingSource = true;
    RuntimeMgr.fetchAvailable(this.pkgKey(), (list: RepoVersion[]) => {
      if (gen !== this.refreshGen) {
        return; // 已有更新一轮的刷新，丢弃本次过期结果
      }
      this.repoVersions = list;
      this.loadingSource = false;
      this.sourceReady = list.length > 0;
      const avail: DevVersionData[] = [];
      for (let i = 0; i < list.length; i++) {
        const rv = list[i];
        if (st.vers.indexOf(rv.ver) < 0) {
          const distroA = this.cfg.langKey !== this.pkgKey() ? `${this.pkgKey()} ` : '';
          avail.push({
            ver: rv.ver, verLabel: `${distroA}${rv.ver}`,
            sizeLabel: rv.sizeLabel, installed: false,
            active: false, alias: '', progress: -1, downloadedLabel: '',
          });
        }
      }
      this.liveAvailable = avail;
      // 已装行补体积标签 + 活跃版本置顶（其余保持版本序）
      for (let i = 0; i < rows.length; i++) {
        rows[i].sizeLabel = this.sizeOf(rows[i].ver);
      }
      rows.sort((a: DevVersionData, b: DevVersionData) => (a.active === b.active) ? 0 : (a.active ? -1 : 1));
        this.liveInstalled = rows;
    });
  }

  private sizeOf(ver: string): string {
    for (let i = 0; i < this.repoVersions.length; i++) {
      if (this.repoVersions[i].ver === ver) {
        return this.repoVersions[i].sizeLabel;
      }
    }
    return '';
  }

  private findRepo(ver: string): RepoVersion | null {
    for (let i = 0; i < this.repoVersions.length; i++) {
      if (this.repoVersions[i].ver === ver) {
        return this.repoVersions[i];
      }
    }
    return null;
  }

  /** 行内进度：running 行实时值；排队行 2%（驱动取消按钮+进度条占位） */
  private pctOf(v: DevVersionData): number {
    if (v.ver === this.busyVer) { return this.busyPct; }
    return this.queuePosOf(v) >= 0 ? 2 : -1;
  }

  /** 已下载/总量（running 实时）；排队行显示位次（dlText 槽复用） */
  private dlLabel(v: DevVersionData): string {
    if (v.ver === this.busyVer && this.busyDl !== '') { return this.busyDl; }
    const q: number = this.queuePosOf(v);
    return q > 0 ? `排队中（第 ${q} 位）` : (q === 0 ? '准备中…' : '');
  }

  private doInstall(v: DevVersionData): void {
    // P1 分队列：busy 时入队（TaskQueue 接管）——前置守卫去掉
    const rv: RepoVersion | null = this.findRepo(v.ver);
    if (rv === null) {
      DevToast.show($r('app.string.component_19'));
      return;
    }
    // busyVer 不前置覆盖（通用工具页同坑：A 完成清 busyVer 时 B 可能已接棒被误清）；
    // 排队行由 queueRev+queuePosOf 渲染，running 行由 claim（onBusyChange）+进度回调驱动
    RuntimeMgr.install(this.pkgKey(), rv, (pct: number, text: string) => {
      this.busyVer = v.ver;   // 自锚（syncBusy 万一没接住——页面重建等场景）
      this.busyAction = 'install';
      this.busyPct = pct;
      this.busyText = text;
      const dm = text.match(/(\d+(?:\.\d+)?M\/\d+M)/);
      this.busyDl = dm !== null ? dm[1] : '';
    }, (ok: boolean, msg: string) => {
      if (this.busyVer === v.ver) {   // 只清自己的 busy（A 完成时 busyVer 可能已是接棒的 B）
        this.busyVer = '';
        this.busyPct = -1;
        this.busyText = '';
        this.busyDl = '';
        this.busyAction = '';
      }
      DevToast.show(msg);
      this.refresh();
      // 装完首配提示（用户反馈：干净环境装完 python 应提示配源）：
      // pip 源未配置（provision 未写或无推荐源）→ 询问是否立即配置 → 跳镜像管理 tab
      if (ok && this.pkgKey() === 'python') {
        let configured = false;
        try {
          const conf: string = fs.readTextSync(`${HOME_PATH}/.pip/pip.conf`);
          configured = conf.indexOf('index-url') >= 0;
        } catch (_) {
        }
        if (!configured) {
          setTimeout(() => {
            DevConfirm.ask('pip 源未配置',
              '检测到 pip 镜像源尚未配置。是否立即配置？配置后安装第三方包将使用国内镜像，速度更快。',
              () => {
                // 跨页场景（弹窗时用户已离开 python 页——页面组件可能已销毁）：
                // AppStorage 通知 Index 导航 + 新实例消费 tab 提示；本页存活时本地切 tab 立即生效
                AppStorage.setOrCreate('nav_request', 'python');
                AppStorage.setOrCreate('lang_tab_hint', 'python|mirror');
                this.tab = this.mirrorTabIndex();
              },
              '立即配置');
          }, 400);
        }
      }
    });
  }

  /** 镜像管理 tab 下标（cfg.tabLabels 中「镜像」类 tab；找不到回退 1） */
  private mirrorTabIndex(): number {
    const labels: string[] = this.tabLabels();
    for (let i = 0; i < labels.length; i++) {
      if (labels[i].indexOf('镜像') >= 0) { return i; }
    }
    return 1;
  }

  /** 行级取消（P0+P1）：本版本排队中的动作（install/activate/uninstall）先出队；
   *  running 才走 RuntimeMgr.cancel（下载/解压/ensurepip 半路可停，断点保留重装续传；
   *  卸载不支持取消——rm 半路目录状态不可控，卸载本身秒~十几秒级） */
  private doCancel(v: DevVersionData): void {
    const kinds: string[] = ['install', 'activate', 'uninstall'];
    for (let i = 0; i < kinds.length; i++) {
      if (TaskQueue.dequeue(`${kinds[i]}_${this.pkgKey()}_${v.ver}`)) {
        DevToast.show($r('app.string.component_20'));
        return;
      }
    }
    RuntimeMgr.cancel();
    DevToast.show($r('app.string.component_21'));
  }

  private doSetActive(v: DevVersionData): void {
    // P1：busy 时入队（TaskQueue 接管）——前置守卫去掉
    RuntimeMgr.setActive(this.pkgKey(), v.ver, (ok: boolean, msg: string) => {
      if (this.busyVer === v.ver) {   // 防误清接棒任务
        this.busyVer = '';
        this.busyPct = -1;
        this.busyText = '';
        this.busyAction = '';
      }
      DevToast.show(msg);
      this.refresh();
    });
  }

  private askUninstall(v: DevVersionData): void {
    // P1：busy 时入队（TaskQueue 接管）——前置守卫去掉
    DevConfirm.danger(
      `卸载 ${this.cfg.title} ${v.ver}`,
      v.active ? (this.liveInstalled.filter((x: DevVersionData): boolean => x.ver !== v.ver).length > 0 ? `此为活跃版本，卸载后自动切换到 ${this.liveInstalled.filter((x: DevVersionData): boolean => x.ver !== v.ver)[0].ver}。` : '此为唯一版本，卸载后将清理 PATH。') : '将删除该版本运行时文件。',
      () => {
        RuntimeMgr.uninstall(this.pkgKey(), v.ver, this.repoVersions, (pct: number, text: string) => {
          this.busyVer = v.ver;   // 自锚
          this.busyAction = 'uninstall';   // 行按钮真红'卸载中…'
          this.busyPct = pct;
          this.busyText = text;
        }, (ok: boolean, msg: string) => {
          if (this.busyVer === v.ver) {   // 防误清接棒任务
            this.busyVer = '';
            this.busyPct = -1;
            this.busyText = '';
            this.busyAction = '';
          }
          DevToast.show(msg);
          this.refresh();
        });
      },
      '卸载',
    );
  }

  private stub(): void {
    DevToast.show($r('app.string.component_22'));
  }

  private tabLabels(): string[] {
    return this.cfg.tabLabels ?? ['运行时', '包与工具', '项目', '设置'];
  }

  private hasCustomTab(idx: number): boolean {
    if (idx === 1) { return this.tab1Content !== undefined && this.tab1Content !== devNoop; }
    if (idx === 2) { return this.tab2Content !== undefined && this.tab2Content !== devNoop; }
    if (idx === 3) { return this.tab3Content !== undefined && this.tab3Content !== devNoop; }
    return false;
  }

  build() {
    Column() {
      DevPageHeader({
        title: this.cfg.title,
        subtitle: this.cfg.subtitle,
        showDivider: false,
      })
      .margin({ bottom: 12 })

      if (this.tabLabels().length > 1) {   // 单 tab（商用范围裁剪后）不渲染 tab 行
        DevSegmentTabs({
          options: this.tabLabels(),
          active: this.tab,
          onChange: (idx: number) => {
            this.tab = idx;
          },
        })
        .margin({ bottom: 4 })
      }

      if (this.tab === 0) {
        // 运行时 Tab：保持 Scroll（版本列表可能较长）
        Scroll() {
          Column({ space: 12 }) {
            this.buildRuntimeTab()
          }
          .width('100%')
          .padding({ top: 8, bottom: 32 })
        }
        .layoutWeight(1)
        .align(Alignment.TopStart)
        .scrollBarWidth(DevTheme.SCROLL_BAR_WIDTH)
        .scrollBarColor(DevTheme.SCROLL_BAR_COLOR)
      } else if (this.hasCustomTab(this.tab) || this.tab >= 1) {
        // 自定义 Tab / 生态 Tab：内容直接填充剩余高度（由 Tab 自行管理滚动）
        Column() {
          if (this.tab === 1) {
            if (this.hasCustomTab(1)) { this.tab1Content() } else { this.buildEcoTab() }
          } else if (this.tab === 2) {
            if (this.hasCustomTab(2)) { this.tab2Content() } else { this.buildProjectTab() }
          } else {
            if (this.hasCustomTab(3)) { this.tab3Content() } else { this.buildSettingsTab() }
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: DevTheme.CONTENT_PAD, right: DevTheme.CONTENT_PAD, top: 8, bottom: 16 })
  }

  @Builder
  buildRuntimeTab() {
    Row({ space: 8 }) {
      Text($r('app.string.component_23'))
        .fontSize(DevTheme.FS_CAPTION)
        .fontColor(DevTheme.TEXT_TERTIARY)
      DevChip({
        text: this.sourceReady ? this.cfg.sourceLabel : (this.loadingSource ? '正在获取…' : '暂未收录'),
        tone: this.sourceReady ? 'info' : 'neutral',
        mono: false,
      })
      if (!this.sourceReady && !this.loadingSource) {
        Text($r('app.string.component_24'))
          .fontSize(DevTheme.FS_CAPTION)
          .fontColor(DevTheme.WARNING)
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
    }
    .width('100%')

    DevCard({ title: '已安装', subtitle: '', accent: '', pad: 12 }) {
      Column() {
        if (this.liveInstalled.length === 0) {
          Text($r('app.string.component_25'))
            .fontSize(DevTheme.FS_CAPTION)
            .fontColor(DevTheme.TEXT_TERTIARY)
            .width('100%')
            .padding({ top: 4, bottom: 4 })
        } else {
          ForEach(this.liveInstalled, (v: DevVersionData) => {
            DevVersionRow({
              data: {
                ver: v.ver, verLabel: v.verLabel, sizeLabel: v.sizeLabel, installed: v.installed,
                active: v.active, alias: v.alias, progress: this.pctOf(v),
                downloadedLabel: this.dlLabel(v),
                busyAction: this.busyVer === v.ver ? this.busyAction : '',
              },
              sourcePending: !this.sourceReady,
              dlText: this.dlLabel(v),
              isActive: v.active,
              onInstall: () => {
                this.doInstall(v);
              },
              onSetActive: () => {
                this.doSetActive(v);
              },
              onCancel: () => {
                this.doCancel(v);
              },
              onUninstall: () => {
                this.askUninstall(v);
              },
            })
          }, (v: DevVersionData) => `${v.ver}_${v.active}_${this.queueRev}_${this.busyVer === v.ver}`)
        }
      }
      .width('100%')
    }

    DevCard({ title: '可安装版本', subtitle: '', accent: '', pad: 12 }) {
      Column() {
        if (this.loadingSource) {
          Text($r('app.string.component_26'))
            .fontSize(DevTheme.FS_CAPTION)
            .fontColor(DevTheme.TEXT_TERTIARY)
            .width('100%')
            .padding({ top: 4, bottom: 4 })
        } else if (this.liveAvailable.length === 0 && this.sourceReady) {
          Text($r('app.string.component_27'))
            .fontSize(DevTheme.FS_CAPTION)
            .fontColor(DevTheme.TEXT_TERTIARY)
            .width('100%')
            .padding({ top: 4, bottom: 4 })
        }
        ForEach(this.liveAvailable, (v: DevVersionData) => {
          DevVersionRow({
            data: {
              ver: v.ver, verLabel: v.verLabel, sizeLabel: v.sizeLabel, installed: v.installed,
              active: v.active, alias: v.alias, progress: this.pctOf(v),
              busyAction: this.busyVer === v.ver ? this.busyAction : '',
            },
            sourcePending: !this.sourceReady,
              dlText: this.dlLabel(v),
              isActive: v.active,
            onInstall: () => {
              this.doInstall(v);
            },
            onSetActive: () => {
              this.doSetActive(v);
            },
            onCancel: () => {
              this.doCancel(v);
            },
            onUninstall: () => {
              this.askUninstall(v);
            },
          })
        }, (v: DevVersionData) => `${v.ver}_${v.active}_${this.queueRev}_${this.busyVer === v.ver}`)
      }
      .width('100%')
    }
  }

  @Builder
  buildEcoTab() {
    if (this.cfg.ecoTabs.length === 0) {
      DevEmpty({ text: '生态工具规划中', hint: '该语言的包与工具管理将随后续版本提供', image: 'default' })
    } else {
      ForEach(this.cfg.ecoTabs, (t: LangTabSpec) => {
        DevCard({ title: t.label, subtitle: t.hint, accent: '', pad: 12 }) {
          if (this.ecoContent !== undefined) {
            this.ecoContent()
          } else {
            DevEmpty({ text: '功能接入中', hint: '当前为界面预览', image: 'default' })
          }
        }
      }, (t: LangTabSpec) => t.label)
    }
  }

  @Builder
  buildProjectTab() {
    DevEmpty({ text: '暂无项目', hint: '项目识别与管理将随后续版本提供', image: 'default' })
  }

  @Builder
  buildSettingsTab() {
    DevCard({ title: '语言设置', subtitle: '镜像源与环境变量偏好', accent: '', pad: 12 }) {
      Column({ space: 8 }) {
        DevKVRow({ k: '默认安装源', v: this.cfg.sourceLabel, copyable: false, mono: false })
        Divider().color(DevTheme.BORDER)
        DevBtn({
          text: '配置镜像源',
          buttonSize: 'small',
          plain: true,
          onTap: () => {
            this.stub();
          },
        })
      }
      .width('100%')
    }
  }
}

// ─── 28. MCP 配置内容（双宿主复用组件：弹窗 McpConfigDialog 薄壳包装；页面/窗口宿主亦可直用。
//      内容收敛自 pages/mcp_manager.ets（较新：工具 13 条含 check_tool/get_system_info、
//      流式 HTTP 步骤文案、说明标题、MCP 服务器块标题）+ 弹窗版独有交互（已复制 ✓ 反馈、
//      IBestSwitch 开关、加深后的 JSON 灰底 #EEEEF0/#161618）──

/** MCP 工具清单 */
const MCP_TOOL_LIST: string[][] = [
  ['list_runtimes', '查询所有语言运行时及版本'],
  ['get_runtime_status', '查某语言安装/活跃状态'],
  ['install_runtime', '安装指定语言版本'],
  ['uninstall_runtime', '卸载语言版本（需确认）'],
  ['brew_list', 'HarmonyBrew 已装包列表'],
  ['pip_list', 'pip 已装 Python 包'],
  ['npm_list_global', 'npm 全局包'],
  ['goproxy_get', '查询 GOPROXY'],
  ['get_env_info', '环境信息（PATH / JAVA_HOME 等）'],
  ['list_tools', '可用通用工具列表'],
  ['check_tool', '检查某工具版本'],
  ['get_task_progress', '当前任务进度'],
  ['get_system_info', '系统信息'],
];

/** 应用配置 JSON 块（逐行渲染） */
const MCP_JSON_BLOCK: string[] = [
  '{',
  '  "mcpServers": {',
  '    "DevBox MCP": {',
  '      "url": "http://127.0.0.1:18765/mcp",',
  '      "headers": {}',
  '    }',
  '  }',
  '}',
];

const MCP_ENDPOINT: string = 'http://127.0.0.1:18765/mcp';
const MCP_CONFIG_TEXT: string = '{\n  "mcpServers": {\n    "DevBox MCP": {\n      "url": "http://127.0.0.1:18765/mcp",\n      "headers": {}\n    }\n  }\n}';

@Component
export struct McpConfigContent {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @StorageProp('mcp_enabled') @Watch('onMcpEnabledChange') mcpEnabled: boolean = true;
  @State tab: number = 0;
  @State copied: boolean = false;

  /** 标题字号（弹窗 18；更大面板/窗口宿主可传 20） */
  @Prop titleFontSize: number = 18;
  /** 关闭按钮回调：弹窗注入 controller.close()；窗口宿主可注入 destroyWindow 等 */
  onClose: () => void = () => {};

  /** MCP Server 在 TrayAbility 进程：管理通道跨进程发送启停命令（并持久化） */
  private onMcpEnabledChange(): void {
    AppStorage.setOrCreate('mcp_enabled', this.mcpEnabled);
    TrayService.setMcpRunning(this.mcpEnabled);
    // 开启 MCP 时引导通知授权（敏感操作确认通知是 MCP 安全链的一环）：
    // 前台拨开关正是系统授权框可弹的时机；已授权则静默（requestEnableNotification
    // 系统仅首次弹框，此后调用直接返回）
    if (this.mcpEnabled) {
      notificationManager.isNotificationEnabled().then((on: boolean) => {
        if (!on) {
          notificationManager.requestEnableNotification().catch((_e: object) => {});
        }
      }).catch((_e: object) => {});
    }
  }

  @Builder
  panelHeader() {
    // 关闭走系统路径（ESC / 点击遮罩 / 宿主窗口关闭）——与全局二级窗口一致，无 × 按钮
    Row({ space: 8 }) {
      Text($r('app.string.component_28'))
        .fontSize(this.titleFontSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(DevTheme.TEXT_PRIMARY)
      Blank()
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  @Builder
  serverBlock() {
    Column() {
      // ── 左：服务信息 / 右：开关 ──
      Row({ space: 12 }) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text($r('app.string.component_29'))
              .fontSize(DevTheme.FS_H1)
              .fontWeight(FontWeight.Medium)
              .fontColor(DevTheme.TEXT_PRIMARY)
            DevStatusDot({
              status: this.mcpEnabled ? 1 : 0,
              label: this.mcpEnabled ? '运行中' : '已关闭',
              dotSize: 7,
            })
          }

          // 地址 + 复制
          Row({ space: 6 }) {
            Text(MCP_ENDPOINT)
              .fontSize(DevTheme.FS_BODY)
              .fontColor(DevTheme.TEXT_SECONDARY)
              .fontFamily(DevTheme.MONO_FONT)
            DevBtn({
              text: '复制',
              buttonSize: 'mini',
              plain: true,
              onTap: () => {
                copyText(MCP_ENDPOINT);
              },
            })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        IBestSwitch({
          value: this.mcpEnabled,
          switchSize: 20,
          activeColor: DevTheme.SELECT,
          inactiveColor: DevTheme.BORDER_STRONG,
          onChange: (v: boolean | IBestStringNumber) => {
            this.mcpEnabled = v as boolean;
          },
        })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })

      // 通知引导（MCP 安全链：敏感操作经设备通知确认）——一句话 + 直达设置
      Row({ space: 8 }) {
        Text($r('app.string.component_30'))
          .fontSize(DevTheme.FS_CAPTION)
          .fontColor(DevTheme.TEXT_TERTIARY)
          .layoutWeight(1)
        DevBtn({
          text: '通知设置', buttonSize: 'mini', plain: true,
          onTap: () => {
            // 打开通知设置面板并回读结果（API 26：openNotificationSettingsWithResult
            // 返回 NotificationSetting，含 bannerEnabled/soundEnabled）——用户拨完开关
            // 回来即可检查横幅状态，未开启即时提示（横幅开关无编程 setter，只能用户手拨）
            const ctx: common.UIAbilityContext | undefined =
              AppStorage.get<common.UIAbilityContext>('ui_context_ctx');
            if (ctx === undefined || ctx === null) { return; }
            notificationManager.openNotificationSettingsWithResult(ctx).then((setting: notificationManager.NotificationSetting) => {
              if (setting.bannerEnabled === false) {
                DevToast.show($r('app.string.component_31'));
              }
            }).catch((_e: object) => {
              // 回读失败降级为普通打开
              notificationManager.openNotificationSettings(ctx).catch((_e2: object) => {
                DevToast.show($r('app.string.component_32'));
              });
            });
          },
        })
      }
      .width('100%')
      .padding({ left: 14, right: 14, bottom: 12 })
    }
    .width('100%')
    .borderRadius(DevTheme.RADIUS_LG)
    .backgroundColor(DevTheme.BG_CARD)
    .border({ width: 1, color: DevTheme.BORDER })
    .margin({ bottom: 12 })
  }

  @Builder
  tabBar() {
    Row({ space: 0 }) {
      ForEach(['应用配置', '工具列表'], (label: string, idx: number) => {
        Text(label)
          .fontSize(this.tab === idx ? 14 : 13)
          .fontWeight(this.tab === idx ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.tab === idx ? DevTheme.TEXT_PRIMARY : DevTheme.TEXT_TERTIARY)
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .borderRadius(DevTheme.RADIUS_MD)
          .backgroundColor(this.tab === idx ? DevTheme.BG_HOVER : Color.Transparent)
          .onClick(() => { this.tab = idx; })
      }, (label: string) => label)
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  @Builder
  configTab() {
    Column({ space: 12 }) {
      // 说明
      Text($r('app.string.component_33'))
        .fontSize(DevTheme.FS_H2)
        .fontWeight(FontWeight.Medium)
        .fontColor(DevTheme.TEXT_PRIMARY)
        .width('100%')

      // 步骤 1
      Row({ space: 10 }) {
        Text('1').fontSize(DevTheme.FS_H3).fontWeight(FontWeight.Medium).fontColor(DevTheme.PRIMARY_FG)
          .width(20).height(20).textAlign(TextAlign.Center).borderRadius(10).backgroundColor(DevTheme.PRIMARY)
        Text($r('app.string.component_34'))
          .fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_SECONDARY).layoutWeight(1).lineHeight(20)
      }.width('100%')

      // 步骤 2
      Row({ space: 10 }) {
        Text('2').fontSize(DevTheme.FS_H3).fontWeight(FontWeight.Medium).fontColor(DevTheme.PRIMARY_FG)
          .width(20).height(20).textAlign(TextAlign.Center).borderRadius(10).backgroundColor(DevTheme.PRIMARY)
        Text($r('app.string.component_35'))
          .fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_SECONDARY).layoutWeight(1)
      }.width('100%')

      // 步骤 3
      Row({ space: 10 }) {
        Text('3').fontSize(DevTheme.FS_H3).fontWeight(FontWeight.Medium).fontColor(DevTheme.PRIMARY_FG)
          .width(20).height(20).textAlign(TextAlign.Center).borderRadius(10).backgroundColor(DevTheme.PRIMARY)
        Text($r('app.string.component_36'))
          .fontSize(DevTheme.FS_BODY).fontColor(DevTheme.TEXT_SECONDARY).layoutWeight(1)
      }.width('100%')

      // JSON 代码块（灰底 + 复制图标 + 已复制反馈）
      Stack({ alignContent: Alignment.TopEnd }) {
        Column({ space: 2 }) {
          ForEach(MCP_JSON_BLOCK, (line: string) => {
            Text(line).fontSize(DevTheme.FS_H3).fontFamily(DevTheme.MONO_FONT)
              .fontColor(DevTheme.TEXT_SECONDARY).lineHeight(18)
          }, (line: string) => line)
        }
        .width('100%').padding(14).alignItems(HorizontalAlign.Start)

        // 复制图标（点击变 ✓ + 背景变绿 + 1.5s 恢复）
        Stack({ alignContent: Alignment.Center }) {
          if (this.copied) {
            // 已复制：显示 ✓
            Text('✓')
              .fontSize(DevTheme.FS_H2)
              .fontWeight(FontWeight.Medium)
              .fontColor(DevTheme.SUCCESS)
          } else {
            // 正常：双叠矩形
            Column().width(9).height(11).borderRadius(2)
              .border({ width: 1, color: DevTheme.TEXT_TERTIARY }).offset({ x: -2, y: 2 })
            Column().width(9).height(11).borderRadius(2)
              .backgroundColor(this.themeReact === 'light' ? DevTheme.CODE_BG_LIGHT : DevTheme.CODE_BG_DARK)
              .border({ width: 1, color: DevTheme.TEXT_SECONDARY }).offset({ x: 2, y: -2 })
          }
        }
        .width(32)
        .height(32)
        .margin({ top: 8, right: 8 })
        .borderRadius(DevTheme.RADIUS_FULL)
        .backgroundColor(this.copied ? (this.themeReact === 'light' ? DevTheme.CODE_COPIED_LIGHT : DevTheme.CODE_COPIED_DARK) : Color.Transparent)
        .animation({ duration: 200, curve: Curve.EaseOut })
        .onClick(() => {
          copyText(MCP_CONFIG_TEXT);
          this.copied = true;
          setTimeout(() => {
            this.copied = false;
          }, 1500);
        })
      }
      .width('100%')
      .borderRadius(DevTheme.RADIUS_MD)
      .backgroundColor(this.themeReact === 'light' ? DevTheme.CODE_BG_LIGHT : DevTheme.CODE_BG_DARK)
      .clip(true)
    }
    .width('100%')
  }

  @Builder
  toolsTab() {
    Column({ space: 6 }) {
      ForEach(MCP_TOOL_LIST, (item: string[]) => {
        Row({ space: 8 }) {
          Text(item[0]).fontSize(DevTheme.FS_CAPTION).fontFamily(DevTheme.MONO_FONT)
            .fontColor(DevTheme.PRIMARY).width(180)
          Text(item[1]).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY).layoutWeight(1)
        }.width('100%').padding({ top: 3, bottom: 3 })
      }, (item: string[]) => item[0])
    }
    .width('100%')
  }

  build() {
    Column() {
      this.panelHeader()
      this.serverBlock()
      this.tabBar()
      if (this.tab === 0) { this.configTab() } else { this.toolsTab() }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

// ─── 28b. MCP 配置弹窗（薄壳：CustomDialog 包装 McpConfigContent，弹窗级容器样式在此） ──

@CustomDialog
export struct McpConfigDialog {
  controller: CustomDialogController;

  build() {
    Column() {
      McpConfigContent({
        onClose: () => {
          this.controller.close();
        },
      })
    }
    .width(450)
    .padding(20)
    .borderRadius(DevTheme.RADIUS_LG)
    .backgroundColor(DevTheme.BG)
    .clip(true)
  }
}

// ─── 25. 分页器（IBestPagination 封装 + DevTheme 配色） ──

@Component
export struct DevPagination {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop currentPage: number;
  @Prop totalItems: number = 0;
  @Prop itemsPerPage: number = 50;
  onChange: (page: number) => void = () => {};

  private totalPages(): number {
    return Math.max(1, Math.ceil(this.totalItems / this.itemsPerPage));
  }

  /** 生成页码序列（带省略号） */
  private pageList(): number[] {
    const total = this.totalPages();
    const cur = this.currentPage;
    if (total <= 7) {
      const list: number[] = [];
      for (let i = 1; i <= total; i++) { list.push(i); }
      return list;
    }
    if (cur <= 4) { return [1, 2, 3, 4, 5, -1, total]; }
    if (cur >= total - 3) { return [1, -1, total - 4, total - 3, total - 2, total - 1, total]; }
    return [1, -1, cur - 1, cur, cur + 1, -2, total];
  }

  build() {
    Row({ space: 10 }) {
      // 上一页（‹）
      Text('‹')
        .fontSize(DevTheme.FS_H1)
        .fontColor(this.currentPage > 1 ? DevTheme.TEXT_PRIMARY : DevTheme.TEXT_MUTED)
        .constraintSize({ minWidth: 28 })
        .height(32)
        .padding({ left: 6, right: 6 })
        .textAlign(TextAlign.Center)
        .borderRadius(4)
        .border({ width: 1, color: this.currentPage > 1 ? DevTheme.BORDER : DevTheme.BG_MUTED })
        .backgroundColor(this.currentPage > 1 ? Color.Transparent : DevTheme.BG_MUTED)
        .onClick(() => {
          if (this.currentPage > 1) { this.onChange(this.currentPage - 1); }
        })

      // 页码按钮
      ForEach(this.pageList(), (p: number) => {
        if (p === -1 || p === -2) {
          Text('···')
            .fontSize(DevTheme.FS_H3)
            .fontColor(DevTheme.TEXT_MUTED)
            .height(32)
            .textAlign(TextAlign.Center)
        } else {
          Text(p.toString())
            .fontSize(DevTheme.FS_H2)
            .fontColor(p === this.currentPage ? (this.themeReact === 'dark' ? DevTheme.BG : '#FFFFFF') : DevTheme.TEXT_PRIMARY)
            .constraintSize({ minWidth: 28 })
            .height(32)
            .padding({ left: 6, right: 6 })
            .textAlign(TextAlign.Center)
            .borderRadius(4)
            .backgroundColor(p === this.currentPage ? DevTheme.TEXT_PRIMARY : Color.Transparent)
            .border({ width: 1, color: p === this.currentPage ? DevTheme.TEXT_PRIMARY : DevTheme.BORDER })
            .onClick(() => {
              if (p !== this.currentPage) { this.onChange(p); }
            })
        }
      }, (p: number, idx: number) => `${p}_${idx}_${this.currentPage === p}`)

      // 下一页（›）
      Text('›')
        .fontSize(DevTheme.FS_H1)
        .fontColor(this.currentPage < this.totalPages() ? DevTheme.TEXT_PRIMARY : DevTheme.TEXT_MUTED)
        .constraintSize({ minWidth: 28 })
        .height(32)
        .padding({ left: 6, right: 6 })
        .textAlign(TextAlign.Center)
        .borderRadius(4)
        .border({ width: 1, color: this.currentPage < this.totalPages() ? DevTheme.BORDER : DevTheme.BG_MUTED })
        .backgroundColor(this.currentPage < this.totalPages() ? Color.Transparent : DevTheme.BG_MUTED)
        .onClick(() => {
          if (this.currentPage < this.totalPages()) { this.onChange(this.currentPage + 1); }
        })
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
  }
}


// ─── 26. 分页计算工具（动态每页数量 = 容器高度 / 行高） ──

export class PageCalc {
  /** 有 desc 行实际高度：padding(7+7) + 名称行(28, DevBtn mini) + Column间距(6) + desc行(15, 11×1.36) = 63 */
  static readonly ITEM_HEIGHT: number = 50; // DevPkgRow.ROW_HEIGHT(48) + ROW_GAP(2)
  /** 无 desc 行实际高度：padding(7+7) + 名称行(28) = 42 */
  static readonly ITEM_HEIGHT_COMPACT: number = 50; // 同 ITEM_HEIGHT（行高固定，有无 desc 不影响）
  /** 行间距（外层 Column space） */
  static readonly ROW_GAP: number = 2;

  /** 根据容器高度计算每页条目数 */
  static computePageSize(containerHeight: number, rowHeight: number = PageCalc.ITEM_HEIGHT): number {
    // N×rowH + (N-1)×gap ≤ h → N ≤ (h + gap) / (rowH + gap)
    return Math.max(3, Math.min(100, Math.floor((containerHeight + PageCalc.ROW_GAP) / (rowHeight + PageCalc.ROW_GAP))));
  }
}

const HOME_PATH: string = '/storage/Users/currentUser';
