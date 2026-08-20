#!/bin/bash
# 构建 iOS IPA(参考 masrobo neme-ai-app/scripts/build-ios.sh)。
# 需在 macOS + Xcode 上运行。
# 可选:构建完成后上传蒲公英(Pgyer)并通知飞书(Feishu)。
#
# 用法:
#   bash scripts/build-ios.sh
#
# 环境变量(可覆盖默认值):
#   PGYER_API_KEY / FEISHU_ACCESS_TOKEN / FEISHU_TEMPLATE_ID / BUILD_CHANNEL_SHORTCUT
set -e

TIME_FORMAT="%Y-%m-%d %H:%M:%S"
PGYER_API_KEY="${PGYER_API_KEY:-78c83aa2cc2846845ff30092040a3b3a}"
FEISHU_ACCESS_TOKEN="${FEISHU_ACCESS_TOKEN:-643fd58d-e9a9-4a4d-8431-d82993853756}"
FEISHU_TEMPLATE_ID="${FEISHU_TEMPLATE_ID:-AAqdXuz6FqSfl}"
FEISHU_QR_IMG_KEY="${FEISHU_QR_IMG_KEY:-img_v3_0214o_9bb97e03-18a3-45e5-b6c3-1e5a9ffa1e0g}"
BUILD_CHANNEL_SHORTCUT="${BUILD_CHANNEL_SHORTCUT:-tts_demo}"

DOWNLOAD_URL="https://www.pgyer.com/$BUILD_CHANNEL_SHORTCUT"
FEISHU_URL="https://open.feishu.cn/open-apis/bot/v2/hook/$FEISHU_ACCESS_TOKEN"

START_TIME=$(date +"$TIME_FORMAT")
WORKDIR=$(pwd)
EXPORTOPTIONSPLIST="$WORKDIR/scripts/adhocExportOptions.plist"
echo "开始打包时间: $START_TIME,工作目录: $WORKDIR"

TARGET_NAME=Runner
BUILD_TYPE=Release
ARCHIVEPATH="$WORKDIR/build/ios"
EXPORTPATH="$WORKDIR/build/ios/archive"
IPADIR="$EXPORTPATH/app.ipa"

mkdir -p "$ARCHIVEPATH" "$EXPORTPATH"

echo "flutter build ios"
flutter build ios --release

cd "$WORKDIR/ios"

echo "xcodebuild archive -workspace ${TARGET_NAME}.xcworkspace -scheme ${TARGET_NAME} -configuration ${BUILD_TYPE} -archivePath ${ARCHIVEPATH}/${TARGET_NAME} -sdk iphoneos"
xcodebuild archive -quiet \
  -workspace "${TARGET_NAME}.xcworkspace" \
  -scheme "${TARGET_NAME}" \
  -configuration "${BUILD_TYPE}" \
  -archivePath "${ARCHIVEPATH}/${TARGET_NAME}" \
  -sdk iphoneos

echo "xcodebuild exportArchive -archivePath ${ARCHIVEPATH}/${TARGET_NAME}.xcarchive -exportPath ${EXPORTPATH} -exportOptionsPlist ${EXPORTOPTIONSPLIST} -allowProvisioningUpdates"
xcodebuild -quiet \
  -exportArchive \
  -archivePath "${ARCHIVEPATH}/${TARGET_NAME}.xcarchive" \
  -exportPath "${EXPORTPATH}" \
  -exportOptionsPlist "${EXPORTOPTIONSPLIST}" \
  -allowProvisioningUpdates

if [ ! -f "$IPADIR" ]; then
  echo "打包文件不存在 => $IPADIR"
  exit 1
fi
echo "打包完成,包路径为: $IPADIR"

if [ -n "$PGYER_API_KEY" ]; then
  echo "开始上传蒲公英..."
  curl -F "file=@$IPADIR" -F "_api_key=$PGYER_API_KEY" https://www.pgyer.com/apiv2/app/upload
  echo "上传完成"
else
  echo "未设置 PGYER_API_KEY,跳过蒲公英上传。"
fi

END_TIME=$(date +"$TIME_FORMAT")
echo "结束打包时间: $END_TIME"
START_TIMESTAMP=$(date -d "$START_TIME" +%s 2>/dev/null || date -j -f "$TIME_FORMAT" "$START_TIME" +%s)
END_TIMESTAMP=$(date -d "$END_TIME" +%s 2>/dev/null || date -j -f "$TIME_FORMAT" "$END_TIME" +%s)
TASK_TIME=$((END_TIMESTAMP-START_TIMESTAMP))

if [ -n "$FEISHU_ACCESS_TOKEN" ]; then
  echo "开始飞书通知..."
  CONTENT="{\"project\":\"flutter_tts_demo\",\"platform\":\"iOS\",\"env\":\"开发环境\",\"startTime\":\"${START_TIME}\",\"endTime\":\"${END_TIME}\",\"duration\":\"${TASK_TIME}\",\"qrcode\":{\"img_key\":\"${FEISHU_QR_IMG_KEY:-}\"},\"links\":{\"url\":\"${DOWNLOAD_URL}\"}}"
  RESP=$(curl -s "$FEISHU_URL" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    -d "{\"msg_type\":\"interactive\",\"card\":{\"type\":\"template\",\"data\":{\"template_id\":\"${FEISHU_TEMPLATE_ID}\",\"template_variable\":${CONTENT}}}}")
  echo ""
  echo "飞书响应: $RESP"
  case "$RESP" in
    *'"code":0'*) echo "飞书通知成功" ;;
    *'image does not belong'*) echo "飞书拒绝:img_key 不属于本飞书应用/租户,请在飞书开放平台上传二维码图后更新 FEISHU_QR_IMG_KEY" ;;
    *) echo "飞书通知被拒,请检查 FEISHU_ACCESS_TOKEN / FEISHU_TEMPLATE_ID / FEISHU_QR_IMG_KEY" ;;
  esac
else
  echo "未设置 FEISHU_ACCESS_TOKEN,跳过飞书通知。"
fi

echo "全部完成。"
