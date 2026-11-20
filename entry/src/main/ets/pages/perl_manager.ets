/**
 * Perl 管理（界面预览 · 功能打桩）
 * DEVENV-SPEC §6：runtime=perl，注册表 ~/usr/local/perl/.devbox/perl-registry.json
 */
import {
  LangRuntimePage,
  LangRuntimeConfig,
  DevVersionData,
} from '../common/component';
import { FeatureScope } from '../utils/FeatureScope';

function perlCfg(): LangRuntimeConfig {
  const installed: DevVersionData[] = [];
  const available: DevVersionData[] = [
    { ver: '5.38.2', sizeLabel: '约 37 MB', installed: false, active: false, alias: '', progress: -1 },
    { ver: '5.36.3', sizeLabel: '约 36 MB', installed: false, active: false, alias: '', progress: -1 },
  ];
  return {
    langKey: 'perl',
    title: 'Perl',
    subtitle: 'Perl · 运行时版本管理',
    sourceLabel: 'OHPCD 制品仓',
    sourcePending: false,
    pkgName: 'perl',

    installed: installed,
    available: available,
    tabLabels: FeatureScope.ECO_TABS ? ['运行时', '包与工具', '项目', '设置'] : ['运行时'],   // 商用范围开关（utils/FeatureScope.ets）
    ecoTabs: [
      { label: 'cpan', hint: '模块管理与镜像源（规划中）' },
      { label: '模块列表', hint: '已装模块列表与卸载（规划中）' },
    ],
  };
}

@Component
export struct PerlManager {
  @StorageProp('themeMode') themeReact: string = 'dark';
  build() {
    LangRuntimePage({ cfg: perlCfg() })
  }
}
