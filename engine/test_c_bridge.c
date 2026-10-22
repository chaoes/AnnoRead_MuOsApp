#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "legado_bridge.h"

// Fake host callbacks so the ajax/crypto wiring is testable without network.
static char* fake_ajax(const char* url, const char* opts, int timeout) {
    (void)opts; (void)timeout;
    char* r = malloc(strlen(url) + 8);
    sprintf(r, "FAKE:%s", url);
    return r;
}

static char* fake_crypto(const char* algo, const char* key, const char* iv, const char* data, int mode) {
    (void)algo; (void)key; (void)iv; (void)mode;
    char* r = malloc(strlen(data) + 8);
    sprintf(r, "ENC:%s", data);
    return r;
}

int main() {
    printf("=== Testing C Native Bridge with QuickJS & Legado ===\n");

    int ok = legado_init();
    assert(ok == 1);
    printf("✔ legado_init() OK\n");

    // 1. Test eval
    char *eval_res = legado_eval("1 + 2 * 3");
    printf("✔ legado_eval('1 + 2 * 3') = %s\n", eval_res);
    assert(strcmp(eval_res, "7") == 0);
    legado_free_string(eval_res);

    // 2. Test parse BookSource
    const char *source_json = 
    "["
    "  {"
    "    \"bookSourceUrl\": \"https://biquge.com\","
    "    \"bookSourceName\": \"笔趣阁\","
    "    \"searchUrl\": \"https://biquge.com/s?q={{key}}&p={{page}}\","
    "    \"ruleSearch\": {"
    "      \"bookList\": \"div.book-item\","
    "      \"name\": \"h3.title@text\","
    "      \"author\": \"span.author@text\","
    "      \"bookUrl\": \"a@href\""
    "    },"
    "    \"ruleToc\": {"
    "      \"chapterList\": \"ul.list li a\","
    "      \"chapterName\": \"text\","
    "      \"chapterUrl\": \"href\""
    "    },"
    "    \"ruleContent\": {"
    "      \"content\": \"div#content@html\""
    "    }"
    "  }"
    "]";

    char *sources = legado_parse_sources(source_json);
    printf("✔ legado_parse_sources: %s\n", sources);
    assert(strstr(sources, "笔趣阁") != NULL);
    legado_free_string(sources);

    // 3. Test build search request
    const char *single_source = 
    "{"
    "  \"bookSourceUrl\": \"https://biquge.com\","
    "  \"searchUrl\": \"https://biquge.com/s?q={{key}}&p={{page}}, {\\\"method\\\": \\\"POST\\\"}\""
    "}";
    char *req = legado_build_search_req(single_source, "诡秘之主", 1);
    printf("✔ legado_build_search_req: %s\n", req);
    assert(strstr(req, "POST") != NULL);
    assert(strstr(req, "%E8%AF%A1%E7%A7%98%E4%B9%8B%E4%B8%BB") != NULL);
    legado_free_string(req);

    // 4. Test parse search result HTML
    const char *search_source = 
    "{"
    "  \"bookSourceUrl\": \"https://biquge.com\","
    "  \"ruleSearch\": {"
    "    \"bookList\": \"div.book-item\","
    "    \"name\": \"h3.title@text\","
    "    \"author\": \"span.author@text\","
    "    \"bookUrl\": \"a@href\""
    "  }"
    "}";
    const char *html = 
    "<div class=\"book-item\">"
    "  <h3 class=\"title\">《诡秘之主》</h3>"
    "  <span class=\"author\">爱潜水的乌贼</span>"
    "  <a href=\"/book/123/\">阅读</a>"
    "</div>";

    char *books = legado_parse_search(search_source, html, "https://biquge.com");
    printf("✔ legado_parse_search: %s\n", books);
    assert(strstr(books, "诡秘之主") != NULL);
    assert(strstr(books, "爱潜水的乌贼") != NULL);
    legado_free_string(books);

    // 5. Test parse TOC
    const char *toc_source = 
    "{"
    "  \"bookSourceUrl\": \"https://biquge.com\","
    "  \"ruleToc\": {"
    "    \"chapterList\": \"ul.list li a\","
    "    \"chapterName\": \"text\","
    "    \"chapterUrl\": \"href\""
    "  }"
    "}";
    const char *toc_html = 
    "<ul class=\"list\">"
    "  <li><a href=\"/c1.html\">第1章 绯红</a></li>"
    "  <li><a href=\"/c2.html\">第2章 处境</a></li>"
    "</ul>";
    char *chapters = legado_parse_toc(toc_source, toc_html, "https://biquge.com/book/123/");
    printf("✔ legado_parse_toc: %s\n", chapters);
    assert(strstr(chapters, "第1章 绯红") != NULL);
    assert(strstr(chapters, "https://biquge.com/c1.html") != NULL);
    legado_free_string(chapters);

    // 6. Test parse content
    const char *content_source = 
    "{"
    "  \"bookSourceUrl\": \"https://biquge.com\","
    "  \"ruleContent\": {"
    "    \"content\": \"div#content@html\""
    "  }"
    "}";
    const char *content_html = 
    "<div id=\"content\">"
    "  <p>痛！好痛！头好痛！</p>"
    "  <br/>"
    "  <p>周明瑞只觉自己的太阳穴在一跳一跳地发胀疼痛。</p>"
    "</div>";
    char *content = legado_parse_content(content_source, content_html, "https://biquge.com/c1.html");
    printf("✔ legado_parse_content:\n%s\n", content);
    assert(strstr(content, "痛！好痛！") != NULL);
    assert(strstr(content, "周明瑞") != NULL);
    legado_free_string(content);

    // 7. Test java.ajax / java.createSymmetricCrypto native hooks
    legado_set_ajax_callback(fake_ajax);
    legado_set_crypto_callback(fake_crypto);
    char *r1 = legado_eval("java.ajax('http://t/x', 5000)");
    printf("✔ java.ajax hook: %s\n", r1);
    assert(strstr(r1, "FAKE:http://t/x") != NULL);
    legado_free_string(r1);

    char *r2 = legado_eval("String(java.createSymmetricCrypto('AES/CBC/PKCS5Padding','k','v').encryptBase64('p'))");
    printf("✔ java.createSymmetricCrypto hook: %s\n", r2);
    assert(strstr(r2, "ENC:p") != NULL);
    legado_free_string(r2);

    legado_free();
    printf("✔ legado_free() OK\n");

    printf("🎉 ALL C NATIVE BRIDGE TESTS PASSED! 🎉\n");
    return 0;
}
