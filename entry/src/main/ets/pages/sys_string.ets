import { CommIconButton, IconButton } from "./icon_button";
import { pasteboard } from "@kit.BasicServicesKit";
import { promptAction } from "@kit.ArkUI";

@Component
export struct SysString {
  // 图片数据源（可替换为实际SVG资源路径）
  stringData: string[] = [
    'sys.string.ohos_id_text_font_family_regular',
    'sys.string.ohos_id_text_font_family_medium',
    'sys.string.ohos_lab_answer_call',
    'sys.string.ohos_desc_answer_call',
    'sys.string.ohos_lab_internet',
    'sys.string.ohos_desc_internet',
    'sys.string.ohos_lab_modify_audio_settings',
    'sys.string.ohos_desc_modify_audio_settings',
    'sys.string.ohos_lab_read_calendar',
    'sys.string.ohos_desc_read_calendar',
    'sys.string.ohos_lab_read_call_log',
    'sys.string.ohos_desc_read_call_log',
    'sys.string.ohos_lab_read_cell_messages',
    'sys.string.ohos_desc_read_cell_messages',
    'sys.string.ohos_lab_read_contacts',
    'sys.string.ohos_desc_read_contacts',
    'sys.string.ohos_lab_get_telephony_state',
    'sys.string.ohos_desc_get_telephony_state',
    'sys.string.ohos_lab_read_messages',
    'sys.string.ohos_desc_read_messages',
    'sys.string.ohos_lab_receive_mms',
    'sys.string.ohos_desc_receive_mms',
    'sys.string.ohos_lab_receive_sms',
    'sys.string.ohos_desc_receive_sms',
    'sys.string.ohos_lab_receive_wap_messages',
    'sys.string.ohos_desc_receive_wap_messages',
    'sys.string.ohos_lab_microphone',
    'sys.string.ohos_desc_microphone',
    'sys.string.ohos_lab_send_messages',
    'sys.string.ohos_desc_send_messages',
    'sys.string.ohos_lab_write_calendar',
    'sys.string.ohos_desc_write_calendar',
    'sys.string.ohos_lab_write_call_log',
    'sys.string.ohos_desc_write_call_log',
    'sys.string.ohos_lab_write_contacts',
    'sys.string.ohos_desc_write_contacts',
    'sys.string.ohos_lab_distributed_datasync',
    'sys.string.ohos_desc_distributed_datasync',
    'sys.string.ohos_lab_manage_voicemail',
    'sys.string.ohos_desc_manage_voicemail',
    'sys.string.ohos_lab_location_in_background',
    'sys.string.ohos_desc_location_in_background',
    'sys.string.ohos_lab_location',
    'sys.string.ohos_desc_location',
    'sys.string.ohos_lab_media_location',
    'sys.string.ohos_desc_media_location',
    'sys.string.ohos_lab_get_network_info',
    'sys.string.ohos_desc_get_network_info',
    'sys.string.ohos_lab_place_call',
    'sys.string.ohos_desc_place_call',
    'sys.string.ohos_lab_camera',
    'sys.string.ohos_desc_camera',
    'sys.string.ohos_lab_set_network_info',
    'sys.string.ohos_desc_set_network_info',
    'sys.string.ohos_lab_read_media',
    'sys.string.ohos_desc_read_media',
    'sys.string.ohos_lab_write_media',
    'sys.string.ohos_desc_write_media',
    'sys.string.ohos_lab_distributed_virtualdevice',
    'sys.string.ohos_desc_distributed_virtualdevice',
    'sys.string.ohos_lab_enroll_biometric',
    'sys.string.ohos_desc_enroll_biometric',
    'sys.string.ohos_lab_access_biometric',
    'sys.string.ohos_desc_access_biometric',
    'sys.string.ohos_lab_access_biometric_internal',
    'sys.string.ohos_desc_access_biometric_internal',
    'sys.string.ohos_lab_reset_biometric_lockout',
    'sys.string.ohos_desc_reset_biometric_lockout',
    'sys.string.ohos_lab_set_time',
    'sys.string.ohos_desc_set_time',
    'sys.string.ohos_lab_set_time_zone',
    'sys.string.ohos_desc_set_time_zone',
    'sys.string.ohos_lab_download_session_manager',
    'sys.string.ohos_desc_download_session_manager',
    'sys.string.ohos_lab_commonevent_sticky',
    'sys.string.ohos_desc_commonevent_sticky',
    'sys.string.ohos_lab_manage_local_accounts',
    'sys.string.ohos_desc_manage_local_accounts',
    'sys.string.ohos_lab_interact_across_local_accounts',
    'sys.string.ohos_desc_interact_across_local_accounts',
    'sys.string.ohos_lab_vibrate',
    'sys.string.ohos_desc_vibrate',
    'sys.string.ohos_lab_activity_motion',
    'sys.string.ohos_desc_activity_motion',
    'sys.string.ohos_lab_read_health_data',
    'sys.string.ohos_desc_read_health_data',
    'sys.string.ohos_lab_connect_ime_ability',
    'sys.string.ohos_desc_connect_ime_ability',
    'sys.string.ohos_lab_set_wallpaper',
    'sys.string.ohos_desc_set_wallpaper',
    'sys.string.ohos_lab_get_wallpaper',
    'sys.string.ohos_desc_get_wallpaper',
    'sys.string.ohos_lab_interact_across_local_accounts_extension',
    'sys.string.ohos_desc_interact_across_local_accounts_extension',
    'sys.string.ohos_lab_accelerometer',
    'sys.string.ohos_desc_accelerometer',
    'sys.string.ohos_lab_gyroscope',
    'sys.string.ohos_desc_gyroscope',
    'sys.string.ohos_lab_set_telephony_state',
    'sys.string.ohos_desc_set_telephony_state',
    'sys.string.ohos_lab_bundle_active_info',
    'sys.string.ohos_desc_bundle_active_info',
    'sys.string.ohos_lab_publish_agent_reminder',
    'sys.string.ohos_desc_publish_agent_reminder',
    'sys.string.ohos_lab_control_task_sync_animator',
    'sys.string.ohos_desc_control_task_sync_animator',
    'sys.string.ohos_lab_notification_controller',
    'sys.string.ohos_desc_notification_controller',
    'sys.string.ohos_app_name',
    'sys.string.ohos_lab_approximately_location',
    'sys.string.ohos_desc_approximately_location',
    'sys.string.ohos_lab_read_imagevideo',
    'sys.string.ohos_desc_read_imagevideo',
    'sys.string.ohos_lab_read_audio',
    'sys.string.ohos_desc_read_audio',
    'sys.string.ohos_lab_read_document',
    'sys.string.ohos_desc_read_document',
    'sys.string.ohos_lab_write_imagevideo',
    'sys.string.ohos_desc_write_imagevideo',
    'sys.string.ohos_lab_write_audio',
    'sys.string.ohos_desc_write_audio',
    'sys.string.ohos_lab_write_document',
    'sys.string.ohos_desc_write_document',
    'sys.string.ohos_lab_read_whole_calendar',
    'sys.string.ohos_desc_read_whole_calendar',
    'sys.string.ohos_lab_write_whole_calendar',
    'sys.string.ohos_desc_write_whole_calendar',
    'sys.string.ohos_lab_app_tracking_consent',
    'sys.string.ohos_desc_app_tracking_consent',
    'sys.string.ohos_lab_get_installed_bundle_list',
    'sys.string.ohos_desc_get_installed_bundle_list',
    'sys.string.ohos_id_text_location_button_description_current_location',
    'sys.string.ohos_id_text_location_button_description_add_location',
    'sys.string.ohos_id_text_location_button_description_select_location',
    'sys.string.ohos_id_text_location_button_description_share_location',
    'sys.string.ohos_id_text_location_button_description_send_location',
    'sys.string.ohos_id_text_location_button_description_locating',
    'sys.string.ohos_id_text_location_button_description_location',
    'sys.string.ohos_id_text_location_button_description_send_current_location',
    'sys.string.ohos_id_text_location_button_description_relocation',
    'sys.string.ohos_id_text_location_button_description_punch_in',
    'sys.string.ohos_id_text_location_button_description_current_position',
    'sys.string.ohos_id_text_paste_button_description_paste',
    'sys.string.ohos_id_text_save_button_description_download',
    'sys.string.ohos_id_text_save_button_description_download_file',
    'sys.string.ohos_id_text_save_button_description_save',
    'sys.string.ohos_id_text_save_button_description_save_image',
    'sys.string.ohos_id_text_save_button_description_save_file',
    'sys.string.ohos_id_text_save_button_description_download_and_share',
    'sys.string.ohos_id_text_save_button_description_receive',
    'sys.string.ohos_id_text_save_button_description_continue_to_receive',
    'sys.string.ohos_lab_access_bluetooth',
    'sys.string.ohos_desc_access_bluetooth',
    'sys.string.ohos_id_draggable_default',
    'sys.string.ohos_lab_get_phone_numbers',
    'sys.string.ohos_desc_get_phone_numbers',
    'sys.string.ohos_id_input_method_settings',
    'sys.string.ohos_lab_read_pasteboard',
    'sys.string.ohos_desc_read_pasteboard',
    'sys.string.ohos_id_divider_shadow_enable_default',
    'sys.string.ohos_id_text_camera_input',
    'sys.string.ohos_id_section_unfocus_effect_enable_default',
    'sys.string.ohos_id_sheet_type',
    'sys.string.ohos_id_multiple_dialog_display',
    'sys.string.ohos_id_expand_display',
    'sys.string.ohos_lab_read_write_download_directory',
    'sys.string.ohos_desc_read_write_download_directory',
    'sys.string.ohos_lab_read_write_documents_directory',
    'sys.string.ohos_desc_read_write_documents_directory',
    'sys.string.ohos_lab_read_write_desktop_directory',
    'sys.string.ohos_desc_read_write_desktop_directory',
    'sys.string.ohos_id_day_font_weight',
    'sys.string.ohos_id_work_state_font_weight',
    'sys.string.ohos_id_popup_double_border_enable_default',
    'sys.string.ohos_id_menu_bg_blur_effect_enable_default',
    'sys.string.ohos_id_menu_double_border_enable_default',
    'sys.string.ohos_grid_edit_title_edit',
    'sys.string.ohos_grid_edit_title_chanel',
    'sys.string.ohos_grid_edit_subtitle_sort',
    'sys.string.ohos_grid_edit_subtitle_add',
    'sys.string.ohos_network_not_connected',
    'sys.string.ohos_network_connected_unstable',
    'sys.string.ohos_unstable_connect_server',
    'sys.string.ohos_custom_network_tips_left',
    'sys.string.ohos_set_network',
    'sys.string.ohos_lab_access_nearlink',
    'sys.string.ohos_desc_access_nearlink',
    'sys.string.ohos_show_password_directly',
    'sys.string.ohos_id_text_fadeout_enable_default',
    'sys.string.ohos_id_list_fadeout_enable_default',
    'sys.string.ohos_textfield_show_handle',
    'sys.string.ohos_id_text_save_button_description_save_to_gallery',
    'sys.string.ohos_add_form_to_desktop',
    'sys.string.ohos_id_sheet_bottom',
    'sys.string.ohos_id_calendar_picker_dialog_button_transparent',
    'sys.string.ohos_id_calendar_picker_dialog_divider_transparent',
    'sys.string.ohos_id_menu_has_filter',
    'sys.string.icon_back',
    'sys.string.icon_cancel',
    'sys.string.icon_save',
    'sys.string.menu_normal_layout',
    'sys.string.menu_normal_placement',
    'sys.string.menu_back_blur',
    'sys.string.form_disable_time_limit',
    'sys.string.textfield_accessibility_property_clear',
    'sys.string.textfield_accessibility_show_password',
    'sys.string.textfield_accessibility_hide_password',
    'sys.string.ohos_toolbar_more',
    'sys.string.qrcode_expiration_prompt',
    'sys.string.slider_accessibility_selected',
    'sys.string.slider_accessibility_unselected',
    'sys.string.slider_accessibility_unselectedDesc',
    'sys.string.slider_accessibility_disabledDesc',
    'sys.string.general_confirm',
    'sys.string.general_last_step',
    'sys.string.general_next_step',
    'sys.string.last_updated_time',
    'sys.string.general_refresh',
    'sys.string.general_copy',
    'sys.string.general_cut',
    'sys.string.general_select_all',
    'sys.string.general_translate',
    'sys.string.general_share',
    'sys.string.general_search',
    'sys.string.general_open',
    'sys.string.general_close',
    'sys.string.general_start',
    'sys.string.general_skip',
    'sys.string.general_maximized_display',
    'sys.string.general_exit_maximized_display',
    'sys.string.general_full_screen_display',
    'sys.string.general_exit_full_screen_display',
    'sys.string.general_window_left_screen',
    'sys.string.general_window_right_screen',
    'sys.string.general_text_clock_week',
    'sys.string.general_display_lunar_calendar',
    'sys.string.general_calendar_week',
    'sys.string.general_year',
    'sys.string.general_month',
    'sys.string.general_day',
    'sys.string.general_pre_month',
    'sys.string.general_pre_year',
    'sys.string.general_next_year',
    'sys.string.general_next_month',
    'sys.string.general_today',
    'sys.string.pass_point',
    'sys.string.general_paste',
    'sys.string.general_cancel',
    'sys.string.general_more',
    'sys.string.stepper_back',
    'sys.string.stepper_next',
    'sys.string.res_writting_tool_bundle_name',
    'sys.string.res_writting_tool_ability_name',
    'sys.string.textfield_show_password',
    'sys.string.textfield_hide_password',
    'sys.string.textfield_show_password_button',
    'sys.string.textfield_hide_password_button',
    'sys.string.textfield_has_showed_password',
    'sys.string.textfield_has_hidden_password',
    'sys.string.ai_write_menu_name',
    'sys.string.calendar_picker_mon',
    'sys.string.calendar_picker_tue',
    'sys.string.calendar_picker_wed',
    'sys.string.calendar_picker_thu',
    'sys.string.calendar_picker_fri',
    'sys.string.calendar_picker_sat',
    'sys.string.calendar_picker_sun',
    'sys.string.save_button_description_export_to_gallery',
    'sys.string.save_button_description_quick_save_to_gallery',
    'sys.string.save_button_description_quick_resave_to_gallery',
    'sys.string.textfield_accessibility_clear',
    'sys.string.ohos_lab_short_term_write_imagevideo',
    'sys.string.ohos_desc_short_term_write_imagevideo',
    'sys.string.ohos_id_notification_restore_volume_tittle',
    'sys.string.ohos_id_notification_restore_volume_context',
    'sys.string.ohos_id_notification_restore_volume_button',
    'sys.string.ohos_id_notification_increase_volume_tittle',
    'sys.string.ohos_id_notification_increase_volume_context',
    'sys.string.ohos_id_notification_increase_volume_button',
    'sys.string.res_writting_tool_is_support',
    'sys.string.general_get_it',
    'sys.string.lab_developer_mode_tips',
    'sys.string.desc_developer_mode_tips',
    'sys.string.delete_used_for_accessibility_text',
    'sys.string.request_agent_download_success',
    'sys.string.request_agent_download_fail',
    'sys.string.request_agent_upload_file',
    'sys.string.request_agent_upload_success',
    'sys.string.request_agent_upload_fail',
    'sys.string.ohos_lab_custom_screen_capture',
    'sys.string.ohos_desc_custom_screen_capture',
    'sys.string.request_agent_download_file',
    'sys.string.save_button_description_save_all',
    'sys.string.menu_focus_directional_key_enable_default',
    'sys.string.notification_screen_recording_title',
    'sys.string.general_window_top_left_screen',
    'sys.string.general_window_top_right_screen',
    'sys.string.general_window_waterfall_mode',
    'sys.string.general_window_top_screen',
    'sys.string.general_window_bottom_screen',
    'sys.string.filter_accessibility_selected',
    'sys.string.filter_accessibility_unselected',
    'sys.string.filter_accessibility_expand',
    'sys.string.filter_accessibility_expanded',
    'sys.string.filter_accessibility_collapse',
    'sys.string.filter_accessibility_collapsed',
    'sys.string.filter_accessibility_filters',
    'sys.string.filter_accessibility_select_desc',
    'sys.string.filter_accessibility_unselect_desc',
    'sys.string.filter_accessibility_expand_desc',
    'sys.string.gridobjectsortcomponent_accessibility_selected_item',
    'sys.string.gridobjectsortcomponent_accessibility_selected_item_desc',
    'sys.string.gridobjectsortcomponent_accessibility_selected_item_delete',
    'sys.string.gridobjectsortcomponent_accessibility_selected_item_drag_start',
    'sys.string.gridobjectsortcomponent_accessibility_selected_item_drag_moving',
    'sys.string.gridobjectsortcomponent_accessibility_selected_item_drag_stop',
    'sys.string.gridobjectsortcomponent_accessibility_unselected_item_add',
    'sys.string.gridobjectsortcomponent_accessibility_item_long_press_gesture',
    'sys.string.gridobjectsortcomponent_accessibility_unselected_item',
    'sys.string.gridobjectsortcomponent_accessibility_unselected_image_item_desc',
    'sys.string.gridobjectsortcomponent_accessibility_unselected_text_item_desc',
    'sys.string.gridobjectsortcomponent_accessibility_unselected_button',
    'sys.string.gridobjectsortcomponent_accessibility_header_edit_button',
    'sys.string.gridobjectsortcomponent_accessibility_deleted',
    'sys.string.gridobjectsortcomponent_accessibility_illegal_area',
    'sys.string.treeview_accessibility_expand_node',
    'sys.string.treeview_accessibility_fold_node',
    'sys.string.treeview_accessibility_expanded_node',
    'sys.string.treeview_accessibility_folded_node',
    'sys.string.treeview_accessibility_node_desc',
    'sys.string.treeview_accessibility_select_node',
    'sys.string.treeview_accessibility_lift_node',
    'sys.string.treeview_accessibility_move_node_parent',
    'sys.string.treeview_accessibility_place_node_parent',
    'sys.string.treeview_accessibility_move_node_child',
    'sys.string.treeview_accessibility_place_node_child',
    'sys.string.treeview_accessibility_implement_node',
    'sys.string.selecttitlebar_accessibility_message_desc',
    'sys.string.subheader_accessibility_title',
    'sys.string.advanced_dialog_accessibility_checkbox',
    'sys.string.advanced_dialog_accessibility_cancel_checked_desc',
    'sys.string.sheet_type',
    'sys.string.dialog_title_font_weight',
    'sys.string.dialog_content_font_weight',
    'sys.string.res_menu_search_is_support',
    'sys.string.text_overlay_menu_copy',
    'sys.string.text_overlay_menu_paste',
    'sys.string.text_overlay_menu_select_all',
    'sys.string.text_overlay_menu_cut',
    'sys.string.ohos_app_has_locked',
    'sys.string.increase_used_for_accessibility_text',
    'sys.string.reduce_used_for_accessibility_text',
    'sys.string.prev_arrow_accessibility_text',
    'sys.string.next_arrow_accessibility_text',
    'sys.string.temporarily_disable_shutdown_findee_text',
    'sys.string.increase_counter_double_click_description',
    'sys.string.reduce_counter_double_click_description',
    'sys.string.res_menu_translate_is_support',
    'sys.string.input_counter_double_click_description',
    'sys.string.open_beauty',
    'sys.string.close_beauty',
    'sys.string.title_adjust_beauty',
    'sys.string.summary_closed_beauty',
    'sys.string.summary_opened_beauty',
    'sys.string.general_window_moveto_top_screen',
    'sys.string.general_window_moveto_bottom_screen',
    'sys.string.First_counter_accessibility_text',
    'sys.string.Second_counter_accessibility_text',
    'sys.string.Third_counter_accessibility_text',
    'sys.string.Fourth_counter_accessibility_text',
    'sys.string.Fifth_counter_accessibility_text',
    'sys.string.Sixth_counter_accessibility_text',
    'sys.string.Seventh_counter_accessibility_text',
    'sys.string.Eighth_counter_accessibility_text',
    'sys.string.Ninth_counter_accessibility_text',
    'sys.string.Tenth_counter_accessibility_text',
    'sys.string.Eleventh_counter_accessibility_text',
    'sys.string.Twelfth_counter_accessibility_text',
    'sys.string.Thirteenth_counter_accessibility_text',
    'sys.string.Fourteenth_counter_accessibility_text',
    'sys.string.Fifteenth_counter_accessibility_text',
    'sys.string.Sixteenth_counter_accessibility_text',
    'sys.string.Seventeenth_counter_accessibility_text',
    'sys.string.Eighteenth_counter_accessibility_text',
    'sys.string.Nineteenth_counter_accessibility_text',
    'sys.string.Twentieth_counter_accessibility_text',
    'sys.string.TwentyFirst_counter_accessibility_text',
    'sys.string.TwentySecond_counter_accessibility_text',
    'sys.string.TwentyThird_counter_accessibility_text',
    'sys.string.TwentyFourth_counter_accessibility_text',
    'sys.string.TwentyFifth_counter_accessibility_text',
    'sys.string.TwentySixth_counter_accessibility_text',
    'sys.string.TwentySeventh_counter_accessibility_text',
    'sys.string.TwentyEighth_counter_accessibility_text',
    'sys.string.TwentyNinth_counter_accessibility_text',
    'sys.string.Thirtieth_counter_accessibility_text',
    'sys.string.ThirtyFirst_counter_accessibility_text',
    'sys.string.off_used_for_accessibility_text',
    'sys.string.camera_device_eject_lab',
    'sys.string.camera_device_eject_desc',
    'sys.string.camera_device_block_confirm',
    'sys.string.camera_device_block_lab',
    'sys.string.camera_device_block_desc',
    'sys.string.camera_use_continue',
    'sys.string.request_agent_download_complete',
    'sys.string.request_agent_task_count',
    'sys.string.tips_double_border_enable_default',
    'sys.string.arkui_app_bar_service_panel',
    'sys.string.arkui_app_bar_close',
    'sys.string.sheet_close',
    'sys.string.navigation_back',
    'sys.string.menu_haptic_feedback',
    'sys.string.arkui_app_bar_provide_service',
    'sys.string.arkui_app_bar_maximize',
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
        ForEach(this.stringData, (item: string) => {
          GridItem() {
            Column({ space: 8 }) {
              Text($r(item))
                .width('80%')
                .height('60%')
                .fontWeight(FontWeight.Bold)
                .textAlign(TextAlign.Center)
                .minFontSize(10)  // 最小字号阈值
                .maxFontSize(24) // 最大字号范围
                .fontColor(Color.Black)

              Text(item)
                .fontSize(14)
                .textAlign(TextAlign.Center)
                .copyOption(CopyOptions.LocalDevice)
                .fontColor(Color.Black)
            }
            .padding(10)
            .backgroundColor(Color.White)
            .borderRadius(12)
            .onClick(() => {
              this.showDetails(item);
            })
          }
          .aspectRatio(1)
        })
      }
      .columnsTemplate('1fr 1fr 1fr')
      .rowsGap(16)
      .columnsGap(16)
      .padding(20)
    }
    .width('100%')
    .height('100%')
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
      Text($r(this.res))
        .width('80%')
        .height('60%')
        .minFontSize(14)  // 最小字号阈值
        .maxFontSize(50)  // 最大字号范围
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Center)

      Text(this.res)
        .fontSize(20)
        .textAlign(TextAlign.Center)
        .width('80%')

      CommIconButton({
        icon: $r('app.media.copy'),
        textResource: $r("app.string.copy"),
        onClickFunc: () => {
          let pasteData: pasteboard.PasteData =
            pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.res);
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
