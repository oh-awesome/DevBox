/**
 * Go 管理（RuntimeMgr 公共件 + GOPROXY 真实功能）
 * 运行时管理走 LangRuntimePage；GOPROXY 走 @BuilderParam ecoContent
 */
import { LangRuntimePage, LangRuntimeConfig, DevChip, DevBtn, DevKVRow } from '../common/component';
import { DevTheme } from '../common/DevTheme';
import { DevTask } from '../utils/DevTask';
import { FeatureScope } from '../utils/FeatureScope';




const HOME = '/storage/Users/currentUser';

interface ProxyPreset {
  name: string;
  url: string;
  note: string;
}

function goCfg(): LangRuntimeConfig {
  return {
    langKey: 'go',
    title: 'Go',
    subtitle: 'Go · 运行时版本管理',
    sourceLabel: 'OHPCD 制品仓',
    sourcePending: false,
    installed: [],
    available: [],
    tabLabels: FeatureScope.ECO_TABS ? ['运行时', '包与工具', '项目', '设置'] : ['运行时'],   // 商用范围开关（utils/FeatureScope.ets）
    ecoTabs: [
      { label: 'GOPROXY', hint: '模块代理加速' },
      { label: '常用工具', hint: 'go fmt / vet / mod（随工具链提供）' },
    ],
  };
}

@Component
export struct GoManager {
  @State goproxy: string = '';
  @State activeProxyName: string = '';

  private proxies(): ProxyPreset[] {
    return [
      { name: '七牛 goproxy.cn', url: 'https://goproxy.cn,direct', note: '国内推荐 · 七牛云' },
      { name: 'goproxy.io', url: 'https://goproxy.io,direct', note: '国内备选' },
      { name: '官方（默认）', url: 'https://proxy.golang.org,direct', note: '官方源' },
    ];
  }

  aboutToAppear(): void {
    this.refresh();
  }

  private refresh(): void {
    // 审计 C-P0-2：此前 onLine 回调为空——goproxy 永远空串，页面恒显"默认"。
    // 收集输出，完成后赋值+匹配
    const out: string[] = [];
    DevTask.shell(`go env GOPROXY 2>/dev/null`,
      (t: string, _e: boolean) => { if (t.trim() !== '') { out.push(t.trim()); } },
      (_ok: boolean, _d: string) => {
        this.goproxy = out.join('\n').trim();
        this.activeProxyName = this.matchName(this.goproxy);
      });
  }

  private matchName(url: string): string {
    if (url.indexOf('goproxy.cn') >= 0) { return '七牛 goproxy.cn'; }
    if (url.indexOf('goproxy.io') >= 0) { return 'goproxy.io'; }
    if (url.indexOf('proxy.golang.org') >= 0) { return '官方（默认）'; }
    return '';
  }

  private apply(url: string): void {
    DevTask.shell(`go env -w GOPROXY=${url}`, (_t, _e) => {}, (_ok, _d) => {});
    this.refresh();
  }

  @Builder
  goproxyContent() {
    Column({ space: 12 }) {
      DevKVRow({ k: '当前 GOPROXY', v: this.activeProxyName !== '' ? this.activeProxyName : (this.goproxy !== '' ? this.goproxy : '默认'), copyable: true, mono: true })
      DevKVRow({ k: 'GOPATH', v: `${HOME}/go`, copyable: false, mono: false })

      ForEach(this.proxies(), (p: ProxyPreset) => {
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Row({ space: 6 }) {
              Text(p.name)
                .fontSize(DevTheme.FS_BODY)
                .fontWeight(this.activeProxyName === p.name ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(DevTheme.TEXT_PRIMARY)
              if (this.activeProxyName === p.name) {
                DevChip({ text: '当前', tone: 'primary', mono: false })
              }
            }
            Text(p.note)
              .fontSize(DevTheme.FS_CAPTION)
              .fontColor(DevTheme.TEXT_TERTIARY)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          DevBtn({
            text: this.activeProxyName === p.name ? '已启用' : '启用',
            buttonSize: 'mini',
            plain: this.activeProxyName === p.name,
            onTap: () => {
              this.apply(p.url);
            },
          })
        }
        .width('100%')
        .padding({ top: 6, bottom: 6 })
      }, (p: ProxyPreset) => p.name)

      Text($r('app.string.go_manager_1'))
        .fontSize(DevTheme.FS_CAPTION)
        .fontColor(DevTheme.TEXT_TERTIARY)
    }
    .width('100%')
  }

  build() {
    LangRuntimePage({
      cfg: goCfg(),
      ecoContent: (): void => {
        this.goproxyContent();
      },
    })
  }
}
