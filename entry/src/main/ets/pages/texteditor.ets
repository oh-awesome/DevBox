import { common } from '@kit.AbilityKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';

const  maxLinesForOneScreen : number = 29;

@Component
export struct TextEditor {
  @State leftContent: string = '1' + '\n'.repeat(maxLinesForOneScreen - 2);
  @State lineContent: string = '';
  @State textFontSize: number = 14;
  @State buttonFontSize: number = 15;
  @State lineHeight: number = this.textFontSize * 1.2;
  private lineScroller: Scroller = new Scroller();
  private textScroller: Scroller = new Scroller();
  private contentController: TextAreaController = new TextAreaController()
  @State menuWidth: number = 80;
  @State currentFileOpend: boolean = false;
  @State @Watch('getLineAreaWidth') lineCount: number = 1;
  
  @State message: string = '';
  @State filePath: string = '';
  @State fileUri: string = '';
  @State fileName: string = '';
  @State titleVisable: Visibility = Visibility.Hidden;
  @State editAreaHeight: number = this.lineHeight * maxLinesForOneScreen;
  @State lineWidth : number = 30; 
  
  getLineAreaWidth() {
    let linesCount = this.lineCount;
    this.lineWidth =  20 + linesCount.toString().length * 10
  }
  
  openFile() {
    let context = getContext(this) as common.Context;
    const options = new picker.DocumentSelectOptions();
    const documentPicker = new picker.DocumentViewPicker(context);
    options.fileSuffixFilters = ['.txt'];
    documentPicker.select(options).then((uris: Array<string>) => {
      this.fileUri = uris[0];
      this.filePath = new fileUri.FileUri(this.fileUri).path;
      this.fileName = new fileUri.FileUri(this.fileUri).name;
      this.lineContent = fs.readTextSync(this.filePath);
      this.titleVisable = Visibility.Visible;
    })
  }

  saveFile() {
    try {
      const options = new picker.DocumentSaveOptions();
      options.defaultFilePathUri = this.fileUri
      options.newFileNames = [this.fileName];
      options.fileSuffixChoices = ['.txt'];
      const filePicker = new picker.DocumentViewPicker();
      filePicker.save(options).then((uris: Array<string>) => {
        let newfile = new fileUri.FileUri(uris[0]).path;
        let file = fs.openSync(newfile, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        let writeLen = fs.writeSync(file.fd, this.lineContent);
        console.info("write data to file succeed and size is:" + writeLen);
        fs.closeSync(file);
      })
    } catch (err) {
      console.error('保存失败:', JSON.stringify(err));
    }
  }
  
  @Builder
  fileMenu () {
    Menu() {
      MenuItem({ content: $r('app.string.notepad_file_open') })
      .onClick(() => {
        this.openFile();
      })
      MenuItem({ content: $r('app.string.notepad_file_save') })
      .onClick(() => {
        this.saveFile();
      })
    }
    .width(this.menuWidth * 1.5)
  }
  
  @Builder
  editMenu () {
    Menu() {
      MenuItem({ content: $r('app.string.notepad_edit_undo') })
      .onClick(() => {
      })
      MenuItem({ content: $r('app.string.notepad_edit_redo') })
      .onClick(() => {
        
      })
      MenuItem({ content: $r('app.string.notepad_edit_copy') })
      .onClick(() => {
        
      })
      MenuItem({ content: $r('app.string.notepad_edit_paste') })
      .onClick(() => {
        
      })
    }
    .width(this.menuWidth * 1.5)
    .enabled(false)
  }
  
  build() {
    Column() {
       Row() {
        Row() {
          Button($r('app.string.notepad_file'), { type: ButtonType.Normal })
          .buttonStyle(ButtonStyleMode.NORMAL)
          .controlSize(ControlSize.SMALL)
          .backgroundColor(Color.Transparent)
          .width(this.menuWidth)
          .borderRadius(4)
          .fontSize(this.buttonFontSize)
          .padding(0)
          .fontColor(Color.Black)
          .bindMenu(this.fileMenu())

        Divider()
        .color($r('app.color.editor_divider'))
        .height('100%')
        .vertical(true)
        .strokeWidth('1px')

         Button($r('app.string.notepad_edit'), { type: ButtonType.Normal })
          .buttonStyle(ButtonStyleMode.NORMAL)
          .controlSize(ControlSize.SMALL)
          .backgroundColor(Color.Transparent)
          .width(this.menuWidth)
          .borderRadius(4)
          .fontSize(this.buttonFontSize)
          .padding(0)
          .fontColor(Color.Black)
          .bindMenu(this.editMenu())
          .enabled(false)
          .visibility(Visibility.Hidden)
        }
        .height(this.lineHeight + 8)
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
      .justifyContent(FlexAlign.Start)
      .height(this.lineHeight + 12)
      
      Divider()
      .color($r('app.color.editor_divider'))
      .width('100%')
      .strokeWidth('1px')

      if (this.titleVisable == Visibility.Visible){
        Text(this.fileName)
        .height(this.lineHeight * 1.5)
        .textAlign(TextAlign.Start)
        .width('100%')
      }
      
      Row() {
        Scroll(this.lineScroller) {
          TextArea({ text: this.leftContent})
          .width(this.lineWidth)
          .fontSize(this.textFontSize)
          .lineHeight(this.lineHeight)
          .fontColor($r('app.color.editor_line_number_text'))
          .backgroundColor($r('app.color.editor_line_number_bar'))
          .textAlign(TextAlign.End)
          .borderRadius(0)
          .padding({ left: 4})
          .focusable(false)
        }
        .scrollBar(BarState.Off)
        .onScroll(() => {
          let scrollHeight = this.lineScroller.currentOffset().yOffset;
          this.textScroller.scrollTo({ xOffset: 0, yOffset: scrollHeight })
        })
        .height(this.editAreaHeight)

        Divider()
        .color($r('app.color.editor_divider'))
        .vertical(true)
        .strokeWidth('1px')
        .height(this.editAreaHeight)
        
        Scroll(this.textScroller) {
          TextArea({
            text: this.lineContent,
            controller: this.contentController
          })
          .fontSize(this.textFontSize)
          .lineHeight(this.lineHeight)
          .fontColor($r('app.color.editor_text'))
          .backgroundColor($r('app.color.editor_area_background'))
          .width('90%')
          .id('TextAreaForTxt')
          .borderRadius(0)
          .defaultFocus(true)
          .onAppear(() => {
            focusControl.requestFocus('TextAreaForTxt')
          })
          .onChange((value: string) => {
            this.lineContent = value;
            this.lineCount = this.contentController.getTextContentLineCount()
            if (this.lineCount == 0) {
              this.leftContent = '1' + '\n'.repeat(maxLinesForOneScreen - 2);
              return;
            }
            this.leftContent = "1";
            for (let i = 1; i < this.lineCount; i++) {
              this.leftContent += '\n' + (i + 1).toString();
            }
            if (this.lineCount < maxLinesForOneScreen) {
              this.leftContent += '\n'.repeat(maxLinesForOneScreen - this.lineCount - 1);
            }
          })
        }
        .onScroll(() => {
          let scrollHeight = this.textScroller.currentOffset().yOffset;
          this.lineScroller.scrollTo({ xOffset: 0, yOffset: scrollHeight })
        })
        .height(this.editAreaHeight)
        .align(Alignment.TopStart)
      }
      .border({
        width: 1,
        color: $r('app.color.editor_divider'),
        radius: 4
      })
      .alignItems(VerticalAlign.Top)
    }
  }
}