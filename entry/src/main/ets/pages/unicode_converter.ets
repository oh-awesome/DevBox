import { CommIconButton } from "./icon_button";

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
      Column({ space: 8 }) {
        Text('Native:')
          .fontStyle(FontStyle.Italic)
          .fontColor($r('sys.color.ohos_id_color_foreground'))
          .fontSize(20)
          .fontWeight(FontWeight.Bolder)
          .textAlign(TextAlign.Start)
          .width('95%')

        TextArea({ placeholder: '', text: this.strString })
          .layoutWeight(1)
          .onChange((value: string) => {
            this.strString = value;
          })
      }
      .width('42%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
      .padding(8)

      Column({ space: 16 }) {
        CommIconButton({
          icon: $r('sys.media.ohos_ic_public_arrow_right'),
          textResource: $r("app.string.convert_to_unicode"),
          onClickFunc: () => {
            this.asciiString = this.encode(this.strString);
          }
        })

        CommIconButton({
          icon: $r('sys.media.ohos_ic_public_arrow_left'),
          textResource: $r("app.string.convert_to_native"),
          onClickFunc: () => {
            this.strString = this.decode(this.asciiString);
          }
        })

        CommIconButton({
          icon: $r('sys.media.ohos_ic_public_cancel'),
          textResource: $r("app.string.convert_clean"),
          onClickFunc: () => {
            this.strString = '';
            this.asciiString = '';
          }
        })
      }
      .width('16%')
      .height('100%')
      .padding({ top: 20 })
      .justifyContent(FlexAlign.Center)

      Column({ space: 8 }) {
        Text('Unicode:')
          .fontStyle(FontStyle.Italic)
          .fontColor($r('sys.color.ohos_id_color_foreground'))
          .fontSize(20)
          .fontWeight(FontWeight.Bolder)
          .textAlign(TextAlign.Start)
          .width('95%')

        TextArea({ placeholder: '', text: this.asciiString })
          .layoutWeight(1)
          .onChange((value: string) => {
            this.asciiString = value;
          })
      }
      .width('42%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
      .padding(4)
    }
    .padding(8)
  }
}