import dataPreferences from '@ohos.data.preferences'
import common from '@ohos.app.ability.common';
import {BusinessError} from '@ohos.base';
import { promptAction, router } from '@kit.ArkUI';
import {UnicodeConverter} from './unicode_converter';
import {AboutPage} from './about';
import {TextEditor} from  './texteditor'
@Entry
@Component
struct Index {
  @State keyword:string = '';
  @State showDialog:boolean = false;
  private  pref:dataPreferences.Preferences | null = null;
  @State currentIndex: number = 0;
  private controller: TabsController = new TabsController();
  @State pageinfos: NavPathStack = new NavPathStack();
  
  async aboutToAppear() {
    try {
        const context = getContext(this) as common.UIAbilityContext;
        this.pref = await dataPreferences.getPreferences(context, 'first_use_pref');
        const isFirstUse = await this.pref.get('isFirstUse', true);
        if (isFirstUse) {
          this.showDialog = true;
        }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`get Preferences failed, err code is ${err?.code}, message is ${err?.message}`);
    } 
  }

  async markAsUsed() {
    if (this.pref) {
      try{
        await this.pref.put('isFirstUse',false);
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
          .fontSize(20)
          .textAlign(TextAlign.Center)
          .margin({ bottom:10, top:25 })
        
        Text($r('app.string.restart_notice'))
          .fontSize(16)
          .textAlign(TextAlign.Center)
          .margin({bottom:25, left:15, right:15})
        
        Button($r('app.string.confirm_button'))
          .width(180)
          .height(40)
          .fontSize(18)
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
        .width('80%')
        .shadow({
          radius: 10,
          color: Color.Gray,
          offsetX: 0,
          offsetY: 5
        });
      }
      .position({x:0,y:0})
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {  
      Column() {
        Tabs({ controller: this.controller }) {
          TabContent() {
            AboutPage()
          }.tabBar($r('app.string.tab_about'))
  
          TabContent() {
            UnicodeConverter()
          }.tabBar($r('app.string.tab_unicode'))

          TabContent() {
            TextEditor()
          }.tabBar($r('app.string.tab_minitxt'))

          TabContent() {
          }.tabBar($r('app.string.tab_qr'))
          
          TabContent() {
          }.tabBar($r('app.string.tab_timestamp'))
          
          TabContent() {
          }.tabBar($r('app.string.tab_radomstrting'))
          
          TabContent() {
          }.tabBar($r('app.string.tab_hex'))
    }
        .barWidth('25%')
        .barHeight('100%')
        .vertical(true)
        .barPosition(BarPosition.Start)
        .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
        .fadingEdge(true)
        .barMode(BarMode.Scrollable)
        .backgroundColor($r('sys.color.comp_background_secondary'))
        .divider({ strokeWidth: '1px', color: $r('sys.color.comp_divider') })
        .onChange((index: number) => {
          this.currentIndex = index;
        })
      }
      .padding($r('sys.float.padding_level8'))
      .justifyContent(FlexAlign.Center)
      // .backgroundImage($r('app.media.image_background')) // 替换自己项目图片资源文件
      .backgroundImageSize({ width: '100%', height: '100%' })
      .borderRadius($r('sys.float.corner_radius_level8'))
      .height('100%')
      .width('100%')
    }
  }
}