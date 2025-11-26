import common from '@ohos.app.ability.common';
import dataPreferences from '@ohos.data.preferences'
import { zlib, BusinessError } from '@kit.BasicServicesKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';

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
      Image($r("app.media.devbox_guide"))
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
    maskColor: "#00000040", // 设置蒙层颜色
    width: 192 * 3,
    height: 108 * 3,
  })
  private pref: dataPreferences.Preferences | null = null;
  @State sdk_5_0_2_Path: string = "";
  @State sdk_5_1_0_Path: string = "";
  @State sdk_6_0_0_Path: string = "";

  async aboutToAppear() {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.pref = await dataPreferences.getPreferences(context, 'first_use_pref');
      this.sdk_5_0_2_Path = await this.pref.get('5_0_2', "") as string;
      this.sdk_5_1_0_Path = await this.pref.get('5_1_0', "") as string;
      this.sdk_6_0_0_Path = await this.pref.get('6_0_0', "") as string;
    } catch (err) {
      const error = err as BusinessError;
      console.error(`get Preferences failed, err code is ${err?.code}, message is ${err?.message}`);
    }
  }

  async ReleaseSdk2Path(sdkVersion: string) {
    if (this.pref) {
      let inFile = '/data/storage/el1/bundle/entry/resources/resfile/sysroot/' + sdkVersion + '/sysroot.zip';
      let DocumentSelectOptions: picker.DocumentSelectOptions = {
        selectMode: picker.DocumentSelectMode.FOLDER,
        maxSelectNumber: 1,
      };
      let documentPicker = new picker.DocumentViewPicker();
      let uris = await documentPicker.select(DocumentSelectOptions);
      if (uris[0] === undefined) {
        return;
      }
      let outFileDir = (new fileUri.FileUri(uris[0])).path + "/ohos_sdk/" + sdkVersion;
      fs.mkdirSync(outFileDir, true);
      let options: zlib.Options = {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION
      };
      zlib.decompressFile(inFile, outFileDir, options).then((data: void) => {
        console.info('ReleaseSdk2Path decompressFile success. data: ' + JSON.stringify(data));
      }).catch((errData: BusinessError) => {
        console.error(`ReleaseSdk2Path errData is errCode:${errData.code}  message:${errData.message}`);
        return;
      })
      try {
        await this.pref.put(sdkVersion, outFileDir);
        await this.pref.flush();
        this.sdk_5_0_2_Path = await this.pref.get('5_0_2', "") as string;
        this.sdk_5_1_0_Path = await this.pref.get('5_1_0', "") as string;
        this.sdk_6_0_0_Path = await this.pref.get('6_0_0', "") as string;
      } catch (err) {
        const e = err as BusinessError;
        console.error(`ReleaseSdk2Path pdate Preferences failed, err code is ${e?.code}, message is ${e?.message}`);
      }
    }
  }

  async RemoveSdk2Path(sdkVersion: string) {
    if (this.pref) {
      let rmPathUri = fileUri.getUriFromPath(await this.pref.get(sdkVersion, "") as string);

      let DocumentSelectOptions: picker.DocumentSelectOptions = {
        selectMode: picker.DocumentSelectMode.FOLDER,
        maxSelectNumber: 1,
        authMode: true,
        defaultFilePathUri: rmPathUri
      };
      let documentPicker = new picker.DocumentViewPicker();
      let uris = await documentPicker.select(DocumentSelectOptions);
      if (uris[0] === undefined) {
        return;
      }

      let rmPath = (new fileUri.FileUri(uris[0])).path;
      console.error(`RemoveSdk2Path path, ${rmPath}`);
      fs.rmdir(rmPath).then(() => {
        console.info("rmdir succeed");
      }).catch((err: BusinessError) => {
        console.error("rmdir failed with error message: " + err.message + ", error code: " + err.code);
      });
      try {
        await this.pref.put(sdkVersion, "");
        await this.pref.flush();
        this.sdk_5_0_2_Path = await this.pref.get('5_0_2', "") as string;
        this.sdk_5_1_0_Path = await this.pref.get('5_1_0', "") as string;
        this.sdk_6_0_0_Path = await this.pref.get('6_0_0', "") as string;
      } catch (err) {
        const e = err as BusinessError;
        console.error(`RemoveSdk2Path pdate Preferences failed, err code is ${e?.code}, message is ${e?.message}`);
      }
    }
  }

  setSdkPathToPasteboard(path: string) {
    let pasteData: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, path);
    let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
    try {
      systemPasteboard.setDataSync(pasteData);
      promptAction.showToast({
        message: $r('app.string.copy_success'),
        duration: 2000,
        bottom: '50vp'
      });
      console.info('Succeeded in setting PasteData.');
    } catch (err) {
      console.error('Failed to set PasteData. Cause:' + err.message);
    }
  }

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

        Row() {
          Column() {
            Image($r("app.media.devbox_guide"))
              .objectFit(ImageFit.Contain)
          }
          .width('50%')
          .onClick(async () => {
            this.guideDialogController.open()
          })

          Column({ space: 8 }) {
            Row({ space: 16 }) {
              Button('ohos sdk 5.0.2')
                .onClick(async () => {
                  this.ReleaseSdk2Path("5_0_2");
                })

              Button() {
                SymbolGlyph($r('sys.symbol.ohos_trash_circle'))
                  .fontSize(24)
                  .fontColor([$r('sys.color.ohos_id_color_foreground_transparent')])
                  .margin({ right: 8 })
              }
              .enabled(this.sdk_5_0_2_Path != "")
              .backgroundColor("#00ffffff")
              .onClick(async () => {
                this.RemoveSdk2Path("5_0_2");
              })

              Button() {
                SymbolGlyph($r('sys.symbol.clipboard_sharing'))
                  .fontSize(24)
                  .fontColor([$r('sys.color.ohos_id_color_foreground_transparent')])
                  .margin({ right: 8 })
              }
              .enabled(this.sdk_5_0_2_Path != "")
              .backgroundColor("#00ffffff")
              .onClick(async () => {
                this.setSdkPathToPasteboard(this.sdk_5_0_2_Path);
              })
            }
            .width('100%')

            Row({ space: 16 }) {
              Button('ohos sdk 5.1.0')
                .onClick(async () => {
                  this.ReleaseSdk2Path("5_1_0");
                })

              Button() {
                SymbolGlyph($r('sys.symbol.ohos_trash_circle'))
                  .fontSize(24)
                  .fontColor([$r('sys.color.ohos_id_color_foreground_transparent')])
                  .margin({ right: 8 })
              }
              .enabled(this.sdk_5_1_0_Path != "")
              .backgroundColor("#00ffffff")
              .onClick(async () => {
                this.RemoveSdk2Path("5_1_0");
              })

              Button() {
                SymbolGlyph($r('sys.symbol.clipboard_sharing'))
                  .fontSize(24)
                  .fontColor([$r('sys.color.ohos_id_color_foreground_transparent')])
                  .margin({ right: 8 })
              }
              .enabled(this.sdk_5_1_0_Path != "")
              .backgroundColor("#00ffffff")
              .onClick(async () => {
                this.setSdkPathToPasteboard(this.sdk_5_1_0_Path);
              })
            }
            .width('100%')

            Row({ space: 16 }) {
              Button('ohos sdk 6.0.0')
                .onClick(async () => {
                  this.ReleaseSdk2Path("6_0_0");
                })

              Button() {
                SymbolGlyph($r('sys.symbol.ohos_trash_circle'))
                  .fontSize(24)
                  .fontColor([$r('sys.color.ohos_id_color_foreground_transparent')])
                  .margin({ right: 8 })
              }
              .enabled(this.sdk_6_0_0_Path != "")
              .backgroundColor("#00ffffff")
              .onClick(async () => {
                this.RemoveSdk2Path("6_0_0");
              })

              Button() {
                SymbolGlyph($r('sys.symbol.clipboard_sharing'))
                  .fontSize(24)
                  .fontColor([$r('sys.color.ohos_id_color_foreground_transparent')])
                  .margin({ right: 8 })
              }
              .enabled(this.sdk_6_0_0_Path != "")
              .backgroundColor("#00ffffff")
              .onClick(async () => {
                this.setSdkPathToPasteboard(this.sdk_6_0_0_Path);
              })
            }
            .width('100%')
          }
          .width('50%')
        }
        .height('180')
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
        .padding(16)


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