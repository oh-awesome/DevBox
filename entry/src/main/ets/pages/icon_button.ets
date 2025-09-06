@Component
export struct IconButton {
  @Prop icon?: Resource; // 图标资源
  @Prop textResource: Resource; // 文本内容
  @Prop background_color: ResourceColor;
  @Prop background_hover_color: ResourceColor; // = Color.Gray;
  @Prop userBorderColor?: ResourceColor; // = Color.White;
  @Prop fontSize?: number = 12;
  @Prop fontColor?: ResourceColor = '#999999';
  @Prop disableFontColor?: ResourceColor = '#FF333333';
  @Prop disabled?: boolean; // 是否禁用（默认false）
  public onClickFunc?: () => void; // 点击回调
  @State isPressed: boolean = false;
  @State focus: boolean = false;
  @State inner_background_color: ResourceColor = this.background_color;

  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 4, }) {
        // 图标
        if (this.icon) {
          Image(this.icon)
            .width(this.fontSize)
            .height(this.fontSize)
            .padding({ right: 4 })
        }

        // 文字
        Text(this.textResource || '')
          .fontSize(this.fontSize || 12)
          .fontColor(this.disabled ? this.disableFontColor : this.fontColor)
          .maxLines(1)
          .wordBreak(WordBreak.BREAK_ALL)
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
    .backgroundColor(this.inner_background_color)
    .borderRadius(6)
    .stateStyles({
      focused: {
        .border({
          width: 2,
          radius: 6
        })
      },
      normal: {
        .border({
          width: 0,
          radius: 6
        })
      }
    })
    .onFocus(() => {
      this.focus = true;
    })
    .onBlur(() => {
      this.focus = false;
    })
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
        this.inner_background_color = isHover ? this.background_hover_color : this.background_color;
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

@Component
export struct CommIconButton {
  public onClickFunc?: () => void; // 点击回调
  @Prop textResource: Resource; // 文本内容
  @Prop icon: Resource; // 图标资源

  build() {
    IconButton({
      icon: this.icon,
      fontSize: 16,
      textResource: this.textResource,
      fontColor: $r("app.color.comm_btn_content"),
      userBorderColor: $r("app.color.comm_btn_broader"),
      background_color: $r("app.color.comm_btn_bg"),
      background_hover_color: $r("app.color.comm_btn_hover_bg"),
      onClickFunc: () => {
        if (this.onClickFunc) {
          this.onClickFunc()
        }
      }
    })
      .constraintSize({
        minHeight: 40,
        maxHeight: 80,
      })
      .height(40)
  }
}