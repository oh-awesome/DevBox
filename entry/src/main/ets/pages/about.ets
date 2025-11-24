import { image } from "@kit.ImageKit";

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

@CustomDialog
struct GuidDialog {
  controller: CustomDialogController
  @State originalImageWidth: number = 0;
  @State originalImageHeight: number = 0;

  build() {
    Column() {
      Image($r('app.media.python_guide'))
        .objectFit(ImageFit.Contain)
    }
    .height('80%')
    .width('80%')
  }
}


@Component
export struct AboutPage {
  guideDialogController: CustomDialogController = new CustomDialogController({
    builder: GuidDialog(),
    // 设置弹窗参数
    alignment: DialogAlignment.Center,
    autoCancel: true, // 点击蒙层可关闭
    customStyle: true,
    maskColor: "#00000040",  // 设置蒙层颜色
    width: 192 * 3,
    height: 108 * 3,
  })

  build() {
    Row() {
      Column() {
        HeadContent({ textResource: $r('app.string.app_describe') })

        TitleContent({ textResource: $r('app.string.key_feature') })
        DetailContent({
          headResource: $r('app.string.key_feature_cmd'),
          textResource: $r('app.string.key_feature_cmds')
        })
        DetailContent({
          headResource: $r('app.string.key_feature_handy_utility'),
          textResource: $r('app.string.key_feature_handy_utilities')
        })
        DetailContent({
          headResource: $r('app.string.key_feature_system_resource'),
          textResource: $r('app.string.key_feature_system_resources')
        })
        DetailContent({
          headResource: $r('app.string.key_feature_number_other'),
          textResource: $r('app.string.key_feature_number_others')
        })

        TitleContent({ textResource: $r('app.string.usage_tips_title') })
        CommContent({ textResource: $r('app.string.usage_tips_content') })

        Column() {
          Image($r('app.media.python_guide'))
            .objectFit(ImageFit.Contain)
        }
        .height('180')
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .padding(16)
        .onClick(async () => {
          this.guideDialogController.open()
        })

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