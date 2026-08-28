import Quartz

# 論理解像度（スケーリング後の解像度）を取得
main_display = Quartz.CGMainDisplayID()
bounds = Quartz.CGDisplayBounds(main_display)
screen_width = int(bounds.size.width)

# 画面横幅を出力
print(screen_width - 180)