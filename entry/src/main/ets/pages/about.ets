@Component
export struct AboutPage {
  static OHPCD_MAIN_PAGE: string = 'https://gitcode.com/OpenHarmonyPCDeveloper/DevBox';

  build() {
    Row() {
      Column() {
        Text($r('app.string.open_terminal_to_use'))
          .fontSize(20)
          .textAlign(TextAlign.Start)
          .margin({
            bottom: 25,
            left: 15,
            right: 15,
            top: 30
          });

        Text($r('app.string.hello_to_visit_Community'))
          .fontSize(20)
          .textAlign(TextAlign.Start)
          .margin({
            bottom: 10,
            left: 15,
            right: 15,
            top: 25
          });

        Hyperlink(AboutPage.OHPCD_MAIN_PAGE)
          .hitTestBehavior(20)
          .margin({
            bottom: 25,
            left: 15,
            right: 15
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

      }
      .margin('10px')
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
    }
  }
}