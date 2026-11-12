# PadTube iOS app (theos). Build: make -C ios package   (needs THEOS=~/theos and GNU make)
TARGET := iphone:clang:9.3:6.0
ARCHS := armv7
# ../scripts/make_ios_sdk.sh: the 9.3 SDK with stubs the current Apple linker accepts for armv7.
SYSROOT := $(THEOS)/sdks/iPhoneOS9.3-armv7.sdk
include $(THEOS)/makefiles/common.mk

ROOT := $(CURDIR)/..
IOS_PREFIX := $(ROOT)/third_party/prefix/ios-armv7

# PUBLIC=1: the public build (docs/release.md). It never links PadWeb (private, D46) and uses the public icon (D47).
# Without PUBLIC=1 the owner's build links PadWeb and uses icon option A when they are on this Mac.
PADWEB := $(HOME)/padweb
ifneq ($(PUBLIC),1)
ifneq ($(wildcard $(PADWEB)/build/ios/libpadweb.a),)
USE_PADWEB := 1
endif
ifneq ($(wildcard $(ROOT)/assets/icons/owner/PTIcon2.png),)
OWNER_ICON := 1
endif
endif

APPLICATION_NAME = PadTube
PadTube_FILES = $(wildcard src/*.m)
# An API newer than iOS 6.0 is a build error. -mno-thumb: see IOS_FLAGS in ../Makefile.
PadTube_CFLAGS = -ffile-prefix-map=$(ROOT)=. -mno-thumb -fobjc-arc -Werror=unguarded-availability -Wno-deprecated-module-dot-map -Wno-deprecated-declarations \
	-I$(ROOT)/core -I$(ROOT)/third_party/vendor
ifeq ($(USE_PADWEB),1)
PadTube_CFLAGS += -I$(PADWEB)/include
else
PadTube_CFLAGS += -DTB_NO_PADWEB
endif
# SELFTEST=1: test-only build that the Mac drives over USB (tests/device). Never ship it.
ifeq ($(SELFTEST),1)
PadTube_FILES += $(wildcard selftest/*.m)
PadTube_CFLAGS += -DTB_SELFTEST -Iselftest -Isrc
endif
PadTube_LDFLAGS = $(ROOT)/build/ios/libtubecore.a $(IOS_PREFIX)/lib/libssl.a $(IOS_PREFIX)/lib/libcrypto.a -lz -lsqlite3
ifeq ($(USE_PADWEB),1)
PadTube_LDFLAGS += $(PADWEB)/build/ios/libpadweb.a
endif
PadTube_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore MediaPlayer AVFoundation CoreMedia ImageIO

include $(THEOS_MAKE_PATH)/application.mk

# PadWeb (in-app browser for links): the 9.3 SDK binds NSURLProtocol/NSHTTPCookie... to CFNetwork; on iOS 6 they
# live in Foundation. Fix the binds in the staged binary, then sign again.
# BUNDLE_ID=<id>: a test copy with its own data folder (docs/release.md §6). Never for a release.
after-stage::
ifeq ($(USE_PADWEB),1)
	python3 $(PADWEB)/tools/fix_cfnetwork_binds.py "$(THEOS_STAGING_DIR)/Applications/PadTube.app/PadTube"
	ldid -S "$(THEOS_STAGING_DIR)/Applications/PadTube.app/PadTube"
endif
ifneq ($(BUNDLE_ID),)
	plutil -replace CFBundleIdentifier -string "$(BUNDLE_ID)" "$(THEOS_STAGING_DIR)/Applications/PadTube.app/Info.plist"
	ldid -S "$(THEOS_STAGING_DIR)/Applications/PadTube.app/PadTube"
endif

before-all::
	$(MAKE) -C $(ROOT) ios-lib
	mkdir -p Resources/Licenses $(ROOT)/build
	cp /etc/ssl/cert.pem Resources/roots.pem
	cp $(ROOT)/third_party/vendor/yyjson-LICENSE.txt Resources/Licenses/
	cp $(ROOT)/third_party/vendor/OpenSSL-LICENSE.txt $(ROOT)/third_party/vendor/qrcodegen-LICENSE.txt Resources/Licenses/
	xcrun clang -w $(ROOT)/tools/make_icon.c -framework ApplicationServices -o $(ROOT)/build/make_icon
	$(ROOT)/build/make_icon Resources
	rm -f Resources/Icon*.png Resources/PTIcon*.png
ifeq ($(OWNER_ICON),1)
	cp $(ROOT)/assets/icons/owner/*.png Resources/
else
	xcrun clang -w $(ROOT)/tools/make_public_icon.c -framework ApplicationServices -o $(ROOT)/build/make_public_icon
	mkdir -p $(ROOT)/build/icons-public
	$(ROOT)/build/make_public_icon $(ROOT)/build/icons-public
	cp $(ROOT)/build/icons-public/PTIcon2*.png Resources/
endif
	rm -rf Resources/tbjs Resources/js
ifeq ($(SELFTEST),1)
	$(MAKE) -C $(ROOT) ios-tbjs
	cp $(ROOT)/build/ios/tbjs Resources/tbjs
	mkdir -p Resources/js
	cp $(ROOT)/local/research-data/qjs/run_one.js $(ROOT)/local/research-data/qjs/run_player_es6.js Resources/js/
endif
