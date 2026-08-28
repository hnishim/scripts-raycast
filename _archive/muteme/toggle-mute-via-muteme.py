import Quartz
import subprocess

# 論理解像度（スケーリング後の解像度）を取得
main_display = Quartz.CGMainDisplayID()
bounds = Quartz.CGDisplayBounds(main_display)
screen_width = int(bounds.size.width)
screen_height = int(bounds.size.height)

# クリック位置を計算
click_x = screen_width - 180
click_y = 12

command = ["cliclick", "-r", "dc:"+ str(click_x) + "," + str(click_y)]
subprocess.run(command)