/**
 * Ruby 管理（界面预览 · 功能打桩）
 * FlyEnv 对齐：运行时四分栏 + gem 源生态 Tab
 */
import { LangRuntimePage, LangRuntimeConfig } from '../common/component';


function rubyCfg(): LangRuntimeConfig {
  return {
    langKey: 'ruby',
    title: 'Ruby',
    subtitle: 'Ruby 运行时 · gem 源',
    sourceLabel: 'OHPCD 制品仓（待收录）',
    sourcePending: true,
    installed: [],
    available: [
      { ver: '3.3.6', sizeLabel: '约 24 MB', installed: false, active: false, alias: '', progress: -1 },
      { ver: '3.2.7', sizeLabel: '约 23 MB', installed: false, active: false, alias: '', progress: -1 },
    ],
    ecoTabs: [
      { label: 'gem 源', hint: 'RubyGems 镜像配置（规划中）' },
    ],
  };
}

@Component
export struct RubyManager {
  @StorageProp('themeMode') themeReact: string = 'dark';
  build() {
    LangRuntimePage({ cfg: rubyCfg() })
  }
}
