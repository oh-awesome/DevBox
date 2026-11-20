/**
 * Java 管理（RuntimeMgr 公共件 · BiShengJDK）
 * 特化钩子：DevEnvPaths.ensureJavaHome（ohpcd devenv 块内 JAVA_HOME）
 */
import {
  LangRuntimePage,
  LangRuntimeConfig,
} from '../common/component';
import { FeatureScope } from '../utils/FeatureScope';

function javaCfg(): LangRuntimeConfig {
  return {
    langKey: 'java',
    pkgName: 'BiShengJDK',
    title: 'Java',
    subtitle: 'Java · 运行时版本管理',
    sourceLabel: 'OHPCD 制品仓',
    sourcePending: false,
    installed: [],
    available: [],
    tabLabels: FeatureScope.ECO_TABS ? ['运行时', '包与工具', '项目', '设置'] : ['运行时'],   // 商用范围开关（utils/FeatureScope.ets）
    ecoTabs: [
      { label: 'Maven', hint: '依赖管理与镜像源（规划中）' },
      { label: 'Gradle', hint: '构建工具与镜像源（规划中）' },
    ],
  };
}

@Component
export struct JavaManager {
  build() {
    LangRuntimePage({ cfg: javaCfg() })
  }
}
