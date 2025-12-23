import dataPreferences from '@ohos.data.preferences'
import common from '@ohos.app.ability.common';
import { BusinessError } from '@ohos.base';
import { UnicodeConverter } from './unicode_converter';
import { QrcodeBuilder } from './qrcode_builder';
import { AboutPage } from './about';
import { TextEditor } from './texteditor'
import { TimeConverterPage } from './timestamp'
import { HexConvertsPage } from './hex_convert'
import { SysMedia } from './sys_media'
import { SysSymbol } from './sys_symbol';
import { SysColor } from './sys_color';
import { SysString } from './sys_string';
import { AboutDialog } from '../about_diaglog/about';
import { CommandManual } from './command_manual';
import { DevBoxUtils } from '../utils/DevBoxUtils';

@Entry
@Component
struct Index {
  @State keyword: string = '';
  @State showDialog: boolean = false;
  private pref: dataPreferences.Preferences | null = null;
  @State currentIndex: number = 0;
  private controller: TabsController = new TabsController();
  @State pageinfos: NavPathStack = new NavPathStack();
  @State titleColor: Resource = $r('sys.color.ohos_id_color_titlebar_icon')
  @State helpButtonColor: Resource = $r('app.color.button_full_transparent')
  dialogController: CustomDialogController = new CustomDialogController({
    builder: AboutDialog(),
    // 设置弹窗参数
    alignment: DialogAlignment.Center,
    autoCancel: true, // 点击蒙层可关闭
    customStyle: false,
    maskColor: "#00000040", // 设置蒙层颜色
    width: 600
  })

  async aboutToAppear() {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.pref = await dataPreferences.getPreferences(context, 'first_use_pref');
      const isFirstUse = await this.pref.get('isFirstUse', true);
      DevBoxUtils.getInstance().setUIAbilityContext(context);
      if (isFirstUse) {
        this.showDialog = true;
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`get Preferences failed, err code is ${error?.code}, message is ${error?.message}`);
    }
  }

  async markAsUsed() {
    if (this.pref) {
      try {
        await this.pref.put('isFirstUse', false);
        await this.pref.flush();
        this.showDialog = false;
      } catch (err) {
        const e = err as BusinessError;
        console.error(`update Preferences failed, err code is ${e?.code}, message is ${e?.message}`);
      }
    }
  }

  @Builder
  tabBuilder(title: string, targetIndex: number) {
    Column() {
      Text(title)
        .fontColor(this.currentIndex === targetIndex ? $r('sys.color.font_emphasize') : $r('sys.color.font_primary'))
        .fontWeight(FontWeight.Regular)
        .fontSize($r('sys.float.Caption_M'))
    }
    .width(72)
    .height(30)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  contentBuilder(text: string) {
  }

  build() {
    if (this.showDialog) {
      Column() {
        Column() {
          Text($r('app.string.tips_dialog'))
            .fontSize(24)
            .textAlign(TextAlign.Center)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.Black)
            .margin({ bottom: 10, top: 25 })

          Text($r('app.string.restart_notice'))
            .fontSize(16)
            .textAlign(TextAlign.Center)
            .fontColor(Color.Black)
            .margin({ bottom: 25, left: 15, right: 15 })

          Button($r('app.string.confirm_button'))
            .width(180)
            .height(40)
            .fontSize(18)
            .borderRadius(8)
            .type(ButtonType.Capsule)
            .backgroundColor('#007DFF')
            .margin({ bottom: 25 })
            .onClick(() => {
              this.markAsUsed();
            })
        }
        .padding(20)
        .backgroundColor(Color.White)
        .borderRadius(16)
        .width('60%')
        .shadow({
          radius: 10,
          color: Color.Gray,
          offsetX: 0,
          offsetY: 5
        });
      }
      .backgroundImage($r("app.media.nextBackground"))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      .backgroundImageSize({ width: '100%', height: '100%' })
      .position({ x: 0, y: 0 })
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      Column() {
        Flex({ justifyContent: FlexAlign.SpaceBetween }) {
          Row({ space: 20 }) {
            Image($r('app.media.AppIcon'))
              .height(20)
              .width(20)
            Text('DevBox')
              .fontColor(this.titleColor)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
          }
          .width('200vp')
          .height('25vp')
          .alignItems(VerticalAlign.Top)
          .justifyContent(FlexAlign.Start)
          .margin({ left: '15vp', top: '15vp' })

          Row({ space: 20 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.questionmark_circle'))
                .fontSize(20)
                .fontWeight(FontWeight.Normal)
                .fontColor([this.titleColor])
            }
            .height(30)
            .width(30)
            .borderRadius(6)
            .backgroundColor(this.helpButtonColor)
            .alignItems(VerticalAlign.Center)
            .justifyContent(FlexAlign.Center)
            .onClick(async () => {
              this.dialogController.open()
            })
            .onHover((isHover: boolean, event: HoverEvent) => {
              if (event.sourceTool === SourceTool.MOUSE) {
                this.helpButtonColor =
                  isHover ? $r('app.color.button_full_hover') : $r('app.color.button_full_transparent');
              }
            })
          }
          .margin({ right: '150vp', top: '10vp' })
          .width('50%')
          .justifyContent(FlexAlign.End)
        }
        .height(48)
        .width('100%')

        Tabs({ controller: this.controller }) {
          TabContent() {
            AboutPage()
          }.tabBar($r('app.string.tab_about'))

          TabContent() {
            CommandManual()
          }.tabBar($r('app.string.tab_cmd_manual'))

          TabContent() {
            UnicodeConverter()
          }.tabBar($r('app.string.tab_unicode'))

          TabContent() {
            TextEditor()
          }.tabBar($r('app.string.tab_minitxt'))

          TabContent() {
            QrcodeBuilder()
          }.tabBar($r('app.string.tab_qr'))

          TabContent() {
            TimeConverterPage()
          }.tabBar($r('app.string.tab_timestamp'))

          TabContent() {
            SysMedia()
          }.tabBar($r('app.string.tab_media'))

          TabContent() {
            SysSymbol()
          }.tabBar($r('app.string.tab_symbol'))

          TabContent() {
            SysColor()
          }.tabBar($r('app.string.tab_color'))

          TabContent() {
            SysString()
          }.tabBar($r('app.string.tab_string'))

          TabContent() {
            HexConvertsPage()
          }.tabBar($r('app.string.tab_hex'))
        }
        .barWidth('25%')
        .barHeight('100%')
        .vertical(true)
        .barPosition(BarPosition.Start)
        .fadingEdge(true)
        .barMode(BarMode.Scrollable)
        .backgroundColor(Color.Transparent)
        .divider({ strokeWidth: '1px', color: $r('sys.color.comp_divider') })
        .onChange((index: number) => {
          this.currentIndex = index;
        })
        .height('92%')
      }
      .justifyContent(FlexAlign.Start)
      .height('100%')
      .width('100%')
      .backgroundImage($r("app.media.nextBackground"))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      .backgroundImageSize({ width: '100%', height: '100%' })
      .onBlur(() => {
        // 组件失去焦点时触发，将背景色变为灰色
        this.titleColor = $r('sys.color.ohos_id_color_foreground_contrary_disable_dark')
      })
      .onFocus(() => {
        // 组件获得焦点时触发，将背景色恢复为白色
        this.titleColor = $r('sys.color.ohos_id_color_titlebar_icon')
      })
    }
  }
}
