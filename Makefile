APP_DIR    ?= AnnoRead
BUILD_DIR   = build
DIST_DIR    = dist
STAGE_ROOT  = $(BUILD_DIR)/stage
STAGE_DIR   = $(STAGE_ROOT)/$(APP_DIR)
PACKAGE_FILE = $(DIST_DIR)/$(APP_DIR).muxapp

ENGINE_DIR  = engine
AARCH64_SO  = $(ENGINE_DIR)/liblegado_qjs_aarch64.so
VENDOR_DIR  = package/vendor

.PHONY: all run test package cross clean

all: test

run:
	@echo "Running Love2D locally (720x720 window)..."
	love .

test:
	@$(MAKE) -C $(ENGINE_DIR) host
	@$(MAKE) -C $(ENGINE_DIR) deploy
	@$(MAKE) -C $(ENGINE_DIR) test
	@python3 tests/test_muxapp_arch.py
	@python3 tests/test_public_examples.py
	@python3 tests/test_json_compat.py $(if $(ANNO_SOURCE_COLLECTION),--collection "$(ANNO_SOURCE_COLLECTION)",)
	@python3 tests/run_http_compat.py
	@echo "Running test suite..."
	@lua tests/test_viewport.lua
	@lua tests/test_input.lua
	@luajit tests/test_navigation_and_input.lua
	@luajit tests/test_settings.lua
	@luajit tests/test_fixes_batch.lua
	@luajit tests/test_discover_fixes.lua
	@luajit tests/test_discover_offline.lua
	@luajit tests/test_ime_and_cache.lua
	@luajit tests/test_multi_source_files.lua
	@luajit tests/test_sources_batch.lua
	@luajit tests/test_layout_margins.lua
	@luajit tests/test_theme_jirai.lua
	@luajit tests/test_shuyuan_verified.lua
	@luajit tests/test_cookie_mowan.lua
	@luajit tests/test_jsoup_compat.lua
	@luajit tests/test_bundled_three_sources.lua
	@luajit tests/test_reader_offline_toc.lua
	@luajit tests/test_reader_navigation_fixes.lua
	@luajit tests/test_change_source.lua
	@luajit tests/test_tts.lua
	@luajit tests/test_tts_config.lua
	@luajit tests/test_tts_controls.lua
	@luajit tests/test_tts_cache.lua
	@luajit tests/test_tts_volume.lua
	@luajit tests/test_tab_search_and_reader_b_tts.lua
	@python3 tests/test_icon_format.py
	@luajit tests/test_power_and_safety.lua
	@luajit tests/test_reading_progress_save.lua
	@luajit tests/test_font.lua
	@luajit tests/test_portability.lua
	@luajit tests/test_aes.lua
	@luac -p main.lua conf.lua src/storage.lua src/views/sources.lua src/views/discover.lua src/viewport.lua src/input.lua src/views/settings.lua src/keyboard.lua src/cache.lua src/book_download.lua src/views/reader.lua src/tts.lua src/tts_config.lua src/tts_cache.lua
	@echo "All tests passed successfully!"

# Cross-build the QuickJS rule engine for the handheld (aarch64 / glibc 2.38).
cross:
	@$(MAKE) -C $(ENGINE_DIR) cross

# Assemble the muOS .muxapp for RG CubeXX (aarch64, glibc 2.38).
#
# Layout (relative to the archive root, which extracts to MUOS/application):
#   AnnoRead/
#     mux_launch.sh          muOS entry point (# HELP/ICON/GRID metadata)
#     mux_lang.ini           application display names
#     icon.png               128x128 install icon
#     love                   bundled aarch64 LÖVE runtime
#     libs/                  bundled runtime libs (rpath hijack via LD_LIBRARY_PATH)
#     main.lua conf.lua src/ assets/ glyph/   game payload
#   conf/ is intentionally NOT shipped: it is created at runtime and holds the
#   user's book sources / bookshelf / chapter cache so reinstalls keep user data.
package: test
	@$(MAKE) -C $(ENGINE_DIR) cross
	@echo "Packaging muOS application: $(PACKAGE_FILE)..."
	@rm -rf $(BUILD_DIR)
	@mkdir -p $(STAGE_DIR)/libs $(STAGE_DIR)/glyph $(DIST_DIR)

	@# --- game payload ---
	@cp -r main.lua conf.lua src assets $(STAGE_DIR)/
	@# The local MiMo key is ignored by Git. Include it only when configured.
	@if [ -f config/mimo_tts.json ]; then mkdir -p $(STAGE_DIR)/config; install -m 600 config/mimo_tts.json $(STAGE_DIR)/config/mimo_tts.json; fi
	@mkdir -p $(STAGE_DIR)/sources
	@if [ -f sources/README.md ]; then cp sources/README.md $(STAGE_DIR)/sources/; fi
	@cp $(ENGINE_DIR)/vendor/Copyright.libxml2 $(STAGE_DIR)/COPYRIGHT-libxml2.txt
	@# swap in the device (aarch64) native rule engine
	@cp $(AARCH64_SO) $(STAGE_DIR)/src/liblegado_qjs.so

	@# --- bundled LÖVE runtime for aarch64 (no system love on muOS) ---
	@cp $(VENDOR_DIR)/love $(STAGE_DIR)/love
	@chmod +x $(STAGE_DIR)/love
	@cp $(VENDOR_DIR)/liblove-11.5.so $(VENDOR_DIR)/libluajit-5.1.so.2 $(STAGE_DIR)/libs/

	@# --- muOS metadata, launcher and icons ---
	@cp package/mux_launch.sh $(STAGE_DIR)/mux_launch.sh
	@chmod +x $(STAGE_DIR)/mux_launch.sh
	@cp package/mux_lang.ini $(STAGE_DIR)/mux_lang.ini
	@cp package/icon.png $(STAGE_DIR)/icon.png
	@cp package/glyph/read.png $(STAGE_DIR)/glyph/read.png

	@# --- normalise line endings so mux_launch.sh runs on device ---
	@sed -i 's/\r$$//' $(STAGE_DIR)/mux_launch.sh

	@# --- package into .muxapp (STORE-only ZIP, as muOS recommends) ---
	@python3 package/make_muxapp.py "$(STAGE_ROOT)" "$(APP_DIR)" "$(PACKAGE_FILE)"

	@rm -rf $(BUILD_DIR)
	@echo "Build complete! Package created at: $(PACKAGE_FILE)"
	@echo "Copy it to the SD card ARCHIVE folder, then install via muOS Archive Manager."

clean:
	@rm -rf $(BUILD_DIR) $(DIST_DIR)
	@$(MAKE) -C $(ENGINE_DIR) clean >/dev/null 2>&1 || true
	@echo "Cleaned build artifacts."
