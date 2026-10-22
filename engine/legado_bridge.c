#include "legado_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "quickjs.h"
#include "legado_js_bundle.h"
#include "native_xpath.h"

static JSRuntime *g_rt = NULL;
static JSContext *g_ctx = NULL;

// Host callbacks registered from Lua (via LuaJIT FFI). NULL = feature disabled.
static char* (*g_ajax_cb)(const char* url, const char* opts, int timeout) = NULL;
static char* (*g_crypto_cb)(const char* algo, const char* key, const char* iv, const char* data, int mode) = NULL;

void legado_set_ajax_callback(char* (*fn)(const char* url, const char* opts, int timeout)) {
    g_ajax_cb = fn;
}

void legado_set_crypto_callback(char* (*fn)(const char* algo, const char* key, const char* iv, const char* data, int mode)) {
    g_crypto_cb = fn;
}

#define LEGADO_JS_DATA ((const char*)legado_js)
#define LEGADO_JS_LEN  (legado_js_len)

static const char* BRIDGE_INIT_SCRIPT = 
"globalThis.__bridge = {\n"
"    parseSources: function(str) {\n"
"        try {\n"
"            return JSON.stringify(Legado.LegadoEngine.parseBookSources(str));\n"
"        } catch(e) { return '[]'; }\n"
"    },\n"
"    buildSearchReq: function(srcJson, key, page) {\n"
"        try {\n"
"            var src = JSON.parse(srcJson);\n"
"            var req = Legado.LegadoEngine.buildSearchRequest(src, key, parseInt(page) || 1);\n"
"            return JSON.stringify(req);\n"
"        } catch(e) { return 'null'; }\n"
"    },\n"
"    parseSearch: function(srcJson, html, base) {\n"
"        try {\n"
"            var src = JSON.parse(srcJson);\n"
"            var res = Legado.LegadoEngine.parseSearchResult(src, html, base);\n"
"            return JSON.stringify(res);\n"
"        } catch(e) { return '[]'; }\n"
"    },\n"
"    parseBookInfo: function(srcJson, html, base) {\n"
"        try {\n"
"            var src = JSON.parse(srcJson);\n"
"            var res = Legado.LegadoEngine.parseBookInfo(src, html, base);\n"
"            return JSON.stringify(res || {});\n"
"        } catch(e) { return '{}'; }\n"
"    },\n"
"    parseExplore: function(url) {\n"
"        try {\n"
"            return JSON.stringify(Legado.LegadoEngine.parseExploreCategories(url));\n"
"        } catch(e) { return '[]'; }\n"
"    },\n"
"    parseToc: function(srcJson, html, base) {\n"
"        try {\n"
"            var src = JSON.parse(srcJson);\n"
"            var res = Legado.LegadoEngine.parseToc(src, html, base);\n"
"            return JSON.stringify(res);\n"
"        } catch(e) { return '{\"chapters\":[],\"nextTocUrl\":null}'; }\n"
"    },\n"
"    parseContent: function(srcJson, html, base) {\n"
"        try {\n"
"            var src = JSON.parse(srcJson);\n"
"            var res = Legado.LegadoEngine.parseContent(src, html, base);\n"
"            return JSON.stringify(res);\n"
"        } catch(e) { return '{\"content\":\"\",\"nextContentUrl\":null}'; }\n"
"    }\n"
"};\n"
"globalThis.java = new Legado.JsHost('');\n";

static JSValue js_native_ajax(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    (void)this_val;
    if (!g_ajax_cb) return JS_NewString(ctx, "");

    const char *url = argc > 0 ? JS_ToCString(ctx, argv[0]) : NULL;
    const char *opts = argc > 1 ? JS_ToCString(ctx, argv[1]) : NULL;
    int timeout = 10000;
    if (argc > 2) {
        int32_t t = 10000;
        if (JS_ToInt32(ctx, &t, argv[2]) == 0) timeout = t;
    }

    char *res = g_ajax_cb(url ? url : "", opts ? opts : "", timeout);

    if (url) JS_FreeCString(ctx, url);
    if (opts) JS_FreeCString(ctx, opts);

    JSValue out = JS_NewString(ctx, res ? res : "");
    if (res) free(res);
    return out;
}

static JSValue js_native_crypto(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    (void)this_val;
    if (!g_crypto_cb) return JS_NewString(ctx, "");

    const char *algo = argc > 0 ? JS_ToCString(ctx, argv[0]) : NULL;
    const char *key = argc > 1 ? JS_ToCString(ctx, argv[1]) : NULL;
    const char *iv = argc > 2 ? JS_ToCString(ctx, argv[2]) : NULL;
    const char *data = argc > 3 ? JS_ToCString(ctx, argv[3]) : NULL;
    int mode = 0;
    if (argc > 4) {
        int32_t m = 0;
        if (JS_ToInt32(ctx, &m, argv[4]) == 0) mode = m;
    }

    char *res = g_crypto_cb(algo ? algo : "", key ? key : "", iv ? iv : "", data ? data : "", mode);

    if (algo) JS_FreeCString(ctx, algo);
    if (key) JS_FreeCString(ctx, key);
    if (iv) JS_FreeCString(ctx, iv);
    if (data) JS_FreeCString(ctx, data);

    JSValue out = JS_NewString(ctx, res ? res : "");
    if (res) free(res);
    return out;
}

// Compile a script as a global Program without executing it. The JS layer
// uses this to select Program completion semantics versus a function body
// (which permits Legado's top-level `return`) before any side effects occur.
static JSValue js_can_eval_program(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    (void)this_val;
    const char *source = argc > 0 ? JS_ToCString(ctx, argv[0]) : NULL;
    if (!source) return JS_FALSE;
    JSValue compiled = JS_Eval(ctx, source, strlen(source), "<legado-compile-check>",
                               JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_COMPILE_ONLY);
    int ok = !JS_IsException(compiled);
    if (!ok) {
        JSValue exception = JS_GetException(ctx);
        JS_FreeValue(ctx, exception);
    }
    JS_FreeValue(ctx, compiled);
    JS_FreeCString(ctx, source);
    return JS_NewBool(ctx, ok);
}

static int set_global_native_function(JSContext *ctx, JSValueConst global,
                                      const char *name, JSCFunction *function,
                                      int length) {
    JSValue value = JS_NewCFunction(ctx, function, name, length);
    if (JS_IsException(value)) return -1;
    return JS_SetPropertyStr(ctx, global, name, value);
}

int legado_init(void) {
    if (g_ctx != NULL) return 1; // already initialized

    g_rt = JS_NewRuntime();
    if (!g_rt) return 0;

    g_ctx = JS_NewContext(g_rt);
    if (!g_ctx) {
        JS_FreeRuntime(g_rt);
        g_rt = NULL;
        return 0;
    }

    // 1. Evaluate core legado.js bundle
    JSValue val = JS_Eval(g_ctx, LEGADO_JS_DATA, LEGADO_JS_LEN, "legado.js", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(val)) {
        JSValue exc = JS_GetException(g_ctx);
        const char *err = JS_ToCString(g_ctx, exc);
        fprintf(stderr, "[LegadoBridge Init Error]: %s\n", err ? err : "unknown");
        JS_FreeCString(g_ctx, err);
        JS_FreeValue(g_ctx, exc);
        JS_FreeValue(g_ctx, val);
        legado_free();
        return 0;
    }
    JS_FreeValue(g_ctx, val);

    // 2. Evaluate __bridge helper
    val = JS_Eval(g_ctx, BRIDGE_INIT_SCRIPT, strlen(BRIDGE_INIT_SCRIPT), "bridge.js", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(val)) {
        JSValue exc = JS_GetException(g_ctx);
        const char *err = JS_ToCString(g_ctx, exc);
        fprintf(stderr, "[LegadoBridge Bridge Init Error]: %s\n", err ? err : "unknown");
        JS_FreeCString(g_ctx, err);
        JS_FreeValue(g_ctx, exc);
        JS_FreeValue(g_ctx, val);
        legado_free();
        return 0;
    }
    JS_FreeValue(g_ctx, val);

    // 3. Inject native host hooks (java.ajax / java.createSymmetricCrypto).
    JSValue global = JS_GetGlobalObject(g_ctx);
    if (JS_IsException(global) ||
        set_global_native_function(g_ctx, global, "__legado_native_ajax", js_native_ajax, 3) < 0 ||
        set_global_native_function(g_ctx, global, "__legado_native_crypto", js_native_crypto, 5) < 0 ||
        set_global_native_function(g_ctx, global, "__legado_can_eval_program", js_can_eval_program, 1) < 0 ||
        set_global_native_function(g_ctx, global, "__legado_native_xpath", js_native_xpath, 3) < 0) {
        JS_FreeValue(g_ctx, global);
        legado_free();
        return 0;
    }
    JS_FreeValue(g_ctx, global);

    return 1;
}

void legado_free(void) {
    native_xpath_clear();
    if (g_ctx) {
        JS_FreeContext(g_ctx);
        g_ctx = NULL;
    }
    if (g_rt) {
        JS_FreeRuntime(g_rt);
        g_rt = NULL;
    }
}

void legado_free_string(char* ptr) {
    if (ptr) {
        free(ptr);
    }
}

static char* call_bridge_fn(const char* fn_name, int argc, JSValueConst *argv) {
    if (!g_ctx && !legado_init()) {
        return strdup("");
    }

    JSValue global_obj = JS_GetGlobalObject(g_ctx);
    JSValue bridge_obj = JS_GetPropertyStr(g_ctx, global_obj, "__bridge");
    if (JS_IsUndefined(bridge_obj)) {
        JS_FreeValue(g_ctx, global_obj);
        return strdup("");
    }

    JSValue fn = JS_GetPropertyStr(g_ctx, bridge_obj, fn_name);
    if (!JS_IsFunction(g_ctx, fn)) {
        JS_FreeValue(g_ctx, fn);
        JS_FreeValue(g_ctx, bridge_obj);
        JS_FreeValue(g_ctx, global_obj);
        return strdup("");
    }

    JSValue ret = JS_Call(g_ctx, fn, bridge_obj, argc, argv);
    char *out_str = NULL;
    if (!JS_IsException(ret)) {
        const char *cstr = JS_ToCString(g_ctx, ret);
        if (cstr) {
            out_str = strdup(cstr);
            JS_FreeCString(g_ctx, cstr);
        }
    } else {
        JSValue exc = JS_GetException(g_ctx);
        const char *err = JS_ToCString(g_ctx, exc);
        fprintf(stderr, "[LegadoBridge Error in %s]: %s\n", fn_name, err ? err : "");
        JS_FreeCString(g_ctx, err);
        JS_FreeValue(g_ctx, exc);
    }

    JS_FreeValue(g_ctx, ret);
    JS_FreeValue(g_ctx, fn);
    JS_FreeValue(g_ctx, bridge_obj);
    JS_FreeValue(g_ctx, global_obj);

    native_xpath_clear();
    return out_str ? out_str : strdup("");
}

char* legado_eval(const char* js_code) {
    if (!g_ctx && !legado_init()) {
        return strdup("");
    }
    if (!js_code) return strdup("");

    JSValue val = JS_Eval(g_ctx, js_code, strlen(js_code), "<eval>", JS_EVAL_TYPE_GLOBAL);
    char *res = NULL;
    if (!JS_IsException(val)) {
        const char *cstr = JS_ToCString(g_ctx, val);
        if (cstr) {
            res = strdup(cstr);
            JS_FreeCString(g_ctx, cstr);
        }
    } else {
        JSValue exc = JS_GetException(g_ctx);
        const char *err = JS_ToCString(g_ctx, exc);
        JSValue stack = JS_GetPropertyStr(g_ctx, exc, "stack");
        const char *stk = JS_ToCString(g_ctx, stack);
        fprintf(stderr, "[LegadoBridge Error in legado_eval]: %s\nStack:\n%s\n", err ? err : "", stk ? stk : "");
        JS_FreeCString(g_ctx, stk);
        JS_FreeValue(g_ctx, stack);
        JS_FreeCString(g_ctx, err);
        JS_FreeValue(g_ctx, exc);
    }
    JS_FreeValue(g_ctx, val);
    native_xpath_clear();
    return res ? res : strdup("");
}

char* legado_parse_sources(const char* json_str) {
    if (!g_ctx && !legado_init()) return strdup("[]");
    JSValue arg = JS_NewString(g_ctx, json_str ? json_str : "[]");
    char *res = call_bridge_fn("parseSources", 1, &arg);
    JS_FreeValue(g_ctx, arg);
    return res;
}

char* legado_build_search_req(const char* source_json, const char* keyword, int page) {
    if (!g_ctx && !legado_init()) return strdup("null");
    JSValue args[3];
    args[0] = JS_NewString(g_ctx, source_json ? source_json : "{}");
    args[1] = JS_NewString(g_ctx, keyword ? keyword : "");
    args[2] = JS_NewInt32(g_ctx, page);
    char *res = call_bridge_fn("buildSearchReq", 3, args);
    JS_FreeValue(g_ctx, args[0]);
    JS_FreeValue(g_ctx, args[1]);
    JS_FreeValue(g_ctx, args[2]);
    return res;
}

char* legado_parse_search(const char* source_json, const char* html_or_json, const char* base_url) {
    if (!g_ctx && !legado_init()) return strdup("[]");
    JSValue args[3];
    args[0] = JS_NewString(g_ctx, source_json ? source_json : "{}");
    args[1] = JS_NewString(g_ctx, html_or_json ? html_or_json : "");
    args[2] = JS_NewString(g_ctx, base_url ? base_url : "");
    char *res = call_bridge_fn("parseSearch", 3, args);
    JS_FreeValue(g_ctx, args[0]);
    JS_FreeValue(g_ctx, args[1]);
    JS_FreeValue(g_ctx, args[2]);
    return res;
}

char* legado_parse_book_info(const char* source_json, const char* html_or_json, const char* base_url) {
    if (!g_ctx && !legado_init()) return strdup("{}");
    JSValue args[3];
    args[0] = JS_NewString(g_ctx, source_json ? source_json : "{}");
    args[1] = JS_NewString(g_ctx, html_or_json ? html_or_json : "");
    args[2] = JS_NewString(g_ctx, base_url ? base_url : "");
    char *res = call_bridge_fn("parseBookInfo", 3, args);
    JS_FreeValue(g_ctx, args[0]);
    JS_FreeValue(g_ctx, args[1]);
    JS_FreeValue(g_ctx, args[2]);
    return res;
}

char* legado_parse_explore_categories(const char* explore_url) {
    if (!g_ctx && !legado_init()) return strdup("[]");
    JSValue arg = JS_NewString(g_ctx, explore_url ? explore_url : "");
    char *res = call_bridge_fn("parseExplore", 1, &arg);
    JS_FreeValue(g_ctx, arg);
    return res;
}

char* legado_parse_toc(const char* source_json, const char* html_or_json, const char* base_url) {
    if (!g_ctx && !legado_init()) return strdup("[]");
    JSValue args[3];
    args[0] = JS_NewString(g_ctx, source_json ? source_json : "{}");
    args[1] = JS_NewString(g_ctx, html_or_json ? html_or_json : "");
    args[2] = JS_NewString(g_ctx, base_url ? base_url : "");
    char *res = call_bridge_fn("parseToc", 3, args);
    JS_FreeValue(g_ctx, args[0]);
    JS_FreeValue(g_ctx, args[1]);
    JS_FreeValue(g_ctx, args[2]);
    return res;
}

char* legado_parse_content(const char* source_json, const char* html_or_json, const char* base_url) {
    if (!g_ctx && !legado_init()) return strdup("");
    JSValue args[3];
    args[0] = JS_NewString(g_ctx, source_json ? source_json : "{}");
    args[1] = JS_NewString(g_ctx, html_or_json ? html_or_json : "");
    args[2] = JS_NewString(g_ctx, base_url ? base_url : "");
    char *res = call_bridge_fn("parseContent", 3, args);
    JS_FreeValue(g_ctx, args[0]);
    JS_FreeValue(g_ctx, args[1]);
    JS_FreeValue(g_ctx, args[2]);
    return res;
}
