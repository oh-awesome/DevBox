
@Component
struct HeadContent {
  @Prop textResource: Resource; // 文本内容

  build() {
    Text(this.textResource)
      .fontSize(16)
      .textAlign(TextAlign.Start)
      .fontWeight(FontWeight.Medium)
      .margin({
        left: 15,
        right: 15,
        top: 24
      });
  }
}

@Component
struct TitleContent {
  @Prop textResource: Resource; // 文本内容

  build() {
    Text(this.textResource)
      .fontSize(16)
      .textAlign(TextAlign.Start)
      .fontWeight(FontWeight.Bolder)
      .margin({
        left: 15,
        right: 15,
        top: 12
      });
  }
}

@Component
struct DetailContent {
  @Prop headResource: Resource; // 文本内容
  @Prop textResource: Resource; // 文本内容

  build() {
    Column() {
      Text(this.headResource)
        .fontSize(15)
        .textAlign(TextAlign.Start)
        .fontWeight(FontWeight.Bold)
        .width("100%")

      Text(this.textResource)
        .fontSize(13)
        .textAlign(TextAlign.Start)
        .width("100%")
        .margin({
          left: 20,
          top: 4
        });
    }
    .margin({
      left: 15,
      top: 6
    })
    .width("100%")
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
struct CommContent {
  @Prop textResource: Resource; // 文本内容

  build() {
    Text(this.textResource)
      .fontSize(13)
      .textAlign(TextAlign.Start)
      .margin({
        left: 15,
        right: 15,
        top: 4
      });
  }
}

@Component
export struct AboutPage {
  static OHPCD_MAIN_PAGE: string = 'https://gitcode.com/OpenHarmonyPCDeveloper/DevBox';
  static DEVBOX_PRIVACY_STATEMENT: string =
    'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1756595219123443648';

  build() {
    Row() {
      Column() {
        HeadContent({textResource: $r('app.string.app_describe')})

        TitleContent({textResource: $r('app.string.key_feature')})
        DetailContent({headResource: $r('app.string.key_feature_cmd'), textResource: $r('app.string.key_feature_cmds')})
        DetailContent({headResource: $r('app.string.key_feature_handy_utility'), textResource: $r('app.string.key_feature_handy_utilities')})
        DetailContent({headResource: $r('app.string.key_feature_system_resource'), textResource: $r('app.string.key_feature_system_resources')})
        DetailContent({headResource: $r('app.string.key_feature_number_other'), textResource: $r('app.string.key_feature_number_others')})

        TitleContent({textResource: $r('app.string.usage_tips_title')})
        CommContent({textResource: $r('app.string.usage_tips_content')})
        CommContent({textResource: $r('app.string.usage_help')})
        Hyperlink(AboutPage.OHPCD_MAIN_PAGE, $r("app.string.ohpcd_name"))
          .size({height: 16})
          .hitTestBehavior(12)
          .margin({
            top: 6,
            left: 15,
            right: 15
          });

        TitleContent({textResource: $r('app.string.privacy_tips_title')})
        CommContent({textResource: $r('app.string.privacy_tips_content')})
        Hyperlink(AboutPage.DEVBOX_PRIVACY_STATEMENT, $r('app.string.privacy_link'))
          .size({height: 16})
          .hitTestBehavior(12)
          .margin({
            top: 6,
            left: 15,
            right: 15
          });

        Column()
          .flexGrow(1);

        Row() {
          Image($r('app.media.mainLogo'))
            .width(28)
            .height(28)
            .objectFit(ImageFit.Contain)
          Column() {
            Text($r('app.string.ohpcd_name'))
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .margin({ left: 15, right: 15, bottom: 4 })

            Text($r('app.string.ohpcd_introduction'))
              .fontSize(12)
              .margin({ left: 15, right: 15 })
          }.margin({ right: 15 })

          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.Start)
        }.margin({ bottom: 24, left: 15, right: 15 })

      }
      .margin('10px')
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
    }
  }
}


@Styles
function HeadStyle() {

}

@Styles
function contentStyle() {

}