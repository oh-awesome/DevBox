/**
 * Bun 管理（界面预览 · 功能打桩）
 * FlyEnv 对齐：运行时四分栏
 */
import { LangRuntimePage, LangRuntimeConfig } from '../common/component';


function bunCfg(): LangRuntimeConfig {
  return {
    langKey: 'bun',
    title: 'Bun',
    subtitle: 'Bun 运行时 · 一体化 JavaScript 工具链',
    sourceLabel: 'OHPCD 制品仓（待收录）',
    sourcePending: true,
    installed: [],
    available: [
      { ver: '1.1.38', sizeLabel: '约 60 MB', installed: false, active: false, alias: '', progress: -1 },
      { ver: '1.0.35', sizeLabel: '约 58 MB', installed: false, active: false, alias: '', progress: -1 },
    ],
    ecoTabs: [],
  };
}

@Component
export struct BunManager {
  @StorageProp('themeMode') themeReact: string = 'dark';
  build() {
    LangRuntimePage({ cfg: bunCfg() })
  }
}
