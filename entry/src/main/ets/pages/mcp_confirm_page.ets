/**
 * mcp_confirm_page —— MCP 敏感操作确认小窗页面（ConfirmAbility 宿主）
 *
 * 布局遵循应用内弹窗规范（DevDialogPanel 同款）：DevBox 图标 + 左对齐标题条
 * （FS_H3 Medium）+ 分隔线 + 左对齐结构化文案 + 底部按钮靠右（DevBtn 取消
 * plain / 确认 danger）。窗口背景透明 + BG_DIALOG 卡片描边阴影，与应用内
 * 弹窗视觉一致（区别于系统弹窗的图标即应用标识）。
 *
 * 决定经 AdminClient(:18766) 回传 TrayAbility 执行/作废后窗口自毁；
 * ESC = 取消；未决销毁由 ConfirmAbility.onDestroy 兜底 reject。
 */
import { common } from '@kit.AbilityKit';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import { DevTheme } from '../common/DevTheme';
import { DevBtn, DevToast } from '../common/component';
import { AdminClient } from '../utils/AdminServer';

interface ConfirmReq {
  op: string;
  title: string;
  body: string;
  detail: string;
  ts: number;
}

interface ConfirmSeg {
  text: string;
  bold: boolean;
}

@Entry
@Component
struct McpConfirmPage {
  @StorageProp('themeMode') themeReact: string = 'dark';
  @StorageProp('mcp_confirm') @Watch('onReqChange') reqRaw: string = '';
  @State op: string = '';
  @State body: string = '';
  @State detail: string = '';
  @State done: string = '';
  @State sending: boolean = false;
  @State segs: ConfirmSeg[] = [];

  aboutToAppear(): void {
    this.parse();
  }

  private onReqChange(): void {
    this.done = '';
    this.sending = false;
    this.parse();
  }

  private parse(): void {
    try {
      const req: ConfirmReq = JSON.parse(this.reqRaw) as ConfirmReq;
      if (req.op !== undefined && req.op !== '') {
        this.op = req.op;
        this.body = req.body ?? '';
        this.detail = req.detail ?? '';
        this.buildSegs(this.body);
      }
    } catch (_) {
    }
  }

  /** 「」标记段解析：标记内=组件名（加粗渲染），标记外=普通文本 */
  private buildSegs(body: string): void {
    const segs: ConfirmSeg[] = [];
    let bold: boolean = false;
    let buf: string = '';
    for (let i = 0; i < body.length; i++) {
      const ch: string = body[i];
      if (ch === '「' || ch === '」') {
        if (buf !== '') { segs.push({ text: buf, bold: bold }); }
        buf = '';
        bold = !bold;
      } else {
        buf += ch;
      }
    }
    if (buf !== '') { segs.push({ text: buf, bold: bold }); }
    this.segs = segs;
  }

  private send(kind: 'approve' | 'reject'): void {
    if (this.op === '' || this.sending) { return; }
    this.sending = true;
    // 已决标记（ConfirmAbility.onDestroy 据此判断是否需要兜底 reject）——
    // 注意失败分支要回滚标记，否则"未决销毁兜底"被跳过、请求悬挂 30 分钟（审计 6-2）
    AppStorage.setOrCreate('mcp_confirm_decided', true);
    AdminClient.postText(`confirm.${kind}:${this.op}`).then((resp: string) => {
      let msg: string = kind === 'approve' ? '已确认，操作执行中' : '已取消该操作';
      if (resp !== '') {
        try {
          const r: Record<string, Object> = JSON.parse(resp) as Record<string, Object>;
          if (r['result'] !== undefined && `${r['result']}`.length > 0) {
            msg = `${r['result']}`.slice(0, 80);
          }
        } catch (_) {
        }
      } else {
        // 回传失败：请求仍在托盘侧等待——恢复未决标记，让 onDestroy 兜底 reject 生效
        AppStorage.setOrCreate('mcp_confirm_decided', false);
        msg = '回传失败（托盘进程不可达）';
      }
      DevToast.show(msg);
      // 反馈停留一拍再关窗（失败场景窗口销毁时兜底 reject 会补发作废）
      setTimeout(() => { this.close(); }, 600);
    });
  }

  private close(): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.terminateSelf();
    } catch (_) {
    }
  }

  build() {
    // BG_DIALOG 卡片铺满窗口（描边+阴影同 DevDialogPanel；窗口透明底，圆角外透桌面）
    Column({ space: 0 }) {
      // ── 标题条：应用图标 + 标题（左对齐——DevDialogPanel 同款，区分系统弹窗） ──
      Row({ space: 9 }) {
        Image($r('app.media.DevBoxLogo'))
          .width(18)
          .height(18)
          .borderRadius(4)
        Text($r('app.string.mcp_confirm_page_1'))
          .fontSize(DevTheme.FS_H3)
          .fontWeight(FontWeight.Medium)
          .fontColor(DevTheme.TEXT_PRIMARY)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 12 })

      Divider().color(DevTheme.BORDER)

      // ── 结构化文案（左对齐；「」标记段渲染为加粗——组件名突出，无书名号字符） ──
      Column({ space: 8 }) {
        if (this.done !== '') {
          Text(this.done)
            .fontSize(DevTheme.FS_BODY)
            .fontColor(DevTheme.TEXT_SECONDARY)
            .lineHeight(20)
            .width('100%')
        } else {
          Text() {
            ForEach(this.segs, (seg: ConfirmSeg) => {
              Span(seg.text)
                .fontWeight(seg.bold ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(seg.bold ? DevTheme.TEXT_PRIMARY : DevTheme.TEXT_PRIMARY)
            }, (seg: ConfirmSeg) => seg.text)
          }
          .fontSize(DevTheme.FS_BODY)
          .lineHeight(20)
          .width('100%')
        }
        // 副行：预览原文/预检详情（英文 err 弱化展示——信息不丢不抢眼）
        if (this.done === '' && this.detail !== '') {
          Text(this.detail)
            .fontSize(DevTheme.FS_CAPTION)
            .fontColor(DevTheme.TEXT_TERTIARY)
            .lineHeight(16)
            .width('100%')
        }
        if (this.done === '') {
          Text($r('app.string.mcp_confirm_page_2'))
            .fontSize(DevTheme.FS_CAPTION)
            .fontColor(DevTheme.TEXT_TERTIARY)
            .width('100%')
        }
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 12, bottom: 8 })

      // ── 按钮行（靠右——应用内对话框规范；DevBtn 即应用按钮样式） ──
      Row({ space: 10 }) {
        Blank()
        DevBtn({
          text: '取消', buttonSize: 'small', plain: true,
          disabled: this.sending,
          onTap: () => { this.send('reject'); },
        })
        DevBtn({
          text: '确认执行', buttonSize: 'small', danger: true,
          disabled: this.sending,
          onTap: () => { this.send('approve'); },
        })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DevTheme.BG_DIALOG)
    .borderRadius(DevTheme.RADIUS_LG)
    .border({ width: 1, color: DevTheme.DIALOG_BORDER })
    .clip(true)
    .onKeyEvent((e: KeyEvent) => {
      if (e.type === KeyType.Down && e.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.send('reject');
      }
    })
  }
}
