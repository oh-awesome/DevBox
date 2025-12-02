/*
 * Copyright (c) 2025 OpenHarmonyPCDeveloper
 *
 * Licensed under the Mulan PSL v2 (the "License");
 * You can use this software according to the terms and conditions of the Mulan PSL v2.
 * You may obtain a copy of Mulan PSL v2 at:
 *
 *          http://license.coscl.org.cn/MulanPSL2
 *
 * THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
 * EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
 * MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
 * See the Mulan PSL v2 for more details.
 */

export enum LicenseType {
  APACHE_1 = 'Apache-1.0', // Apache License 1.0
  APACHE_1_1 = 'Apache-1.1', // Apache License 1.1
  APACHE_2 = 'Apache-2.0', // Apache License 2.0

  BSD_0 = '0BSD', // BSD Zero Clause License
  BSD_1 = 'BSD-1-Clause', // BSD 1-Clause License
  BSD_2 = 'BSD-2-Clause', // BSD 2-Clause "Simplified" License
  BSD_3 = 'BSD-3-Clause', // BSD 3-Clause "New" or "Revised" License
  BSD_4 = 'BSD-4-Clause', // BSD 4-Clause "Original" or "Old" License

  BZIP_2 = 'bzip2-1.0.6', // bzip2 and libbzip2 License v1.0.6

  GPL_V1O = 'GPL-1.0-only', // GNU General Public License v1.0 only
  GPL_V1L = 'GPL-1.0-or-later', // GNU General Public License v1.0 or later
  GPL_V2O = 'GPL-2.0-only', // GNU General Public License v2.0 only
  GPL_V2L = 'GPL-2.0-or-later', // GNU General Public License v2.0 or later
  GPL_V3O = 'GPL-3.0-only', // GNU General Public License v3.0 only
  GPL_V3L = 'GPL-3.0-or-later', // GNU General Public License v3.0 or later

  MIT = 'MIT', // MIT License

  MPL_1 = 'MPL-1.0', // Mozilla Public License 1.0
  MPL_1_1 = 'MPL-1.1', // Mozilla Public License 1.1
  MPL_2 = 'MPL-2.0', // Mozilla Public License 2.0

  VIM = 'Vim', // Vim License

  ZLIB = 'Zlib', // zlib License
}

export class Constants {
  public static readonly LICENSE_NAME_COLOR_MAP: Map<LicenseType, Resource> = new Map([
    [LicenseType.APACHE_1, $r('sys.color.ohos_id_color_text_highlight_bg')],
    [LicenseType.APACHE_1_1, $r('sys.color.ohos_id_color_text_highlight_bg_transparent')],
    [LicenseType.APACHE_2, $r('sys.color.ohos_id_color_text_highlight_bg_contrary')],

    [LicenseType.BSD_0, $r('sys.color.ohos_id_color_titlebar_icon')],
    [LicenseType.BSD_1, $r('sys.color.ohos_id_color_titlebar_icon')],
    [LicenseType.BSD_2, $r('sys.color.ohos_id_color_titlebar_icon')],
    [LicenseType.BSD_3, $r('sys.color.ohos_id_color_titlebar_icon')],
    [LicenseType.BSD_4, $r('sys.color.ohos_id_color_titlebar_icon')],

    [LicenseType.BZIP_2, $r('sys.color.ohos_id_color_titlebar_icon')],

    [LicenseType.GPL_V1O, $r('sys.color.ohos_id_color_titlebar_icon')],
    [LicenseType.GPL_V1L, $r('sys.color.ohos_id_color_titlebar_icon')],
    [LicenseType.GPL_V2O, $r('sys.color.ohos_id_color_titlebar_icon')],
    [LicenseType.GPL_V2L, $r('sys.color.ohos_id_color_titlebar_icon')],
    [LicenseType.GPL_V3O, $r('sys.color.ohos_id_color_titlebar_icon')],
    [LicenseType.GPL_V3L, $r('sys.color.ohos_id_color_titlebar_icon')],

    [LicenseType.MIT, $r('sys.color.ohos_id_color_titlebar_icon')],

    [LicenseType.MPL_1, $r('sys.color.ohos_id_color_titlebar_icon')],
    [LicenseType.MPL_1_1, $r('sys.color.ohos_id_color_titlebar_icon')],
    [LicenseType.MPL_2, $r('sys.color.ohos_id_color_titlebar_icon')],

    [LicenseType.VIM, $r('sys.color.ohos_id_color_titlebar_icon')],

    [LicenseType.ZLIB, $r('sys.color.ohos_id_color_titlebar_icon')],
  ]);
}
