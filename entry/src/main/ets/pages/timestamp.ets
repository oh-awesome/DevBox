import promptAction from '@ohos.promptAction';
import { CommIconButton, IconButton } from './icon_button';
import { i18n } from '@kit.LocalizationKit';
import { pasteboard } from '@kit.BasicServicesKit';

interface DateResultType {
  date: string;
  time: string;
  timeZone: string;
  gmt: string;
  info: string;
}

@Component
struct infoBuilder {
  @Prop title: string
  @Prop value: string

  @Builder
  infoBuilerInner() {
    Row({ space: 8 }) {
      Text(this.title)
        .fontSize(16)
        .padding({ left: 24 })
        .width(80)

      Text(this.value)
        .fontSize(16)
        .fontColor($r('app.color.common_text'))
        .copyOption(CopyOptions.LocalDevice)
    }
    .backgroundColor($r('app.color.timestamp_info'))
    .alignItems(VerticalAlign.Center)
    .height(32)
    .width('100%')
    .borderWidth(1)
    .borderColor($r('app.color.editor_divider'))
  }

  build() {
    this.infoBuilerInner();
  }
}


@Component
export struct TimeConverterPage {
  private textClockController: TextClockController = new TextClockController();
  @State timestamp: string = '';
  @State date: Date = new Date;
  @State dateString: string = this.timeFormat(this.date);
  @State secondString: string = this.padZero(this.date.getSeconds());
  @State toInfo: string = '';
  @State toDate: string = '';
  @State toTime: string = '';
  @State toGMT: string = '';
  @State toTimeZone: string = '';
  @State accumulateTime: number = 0;
  @State fromSecond: string = '';
  @State fromMs: string = '';
  @State fromTimeZone: string = '';
  @State fromGMT: string = '';
  @State dateToTimestampResult: string = ''

  private padZero(num: number): string {
    return num < 10 ? `0${num}` : `${num}`
  }

  private timeFormat(date: Date, pattern: string = 'YYYY-MM-DD HH:mm:'): string {
    const year = date.getFullYear()
    const month = this.padZero(date.getMonth() + 1)
    const day = this.padZero(date.getDate())
    const hours = this.padZero(date.getHours())
    const minutes = this.padZero(date.getMinutes())
    const seconds = this.padZero(date.getSeconds())

    return pattern
      .replace('YYYY', year.toString())
      .replace('MM', month)
      .replace('DD', day)
      .replace('HH', hours)
      .replace('mm', minutes)
  }

  private getPeriodName(hour: number): string {
    if (hour >= 0 && hour < 2) {
      return "午夜"
    } else if (hour >= 2 && hour < 6) {
      return "凌晨"
    } else if (hour >= 6 &&
      hour < 8) {
      return "清晨"
    } else if (hour >= 8 && hour < 12) {
      return "上午"
    } else if (hour >= 12 &&
      hour < 14) {
      return "中午"
    } else if (hour >= 14 && hour < 18) {
      return "下午"
    } else if (hour >= 18 &&
      hour < 20) {
      return "傍晚"
    } else if (hour >= 20 && hour < 22) {
      return "晚上"
    } else {
      return "深夜"
    } // 22:00-24:00
  }

  private getShiChen(hour: number): string {
    if (hour >= 23 || hour < 1) {
      return "子时"
    } else if (hour >= 1 && hour < 3) {
      return "丑时"
    } else if (hour >= 3 &&
      hour < 5) {
      return "寅时"
    } else if (hour >= 5 && hour < 7) {
      return "卯时"
    } else if (hour >= 7 &&
      hour < 9) {
      return "辰时"
    } else if (hour >= 9 && hour < 11) {
      return "巳时"
    } else if (hour >= 11 &&
      hour < 13) {
      return "午时"
    } else if (hour >= 13 && hour < 15) {
      return "未时"
    } else if (hour >= 15 &&
      hour < 17) {
      return "申时"
    } else if (hour >= 17 && hour < 19) {
      return "酉时"
    } else if (hour >= 19 &&
      hour < 21) {
      return "戌时"
    } else {
      return "亥时"
    } // 21:00-23:00
  }

  private converDataToString(date: Date): DateResultType {
    const timezone = i18n.getTimeZone();
    const offsetMinutes = timezone.getOffset(date.getTime()) / 60000;
    const gmtSign = offsetMinutes >= 0 ? '+' : '-';
    const gmtHours = Math.abs(offsetMinutes / 60).toString().padStart(2, '0');
    const dayOfWeek = ['日', '一', '二', '三', '四', '五', '六'][date.getDay()]
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    const hours = date.getHours();
    const minutes = date.getMinutes().toString().padStart(2, '0');
    const seconds = date.getSeconds().toString().padStart(2, '0');
    const period = this.getPeriodName(hours);
    const shiChen = this.getShiChen(hours);

    return {
      date: `${year}/${month}/${day}`,
      time: `${hours}:${minutes}:${seconds}`,
      timeZone: timezone.getID(),
      gmt: `${year}-${month}-${day}T${hours}:${minutes}:${seconds} ${gmtSign}${gmtHours}:00`,
      info: `${year}年${month}月/${day}日 ${hours}:${minutes}:${seconds} 星期${dayOfWeek} ${shiChen} ${period}`
    }
  }

  // 时间戳转日期
  convertTimestampToDate() {
    if (!this.timestamp) {
      promptAction.showToast({ message: '请输入时间戳' })
      return
    }
    const ts = Number(this.timestamp)
    if (isNaN(ts)) {
      promptAction.showToast({ message: '请输入有效的时间戳' })
      return
    }

    const date: Date = new Date(ts * 1000)
    const result = this.converDataToString(date);
    this.toDate = result.date;
    this.toTime = result.time;
    this.toTimeZone = result.timeZone;
    this.toGMT = result.gmt;
    this.toInfo = result.info;
  }

  private isZeroToFiftyNine(str: string): boolean {
    // 排除空字符串和非法字符
    if (str.length > 2) {
      return false;
    }
    if (str.length === 0) {
      return true;
    }

    const num = Number(str);
    return !isNaN(num) && num >= 0 && num <= 59;
  }

  // 日期转时间戳
  private convertDateToTimestamp() {

    if (this.secondString == '') {
      this.secondString = '00'
    }

    const datetimeStr = `${this.dateString}${this.secondString} `
    const ts = Date.parse(datetimeStr)
    if (isNaN(ts)) {
      promptAction.showToast({ message: '请输入有效的日期和时间' })
      return
    }
    const seconds = Math.floor(ts / 1000)
    const date = new Date(ts)
    const result = this.converDataToString(date);

    this.fromSecond = `${seconds}`;
    this.fromMs = `${ts}`;
    this.fromTimeZone = result.timeZone;
    this.fromGMT = result.gmt;
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        TextClock({ timeZoneOffset: -8, controller: this.textClockController })
          .format('aa HH:mm:ss' + '  当前Unix时间戳:' + this.accumulateTime)
          .onDateChange((value: number) => {
            this.accumulateTime = value;
          })
          .fontColor($r('app.color.bar_text'))
          .fontSize(20)
          .padding({ right: 16 })

        CommIconButton({
          icon: $r('app.media.run'),
          textResource: $r("app.string.time_start"),
          onClickFunc: () => {
            this.textClockController.start();
          }
        })
          .width('12%')


        CommIconButton({
          icon: $r('app.media.pause'),
          textResource: $r("app.string.time_pause"),
          onClickFunc: () => {
            this.textClockController.stop();
          }
        })
          .width('12%')

        CommIconButton({
          icon: $r('app.media.copy'),
          textResource: $r("app.string.copy"),
          onClickFunc: () => {
            let pasteData: pasteboard.PasteData =
              pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.accumulateTime.toString());
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
            ;
          }
        })
          .width('12%')

      }
      .backgroundColor($r('app.color.bar_background'))
      .borderRadius($r('sys.float.corner_radius_level4'))
      .height('10%')
      .width('100%')
      .padding(8)

      Column() {
        Row() {
          Column() {
            CommIconButton({
              icon: $r('app.media.calendar'),
              textResource: $r("app.string.convert_timestamp_to_date"),
              onClickFunc: () => {
                this.convertTimestampToDate()
              }
            })
              .width('100%')
              .padding({ bottom: 16 })


            TextInput({
              text: this.timestamp,
              placeholder: '请输入时间戳'
            })
              .type(InputType.Number)
              .onChange((value) => {
                this.timestamp = value;
              })
              .fontSize(16)
              .width('100%')
              .height(40)
          }
          .width('35%')
          .padding({
            top: 8,
            bottom: 8,
            left: 8,
            right: 8
          })

          Column() {
            Row({ space: 8 }) {
              Image($r('app.media.calendar'))
                .height(16)
                .objectFit(ImageFit.Contain)
                .padding({ left: 24 })

              Text(this.toInfo)
                .fontSize(16)
                .fontColor($r('app.color.timestamp_title_text'))
                .copyOption(CopyOptions.LocalDevice)
            }
            .backgroundColor($r('app.color.timestamp_title'))
            .alignItems(VerticalAlign.Center)
            .width('100%')
            .height(40)
            .borderWidth(1)
            .borderColor($r('app.color.editor_divider'))

            infoBuilder({ title: '日期:', value: this.toDate });
            infoBuilder({ title: '时间:', value: this.toTime });
            infoBuilder({ title: '时区:', value: this.toTimeZone });
            infoBuilder({ title: 'GMT:', value: this.toGMT });
          }
          .padding({
            top: 8,
            bottom: 8,
            left: 8,
            right: 8
          })
          .width('65%')
        }
      }
      .width('100%')
      .borderWidth(1)
      .borderColor($r('app.color.editor_divider'))
      .borderRadius(4)
      .alignItems(HorizontalAlign.Center)

      Column() {
        Row({}) {
          Column({ space: 8 }) {
            CommIconButton({
              icon: $r('app.media.calendar'),
              textResource: $r("app.string.convert_date_to_timestamp"),
              onClickFunc: () => {
                this.convertDateToTimestamp()
              }
            })
              .width('100%')


            CommIconButton({
              // icon: $r('app.media.copy'),
              textResource: $r("app.string.select_datetime"),
              onClickFunc: () => {
                this.getUIContext().showDatePickerDialog({
                  selected: this.date,
                  showTime: true,
                  useMilitaryTime: true,
                  dateTimeOptions: { hour: "numeric", minute: "2-digit" },
                  onDateAccept: (value: Date) => {
                    this.date = value;
                    this.dateString = this.timeFormat(this.date)
                  }
                })
              }
            })
              .width('100%')

            Row() {
              // 不可编辑的固定前缀
              Text(this.dateString)
                .fontSize(12)
                .fontColor($r('app.color.common_text'))

              // 可编辑部分输入框
              TextInput({
                text: this.secondString
              })
                .textAlign(TextAlign.Start)
                .width(60)
                .margin({ left: 4, right: 0 })
                .type(InputType.Number)
                .maxLength(2)
                .fontSize(12)
                .onChange((value: string) => {
                  const lastinput = this.secondString;
                  if (this.isZeroToFiftyNine(value) === false) {
                    this.secondString = '';
                    this.secondString = lastinput;
                    return;
                  }
                  this.secondString = value;
                })
                .height(30)
            }
            .borderRadius(4)
            .width('90%')
            .padding({ bottom: 16 })
            .justifyContent(FlexAlign.Center)
          }
          .width('35%')
          .padding({
            top: 8,
            bottom: 8,
            left: 8,
            right: 8
          })

          Column() {
            Row({ space: 8 }) {
              Image($r('app.media.clock'))
                .height(16)
                .objectFit(ImageFit.Contain)
                .padding({ left: 24 })

              Text('Unix 时间戳: ' + this.fromSecond)
                .fontSize(16)
                .fontColor($r('app.color.timestamp_title_text'))
                .copyOption(CopyOptions.LocalDevice)
            }
            .backgroundColor($r('app.color.timestamp_title'))
            .alignItems(VerticalAlign.Center)
            .width('100%')
            .height(40)
            .borderWidth(1)
            .borderColor($r('app.color.editor_divider'))

            infoBuilder({ title: '秒:', value: this.fromSecond });
            infoBuilder({ title: '毫秒:', value: this.fromMs });
            infoBuilder({ title: '时区:', value: this.fromTimeZone });
            infoBuilder({ title: 'GMT:', value: this.fromGMT });
          }
          .padding({
            top: 8,
            bottom: 8,
            left: 8,
            right: 8
          })
          .width('65%')
        }
      }
      .width('100%')
      .borderWidth(1)
      .borderColor($r('app.color.editor_divider'))
      .borderRadius(4)
      .alignItems(HorizontalAlign.Center)
    }
    .padding({
      top: 8,
      bottom: 8,
      left: 8,
      right: 8
    })
  }
}