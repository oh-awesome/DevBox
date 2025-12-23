import webview from '@ohos.web.webview';
import { LevelMode } from '@kit.ArkUI';
import { OpenSourceNoticeMetaData } from './opensource_info';
import ossComponentsList from './opensource_list';
import { DevBoxUtils } from '../utils/DevBoxUtils';
import Logger from '../utils/Logger';

const PATH_PRE: string = 'licenseList/';
const TAG: string = '[AboutDialog] ';

@CustomDialog
export struct AboutDialog {
  controller: CustomDialogController
  @State private appIcon: Resource = $r("app.media.AppIcon")
  @State private appName: Resource = $r('app.string.app_name')
  @State private version: Resource = $r('app.string.about_version')
  @State private buildNumber: Resource = $r('app.string.about_buildNumber')
  @State private developer: Resource = $r('app.string.about_developer')
  @State private website: Resource = $r('app.string.about_website')
  @State private webAlias: Resource = $r('app.string.about_websiteAlias')
  @State private description: Resource = $r('app.string.about_description')
  @State private descriptionDetails: Resource = $r('app.string.about_description_details')
  @State private showVersionInfo: boolean = false
  @State private showDescriptionDetails: boolean = false

  build() {
    Column({ space: 0 }) {
      // 头部标题栏
      Row() {
        Text($r('app.string.about_about'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#000000')
      }
      .width('100%')
      .height('10%')
      .justifyContent(FlexAlign.Start)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')

      // 主要内容区域
      Scroll() {
        Column({ space: 8 }) {
          // 应用图标和基本信息
          Column({ space: 15 }) {
            // 应用图标
            Row() {
              Image(this.appIcon)
                .width(80)
                .height(80)
                .borderRadius(16)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)

            // 应用名称
            Text(this.appName)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor('#000000')

            // 版本信息
            Column({ space: 8 }) {
              Row() {
                Text($r('app.string.about_version_head'))
                  .fontSize(16)
                  .fontColor('#666666')
                Text(this.version)
                  .fontSize(16)
                  .fontColor('#666666')
              }

              if (this.showVersionInfo) {
                Row() {
                  Text($r('app.string.about_build_version_head'))
                    .fontSize(14)
                    .fontColor('#666666')
                  Text(this.buildNumber)
                    .fontSize(14)
                    .fontColor('#666666')
                }
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.showVersionInfo = !this.showVersionInfo
            })
          }
          .width('100%')
          .padding({ top: 30, bottom: 30 })
          .backgroundColor('#FFFFFF')

          // 应用描述
          Column({ space: 12 }) {
            Row() {
              Text($r('app.string.about_appInfo'))
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor('#000000')
            }
            .width('100%')

            Text(this.description)
              .fontSize(14)
              .fontColor('#666666')
              .textAlign(TextAlign.Start)
              .lineHeight(20)

            if (this.showDescriptionDetails) {
              Text(this.descriptionDetails)
                .fontSize(14)
                .fontColor('#999999')
            }

          }
          .width('100%')
          .padding({
            left: 20,
            right: 20,
            top: 15,
            bottom: 15
          })
          .backgroundColor('#FFFFFF')
          .onClick(() => {
            this.showDescriptionDetails = !this.showDescriptionDetails
          })

          // 开发者信息
          Column({ space: 12 }) {
            Row() {
              Text($r('app.string.about_developerInfo'))
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor('#000000')
            }
            .width('100%')

            this.buildInfoItem($r('app.string.about_developer_who'), this.developer)
            this.buildLinkItem($r('app.string.about_developer_web'), this.webAlias, this.website)
          }
          .width('100%')
          .padding({
            left: 20,
            right: 20,
            top: 15,
            bottom: 15
          })
          .backgroundColor('#FFFFFF')

          // 功能按钮区域
          Column({ space: 12 }) {
            this.buildLinkItemWithIcon($r('app.string.about_privacy'), $r('app.string.about_privacy_web'),
              $r('sys.media.person_shield'))
          }
          .width('100%')
          .padding({
            left: 20,
            right: 20,
            top: 15,
            bottom: 15
          })
          .backgroundColor('#FFFFFF')

          Row() {
            Image($r('app.media.opensource'))
              .height(20)
              .width(20)
              .margin({ right: 12 })
            Text($r('app.string.about_opensource'))
              .fontSize(15)
              .fontColor($r('sys.color.ohos_id_color_text_hyperlink'))
              .layoutWeight(1)
          }
          .width('100%')
          .height(44)
          .padding({
            left: 20,
            right: 20,
            top: 15,
            bottom: 15
          })
          .backgroundColor('#FFFFFF')
          .onClick(async () => {
            let openSourceDialogController: CustomDialogController = new CustomDialogController({
              builder: OpenSourceDialog(),
              levelMode: LevelMode.OVERLAY,
              // 设置弹窗参数
              alignment: DialogAlignment.Center,
              autoCancel: true, // 点击蒙层可关闭
              customStyle: false,
              maskColor: "#00000040", // 设置蒙层颜色
              width: 700
            })
            openSourceDialogController.open()
          })

        }
      }
      .flexGrow(1)
      .backgroundColor('#F5F5F5')
      .height('80%')


      // 底部版权信息
      Row() {
        Text() {
          Span($r('app.string.about_copyright_info'))
          Span(' © ')
          Span($r('app.string.about_copyright_year'))
          Span(" ")
          Span($r('app.string.about_developer'))
          Span(" ")
          Span($r('app.string.about_rightsReserved'))

        }
        .fontSize(12)
        .fontColor('#999999')

      }
      .width('100%')
      .height('8%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  buildInfoItem(label: Resource, value: Resource) {
    Column() {
      Text(label)
        .fontSize(16)
        .fontColor('#666666')
        .layoutWeight(1)

      Text(value)
        .fontSize(14)
        .fontColor('#000000')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 24 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height(44)
  }

  @Builder
  buildLinkItem(label: Resource, alias: Resource, web: Resource) {
    Column() {
      Text(label)
        .fontSize(16)
        .fontColor('#666666')
        .layoutWeight(1)

      Hyperlink(web, alias)
        .size({ height: 14 })
        .hitTestBehavior(12)
        .padding({ left: 24 })

    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height(44)
  }

  @Builder
  buildLinkItemWithIcon(alias: Resource, web: Resource, icon: Resource) {
    Row() {
      Image(icon)
        .width(20)
        .height(20)
        .margin({ right: 12 })

      Hyperlink(web, alias)
        .size({ height: 18 })
        .hitTestBehavior(12)

    }
    .width('100%')
    .height(44)
  }
}

@CustomDialog
struct OpenSourceDialog {
  controller: CustomDialogController
  // 开源组件数据
  @State ossComponents: OpenSourceNoticeMetaData[] = [];
  private webController: webview.WebviewController = new webview.WebviewController();
  @State timeStamp: number = new Date().getTime();

  aboutToAppear(): void {
    try {
      this.getUIContext().getHostContext()?.resourceManager.getRawFileContent('softwareList/software_list.json')
        .then(value => {
          let res: string = DevBoxUtils.uint8ArrayToString(value);
          this.ossComponents = JSON.parse(res) as OpenSourceNoticeMetaData[];
          this.ossComponents.sort((a: OpenSourceNoticeMetaData, b: OpenSourceNoticeMetaData) => {
            return a.name.localeCompare(b.name);
          });
          if (this.ossComponents.length === 0) {
            this.ossComponents = ossComponentsList;
          }

        });
    } catch (e) {
      Logger.error(TAG, 'ossComponents get failed, restore default');
      this.ossComponents = ossComponentsList;
    }
  }

  build() {
    Column() {
      this.HeaderBuilder()

      // 主要内容区域
      Column() {
        Scroll() {
          Column({ space: 20 }) {
            // 协议概述
            this.AgreementOverview()

            // 开源组件列表
            this.OssComponentsList()

            // 源代码获取
            this.SourceCodeAccess()
          }
          .padding(20)
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto)
        .height('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#f9fafb')
  }

  @Builder
  HeaderBuilder() {
    Column({ space: 16 }) {

      Text($r('app.string.about_opensource_head'))
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1f2937')


      Text() {
        Span($r("app.string.about_opensource_update_date"))
        Span($r('app.string.about_opensource_update_date_info'))

      }
      .fontSize(14)
      .fontColor('#9ca3af')
    }
    .width('100%')
    .padding(30)
    .backgroundColor('#ffffff')
    .margin({ top: 10 })
  }

  @Builder
  AgreementOverview() {
    Column({ space: 15 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.info_circle_fill'))
          .fontSize(24)
          .fontColor([$r('sys.color.ohos_id_color_emphasize_contrary')])
          .margin({ right: 8 })

        Text($r('app.string.about_opensource_license_declaration'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1f2937')
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      Text($r('app.string.about_opensource_license_declaration_info'))
        .fontSize(16)
        .fontColor('#4b5563')
        .textAlign(TextAlign.Start)

      // 重要提示
      Column({ space: 8 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.warning'))
            .fontSize(18)
            .fontColor([$r('sys.color.ohos_id_color_emphasize_contrary_transparent')])
            .margin({ right: 8 })

          Text($r('app.string.about_opensource_import_notice'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1e40af')
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)

        Text($r('app.string.about_opensource_import_notice_info'))
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
    .backgroundColor('#ffffff')
    .shadow({
      radius: 8,
      color: '#00000010',
      offsetX: 0,
      offsetY: 1
    })
  }

  @Builder
  OssComponentsList() {
    Column({ space: 20 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.list_bullet'))
          .fontSize(24)
          .fontColor([$r('sys.color.ohos_id_color_connected_transparent')])
          .margin({ right: 8 })

        Text($r('app.string.about_opensource_list_head'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1f2937')
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      // 开源组件卡片列表
      Column({ space: 15 }) {
        ForEach(this.ossComponents,
          (item: OpenSourceNoticeMetaData, index: number) => {
            if (!item.isNeedHide) {
              Column({ space: 0 }) {
                // 组件标题
                Row() {
                  Text(item.name)
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#1f2937')
                }
                .width('100%')
                .padding({
                  top: 16,
                  bottom: 8,
                  left: 16,
                  right: 16
                })
                .backgroundColor('#f9fafb')
                .border({ width: { bottom: 1 }, color: '#e5e7eb' })

                Row() {
                  // 协议类型
                  Column() {
                    Text(item.license)
                      .fontSize(12)
                      .fontColor('#1e40af')
                      .fontWeight(FontWeight.Bold)
                      .borderRadius(16)
                      .backgroundColor($r('sys.color.ohos_id_color_palette_aux2_transparent'))
                      .padding({
                        top: 4,
                        bottom: 4,
                        left: 16,
                        right: 16
                      })
                  }
                  .layoutWeight(5)
                  .justifyContent(FlexAlign.Center)


                  // 代码仓地址
                  Column() {
                    Hyperlink(item.source, $r('app.string.about_opensource_code_repository_URL'))
                      .size({ height: 16 })
                      .hitTestBehavior(12)
                      .padding({ left: 24 })
                  }
                  .layoutWeight(4)
                  .justifyContent(FlexAlign.Center)

                  // 查看许可证
                  Column() {
                    Text($r('app.string.about_opensource_view_license'))
                      .fontSize(12)
                      .fontColor('#059669')
                      .onClick(() => {
                        item.showLicense = !item.showLicense
                        this.timeStamp = Date.now();
                      })
                  }
                  .layoutWeight(4)
                  .justifyContent(FlexAlign.Center)
                }
                .width('100%')
                .backgroundColor('#ffffff')
                .border({
                  width: 1,
                  color: '#e5e7eb'
                })
                .height(40)

                if (this.timeStamp && this.ossComponents[index].showLicense === true) {
                  Column() {
                    Web({
                      src: $rawfile(PATH_PRE + item.licenseFile),
                      controller: this.webController
                    })
                  }
                  .width('100%')
                }
              }
              .border({
                width: 2,
                color: '#ffcbcdcd'
              })
              .borderRadius(12)
            }
          })
      }
    }
  }

  @Builder
  SourceCodeAccess() {
    Column({ space: 15 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.download'))
          .fontSize(24)
          .fontColor([$r('sys.color.ohos_id_color_alert')])
          .margin({ right: 8 })

        Text($r('app.string.about_opensource_source_code_acquisition'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1f2937')
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      Column({ space: 12 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.envelope_fill'))
            .fontSize(18)
            .fontColor([$r('sys.color.ohos_id_color_palette_aux5_dark')])
            .margin({ right: 8 })

          Text($r('app.string.about_opensource_source_code_acquisition_method'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#065f46')
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)

        Column({ space: 8 }) {
          Row() {
            Text($r('app.string.about_opensource_get_from_code_url'))
              .fontSize(14)
              .fontColor('#047857')
            Hyperlink($r('app.string.about_opensource_code_repository'),
              $r('app.string.about_opensource_click_access'))
              .size({ height: 18 })
              .hitTestBehavior(12)
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#d1fae5')
        .border({ width: { left: 4 }, color: '#10b981' })
      }
      .width('100%')
      .padding(20)
      .backgroundColor('#ffffff')
      .shadow({
        radius: 8,
        color: '#00000010',
        offsetX: 0,
        offsetY: 1
      })
    }
  }
}