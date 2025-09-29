import { hilog } from '@kit.PerformanceAnalysisKit';
import miniTermNapi from 'libmini_terminal.so';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { fileUri, picker } from '@kit.CoreFileKit';


const DOMAIN = 0x0000;

miniTermNapi.run();

class MyXComponentController extends XComponentController {
  onSurfaceCreated(surfaceId: string): void {
    hilog.info(DOMAIN, 'testTag', 'onSurfaceCreated surfaceId: %{public}s', surfaceId);
    miniTermNapi.createSurface(BigInt(surfaceId));
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    hilog.info(DOMAIN, 'testTag', 'onSurfaceChanged surfaceId: %{public}s rect: %{public}s', surfaceId,
      JSON.stringify(rect));
    miniTermNapi.resizeSurface(BigInt(surfaceId), rect.surfaceWidth, rect.surfaceHeight);
  }

  onSurfaceDestroyed(surfaceId: string): void {
    hilog.info(DOMAIN, 'testTag', 'onSurfaceDestroyed surfaceId: %{public}s', surfaceId);
    miniTermNapi.destroySurface(BigInt(surfaceId))
  }
}

let keyMapping: Map<string, number[]> = new Map();
keyMapping.set("KEYCODE_SPACE", [0x20]);
keyMapping.set("KEYCODE_ENTER", [0x0d]);
keyMapping.set("KEYCODE_DEL", [0x7f]);
keyMapping.set("KEYCODE_TAB", [0x09]);
keyMapping.set("KEYCODE_ESCAPE", [0x1b]);
keyMapping.set("KEYCODE_DPAD_UP", [0x1b, 0x5b, 0x41]);
keyMapping.set("KEYCODE_DPAD_DOWN", [0x1b, 0x5b, 0x42]);
keyMapping.set("KEYCODE_DPAD_RIGHT", [0x1b, 0x5b, 0x43]);
keyMapping.set("KEYCODE_DPAD_LEFT", [0x1b, 0x5b, 0x44]);
keyMapping.set("KEYCODE_F1", [0x1b, 0x4f, 0x50]);
keyMapping.set("KEYCODE_F2", [0x1b, 0x4f, 0x51]);
keyMapping.set("KEYCODE_F3", [0x1b, 0x4f, 0x52]);
keyMapping.set("KEYCODE_F4", [0x1b, 0x4f, 0x53]);
keyMapping.set("KEYCODE_F5", [0x1b, 0x5b, 0x31, 0x35, 0x7e]);
keyMapping.set("KEYCODE_F6", [0x1b, 0x5b, 0x31, 0x37, 0x7e]);
keyMapping.set("KEYCODE_F7", [0x1b, 0x5b, 0x31, 0x38, 0x7e]);
keyMapping.set("KEYCODE_F8", [0x1b, 0x5b, 0x31, 0x39, 0x7e]);
keyMapping.set("KEYCODE_F10", [0x1b, 0x5b, 0x32, 0x31, 0x7e]);
keyMapping.set("KEYCODE_F11", [0x1b, 0x5b, 0x32, 0x33, 0x7e]);
keyMapping.set("KEYCODE_F12", [0x1b, 0x5b, 0x32, 0x34, 0x7e]);

@Component
export struct MiniTerminal {
  @State leftCtrlPressed: boolean = false;
  xComponentController: XComponentController = new MyXComponentController();
  @State HomePermission: boolean = false;
  @State DocumentPermission: boolean = false;
  @State DownloadPermission: boolean = false;
  @State DesktopPermission: boolean = false;

  async grantPermission(path: string): Promise<boolean> {
    let uri = fileUri.getUriFromPath(path);
    let DocumentSelectOptions: picker.DocumentSelectOptions = {
      selectMode: picker.DocumentSelectMode.FOLDER,
      authMode: true,
      defaultFilePathUri: uri
    };
    let documentPicker = new picker.DocumentViewPicker();
    let uris = await documentPicker.select(DocumentSelectOptions);
    if (uris[0] === undefined) {
      return false;
    }

    return true;
  }

  build() {
    Column() {
      Text($r("app.string.get_user_permission"))
        .height('7%')
      Row() {
        Button($r('app.string.get_user_permission_home'), { type: ButtonType.Normal })
          .grantButton()
          .fontColor('#000000')
          .fontWeight(FontWeight.Bold)
          .enabled(!this.HomePermission)
          .onClick(async () => {
            this.HomePermission = await this.grantPermission("/storage/Users/currentUser");
          })

        Button($r('app.string.get_user_permission_document'), { type: ButtonType.Normal })
          .grantButton()
          .fontColor('#000000')
          .fontWeight(FontWeight.Bold)
          .enabled(!this.DocumentPermission)
          .onClick(async () => {
            this.DocumentPermission = await this.grantPermission("/storage/Users/currentUser/Documents");
          })
        Button($r('app.string.get_user_permission_download'), { type: ButtonType.Normal })
          .grantButton()
          .fontColor('#000000')
          .fontWeight(FontWeight.Bold)
          .enabled(!this.DownloadPermission)
          .onClick(async () => {
            this.DownloadPermission = await this.grantPermission("/storage/Users/currentUser/Download");
          })

        Button($r('app.string.get_user_permission_desktop'), { type: ButtonType.Normal })
          .grantButton()
          .fontColor('#000000')
          .fontWeight(FontWeight.Bold)
          .enabled(!this.DesktopPermission)
          .onClick(async () => {
            this.DesktopPermission = await this.grantPermission("/storage/Users/currentUser/Desktop");
          })
      }
      .height(40)

      Stack() {
        XComponent({
          type: XComponentType.SURFACE,
          controller: this.xComponentController
        })
          .focusable(false)

        TextArea()
          .width('100%')
          .height('100%')
          .fontColor(Color.Transparent)
          .caretColor(Color.Transparent)
          .backgroundColor(Color.Transparent)
          .selectionMenuHidden(true)
          .enterKeyType(EnterKeyType.Go)
          .onKeyPreIme((event: KeyEvent) => {
            if (event.type === KeyType.Down) {
              if (this.leftCtrlPressed && event.unicode as number >= 97 && event.unicode as number <= 122) {
                // Ctrl-A to Ctrl-Z
                let buffer = new ArrayBuffer(1);
                let view = new Uint8Array(buffer);
                view[0] = event.unicode as number - 97 + 1; // ^A is 0x1
                miniTermNapi.send(buffer);
              } else if (event.keyText === "KEYCODE_EQUALS") {
                let buffer = new ArrayBuffer(1);
                let view = new Uint8Array(buffer);
                // workaround
                if (event.unicode === 0x3d) {
                  view[0] = 0x2b;
                } else {
                  view[0] = 0x3d;
                }
                miniTermNapi.send(buffer);
              } else if (event.unicode !== 0) {
                let textEncoder = util.TextEncoder.create('utf-8');
                let encodeResult = textEncoder.encodeInto(String.fromCharCode(event.unicode as number));
                miniTermNapi.send(encodeResult.buffer);
              } else {
                if (event.keyText === "KEYCODE_CTRL_LEFT") {
                  this.leftCtrlPressed = true;
                } else if (keyMapping.has(event.keyText)) {
                  let data: number[] = keyMapping.get(event.keyText)!;
                  let buffer = new ArrayBuffer(data.length);
                  let view = new Uint8Array(buffer);
                  let i = 0;
                  for (let byte of data) {
                    view[i] = byte;
                    i += 1;
                  }
                  miniTermNapi.send(buffer);
                }
              }
            } else if (event.type === KeyType.Up) {
              if (event.keyText === "KEYCODE_CTRL_LEFT") {
                this.leftCtrlPressed = false;
              }
            }
            return true;
          })
      }
      .width('100%')
      .height('85%')
    }
    .width('98%')
    .height('98%')
  }
}


@Styles
function grantButton() {
  .width('25%')
  .height("100%")
  .backgroundColor('#d2f1f1f1')
}