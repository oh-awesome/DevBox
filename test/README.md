# DevBox 自动化测试

真机（hdc）视觉 + MCP 真值双通道自动化。无 OCR、无大模型看图——
模板匹配（NCC）做定位、像素 diff 做生效判据、hilog/MCP 做状态真值。

## 目录结构

```
test/
└── ui_automation/
    ├── run_smoke.py      L1 全页面冒烟（13 页导航 + 渲染三断言）
    ├── run_all.py        全量回归编排（L1+L2+L3 汇总报告）
    ├── core/             框架四件套
    │   ├── device.py     hdc 设备控制（截图/点击/keyEvent/冷启 test_mode 锁屏）
    │   ├── vision.py     像素断言（diff/模板匹配/蓝色按钮扫描/文本行带）
    │   ├── dump.py       dumpLayout 首帧解析（重启后可信；含 type 定位/区域查找）
    │   └── mcp.py        MCP JSON-RPC 客户端（fport 18765 真值通道）
    ├── cases/            用例（每个自成一体的 main + 独立报告）
    └── templates/        侧栏/页签模板 PNG + meta.json 坐标
```

## 用例矩阵

| 级别 | 用例 | 覆盖 |
|---|---|---|
| L1 | run_smoke | 13 页导航切换、内容行带、无红块 |
| L2 | case_brew_conan_smoke | brew/conan 安装链路冒烟 |
| L2 | case_brew_sources | brew 三源结构 + 多 tap |
| L2 | case_lang_queue | 语言运行时队列（入队/位次/推进/收尾） |
| L2 | case_tools_queue | 通用工具队列（取消/重入回归线） |
| L3 | case_mcp_security | MCP 注入防护（6 载荷×3 工具）、非法参数、10KB 极限、并发、契约 |
| L3 | case_search_edge | 搜索空/无结果/注入字符/500 字符极限/清空恢复/命中 |
| L3 | case_keyboard_nav | Tab 焦点激活、15×TAB 走焦健壮、Enter、键鼠混用 |
| L3 | case_theme_toggle | 深浅往返、浅色 4 页扫、4 连切压力、dump 完整性 |
| L3 | case_pagination_edge | 分页首末页禁用态、末页跳转、回首页无损 |
| L3 | case_brew_priority | brew PATH 优先开关（块序翻转/往返）、环境页冲突弹窗双分支（保留/调整）、清理归零 |

## 运行

```bash
# 前置：设备已连接（hdc list targets）、DevBox 已装机、MCP 开关已开（托盘进程监听 18765）
python run_smoke.py [workdir]                # L1 冒烟（~2 分钟）
python run_all.py [workdir] --quick          # L1+L3 边缘（~10 分钟，无真实安装）
python run_all.py [workdir]                  # 全量（含 L2 真实安装，~1 小时+）
python cases/case_mcp_security.py            # 单跑（无 UI 依赖，最稳）
```

报告落 `reports/`（过程产物不入库）；截图/ dump 落 workdir `.shots/`。

## 框架铁律（真机实证沉淀）

1. **模板与主题绑定**：NCC 模板对反色失配——浅色截的模板在深色下全量导航假失败
   （2026-11-15 实证：模板=浅色捕获；run_all 启动前自动归一化到浅色）。
2. **dumpLayout 只信首帧**：force-stop 重启后第一次 dump 可信，换页后卡幽灵帧
   ——运行期断言一律走 vision 模板匹配或 dump 换页重取。
3. **窗口失焦点击全无效**（diff=0 判定）：交互前 `restart_app` 夺焦。
4. **test_mode 全屏锁定**：`aa start --ps test_mode true` 窗口 maximize 至全屏 (0,0)，
   dump 坐标=屏幕坐标；老 WIN=(76,76) 裁剪仅用于历史模板兼容。
5. **python subprocess 走 cmd.exe**：`>/dev/null` 与 `MSYS_NO_PATHCONV` 不可用；
   特殊字符载荷用设备端单引号包裹传 literal。
6. **中文输入走 MCP 通道**：cmd.exe→hdc 编码链（GBK→UTF-8）有 mojibake 风险，
   UI 中文断言用 MCP 真值替代。
7. **uitest inputText 是追加语义**（实测回读 520=历史 20+500）：清空须
   Ctrl+A（uinput 组合 2072+2017）+ DEL（keyEvent 2055）。
8. **hilog 断言要容错**：启动日志洪峰会刷穿缓冲——一律配 dump 状态兜底。
9. **模板降采样 2 倍**：4 倍会把 32px 高文本模板压到 8px，NCC 失效。
10. **region clamp 先 min 后切片**：负坐标会被 Python 切片当尾部索引。
11. **46px 图标按钮点中心**：⟳+64 才是主题开关正中心（+46 落左缘不命中）。

## 断言通道选型

| 需要断言什么 | 用什么 |
|---|---|
| 页面切换是否生效 | 前后像素 diff（>3000） |
| 某文字/图标是否存在 | vision.match 模板匹配（th=0.78） |
| 列表是否有内容（非空白） | text_rows 边缘密度行带 |
| 是否弹错误提示 | red_alert 红色块扫描（#F24822 系） |
| 安装/任务真实状态 | MCP 工具调用（真值）或 hilog testTag |
| 搜索框/无文本控件位置 | dump nodes_by_type('TextInput') |
