/**
 * Lua 管理（界面预览 · 功能打桩）
 * DEVENV-SPEC §6：runtime=lua，注册表 ~/usr/local/lua/.devbox/lua-registry.json
 */
import {
  LangRuntimePage,
  LangRuntimeConfig,
  DevVersionData,
} from '../common/component';
import { FeatureScope } from '../utils/FeatureScope';

function luaCfg(): LangRuntimeConfig {
  const installed: DevVersionData[] = [];
  const available: DevVersionData[] = [
    { ver: '5.4.7', sizeLabel: '约 1.4 MB', installed: false, active: false, alias: '', progress: -1 },
    { ver: '5.3.6', sizeLabel: '约 1.3 MB', installed: false, active: false, alias: '', progress: -1 },
  ];
  return {
    langKey: 'lua',
    title: 'Lua',
    subtitle: 'Lua · 运行时版本管理',
    sourceLabel: 'OHPCD 制品仓',
    sourcePending: false,
    pkgName: 'lua',

    installed: installed,
    available: available,
    tabLabels: FeatureScope.ECO_TABS ? ['运行时', '包与工具', '项目', '设置'] : ['运行时'],   // 商用范围开关（utils/FeatureScope.ets）
    ecoTabs: [
      { label: 'luarocks', hint: '包管理与镜像源（规划中）' },
      { label: 'luaRocks 列表', hint: '已装 rock 列表与卸载（规划中）' },
    ],
  };
}

@Component
export struct LuaManager {
  @StorageProp('themeMode') themeReact: string = 'dark';
  build() {
    LangRuntimePage({ cfg: luaCfg() })
  }
}
