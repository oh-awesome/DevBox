/**
 * PHP 管理（界面预览 · 功能打桩）
 * FlyEnv 对齐：运行时四分栏 + Composer 生态 Tab + 扩展管理（C6 桩）
 */
import {
  LangRuntimePage,
  LangRuntimeConfig,
  DevVersionData,
} from '../common/component';
import { FeatureScope } from '../utils/FeatureScope';

function phpCfg(): LangRuntimeConfig {
  const installed: DevVersionData[] = [];
  const available: DevVersionData[] = [
    { ver: '8.3.13', sizeLabel: '约 36 MB', installed: false, active: false, alias: '', progress: -1 },
    { ver: '8.2.25', sizeLabel: '约 35 MB', installed: false, active: false, alias: '', progress: -1 },
    { ver: '8.1.30', sizeLabel: '约 34 MB', installed: false, active: false, alias: '', progress: -1 },
  ];
  return {
    langKey: 'php',
    title: 'PHP',
    subtitle: 'PHP · 运行时版本管理',
    sourceLabel: 'OHPCD 制品仓',
    sourcePending: false,
    pkgName: 'php',

    installed: installed,
    available: available,
    tabLabels: FeatureScope.ECO_TABS ? ['运行时', '包与工具', '项目', '设置'] : ['运行时'],   // 商用范围开关（utils/FeatureScope.ets）
    ecoTabs: [
      { label: 'Composer', hint: '依赖管理与镜像源（规划中）' },
      { label: '扩展管理', hint: '已加载扩展 / 安装 / 禁用（规划中）' },
      { label: 'php.ini', hint: '配置文件编辑（规划中）' },
    ],
  };
}

@Component
export struct PhpManager {
  @StorageProp('themeMode') themeReact: string = 'dark';
  build() {
    LangRuntimePage({ cfg: phpCfg() })
  }
}
