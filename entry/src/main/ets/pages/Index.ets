import dataPreferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { BusinessError } from '@ohos.base';
import { UnicodeConverter } from './unicode_converter';
import { QrcodeBuilder } from './qrcode_builder';
import { AboutPage } from './about';
import { TextEditor } from './texteditor';
import { TimeConverterPage } from './timestamp';
import { HexConvertsPage } from './hex_convert';
import { SysMedia } from './sys_media';
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
  tipsController: CustomDialogController = new CustomDialogController({
    builder: UserTipsDiagLog(),
    // 设置弹窗参数
    alignment: DialogAlignment.Center,
    autoCancel: true, // 点击蒙层可关闭
    customStyle: false,
    maskColor: "#00000040", // 设置蒙层颜色
    width: 400,
    height: 350
  })

  async aboutToAppear() {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.pref = await dataPreferences.getPreferences(context, 'first_use_pref');
      const isFirstUse = await this.pref.get('needTips', 'need');
      DevBoxUtils.getInstance().setUIAbilityContext(context);
      if (isFirstUse === 'need') {
        this.showDialog = true;
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`get Preferences failed, err code is ${error?.code}, message is ${error?.message}`);
    }
    if (this.showDialog === true) {
      this.tipsController.open();
    }
  }

  build() {
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

@CustomDialog
export struct UserTipsDiagLog {
  controller: CustomDialogController
  private pref: dataPreferences.Preferences | null = null;
  @State isNoLongerTip: boolean = false;

  async markAsUsed() {
    if (this.isNoLongerTip) {
      try {
        const context = getContext(this) as common.UIAbilityContext;
        this.pref = await dataPreferences.getPreferences(context, 'first_use_pref');
        await this.pref.put('needTips', 'noneed');
        await this.pref.flush();

        const perfNeedTipsPer = await this.pref.get('needTips', 'need');
        console.error(`markAsUsed  get ${perfNeedTipsPer}`);

      } catch (err) {
        const e = err as BusinessError;
        console.error(`update Preferences failed, err code is ${e?.code}, message is ${e?.message}`);
      }
    }
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.usertisp_title'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#000000')
      }
      .width('100%')
      .height('10%')
      .justifyContent(FlexAlign.Start)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#ffefefef')

      Column({ space: 15 }) {
        // 重要提示
        Column({ space: 8 }) {
          Row() {
            SymbolGlyph($r('sys.symbol.warning'))
              .fontSize(22)
              .fontColor([$r('sys.color.ohos_id_color_emphasize_contrary_transparent')])
              .margin({ right: 8 })

            Text($r('app.string.tips_dialog'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1e40af')
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)

          Text($r('app.string.restart_notice'))
            .fontSize(14)
            .fontColor('#374151')
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#dbeafe')
        .border({ width: { left: 4 }, color: '#3b82f6' })
      }
      .width('100%')
      .padding(20)
      .backgroundColor('#ffefefef')
      .shadow({
        radius: 8,
        color: '#00000010',
        offsetX: 0,
        offsetY: 1
      })

      Column() {
        // 不再提示复选框
        Row() {
          Row() {
            Checkbox()
              .select(this.isNoLongerTip)
              .shape(CheckBoxShape.ROUNDED_SQUARE)
              .onChange((value: boolean) => {
                this.isNoLongerTip = value;
                // 可选：此处可添加本地存储逻辑，保存用户选择（如使用Preferences）
                console.log("不再提示状态：", value);
              })
              .margin({ right: 10 })

            Text($r('app.string.usertisp_nolonger'))
              .fontSize(14)
              .fontColor('#666666')
          }
          .backgroundColor("#ffefefef")

          // 确定按钮
          Button($r('app.string.confirm_button'))
            .width(120)
            .height(40)
            .fontSize(16)
            .fontColor('#FFFFFF')
            .backgroundColor('#007DFF')
            .borderRadius(8)
            .onClick(() => {
              this.markAsUsed();
              this.controller.close()
            })

        }
        .width('80%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 30 })
        .backgroundColor('#ffefefef')
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .backgroundColor('#ffefefef')

    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor('#ffefefef')
    .padding(16)

  }
}