# Host (macOS arm64) build of the C core and its tests. The iOS app has its own theos Makefile in ios/.
ROOT     := $(CURDIR)
PREFIX   := $(ROOT)/third_party/prefix/macos-arm64
VENDOR   := $(ROOT)/third_party/vendor
OUT      := $(ROOT)/build/host
CC       := xcrun clang
CFLAGS   := -std=c99 -O1 -g -Wall -Wextra -Werror -Wno-unused-parameter -Icore -I$(VENDOR) -I$(PREFIX)/include
LIBS     := $(PREFIX)/lib/libssl.a $(PREFIX)/lib/libcrypto.a -lz -lsqlite3

CORE_OBJ := $(patsubst core/%.c,$(OUT)/core/%.o,$(wildcard core/*.c)) $(OUT)/vendor/yyjson.o $(OUT)/vendor/qrcodegen.o
UNIT_OBJ := $(patsubst tests/host/%.c,$(OUT)/tests/%.o,$(wildcard tests/host/test_*.c)) $(OUT)/tests/tb_test_main.o
E2E_OBJ  := $(patsubst tests/e2e/%.c,$(OUT)/e2e/%.o,$(wildcard tests/e2e/*.c)) $(OUT)/tests/tb_test_main.o

.PHONY: all
all: $(OUT)/unit_tests $(OUT)/e2e_tests

$(OUT)/core/%.o: core/%.c core/*.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUT)/vendor/%.o: $(VENDOR)/%.c
	@mkdir -p $(dir $@)
	$(CC) -std=c99 -O2 -w -c $< -o $@

$(OUT)/tests/%.o: tests/host/%.c tests/host/tb_test.h core/*.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -Itests/host -c $< -o $@

$(OUT)/e2e/%.o: tests/e2e/%.c tests/host/tb_test.h core/*.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -Itests/host -c $< -o $@

$(OUT)/unit_tests: $(UNIT_OBJ) $(CORE_OBJ)
	$(CC) $^ $(LIBS) -o $@

$(OUT)/e2e_tests: $(E2E_OBJ) $(CORE_OBJ)
	$(CC) $^ $(LIBS) -o $@

# ---------------------------------------------------------------------------
# iOS armv7 / iOS 6 static library for the app.
IOS_SDK    := $(HOME)/theos/sdks/iPhoneOS9.3-armv7.sdk
IOS_OUT    := $(ROOT)/build/ios
IOS_PREFIX := $(ROOT)/third_party/prefix/ios-armv7
# An API newer than the iOS 6.0 deployment target is a build error.
# -mno-thumb: ld-27037 writes code pointers without the Thumb bit; Thumb code crashes when entered through a pointer.
IOS_FLAGS  := -arch armv7 -mno-thumb -isysroot $(IOS_SDK) -miphoneos-version-min=6.0 -Werror=unguarded-availability -ffile-prefix-map=$(ROOT)=.
IOS_CFLAGS := -std=c99 -Os -g -Wall -Wextra -Werror -Wno-unused-parameter $(IOS_FLAGS) -Icore -I$(VENDOR) -I$(IOS_PREFIX)/include
IOS_OBJ    := $(patsubst core/%.c,$(IOS_OUT)/core/%.o,$(wildcard core/*.c)) $(IOS_OUT)/vendor/yyjson.o $(IOS_OUT)/vendor/qrcodegen.o

.PHONY: ios-lib
ios-lib: $(IOS_OUT)/libtubecore.a

$(IOS_OUT)/core/%.o: core/%.c core/*.h
	@mkdir -p $(dir $@)
	$(CC) $(IOS_CFLAGS) -c $< -o $@

$(IOS_OUT)/vendor/%.o: $(VENDOR)/%.c
	@mkdir -p $(dir $@)
	$(CC) -std=c99 -O2 -w $(IOS_FLAGS) -c $< -o $@

$(IOS_OUT)/libtubecore.a: $(IOS_OBJ)
	@rm -f $@
	xcrun libtool -static -o $@ $^

# JS solver helper (fallback path only, own process): QuickJS-NG + tools/tbjs.c, armv7.
QJS := $(ROOT)/third_party/src/quickjs-0.18.0
.PHONY: ios-tbjs
ios-tbjs: $(IOS_OUT)/tbjs
$(IOS_OUT)/tbjs: tools/tbjs.c
	@mkdir -p $(dir $@)
	$(CC) -std=gnu11 -Os -w -D_GNU_SOURCE $(IOS_FLAGS) -include tools/ios6_compat.h -I$(QJS) tools/tbjs.c $(QJS)/quickjs.c $(QJS)/libregexp.c $(QJS)/libunicode.c $(QJS)/dtoa.c -lm -o $@
	ldid -S $@
