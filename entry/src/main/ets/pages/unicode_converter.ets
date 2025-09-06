@Component
export struct UnicodeConverter {
  @State strString: string = '';
  @State asciiString: string = '';
  @State firstString: string = '';
  @State secondString: string = '';

  decode(input: string): string {
    const regex = /\\u([0-9A-Fa-f]{4})/g;
    let result = "";
    let lastIndex = 0;
    let match: RegExpExecArray | null;

    while ((match = regex.exec(input)) !== null) {
      result += input.substring(lastIndex, match.index);
      result += String.fromCharCode(parseInt(match[1], 16));
      lastIndex = regex.lastIndex;
    }
    result += input.substring(lastIndex);
    return result;
  }

  encode(input: string): string {
    return Array.from(input)
      .map(char => {
        const code = char.charCodeAt(0);
        return code > 127 ? `\\u${code.toString(16).padStart(4, "0")}` : char;
      })
      .join("");
  }

  build() {
    Row({ space: 5 }) {
      Column() {
        Text('Native:')
          .fontStyle(FontStyle.Italic)
          .fontColor('#808080')
          .fontSize(20)
          .textAlign(TextAlign.Start)
        TextArea({ placeholder: '', text: this.strString })
          .layoutWeight(1)
          .onChange((value: string) => {
            this.strString = value;
          })
      }
      .width('42%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
      .padding({ left: 10 })

      Column({ space: 20 }) {
        Button('> Unicode', { type: ButtonType.Normal })
          .buttonStyle(ButtonStyleMode.NORMAL)
          .controlSize(ControlSize.SMALL)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .width('80%')
          .borderRadius(6)
          .fontSize(16)
          .padding(0)
          .onClick(() => {
            this.asciiString = this.encode(this.strString);
          })

        Button('Native <', { type: ButtonType.Normal })
          .buttonStyle(ButtonStyleMode.NORMAL)
          .controlSize(ControlSize.SMALL)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .width('80%')
          .borderRadius(6)
          .fontSize(16)
          .padding(0)
          .onClick(() => {
            this.strString = this.decode(this.asciiString);
          })

        Button($r('app.string.reset'), { type: ButtonType.Normal })
          .buttonStyle(ButtonStyleMode.NORMAL)
          .controlSize(ControlSize.SMALL)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .fontSize(16)
          .padding(0)
          .width('80%')
          .borderRadius(6)
          .onClick(() => {
            this.strString = '';
            this.asciiString = '';
          })
      }
      .width('16%')
      .height('100%')
      .padding({ top: 20 })
      .justifyContent(FlexAlign.Start)

      Column() {
        Text('Unicode')
          .fontStyle(FontStyle.Italic)
          .fontColor('#808080')
          .fontSize(20)
          .textAlign(TextAlign.Start)
        TextArea({ placeholder: '', text: this.asciiString })
          .layoutWeight(1)
          .onChange((value: string) => {
            this.asciiString = value;
          })
      }
      .width('42%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    }
    .padding(8)
  }
}