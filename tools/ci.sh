#!/usr/bin/env bash
# 本地全量闸门 —— 和 .github/workflows/ci.yml 跑的是同一套检查，放在本地是为了
# 提交前不用等 CI 就能发现问题（CI 反馈慢，且容器里重现问题更折腾）。
#
# 设计要点：把"引擎级错误"和"测试自报的错误"分开看。
#   Godot 里 SCRIPT ERROR / Parse Error 不会计入任何 check()，于是出现过
#   "GDScript 一路报错、测试却 checks=331 failed=0 ALL PASS"的情况。
# 所以本脚本既看 checks= 也 grep 日志里的引擎报错，任一命中即判 FAIL。
#
# 用法:
#   tools/ci.sh             # 跑纯逻辑套件（无头，快）
#   tools/ci.sh --full      # 再加 xvfb 才跑得动的取帧/计时套件
#   tools/ci.sh --export    # 额外验证导出 preset 可用
set -u
cd "$(dirname "$0")/.." || exit 3

GODOT="${GODOT:-E:/Godot/Godot_v4.7.2-stable_win64_console.exe}"
[ -x "$GODOT" ] || { echo "找不到 Godot：$GODOT（可用 GODOT=... 覆盖）"; exit 3; }

FULL=0
DO_EXPORT=0
for a in "$@"; do
	case "$a" in
		--full)   FULL=1 ;;
		--export) DO_EXPORT=1 ;;
	esac
done

mkdir -p tools/_scratch
FAIL=0

# —— 预检：排除目录里不得有 .gd（它们不进包却会全局注册 class_name）——
stray=$(find tools screenshots saves legacy_web_v1 -name "*.gd" -type f 2>/dev/null || true)
if [ -n "$stray" ]; then
	echo "PREFLIGHT FAIL: 排除目录里有 .gd，可能抢注全局类名："
	echo "$stray"
	exit 4
fi

# —— 编译闸：在项目上下文里启动一次（autoload 能解析），真 Parse Error 才会现形 ——
# 不用 --check-only --script：那个模式不加载 autoload，Config/GameState/Sfx 全被判成
# "Identifier not found"，干净仓库也误报。也不用 --import：它只重导资产、不重编译 GDScript，
# 注入真错也查不出。用最短的 envcheck 模式当探针。
echo "================ 编译闸 (envcheck) ================"
"$GODOT" --headless --path "$(pwd)" -- --test=envcheck > tools/_scratch/ci_compile.log 2>&1
if grep -qE "SCRIPT ERROR|Parse Error" tools/_scratch/ci_compile.log; then
	echo "  编译闸未过："
	grep -n "SCRIPT ERROR\|Parse Error" -A1 tools/_scratch/ci_compile.log | head -20
	FAIL=1
else
	echo "  全项目脚本无 Parse Error"
fi

run_mode() {
	local mode="$1" headless="$2"
	local log="tools/_scratch/ci_${mode}.log"
	echo "================ $mode ================"
	# shellcheck disable=SC2086
	"$GODOT" $headless --path "$(pwd)" -- --test="$mode" > "$log" 2>&1
	local rc=$?
	tail -6 "$log"
	if [ "$rc" -ne 0 ]; then echo "  ↳ exit=$rc"; FAIL=1; fi
	if grep -qE "SCRIPT ERROR|Parse Error" "$log"; then
		echo "  ↳ 引擎级脚本错误："
		grep -n "SCRIPT ERROR\|Parse Error" -A1 "$log" | head -12
		FAIL=1
	fi
	if ! grep -qE "ALL PASS|: PASS|shots=[0-9]+ fails=0|ALL DONE|DONE" "$log"; then
		echo "  ↳ 未匹配到通过标记"
		FAIL=1
	fi
}

# 纯逻辑套件（无头）
for m in smoke border chapter trace; do
	run_mode "$m" "--headless"
done

if [ "$FULL" = "1" ]; then
	# 需要真实窗口取帧/计时
	if command -v xvfb-run >/dev/null 2>&1; then
		for m in soak perf artcheck music envcheck; do
			local_log="tools/_scratch/ci_${m}.log"
			echo "================ $m (xvfb) ================"
			xvfb-run -a -s "-screen 0 1280x720x24" \
				"$GODOT" --path "$(pwd)" -- --test="$m" > "$local_log" 2>&1
			tail -6 "$local_log"
			grep -qE "SCRIPT ERROR|Parse Error" "$local_log" && { FAIL=1; echo "  ↳ 引擎级错误"; }
			grep -qE "ALL PASS|: PASS|ALL DONE|ARTCHECK OK" "$local_log" || { FAIL=1; echo "  ↳ 未通过"; }
		done
	else
		echo "（跳过取帧套件：本机没有 xvfb-run；Windows 上直接用带窗口的 verify.sh）"
	fi
fi

if [ "$DO_EXPORT" = "1" ]; then
	echo "================ export preset 可用性 ================"
	preset=$(grep -m1 '^name=' export_presets.cfg | cut -d'"' -f2)
	mkdir -p tools/_scratch/export
	if "$GODOT" --headless --path "$(pwd)" --export-release "$preset" \
		"tools/_scratch/export/out.exe" > tools/_scratch/ci_export.log 2>&1; then
		echo "  导出成功：$preset"
	else
		echo "  导出失败（多为缺导出模板），见 tools/_scratch/ci_export.log"
		tail -15 tools/_scratch/ci_export.log
		FAIL=1
	fi
fi

echo
if [ "$FAIL" -ne 0 ]; then echo "CI GATE: FAIL"; exit 1; fi
echo "CI GATE: OK"
