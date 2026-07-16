# ============================================================
#  XJWeChatPay v3.0 Makefile - Theos build configuration (Enhanced)
# ============================================================

TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = XJWeChatPay

# Source files (enhanced)
XJWeChatPay_FILES = Tweak.x \
    XJPaymentXMLParser.m \
    XJRemoteConfig.m \
    XJPaySourceConfig.m \
    XJMessageDedup.m

# Compiler flags
XJWeChatPay_CFLAGS = -fobjc-arc -Wno-deprecated -Wno-unused-variable
XJWeChatPay_LDFLAGS = -Wl,-segalign,4000

# Frameworks (unchanged)
XJWeChatPay_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
