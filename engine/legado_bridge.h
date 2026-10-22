#ifndef LEGADO_BRIDGE_H
#define LEGADO_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) || defined(__CYGWIN__)
  #ifdef LEGADO_BUILD_DLL
    #define LEGADO_API __declspec(dllexport)
  #else
    #define LEGADO_API __declspec(dllimport)
  #endif
#else
  #define LEGADO_API __attribute__((visibility("default")))
#endif

/**
 * Initialize Legado QuickJS Engine.
 * Creates the QuickJS runtime, context, and initializes the Legado 3.0 rule engine.
 * Returns 1 on success, 0 on failure.
 */
LEGADO_API int legado_init(void);

/**
 * Clean up and destroy the Legado QuickJS Engine.
 */
LEGADO_API void legado_free(void);

/**
 * Evaluate arbitrary JavaScript code inside the Legado context.
 * Returns allocated C string (JSON or string representation). Caller must free with legado_free_string().
 */
LEGADO_API char* legado_eval(const char* js_code);

/**
 * Parse Legado BookSources from JSON text.
 * Handles arrays, single objects, wrapped envelopes (data/list/sources), and filters damaged sources.
 * Returns JSON array string of normalized BookSources.
 */
LEGADO_API char* legado_parse_sources(const char* json_str);

/**
 * Build HTTP request info for searching.
 * Subsitutes {{key}}, {{page}}, parses method, headers, and body options.
 * Returns JSON object string { url, method, headers, body }.
 */
LEGADO_API char* legado_build_search_req(const char* source_json, const char* keyword, int page);

/**
 * Parse Search results HTML / JSON according to the source's ruleSearch.
 * Returns JSON array string of Book objects [{ name, author, bookUrl, coverUrl, intro, latestChapterTitle, kind, origin, originName }].
 */
LEGADO_API char* legado_parse_search(const char* source_json, const char* html_or_json, const char* base_url);

/**
 * Parse Book Information / Detail page according to ruleBookInfo.
 * Returns JSON object string { name, author, bookUrl, coverUrl, intro, latestChapterTitle, tocUrl, kind, wordCount }.
 */
LEGADO_API char* legado_parse_book_info(const char* source_json, const char* html_or_json, const char* base_url);

/**
 * Parse explore categories from exploreUrl (multi-line or JSON array).
 * Returns JSON array string [{ title, url }, ...].
 */
LEGADO_API char* legado_parse_explore_categories(const char* explore_url);

/**
 * Parse Table of Contents (TOC / chapter list) according to ruleToc.
 * Returns JSON object string { chapters: [{ title, url, index, bookUrl, isVip, chapterInfo }], nextTocUrl }.
 */
LEGADO_API char* legado_parse_toc(const char* source_json, const char* html_or_json, const char* base_url);

/**
 * Parse Chapter Content according to ruleContent.
 * Cleans HTML tags, extracts typography, applies replaceRegex.
 * Returns JSON object string { content, nextContentUrl }.
 */
LEGADO_API char* legado_parse_content(const char* source_json, const char* html_or_json, const char* base_url);

/**
 * Free memory of strings returned by any legado_* functions.
 */
LEGADO_API void legado_free_string(char* ptr);

/**
 * Register the host HTTP callback backing java.ajax().
 * The callback receives (url, optsJson, timeoutMs) and must return a heap
 * string (freed by the bridge) or NULL. Passing NULL disables java.ajax,
 * which then returns ''.
 */
LEGADO_API void legado_set_ajax_callback(char* (*fn)(const char* url, const char* opts, int timeout));

/**
 * Register the host crypto callback backing java.createSymmetricCrypto().
 * The callback receives (algo, key, iv, data, mode) where mode is 0 for
 * encrypt and 1 for decrypt, and must return a heap string (freed by the
 * bridge) or NULL. Passing NULL makes createSymmetricCrypto throw.
 */
LEGADO_API void legado_set_crypto_callback(char* (*fn)(const char* algo, const char* key, const char* iv, const char* data, int mode));

#ifdef __cplusplus
}
#endif

#endif // LEGADO_BRIDGE_H
