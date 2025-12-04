import commandManualDataList, { CommandManualData, CommandManualOption } from './manual_data';
import measure from '@ohos.measure';

const TITLE_WIDTH = '200vp'

@Component
export struct CommandManual {
  @State commandLists: CommandManualData[] = commandManualDataList;
  @State searchText: string = '';
  @State timeStamp: number = new Date().getTime();
  @State timeStampFilter: number = new Date().getTime();

  build() {
    Column() {
      this.HeaderBuilder()

      // 主要内容区域
      Column() {
        Scroll() {
          Column({ space: 20 }) {
            this.AboutDevBox()
            this.CommandManualList()
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
    Row({ space: 16 }) {
      Text() {
        Span($r('app.string.app_name'))
        Span($r('app.string.tab_cmd_manual'))
      }
      .fontSize(30)
      .fontWeight(FontWeight.Bold)
      .fontColor('#1f2937')
      .width('40%')

      TextInput({ text: this.searchText, placeholder: "输入命令名称或功能关键描述过滤命令" })
        .placeholderColor($r('sys.color.ohos_id_color_foreground_contrary_disable_dark'))
        .onChange((value: string) => {
          // 用户输入变化时，更新搜索文本状态
          this.searchText = value;
          this.timeStampFilter = Date.now();
        })
        .width('50%')
        .backgroundColor($r('app.color.manual_code_bg_color'))
        .borderRadius(8)
        .textAlign(TextAlign.Start)
        .fontSize(14)
        .padding(8)
        .fontColor('#1f2937')

      // 清除按钮

      SymbolGlyph($r('sys.symbol.clean'))
        .fontSize(24)
        .fontColor([this.searchText === "" ? $r('sys.color.ohos_id_color_foreground_contrary_disable_dark') :
        $r('sys.color.ohos_id_color_emphasize_contrary')])
        .margin({ right: 8 })
        .onClick(() => {
          this.searchText = '';
          this.timeStampFilter = Date.now();
        })
    }
    .width('100%')
    .padding(30)
    .backgroundColor('#ffffff')
    .margin({ top: 10 })
  }

  @Builder
  AboutDevBox() {
    Column({ space: 15 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.info_circle_fill'))
          .fontSize(24)
          .fontColor([$r('sys.color.ohos_id_color_emphasize_contrary')])
          .margin({ right: 8 })

        Text() {
          Span($r('app.string.about_about'))
          Span($r('app.string.app_name'))
        }
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1f2937')
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      Text($r('app.string.command_user_guide'))
        .fontSize(16)
        .fontColor('#4b5563')
        .textAlign(TextAlign.Start)

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
  CommandManualList() {
    Column({ space: 20 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.list_bullet'))
          .fontSize(24)
          .fontColor([$r('sys.color.ohos_id_color_connected_transparent')])
          .margin({ right: 8 })

        Text($r('app.string.command_list'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1f2937')
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      // 列表
      Column({ space: 15 }) {
        ForEach(this.commandLists,
          (item: CommandManualData, index: number) => {
            if (!item.isNeedHide && (this.timeStampFilter &&
              (item.name.includes(this.searchText) === true || item.description.includes(this.searchText) === true ||
                this.searchText === ""))) {
              Column({ space: 0 }) {
                Row() {
                  Column({ space: 8 }) {
                    Text(item.name)
                      .fontSize(18)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#ff0b60dd')
                    Text(item.description)
                      .fontSize(14)
                      .fontWeight(FontWeight.Normal)
                      .fontColor('#ff57585a')
                  }
                  .width('90%')
                  .alignItems(HorizontalAlign.Start)

                  Column() {
                    SymbolGlyph($r('sys.symbol.curve_magnifyingglass'))
                      .fontSize(24)
                      .fontColor([$r('sys.color.ohos_id_color_emphasize_contrary')])
                      .margin({ right: 8 })
                  }
                }
                .justifyContent(FlexAlign.SpaceBetween)
                .width('100%')
                .padding({
                  top: 16,
                  bottom: 8,
                  left: 16,
                  right: 16
                })
                .backgroundColor('#f9fafb')
                .border({ width: { bottom: 1 }, color: '#e5e7eb' })
                .onClick(() => {
                  item.showDetails = !item.showDetails
                  this.timeStamp = Date.now();
                })

                if (this.timeStamp && this.commandLists[index].showDetails === true) {
                  Column({ space: 8 }) {
                    Text("语法")
                      .fontSize(18)
                      .fontColor(Color.Black)
                      .fontWeight(FontWeight.Bold)
                      .width('100%')
                      .padding(8)

                    Text(item.syntax)
                      .fontSize(16)
                      .fontWeight(FontWeight.Normal)
                      .fontColor(Color.Black)
                      .padding(8)
                      .borderRadius(2)
                      .width('100%')
                      .backgroundColor($r('app.color.manual_code_bg_color'))

                    Text("选项")
                      .fontSize(18)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.Black)
                      .width('100%')
                      .padding(8)

                    ForEach(item.options,
                      (option: CommandManualOption, index: number) => {
                        Column() {
                          Stack() {
                            Row() {
                              Text(option.paramName)
                                .fontSize(16)
                                .fontWeight(FontWeight.Normal)
                                .fontColor(Color.Black)
                                .padding(6)
                                .backgroundColor($r('app.color.manual_code_bg_color'))
                                .borderRadius(6)
                                .textAlign(TextAlign.Start)
                                .copyOption(CopyOptions.InApp)
                            }
                            .constraintSize({ minWidth: TITLE_WIDTH })
                            .padding(8)

                            Row() {
                              Row()
                                .width(TITLE_WIDTH)
                                .padding(8)
                              Text(option.description)
                                .fontSize(16)
                                .fontWeight(FontWeight.Normal)
                                .textAlign(TextAlign.Start)
                                .fontColor(Color.Black)
                                .padding(8)
                                .width('calc(100% - 230vp)')
                                .copyOption(CopyOptions.InApp)
                                .visibility(!this.needChangeLine(option.paramName) ? Visibility.Visible :
                                Visibility.None)
                            }
                            .width('100%')
                          }
                          .alignContent(Alignment.Start)
                          .width('100%')

                          Row() {
                            Row()
                              .width(TITLE_WIDTH)
                              .padding(8)
                            Text(option.description)
                              .fontSize(16)
                              .fontWeight(FontWeight.Normal)
                              .fontColor(Color.Black)
                              .padding(8)
                              .width('calc(100% - 230vp)')
                              .copyOption(CopyOptions.InApp)
                          }
                          .width('100%')
                          .visibility(this.needChangeLine(option.paramName) ? Visibility.Visible : Visibility.None)
                        }
                        .alignItems(HorizontalAlign.Start)
                        .width('100%')
                      })

                    Text("示意")
                      .fontSize(18)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.Black)
                      .width('100%')
                      .padding(8)

                    ForEach(item.examples, (example: string, index: number) => {
                      Text(example)
                        .fontSize(16)
                        .fontWeight(FontWeight.Normal)
                        .fontColor(Color.Black)
                        .padding(8)
                        .borderRadius(2)
                        .copyOption(CopyOptions.InApp)
                        .width('100%')
                        .backgroundColor($r('app.color.manual_code_bg_color'))
                    })
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .padding(16)
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

  needChangeLine(content: string): boolean {
    const size = measure.measureTextSize({
      textContent: content,
      fontSize: '16fp',
    })
    if (!size || !size.width) {
      return false;
    }
    return size.width > 330;
  }
}