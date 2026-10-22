CC ?= gcc
CROSS ?= aarch64-linux-gnu-gcc
AR ?= ar
CFLAGS ?= -O2 -fPIC -fvisibility=hidden -Wall
LIBS = -lm -lpthread
TARGET = liblegado_qjs.so
CROSS_TARGET = liblegado_qjs_aarch64.so
QJS_SRC = quickjs/quickjs.c quickjs/libregexp.c quickjs/libunicode.c quickjs/dtoa.c
LIBXML_VERSION = 2.15.4
LIBXML_SHA256 = 98087fd181d9070724f3fbc65c7377db03038eb92bd882374daff44940138821
LIBXML_ARCHIVE = vendor/libxml2-$(LIBXML_VERSION).tar.xz
CACHE_ROOT ?= build/libxml2-src
HOST_BUILD = build/host-libxml
CROSS_BUILD = build/aarch64-libxml
NATIVE_SRC = legado_bridge.c native_xpath.c

.PHONY: all host cross deploy test clean
all: host
host: $(TARGET)

$(LIBXML_ARCHIVE):
	@mkdir -p vendor
	@echo "Missing pinned libxml2 archive: $@" >&2; exit 1

$(CACHE_ROOT)/libxml2-$(LIBXML_VERSION)/.stamp: $(LIBXML_ARCHIVE)
	@mkdir -p $(CACHE_ROOT)
	echo "$(LIBXML_SHA256)  $(LIBXML_ARCHIVE)" | sha256sum -c -
	rm -rf $(CACHE_ROOT)/libxml2-$(LIBXML_VERSION)
	mkdir -p $(CACHE_ROOT)/libxml2-$(LIBXML_VERSION)
	tar -xJf $(LIBXML_ARCHIVE) --strip-components=1 -C $(CACHE_ROOT)/libxml2-$(LIBXML_VERSION)
	touch $@

$(HOST_BUILD)/libxml2.a: Makefile $(CACHE_ROOT)/libxml2-$(LIBXML_VERSION)/.stamp
	cmake -S $(CACHE_ROOT)/libxml2-$(LIBXML_VERSION) -B $(HOST_BUILD) -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_C_FLAGS='-ffunction-sections -fdata-sections' -DBUILD_SHARED_LIBS=OFF -DLIBXML2_WITH_HTML=ON -DLIBXML2_WITH_XPATH=ON -DLIBXML2_WITH_OUTPUT=ON -DLIBXML2_WITH_ICONV=ON -DLIBXML2_WITH_ICU=OFF -DLIBXML2_WITH_ZLIB=OFF -DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_PROGRAMS=OFF -DLIBXML2_WITH_TESTS=OFF -DLIBXML2_WITH_CATALOG=OFF -DLIBXML2_WITH_MODULES=OFF -DLIBXML2_WITH_DEBUG=OFF -DLIBXML2_WITH_VALID=OFF -DLIBXML2_WITH_SCHEMAS=OFF -DLIBXML2_WITH_RELAXNG=OFF -DLIBXML2_WITH_XINCLUDE=OFF -DLIBXML2_WITH_READER=OFF -DLIBXML2_WITH_WRITER=OFF -DLIBXML2_WITH_PUSH=OFF -DLIBXML2_WITH_SAX1=OFF -DLIBXML2_WITH_XPTR=OFF -DLIBXML2_WITH_PATTERN=OFF -DLIBXML2_WITH_REGEXPS=OFF
	cmake --build $(HOST_BUILD) -j$$(nproc)

$(CROSS_BUILD)/libxml2.a: Makefile $(CACHE_ROOT)/libxml2-$(LIBXML_VERSION)/.stamp
	cmake -S $(CACHE_ROOT)/libxml2-$(LIBXML_VERSION) -B $(CROSS_BUILD) -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 -DCMAKE_C_COMPILER=$(CROSS) -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_C_FLAGS='-ffunction-sections -fdata-sections' -DBUILD_SHARED_LIBS=OFF -DLIBXML2_WITH_HTML=ON -DLIBXML2_WITH_XPATH=ON -DLIBXML2_WITH_OUTPUT=ON -DLIBXML2_WITH_ICONV=ON -DLIBXML2_WITH_ICU=OFF -DLIBXML2_WITH_ZLIB=OFF -DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_PROGRAMS=OFF -DLIBXML2_WITH_TESTS=OFF -DLIBXML2_WITH_CATALOG=OFF -DLIBXML2_WITH_MODULES=OFF -DLIBXML2_WITH_DEBUG=OFF -DLIBXML2_WITH_VALID=OFF -DLIBXML2_WITH_SCHEMAS=OFF -DLIBXML2_WITH_RELAXNG=OFF -DLIBXML2_WITH_XINCLUDE=OFF -DLIBXML2_WITH_READER=OFF -DLIBXML2_WITH_WRITER=OFF -DLIBXML2_WITH_PUSH=OFF -DLIBXML2_WITH_SAX1=OFF -DLIBXML2_WITH_XPTR=OFF -DLIBXML2_WITH_PATTERN=OFF -DLIBXML2_WITH_REGEXPS=OFF
	cmake --build $(CROSS_BUILD) -j$$(nproc)

$(TARGET): Makefile $(NATIVE_SRC) native_xpath.h legado_bridge.h legado_js_bundle.h $(QJS_SRC) $(HOST_BUILD)/libxml2.a
	$(CC) -shared $(CFLAGS) -ffunction-sections -fdata-sections -Iquickjs -I. -I$(HOST_BUILD) -I$(CACHE_ROOT)/libxml2-$(LIBXML_VERSION)/include $(NATIVE_SRC) $(QJS_SRC) $(HOST_BUILD)/libxml2.a -Wl,--gc-sections -Wl,--exclude-libs,ALL $(LIBS) -o $@

$(CROSS_TARGET): Makefile $(NATIVE_SRC) native_xpath.h legado_bridge.h legado_js_bundle.h legado_compat_glibc238.c $(QJS_SRC) $(CROSS_BUILD)/libxml2.a
	$(CROSS) -c -O2 -fPIC -fno-builtin legado_compat_glibc238.c -o build/compat-aarch64.o
	$(CROSS) -shared $(CFLAGS) -fno-builtin -ffunction-sections -fdata-sections -Iquickjs -I. -I$(CROSS_BUILD) -I$(CACHE_ROOT)/libxml2-$(LIBXML_VERSION)/include $(NATIVE_SRC) $(QJS_SRC) build/compat-aarch64.o $(CROSS_BUILD)/libxml2.a -Wl,--wrap=cosh -Wl,--wrap=sinh -Wl,--gc-sections -Wl,--exclude-libs,ALL $(LIBS) -o $@

legado_js_bundle.h: legado.js
	xxd -i legado.js > legado_js_bundle.h
	python3 fix_bundle_terminator.py legado_js_bundle.h

cross: $(CROSS_TARGET)
deploy: $(TARGET)
	python3 deploy_host.py "$(TARGET)" "../src/liblegado_qjs.so"

test: $(TARGET)
	@if command -v qjs >/dev/null 2>&1 && qjs -e "1" >/dev/null 2>&1; then set -e; qjs -m test_legado.js; qjs -m test_jsonpath_java.js; qjs -m test_java_host.js; fi
	$(CC) -O2 -Iquickjs -I. test_c_bridge.c -L. -llegado_qjs -Wl,-rpath,'$$ORIGIN/..' -o build/test_c_bridge
	./build/test_c_bridge
	$(CC) -O2 -Iquickjs -I. test_xpath.c -L. -llegado_qjs -Wl,-rpath,'$$ORIGIN/..' -o build/test_xpath
	./build/test_xpath
	$(CC) -O2 -Iquickjs -I. test_native_flow.c -L. -llegado_qjs -Wl,-rpath,'$$ORIGIN/..' -o build/test_native_flow
	./build/test_native_flow
	$(CC) -O2 -Iquickjs -I. test_compat_native.c -L. -llegado_qjs -Wl,-rpath,'$$ORIGIN/..' -o build/test_compat_native
	./build/test_compat_native test_compat.js

clean:
	rm -rf build/host-libxml build/aarch64-libxml build/test_xpath build/test_c_bridge build/test_native_flow build/test_compat_native build/compat-aarch64.o $(TARGET) $(CROSS_TARGET) build/compat-aarch64.o
