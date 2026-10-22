JSON.stringify((() => {
 const R = Legado.RuleAnalyzer;
 if (typeof __legado_native_xpath !== 'function') throw Error('missing native hook');
 const tests = [];
 function check(name, actual, expected) {
   if (JSON.stringify(actual) !== JSON.stringify(expected)) throw Error(name + ': ' + JSON.stringify(actual));
   tests.push(name);
 }
 const html = '<div><i>one</i><i>two</i></div><div><i>three</i><i>four</i></div>';
 check('predicate per parent', R.extractList(html, '//div/i[1]/text()'), ['one','three']);
 check('global grouped predicate', R.extractList(html, '@XPath:(//i)[1]/text()'), ['one']);
 check('multiple predicates', R.extractString('<p class="a">x</p><p class="a">字数：20</p>', "//p[contains(@class,'a')][contains(text(),'字数')]/text()##字数："), '20');
 check('boolean and', R.extractString('<a id="linkNext" href="/p2">下一页</a>', "//*[@id='linkNext' and contains(text(),'下一页')]/@href"), '/p2');
 check('child predicate', R.extractList('<dd>empty</dd><dd><a>x</a></dd>', '//dd[a]').length, 1);
 check('all paragraph text', R.extractString('<div id="content"><p>甲</p><p>乙</p></div>', "//*[@id='content']/p/text()"), '甲\n乙');
 check('direct text distinct from descendants', R.extractList('<p>A<b>B</b>C</p>', '//p/text()'), ['A','C']);
 check('quoted slash', R.extractString('<a href="/a/b">ok</a>', '//a[@href="/a/b"]/text()'), 'ok');
 check('scalar string', R.extractString(html, '@XPath:string(//i[1])'), 'one');
 check('scalar count', R.extractString(html, '@XPath:count(//i)'), '4');
 const rows = R.extractList('<div class="bookbox"><h2>A</h2></div><div class="bookbox"><h2>B</h2></div>', '//div');
 check('context remains per item', rows.map(x=>R.extractString(x, '@XPath:.//h2/text()')), ['A','B']);
 check('parent axis retains document', R.extractString(rows[1], '@XPath:../div[1]/h2/text()'), 'A');
 return {passed:tests.length, tests};
})())