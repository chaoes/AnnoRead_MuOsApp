#include "native_xpath.h"
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <libxml/HTMLparser.h>
#include <libxml/HTMLtree.h>
#include <libxml/xpath.h>

static htmlDocPtr xpath_cached_doc;
static char *xpath_cached_html;
static size_t xpath_cached_len;

static int set_xpath_string(JSContext *ctx, JSValueConst object,
                            const char *name, const char *value) {
    JSValue string = JS_NewString(ctx, value);
    if (JS_IsException(string)) return -1;
    return JS_SetPropertyStr(ctx, object, name, string);
}

void native_xpath_clear(void) {
    xmlFreeDoc(xpath_cached_doc);
    free(xpath_cached_html);
    xpath_cached_doc = NULL;
    xpath_cached_html = NULL;
    xpath_cached_len = 0;
}

JSValue js_native_xpath(JSContext *ctx, JSValueConst this_val,
                              int argc, JSValueConst *argv) {
    (void)this_val;
    if (argc < 2) return JS_ThrowTypeError(ctx, "XPath requires HTML and expression");
    size_t len = 0;
    const char *html = JS_ToCStringLen(ctx, &len, argv[0]);
    const char *expr = JS_ToCString(ctx, argv[1]);
    const char *path = argc > 2 ? JS_ToCString(ctx, argv[2]) : NULL;
    htmlDocPtr doc = NULL;
    xmlXPathContextPtr xp = NULL;
    xmlXPathObjectPtr selection = NULL, result = NULL;
    JSValue out = JS_UNDEFINED;
    if (!html || !expr || (argc > 2 && !path)) goto exception;
    if (len > 8 * 1024 * 1024 || len > INT_MAX) {
        JS_ThrowRangeError(ctx, "HTML exceeds evaluation limit"); goto exception;
    }
    if (xpath_cached_doc && len == xpath_cached_len &&
        memcmp(html, xpath_cached_html, len) == 0) {
        doc = xpath_cached_doc;
    } else {
        native_xpath_clear();
        doc = htmlReadMemory(html, (int)len, NULL, "UTF-8",
                             HTML_PARSE_NOERROR | HTML_PARSE_NOWARNING | HTML_PARSE_NODEFDTD);
        if (doc) {
            xpath_cached_html = malloc(len + 1);
            if (!xpath_cached_html) {
                xmlFreeDoc(doc); doc = NULL;
                JS_ThrowOutOfMemory(ctx); goto exception;
            }
            memcpy(xpath_cached_html, html, len + 1);
            xpath_cached_len = len;
            xpath_cached_doc = doc;
        }
    }
    if (!doc) { JS_ThrowInternalError(ctx, "HTML parse failed"); goto exception; }
    xp = xmlXPathNewContext(doc);
    if (!xp) { JS_ThrowOutOfMemory(ctx); goto exception; }
    xp->opLimit = 1000000;
    if (path && *path) {
        selection = xmlXPathEvalExpression((const xmlChar *)path, xp);
        if (!selection || selection->type != XPATH_NODESET ||
            !selection->nodesetval || selection->nodesetval->nodeNr != 1) {
            JS_ThrowInternalError(ctx, "XPath context no longer exists"); goto exception;
        }
        xp->node = selection->nodesetval->nodeTab[0];
    }
    result = xmlXPathEvalExpression((const xmlChar *)expr, xp);
    if (!result) { JS_ThrowSyntaxError(ctx, "Invalid or over-limit XPath"); goto exception; }
    out = JS_NewArray(ctx);
    if (JS_IsException(out)) goto cleanup;
    if (result->type == XPATH_NODESET) {
        int count = result->nodesetval ? result->nodesetval->nodeNr : 0;
        for (int i = 0; i < count; i++) {
            xmlNodePtr node = result->nodesetval->nodeTab[i];
            JSValue value;
            if (node->type == XML_ELEMENT_NODE) {
                xmlBufferPtr buf = xmlBufferCreate();
                xmlChar *nodepath = xmlGetNodePath(node);
                xmlChar *text = xmlNodeGetContent(node);
                if (!buf || !nodepath || !text || htmlNodeDump(buf, doc, node) < 0) {
                    if (buf) xmlBufferFree(buf);
                    xmlFree(nodepath); xmlFree(text);
                    JS_ThrowOutOfMemory(ctx); goto exception;
                }
                value = JS_NewObject(ctx);
                if (JS_IsException(value) ||
                    set_xpath_string(ctx, value, "html", (const char *)xmlBufferContent(buf)) < 0 ||
                    set_xpath_string(ctx, value, "path", (const char *)nodepath) < 0 ||
                    set_xpath_string(ctx, value, "text", (const char *)text) < 0) {
                    JS_FreeValue(ctx, value);
                    xmlBufferFree(buf); xmlFree(nodepath); xmlFree(text);
                    goto exception;
                }
                xmlBufferFree(buf); xmlFree(nodepath); xmlFree(text);
            } else if (node->type == XML_ATTRIBUTE_NODE || node->type == XML_TEXT_NODE ||
                       node->type == XML_CDATA_SECTION_NODE || node->type == XML_COMMENT_NODE) {
                xmlChar *text = xmlNodeGetContent(node);
                value = JS_NewString(ctx, text ? (const char *)text : "");
                xmlFree(text);
                if (JS_IsException(value)) { JS_ThrowOutOfMemory(ctx); goto exception; }
            } else {
                JS_ThrowTypeError(ctx, "Unsupported XPath node type in prototype"); goto exception;
            }
            if (JS_IsException(value)) goto exception;
            if (JS_SetPropertyUint32(ctx, out, (uint32_t)i, value) < 0) goto exception;
        }
    } else {
        xmlChar *text = xmlXPathCastToString(result);
        if (!text) { JS_ThrowOutOfMemory(ctx); goto exception; }
        JSValue value = JS_NewString(ctx, (const char *)text);
        xmlFree(text);
        if (JS_IsException(value)) goto exception;
        if (JS_SetPropertyUint32(ctx, out, 0, value) < 0) goto exception;
    }
    goto cleanup;
exception:
    JS_FreeValue(ctx, out);
    out = JS_EXCEPTION;
cleanup:
    xmlXPathFreeObject(result);
    xmlXPathFreeObject(selection);
    xmlXPathFreeContext(xp);
    if (html) JS_FreeCString(ctx, html);
    if (expr) JS_FreeCString(ctx, expr);
    if (path) JS_FreeCString(ctx, path);
    return out;
}
