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
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import Logger from './Logger';
import json from '@ohos.util.json';
import { BusinessError } from '@kit.BasicServicesKit';
import { CommandManualData } from '../pages/manual_data';

const TAG = '[DEVBOXUTILS]';
// 手册信息路径前缀
const COMMAND_MANAL_PATH = 'commonManualInfo/';

export class DevBoxUtils {
  public static instance: DevBoxUtils;
  private uiAbilityContext?: common.UIAbilityContext;

  static getInstance(): DevBoxUtils {
    if (!DevBoxUtils.instance) {
      DevBoxUtils.instance = new DevBoxUtils();
    }
    return DevBoxUtils.instance;
  }

  setUIAbilityContext(currentUIAbilityContext: common.UIAbilityContext) {
    Logger.info(TAG, 'setUIAbilityContext');
    DevBoxUtils.getInstance().uiAbilityContext = currentUIAbilityContext;
  }


  /**
   * 获取开源软件配置文件目录列表
   */
  static getOpensourceFileList(): string[] {
    if (!DevBoxUtils.getInstance().uiAbilityContext) {
      Logger.error(TAG, 'uiAbilityContext error');
      return [];
    }
    try {
      let value: Uint8Array | undefined =
        DevBoxUtils.getInstance().uiAbilityContext?.resourceManager.getRawFileContentSync(COMMAND_MANAL_PATH +
          'all_manual_list.json');
      if (!value) {
        return [];
      }
      let allManualData: AllManualData[] = json.parse(DevBoxUtils.uint8ArrayToString(value)) as AllManualData[];
      if (!allManualData[0] || allManualData[0]?.filename.length < 1) {
        Logger.error(TAG, 'getOpensourceFileList getRawFileContent error');
      }
      return allManualData[0].filename;
    } catch (e) {
      const error = e as BusinessError;
      Logger.error(TAG, `getOpensourceFileList error code is ${error?.code} mgs: ${error.message}`);
      return [];
    }
  }

  static getAllManualInfo(): CommandManualData[] {
    let mergeList: CommandManualData[] = [];
    try {
      let fileList: string[] = DevBoxUtils.getOpensourceFileList();
      if (fileList.length === 0) {
        return mergeList;
      }
      Logger.info(TAG, `fileList length is ${fileList.length}`);
      // 合并每个文件数组
      for (let i = 0; i < fileList.length; i++) {
        let value: Uint8Array | undefined =
          DevBoxUtils.getInstance().uiAbilityContext?.resourceManager.getRawFileContentSync(COMMAND_MANAL_PATH +
          fileList[i]);
        if (!value) {
          return mergeList;
        }
        let commandManualDataList: CommandManualData[] =
          json.parse(DevBoxUtils.uint8ArrayToString(value)) as CommandManualData[];
        mergeList = mergeList.concat(commandManualDataList);
      }
      mergeList.sort((a: CommandManualData, b: CommandManualData) => {
        return a.name.localeCompare(b.name);
      })
      Logger.info(TAG, `mergeList length is ${mergeList.length}`);
    } catch (e) {
      const error = e as BusinessError;
      Logger.error(TAG, `getAllManualInfo error code is ${error?.code} mgs: ${error.message}`);
      return mergeList;
    }
    return mergeList;
  }

  /**
   * uint8ArrayToString
   */
  static uint8ArrayToString(array: Uint8Array): string {
    let textDecoderOptions: util.TextDecoderOptions = {
      fatal: false,
      ignoreBOM: true
    }
    let decodeToStringOptions: util.DecodeToStringOptions = {
      stream: false
    }
    let textDecoder = util.TextDecoder.create('utf-8', textDecoderOptions);
    let retStr = textDecoder.decodeToString(array, decodeToStringOptions);
    return retStr;
  }
}


export class AllManualData {
  filename: string[] = [];
}
