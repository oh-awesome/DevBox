/**
 * 关于页 — 严格按老代码 AboutDialog 布局（已上架验证通过的合规内容）
 * 结构：图标+名称+版本 → 应用介绍 → 开发者信息 → 隐私声明(链接) → 开源声明(链接弹窗)
 */
import {
  DevBtn, DevCard, DevStatusDot,
} from '../common/component';
import { DevTheme } from '../common/DevTheme';
import { DevGateService } from '../utils/DevGateService';
import { common, Want } from '@kit.AbilityKit';

const PRIVACY_URL: string = 'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2086950162705470720';
const REPO_URL: string = 'https://gitcode.com/OpenHarmonyPCDeveloper/DevBox';

@Component
export struct AboutPage {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @State showVersionInfo: boolean = false;
  @State showDescriptionDetails: boolean = false;
  @State ossDialogOpen: boolean = false;
  @State ossLicenseExpanded: string = '';

  private openUrl(url: string): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.startAbility({
        action: 'ohos.want.action.viewData',
        uri: url,
      } as Want);
    } catch (_) {
    }
  }

  @Builder
  infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(DevTheme.FS_H2)
        .fontColor(DevTheme.TEXT_TERTIARY)
      Blank()
      Text(value)
        .fontSize(DevTheme.FS_H2)
        .fontColor(DevTheme.TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 24 })
    }
    .width('100%')
    .height(36)
  }

  @Builder
  linkRow(label: string, url: string, alias: string) {
    Row() {
      Text(label)
        .fontSize(DevTheme.FS_H2)
        .fontColor(DevTheme.TEXT_TERTIARY)
      Blank()
      Text(alias !== '' ? alias : url)
        .fontSize(DevTheme.FS_H2)
        .fontColor(DevTheme.INFO)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 24 })
    }
    .width('100%')
    .height(36)
    .onClick(() => { this.openUrl(url); })
  }

  @Builder
  privacyLink() {
    Row() {
      Text($r('app.string.about_1'))
        .fontSize(DevTheme.FS_H2)
        .fontColor(DevTheme.INFO)
        .layoutWeight(1)
      Text($r('app.string.about_2'))
        .fontSize(DevTheme.FS_H3)
        .fontColor(DevTheme.TEXT_TERTIARY)
    }
    .width('100%')
    .height(40)
    .onClick(() => { this.openUrl(PRIVACY_URL); })
  }

  @Builder
  openSourceLink() {
    Row() {
      Text($r('app.string.about_3'))
        .fontSize(DevTheme.FS_H2)
        .fontColor(DevTheme.INFO)
        .layoutWeight(1)
      Text($r('app.string.about_2'))
        .fontSize(DevTheme.FS_H3)
        .fontColor(DevTheme.TEXT_TERTIARY)
    }
    .width('100%')
    .height(40)
    .onClick(() => { this.ossDialogOpen = true; })
  }

  
  /** 协议原文折叠区（点击标题行展开/收起） */
  @Builder
  ossLicenseSection(key: string, title: string) {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Text(this.ossLicenseExpanded === key ? '▾' : '▸')
          .fontSize(DevTheme.FS_H2)
          .fontColor(DevTheme.TEXT_TERTIARY)
          .width(20)
        Text(title)
          .fontSize(DevTheme.FS_H3)
          .fontColor(DevTheme.TEXT_PRIMARY)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .borderRadius(DevTheme.RADIUS_MD)
      .backgroundColor(DevTheme.BG_SUBTLE)
      .onClick(() => {
        this.ossLicenseExpanded = this.ossLicenseExpanded === key ? '' : key;
      })

      if (this.ossLicenseExpanded === key) {
        Scroll() {
          Text(this.ossLicenseText(key))
            .fontSize(DevTheme.FS_CAPTION)
            .fontColor(DevTheme.TEXT_MUTED)
            .fontFamily(DevTheme.MONO_FONT)
            .lineHeight(18)
            .padding(12)
        }
        .constraintSize({ maxHeight: 240 })
        .width('100%')
        .margin({ top: 6 })
        .borderRadius(DevTheme.RADIUS_MD)
        .backgroundColor(DevTheme.BG_SUBTLE)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
  }

  /** 协议原文文本（摘要 + 全文链接） */
  private ossLicenseText(key: string): string {
    if (key === 'mulan') {
      return '木兰宽松许可证，第2版\n2020年1月 http://license.coscl.org.cn/MulanPSL2\n\n一、定义\n\n贡献者：通过许可协议将源代码提交给本软件的个人或法人。\n您：利用本软件的个人或法人。\n\n二、授权\n\n授予您永久性、全球性、免版税、非独占、不可撤销的知识产权许可。分发时必须保留本许可证完整文本。\n\n三、免责声明\n\n本许可证以"按原样"基础提供，不附带任何担保。\n\n全文见 http://license.coscl.org.cn/MulanPSL2';
    }
    if (key === 'mit') {
      // 逐字保留上游 LICENSE（oh_modules/@ibestservices/ibest-ui-v2/LICENSE）——MIT 要求版权与许可声明原文保留
      return 'MIT License\n\nCopyright (c) 2024 ibestservices\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.';
    }
    return '0BSD\n\nCopyright (c) Lasse Collin\n\nPermission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted.\n\nTHE SOFTWARE IS PROVIDED "AS IS".\n\nhttps://opensource.org/licenses/0BSD';
  }

  /** 第三方组件声明行（名称 / 许可证 / 版权 / 协议链接） */
  @Builder
  ossComponent(name: string, license: string, copyright: string, licenseUrl: string) {
    Column({ space: 2 }) {
      Row({ space: 8 }) {
        Text(name)
          .fontSize(DevTheme.FS_H3)
          .fontColor(DevTheme.TEXT_PRIMARY)
        Text(license)
          .fontSize(DevTheme.FS_CAPTION)
          .fontColor(DevTheme.INFO)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor(DevTheme.BG_ACCENT_INFO)
      }
      .width('100%')

      Text(copyright)
        .fontSize(DevTheme.FS_CAPTION)
        .fontColor(DevTheme.TEXT_MUTED)
        .width('100%')

      Text(licenseUrl)
        .fontSize(DevTheme.FS_CAPTION)
        .fontColor(DevTheme.INFO)
        .width('100%')
        .onClick(() => { this.openUrl(licenseUrl); })
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  build() {
    Stack() {
    Scroll() {
      Column({ space: 8 }) {
        // ── 图标 + 名称 + 版本 ──
        Column({ space: 12 }) {
          Image($r('app.media.AppIcon'))
            .width(64).height(64)
            .borderRadius(14)
            .objectFit(ImageFit.Cover)

          Text('DevBox')
            .fontSize(DevTheme.FS_H1)
            .fontWeight(FontWeight.Bold)
            .fontColor(DevTheme.TEXT_PRIMARY)

          Column({ space: 4 }) {
            Row() {
              Text($r('app.string.about_4'))
                .fontSize(DevTheme.FS_H2).fontColor(DevTheme.TEXT_TERTIARY)
              Text('2.0.0')
                .fontSize(DevTheme.FS_H2).fontColor(DevTheme.TEXT_TERTIARY)
            }
            if (this.showVersionInfo) {
              Text($r('app.string.about_5'))
                .fontSize(DevTheme.FS_H3).fontColor(DevTheme.TEXT_MUTED)
            }
          }
          .onClick(() => { this.showVersionInfo = !this.showVersionInfo; })
        }
        .width('100%')
        .padding({ top: 30, bottom: 24, left: 16, right: 16 })
        .borderRadius(DevTheme.RADIUS_LG)
        .backgroundColor(DevTheme.BG_CARD)
        .border({ width: 1, color: DevTheme.BORDER })

        // ── 应用介绍 ──
        Column({ space: 12 }) {
          Text($r('app.string.about_6'))
            .fontSize(DevTheme.FS_H1).fontWeight(FontWeight.Medium).fontColor(DevTheme.TEXT_PRIMARY).width('100%')
          Column({ space: 6 }) {
            Text($r('app.string.about_7'))
              .fontSize(DevTheme.FS_H2).fontColor(DevTheme.TEXT_SECONDARY).lineHeight(20).width('100%')
            if (this.showDescriptionDetails) {
              Text($r('app.string.about_8'))
                .fontSize(DevTheme.FS_H3).fontColor(DevTheme.TEXT_MUTED).lineHeight(18).width('100%')
            }
          }.width('100%')
          .onClick(() => { this.showDescriptionDetails = !this.showDescriptionDetails; })
        }
        .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .borderRadius(DevTheme.RADIUS_LG).backgroundColor(DevTheme.BG_CARD)
        .border({ width: 1, color: DevTheme.BORDER })

        // ── 环境准备指南（开发工具依赖的两项系统设置——详细教程） ──
        DevCard({ title: '环境准备指南', subtitle: '开发工具安装与使用前的系统设置说明', accent: '', pad: 16 }) {
          Column({ space: 16 }) {
            // ── 教程 1：开发者模式 ──
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                DevStatusDot({ status: 1 })
                Text($r('app.string.about_9'))
                  .fontSize(DevTheme.FS_H2)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(DevTheme.TEXT_PRIMARY)
                  .layoutWeight(1)
                DevBtn({
                  text: '打开设置',
                  buttonSize: 'small',
                  plain: true,
                  onTap: () => {
                    const ctx = getContext(this) as common.UIAbilityContext;
                    DevGateService.openDeveloperModeSettings(ctx);
                  },
                })
              }
              .width('100%')

              Column({ space: 4 }) {
                Text($r('app.string.about_10'))
                  .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_SECONDARY).width('100%')
                Text($r('app.string.about_11'))
                  .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_SECONDARY).width('100%')
                Text($r('app.string.about_12'))
                  .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_SECONDARY).width('100%')
                Text($r('app.string.about_13'))
                  .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_SECONDARY).width('100%')
                Text($r('app.string.about_14'))
                  .fontSize(DevTheme.FS_CAPTION)
                  .fontColor(DevTheme.TEXT_MUTED)
                  .width('100%')
                  .margin({ top: 4 })
              }
              .width('100%')
              .padding({ left: 20 })
            }
            .width('100%')

            Divider().color(DevTheme.BORDER)

            // ── 教程 2：运行非应用市场扩展程序 ──
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                DevStatusDot({ status: 1 })
                Text($r('app.string.about_15'))
                  .fontSize(DevTheme.FS_H2)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(DevTheme.TEXT_PRIMARY)
                  .layoutWeight(1)
                DevBtn({
                  text: '打开设置',
                  buttonSize: 'small',
                  plain: true,
                  onTap: () => {
                    const ctx = getContext(this) as common.UIAbilityContext;
                    DevGateService.openLocalPluginSettings(ctx);
                  },
                })
              }
              .width('100%')

              Column({ space: 4 }) {
                Text($r('app.string.about_16'))
                  .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_SECONDARY).width('100%')
                Text($r('app.string.about_17'))
                  .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_SECONDARY).width('100%')
                Text($r('app.string.about_18'))
                  .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_SECONDARY).width('100%')
                Text($r('app.string.about_19'))
                  .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_SECONDARY).width('100%')

                Row({ space: 8 }) {
                  Text('⚠')
                    .fontSize(DevTheme.FS_H2)
                    .fontColor(DevTheme.WARNING)
                  Text($r('app.string.about_20'))
                    .fontSize(DevTheme.FS_CAPTION)
                    .fontColor(DevTheme.TEXT_SECONDARY)
                    .lineHeight(16)
                    .layoutWeight(1)
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .borderRadius(DevTheme.RADIUS_MD)
                .backgroundColor(DevTheme.BG_ACCENT_WARNING)
              }
              .width('100%')
              .padding({ left: 20 })

              Divider().color(DevTheme.BORDER)

              // ── 教程 3：环境变量生效说明 ──
              Column({ space: 6 }) {
                Row({ space: 8 }) {
                  DevStatusDot({ status: 1 })
                  Text($r('app.string.about_21'))
                    .fontSize(DevTheme.FS_H2)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(DevTheme.TEXT_PRIMARY)
                }
                .width('100%')

                Column({ space: 4 }) {
                  Text($r('app.string.about_22'))
                    .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_SECONDARY).width('100%')
                  Text($r('app.string.about_23'))
                    .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_SECONDARY).width('100%')
                  Text($r('app.string.about_24'))
                    .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED).width('100%')
                  Text($r('app.string.about_25'))
                    .fontSize(DevTheme.FS_CAPTION).fontColor(DevTheme.TEXT_MUTED).width('100%')
                }
                .width('100%')
                .padding({ left: 20 })
              }
              .width('100%')
              .margin({ top: 4 })

              Divider().color(DevTheme.BORDER)

              // ── 风险提示 ──
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        // ── 开发者信息 ──
        Column({ space: 12 }) {
          Text($r('app.string.about_26'))
            .fontSize(DevTheme.FS_H1).fontWeight(FontWeight.Medium).fontColor(DevTheme.TEXT_PRIMARY).width('100%')
          this.infoRow('开发者', 'OpenHarmony PC Developer Community')
          this.linkRow('官网', REPO_URL, 'OpenHarmonyPCDeveloper/DevBox')
        }
        .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .borderRadius(DevTheme.RADIUS_LG).backgroundColor(DevTheme.BG_CARD)
        .border({ width: 1, color: DevTheme.BORDER })

        // ── 隐私 + 开源（同一卡片） ──
        Column({ space: 0 }) {
          this.privacyLink()
          Divider().color(DevTheme.BORDER)
          this.openSourceLink()
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .borderRadius(DevTheme.RADIUS_LG)
        .backgroundColor(DevTheme.BG_CARD)
        .border({ width: 1, color: DevTheme.BORDER })

        // ── 底部版权 ──
        Column({ space: 4 }) {
          Text('Copyright 2025-2026 OpenHarmony PC Developer')
            .fontSize(DevTheme.FS_H3)
            .fontColor(DevTheme.TEXT_MUTED)
          Text('All rights reserved')
            .fontSize(DevTheme.FS_CAPTION)
            .fontColor(DevTheme.TEXT_MUTED)
        }
        .width('100%')
        .padding({ top: 16, bottom: 24 })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8 })
    }
    .align(Alignment.TopStart)
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)

    // 开源声明弹窗（全屏遮罩 + 居中面板，MCP 窗口模式）
    if (this.ossDialogOpen) {
      Stack() {
        Column()
          .width('100%').height('100%')
          .backgroundColor(DevTheme.BG_OVERLAY)
          .onClick(() => { this.ossDialogOpen = false; })

        Column({ space: 0 }) {
          Row({ space: 12 }) {
            Text($r('app.string.about_27'))
              .fontSize(DevTheme.FS_H1).fontWeight(FontWeight.Bold)
              .fontColor(DevTheme.TEXT_PRIMARY).layoutWeight(1)
            Text('✕')
              .fontSize(DevTheme.FS_H1).fontColor(DevTheme.TEXT_TERTIARY)
              .width(32).height(32).textAlign(TextAlign.Center)
              .borderRadius(8).hoverEffect(HoverEffect.Scale)
              .onClick(() => { this.ossDialogOpen = false; })
          }
          .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 12 })
          Divider().color(DevTheme.BORDER)
          Scroll() {
            Column({ space: 16 }) {
              Column({ space: 6 }) {
                Text($r('app.string.about_28'))
                  .fontSize(DevTheme.FS_H2)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(DevTheme.TEXT_PRIMARY)
                  .width('100%')

                Text('Copyright (c) 2026 OpenHarmony PC Developer Community')
                  .fontSize(DevTheme.FS_H2)
                  .fontColor(DevTheme.TEXT_SECONDARY)
                  .fontFamily(DevTheme.MONO_FONT)
                  .width('100%')

                Text($r('app.string.about_29'))
                  .fontSize(DevTheme.FS_H2)
                  .fontColor(DevTheme.TEXT_SECONDARY)
                  .lineHeight(20)
                  .width('100%')

                Text($r('app.string.about_30'))
                  .fontSize(DevTheme.FS_H2)
                  .fontColor(DevTheme.INFO)
                  .width('100%')
                  .onClick(() => { this.openUrl('http://license.coscl.org.cn/MulanPSL2'); })

                Text('源代码：' + REPO_URL)
                  .fontSize(DevTheme.FS_H2)
                  .fontColor(DevTheme.INFO)
                  .width('100%')
                  .onClick(() => { this.openUrl(REPO_URL); })
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .borderRadius(DevTheme.RADIUS_MD)
              .backgroundColor(DevTheme.BG_SUBTLE)
              .alignItems(HorizontalAlign.Start)

              Column({ space: 8 }) {
                Text($r('app.string.about_31'))
                  .fontSize(DevTheme.FS_H2)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(DevTheme.TEXT_PRIMARY)
                  .width('100%')

                this.ossComponent('IBest-UI-V2', 'MIT License',
                  'Copyright (c) 2024 ibestservices',
                  'https://opensource.org/licenses/MIT')
                this.ossComponent('liblzma (xz)', '0BSD / 公共领域',
                  'Copyright (c) Lasse Collin 和贡献者',
                  'https://opensource.org/licenses/0BSD')
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .borderRadius(DevTheme.RADIUS_MD)
              .backgroundColor(DevTheme.BG_SUBTLE)
              .alignItems(HorizontalAlign.Start)

              Text($r('app.string.about_32'))
                .fontSize(DevTheme.FS_H2)
                .fontWeight(FontWeight.Medium)
                .fontColor(DevTheme.TEXT_PRIMARY)
                .width('100%')

              Text($r('app.string.about_33'))
                .fontSize(DevTheme.FS_H2)
                .fontColor(DevTheme.TEXT_SECONDARY)
                .lineHeight(20)
                .width('100%')

              Text($r('app.string.about_34'))
                .fontSize(DevTheme.FS_H2)
                .fontWeight(FontWeight.Medium)
                .fontColor(DevTheme.TEXT_PRIMARY)
                .width('100%')

              Text($r('app.string.about_35'))
                .fontSize(DevTheme.FS_H2)
                .fontColor(DevTheme.TEXT_SECONDARY)
                .lineHeight(20)
                .width('100%')

              Column({ space: 6 }) {
                Text($r('app.string.about_36'))
                  .fontSize(DevTheme.FS_H2)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(DevTheme.TEXT_PRIMARY)
                  .width('100%')

                Text($r('app.string.about_37'))
                  .fontSize(DevTheme.FS_H2)
                  .fontColor(DevTheme.TEXT_SECONDARY)
                  .lineHeight(20)
                  .width('100%')
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .borderRadius(DevTheme.RADIUS_MD)
              .backgroundColor(DevTheme.BG_ACCENT_WARNING)
              .alignItems(HorizontalAlign.Start)

              Text($r('app.string.about_38'))
                .fontSize(DevTheme.FS_H2)
                .fontWeight(FontWeight.Medium)
                .fontColor(DevTheme.TEXT_PRIMARY)
                .width('100%')
                .padding({ top: 4 })

              this.ossLicenseSection('mulan', 'Mulan PSL-2.0')
              this.ossLicenseSection('mit', 'MIT License')
              this.ossLicenseSection('bsd', '0BSD')
              }
            .padding({ left: 16, right: 16, bottom: 20 })
          }
          .align(Alignment.TopStart).layoutWeight(1).scrollBar(BarState.Auto)
        }
        .width(500).height(480)
        .borderRadius(DevTheme.RADIUS_LG)
        .backgroundColor(DevTheme.BG_CARD)
        .border({ width: 1, color: DevTheme.BORDER })
      }
      .width('100%').height('100%')
    }
    }
  }
}
