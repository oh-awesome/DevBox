@Component
export struct IconButton {
  public icon?: Resource // 图标资源
  public text?: string // 文本内容
  public textResource?: Resource // 文本内容
  public color?: ResourceColor = Color.White;
  public fontSize?: number = 12;
  public fontColor?: ResourceColor = '#999';
  public disabled?: boolean // 是否禁用（默认false）
  public onClickFunc?: () => void // 点击回调
  public isPressed: boolean = false

  build() {
    Button() {
      Row({ space: 4, }) {
        // 图标
        if (this.icon) {
          Image(this.icon)
            .width(this.fontSize)
            .height(this.fontSize)
        }

        // 文字
        Text(this.text || this.textResource || '')
          .fontSize(this.fontSize || 12)
          .fontColor(this.disabled ? this.fontColor : '#333')
      }
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: 8,
      right: 8,
      top: 8,
      bottom: 8
    })
    .backgroundColor(this.color)
    .borderRadius(6)
    .shadow({
      radius: 8,
      color: '#20000000',
      offsetX: 2,
      offsetY: 2
    })
    .onClick(() => {
      if (!this.disabled && this.onClickFunc) {
        this.onClickFunc()
      }
    })
    .onHover((isHover: boolean, event: HoverEvent) => {
      if (event.sourceTool === SourceTool.MOUSE) {
        this.color = isHover ? Color.Green : Color.White
      }
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isPressed = true
      } else if (event.type === TouchType.Up) {
        this.isPressed = false
      }
    })
    .scale({
      x: this.isPressed ? 0.95 : 1,
      y: this.isPressed ? 0.95 : 1,
    })
    .animation({
      duration: 100,
      curve: Curve.EaseOut
    })
  }
}
