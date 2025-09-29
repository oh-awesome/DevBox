import { promptAction } from '@kit.ArkUI'
import { CommIconButton } from './icon_button';

class DecimalToBinaryUtil {
  public decimalToBinaryUtil(decimal: number): string {
    if (decimal <= 0) {
      return '';
    }
    let binary = '';
    while (decimal > 0) {
      binary = (decimal % 2) + binary;
      decimal = Math.floor(decimal / 2);
    }
    return binary;
  }
}

export class BinaryToDecimalUtil {
  public binaryToDecimalUtil(binary: string): number {
    let decimal: number = 0;
    let base: number = 1;
    for (let i: number = binary.length - 1; i >= 0; i--) {
      if (binary[i] === '1') {
        decimal += base;
      }
      base *= 2;
    }
    return decimal;
  }
}

/*
十进制转十六进制
 */
export class DecimalToHexadecimallUtil {
  public decimalToHexadecimallUtil(decimal: number): string {
    let hex = '';
    while (decimal > 0) {
      let digit = decimal % 16;
      //hex = (digit > 9 ?'':'0') + digit.toString(16) + hex;
      hex = digit.toString(16) + hex;
      decimal = Math.floor(decimal / 16);
    }
    return hex;
  }
}

/**
 *十六进制转十进制
 * @param hex hex string
 * @returns number
 */
export class HexadecimalToDecimalUtil {
  public hexadecimalToDecimalUtil(hex: string): number {
    return parseInt(hex, 16);
  }
}

/*
十进制转八进制
 */
export class DecimalToOctalUtil {
  public decimalToOctalUtil(num: number): string {
    if (num === 0) {
      return '0';
    }
    let octal = '';
    while (num > 0) {
      octal = (num % 8) + octal;
      num = Math.floor(num / 8);
    }
    return octal;
  }
}

/*
八进制转十进制
 */
export class OctalToDecimalUtil {
  public octalToDecimalUtil(octal: string): number {
    let decimal = 0;
    let base = 0;
    while (octal.length > 0) {
      decimal += Math.floor(Number(octal[octal.length - 1])) * Math.pow(8, base);
      base++;
      octal = octal.substring(0, octal.length - 1);
    }
    return decimal;
  }
}

@Component
export struct HexConvertsPage {
  @State
  text: string = ''
  @State
  text3: string = ''
  @State
  text4: string = ''
  //十进制转二进制
  decimalToBinary = new DecimalToBinaryUtil()

  ToBinary() {
    let num: number = 0
    num = Number(this.text)
    const N1 = this.decimalToBinary.decimalToBinaryUtil(num)
    this.text = N1
    return this.text
  }

  //十进制转八进制
  DecimalToOctal = new DecimalToOctalUtil()

  ToOctal() {
    let num: number = 0
    num = Number(this.text)
    const N1 = this.DecimalToOctal.decimalToOctalUtil(num)
    this.text = N1
    return this.text
  }

  //十进制转十六进制
  decimalToHexadecimall = new DecimalToHexadecimallUtil()

  ToHexadecimal() {
    let num: number = 0
    num = Number(this.text)
    const N1 = this.decimalToHexadecimall.decimalToHexadecimallUtil(num)
    this.text = N1
    return this.text
  }

  //二进制转十进制
  binaryToDecimal = new BinaryToDecimalUtil()

  binaryToDecimalUtil() {
    const N1 = this.binaryToDecimal.binaryToDecimalUtil(this.text)
    this.text = N1.toString()
    return this.text
  }

  //八进制转十进制
  octalToDecimal = new OctalToDecimalUtil()

  octalToDecimalUtil() {
    const N1 = this.octalToDecimal.octalToDecimalUtil(this.text)
    this.text = N1.toString()
    return this.text
  }

  //十六进制转十进制
  hexadecimalToDecimal = new HexadecimalToDecimalUtil()

  hexadecimalToDecimalUtil() {
    const N1 = this.hexadecimalToDecimal.hexadecimalToDecimalUtil(this.text)
    this.text = N1.toString()
    return this.text
  }

  build() {
    Column({ space: 8 }) {
      Text('Input:')
        .fontStyle(FontStyle.Italic)
        .fontColor($r('sys.color.ohos_id_color_foreground'))
        .fontSize(20)
        .fontWeight(FontWeight.Bolder)
        .textAlign(TextAlign.Start)
        .width('95%')

      TextInput({ text: this.text })
        .type(InputType.Normal)
        .width('95%')
        .height(50)
        .fontSize(15)
        .fontColor($r('sys.color.ohos_id_color_foreground'))
        .backgroundColor($r('sys.color.ohos_id_color_foreground_contrary_disable'))
        .onChange((value: string) => {
          this.text = value
          this.text4 = this.text
        })
        .margin({ bottom: 16 })

      Text('Result:')
        .fontStyle(FontStyle.Italic)
        .fontColor($r('sys.color.ohos_id_color_foreground'))
        .fontSize(20)
        .fontWeight(FontWeight.Bolder)
        .textAlign(TextAlign.Start)
        .width('95%')

      Text(this.text3)
        .width('95%')
        .height(50)
        .fontSize(15)
        .borderRadius(6)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_foreground'))
        .backgroundColor($r('sys.color.ohos_id_color_foreground_contrary_disable'))
        .margin({ top: 10, bottom: 24})
        .padding({ left: 48 })

      Grid() {
        GridItem() {
          CommIconButton({
            textResource: $r("app.string.convert_Dec2Bin"),
            onClickFunc: () => {
              this.text3 = this.ToBinary()
              this.text = this.text4
            }
          })
        }

        GridItem() {
          CommIconButton({
            textResource: $r("app.string.convert_Dec2Oct"),
            onClickFunc: () => {
              this.text3 = this.ToOctal()
              this.text = this.text4
            }
          })
        }

        GridItem() {
          CommIconButton({
            textResource: $r("app.string.convert_Dec2Hex"),
            onClickFunc: () => {
              this.text3 = this.ToHexadecimal()
              this.text = this.text4
            }
          })
        }


        GridItem() {
          CommIconButton({
            textResource: $r("app.string.convert_Bin2Dec"),
            onClickFunc: () => {
              this.text3 = this.binaryToDecimalUtil()
              this.text = this.text4
            }
          })
        }

        GridItem() {
          CommIconButton({
            textResource: $r("app.string.convert_Oct2Dec"),
            onClickFunc: () => {
              this.text3 = this.octalToDecimalUtil()
              this.text = this.text4
            }
          })
        }

        GridItem() {
          CommIconButton({
            textResource: $r("app.string.convert_Hex2Dec"),
            onClickFunc: () => {
              this.text3 = this.hexadecimalToDecimalUtil()
              this.text = this.text4
            }
          })
        }
      }
      .columnsTemplate('1fr 1fr 1fr')
      .rowsGap(16)
      .columnsGap(16)
      .padding(20)

    }
    .borderRadius(20)
    .width('90%')
    .height('90%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)

  }
}