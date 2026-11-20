/**
 * FeatureScope —— 商用发布功能范围开关（集中翻转点）
 *
 * 背景：2026-11-11 商用发布裁剪（详见 docs/商用发布-功能范围.md）。
 * 裁剪走渲染层（tab/侧边栏不渲染），页面代码与数据全部保留。
 * 后续功能筹备完成上线：把对应开关改 true 即恢复，无需找散落各处的裁剪点。
 *
 * 恢复时还需同步（仅自动化测试资产）：
 *  - test/ui_automation/templates/meta.json：加回 sidebar_Ruby / sidebar_Bun 条目
 *  - test/ui_automation/gen_templates.py：SIDEBAR_ITEMS 加回（重新生成模板用）
 */
export class FeatureScope {
  /** 各语言生态 tab（java/rust/lua/perl/go/php 的 包与工具/项目/设置） */
  static readonly ECO_TABS: boolean = false;
  /** python / node 的「项目管理」tab */
  static readonly PROJECT_TAB: boolean = false;
  /** Ruby / Bun 整页（侧边栏入口；页面代码保留） */
  static readonly RUBY_BUN: boolean = false;
}
