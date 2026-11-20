/**
 * brewcomponents.ets —— HarmonyBrew 页专用公共件（新 UI：左列表右详情模式）
 *
 * 只服务 brew 页三视图（软件仓库/已安装/可升级）共用的行与命令块；
 * 通用件仍在 component.ets。风格全部走 DevTheme（产品决策：brew 页用
 * 应用自己的深色配色，不引入 BrewUI 琥珀体系）。
 */
import { DevTheme } from './DevTheme';
import { copyText } from './component';

/**
 * DevCommandBlock —— 可复制的终端命令块（"Homebrew 是唯一事实源"理念：
 * 每个操作按钮旁展示用户会敲的命令，省略解析专用旗标）。
 */
@Component
export struct DevCommandBlock {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop command: string;
  /** 命令语义脚注（如"安装此软件包"） */
  @Prop footnote: string = '';

  build() {
    Column({ space: 4 }) {
      Row() {
        Text($r('app.string.brewcomponents_1'))
          .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
        Blank()
        Text($r('app.string.brewcomponents_2'))
          .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.PRIMARY)
          .padding({ top: 2, bottom: 2, left: 8, right: 8 })
          .borderRadius(DevTheme.RADIUS_SM)
          .onClick(() => { copyText(this.command); })
      }.width('100%')

      Text(`$ ${this.command}`)
        .fontSize(DevTheme.FS_BODY).fontFamily(DevTheme.MONO_FONT)
        .fontColor(DevTheme.TEXT_PRIMARY)
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(DevTheme.RADIUS_MD)
        .backgroundColor(DevTheme.BG_ACCENT_PRIMARY)

      if (this.footnote !== '') {
        Text(this.footnote)
          .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
      }
    }.width('100%')
  }
}

/**
 * BrewListRow —— 左列列表行（点行=选中；行内不放操作按钮——安装入口在右详情）。
 * 高度固定 64vp（名称行 + desc 行 + 元信息行），选中态整行背景高亮。
 */
@Component
export struct BrewListRow {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @Prop name: string;
  @Prop desc: string;
  @Prop ver: string;
  /** 元信息副行（如 "近7天下载 112"；空则不渲染） */
  @Prop meta: string;
  @Prop selected: boolean;
  @Prop installed: boolean;      // 已装徽标
  @Prop canUpgrade: boolean;     // 可升级徽标
  @Prop installing: boolean;     // 行内 spinner（相位 running）
  @Prop deprecated: boolean;
  onRowClick: () => void = () => {};

  build() {
    Column({ space: 3 }) {
      Row({ space: 6 }) {
        if (this.installing) {
          LoadingProgress().width(13).height(13).color(DevTheme.PRIMARY)
        }
        Text(this.name)
          .fontSize(DevTheme.FS_BODY).fontWeight(FontWeight.Medium)
          .fontColor(this.selected ? DevTheme.PRIMARY : DevTheme.TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.deprecated) {
          Text($r('app.string.brewcomponents_3'))
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.DANGER)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .borderRadius(DevTheme.RADIUS_SM)
            .border({ width: 1, color: DevTheme.DANGER })
        }
        if (this.canUpgrade) {
          Text($r('app.string.brewcomponents_4'))
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.WARNING)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .borderRadius(DevTheme.RADIUS_SM)
            .border({ width: 1, color: DevTheme.WARNING })
        }
        if (this.installed && !this.installing) {
          Text($r('app.string.brewcomponents_5'))
            .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.SUCCESS)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .borderRadius(DevTheme.RADIUS_SM)
            .border({ width: 1, color: DevTheme.SUCCESS })
        }
      }.width('100%')

      if (this.desc !== '') {
        Text(this.desc)
          .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_TERTIARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      Row({ space: 8 }) {
        if (this.ver !== '') {
          Text(this.ver).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
        }
        if (this.meta !== '') {
          Text(this.meta).fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED)
        }
      }.width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(DevTheme.RADIUS_MD)
    .backgroundColor(this.selected ? DevTheme.BG_ACCENT_PRIMARY : DevTheme.BG_CARD)
    .border({ width: 1, color: this.selected ? DevTheme.PRIMARY : DevTheme.BORDER })
    .onClick(() => { this.onRowClick(); })
  }
}
