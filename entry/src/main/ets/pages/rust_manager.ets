/**
 * Rust 管理（RuntimeMgr 公共件）
 * 特化钩子：DevEnvHeal.healCargoBins（bin 链接到 ~/.cargo/bin）
 */
import {
  LangRuntimePage,
  LangRuntimeConfig,
} from '../common/component';
import { FeatureScope } from '../utils/FeatureScope';

function rustCfg(): LangRuntimeConfig {
  return {
    langKey: 'rust',
    title: 'Rust',
    subtitle: 'Rust · 运行时版本管理',
    sourceLabel: 'OHPCD 制品仓',
    sourcePending: false,
    installed: [],
    available: [],
    tabLabels: FeatureScope.ECO_TABS ? ['运行时', '包与工具', '项目', '设置'] : ['运行时'],   // 商用范围开关（utils/FeatureScope.ets）
    ecoTabs: [
      { label: 'cargo 工具', hint: 'rustfmt / clippy / rust-analyzer（随工具链提供）' },
      { label: 'crates 镜像', hint: 'rsproxy 镜像配置（规划中）' },
    ],
  };
}

@Component
export struct RustManager {
  build() {
    LangRuntimePage({ cfg: rustCfg() })
  }
}
