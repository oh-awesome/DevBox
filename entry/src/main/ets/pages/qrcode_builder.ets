import picker from '@ohos.file.picker';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs'
import { generateBarcode, scanCore } from '@kit.ScanKit';
import { fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit'

const TAG = 'QrcodeBuilder';

@Component
export struct QrcodeBuilder {
  @State userText: string = '你好';
  @State pixelMap: image.PixelMap | undefined = undefined;
  @State numb: number = 1;
  @State valuedToSend: string = '';
  dialogCOntrollerInput: CustomDialogController = new CustomDialogController({
    builder: CustomDialogControllerInput({
      receivedValue: this.valuedToSend,
      onClickOK: (value: string): void => this.saveTask(value)
    })
  })
  dialogCOntrollerCard: CustomDialogController = new CustomDialogController({
    builder: CustomDialogControllerCard({
      onClickOK: (value: string): void => this.saveTask(value)
    })
  })

  aboutToAppear(): void {
    this.generateQrCode();
  }

  saveTask(value: string) {
    this.userText = value;
  }

  // 通过FilePicker保存文件
  async saveQRCode() {
    const imagePackerApi = image.createImagePacker();
    let documentSaveOptions = new picker.DocumentSaveOptions();
    documentSaveOptions.fileSuffixChoices = ['.jpeg', 'png', 'jpg', '*'];
    let documentPicker = new picker.DocumentViewPicker();
    documentPicker.save(documentSaveOptions).then(async (uris: Array<string>) => {
      const path: string = new fileUri.FileUri(uris[0]).path;
      let file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      let packOpts: image.PackingOption = { format: 'image/jpeg', quality: 98 };
      packOpts.desiredDynamicRange = image.PackingDynamicRange.AUTO;
      imagePackerApi.packToFile(this.pixelMap, file.fd, packOpts).then(() => {
        console.log(TAG, 'save image success');
      }).catch((err: BusinessError) => {
        console.log(TAG, 'save image success');
      }).finally(() => {
        if (file) {
          fs.closeSync(file.fd)
        }
      })
    })
  }

  generateQrCode() {
    let options: generateBarcode.CreateOptions = {
      scanType: scanCore.ScanType.QR_CODE,
      height: 200,
      width: 200
    }
    generateBarcode.createBarcode(this.userText, options, (error, pixelMap: image.PixelMap) => {
      if (error) {
        console.log('generete bar code failed' + JSON.stringify(error));
        return;
      }
      this.pixelMap = pixelMap;
    })
  }

  @Builder
  tipsList() {
    Scroll() {
      Column({ space: 15 }) {
        Button($r('app.string.ecard_qr'))
          .onClick(() => {
            this.dialogCOntrollerCard.open();
          })
          .buttonExtend()

        Button($r('app.string.phone_qr'))
          .onClick(() => {
            this.dialogCOntrollerInput.open();
            this.valuedToSend = '手机号'
          })
          .buttonExtend()

        Button('email')
          .onClick(() => {
            this.dialogCOntrollerInput.open();
            this.valuedToSend = 'email'
          })
          .buttonExtend()

        Button($r('app.string.vx_account_qr'))
          .onClick(() => {
            this.dialogCOntrollerInput.open();
            this.valuedToSend = '微信公众号';
          })
          .buttonExtend()

        Button('WIFI')
          .onClick(() => {
            this.dialogCOntrollerInput.open();
            this.valuedToSend = 'WIFI'
          })
          .buttonExtend()
      }
    }
    .height(400)
    .margin(16)
  }

  build() {
    Column({ space: 15 }) {
      Row() {
        this.tipsList();
        Column() {
          TextArea({ text: this.userText })
            .onChange((value: string) => {
              this.userText = value;
            })
            .key(TAG)
            .onAppear(() => {
              focusControl.requestFocus(TAG)
            })
            .height(150)
            .width('80%')
            .margin({ bottom: 16 })

          Row() {
            Row() {
              Row() {
                if (this.pixelMap) {
                  Image(this.pixelMap)
                    .objectFit(ImageFit.Contain)
                } else {
                  Blank()
                }
              }
              .width(250)
              .height(250)
              .margin({ right: 30 })


              Column() {
                Button($r('app.string.builder_qrcode'))
                  .margin({ bottom: 30 })
                  .onClick(() => {
                    this.generateQrCode();
                  })
                  .width(150)
                Button($r('app.string.save_qrcode'))
                  .width(150)
                  .onClick(() => {
                    this.saveQRCode();
                  })
              }
              .margin({ right: 20 })
            }
            .width('80%')
            .justifyContent(FlexAlign.Start)
            .alignItems(VerticalAlign.Center)
          }
        }
      }
    }
    .padding(16)
  }
}


@CustomDialog
struct CustomDialogControllerInput {
  controller: CustomDialogController;
  receivedValue?: string;
  @State output: string = '';
  onClickOK?: (value: string) => void;

  build() {
    Column() {
      Row() {
        TextInput({ placeholder: '请输入' + this.receivedValue })
          .onChange((value: string) => {
            this.output = value;
          })
          .width(300)

        Button('确认')
          .onClick(() => {
            if (this.onClickOK != undefined) {
              this.onClickOK(this.output);
            }
            this.controller.close();
          })
          .width('20%')
      }
      .justifyContent(FlexAlign.Center)
      .margin(16)
      .height(50)
    }
    .align(Alignment.Center)
  }
}

@CustomDialog
struct CustomDialogControllerCard {
  controller: CustomDialogController;
  @State cardOption: string[] = ['姓名', '手机', '电话', '公司', '职位', '公司地址', '备注'];
  @State cardOutput: string[] = ['', '', '', '', '', '', ''];
  @State output: string = '';
  @State index: number = 0;
  onClickOK?: (value: string) => void;

  build() {
    Column() {
      Grid() {
        ForEach(this.cardOption, (item: string, index: number) => {
          GridItem() {
            Column() {
              Text(item)
              TextInput({ placeholder: item })
                .onChange((value: string) => {
                  this.index = index;
                  this.cardOutput[this.index] = value;
                })
            }
            .margin(4)
          }
        })
      }
      .rowsTemplate('4fr 4fr 4fr 4fr')
      .columnsTemplate('4fr 4fr')
      .height(300)
      .margin(8)

      Button('确认')
        .margin({ bottom: 8 })
        .onClick(() => {
          this.index = 0;
          for (; this.index < this.cardOption.length; ++this.index) {
            if (this.index != 0 && this.index % 2 === 0) {
              this.output += '\n';
            }
            this.output += this.cardOption[this.index] + ':' + this.cardOutput[this.index] + '   ';
          }
          if (this.onClickOK != undefined) {
            this.onClickOK(this.output);
          }
          this.controller.close();
        })
    }
    .align(Alignment.Center)
  }
}


@Extend(Button)
function buttonExtend() {
  .height(50)
  .width('15%')
  .fontSize(16)
  .flexGrow(1)
  .padding(0)
  .margin({ bottom: 16 })
}
