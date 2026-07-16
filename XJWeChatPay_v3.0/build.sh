#!/bin/bash
# XJWeChatPay v3.0 - 自动版本号递增构建脚本
# 每次编译自动生成唯一版本号的文件名
# 用法: cd XJWeChatPay_v3.0 && ./build.sh

set -e

cd "$(dirname "$0")"
export THEOS="$HOME/theos"
export THEOS_SDKS_PATH="$HOME/theos/sdks"

# 读取当前 build 号
BUILD_FILE=".buildnum"
BUILD=$(cat "$BUILD_FILE" 2>/dev/null || echo "1")
BASE_VERSION="3.0.0"
NEW_VERSION="${BASE_VERSION}-${BUILD}"
PARENT_DIR="$(dirname "$PWD")"

echo "============================================"
echo "  XJWeChatPay Build #${BUILD}"
echo "  Version: ${NEW_VERSION}"
echo "============================================"

# 更新 control 文件版本号
sed -i '' "s/^Version:.*/Version: ${NEW_VERSION}/" control

# 编译（DEBUG=0 避免 theos 加 +debug 后缀）
make clean
make package DEBUG=0

# 查找实际生成的 deb（theos 可能会添加内部 revision 后缀）
ACTUAL_DEB=$(ls packages/com.xj.wechatpay_${NEW_VERSION}*_iphoneos-arm.deb 2>/dev/null | head -1)

if [ -z "$ACTUAL_DEB" ]; then
    echo "[ERROR] deb not found in packages/"
    exit 1
fi

echo "[FOUND] $ACTUAL_DEB"

# 产物重命名到工作区
DYLIB_FILE="XJWeChatPay_v${NEW_VERSION}.dylib"
DEB_FILE="XJWeChatPay_v${NEW_VERSION}.deb"

cp "$ACTUAL_DEB" "$PARENT_DIR/${DEB_FILE}"
echo "[OK] $PARENT_DIR/${DEB_FILE}"

# 从 deb 提取 dylib
python3 -c "
import lzma, tarfile, io, shutil, glob, os
# 找到 deb 文件
parent = '$PARENT_DIR'
deb_path = os.path.join(parent, '$DEB_FILE')
with open(deb_path, 'rb') as f:
    data = f.read()
pos = 8
while pos < len(data):
    name = data[pos:pos+16].rstrip(b' ').decode('ascii', errors='ignore')
    size = int(data[pos+48:pos+58].rstrip(b' '))
    pos += 60
    if name.startswith('data.tar'):
        raw = data[pos:pos+size]
        raw = lzma.decompress(raw)
        with tarfile.open(fileobj=io.BytesIO(raw)) as tar:
            for m in tar.getmembers():
                if 'XJWeChatPay.dylib' in m.name:
                    f = tar.extractfile(m)
                    with open(os.path.join(parent, '$DYLIB_FILE'), 'wb') as o:
                        shutil.copyfileobj(f, o)
                    print(f'[OK] {m.name} ({m.size} bytes)')
    pos += size
    if pos % 2: pos += 1
"
echo "[OK] $PARENT_DIR/${DYLIB_FILE}"

# 递增 build 号
echo "$((BUILD + 1))" > "$BUILD_FILE"

echo "============================================"
echo "  Build #${BUILD} 完成"
echo "  deb:   ${DEB_FILE}"
echo "  dylib: ${DYLIB_FILE}"
echo "  Next:  #$((BUILD + 1))"
echo "============================================"
