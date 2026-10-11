#!/usr/bin/env bash
# FitLog 玻璃版 → Android APK（纯 aapt2 + d8 + apksigner，无 Gradle）
# 说明：因为本机项目路径含中文，aapt2 无法读取，故先拷到 ASCII 临时目录 C:/tmp/flg 构建，再把 APK 拷回。
# 用法：在 FitLog-glass-apk/ 目录运行 `bash build_apk.sh`
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
BT="C:/Android/build-tools/34.0.0"
PLAT="C:/Android/platforms/android-34/android.jar"
PY="C:/Users/dongxiaotong/AppData/Local/hermes/hermes-agent/venv/Scripts/python.exe"
SRC="$HERE/../web"                   # 玻璃前端（index.html/styles.css/app.js）
B="/c/tmp/flg"                       # ASCII 临时构建目录
BWIN=$(cygpath -w "$B")

echo "==> 准备 ASCII 临时构建目录"
rm -rf "$B"
mkdir -p "$B/app/src/main/java/com/fitlog/glass" \
         "$B/app/src/main/res/values" "$B/app/src/main/res/drawable" "$B/app/src/main/res/layout" \
         "$B/app/src/main/assets" "$B/build" "$B/build/dexout"
cp "$HERE/app/src/main/AndroidManifest.xml"        "$B/app/src/main/"
cp "$HERE/app/src/main/res/values/"*               "$B/app/src/main/res/values/"
cp "$HERE/app/src/main/res/drawable/"*             "$B/app/src/main/res/drawable/"
cp "$HERE/app/src/main/res/layout/"*               "$B/app/src/main/res/layout/"
cp "$HERE/app/src/main/java/com/fitlog/glass/MainActivity.java" "$B/app/src/main/java/com/fitlog/glass/"
cp "$SRC/index.html" "$SRC/styles.css" "$SRC/app.js" "$B/app/src/main/assets/"

echo "==> aapt2 编译 + 链接"
"$BT/aapt2.exe" compile --dir "$B/app/src/main/res" -o "$B/build/res.zip"
"$BT/aapt2.exe" link -o "$B/build/app-base.apk" -I "$PLAT" \
  --manifest "$B/app/src/main/AndroidManifest.xml" -R "$B/build/res.zip" \
  -A "$B/app/src/main/assets" --auto-add-overlay

echo "==> 编译 Java → dex"
javac -encoding UTF-8 -cp "$PLAT" -d "$B/build/classes" "$B/app/src/main/java/com/fitlog/glass/MainActivity.java"
jar cf "$B/build/classes.jar" -C "$B/build/classes" .
"$BT/d8.bat" --lib "$PLAT" --min-api 24 --output "$B/build/dexout" "$B/build/classes.jar"
cp "$B/build/dexout/classes.dex" "$B/build/classes.dex"

echo "==> 注入 classes.dex（STORED 不压缩）"
"$PY" - "$BWIN" <<'PY'
import zipfile, shutil, sys
root=sys.argv[1]
shutil.copy(f"{root}/build/app-base.apk", f"{root}/build/app-raw.apk")
with zipfile.ZipFile(f"{root}/build/app-raw.apk",'a',zipfile.ZIP_STORED) as z:
    z.write(f"{root}/build/classes.dex","classes.dex")
PY

echo "==> zipalign + 签名"
"$BT/zipalign.exe" -p 4 "$B/build/app-raw.apk" "$B/build/app-aligned.apk"
[[ -f "$B/debug.keystore" ]] || keytool -genkeypair -v -keystore "$B/debug.keystore" \
  -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass android -keypass android -dname "CN=Android Debug,O=Android,C=US"
"$BT/apksigner.bat" sign --ks "$B/debug.keystore" --ks-key-alias androiddebugkey \
  --ks-pass pass:android --key-pass pass:android --out "$B/build/FitLog-glass.apk" "$B/build/app-aligned.apk"
"$BT/apksigner.bat" verify "$B/build/FitLog-glass.apk"

mkdir -p "$HERE/build"
cp "$B/build/FitLog-glass.apk" "$HERE/build/FitLog-glass.apk"
echo "DONE -> $HERE/build/FitLog-glass.apk"
ls -lh "$HERE/build/FitLog-glass.apk"
