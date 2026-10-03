#!/usr/bin/env bash
# 自检跑法包一层：引擎自己打的 SCRIPT ERROR / at: 栈不算进任何 check()，
# 所以"GDScript 报了一路错、测试却 ALL PASS"是可能发生的——实测发生过一次
# （records.gd 里 items 类型不对，_draw_order_panel 每帧抛错 45 次，autotest 报 0 fail）。
# 这个包装把日志里的错误数当成退出码的一部分。
#
# 用法: tools/verify.sh smoke|border|autotest|soak|chapter|artcheck|music|envcheck|probe
#       tools/verify.sh --pkg smoke      # 跑导出包里的自检
set -u
cd "$(dirname "$0")/.." || exit 3

GODOT="E:/godot/Godot_v4.7.2-stable_win64_console.exe"
PKG="builds/windows/ChaihuoFastFood.console.exe"

MODE="${1:-smoke}"
PKG_RUN=0
if [ "$MODE" = "--pkg" ]; then PKG_RUN=1; MODE="${2:-smoke}"; fi

# autotest/border/soak 会读 viewport 纹理截图，无头下取不到帧，必须带窗口跑
case "$MODE" in
	artcheck|smoke|chapter|music|envcheck|probe|persist_write|persist_read) HEADLESS="--headless" ;;
	*) HEADLESS="" ;;
esac

LOG="tools/_scratch/verify_${MODE}.log"
mkdir -p tools/_scratch

# 开机前先看一眼"被 exclude_filter 排除的目录里有没有 .gd"。
# 这类文件不会进包，但 Godot 的 class_name 是全局注册的——一份 tools/_scratch/bak_daysim.gd
# 就能把 DaySim 抢注过去，于是包里没有那个文件、游戏一开机就 Parse Error 打不开，
# 而源码树里跑测试全绿（两份都在，看不出被抢注）。这个检查必须在 Godot 之外做：
# 真出事时测试脚本自己也编译不过，写在测试里的闸根本不会执行。
STRAY=$(find tools screenshots saves legacy_web_v1 -name "*.gd" -type f 2>/dev/null)
if [ -n "$STRAY" ]; then
	echo "PREFLIGHT FAIL: 排除目录里有 .gd，它不会进包却可能抢注全局类名："
	echo "$STRAY"
	echo "把它挪出项目（不是删）后重跑 --import。"
	exit 4
fi

if [ "$PKG_RUN" = "1" ]; then
	(cd builds/windows && "./ChaihuoFastFood.console.exe" -- --test="$MODE") > "$LOG" 2>&1
else
	"$GODOT" $HEADLESS --path "$(pwd)" -- --test="$MODE" > "$LOG" 2>&1
fi
RC=$?

ERRS=$(grep -c "SCRIPT ERROR\|ERROR: Function\|Parse Error" "$LOG" 2>/dev/null || true)
ERRS=${ERRS:-0}
VERDICT=$(grep -oE "ALL PASS|: FAIL|: PASS|checks=[0-9]+ passed=[0-9]+ failed=[0-9]+|shots=[0-9]+ fails=[0-9]+|ARTCHECK OK scripts=[0-9]+" "$LOG" | tail -3 | tr '\n' ' ')

echo "mode=$MODE pkg=$PKG_RUN exit=$RC log_errors=$ERRS"
echo "verdict: $VERDICT"
if [ "$ERRS" != "0" ]; then
	grep -n "SCRIPT ERROR\|Parse Error" -A 1 "$LOG" | head -12
fi
if [ "$RC" -ne 0 ] || [ "$ERRS" != "0" ]; then
	echo "VERIFY FAIL ($MODE)"
	exit 1
fi
echo "VERIFY OK ($MODE)"
