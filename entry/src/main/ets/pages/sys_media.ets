import { IconButton } from "./icon_button";
import { pasteboard } from "@kit.BasicServicesKit";
import { promptAction } from "@kit.ArkUI";

@Component
export struct SysMedia {
  // 图片数据源（可替换为实际SVG资源路径）
  mediaData: string[] = [
    'sys.media.ohos_app_icon',
    'sys.media.ohos_ic_back',
    'sys.media.ohos_ic_public_ok',
    'sys.media.ohos_ic_public_arrow_left',
    'sys.media.ohos_ic_public_arrow_right',
    'sys.media.ohos_ic_public_arrow_up',
    'sys.media.ohos_ic_public_arrow_down',
    'sys.media.ohos_ic_public_cut',
    'sys.media.ohos_ic_public_copy',
    'sys.media.ohos_ic_public_paste',
    'sys.media.ohos_ic_public_select_all',
    'sys.media.ohos_ic_public_share',
    'sys.media.ohos_ic_public_translate_c2e',
    'sys.media.ohos_ic_public_search_filled',
    'sys.media.ohos_save_button_filled',
    'sys.media.ohos_save_button_line',
    'sys.media.ohos_ic_bottomsheet_close',
    'sys.media.ohos_ic_public_clock',
    'sys.media.ohos_ic_public_email',
    'sys.media.ohos_ic_public_express',
    'sys.media.ohos_ic_public_flight',
    'sys.media.ohos_ic_public_location',
    'sys.media.ohos_ic_public_phone',
    'sys.media.ohos_ic_public_text',
    'sys.media.ohos_ic_public_web',
    'sys.media.ohos_ic_public_device_matebook',
    'sys.media.ohos_ic_public_device_pad',
    'sys.media.ohos_ic_public_device_smartscreen',
    'sys.media.ohos_ic_public_device_watch',
    'sys.media.ohos_ic_public_device_phone',
    'sys.media.ohos_ic_eco_hop',
    'sys.media.ohos_ic_public_more',
    'sys.media.ohos_ic_public_add',
    'sys.media.ohos_ic_public_minus',
    'sys.media.ohos_ic_public_cast_stream',
    'sys.media.ohos_ic_public_cast_mirror',
    'sys.media.ohos_ic_public_camera',
    'sys.media.ohos_ic_public_cancel',
    'sys.media.ohos_ic_public_hang_up',
    'sys.media.ohos_ic_public_pause',
    'sys.media.ohos_ic_public_play_last',
    'sys.media.ohos_ic_public_play_next',
    'sys.media.ohos_ic_public_play',
    'sys.media.ohos_ic_public_restore',
    'sys.media.ohos_ic_public_sound_off',
    'sys.media.ohos_ic_public_sound',
    'sys.media.ohos_ic_public_video_off',
    'sys.media.ohos_ic_public_video',
    'sys.media.ohos_ic_public_voice_off',
    'sys.media.ohos_ic_public_voice',
    'sys.media.ohos_ic_public_albums',
    'sys.media.ohos_ic_public_scan',
    'sys.media.ohos_ic_public_add_norm_filled',
    'sys.media.ohos_ic_public_remove_filled',
    'sys.media.ohos_ic_public_edit',
    'sys.media.ohos_ic_public_fail',
    'sys.media.ohos_ic_public_close',
    'sys.media.ohos_ic_compnent_titlebar_back',
    'sys.media.ohos_ic_compnent_titlebar_back_filled',
    'sys.media.ohos_ic_public_cancel_filled',
    'sys.media.ohos_ic_public_drawer_close',
    'sys.media.ohos_ic_public_drawer_close_filled',
    'sys.media.ohos_ic_public_drawer_open',
    'sys.media.ohos_ic_public_drawer_open_filled',
    'sys.media.ohos_ic_public_input_cancel',
    'sys.media.ohos_ic_normal_white_grid_zip',
    'sys.media.ohos_ic_normal_white_grid_xml',
    'sys.media.ohos_ic_normal_white_grid_xls',
    'sys.media.ohos_ic_normal_white_grid_wma',
    'sys.media.ohos_ic_normal_white_grid_wav',
    'sys.media.ohos_ic_normal_white_grid_video',
    'sys.media.ohos_ic_normal_white_grid_txt',
    'sys.media.ohos_ic_normal_white_grid_pdf',
    'sys.media.ohos_ic_normal_white_grid_mp3',
    'sys.media.ohos_ic_normal_white_grid_image',
    'sys.media.ohos_ic_normal_white_grid_html',
    'sys.media.ohos_ic_normal_white_grid_folder',
    'sys.media.ohos_ic_normal_white_grid_flac',
    'sys.media.ohos_ic_normal_white_grid_doc',
    'sys.media.ohos_ic_normal_white_grid_compress',
    'sys.media.ohos_ic_normal_white_grid_calendar',
    'sys.media.ohos_ic_normal_white_grid_audio',
    'sys.media.ohos_icon_mask_svg',
    'sys.media.ohos_ic_public_remove',
    'sys.media.ohos_user_auth_icon_face',
    'sys.media.ohos_user_auth_icon_fingerprint',
    'sys.media.ohos_ic_public_device_bluetooth_filled',
    'sys.media.ohos_ic_public_device_earphone_filled',
    'sys.media.ohos_ic_public_device_earpiece_filled',
    'sys.media.ohos_ic_public_device_speaker_filled',
    'sys.media.ohos_ic_public_device_sound_filled',
    'sys.media.ohos_ic_public_device_soundx_filled',
    'sys.media.ohos_ic_public_device_smartscreen_filled',
    'sys.media.ohos_ic_public_ok_filled',
    'sys.media.save_button_picture',
    'sys.media.clone_app_badge_1',
    'sys.media.clone_app_badge_2',
    'sys.media.clone_app_badge_3',
    'sys.media.clone_app_badge_4',
    'sys.media.clone_app_badge_5',
    'sys.media.ic_public_worldclock_filled',
    'sys.media.ic_public_ai_write',
    'sys.media.Copy_Drag',
    'sys.media.Copy_One_Drag',
    'sys.media.Forbid_Drag',
    'sys.media.Forbid_One_Drag',
    'sys.media.Move_Drag',
    'sys.media.safe_volume_notification_icon',
    'sys.media.app_lock_picture',
    'sys.media.ohos_ic_window_menu_screen_t',
    'sys.media.ohos_ic_window_menu_screen_b',
    'sys.media.ohos_ic_window_menu_waterfall',
    'sys.media.ic_public_camera_beauty',
    'sys.media.ohos_ic_window_menu_moveto_t',
    'sys.media.ohos_ic_window_menu_moveto_b',
    'sys.media.ohos_ic_window_menu_back',
    'sys.media.ic_time_limit_picture',

  ]
  private dialogController: CustomDialogController | undefined = undefined;

  showDetails(res: string): void {
    try {
      this.dialogController = new CustomDialogController({
        builder: SysResourceDetails({
          res: res
        }),
        autoCancel: true,
        width: 500,
        onWillDismiss: (action: DismissDialogAction) => {
          if (action.reason === DismissReason.PRESS_BACK) {
            return;
          }
          action.dismiss();
        }
      });
      this.dialogController.open();
    } catch (error) {
      console.error('Failed to open dialog:', error.message);
    }
  }

  build() {
    Column() {
      Grid() {
        ForEach(this.mediaData, (item: string) => {
          GridItem() {
            Column({ space: 8 }) {
              Image($r(item))
                .width(80)
                .height(80)
                .objectFit(ImageFit.Contain)

              Text(item)
                .maxLines(1)  // 优先限制行数
                .minFontSize(8)  // 最小字号阈值
                .maxFontSize(24)  // 最大字号范围
                .textAlign(TextAlign.Center)
                .copyOption(CopyOptions.LocalDevice)
            }
            .padding(10)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .onClick(() => {
              this.showDetails(item);
            })
          }
          .aspectRatio(1)
        })
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .rowsGap(16)
      .columnsGap(16)
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}

@CustomDialog
struct SysResourceDetails {
  @Prop res: string = '';
  controller: CustomDialogController;

  closeDialog(): void {
    this.controller.close();
  }

  build() {
    Column({ space: 8 }) {
      Image($r(this.res))
        .width('60%')
        .height('60%')
        .objectFit(ImageFit.Contain)

      Text(this.res)
        .maxLines(1)  // 优先限制行数
        .minFontSize(14)  // 最小字号阈值
        .maxFontSize(24)  // 最大字号范围
        .textAlign(TextAlign.Center)
        .width('80%')

      IconButton({
        icon: $r('app.media.copy'),
        fontSize: 16,
        text: '复制',
        fontColor: $r('app.color.button_copy_text'),
        color: $r('app.color.button_copy_background'),
        onClickFunc: () => {
          let pasteData: pasteboard.PasteData =
            pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.res);
          let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
          try {
            systemPasteboard.setDataSync(pasteData);
            promptAction.showToast({
              message: '已复制到剪贴板',
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
        .height(40)
        .width('50%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
