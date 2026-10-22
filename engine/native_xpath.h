#ifndef LEGADO_NATIVE_XPATH_H
#define LEGADO_NATIVE_XPATH_H
#include "quickjs.h"
void native_xpath_clear(void);
JSValue js_native_xpath(JSContext *, JSValueConst, int, JSValueConst *);
#endif
