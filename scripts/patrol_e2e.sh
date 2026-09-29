#!/bin/sh
# 跑 patrol 端到端测试(**默认出截图**)。
#
# 用法:
#   sh scripts/patrol_e2e.sh                        # 全部套件,截图开
#   sh scripts/patrol_e2e.sh knowledge memory       # 只跑指定套件(名字可省 _test)
#   sh scripts/patrol_e2e.sh --no-screenshots       # 全部套件,不截图、不拉取
#   sh scripts/patrol_e2e.sh -d emulator-5554       # 指定设备
#   sh scripts/patrol_e2e.sh knowledge --no-screenshots
#
# 截图落在 screenshots/<套件>/<名字>.png(仓库 .gitignore 已忽略该目录)。
# 每个套件的完整输出落在 build/e2e_logs/<套件>.log。
#
# ⚠️ 为什么必须"跑一个拉一个":android/app/build.gradle.kts 里
#    testInstrumentationRunnerArguments["clearPackageData"] = "true" —— **每轮跑之前**
#    清空应用数据,而截图是写在设备上 App 的文档目录里;跑完 App 还会被卸载。
#    所以开截图时会自动带 --no-uninstall,并在每个套件跑完后**立刻** adb 拉取。
#
# 环境变量(可覆盖默认值):
#   PATROL_BIN           patrol 可执行文件(默认自动找:PATH → pub cache bin)
#   E2E_DEVICE           等价于 -d
#   E2E_PACKAGE_NAME     被测 Android 包名(默认从 build.gradle.kts 的 applicationId 读)
#   E2E_SCREENSHOTS_DIR  截图落地目录(默认 screenshots)
#
# 注意:截图拉取走 adb,**只支持 Android**;iOS 模拟器需自行从容器目录取。

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1

SCREENSHOTS_DIR="${E2E_SCREENSHOTS_DIR:-screenshots}"
LOG_DIR="build/e2e_logs"
DEVICE="${E2E_DEVICE:-}"
SHOTS=1
WANTED=""

# 默认套件(顺序固定:先冒烟、再对话、最后真机嵌入;嵌入那个会真下 24.5MB 模型)。
DEFAULT_SUITES="app_smoke_test settings_test conversation_test knowledge_test memory_test context_injection_test embedding_test"

usage() {
  sed -n '2,30p' "$0" | sed 's/^#\{1,\} \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --no-screenshots) SHOTS=0 ;;
    --screenshots) SHOTS=1 ;;
    -d|--device) shift; DEVICE="${1:-}" ;;
    -*) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
    *) WANTED="$WANTED $1" ;;
  esac
  shift
done

# patrol CLI:先 PATH,再 pub cache(Windows 上是 $LOCALAPPDATA/Pub/Cache/bin)。
resolve_patrol() {
  if [ -n "${PATROL_BIN:-}" ]; then echo "$PATROL_BIN"; return; fi
  for c in patrol patrol.bat patrol.exe; do
    if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return; fi
  done
  for d in "${PUB_CACHE:-}" "$HOME/.pub-cache" "$LOCALAPPDATA/Pub/Cache" "$HOME/AppData/Local/Pub/Cache"; do
    [ -n "$d" ] || continue
    for c in patrol patrol.bat; do
      f="$d/bin/$c"
      [ -e "$f" ] || continue
      case "$c" in
        # ⚠️ Windows 的 .bat 没有 POSIX 可执行位,`-x` 在 Git Bash 下恒为假 ——
        # 只看文件在不在(直接执行是可行的)。
        *.bat|*.cmd|*.exe) echo "$f"; return ;;
        *) if [ -x "$f" ]; then echo "$f"; return; fi ;;
      esac
    done
  done
}

PATROL=$(resolve_patrol)
if [ -z "$PATROL" ]; then
  echo "找不到 patrol CLI。先装:dart pub global activate patrol_cli" >&2
  exit 1
fi

# 设备:没给 -d 就必须自己定一个。**不能让 patrol 去问** —— 多设备时它会交互式
# 提示选哪个,而脚本里 stdin 不是终端 ⇒ 直接 "Device selection was cancelled" 失败。
detect_device() {
  command -v adb >/dev/null 2>&1 || return 0
  adb devices | tr -d '\r' | awk 'NR > 1 && $2 == "device" { print $1 }'
}

if [ -z "$DEVICE" ]; then
  DEVICES=$(detect_device)
  N=$(printf '%s\n' "$DEVICES" | grep -c .)
  if [ "$N" -eq 0 ]; then
    echo "没找到已连接的 Android 设备(adb devices 为空)。" >&2
    exit 1
  fi
  DEVICE=$(printf '%s\n' "$DEVICES" | head -1)
  if [ "$N" -gt 1 ]; then
    echo "注意:找到 $N 个 Android 设备,默认用第一个($DEVICE);可用 -d 指定。"
  fi
fi

# 被测包名(拉截图要用)。默认从 gradle 读,避免和 applicationId 漂移。
# ⚠️ 只认**赋值行**(`applicationId = "..."`):build.gradle.kts 里还有一行提到
# applicationId 的**注释**,宽松匹配会把它整行当成包名,然后 run-as 一路失败、
# 表现成"跑了但 0 张截图"。
if [ -z "${E2E_PACKAGE_NAME:-}" ]; then
  E2E_PACKAGE_NAME=$(grep -m1 '^[[:space:]]*applicationId[[:space:]]*=' android/app/build.gradle.kts 2>/dev/null |
    sed 's/.*"\([^"]*\)".*/\1/')
fi
case "$E2E_PACKAGE_NAME" in
  ''|*[!A-Za-z0-9._]*)
    echo "警告:包名解析结果不像包名:「$E2E_PACKAGE_NAME」—— 截图将拉不到,请用 E2E_PACKAGE_NAME 指定" >&2
    ;;
esac

# 去掉 ANSI 颜色,便于抓 summary 行。
strip_ansi() {
  sed "s/$(printf '\033')\[[0-9;]*[A-Za-z]//g" "$1"
}

# 套件名归一化:app_smoke / app_smoke_test / patrol_test/app_smoke_test.dart 都接受。
normalize_suite() {
  s=$(basename "$1")
  s=${s%.dart}
  case "$s" in
    *_test) ;;
    *) s="${s}_test" ;;
  esac
  echo "$s"
}

# 从设备上把该套件的截图拉下来。跑完必须**立刻**调用(见文件头说明)。
pull_screenshots() {
  suite=$1
  [ "$SHOTS" = "1" ] || return 0
  if ! command -v adb >/dev/null 2>&1; then
    echo "    (未找到 adb,跳过拉取)"
    return 0
  fi

  # 合并 stderr,好把两类"没有图"区分开:包名/权限出错 vs 该套件本来就不截图
  # (如 embedding_test 直接调引擎,没有 UI 步骤,自然没有图)。
  RAW=$(adb -s "$DEVICE" shell run-as "$E2E_PACKAGE_NAME" ls app_flutter/screenshots 2>&1 | tr -d '\r')
  case "$RAW" in
    *"unknown package"*|*"not debuggable"*|*"Permission denied"*)
      echo "    ⚠️ 拉不到截图:run-as $E2E_PACKAGE_NAME 失败(包名不对?用 E2E_PACKAGE_NAME 指定)" >&2
      return 0
      ;;
    ""|*"No such file"*)
      echo "    (该套件无截图)"
      return 0
      ;;
  esac
  LIST="$RAW"

  dest="$SCREENSHOTS_DIR/$suite"
  rm -rf "$dest"
  mkdir -p "$dest"

  n=0
  for f in $LIST; do
    case "$f" in
      *.png) ;;
      *) continue ;;
    esac
    adb -s "$DEVICE" exec-out run-as "$E2E_PACKAGE_NAME" cat "app_flutter/screenshots/$f" >"$dest/$f" 2>/dev/null
    # 空文件当成没拉到(exec-out 失败时会留下 0 字节)。
    if [ -s "$dest/$f" ]; then
      n=$((n + 1))
    else
      rm -f "$dest/$f"
    fi
  done
  SCREENSHOT_COUNT=$n
}

SUITES="${WANTED:-$DEFAULT_SUITES}"

# 结果行里的截图小结(关截图时明说"关闭",别写成 0 张让人以为没拉到)。
shot_note() {
  if [ "$SHOTS" = "1" ]; then echo "截图 $SCREENSHOT_COUNT 张"; else echo "截图 关闭"; fi
}

echo "patrol: $PATROL"
echo "设备:   $DEVICE"
echo "截图:   $([ "$SHOTS" = "1" ] && echo "开($SCREENSHOTS_DIR/<套件>/)" || echo "关(--dart-define=E2E_SCREENSHOTS=false)")"
[ -n "$E2E_PACKAGE_NAME" ] || echo "警告:  读不到 applicationId,截图拉取会失败(可用 E2E_PACKAGE_NAME 指定)"
mkdir -p "$LOG_DIR" "$SCREENSHOTS_DIR"

FAILED=""
REPORT=""
for s in $SUITES; do
  suite=$(normalize_suite "$s")
  target="patrol_test/$suite.dart"
  log="$LOG_DIR/$suite.log"

  if [ ! -f "$target" ]; then
    echo "❌ 跳过(文件不存在): $target"
    FAILED="$FAILED $suite"
    REPORT="$REPORT
❌ $suite  —— 文件不存在"
    continue
  fi

  echo ""
  echo "=== $suite ($(date '+%H:%M:%S')) ==="

  if [ "$SHOTS" = "1" ]; then
    # 开截图:跑完不卸载,图才还在设备上(见文件头 clearPackageData 说明)。
    EXTRA="--no-uninstall"
  else
    # 关截图:测试内直接跳过渲染与落盘;跑完照常卸载。
    EXTRA="--dart-define=E2E_SCREENSHOTS=false"
  fi
  EXTRA="$EXTRA -d $DEVICE"

  # shellcheck disable=SC2086  # EXTRA 需要按空格拆成多个参数
  "$PATROL" test -t "$target" $EXTRA >"$log" 2>&1
  code=$?

  SCREENSHOT_COUNT=0
  pull_screenshots "$suite"

  total=$(strip_ansi "$log" | grep -a 'Total:' | tail -1 | sed 's/.*Total: *//')
  ok=$(strip_ansi "$log" | grep -a 'Successful:' | tail -1 | sed 's/.*Successful: *//')
  bad=$(strip_ansi "$log" | grep -a 'Failed:' | tail -1 | sed 's/.*Failed: *//')
  dur=$(strip_ansi "$log" | grep -a 'Duration:' | tail -1 | sed 's/.*Duration: *//')

  if [ "$code" -eq 0 ]; then
    line="✅ $suite  成功 ${ok:-?}/${total:-?} · 失败 ${bad:-?} · ${dur:-?} · $(shot_note)"
  else
    line="❌ $suite  成功 ${ok:-?}/${total:-?} · 失败 ${bad:-?} · ${dur:-?} · $(shot_note)(exit=$code,日志 $log)"
    FAILED="$FAILED $suite"
  fi
  echo "    $line"
  REPORT="$REPORT
$line"
done

echo ""
echo "──────── 结果 ────────$REPORT"
echo ""
if [ -n "$FAILED" ]; then
  echo "失败套件:$FAILED"
  exit 1
fi
echo "全部通过。"
[ "$SHOTS" = "1" ] && echo "截图:$SCREENSHOTS_DIR/<套件>/"
exit 0
