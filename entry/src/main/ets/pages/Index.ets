import dataPreferences from '@ohos.data.preferences'
import common from '@ohos.app.ability.common';
import {BusinessError} from '@ohos.base';

const OHPCD_MAIN_PAGE:string = 'https://gitcode.com/OpenHarmonyPCDeveloper/DevBox';

@Entry
@Component
struct Index {
  @State keyword:string = '';
  @State showDialog:boolean = false;
  private  pref:dataPreferences.Preferences | null = null;
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

build() {
  Column() {
    Text($r('app.string.open_terminal_to_use'))
      .fontSize(20)
      .textAlign(TextAlign.Start)
      .margin({
        bottom:25,
        left:15,
        right:15,
        top:30
      });
    
    Text($r('app.string.hello_to_visit_Community'))
      .fontSize(20)
      .textAlign(TextAlign.Start)
      .margin({
        bottom:10,
        left:15,
        right:15,
        top:25
      });
      
    Hyperlink(OHPCD_MAIN_PAGE)
      .hitTestBehavior(20)
      .margin({
        bottom:25,
        left:15,
        right:15
      });
      
    Column()
      .flexGrow(1);
      
    Row() {
      Image($r('app.media.mainLogo'))
        .width(40)
        .height(40)
        .objectFit(ImageFit.Contain)
        Column() {
          Text($r('app.string.ohpcd_name'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .margin({ left: 15, right: 15, bottom: 4 })
          
          Text($r('app.string.ohpcd_introduction'))
            .fontSize(14)
            .margin({ left: 15, right: 15 })
        }.margin({ right: 15 })
        
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
    }.margin({ bottom: 30, left: 15, right: 15 })
          
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
      }
    }
    .margin('10px')
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
  }
}