#!/usr/bin/env bash
#
# SCare Routine — wireless build + install + launch
# Usage:  ./run-device.sh
# Xcode UI'ya hiç dokunmadan telefona yükler ve uygulamayı açar.
#
set -e

# -------------------------------------------------------------------
# Konfigürasyon
# -------------------------------------------------------------------
SCHEME="SCare Routine"
CONFIGURATION="Debug"
BUNDLE_ID="com.aliarifsoydas.scareroutine"

# Telefonun bağlı olduğunu doğrula (Wi-Fi veya kablo)
CONNECTED=$(xcrun devicectl list devices 2>/dev/null | grep -E "iPhone.*connected" | head -1)

if [ -z "$CONNECTED" ]; then
    echo "❌ Bağlı bir iPhone bulunamadı. Aynı Wi-Fi'da ve 'Connect via network' açık mı kontrol et."
    echo "   Listele: xcrun devicectl list devices"
    exit 1
fi

# UDID'i UUID regex'i ile çek (devicectl CoreDevice formatı)
CORE_UDID=$(echo "$CONNECTED" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)
echo "📱 Cihaz CoreDevice ID: $CORE_UDID"

# -------------------------------------------------------------------
# Build
# -------------------------------------------------------------------
echo "🔨 Build başlıyor..."
DERIVED_DATA=$(mktemp -d)

xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=iOS,name=iPhone' \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    -quiet \
    build

# .app dosyasının yolunu bul (iOS device build'i Debug-iphoneos/ altında)
APP_PATH=$(find "$DERIVED_DATA/Build/Products" -name "*.app" -type d -maxdepth 3 | head -1)

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "❌ Build çıktısı bulunamadı."
    exit 1
fi

echo "✅ Build başarılı: $APP_PATH"

# -------------------------------------------------------------------
# Install
# -------------------------------------------------------------------
echo "📦 Yükleniyor..."
xcrun devicectl device install app --device "$CORE_UDID" "$APP_PATH"

# -------------------------------------------------------------------
# Önceki instance'ı terminate et (debugger zombi'sini önlemek için)
# -------------------------------------------------------------------
echo "🛑 Önceki instance kapatılıyor (varsa)..."
PIDS=$(xcrun devicectl device info processes --device "$CORE_UDID" 2>/dev/null \
    | awk -v bid="$BUNDLE_ID" '$0 ~ bid {print $1}')
if [ -n "$PIDS" ]; then
    for pid in $PIDS; do
        xcrun devicectl device process terminate --device "$CORE_UDID" --pid "$pid" >/dev/null 2>&1 || true
    done
    sleep 1
fi

# -------------------------------------------------------------------
# Launch
# -------------------------------------------------------------------
echo "🚀 Açılıyor..."
if ! xcrun devicectl device process launch --device "$CORE_UDID" "$BUNDLE_ID" 2>&1; then
    echo "⚠️  Otomatik launch başarısız oldu. Telefondan elle aç — install zaten tamam."
fi

echo "✨ Bitti. Cleanup..."
rm -rf "$DERIVED_DATA"
