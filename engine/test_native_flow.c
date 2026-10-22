#include "legado_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static char *quote(const char *s) {
  size_t n = strlen(s);
  char *o = malloc(n * 6 + 3), *p = o;
  *p++ = '"';
  for (; *s; s++) {
    unsigned char c = *s;
    if (c == '"' || c == '\\') {
      *p++ = '\\';
      *p++ = c;
    } else if (c == '\n') {
      *p++ = '\\';
      *p++ = 'n';
    } else if (c == '\r') {
      *p++ = '\\';
      *p++ = 'r';
    } else if (c == '\t') {
      *p++ = '\\';
      *p++ = 't';
    } else if (c < 32) {
      p += sprintf(p, "\\u%04x", c);
    } else
      *p++ = c;
  }
  *p++ = '"';
  *p = 0;
  return o;
}
static void expect(const char *label, char *json, const char *predicate) {
  if (!json) {
    fprintf(stderr, "%s returned null\n", label);
    exit(1);
  }
  char *quoted = quote(json);
  size_t n = strlen(quoted) + strlen(predicate) + 80;
  char *js = malloc(n);
  snprintf(js, n, "(()=>{const x=JSON.parse(%s);return %s})()", quoted,
           predicate);
  char *r = legado_eval(js);
  if (!r || strcmp(r, "true")) {
    fprintf(stderr, "%s failed: %s\nJSON: %s\n", label, r ? r : "null", json);
    exit(1);
  }
  free(quoted);
  free(js);
  legado_free_string(r);
  legado_free_string(json);
}
int main(void) {
  if (!legado_init())
    return 2;
  char *hook = legado_eval("typeof __legado_native_xpath");
  if (!hook || strcmp(hook, "function")) {
    fprintf(stderr, "native XPath hook absent\n");
    return 1;
  }
  legado_free_string(hook);
  const char *ss = "{\"ruleSearch\":{\"bookList\":\"//"
                   "div[@class='book']\",\"name\":\"@XPath:.//a/"
                   "text()\",\"author\":\"@XPath:.//span/"
                   "text()\",\"bookUrl\":\"@XPath:.//a/@href\"}}";
  expect("search",
         legado_parse_search(ss,
                             "<div class='book'><a href='/book/1'>A "
                             "Novel</a><span>Writer</span></div>",
                             "https://ex.test/search"),
         "x.length===1&&x[0].name==='A "
         "Novel'&&x[0].author==='Writer'&&x[0].bookUrl==='https://ex.test/book/"
         "1'");
  const char *ds = "{\"ruleBookInfo\":{\"name\":\"@XPath://h1/"
                   "text()\",\"tocUrl\":\"@XPath://a[@id='toc']/@href\"}}";
  expect("detail",
         legado_parse_book_info(
             ds, "<h1>A Novel</h1><a id='toc' href='/toc/1'>TOC</a>",
             "https://ex.test/book/1"),
         "x.name==='A Novel'&&x.tocUrl==='https://ex.test/toc/1'");
  const char *ts =
      "{\"ruleToc\":{\"chapterList\":\"//li/a\",\"chapterName\":\"@XPath:.//"
      "text()\",\"chapterUrl\":\"@XPath:./@href\",\"nextTocUrl\":\"//"
      "a[@rel='next']/@href\"}}";
  expect("toc page 1",
         legado_parse_toc(ts,
                          "<ul><li><a href='/c1'>Chapter 1</a></li><a "
                          "rel='next' href='/toc/2'>Next</a></ul>",
                          "https://ex.test/toc/1"),
         "x.chapters.length===1&&x.chapters[0].title==='Chapter "
         "1'&&x.chapters[0].url==='https://ex.test/c1'&&x.nextTocUrl==='https:/"
         "/ex.test/toc/2'");
  expect("toc page 2",
         legado_parse_toc(ts, "<ul><li><a href='/c2'>Chapter 2</a></li></ul>",
                          "https://ex.test/toc/2"),
         "x.chapters.length===1&&x.chapters[0].title==='Chapter "
         "2'&&x.chapters[0].url==='https://ex.test/c2'&&x.nextTocUrl===null");
  const char *cs = "{\"ruleContent\":{\"content\":\"@XPath://"
                   "div[@id='content']/p/text()\"}}";
  expect("content paragraphs",
         legado_parse_content(
             cs,
             "<div id='content'><p>Paragraph one.</p><p>Paragraph "
             "two.</p><p>Paragraph three.</p></div>",
             "https://ex.test/c1"),
         "x.content==='Paragraph one.\\nParagraph two.\\nParagraph three.'");
  legado_free();
  puts("Native offline search/detail/two-page TOC/all paragraphs passed");
  return 0;
}
