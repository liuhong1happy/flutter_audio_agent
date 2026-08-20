#!/bin/sh
# 构建 Android APK(参考 masrobo neme-ai-app/scripts/build-android.sh)。
# 可选:构建完成后上传蒲公英(Pgyer)并通知飞书(Feishu)。
#
# 用法:
#   sh scripts/build-android.sh [--target-platform android-arm,android-arm64]
#
# 环境变量(可覆盖默认值):
#   PGYER_API_KEY         蒲公英 API Key(默认见下)
#   FEISHU_ACCESS_TOKEN   飞书机器人 webhook token(默认见下)
#   FEISHU_TEMPLATE_ID    飞书消息卡片模板 id(默认 AAqdXuz6FqSfl)
#   BUILD_CHANNEL_SHORTCUT 蒲公英渠道短链(默认 tts_demo)
set -e

TIME_FORMAT="%Y-%m-%d %H:%M:%S"
PGYER_API_KEY="${PGYER_API_KEY:-78c83aa2cc2846845ff30092040a3b3a}"
FEISHU_ACCESS_TOKEN="${FEISHU_ACCESS_TOKEN:-643fd58d-e9a9-4a4d-8431-d82993853756}"
FEISHU_TEMPLATE_ID="${FEISHU_TEMPLATE_ID:-AAqdXuz6FqSfl}"
FEISHU_QR_IMG_KEY="${FEISHU_QR_IMG_KEY:-img_v3_0214o_9bb97e03-18a3-45e5-b6c3-1e5a9ffa1e0g}"
BUILD_CHANNEL_SHORTCUT="${BUILD_CHANNEL_SHORTCUT:-tts_demo}"
TARGET_PLATFORM="${1:-android-arm,android-arm64}"

DOWNLOAD_URL="https://www.pgyer.com/$BUILD_CHANNEL_SHORTCUT"
FEISHU_URL="https://open.feishu.cn/open-apis/bot/v2/hook/$FEISHU_ACCESS_TOKEN"

START_TIME=$(date +"$TIME_FORMAT")
WORKDIR=$(pwd)
echo "开始打包时间: $START_TIME,工作目录: $WORKDIR"

echo "删除 build 目录"
rm -rf "$WORKDIR/build"

flutter build apk --target-platform "$TARGET_PLATFORM"

APKDIR="$WORKDIR/build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APKDIR" ]; then
  echo "打包文件不存在 => $APKDIR"
  exit 1
fi
echo "打包完成,包路径为: $APKDIR"

if [ -n "$PGYER_API_KEY" ]; then
  echo "开始上传蒲公英..."
  curl -F "file=@$APKDIR" -F "_api_key=$PGYER_API_KEY" -# https://www.pgyer.com/apiv2/app/upload
  echo "上传完成"
else
  echo "未设置 PGYER_API_KEY,跳过蒲公英上传。"
fi

END_TIME=$(date +"$TIME_FORMAT")
echo "结束打包时间: $END_TIME"
# 计算耗时(秒)
START_TIMESTAMP=$(date -d "$START_TIME" +%s 2>/dev/null || date -j -f "$TIME_FORMAT" "$START_TIME" +%s)
END_TIMESTAMP=$(date -d "$END_TIME" +%s 2>/dev/null || date -j -f "$TIME_FORMAT" "$END_TIME" +%s)
TASK_TIME=$((END_TIMESTAMP-START_TIMESTAMP))

if [ -n "$FEISHU_ACCESS_TOKEN" ]; then
  echo "开始飞书通知..."
  # 模板要求 duration 与 qrcode.img_key(飞书图库图片 key,可经 FEISHU_QR_IMG_KEY 提供)。
  CONTENT="{\"project\":\"flutter_tts_demo\",\"platform\":\"Android\",\"env\":\"开发环境\",\"startTime\":\"${START_TIME}\",\"endTime\":\"${END_TIME}\",\"duration\":\"${TASK_TIME}\",\"qrcode\":{\"img_key\":\"${FEISHU_QR_IMG_KEY:-}\"},\"links\":{\"url\":\"${DOWNLOAD_URL}\"}}"
  curl "$FEISHU_URL" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    -d "{\"msg_type\":\"interactive\",\"card\":{\"type\":\"template\",\"data\":{\"template_id\":\"${FEISHU_TEMPLATE_ID}\",\"template_variable\":${CONTENT}}}}"
  echo ""
  echo "飞书通知完成"
else
  echo "未设置 FEISHU_ACCESS_TOKEN,跳过飞书通知。"
fi

echo "全部完成。"
