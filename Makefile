TARGET := iphone:clang:latest:15.0
ARCHS := arm64
INSTALL_TARGET_PROCESSES = TikTok

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LiquidTok
LiquidTok_FILES = Tweak.x Tracking.x Login.x Tiling.x Debug.x
LiquidTok_CFLAGS = -fobjc-arc
LiquidTok_FRAMEWORKS = UIKit Network

include $(THEOS_MAKE_PATH)/tweak.mk
