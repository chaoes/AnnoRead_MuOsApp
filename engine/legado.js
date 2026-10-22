/**
 * Legado (开源阅读) 3.0 Rule & BookSource Engine for QuickJS
 * 
 * Reimplemented for QuickJS, Love2D (LuaJIT FFI), Live2D, and Embedded Environments.
 * Implements the Legado rule subset used by supported non-interactive sources.
 * Browser, login, CAPTCHA, and other interactive host APIs remain unsupported.
 */

(function (global) {
    'use strict';

    // =========================================================================
    // 1. Utility Functions & MD5 / Base64 / Entity Decoding
    // =========================================================================

    const HTML_ENTITIES = {
        '&nbsp;': ' ',
        '&lt;': '<',
        '&gt;': '>',
        '&amp;': '&',
        '&quot;': '"',
        '&apos;': "'",
        '&cent;': '¢',
        '&pound;': '£',
        '&yen;': '¥',
        '&euro;': '€',
        '&copy;': '©',
        '&reg;': '®',
        '&mdash;': '—',
        '&ndash;': '–',
        '&ldquo;': '“',
        '&rdquo;': '”',
        '&lsquo;': '‘',
        '&rsquo;': '’',
        '&hellip;': '…'
    };

    function decodeHtmlEntities(str) {
        if (!str || typeof str !== 'string') return '';
        return str
            .replace(/&#(\d+);/g, (_, dec) => String.fromCharCode(parseInt(dec, 10)))
            .replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => String.fromCharCode(parseInt(hex, 16)))
            .replace(/&[a-zA-Z]+;/g, m => HTML_ENTITIES[m] !== undefined ? HTML_ENTITIES[m] : m);
    }

    // Pure JavaScript MD5 Implementation for QuickJS
    function md5(string) {
        function rotateLeft(lValue, iShiftBits) {
            return (lValue << iShiftBits) | (lValue >>> (32 - iShiftBits));
        }
        function addUnsigned(lX, lY) {
            const lX8 = (lX & 0x80000000);
            const lY8 = (lY & 0x80000000);
            const lX4 = (lX & 0x40000000);
            const lY4 = (lY & 0x40000000);
            const lResult = (lX & 0x3FFFFFFF) + (lY & 0x3FFFFFFF);
            if (lX4 & lY4) return (lResult ^ 0x80000000 ^ lX8 ^ lY8);
            if (lX4 | lY4) {
                if (lResult & 0x40000000) return (lResult ^ 0xC0000000 ^ lX8 ^ lY8);
                else return (lResult ^ 0x40000000 ^ lX8 ^ lY8);
            } else {
                return (lResult ^ lX8 ^ lY8);
            }
        }
        function F(x, y, z) { return (x & y) | ((~x) & z); }
        function G(x, y, z) { return (x & z) | (y & (~z)); }
        function H(x, y, z) { return (x ^ y ^ z); }
        function I(x, y, z) { return (y ^ (x | (~z))); }
        function FF(a, b, c, d, x, s, ac) {
            a = addUnsigned(a, addUnsigned(addUnsigned(F(b, c, d), x), ac));
            return addUnsigned(rotateLeft(a, s), b);
        }
        function GG(a, b, c, d, x, s, ac) {
            a = addUnsigned(a, addUnsigned(addUnsigned(G(b, c, d), x), ac));
            return addUnsigned(rotateLeft(a, s), b);
        }
        function HH(a, b, c, d, x, s, ac) {
            a = addUnsigned(a, addUnsigned(addUnsigned(H(b, c, d), x), ac));
            return addUnsigned(rotateLeft(a, s), b);
        }
        function II(a, b, c, d, x, s, ac) {
            a = addUnsigned(a, addUnsigned(addUnsigned(I(b, c, d), x), ac));
            return addUnsigned(rotateLeft(a, s), b);
        }
        function convertToWordArray(string) {
            let lWordCount;
            const lMessageLength = string.length;
            const lNumberOfWords_temp1 = lMessageLength + 8;
            const lNumberOfWords_temp2 = (lNumberOfWords_temp1 - (lNumberOfWords_temp1 % 64)) / 64;
            const lNumberOfWords = (lNumberOfWords_temp2 + 1) * 16;
            const lWordArray = Array(lNumberOfWords - 1);
            let lBytePosition = 0;
            let lByteCount = 0;
            while (lByteCount < lMessageLength) {
                lWordCount = (lByteCount - (lByteCount % 4)) / 4;
                lBytePosition = (lByteCount % 4) * 8;
                lWordArray[lWordCount] = (lWordArray[lWordCount] | (string.charCodeAt(lByteCount) << lBytePosition));
                lByteCount++;
            }
            lWordCount = (lByteCount - (lByteCount % 4)) / 4;
            lBytePosition = (lByteCount % 4) * 8;
            lWordArray[lWordCount] = lWordArray[lWordCount] | (0x80 << lBytePosition);
            lWordArray[lNumberOfWords - 2] = lMessageLength << 3;
            lWordArray[lNumberOfWords - 1] = lMessageLength >>> 29;
            return lWordArray;
        }
        function wordToHex(lValue) {
            let WordToHexValue = "", WordToHexValue_temp = "", lByte, lCount;
            for (lCount = 0; lCount <= 3; lCount++) {
                lByte = (lValue >>> (lCount * 8)) & 255;
                WordToHexValue_temp = "0" + lByte.toString(16);
                WordToHexValue = WordToHexValue + WordToHexValue_temp.substr(WordToHexValue_temp.length - 2, 2);
            }
            return WordToHexValue;
        }
        function utf8Encode(string) {
            string = string.replace(/\r\n/g, "\n");
            let utftext = "";
            for (let n = 0; n < string.length; n++) {
                const c = string.charCodeAt(n);
                if (c < 128) {
                    utftext += String.fromCharCode(c);
                } else if ((c > 127) && (c < 2048)) {
                    utftext += String.fromCharCode((c >> 6) | 192);
                    utftext += String.fromCharCode((c & 63) | 128);
                } else {
                    utftext += String.fromCharCode((c >> 12) | 224);
                    utftext += String.fromCharCode(((c >> 6) & 63) | 128);
                    utftext += String.fromCharCode((c & 63) | 128);
                }
            }
            return utftext;
        }

        const x = convertToWordArray(utf8Encode(String(string || '')));
        let a = 0x67452301, b = 0xEFCDAB89, c = 0x98BADCFE, d = 0x10325476;
        const S11 = 7, S12 = 12, S13 = 17, S14 = 22;
        const S21 = 5, S22 = 9, S23 = 14, S24 = 20;
        const S31 = 4, S32 = 11, S33 = 16, S34 = 23;
        const S41 = 6, S42 = 10, S43 = 15, S44 = 21;

        for (let k = 0; k < x.length; k += 16) {
            const AA = a, BB = b, CC = c, DD = d;
            a = FF(a, b, c, d, x[k + 0], S11, 0xD76AA478);
            d = FF(d, a, b, c, x[k + 1], S12, 0xE8C7B756);
            c = FF(c, d, a, b, x[k + 2], S13, 0x242070DB);
            b = FF(b, c, d, a, x[k + 3], S14, 0xC1BDCEEE);
            a = FF(a, b, c, d, x[k + 4], S11, 0xF57C0FAF);
            d = FF(d, a, b, c, x[k + 5], S12, 0x4787C62A);
            c = FF(c, d, a, b, x[k + 6], S13, 0xA8304613);
            b = FF(b, c, d, a, x[k + 7], S14, 0xFD469501);
            a = FF(a, b, c, d, x[k + 8], S11, 0x698098D8);
            d = FF(d, a, b, c, x[k + 9], S12, 0x8B44F7AF);
            c = FF(c, d, a, b, x[k + 10], S13, 0xFFFF5BB1);
            b = FF(b, c, d, a, x[k + 11], S14, 0x895CD7BE);
            a = FF(a, b, c, d, x[k + 12], S11, 0x6B901122);
            d = FF(d, a, b, c, x[k + 13], S12, 0xFD987193);
            c = FF(c, d, a, b, x[k + 14], S13, 0xA679438E);
            b = FF(b, c, d, a, x[k + 15], S14, 0x49B40821);

            a = GG(a, b, c, d, x[k + 1], S21, 0xF61E2562);
            d = GG(d, a, b, c, x[k + 6], S22, 0xC040B340);
            c = GG(c, d, a, b, x[k + 11], S23, 0x265E5A51);
            b = GG(b, c, d, a, x[k + 0], S24, 0xE9B6C7AA);
            a = GG(a, b, c, d, x[k + 5], S21, 0xD62F105D);
            d = GG(d, a, b, c, x[k + 10], S22, 0x2441453);
            c = GG(c, d, a, b, x[k + 15], S23, 0xD8A1E681);
            b = GG(b, c, d, a, x[k + 4], S24, 0xE7D3FBC8);
            a = GG(a, b, c, d, x[k + 9], S21, 0x21E1CDE6);
            d = GG(d, a, b, c, x[k + 14], S22, 0xC33707D6);
            c = GG(c, d, a, b, x[k + 3], S23, 0xF4D50D87);
            b = GG(b, c, d, a, x[k + 8], S24, 0x455A14ED);
            a = GG(a, b, c, d, x[k + 13], S21, 0xA9E3E905);
            d = GG(d, a, b, c, x[k + 2], S22, 0xFCEFA3F8);
            c = GG(c, d, a, b, x[k + 7], S23, 0x676F02D9);
            b = GG(b, c, d, a, x[k + 12], S24, 0x8D2A4C8A);

            a = HH(a, b, c, d, x[k + 5], S31, 0xFFFA3942);
            d = HH(d, a, b, c, x[k + 8], S32, 0x8771F681);
            c = HH(c, d, a, b, x[k + 11], S33, 0x6D9D6122);
            b = HH(b, c, d, a, x[k + 14], S34, 0xFDE5380C);
            a = HH(a, b, c, d, x[k + 1], S31, 0xA4BEEA44);
            d = HH(d, a, b, c, x[k + 4], S32, 0x4BDECFA9);
            c = HH(c, d, a, b, x[k + 7], S33, 0xF6BB4B60);
            b = HH(b, c, d, a, x[k + 10], S34, 0xBEBFBC70);
            a = HH(a, b, c, d, x[k + 13], S31, 0x289B7EC6);
            d = HH(d, a, b, c, x[k + 0], S32, 0xEAA127FA);
            c = HH(c, d, a, b, x[k + 3], S33, 0xD4EF3085);
            b = HH(b, c, d, a, x[k + 6], S34, 0x4881D05);
            a = HH(a, b, c, d, x[k + 9], S31, 0xD9D4D039);
            d = HH(d, a, b, c, x[k + 12], S32, 0xE6DB99E5);
            c = HH(c, d, a, b, x[k + 15], S33, 0x1FA27CF8);
            b = HH(b, c, d, a, x[k + 2], S34, 0xC4AC5665);

            a = II(a, b, c, d, x[k + 0], S41, 0xF4292244);
            d = II(d, a, b, c, x[k + 7], S42, 0x432AFF97);
            c = II(c, d, a, b, x[k + 14], S43, 0xAB9423A7);
            b = II(b, c, d, a, x[k + 5], S44, 0xFC93A039);
            a = II(a, b, c, d, x[k + 12], S41, 0x655B59C3);
            d = II(d, a, b, c, x[k + 3], S42, 0x8F0CCC92);
            c = II(c, d, a, b, x[k + 10], S43, 0xFFEFF47D);
            b = II(b, c, d, a, x[k + 1], S44, 0x85845DD1);
            a = II(a, b, c, d, x[k + 8], S41, 0x6FA87E4F);
            d = II(d, a, b, c, x[k + 15], S42, 0xFE2CE6E0);
            c = II(c, d, a, b, x[k + 6], S43, 0xA3014314);
            b = II(b, c, d, a, x[k + 13], S44, 0x4E0811A1);
            a = II(a, b, c, d, x[k + 4], S41, 0xF7537E82);
            d = II(d, a, b, c, x[k + 11], S42, 0xBD3AF235);
            c = II(c, d, a, b, x[k + 2], S43, 0x2AD7D2BB);
            b = II(b, c, d, a, x[k + 9], S44, 0xEB86D391);

            a = addUnsigned(a, AA);
            b = addUnsigned(b, BB);
            c = addUnsigned(c, CC);
            d = addUnsigned(d, DD);
        }
        return (wordToHex(a) + wordToHex(b) + wordToHex(c) + wordToHex(d)).toLowerCase();
    }

    // Base64 helper
    const B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    function base64Encode(input) {
        const str = String(input);
        let output = '';
        let chr1, chr2, chr3, enc1, enc2, enc3, enc4;
        let i = 0;
        const utf8Str = unescape(encodeURIComponent(str));
        while (i < utf8Str.length) {
            chr1 = utf8Str.charCodeAt(i++);
            chr2 = utf8Str.charCodeAt(i++);
            chr3 = utf8Str.charCodeAt(i++);
            enc1 = chr1 >> 2;
            enc2 = ((chr1 & 3) << 4) | (chr2 >> 4);
            enc3 = ((chr2 & 15) << 2) | (chr3 >> 6);
            enc4 = chr3 & 63;
            if (isNaN(chr2)) {
                enc3 = enc4 = 64;
            } else if (isNaN(chr3)) {
                enc4 = 64;
            }
            output += B64_CHARS.charAt(enc1) + B64_CHARS.charAt(enc2) +
                      B64_CHARS.charAt(enc3) + B64_CHARS.charAt(enc4);
        }
        return output;
    }

    function base64Decode(input) {
        let output = "";
        let chr1, chr2, chr3;
        let enc1, enc2, enc3, enc4;
        let i = 0;
        input = String(input).replace(/[^A-Za-z0-9\+\/\=]/g, "");
        while (i < input.length) {
            enc1 = B64_CHARS.indexOf(input.charAt(i++));
            enc2 = B64_CHARS.indexOf(input.charAt(i++));
            enc3 = B64_CHARS.indexOf(input.charAt(i++));
            enc4 = B64_CHARS.indexOf(input.charAt(i++));
            chr1 = (enc1 << 2) | (enc2 >> 4);
            chr2 = ((enc2 & 15) << 4) | (enc3 >> 2);
            chr3 = ((enc3 & 3) << 6) | enc4;
            output += String.fromCharCode(chr1);
            if (enc3 !== 64) output += String.fromCharCode(chr2);
            if (enc4 !== 64) output += String.fromCharCode(chr3);
        }
        try {
            return decodeURIComponent(escape(output));
        } catch (e) {
            return output;
        }
    }

    // URL resolution helper
    function resolveUrl(baseUrl, relativeUrl) {
        if (!relativeUrl) return '';
        const trimmed = String(relativeUrl).trim();
        if (!trimmed) return '';
        if (/^(https?:|data:|javascript:|file:)/i.test(trimmed)) return trimmed;
        if (trimmed.startsWith('//')) {
            const protocol = baseUrl.startsWith('https:') ? 'https:' : 'http:';
            return protocol + trimmed;
        }
        if (!baseUrl) return trimmed;

        try {
            const baseMatch = baseUrl.match(/^((https?:)\/\/([^\/?#]+))(\/[^?#]*)?(\?[^#]*)?(#.*)?$/i);
            if (!baseMatch) return baseUrl.replace(/\/+$/, '') + '/' + trimmed.replace(/^\/+/, '');

            const origin = baseMatch[1];
            const basePath = baseMatch[4] || '/';

            if (trimmed.startsWith('/')) {
                return origin + trimmed;
            }

            const dir = basePath.substring(0, basePath.lastIndexOf('/') + 1);
            let fullPath = dir + trimmed;
            const segments = fullPath.split('/');
            const resolvedSegments = [];
            for (const seg of segments) {
                if (seg === '.' || seg === '') {
                    if (resolvedSegments.length === 0) resolvedSegments.push('');
                } else if (seg === '..') {
                    if (resolvedSegments.length > 1) resolvedSegments.pop();
                } else {
                    resolvedSegments.push(seg);
                }
            }
            return origin + resolvedSegments.join('/');
        } catch (e) {
            return baseUrl.replace(/\/+$/, '') + '/' + trimmed.replace(/^\/+/, '');
        }
    }

    // =========================================================================
    // 2. High-Performance HTML / DOM Tree Parser (Pure JS for QuickJS)
    // =========================================================================

    const VOID_TAGS = new Set([
        'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input',
        'link', 'meta', 'param', 'source', 'track', 'wbr'
    ]);

    class JsoupElements extends Array {
        static get [Symbol.species]() { return Array; }
        constructor(nodes) {
            super(...(nodes || []));
        }
        size() { return this.length; }
        isEmpty() { return this.length === 0; }
        get(index) {
            const idx = typeof index === 'number' ? index : parseInt(index, 10);
            const i = idx < 0 ? this.length + idx : idx;
            return (i >= 0 && i < this.length) ? this[i] : null;
        }
        eq(index) {
            const el = this.get(index);
            return new JsoupElements(el ? [el] : []);
        }
        first() { return this.length ? this[0] : null; }
        last() { return this.length ? this[this.length - 1] : null; }
        text() {
            return this.map(node => node.text()).join(' ').replace(/\s+/g, ' ').trim();
        }
        eachText() {
            return this.map(node => node.text().trim()).filter(Boolean);
        }
        attr(name, val) {
            if (val !== undefined) {
                for (const node of this) node.attributes[name.toLowerCase()] = String(val);
                return this;
            }
            return this.length ? this[0].attr(name) : '';
        }
        eachAttr(name) {
            return this.map(node => node.attr(name)).filter(Boolean);
        }
        hasAttr(name) {
            return this.some(node => node.hasAttr(name));
        }
        removeAttr(name) {
            for (const node of this) node.removeAttr(name);
            return this;
        }
        val() { return this.length ? this[0].val() : ''; }
        html(val) {
            if (val !== undefined) {
                for (const node of this) {
                    node.children = [];
                    const subDoc = parseHTML(val);
                    for (const c of subDoc.children) {
                        c.parent = node;
                        node.children.push(c);
                    }
                }
                return this;
            }
            return this.map(node => node.html()).join('');
        }
        outerHtml() {
            return this.map(node => node.outerHtml()).join('\n');
        }
        toString() {
            return this.outerHtml();
        }
        parents() {
            const res = [];
            const seen = new Set();
            for (const node of this) {
                for (const p of node.parents()) {
                    if (!seen.has(p)) {
                        seen.add(p);
                        res.push(p);
                    }
                }
            }
            return new JsoupElements(res);
        }
        parent() {
            const res = [];
            const seen = new Set();
            for (const node of this) {
                const p = node.parent();
                if (p && !seen.has(p)) {
                    seen.add(p);
                    res.push(p);
                }
            }
            return new JsoupElements(res);
        }
        children() {
            const res = [];
            for (const node of this) {
                res.push(...node.children());
            }
            return new JsoupElements(res);
        }
        not(selector) {
            return new JsoupElements(this.filter(node => !matchesSimpleSelector(node, selector)));
        }
        is(selector) {
            return this.some(node => matchesSimpleSelector(node, selector));
        }
        contains(el) {
            return this.includes(el);
        }
        slice(start, end) {
            return new JsoupElements(Array.prototype.slice.call(this, start, end));
        }
        unwrap() {
            for (const node of this) node.unwrap();
            return this;
        }
        remove(index) {
            if (typeof index === 'number') {
                const target = this.get(index);
                if (target) {
                    target.remove();
                    const arrIdx = this.indexOf(target);
                    if (arrIdx !== -1) this.splice(arrIdx, 1);
                }
                return this;
            }
            for (const node of this) node.remove();
            return this;
        }
        empty() {
            for (const node of this) node.empty();
            return this;
        }
        wrap(wrapHtml) {
            for (const node of this) node.wrap(wrapHtml);
            return this;
        }
        toArray() {
            return Array.from(this);
        }
        select(selector) {
            const found = [];
            const seen = new Set();
            for (const node of this) {
                for (const el of node.select(selector)) {
                    if (!seen.has(el)) {
                        seen.add(el);
                        found.push(el);
                    }
                }
            }
            return new JsoupElements(found);
        }
        selectFirst(selector) {
            const list = this.select(selector);
            return list.length > 0 ? list[0] : null;
        }
    }

    class Node {
        constructor(type, name = '') {
            this.nodeType = type; // 1: Element, 3: Text, 8: Comment, 9: Document
            this.tagName = name.toLowerCase();
            this.attributes = {};
            this.children = [];
            this.parent = null;
            this.textValue = '';
        }

        attr(name) {
            if (!name) return '';
            const val = this.attributes[name.toLowerCase()];
            return val !== undefined ? val : '';
        }

        id() { return this.attr('id'); }
        className() { return this.attr('class'); }
        classNames() {
            const cls = this.attr('class');
            return new Set(cls ? cls.split(/\s+/).filter(Boolean) : []);
        }
        tagName() { return this.tagName; }
        hasAttr(name) {
            return !!(name && (name.toLowerCase() in this.attributes));
        }
        removeAttr(name) {
            if (name) delete this.attributes[name.toLowerCase()];
            return this;
        }
        val() { return this.attr('value'); }
        data() {
            let res = '';
            for (let i = 0; i < this.children.length; i++) {
                if (this.children[i].nodeType === 3) res += this.children[i].textValue;
            }
            return res || this.text();
        }
        parent() {
            return (this.parent && this.parent.nodeType === 1) ? this.parent : null;
        }
        parents() {
            const list = [];
            let p = this.parent;
            while (p && p.nodeType === 1) {
                list.push(p);
                p = p.parent;
            }
            return new JsoupElements(list);
        }
        children() {
            return new JsoupElements(this.children.filter(c => c.nodeType === 1));
        }
        child(index) {
            const c = this.children.filter(x => x.nodeType === 1);
            return (index >= 0 && index < c.length) ? c[index] : null;
        }
        childrenSize() {
            return this.children.filter(c => c.nodeType === 1).length;
        }
        nextElementSibling() {
            if (!this.parent) return null;
            const sibs = this.parent.children.filter(c => c.nodeType === 1);
            const idx = sibs.indexOf(this);
            return (idx !== -1 && idx + 1 < sibs.length) ? sibs[idx + 1] : null;
        }
        previousElementSibling() {
            if (!this.parent) return null;
            const sibs = this.parent.children.filter(c => c.nodeType === 1);
            const idx = sibs.indexOf(this);
            return (idx > 0) ? sibs[idx - 1] : null;
        }
        firstElementSibling() {
            if (!this.parent) return this;
            const sibs = this.parent.children.filter(c => c.nodeType === 1);
            return sibs.length > 0 ? sibs[0] : this;
        }
        lastElementSibling() {
            if (!this.parent) return this;
            const sibs = this.parent.children.filter(c => c.nodeType === 1);
            return sibs.length > 0 ? sibs[sibs.length - 1] : this;
        }
        siblingElements() {
            if (!this.parent) return new JsoupElements();
            return new JsoupElements(this.parent.children.filter(c => c.nodeType === 1 && c !== this));
        }
        elementSiblingIndex() {
            if (!this.parent) return 0;
            const sibs = this.parent.children.filter(c => c.nodeType === 1);
            const idx = sibs.indexOf(this);
            return idx === -1 ? 0 : idx;
        }
        is(selector) {
            return matchesSimpleSelector(this, selector);
        }
        matches(selector) {
            return matchesSimpleSelector(this, selector);
        }
        empty() {
            this.children = [];
            return this;
        }
        remove() {
            if (this.parent) {
                const idx = this.parent.children.indexOf(this);
                if (idx !== -1) this.parent.children.splice(idx, 1);
                this.parent = null;
            }
            return this;
        }
        unwrap() {
            if (!this.parent) return this;
            const idx = this.parent.children.indexOf(this);
            if (idx !== -1) {
                for (let i = 0; i < this.children.length; i++) {
                    this.children[i].parent = this.parent;
                }
                this.parent.children.splice(idx, 1, ...this.children);
                this.parent = null;
            }
            return this;
        }
        wrap(wrapHtml) {
            if (!this.parent || !wrapHtml) return this;
            const wrapperDoc = parseHTML(wrapHtml);
            const wrapperEl = wrapperDoc.children.find(c => c.nodeType === 1);
            if (!wrapperEl) return this;
            let deepest = wrapperEl;
            while (deepest.children.some(c => c.nodeType === 1)) {
                deepest = deepest.children.find(c => c.nodeType === 1);
            }
            const idx = this.parent.children.indexOf(this);
            if (idx !== -1) {
                this.parent.children[idx] = wrapperEl;
                wrapperEl.parent = this.parent;
                deepest.children.push(this);
                this.parent = deepest;
            }
            return this;
        }
        getElementById(id) {
            return this.selectFirst('#' + id);
        }
        getElementsByClass(className) {
            return this.select('.' + className);
        }
        getElementsByTag(tagName) {
            return this.select(tagName);
        }
        getElementsByAttribute(attr) {
            return this.select('[' + attr + ']');
        }
        getElementsByAttributeValue(attr, val) {
            return this.select('[' + attr + '="' + val + '"]');
        }
        getElementsContainingOwnText(text) {
            return this.select(':containsOwn(' + text + ')');
        }
        getElementsContainingText(text) {
            return this.select(':contains(' + text + ')');
        }
        getElementsMatchingOwnText(regex) {
            return this.select(':matchesOwn(' + regex + ')');
        }
        getElementsMatchingText(regex) {
            return this.select(':matches(' + regex + ')');
        }

        text() {
            if (this.nodeType === 3) return this.textValue;
            let res = '';
            for (let i = 0; i < this.children.length; i++) {
                res += this.children[i].text();
            }
            return decodeHtmlEntities(res);
        }

        textNodes() {
            const list = [];
            for (let i = 0; i < this.children.length; i++) {
                if (this.children[i].nodeType === 3) {
                    const txt = decodeHtmlEntities(this.children[i].textValue).trim();
                    if (txt) list.push(txt);
                }
            }
            return list.join('\n');
        }

        ownText() {
            let res = '';
            for (let i = 0; i < this.children.length; i++) {
                if (this.children[i].nodeType === 3) {
                    res += this.children[i].textValue;
                }
            }
            return decodeHtmlEntities(res).trim();
        }

        html() {
            let res = '';
            for (let i = 0; i < this.children.length; i++) {
                res += this.children[i].outerHtml();
            }
            return res;
        }

        outerHtml() {
            if (this.nodeType === 3) return this.textValue;
            if (this.nodeType === 8) return `<!--${this.textValue}-->`;
            if (this.nodeType === 9) return this.html();

            let attrs = '';
            for (const [k, v] of Object.entries(this.attributes)) {
                attrs += ` ${k}="${String(v).replace(/"/g, '&quot;')}"`;
            }
            if (VOID_TAGS.has(this.tagName)) {
                return `<${this.tagName}${attrs}>`;
            }
            return `<${this.tagName}${attrs}>${this.html()}</${this.tagName}>`;
        }

        select(selector) {
            return new JsoupElements(querySelectorAll(this, selector));
        }

        selectFirst(selector) {
            const list = this.select(selector);
            return list.length > 0 ? list[0] : null;
        }

        toString() {
            return this.outerHtml();
        }
    }

    function parseHTML(htmlString) {
        if (!htmlString) return new Node(9, '#document');
        const str = String(htmlString);
        const root = new Node(9, '#document');
        let current = root;
        const stack = [root];

        let index = 0;
        const len = str.length;

        while (index < len) {
            const nextTag = str.indexOf('<', index);
            if (nextTag === -1) {
                const text = str.slice(index);
                if (text.length > 0) {
                    const textNode = new Node(3);
                    textNode.textValue = text;
                    textNode.parent = current;
                    current.children.push(textNode);
                }
                break;
            }

            if (nextTag > index) {
                const text = str.slice(index, nextTag);
                const textNode = new Node(3);
                textNode.textValue = text;
                textNode.parent = current;
                current.children.push(textNode);
            }

            // Comment
            if (str.startsWith('<!--', nextTag)) {
                const endComment = str.indexOf('-->', nextTag + 4);
                if (endComment === -1) break;
                index = endComment + 3;
                continue;
            }

            // CDATA
            if (str.startsWith('<![CDATA[', nextTag)) {
                const endCdata = str.indexOf(']]>', nextTag + 9);
                if (endCdata === -1) break;
                const textNode = new Node(3);
                textNode.textValue = str.slice(nextTag + 9, endCdata);
                textNode.parent = current;
                current.children.push(textNode);
                index = endCdata + 3;
                continue;
            }

            // Doctype / XML declaration
            if (str.startsWith('<!', nextTag) || str.startsWith('<?', nextTag)) {
                const endSpecial = str.indexOf('>', nextTag);
                if (endSpecial === -1) break;
                index = endSpecial + 1;
                continue;
            }

            // End tag </tag>
            if (str.startsWith('</', nextTag)) {
                const endClose = str.indexOf('>', nextTag + 2);
                if (endClose === -1) break;
                const tagName = str.slice(nextTag + 2, endClose).trim().toLowerCase().split(/\s+/)[0];
                
                for (let i = stack.length - 1; i > 0; i--) {
                    if (stack[i].tagName === tagName) {
                        stack.splice(i);
                        current = stack[stack.length - 1];
                        break;
                    }
                }
                index = endClose + 1;
                continue;
            }

            // Start tag <tag ...>
            const tagClose = str.indexOf('>', nextTag + 1);
            if (tagClose === -1) break;

            const tagContent = str.slice(nextTag + 1, tagClose).trim();
            const isSelfClosing = tagContent.endsWith('/');
            const cleanContent = isSelfClosing ? tagContent.slice(0, -1).trim() : tagContent;

            const nameMatch = cleanContent.match(/^[a-zA-Z0-9_\-:]+/);
            if (!nameMatch) {
                index = tagClose + 1;
                continue;
            }

            const tagName = nameMatch[0].toLowerCase();
            const elem = new Node(1, tagName);
            elem.parent = current;
            current.children.push(elem);

            const attrPart = cleanContent.slice(tagName.length);
            const attrRegex = /([a-zA-Z0-9_\-:]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
            let m;
            while ((m = attrRegex.exec(attrPart)) !== null) {
                const key = m[1].toLowerCase();
                const val = m[2] !== undefined ? m[2] : (m[3] !== undefined ? m[3] : (m[4] !== undefined ? m[4] : ''));
                elem.attributes[key] = decodeHtmlEntities(val);
            }

            index = tagClose + 1;

            if (tagName === 'script' || tagName === 'style') {
                const endTag = `</${tagName}>`;
                const closePos = str.toLowerCase().indexOf(endTag, index);
                if (closePos !== -1) {
                    const rawContent = str.slice(index, closePos);
                    const txt = new Node(3);
                    txt.textValue = rawContent;
                    txt.parent = elem;
                    elem.children.push(txt);
                    index = closePos + endTag.length;
                    continue;
                }
            }

            if (!isSelfClosing && !VOID_TAGS.has(tagName)) {
                stack.push(elem);
                current = elem;
            }
        }

        return root;
    }

    function jsoupDocument(html) {
        return parseHTML(html);
    }

    // Small explicit adapter for the org.jsoup surface used by the supported
    // non-interactive source rules. It delegates parsing and selectors to this
    // engine's DOM implementation; unsupported Java APIs remain unavailable.
    const jsoupHostApi = {
        jsoup: {
            Jsoup: {
                parse(html, baseUri) { return jsoupDocument(html); },
                parseBodyFragment(html) { return jsoupDocument(html); }
            }
        },
        org: {
            jsoup: {
                Jsoup: {
                    parse(html, baseUri) { return jsoupDocument(html); },
                    parseBodyFragment(html) { return jsoupDocument(html); }
                }
            }
        }
    };

    // =========================================================================
    // 3. CSS Selector & Legado Rule Token Matching Engine
    // =========================================================================

    function matchesSimpleSelector(node, selector) {
        if (!node || node.nodeType !== 1) return false;
        if (!selector || selector === '*') return true;

        let sel = selector.trim();
        sel = sel.replace(/^@css:/i, '').replace(/^tag\./i, '').replace(/^class\./i, '.').replace(/^id\./i, '#');

        // 1. :not(selector)
        const notMatches = [];
        sel = sel.replace(/:not\(\s*([^)]+?)\s*\)/g, (_, inner) => {
            notMatches.push(inner.trim());
            return '';
        });
        for (const inner of notMatches) {
            if (matchesSimpleSelector(node, inner)) return false;
        }

        // 2. :has(selector)
        const hasMatches = [];
        sel = sel.replace(/:has\(\s*([^)]+?)\s*\)/g, (_, inner) => {
            hasMatches.push(inner.trim());
            return '';
        });
        for (const inner of hasMatches) {
            if (node.select(inner).length === 0) return false;
        }

        // 3. :contains(text)
        const containsMatches = [];
        sel = sel.replace(/:contains\(\s*([^)]+?)\s*\)/g, (_, text) => {
            containsMatches.push(text.trim());
            return '';
        });
        for (const txt of containsMatches) {
            if (!node.text().toLowerCase().includes(txt.toLowerCase())) return false;
        }

        // 4. :containsOwn(text)
        const containsOwnMatches = [];
        sel = sel.replace(/:containsOwn\(\s*([^)]+?)\s*\)/g, (_, text) => {
            containsOwnMatches.push(text.trim());
            return '';
        });
        for (const txt of containsOwnMatches) {
            if (!node.ownText().toLowerCase().includes(txt.toLowerCase())) return false;
        }

        // 5. :matches(regex)
        const matchesReg = [];
        sel = sel.replace(/:matches\(\s*([^)]+?)\s*\)/g, (_, pat) => {
            matchesReg.push(pat.trim());
            return '';
        });
        for (const pat of matchesReg) {
            try {
                if (!new RegExp(pat).test(node.text())) return false;
            } catch (e) { return false; }
        }

        // 6. :matchesOwn(regex)
        const matchesOwnReg = [];
        sel = sel.replace(/:matchesOwn\(\s*([^)]+?)\s*\)/g, (_, pat) => {
            matchesOwnReg.push(pat.trim());
            return '';
        });
        for (const pat of matchesOwnReg) {
            try {
                if (!new RegExp(pat).test(node.ownText())) return false;
            } catch (e) { return false; }
        }

        // 7. Structural pseudo classes
        if (sel.includes(':empty')) {
            sel = sel.replace(/:empty/g, '');
            const hasChildEl = node.children.some(c => c.nodeType === 1);
            const hasText = node.children.some(c => c.nodeType === 3 && c.textValue.trim().length > 0);
            if (hasChildEl || hasText) return false;
        }

        if (sel.includes(':root')) {
            sel = sel.replace(/:root/g, '');
            if (node.parent && node.parent.nodeType === 1) return false;
        }

        if (sel.includes(':first-child') || sel.includes(':first')) {
            sel = sel.replace(/:first-child/g, '').replace(/:first/g, '');
            if (!node.parent) return false;
            const sibs = node.parent.children.filter(c => c.nodeType === 1);
            if (sibs[0] !== node) return false;
        }

        if (sel.includes(':last-child') || sel.includes(':last')) {
            sel = sel.replace(/:last-child/g, '').replace(/:last/g, '');
            if (!node.parent) return false;
            const sibs = node.parent.children.filter(c => c.nodeType === 1);
            if (sibs[sibs.length - 1] !== node) return false;
        }

        if (sel.includes(':only-child')) {
            sel = sel.replace(/:only-child/g, '');
            if (!node.parent) return false;
            const sibs = node.parent.children.filter(c => c.nodeType === 1);
            if (sibs.length !== 1) return false;
        }

        if (sel.includes(':first-of-type')) {
            sel = sel.replace(/:first-of-type/g, '');
            if (!node.parent) return false;
            const sibs = node.parent.children.filter(c => c.nodeType === 1 && c.tagName === node.tagName);
            if (sibs[0] !== node) return false;
        }

        if (sel.includes(':last-of-type')) {
            sel = sel.replace(/:last-of-type/g, '');
            if (!node.parent) return false;
            const sibs = node.parent.children.filter(c => c.nodeType === 1 && c.tagName === node.tagName);
            if (sibs[sibs.length - 1] !== node) return false;
        }

        if (sel.includes(':only-of-type')) {
            sel = sel.replace(/:only-of-type/g, '');
            if (!node.parent) return false;
            const sibs = node.parent.children.filter(c => c.nodeType === 1 && c.tagName === node.tagName);
            if (sibs.length !== 1) return false;
        }

        // 8. Attribute selectors
        const attrMatches = [];
        sel = sel.replace(/\[([a-zA-Z0-9_\-:]+)(?:\s*([*^$!~]?=)\s*(?:"([^"]*)"|'([^']*)'|([^\]]*)))?\]/g, (_, attr, op, v1, v2, v3) => {
            const rawVal = v1 !== undefined ? v1 : (v2 !== undefined ? v2 : (v3 !== undefined ? v3.trim() : ''));
            attrMatches.push({ attr: attr.toLowerCase(), op, val: rawVal });
            return '';
        });

        for (const { attr, op, val } of attrMatches) {
            const elemVal = node.attr(attr);
            if (op === undefined) {
                if (!(attr in node.attributes)) return false;
            } else if (op === '=') {
                if (elemVal !== val) return false;
            } else if (op === '!=') {
                if (elemVal === val) return false;
            } else if (op === '^=') {
                if (!elemVal.startsWith(val)) return false;
            } else if (op === '$=') {
                if (!elemVal.endsWith(val)) return false;
            } else if (op === '*=') {
                if (!elemVal.includes(val)) return false;
            } else if (op === '~=') {
                let matched = false;
                try {
                    matched = new RegExp(val).test(elemVal);
                } catch (e) {
                    matched = elemVal.includes(val);
                }
                if (!matched && elemVal.split(/\s+/).includes(val)) {
                    matched = true;
                }
                if (!matched) return false;
            }
        }

        if (sel === '') return true;

        let reqId = null;
        const idMatch = sel.match(/#([a-zA-Z0-9_\-]+)/);
        if (idMatch) {
            reqId = idMatch[1];
            sel = sel.replace(/#[a-zA-Z0-9_\-]+/, '');
        }

        const reqClasses = [];
        sel = sel.replace(/\.([a-zA-Z0-9_\-]+)/g, (_, cls) => {
            reqClasses.push(cls);
            return '';
        });

        const reqTag = sel.trim().toLowerCase();
        if (reqTag && reqTag !== node.tagName) return false;
        if (reqId && node.attr('id') !== reqId) return false;

        if (reqClasses.length > 0) {
            const classAttr = node.attr('class') || '';
            const nodeClasses = new Set(classAttr.split(/\s+/).filter(Boolean));
            for (const c of reqClasses) {
                if (!nodeClasses.has(c)) return false;
            }
        }

        return true;
    }

    function splitSelectorGroups(str) {
        const groups = [];
        let cur = '';
        let inBracket = 0;
        let inParen = 0;
        let quote = null;
        for (let i = 0; i < str.length; i++) {
            const ch = str[i];
            if (quote) {
                cur += ch;
                if (ch === quote && str[i - 1] !== '\\') quote = null;
            } else if (ch === '"' || ch === "'") {
                quote = ch;
                cur += ch;
            } else if (ch === '[') {
                inBracket++;
                cur += ch;
            } else if (ch === ']') {
                inBracket = Math.max(0, inBracket - 1);
                cur += ch;
            } else if (ch === '(') {
                inParen++;
                cur += ch;
            } else if (ch === ')') {
                inParen = Math.max(0, inParen - 1);
                cur += ch;
            } else if (inBracket === 0 && inParen === 0 && ch === ',') {
                if (cur.trim()) groups.push(cur.trim());
                cur = '';
            } else {
                cur += ch;
            }
        }
        if (cur.trim()) groups.push(cur.trim());
        return groups;
    }

    function tokenizeCss(selectorStr) {
        const tokens = [];
        let cur = '';
        let inBracket = 0;
        let inParen = 0;
        let quote = null;
        for (let i = 0; i < selectorStr.length; i++) {
            const ch = selectorStr[i];
            if (quote) {
                cur += ch;
                if (ch === quote && selectorStr[i - 1] !== '\\') quote = null;
            } else if (ch === '"' || ch === "'") {
                quote = ch;
                cur += ch;
            } else if (ch === '[') {
                inBracket++;
                cur += ch;
            } else if (ch === ']') {
                inBracket = Math.max(0, inBracket - 1);
                cur += ch;
            } else if (ch === '(') {
                inParen++;
                cur += ch;
            } else if (ch === ')') {
                inParen = Math.max(0, inParen - 1);
                cur += ch;
            } else if (inBracket === 0 && inParen === 0) {
                if (ch === '>' || ch === '+' || ch === '~') {
                    if (cur.trim()) tokens.push(cur.trim());
                    tokens.push(ch);
                    cur = '';
                } else if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
                    if (cur.trim()) {
                        tokens.push(cur.trim());
                        cur = '';
                    }
                } else {
                    cur += ch;
                }
            } else {
                cur += ch;
            }
        }
        if (cur.trim()) tokens.push(cur.trim());
        return tokens;
    }

    function collectDescendants(parent, matcher, maxDepth = 999) {
        const results = [];
        function walk(node, depth) {
            if (depth > maxDepth) return;
            for (let i = 0; i < node.children.length; i++) {
                const child = node.children[i];
                if (child.nodeType === 1) {
                    if (matcher(child)) results.push(child);
                    walk(child, depth + 1);
                }
            }
        }
        walk(parent, 1);
        return results;
    }

    function nthChildMatches(expression, position) {
        const expr = String(expression).replace(/\s+/g, '').toLowerCase();
        if (expr === 'odd') return position % 2 === 1;
        if (expr === 'even') return position % 2 === 0;
        if (/^[+-]?\d+$/.test(expr)) return position === parseInt(expr, 10);
        const match = expr.match(/^([+-]?\d*)n([+-]\d+)?$/);
        if (!match) return false;
        const aText = match[1];
        const a = aText === '' || aText === '+' ? 1 : aText === '-' ? -1 : parseInt(aText, 10);
        const b = parseInt(match[2] || '0', 10);
        if (a === 0) return position === b;
        const n = (position - b) / a;
        return Number.isInteger(n) && n >= 0;
    }

    function querySelectorAll(root, selectorStr) {
        if (!selectorStr) return new JsoupElements([root]);
        const trimmed = selectorStr.trim();
        if (!trimmed) return new JsoupElements([root]);

        const groups = splitSelectorGroups(trimmed);
        if (groups.length > 1) {
            const resultSet = new Set();
            for (const part of groups) {
                const sub = querySelectorAll(root, part);
                for (const el of sub) resultSet.add(el);
            }
            return new JsoupElements(Array.from(resultSet));
        }

        const tokens = tokenizeCss(trimmed);
        let currentCandidates = [root];

        let combinator = ' ';
        for (let i = 0; i < tokens.length; i++) {
            const tok = tokens[i];
            if (tok === '>') {
                combinator = '>';
                continue;
            }
            if (tok === '+') {
                combinator = '+';
                continue;
            }
            if (tok === '~') {
                combinator = '~';
                continue;
            }

            const sliceMatch = tok.match(/\[\s*(-?\d*)\s*:\s*(-?\d*)\s*\]/);
            const indexMatch = !sliceMatch && tok.match(/\[\s*(-?\d+)\s*\]/);

            const eqMatch = tok.match(/:eq\(\s*(-?\d+)\s*\)/i);
            const gtMatch = tok.match(/:gt\(\s*(\d+)\s*\)/i);
            const ltMatch = tok.match(/:lt\(\s*(\d+)\s*\)/i);
            const nthMatch = tok.match(/:nth-child\(\s*([^)]*?)\s*\)/i);

            let baseTok = tok;
            if (sliceMatch) baseTok = baseTok.replace(/\[\s*(-?\d*)\s*:\s*(-?\d*)\s*\]/, '');
            if (indexMatch) baseTok = baseTok.replace(/\[\s*(-?\d+)\s*\]/, '');
            if (eqMatch) baseTok = baseTok.replace(/:eq\(\s*-?\d+\s*\)/i, '');
            if (gtMatch) baseTok = baseTok.replace(/:gt\(\s*\d+\s*\)/i, '');
            if (ltMatch) baseTok = baseTok.replace(/:lt\(\s*\d+\s*\)/i, '');
            if (nthMatch) baseTok = baseTok.replace(/:nth-child\(\s*[^)]*?\s*\)/i, '');

            const nextCandidates = [];
            for (const parent of currentCandidates) {
                let matched = [];
                if (combinator === '>') {
                    for (const child of parent.children) {
                        if (child.nodeType === 1 && matchesSimpleSelector(child, baseTok)) {
                            matched.push(child);
                        }
                    }
                } else if (combinator === '+') {
                    const nextSib = parent.nextElementSibling ? parent.nextElementSibling() : null;
                    if (nextSib && matchesSimpleSelector(nextSib, baseTok)) {
                        matched.push(nextSib);
                    }
                } else if (combinator === '~') {
                    let cur = parent.nextElementSibling ? parent.nextElementSibling() : null;
                    while (cur) {
                        if (matchesSimpleSelector(cur, baseTok)) matched.push(cur);
                        cur = cur.nextElementSibling ? cur.nextElementSibling() : null;
                    }
                } else {
                    matched = collectDescendants(parent, el => matchesSimpleSelector(el, baseTok));
                    if (parent.nodeType === 1 && matchesSimpleSelector(parent, baseTok)) {
                        matched.unshift(parent);
                    }
                }

                if (nthMatch) {
                    matched = matched.filter(el => {
                        const siblings = el.parent ? el.parent.children.filter(child => child.nodeType === 1) : [];
                        return nthChildMatches(nthMatch[1], siblings.indexOf(el) + 1);
                    });
                }
                if (sliceMatch) {
                    const start = sliceMatch[1] !== '' ? parseInt(sliceMatch[1], 10) : 0;
                    const end = sliceMatch[2] !== '' ? parseInt(sliceMatch[2], 10) : undefined;
                    matched = matched.slice(start, end);
                }
                if (indexMatch) {
                    let idx = parseInt(indexMatch[1], 10);
                    if (idx < 0) idx = matched.length + idx;
                    matched = (idx >= 0 && idx < matched.length) ? [matched[idx]] : [];
                }
                if (eqMatch) {
                    let eqIndex = parseInt(eqMatch[1], 10);
                    if (eqIndex < 0) eqIndex = matched.length + eqIndex;
                    matched = (eqIndex >= 0 && eqIndex < matched.length) ? [matched[eqIndex]] : [];
                }
                if (gtMatch) {
                    const gtIndex = parseInt(gtMatch[1], 10);
                    matched = matched.filter((_, idx) => idx > gtIndex);
                }
                if (ltMatch) {
                    const ltIndex = parseInt(ltMatch[1], 10);
                    matched = matched.filter((_, idx) => idx < ltIndex);
                }

                for (const m of matched) nextCandidates.push(m);
            }
            currentCandidates = nextCandidates;
            combinator = ' ';
        }

        return new JsoupElements(currentCandidates);
    }

    // =========================================================================
    // 3.5 Embedded XPath 1.0 Evaluator for HTML DOM (Legado // and @XPath:)
    // =========================================================================

    function evaluateNativeXPath(target, expr) {
        if (!target || (!(target instanceof Node) && typeof target !== 'string')) return [];
        const document = target instanceof Node && target.__xpathDocument
            ? target.__xpathDocument : {html: typeof target === 'string' ? target : (target && typeof target.outerHtml === 'function' ? target.outerHtml() : '')};
        const path = target instanceof Node ? (target.__xpathPath || '') : '';
        const rows = globalThis.__legado_native_xpath(document.html,
            expr.replace(/^@xpath:/i, '').trim(), path);
        return rows.map(row => {
            if (typeof row === 'string') return row;
            const node = parseHTML(row.html).children.find(child => child.nodeType === 1);
            if (!node) throw new Error('Cannot adapt native XPath element');
            node.__xpathDocument = document;
            node.__xpathPath = row.path;
            node.text = () => row.text;
            return node;
        });
    }

    function evaluateXPath(rootNode, xpathExpr) {
        if (!rootNode || !xpathExpr) return [];
        let expr = xpathExpr.trim().replace(/^@xpath:/i, '');
        // XPath expressions used on a matched element commonly start with
        // `.//` to make the query relative to that element.
        expr = expr.replace(/^\.\//, '');
        if (!expr.startsWith('//') && !expr.startsWith('/')) return [];

        let extractAttr = null;
        let extractText = false;
        let extractAllText = false;
        let extractDirectText = false;

        // Check tail extraction: /@href, /@src, /text()
        const allTextTail = /\/\/text\(\)(?=$)/i;
        const textTail = /\/text\(\)$/i;
        const directTextTail = /\/text\(\)\[(\d+)\]$/i;
        const attrTail = /\/@([a-zA-Z0-9_\-]+)$/i;

        const directTextMatch = expr.match(directTextTail);
        if (allTextTail.test(expr)) {
            extractAllText = true;
            expr = expr.replace(allTextTail, '');
        } else if (directTextMatch) {
            extractDirectText = true;
            expr = expr.replace(directTextTail, '');
        } else if (textTail.test(expr)) {
            extractText = true;
            expr = expr.replace(textTail, '');
        } else {
            const m = expr.match(attrTail);
            if (m) {
                extractAttr = m[1].toLowerCase();
                expr = expr.replace(attrTail, '');
            }
        }

        // Tokenize into steps: each step has isDescendant (true for //, false for /) and seg
        const steps = [];
        let p = 0;
        const len = expr.length;
        while (p < len) {
            let isDesc = false;
            if (expr.substr(p, 2) === '//') {
                isDesc = true;
                p += 2;
            } else if (expr.charAt(p) === '/') {
                isDesc = false;
                p += 1;
            } else if (p === 0) {
                isDesc = false;
            } else {
                break;
            }

            const textFunction = expr.indexOf('text()', p) === p || expr.indexOf('text()[', p) === p;
            let nextSlash = textFunction ? -1 : expr.indexOf('/', p);
            let seg = '';
            if (nextSlash === -1) {
                seg = expr.slice(p);
                p = len;
            } else {
                seg = expr.slice(p, nextSlash);
                p = nextSlash;
            }
            if (seg.length > 0) {
                steps.push({ isDesc, seg });
            }
        }

        let currentNodes = [rootNode];

        for (let i = 0; i < steps.length; i++) {
            const step = steps[i];
            const nextNodes = [];

            // Parse tag (including namespace colon) and optional predicate [@attr="val"] or [position()]
            const predMatch = step.seg.match(/^([a-zA-Z0-9_\-:\*]+)(?:\[(.*)\])?$/);
            if (!predMatch) {
                // Malformed syntax: do not default to *; fail safe
                return [];
            }

            const tag = predMatch[1].toLowerCase();
            let predAttr = null;
            let predVal = null;
            let predPos = -1;
            let containsAttr = null;
            let containsVal = null;
            let containsText = null;

            const pred = predMatch[2];
            const positionMatch = pred && pred.match(/^(.*)\[(\d+)\]$/);
            const nodePred = positionMatch ? positionMatch[1] : pred;
            const nodePosition = positionMatch ? parseInt(positionMatch[2], 10) : null;
            const indexOnLastDescendant = nodePosition !== null && nodePred === '';
            if (nodePred) {
                const attrM = nodePred.match(/^@([a-zA-Z0-9_\-]+)\s*=\s*['"]([^'"]*)['"]$/);
                const containsM = nodePred.match(/^contains\(\s*@([a-zA-Z0-9_\-]+)\s*,\s*['"]([^'"]*)['"]\s*\)$/i);
                const containsTextM = nodePred.match(/^contains\(\s*text\(\)\s*,\s*['"]([^'"]*)['"]\s*\)$/i);
                if (attrM) {
                    predAttr = attrM[1].toLowerCase();
                    predVal = attrM[2];
                } else if (containsM) {
                    containsAttr = containsM[1].toLowerCase();
                    containsVal = containsM[2];
                } else if (containsTextM) {
                    containsText = containsTextM[1];
                } else if (/^\d+$/.test(nodePred)) predPos = parseInt(nodePred, 10);
            }

            const matcher = (node) => {
                if (!node || node.nodeType !== 1) return false;
                if (tag !== '*' && node.tagName !== tag) return false;
                if (predAttr !== null) {
                    const v = node.attr(predAttr);
                    if (v !== predVal) return false;
                }
                if (containsAttr !== null) {
                    const v = node.attr(containsAttr) || '';
                    if (!v.includes(containsVal)) return false;
                }
                if (containsText !== null && !node.text().includes(containsText)) return false;
                return true;
            };

            let candidates = [];
            for (const parent of currentNodes) {
                let parentCandidates = [];
                if (step.isDesc || parent === rootNode) {
                    parentCandidates = collectDescendants(parent, matcher);
                } else {
                    // Direct child only
                    for (let c = 0; c < parent.children.length; c++) {
                        const child = parent.children[c];
                        if (matcher(child)) parentCandidates.push(child);
                    }
                }
                candidates.push(...parentCandidates);
            }
            if (nodePosition !== null && !step.isDesc && nodePred) {
                const filtered = candidates.filter(matcher);
                if (nodePosition > 0 && nodePosition <= filtered.length) nextNodes.push(filtered[nodePosition - 1]);
                currentNodes = nextNodes;
                if (currentNodes.length === 0) break;
                continue;
            }
            if (nodePosition !== null && nodePred !== '') {
                const eligible = candidates.filter(matcher);
                if (nodePosition > 0 && nodePosition <= eligible.length) nextNodes.push(eligible[nodePosition - 1]);
            } else if (indexOnLastDescendant) {
                if (nodePosition > 0 && nodePosition <= candidates.length) nextNodes.push(candidates[nodePosition - 1]);
            } else if (/^\d+$/.test(pred || '')) {
                if (predPos > 0 && predPos <= candidates.length) nextNodes.push(candidates[predPos - 1]);
            } else {
                nextNodes.push(...candidates);
            }

            currentNodes = nextNodes;
            if (currentNodes.length === 0) break;
        }

        if (extractText) {
            return currentNodes.map(n => n.text ? n.text().trim() : '');
        }
        if (extractAllText) {
            const out = [];
            const visit = (node) => {
                if (!node || !Array.isArray(node.children)) return;
                for (const child of node.children) {
                    if (child.nodeType === 3) {
                        const text = decodeHtmlEntities(child.textValue).trim();
                        if (text) out.push(text);
                    } else if (child.nodeType === 1) visit(child);
                }
            };
            for (const node of currentNodes) visit(node);
            return out;
        }
        if (extractDirectText) {
            const index = Math.max(0, parseInt(directTextMatch[1], 10) - 1);
            return currentNodes.map(n => {
                if (!n || !Array.isArray(n.children)) return '';
                const texts = n.children.filter(c => c.nodeType === 3 && c.textValue.trim());
                const node = texts[index];
                return node ? decodeHtmlEntities(node.textValue).trim() : '';
            });
        }
        if (extractAttr !== null) {
            return currentNodes.map(n => n.attr ? (n.attr(extractAttr) || '') : '');
        }

        return currentNodes;
    }

    // =========================================================================
    // 4. Legado RuleAnalyzer (CSS, @ Chaining, Indexing, Direct Attrs, Regex, JS)
    // =========================================================================

    const DIRECT_ATTRS = new Set([
        'text', 'textnodes', 'owntext', 'all', 'html', 'href', 'src', 'content', 'title', 'alt', 'value'
    ]);

    function parseTokenAndIndex(token) {
        const trimmed = token.trim();
        // Legado slice e.g. .item[0:9] or [1:-1]
        const sliceMatch = trimmed.match(/^(.*)\[\s*(-?\d*)\s*:\s*(-?\d*)\s*\]$/);
        if (sliceMatch) {
            return { selector: sliceMatch[1].trim(), indexOp: 'slice:' + (sliceMatch[2] || '') + ':' + (sliceMatch[3] || '') };
        }
        // Legado index e.g. .item[0] or [-1]
        const bracketIndexMatch = trimmed.match(/^(.*)\[\s*(-?\d+)\s*\]$/);
        if (bracketIndexMatch) {
            return { selector: bracketIndexMatch[1].trim(), indexOp: bracketIndexMatch[2].trim() };
        }
        if (trimmed.includes('!')) {
            const parts = trimmed.split('!');
            return { selector: parts[0].trim(), indexOp: '!' + parts[1].trim() };
        }
        const match = trimmed.match(/^(.*)\.(-?\d+)$/);
        if (match) {
            return { selector: match[1].trim(), indexOp: match[2].trim() };
        }
        return { selector: trimmed, indexOp: null };
    }

    function applyIndexOp(elements, indexOp) {
        if (!elements || elements.length === 0 || !indexOp) return elements;

        if (indexOp.startsWith('slice:')) {
            const parts = indexOp.split(':');
            const sStart = parts[1] !== '' ? parseInt(parts[1], 10) : 0;
            const sEnd = parts[2] !== '' ? parseInt(parts[2], 10) : undefined;
            return elements.slice(sStart, sEnd);
        }

        if (indexOp.startsWith('!')) {
            let skipIndex = parseInt(indexOp.slice(1), 10) || 0;
            if (skipIndex < 0) skipIndex = elements.length + skipIndex;
            return elements.filter((_, idx) => idx !== skipIndex);
        }

        const idx = parseInt(indexOp, 10);
        if (isNaN(idx)) return elements;

        if (idx < 0) {
            const realIdx = elements.length + idx;
            return realIdx >= 0 && realIdx < elements.length ? [elements[realIdx]] : [];
        } else {
            return idx >= 0 && idx < elements.length ? [elements[idx]] : [];
        }
    }

    function cleanCssSelector(sel) {
        return sel
            .replace(/^@?css:/i, '')
            .replace(/^class\./i, '.')
            .replace(/^id\./i, '#')
            .replace(/^tag\./i, '')
            .trim();
    }

    function extractAttrFromElement(el, attrName) {
        if (!el) return '';
        const lower = attrName.toLowerCase();
        switch (lower) {
            case 'text':
                return el.text().trim();
            case 'textnodes':
                return el.textNodes();
            case 'owntext':
                return el.ownText();
            case 'all':
                return el.outerHtml();
            case 'html':
                return el.html().trim();
            case 'href':
                return el.attr('href');
            case 'src':
                return el.attr('src');
            case 'content':
                return el.attr('content') || el.attr('value');
            case 'title':
                return el.attr('title');
            case 'alt':
                return el.attr('alt');
            case 'value':
                return el.attr('value');
            default:
                return el.attr(lower) || el.text().trim();
        }
    }

    // AllInOne regex list rule: ":pattern" with optional "##replacement##".
    // Each global match becomes an object exposing $1..$n, so follow-up rules
    // like chapterName: "$2" / chapterUrl: "$1" can pull capture groups.
    function extractAllInOneRegex(html, patternStr) {
        let pattern = patternStr;
        let replacement = null;

        const parts = pattern.split('##');
        pattern = parts[0];
        if (parts.length >= 2) replacement = parts[1];

        const results = [];
        let reg;
        try {
            reg = new RegExp(pattern, 'g');
        } catch (e) {
            return results;
        }

        let m;
        while ((m = reg.exec(html)) !== null) {
            if (m[0] === '') { reg.lastIndex++; continue; }
            const item = { $0: m[0] };
            for (let i = 1; i < m.length; i++) {
                item['$' + i] = m[i] !== undefined ? m[i] : '';
            }
            if (replacement !== null) {
                item.$0 = m[0].replace(new RegExp(pattern), replacement);
            }
            item.toString = function () { return this.$1 !== undefined ? this.$1 : this.$0; };
            results.push(item);
        }
        return results;
    }

    // '%%' interleave: take 1st of each list, then 2nd of each, ...
    function interleaveLists(lists) {
        const out = [];
        let maxLen = 0;
        for (const l of lists) maxLen = Math.max(maxLen, l.length);
        for (let i = 0; i < maxLen; i++) {
            for (const l of lists) {
                if (i < l.length) out.push(l[i]);
            }
        }
        return out;
    }

    function splitTopLevelCommas(text) {
        const parts = [];
        let start = 0;
        let quote = '';
        let escaped = false;
        let squareDepth = 0;
        for (let i = 0; i < text.length; i++) {
            const c = text[i];
            if (quote) {
                if (escaped) escaped = false;
                else if (c === '\\') escaped = true;
                else if (c === quote) quote = '';
                continue;
            }
            if (c === '"' || c === "'") quote = c;
            else if (c === '[') squareDepth++;
            else if (c === ']') squareDepth = Math.max(0, squareDepth - 1);
            else if (c === ',' && squareDepth === 0) {
                parts.push(text.slice(start, i).trim());
                start = i + 1;
            }
        }
        const tail = text.slice(start).trim();
        if (tail) parts.push(tail);
        return parts;
    }

    function splitJsRule(rule) {
        const text = String(rule || '').trim();
        if (text.startsWith('@js:')) return { script: text.slice(4).trim(), suffix: '' };
        const start = text.indexOf('<js>');
        if (start < 0) return null;
        const end = text.indexOf('</js>', start + 4);
        if (end < 0) return null;
        return {
            prefix: text.slice(0, start).trim(),
            script: text.slice(start + 4, end).trim(),
            suffix: text.slice(end + 5).trim()
        };
    }

    function splitTopLevelAlts(rule) {
        if (!rule) return [];
        const trimmed = String(rule).trim();
        if (trimmed.startsWith('@js:') || (trimmed.startsWith('<js>') && trimmed.endsWith('</js>'))) {
            return [trimmed];
        }
        const jsIdx = trimmed.indexOf('@js:');
        const jsTagIdx = trimmed.indexOf('<js>');
        let cutoff = trimmed.length;
        if (jsIdx !== -1) cutoff = Math.min(cutoff, jsIdx);
        if (jsTagIdx !== -1) cutoff = Math.min(cutoff, jsTagIdx);

        const beforeJs = trimmed.slice(0, cutoff);
        if (beforeJs.includes('||')) {
            const parts = beforeJs.split('||');
            const lastPart = parts.pop() + trimmed.slice(cutoff);
            parts.push(lastPart);
            return parts.map(p => p.trim()).filter(Boolean);
        }
        return [trimmed];
    }

    class RuleAnalyzer {
        /**
         * Extract a list of Elements or Items using Legado 3.0 rule syntax:
         * - '||' fallback alternatives
         * - JS blocks: @js:... or <js>...</js> returning Array
         * - JSONPath: $.data.list, @json:data.list
         * - '@' hierarchy chaining (e.g. table@tr@td@a)
         * - Index filters (e.g. tr!0, a.-1, p.0)
         * - Standard CSS selectors
         */
        static _variables = {};

        static extractList(target, rule, baseUrl = '', variables = {}) {
            if (!target) return [];
            if (!rule || !rule.trim()) {
                return Array.isArray(target) ? target : [target];
            }

            // Leading '-' reverses the resulting list (used by inverted TOCs).
            // It may precede either a CSS chain or an AllInOne `:pattern`.
            const rawRule = String(rule).trim();
            const reversed = rawRule.startsWith('-');
            const effectiveRule = reversed ? rawRule.slice(1).trim() : rawRule;
            const finish = (list) => {
                if (reversed && Array.isArray(list)) return list.slice().reverse();
                return list;
            };

            const alts = splitTopLevelAlts(effectiveRule);
            if (alts.length > 1) {
                for (const alt of alts) {
                    const subList = RuleAnalyzer.extractList(target, alt, baseUrl, variables);
                    if (subList.length > 0) return finish(subList);
                }
                return [];
            }

            const trimmed = alts[0] || '';

            // '%%' interleave across sub-rules (e.g. "a@text%%b@text").
            if (trimmed.includes('%%')) {
                const parts = trimmed.split('%%').map(p => p.trim()).filter(Boolean);
                if (parts.length > 1) {
                    const lists = parts.map(p => RuleAnalyzer.extractList(target, p, baseUrl, variables));
                    const merged = interleaveLists(lists);
                    // Scalar contexts want the joined text; list contexts want the array.
                    return finish(merged);
                }
            }

            // AllInOne regex list rule: ":pattern" (but not "://host" URLs).
            if (trimmed.startsWith(':') && !trimmed.startsWith('://')) {
                return finish(extractAllInOneRegex(String(target), trimmed.slice(1)));
            }

            // A rule can select JSON/HTML values first, then transform them in
            // a JS stage, and optionally continue with another selector.
            const jsRule = splitJsRule(trimmed);
            if (jsRule) {
                const prefixResult = jsRule.prefix
                    ? RuleAnalyzer.extractList(target, jsRule.prefix, baseUrl, variables)
                    : target;
                const evalVal = evalLegadoScript(jsRule.script, prefixResult, baseUrl, variables);
                if (jsRule.suffix) return finish(RuleAnalyzer.extractList(evalVal, jsRule.suffix, baseUrl, variables));
                if (Array.isArray(evalVal)) return finish(evalVal);
                if (evalVal) return finish([evalVal]);
                return [];
            }

            // 1.5. XPath list evaluation (starts with // or @XPath:)
            if (trimmed.startsWith('//') || trimmed.startsWith('/') || /^@xpath:/i.test(trimmed)) {
                if (typeof globalThis.__legado_native_xpath === 'function')
                    return finish(evaluateNativeXPath(target, trimmed));
                let elem = target;
                if (typeof target === 'string') elem = parseHTML(target);
                if (elem instanceof Node) {
                    return finish(evaluateXPath(elem, trimmed));
                }
                return [];
            }

            // 3. JSONPath list evaluation
            if (trimmed.startsWith('$.') || trimmed.startsWith('@json:') ||
                (/^\.[\w$]+(?:\.[\w$]+|\[\*\]|\[\d+\])*$/.test(trimmed) && typeof target === 'string' && /^[\s]*[\[{]/.test(target)) ||
                (typeof target === 'object' && !(target instanceof Node))) {
                const extracted = RuleAnalyzer.extractFromJson(target, trimmed);
                if (Array.isArray(extracted)) return finish(extracted);
                if (extracted && typeof extracted === 'object') {
                    if (Array.isArray(extracted.list)) return finish(extracted.list);
                    return finish([extracted]);
                }
                if (typeof extracted === 'string') {
                    try {
                        const parsed = JSON.parse(extracted);
                        if (Array.isArray(parsed)) return finish(parsed);
                    } catch (e) {}
                }
            }

            // 4. HTML / DOM element list evaluation
            let elem = target;
            if (typeof target === 'string') {
                elem = parseHTML(target);
            }
            if (!(elem instanceof Node)) return [];

            return finish(RuleAnalyzer.extractSingleList(elem, trimmed));
        }

        static extractSingleList(element, rawRule) {
            if (!rawRule) return [element];
            const cleanRule = rawRule.replace(/^@css:/i, '').trim();

            // jsoup `children` — all direct child elements.
            if (cleanRule.toLowerCase() === 'children') {
                return element.children.filter(c => c.nodeType === 1);
            }

            // Hierarchy @ chaining
            if (cleanRule.includes('@')) {
                const tokens = cleanRule.split('@');
                let currentElements = [element];
                const tokenList = tokens.map(t => t.trim()).filter(Boolean);

                // Trailing attribute token (e.g. `tag.li@tag.a@text`) extracts
                // a value from each matched element instead of selecting further.
                let trailingAttr = null;
                const lastTok = tokenList.length > 0 ? tokenList[tokenList.length - 1] : '';
                const lowerLast = lastTok.toLowerCase();
                if (DIRECT_ATTRS.has(lowerLast)) {
                    trailingAttr = lowerLast;
                    tokenList.pop();
                } else if (lowerLast.startsWith('attr.')) {
                    trailingAttr = lowerLast.replace(/^attr\./, '');
                    tokenList.pop();
                }

                for (let i = 0; i < tokenList.length; i++) {
                    const tok = tokenList[i];

                    const nextElements = [];

                    // jsoup `children` — direct child elements of each current node.
                    if (tok.toLowerCase() === 'children') {
                        for (const parent of currentElements) {
                            for (const child of parent.children) {
                                if (child.nodeType === 1) nextElements.push(child);
                            }
                        }
                        currentElements = nextElements;
                        if (currentElements.length === 0) break;
                        continue;
                    }

                    const { selector, indexOp } = parseTokenAndIndex(tok);
                    const cleanSel = cleanCssSelector(selector);

                    for (const parent of currentElements) {
                        const matched = cleanSel ? parent.select(cleanSel) : [parent];
                        const filtered = applyIndexOp(matched, indexOp);
                        for (const el of filtered) nextElements.push(el);
                    }
                    currentElements = nextElements;
                    if (currentElements.length === 0) break;
                }

                if (trailingAttr !== null) {
                    return currentElements.map(el => extractAttrFromElement(el, trailingAttr));
                }
                return currentElements;
            }

            // Standard CSS selector
            const { selector, indexOp } = parseTokenAndIndex(cleanRule);
            const cleanSel = cleanCssSelector(selector);
            try {
                const selected = element.select(cleanSel);
                return applyIndexOp(selected, indexOp);
            } catch (e) {
                return [];
            }
        }

        /**
         * Extract single string from Element, JSON, or String
         */
        static extractString(elementOrJson, rule, baseUrl = '', variables = {}) {
            if (elementOrJson === null || elementOrJson === undefined || !rule) return '';

            // '%%' interleave in scalar context: join each interleaved list by '\n'.
            const ruleStr = String(rule);
            if (ruleStr.includes('%%')) {
                const parts = ruleStr.split('%%').map(p => p.trim()).filter(Boolean);
                if (parts.length > 1) {
                    const lists = parts.map(p => RuleAnalyzer.extractList(elementOrJson, p, baseUrl, variables));
                    const merged = interleaveLists(lists);
                    const strs = merged.map(x => (x && typeof x === 'object' && typeof x.text === 'function') ? x.text() : String(x));
                    return strs.filter(s => s && s.trim().length > 0).join('\n');
                }
            }

            const alts = splitTopLevelAlts(ruleStr);
            if (alts.length > 1) {
                for (const alt of alts) {
                    const res = RuleAnalyzer.extractString(elementOrJson, alt, baseUrl, variables);
                    if (res && res.trim().length > 0) return res.trim();
                }
                return '';
            }

            return RuleAnalyzer.extractSingleString(elementOrJson, alts[0] || '', baseUrl, variables);
        }

        static extractSingleString(target, rawRule, baseUrl, variables) {
            let trimmed = rawRule.trim();
            if (!trimmed) return '';

            // Resolve a bare URL template as a value before JSON/HTML rule
            // dispatch. Keep JS-containing rules on the normal execution path.
            if (trimmed.includes('{{') && !trimmed.includes('@js:') &&
                !trimmed.includes('<js>') &&
                /^(https?:|data:|file:|\/|\.\.?\/)/i.test(trimmed)) {
                const expanded = trimmed.replace(/{{([\s\S]*?)}}/g, (whole, expression) => {
                    const value = RuleAnalyzer.extractSingleString(target, expression.trim(), baseUrl, variables);
                    return value === null || value === undefined ? '' : String(value);
                }).trim();
                const optionIndex = expanded.indexOf(',{');
                const valueUrl = optionIndex >= 0 ? expanded.slice(0, optionIndex).trim() : expanded;
                const options = optionIndex >= 0 ? expanded.slice(optionIndex) : '';
                return resolveUrl(baseUrl, valueUrl) + options;
            }

            const hasTemplate = trimmed.includes('{{');
            if (hasTemplate) {
                trimmed = trimmed.replace(/{{([\s\S]*?)}}/g, (whole, expression) => {
                    const value = RuleAnalyzer.extractSingleString(target, expression.trim(), baseUrl, variables);
                    return value === null || value === undefined ? '' : String(value);
                }).trim();
            }

            // @put:{key:"rule",...} — evaluate and store each initializer.
            // @get:key        — read it back.
            if (trimmed.startsWith('@put:')) {
                const body = trimmed.slice(5).trim();
                const getMatch = body.match(/@get:\s*\{?([A-Za-z0-9_\-]+)\}?\s*$/);
                const putBody = getMatch ? body.slice(0, getMatch.index).trim() : body;
                const store = variables || RuleAnalyzer._variables;
                const inner = putBody.replace(/^\{/, '').replace(/\}$/, '').trim();
                let lastValue = '';
                for (const assignment of splitTopLevelCommas(inner)) {
                    const m = assignment.match(/^([A-Za-z0-9_\-]+)\s*:\s*([\s\S]*)$/);
                    if (!m) continue;
                    const putKey = m[1];
                    let valRule = m[2].trim();
                    if ((valRule.startsWith('"') && valRule.endsWith('"')) ||
                        (valRule.startsWith("'") && valRule.endsWith("'"))) {
                        valRule = valRule.slice(1, -1);
                    }
                    const val = RuleAnalyzer.extractSingleString(target, valRule, baseUrl, store);
                    if (store) store[putKey] = val;
                    lastValue = val;
                }
                if (getMatch) {
                    const gKey = getMatch[1];
                    return (store && store[gKey] !== undefined) ? String(store[gKey]) : '';
                }
                return lastValue;
            }

            if (trimmed.startsWith('@get:')) {
                const gKey = trimmed.slice(5).trim().replace(/^\{/, '').replace(/\}$/, '').trim();
                const store = variables || RuleAnalyzer._variables;
                return (store && store[gKey] !== undefined) ? String(store[gKey]) : '';
            }

            // AllInOne capture-group reference: '$1', '$2', ...
            if (/^\$\d+$/.test(trimmed) && target && typeof target === 'object' && !(target instanceof Node)) {
                const val = target[trimmed];
                return val !== undefined && val !== null ? String(val) : '';
            }

            // Legado `text.<label>@href` can select a link by its visible text.
            const textSelector = trimmed.match(/^text\.([^@]+?)(?:@([a-zA-Z][\w.-]*))?$/i);
            if (textSelector) {
                const needle = textSelector[1].trim();
                const attr = String(textSelector[2] || 'text').toLowerCase();
                let root = target;
                if (typeof target === 'string') root = parseHTML(target);
                if (root instanceof Node) {
                    const candidates = root.nodeType === 9 ? root.children : [root];
                    const queue = [...candidates];
                    while (queue.length > 0) {
                        const node = queue.shift();
                        if (node.nodeType === 1) {
                            if (node.text().includes(needle)) {
                                if (attr === 'text') return node.text().trim();
                                const value = extractAttrFromElement(node, attr);
                                if (value) return (attr === 'href' || attr === 'src') && baseUrl
                                    ? resolveUrl(baseUrl, value) : value;
                            }
                            for (const c of node.children) if (c.nodeType === 1) queue.push(c);
                        }
                    }
                }
                return '';
            }

            // XPath string extraction, optionally followed by Legado regex cleanup.
            const isXpath = (trimmed.startsWith('//') || /^@xpath:/i.test(trimmed) || (trimmed.startsWith('/') && !trimmed.includes('?') && !trimmed.includes('=') && /^\/[A-Za-z*]/.test(trimmed))) &&
                            !trimmed.includes('<js>') && !trimmed.includes('@js:') &&
                            (typeof target === 'string' || target instanceof Node);
            if (isXpath) {
                const useNative = typeof globalThis.__legado_native_xpath === 'function';
                let elem = target;
                if (!useNative && typeof target === 'string') elem = parseHTML(target);
                if (useNative || elem instanceof Node) {
                    const xpathRule = trimmed.split('##')[0].trim();
                    const res = typeof globalThis.__legado_native_xpath === 'function'
                        ? evaluateNativeXPath(target, xpathRule) : evaluateXPath(elem, xpathRule);
                    if (res && res.length > 0) {
                        let value = res.map(first => typeof first === 'string' ? first :
                            (first instanceof Node ? (first.nodeType === 3 ? decodeHtmlEntities(first.textValue) : first.text()) : ''))
                            .filter(Boolean).join('\n');
                        if (xpathRule.includes('/text()[')) value = res[0] || '';
                        else if (!xpathRule.includes('//text()')) value = res[0] instanceof Node ? res[0].text() : value;
                        const xpathRegexParts = trimmed.split('##');
                        if (xpathRegexParts.length >= 2) {
                            try {
                                value = value.replace(new RegExp(xpathRegexParts[1], 'g'), xpathRegexParts.length >= 3 ? xpathRegexParts[2] : '');
                            } catch (e) {}
                        }
                        return value.trim();
                    }
                }
                return '';
            }

            // 1. Check for JS blocks (@js: or <js>) with optional pre-rule
            // e.g. "$.id@js: 'url' + result" or "$.catName&&$.bookStatus@js: ..."
            let jsScript = null;
            let preRule = null;

            const jsAtIdx = trimmed.indexOf('@js:');
            const jsTagIdx = trimmed.indexOf('<js>');

            if (jsAtIdx !== -1) {
                preRule = trimmed.slice(0, jsAtIdx).trim();
                jsScript = trimmed.slice(jsAtIdx + 4).trim();
            } else if (jsTagIdx !== -1 && trimmed.includes('</js>')) {
                preRule = trimmed.slice(0, jsTagIdx).trim();
                const endTagIdx = trimmed.indexOf('</js>', jsTagIdx + 4);
                jsScript = trimmed.slice(jsTagIdx + 4, endTagIdx).trim();
                var postRule = trimmed.slice(endTagIdx + 5).trim();
            }

            if (jsScript !== null) {
                let jsInput = target;
                if (preRule) {
                    // preRule could have &&
                    if (preRule.includes('&&')) {
                        const parts = preRule.split('&&');
                        const results = [];
                        for (const p of parts) {
                            let val = RuleAnalyzer.extractSingleString(target, p.trim(), baseUrl, variables);
                            if (!val && /^(https?:|data:|file:|\/|\.\.?\/)/i.test(p.trim())) val = p.trim();
                            if (val) results.push(val);
                        }
                        jsInput = results.join('\n');
                    } else {
                        jsInput = RuleAnalyzer.extractSingleString(target, preRule, baseUrl, variables);
                        if (!jsInput && /^(https?:|data:|file:|\/|\.\.?\/)/i.test(preRule)) {
                            jsInput = preRule;
                        }
                    }
                } else {
                    if (target instanceof Node) {
                        jsInput = target.outerHtml();
                    } else if (typeof target === 'object') {
                        jsInput = JSON.stringify(target);
                    }
                }

                const evalVal = evalLegadoScript(jsScript, jsInput, baseUrl, variables);
                if (postRule) return RuleAnalyzer.extractString(evalVal, postRule, baseUrl, variables);
                return evalVal !== null && evalVal !== undefined ? String(evalVal).trim() : '';
            }

            // A plain URL template is a value, not a selector. Resolve only the
            // URL portion so inline request options remain available to formatRequest.
            if (hasTemplate && !trimmed.includes('@js:') && !trimmed.includes('<js>') &&
                /^(https?:|data:|file:|\/|\.\.?\/)/i.test(trimmed)) {
                const optionIndex = trimmed.indexOf(',{');
                const valueUrl = optionIndex >= 0 ? trimmed.slice(0, optionIndex).trim() : trimmed;
                const options = optionIndex >= 0 ? trimmed.slice(optionIndex) : '';
                return resolveUrl(baseUrl, valueUrl) + options;
            }

            // Text templates may contain ordinary prose and a trailing regex cleanup.
            // Expand them as values while still allowing JS blocks and selectors above.
            if (hasTemplate && !trimmed.includes('@js:') && !trimmed.includes('<js>') &&
                !trimmed.startsWith('$.') && !trimmed.startsWith('@json:') &&
                !trimmed.startsWith('@put:') && !trimmed.startsWith('@get:') &&
                !trimmed.includes('&&') && !/^[.#\[]/.test(trimmed)) {
                const parts = trimmed.split('##');
                let value = parts[0];
                if (parts.length > 1 && parts[1]) {
                    try { value = value.replace(new RegExp(parts[1], 'g'), parts.length > 2 ? parts[2] : ''); }
                    catch (e) {}
                }
                return value.trim();
            }

            // 2. Handle && rule joining (e.g. $.catName && $.bookStatus)
            if (trimmed.includes('&&')) {
                const parts = trimmed.split('&&');
                const results = [];
                for (const p of parts) {
                    const subVal = RuleAnalyzer.extractSingleString(target, p.trim(), baseUrl, variables);
                    if (subVal) results.push(subVal);
                }
                return results.join('\n');
            }

            // 3. JSONPath extraction if target is an object/json-string or rule starts with $. or @json:
            const isJsonTarget = (typeof target === 'object' && !(target instanceof Node)) ||
                                 (typeof target === 'string' && (target.startsWith('{') || target.startsWith('[')));
            const isJsonRule = trimmed.startsWith('@json:') || trimmed.startsWith('$.');

            if (isJsonRule || isJsonTarget) {
                const jsonVal = RuleAnalyzer.extractFromJson(target, trimmed);
                if (jsonVal !== '' && jsonVal !== null && jsonVal !== undefined) {
                    let text = typeof jsonVal === 'object' ? JSON.stringify(jsonVal) : String(jsonVal);
                    // Automatic relative URL resolution for json results
                    if ((text.startsWith('/') || text.startsWith('./')) && baseUrl) {
                        text = resolveUrl(baseUrl, text);
                    }
                    return text.trim();
                }
                if (isJsonRule) return '';
            }

            // 4. HTML / DOM regex replacements: ##pattern##replacement or ##pattern
            //    OnlyOne form `##pattern##replacement###` does a single replace with $n backrefs.
            const isOnlyOne = /###\s*$/.test(trimmed);
            let ruleForParts = isOnlyOne ? trimmed.replace(/###\s*$/, '') : trimmed;
            const regexParts = ruleForParts.split('##');
            const mainRule = regexParts[0].trim();

            let currentText = '';
            let isUrlAttr = false;

            // OnlyOne with an empty main rule applies the regex to the raw target.
            if (isOnlyOne && mainRule === '') {
                const pattern = regexParts[1] || '';
                const replacement = regexParts.length >= 3 ? regexParts[2] : '';
                let src = target;
                if (target instanceof Node) src = target.outerHtml();
                else if (typeof target === 'object') src = JSON.stringify(target);
                else src = String(target);
                if (pattern) {
                    try {
                        const m = src.match(new RegExp(pattern));
                        if (m) {
                            currentText = replacement;
                            for (let i = 0; i < m.length; i++) {
                                currentText = currentText.replace(new RegExp('\\$' + i, 'g'), m[i] !== undefined ? m[i] : '');
                            }
                        } else {
                            currentText = '';
                        }
                    } catch (e) {
                        currentText = '';
                    }
                }
                if (baseUrl && currentText && (pattern.includes('href') || pattern.includes('src') || currentText.startsWith('/') || currentText.startsWith('./'))) {
                    currentText = resolveUrl(baseUrl, currentText);
                }
                return currentText.trim();
            }

            let elem = target;
            if (typeof target === 'string' && !(target.startsWith('{') || target.startsWith('['))) {
                // If mainRule has CSS or @, parse HTML
                if (mainRule.includes('.') || mainRule.includes('#') || mainRule.includes('@') || mainRule.includes(' ')) {
                    elem = parseHTML(target);
                } else {
                    currentText = target;
                }
            }

            if (mainRule.length > 0 && elem instanceof Node) {
                const lowerMain = mainRule.replace(/^@/, '').toLowerCase();

                // Direct attribute check
                if (DIRECT_ATTRS.has(lowerMain)) {
                    currentText = extractAttrFromElement(elem, lowerMain);
                    if (lowerMain === 'href' || lowerMain === 'src') isUrlAttr = true;
                } else if (mainRule.includes('@')) {
                    const tokens = mainRule.split('@').filter(Boolean);
                    if (tokens.length > 0) {
                        const lastToken = tokens[tokens.length - 1].trim();
                        const lowerLast = lastToken.toLowerCase();

                        let attrName = 'text';
                        let selectorTokens = tokens;
                        if (DIRECT_ATTRS.has(lowerLast) || lowerLast.startsWith('attr.')) {
                            attrName = lowerLast.replace(/^attr\./, '');
                            selectorTokens = tokens.slice(0, -1);
                        }

                        if (attrName === 'href' || attrName === 'src') isUrlAttr = true;

                        let currentEl = elem;
                        for (let i = 0; i < selectorTokens.length; i++) {
                            if (!currentEl) break;
                            const { selector, indexOp } = parseTokenAndIndex(selectorTokens[i]);
                            const cleanSel = cleanCssSelector(selector);
                            const matched = cleanSel ? currentEl.select(cleanSel) : [currentEl];
                            const filtered = applyIndexOp(matched, indexOp);
                            currentEl = filtered.length > 0 ? filtered[0] : null;
                        }

                        if (currentEl) {
                            currentText = extractAttrFromElement(currentEl, attrName);
                        }
                    }
                } else {
                    const { selector, indexOp } = parseTokenAndIndex(mainRule);
                    const cleanSel = cleanCssSelector(selector);
                    const matched = elem.select(cleanSel);
                    const selected = applyIndexOp(matched, indexOp);
                    currentText = selected.length > 0 ? selected[0].text() : '';
                }
            }

            // 5. Apply regex replacements ##pattern##replace
            if (regexParts.length >= 2) {
                const pattern = regexParts[1];
                const replacement = regexParts.length >= 3 ? regexParts[2] : '';
                if (pattern.length > 0) {
                    try {
                        const reg = new RegExp(pattern, 'g');
                        currentText = currentText.replace(reg, replacement);
                    } catch (e) {}
                }
            }

            // 6. Automatic relative URL resolution
            if ((isUrlAttr || currentText.startsWith('/') ||
                (!currentText.startsWith('http://') && !currentText.startsWith('https://') &&
                 (trimmed.includes('href') || trimmed.includes('src') || trimmed.includes('url')))) &&
                baseUrl && currentText.trim().length > 0) {
                currentText = resolveUrl(baseUrl, currentText);
            }

            return currentText.trim();
        }

        static extractFromJson(data, rule) {
            let obj = data;
            if (typeof data === 'string') {
                const s = data.trim();
                if (s.startsWith('{') || s.startsWith('[')) {
                    try { obj = JSON.parse(s); } catch (e) { return ''; }
                } else {
                    return '';
                }
            }
            if (obj === null || obj === undefined) return '';

            const cleanRule = rule
                .replace(/^@json:/i, '')
                .replace(/^\$\.?/, '')
                .trim();

            if (!cleanRule) return obj;

            // Recursive descent: `$..field` collects every matching field anywhere.
            if (/^\./.test(cleanRule)) {
                const targetField = cleanRule.replace(/^\.+/, '').replace(/\[\*\]$/, '').trim();
                const collected = [];
                (function walk(node) {
                    if (node === null || node === undefined) return;
                    if (Array.isArray(node)) {
                        for (const item of node) walk(item);
                        return;
                    }
                    if (typeof node === 'object') {
                        for (const key of Object.keys(node)) {
                            if (key === targetField) {
                                const v = node[key];
                                if (Array.isArray(v)) collected.push(...v);
                                else collected.push(v);
                            }
                            walk(node[key]);
                        }
                    }
                })(obj);
                return collected;
            }

            // Split path by dot only outside bracket expressions
            const parts = [];
            let currentPart = '';
            let inBracket = 0;
            for (let i = 0; i < cleanRule.length; i++) {
                const c = cleanRule[i];
                if (c === '[') inBracket++;
                else if (c === ']') inBracket = Math.max(0, inBracket - 1);

                if (c === '.' && inBracket === 0) {
                    if (currentPart.length > 0) parts.push(currentPart);
                    currentPart = '';
                } else {
                    currentPart += c;
                }
            }
            if (currentPart.length > 0) parts.push(currentPart);
            let cur = obj;
            for (const part of parts) {
                if (cur === null || cur === undefined) break;

                // 1. JSONPath Filter Predicate: e.g. "book[?(@.price > 10)]" or root array "[?(@.id > 1)]"
                const filterMatch = part.match(/^([a-zA-Z0-9_\-]*)\[\?\((.+)\)\]$/);
                if (filterMatch) {
                    const field = filterMatch[1];
                    const expr = filterMatch[2].trim();
                    const targetList = field ? cur[field] : cur;
                    if (!Array.isArray(targetList)) {
                        cur = [];
                        break;
                    }

                    // Parse predicate: @.prop op val
                    const predRegex = /^@\.([a-zA-Z0-9_\-]+)\s*(==|!=|>=|<=|>|<)\s*(.+)$/;
                    const pm = expr.match(predRegex);
                    if (pm) {
                        const prop = pm[1];
                        const op = pm[2];
                        let expected = pm[3].trim().replace(/^['"]/, '').replace(/['"]$/, '');
                        const numExpected = Number(expected);

                        cur = targetList.filter(item => {
                            if (!item || typeof item !== 'object') return false;
                            const actual = item[prop];
                            if (actual === undefined || actual === null) return false;

                            if (!isNaN(numExpected) && typeof actual === 'number') {
                                if (op === '>') return actual > numExpected;
                                if (op === '<') return actual < numExpected;
                                if (op === '>=') return actual >= numExpected;
                                if (op === '<=') return actual <= numExpected;
                                if (op === '==') return actual === numExpected;
                                if (op === '!=') return actual !== numExpected;
                            }

                            const strActual = String(actual);
                            if (op === '==') return strActual === expected;
                            if (op === '!=') return strActual !== expected;
                            return false;
                        });
                    } else {
                        cur = targetList;
                    }
                    continue;
                }

                // 2. JSONPath Slice e.g. "[-2:]" or "book[-2:]"
                const sliceMatch = part.match(/^([a-zA-Z0-9_\-]*)\[(-?\d*):(-?\d*)\]$/);
                if (sliceMatch) {
                    const field = sliceMatch[1];
                    const targetList = field ? cur[field] : cur;
                    if (Array.isArray(targetList)) {
                        const sStart = sliceMatch[2] ? parseInt(sliceMatch[2], 10) : 0;
                        const sEnd = sliceMatch[3] ? parseInt(sliceMatch[3], 10) : targetList.length;
                        cur = targetList.slice(sStart, sEnd);
                        continue;
                    }
                }

                // 3. Simple Index or Wildcard: e.g. "book[0]" or "book[*]"
                const arrMatch = part.match(/^([a-zA-Z0-9_\-]+)\[(\d+|\*)\]$/);
                if (arrMatch) {
                    const field = arrMatch[1];
                    const idx = arrMatch[2];
                    cur = cur[field];
                    if (Array.isArray(cur)) {
                        cur = idx === '*' ? cur : cur[parseInt(idx, 10)];
                    }
                } else if (Array.isArray(cur)) {
                    // Extract property from each element in current list (e.g. list.title)
                    cur = cur.map(item => (item && typeof item === 'object') ? item[part] : null).filter(v => v !== null && v !== undefined);
                } else {
                    cur = cur[part];
                }
            }

            if (cur === null || cur === undefined) return '';
            return cur;
        }
    }

    // =========================================================================
    // 5. Legado Host Script Environment (java.*, result, baseUrl)
    // =========================================================================

    // State in Legado belongs to a book source. Keep it across rule stages for
    // that source, while preventing one source's java/cache/source values from
    // leaking into another source.
    const memoryStores = new Map();
    const sourceContexts = new Map();

    function sourceKey(source) {
        return String(source && (source.bookSourceUrl || source.bookSourceName) || '__default__');
    }

    function cookieDomain(url) {
        if (!url) return '';
        try {
            const m = String(url).match(/^https?:\/\/([^/?#:]+)/i);
            if (m) return m[1].toLowerCase();
            return String(url).trim().split('/')[0].split(':')[0].toLowerCase();
        } catch (e) {
            return '';
        }
    }

    class CookieStore {
        constructor() {
            this._domains = new Map();
        }

        _getDomainMap(domain, create = false) {
            if (!domain) domain = '__global__';
            let map = this._domains.get(domain);
            if (!map && create) {
                map = new Map();
                this._domains.set(domain, map);
            }
            return map;
        }

        getCookie(url) {
            const domain = cookieDomain(url);
            const cookies = new Map();
            if (domain) {
                const parts = domain.split('.');
                if (parts.length > 2) {
                    const parentDomain = parts.slice(1).join('.');
                    const parentMap = this._domains.get(parentDomain);
                    if (parentMap) {
                        for (const [k, v] of parentMap.entries()) cookies.set(k, v);
                    }
                }
                const domainMap = this._domains.get(domain);
                if (domainMap) {
                    for (const [k, v] of domainMap.entries()) cookies.set(k, v);
                }
            } else {
                const globalMap = this._domains.get('__global__');
                if (globalMap) {
                    for (const [k, v] of globalMap.entries()) cookies.set(k, v);
                }
            }
            if (cookies.size === 0) return '';
            const pairs = [];
            for (const [k, v] of cookies.entries()) {
                pairs.push(`${k}=${v}`);
            }
            return pairs.join('; ');
        }

        getKey(url, key) {
            if (!key) return '';
            const cookieStr = this.getCookie(url);
            if (!cookieStr) return '';
            const parts = cookieStr.split(';');
            for (const part of parts) {
                const trimmed = part.trim();
                const eqIdx = trimmed.indexOf('=');
                if (eqIdx !== -1 && trimmed.slice(0, eqIdx).trim() === key) {
                    return trimmed.slice(eqIdx + 1).trim();
                }
            }
            return '';
        }

        setCookie(url, cookieStr) {
            if (!cookieStr || typeof cookieStr !== 'string') return;
            const domain = cookieDomain(url) || '__global__';
            const map = this._getDomainMap(domain, true);
            const parts = cookieStr.split(';');
            for (const part of parts) {
                const trimmed = part.trim();
                if (!trimmed) continue;
                const eqIdx = trimmed.indexOf('=');
                if (eqIdx !== -1) {
                    const k = trimmed.slice(0, eqIdx).trim();
                    const v = trimmed.slice(eqIdx + 1).trim();
                    const lowerK = k.toLowerCase();
                    if (['path', 'domain', 'expires', 'max-age', 'httponly', 'secure', 'samesite'].includes(lowerK)) {
                        continue;
                    }
                    map.set(k, v);
                }
            }
        }

        replaceCookie(url, cookieStr) {
            const domain = cookieDomain(url) || '__global__';
            this._domains.delete(domain);
            this.setCookie(url, cookieStr);
        }

        removeCookie(url) {
            const domain = cookieDomain(url) || '__global__';
            this._domains.delete(domain);
        }

        setWebCookie(url, cookieStr) {
            return this.setCookie(url, cookieStr);
        }
    }

    function getSourceContext(source) {
        const key = sourceKey(source);
        let context = sourceContexts.get(key);
        if (!context) {
            const store = new Map();
            const sourceObject = Object.assign({}, source || {});
            sourceObject.put = (k, v) => { store.set(String(k), v); return v; };
            sourceObject.get = k => store.has(String(k)) ? store.get(String(k)) : '';
            let variableSlot = '';
            sourceObject.setVariable = value => { variableSlot = String(value); return value; };
            sourceObject.getVariable = () => variableSlot;
            sourceObject.getKey = () => key;
            const cache = {
                put: (k, v) => { store.set(String(k), v); return v; },
                get: k => store.has(String(k)) ? store.get(String(k)) : '',
                delete: k => store.delete(String(k)), remove: k => store.delete(String(k)),
                clear: () => store.clear()
            };
            const cookieStore = new CookieStore();
            const cookieApi = {
                getCookie: url => cookieStore.getCookie(url || (sourceObject && sourceObject.bookSourceUrl) || ''),
                getKey: (url, key) => cookieStore.getKey(url || (sourceObject && sourceObject.bookSourceUrl) || '', key),
                setCookie: (url, val) => cookieStore.setCookie(url || (sourceObject && sourceObject.bookSourceUrl) || '', val),
                replaceCookie: (url, val) => cookieStore.replaceCookie(url || (sourceObject && sourceObject.bookSourceUrl) || '', val),
                removeCookie: url => cookieStore.removeCookie(url || (sourceObject && sourceObject.bookSourceUrl) || ''),
                setWebCookie: (url, val) => cookieStore.setWebCookie(url || (sourceObject && sourceObject.bookSourceUrl) || '', val)
            };
            if (source && source.header) {
                try {
                    const headerMap = typeof source.header === 'string' ? JSON.parse(source.header) : source.header;
                    if (headerMap && typeof headerMap === 'object') {
                        for (const [k, v] of Object.entries(headerMap)) {
                            if (k.toLowerCase() === 'cookie' && typeof v === 'string') {
                                cookieStore.setCookie(sourceObject.bookSourceUrl || '', v);
                            }
                        }
                    }
                } catch (e) {}
            }
            context = { key, store, source: sourceObject, book: {}, jsLib: null, jsLibError: null,
                cache, cookieStore, cookieApi, host: null, getVariable: () => variableSlot, setVariable: value => { variableSlot = String(value); return value; } };
            sourceContexts.set(key, context);
            memoryStores.set(key, store);
        } else if (source) {
            Object.assign(context.source, source);
            if (source.header) {
                try {
                    const headerMap = typeof source.header === 'string' ? JSON.parse(source.header) : source.header;
                    if (headerMap && typeof headerMap === 'object') {
                        for (const [k, v] of Object.entries(headerMap)) {
                            if (k.toLowerCase() === 'cookie' && typeof v === 'string') {
                                context.cookieStore.setCookie(context.source.bookSourceUrl || '', v);
                            }
                        }
                    }
                } catch (e) {}
            }
        }
        return context;
    }

    function ruleVariables(source) {
        const context = getSourceContext(source);
        const host = context.host || (context.host = new JsHost(source && source.bookSourceUrl || '', source));
        host.baseUrl = source && source.bookSourceUrl || '';
        loadSourceJsLib(context, host);
        return {source: context.source, cache: context.cache, java: host, cookie: context.cookieApi, ...(context.jsLib || {}), book: context.book};
    }

    class JsHost {
        constructor(baseUrl = '', source = null) {
            this.baseUrl = baseUrl;
            this._content = '';
            this._baseUrl = baseUrl;
            this._context = getSourceContext(source);
            this.cookie = this._context.cookieApi;
        }

        // Legado: java.setContent(content, baseUrl) sets the document that
        // later java.getElement(s)/getString(List) calls operate on.
        setContent(content, baseUrl) {
            this._content = content === null || content === undefined ? '' : content;
            if (baseUrl !== undefined && baseUrl !== null) this._baseUrl = baseUrl;
            return this;
        }

        getElement(ruleStr) {
            const doc = parseHTML(typeof this._content === 'string' ? this._content : String(this._content || ''));
            const cleanSel = cleanCssSelector(String(ruleStr || '').replace(/^@css:/i, ''));
            if (!cleanSel) return '';
            const list = doc.select(cleanSel);
            return list.length > 0 ? list[0] : '';
        }

        getElements(ruleStr) {
            const doc = parseHTML(typeof this._content === 'string' ? this._content : String(this._content || ''));
            const cleanSel = cleanCssSelector(String(ruleStr || '').replace(/^@css:/i, ''));
            if (!cleanSel) return [];
            return doc.select(cleanSel);
        }

        getStringList(rule, isUrl = false) {
            let source = this._content;
            if (isUrl) {
                source = this.ajax(rule);
            }
            return RuleAnalyzer.extractList(source, rule, this._baseUrl || this.baseUrl);
        }

        getString(arg1, arg2 = false) {
            if (arguments.length === 1 || typeof arg2 === 'boolean') {
                const isUrl = !!arg2;
                if (isUrl) {
                    const fetched = this.ajax(arg1);
                    return RuleAnalyzer.extractString(fetched, arg1, this._baseUrl || this.baseUrl);
                }
                const list = this.getStringList(arg1, false);
                if (list.length > 0) {
                    const first = list[0];
                    return (first && typeof first.text === 'function') ? first.text() : String(first);
                }
                return RuleAnalyzer.extractString(this._content, arg1, this._baseUrl || this.baseUrl);
            }
            const res = RuleAnalyzer.extractFromJson(arg1, arg2);
            return typeof res === 'object' ? JSON.stringify(res) : String(res !== undefined ? res : '');
        }

        put(key, value) {
            this._context.store.set(String(key), value);
            return value;
        }

        get(key) {
            const value = this._context.store.get(String(key));
            return value === undefined || value === null ? '' : value;
        }

        setVariable(key, value) { return this.put(key, value); }
        getVariable(key) { return this.get(key); }

        base64Encode(str, flags) {
            return base64Encode(str);
        }

        base64Decode(str) {
            return base64Decode(str);
        }

        md5Encode(str) {
            return md5(str);
        }

        md5Encode16(str) {
            return md5(str).slice(8, 24);
        }

        digest(algo, str) {
            const algorithm = String(algo || '').toUpperCase();
            if (algorithm === 'MD5') {
                return md5(str || '');
            }
            throw new Error('java.digest unsupported algorithm: ' + algorithm);
        }

        hexEncode(str) {
            if (!str) return '';
            let out = '';
            for (let i = 0; i < str.length; i++) {
                const hex = str.charCodeAt(i).toString(16);
                out += (hex.length === 1 ? '0' : '') + hex;
            }
            return out;
        }

        hexDecode(hexStr) {
            if (!hexStr) return '';
            let out = '';
            for (let i = 0; i < hexStr.length; i += 2) {
                out += String.fromCharCode(parseInt(hexStr.substr(i, 2), 16));
            }
            return out;
        }

        hexDecodeToString(hexStr) {
            const hex = String(hexStr == null ? '' : hexStr).trim();
            if (!hex) return '';
            if (hex.length % 2 !== 0 || !/^[0-9a-f]+$/i.test(hex)) {
                throw new Error('java.hexDecodeToString expects an even-length hex byte string');
            }
            let bytes = '';
            for (let i = 0; i < hex.length; i += 2) {
                bytes += String.fromCharCode(parseInt(hex.slice(i, i + 2), 16));
            }
            try {
                return decodeURIComponent(escape(bytes));
            } catch (e) {
                throw new Error('java.hexDecodeToString received invalid UTF-8: ' + e.message);
            }
        }

        timeFormat(timestamp, format = 'yyyy-MM-dd HH:mm:ss') {
            const date = new Date(Number(timestamp) || Date.now());
            const pad = n => (n < 10 ? '0' + n : String(n));
            const y = date.getFullYear();
            const M = pad(date.getMonth() + 1);
            const d = pad(date.getDate());
            const H = pad(date.getHours());
            const m = pad(date.getMinutes());
            const s = pad(date.getSeconds());

            return format
                .replace('yyyy', y)
                .replace('MM', M)
                .replace('dd', d)
                .replace('HH', H)
                .replace('mm', m)
                .replace('ss', s);
        }

        encodeURI(str) {
            try { return encodeURIComponent(str); } catch (e) { return str; }
        }

        decodeURI(str) {
            try { return decodeURIComponent(str); } catch (e) { return str; }
        }

        log(msg) {
            if (typeof console !== 'undefined' && console.log) {
                console.log('[Legado JS Log]:', msg);
            }
            return msg;
        }

        toast(message) {
            recordScriptDiagnostic(this._context, 'java.toast', 'UI notification unsupported by this host: ' + String(message || ''));
            return false;
        }

        longToast(message) {
            recordScriptDiagnostic(this._context, 'java.longToast', 'UI notification unsupported by this host: ' + String(message || ''));
            return false;
        }

        getCookie(url) {
            return this._context.cookieApi.getCookie(url || this.baseUrl);
        }

        getKey(url, key) {
            return this._context.cookieApi.getKey(url || this.baseUrl, key);
        }

        setCookie(url, cookieStr) {
            return this._context.cookieApi.setCookie(url || this.baseUrl, cookieStr);
        }

        showBrowser() { throw new Error('java.showBrowser unsupported: browser interaction is unavailable'); }

        ajax(url, optsOrTimeout, timeout) {
            let opts = '';
            let to = 10000;
            if (typeof optsOrTimeout === 'number') {
                to = optsOrTimeout;
            } else if (typeof optsOrTimeout === 'string') {
                opts = optsOrTimeout;
                if (typeof timeout === 'number') to = timeout;
            } else if (typeof timeout === 'number') {
                to = timeout;
            }

            const full = String(url || '');
            // Options may be embedded in the URL: "url,{...}"
            const commaIdx = full.indexOf(',{');
            let cleanUrl = full;
            let inlineOpts = '';
            if (commaIdx !== -1) {
                cleanUrl = full.slice(0, commaIdx).trim();
                inlineOpts = full.slice(commaIdx + 1).trim();
            }
            const mergedOpts = inlineOpts || opts;

            if (global.__legado_native_ajax) {
                try {
                    const res = global.__legado_native_ajax(resolveUrl(this.baseUrl, cleanUrl), mergedOpts, to);
                    return res === null || res === undefined ? '' : String(res);
                } catch (e) {
                    recordScriptDiagnostic(this._context, 'java.ajax', 'HTTP callback failed: ' + (e && e.message || e));
                    throw new Error('java.ajax failed: ' + (e && e.message || e));
                }
            }
            recordScriptDiagnostic(this._context, 'java.ajax', 'HTTP callback is unavailable in this host');
            return '';
        }

        connect(url, options = {}) {
            const host = this;
            let targetUrl = String(url || '');
            let requestOptions = Object.assign({}, options || {});
            const optionAt = targetUrl.indexOf(',{');
            if (optionAt >= 0) {
                const rawOptions = targetUrl.slice(optionAt + 1).trim();
                targetUrl = targetUrl.slice(0, optionAt).trim();
                try { requestOptions = Object.assign(requestOptions, JSON.parse(rawOptions)); }
                catch (e) { throw new Error('java.connect inline options are invalid JSON: ' + e.message); }
            }
            let method = 'GET';
            let body = requestOptions.body === undefined ? null : requestOptions.body;
            if (requestOptions.method) method = String(requestOptions.method).toUpperCase();
            const headers = Object.assign({}, requestOptions.headers || {});
            const request = {
                header(name, value) { headers[name] = value; return client; },
                headers(values) { Object.assign(headers, values || {}); return client; },
                method(value, data) { method = String(value || 'GET').toUpperCase(); if (data !== undefined) body = data; return client; },
                get() { method = 'GET'; return client; }, post(data) { method = 'POST'; body = data; return client; },
                url() { return resolveUrl(host.baseUrl, targetUrl); }
            };
            const client = {
                header: request.header, headers: request.headers, method: request.method,
                get: request.get, post: request.post,
                raw() { return client.execute().raw(); },
                execute() {
                    const target = request.url();
                    const opts = Object.assign({}, requestOptions, {method, headers, _legado_response_meta: true});
                    if (body !== null) opts.body = body;
                    const raw = host.ajax(target, JSON.stringify(opts));
                    let meta;
                    try { meta = JSON.parse(raw); } catch (_) {
                        throw new Error('java.connect response metadata is invalid; host returned a body-only response');
                    }
                    const requestInfo = {url: meta.final_url || target, method, headers};
                    const response = {body: meta.body || '', status: meta.status, final_url: meta.final_url || target,
                        headers: meta.headers || {}, error: meta.error || null};
                    const result = {
                        body: () => response.body, string: () => response.body, code: () => response.status,
                        message: () => response.error || '', headers: () => response.headers,
                        request: () => ({url: () => requestInfo.url, method: () => requestInfo.method, headers: () => requestInfo.headers}),
                        raw: () => ({request: () => ({url: () => requestInfo.url, method: () => requestInfo.method}),
                            code: () => response.status, body: () => ({string: () => response.body}), headers: () => response.headers})
                    };
                    if (response.error) throw new Error('java.connect failed: ' + response.error);
                    return result;
                }
            };
            return client;
        }

        createSymmetricCrypto(algo, key, iv) {
            const self = this;
            const call = (data, mode) => {
                if (!global.__legado_native_crypto) {
                    throw new Error('createSymmetricCrypto 未注册原生回调');
                }
                const res = global.__legado_native_crypto(algo, key, iv, data, mode);
                return res === null || res === undefined ? '' : String(res);
            };
            return {
                encryptBase64(plain) { return call(plain, 0); },
                decryptBase64(cipher) { return call(cipher, 1); }
            };
        }

        aesBase64DecodeToString(cipherBase64, key, algo, iv) {
            const algorithm = String(algo || '');
            const normalized = algorithm.toUpperCase();
            if (normalized !== 'AES/CBC/PKCS5PADDING' && normalized !== 'AES/CBC/PKCS7PADDING') {
                throw new Error('java.aesBase64DecodeToString unsupported algorithm: ' + algorithm);
            }
            if (typeof global.__legado_native_crypto !== 'function') {
                throw new Error('java.aesBase64DecodeToString requires the native crypto callback');
            }
            const result = global.__legado_native_crypto(
                algorithm, String(key), String(iv), String(cipherBase64), 1);
            return result === null || result === undefined ? '' : String(result);
        }
    }

    const scriptDiagnostics = [];
    function recordScriptDiagnostic(source, script, error) {
        const message = String(error && error.message || error || 'Unknown script error');
        scriptDiagnostics.push({ source: sourceKey(source && source.source ? source.source : source), message, script: String(script || '').slice(0, 240) });
        if (scriptDiagnostics.length > 100) scriptDiagnostics.shift();
    }

    function loadSourceJsLib(context, host) {
        if (!context) return;
        const raw = context.source.jsLib;
        if (context.jsLibSource === raw) {
            if (context.jsLibError) throw new Error('jsLib 加载失败: ' + context.jsLibError.message);
            return;
        }
        context.jsLibSource = raw;
        context.jsLib = {};
        context.jsLibError = null;
        if (!raw) return;
        const body = String(raw).replace(/^\s*<js>/i, '').replace(/<\/js>\s*$/i, '');
        const names = [];
        let i = 0, depth = 0, quote = '', lineComment = false, blockComment = false, escape = false;
        while (i < body.length) {
            const c = body[i], n = body[i + 1];
            if (lineComment) { if (c === '\n') lineComment = false; i++; continue; }
            if (blockComment) { if (c === '*' && n === '/') { blockComment = false; i += 2; } else i++; continue; }
            if (quote) {
                if (escape) escape = false;
                else if (c === '\\') escape = true;
                else if (c === quote) quote = '';
                i++; continue;
            }
            if (c === '/' && n === '/') { lineComment = true; i += 2; continue; }
            if (c === '/' && n === '*') { blockComment = true; i += 2; continue; }
            if (c === '/') {
                let p = i - 1;
                while (p >= 0 && /\s/.test(body[p])) p--;
                const prefix = body.slice(Math.max(0, p - 8), p + 1);
                const regexMayStart = p < 0 || /[=(:,[!&|?;{}]/.test(body[p]) || /\b(?:return|throw|case|typeof|delete|void)\s*$/.test(prefix);
                if (regexMayStart) {
                    let inClass = false, escaped = false;
                    i++;
                    while (i < body.length) {
                        const r = body[i++];
                        if (escaped) { escaped = false; continue; }
                        if (r === '\\') { escaped = true; continue; }
                        if (r === '[') inClass = true;
                        else if (r === ']') inClass = false;
                        else if (r === '/' && !inClass) break;
                    }
                    while (/[A-Za-z]/.test(body[i] || '')) i++;
                    continue;
                }
            }
            if (c === '"' || c === "'" || c === '`') { quote = c; i++; continue; }
            if (depth === 0 && /[A-Za-z_$]/.test(c)) {
                let end = i + 1;
                while (end < body.length && /[\w$]/.test(body[end])) end++;
                const word = body.slice(i, end);
                if (word === 'function' || word === 'const' || word === 'let' || word === 'var') {
                    let p = end;
                    while (p < body.length && /\s/.test(body[p])) p++;
                    if (word === 'function' && body[p] === '*') { p++; while (/\s/.test(body[p] || '')) p++; }
                    const match = body.slice(p).match(/^([A-Za-z_$][\w$]*)/);
                    if (match && !names.includes(match[1])) names.push(match[1]);
                }
                i = end; continue;
            }
            if (c === '{') depth++;
            else if (c === '}') depth = Math.max(0, depth - 1);
            i++;
        }
        try {
            const result = new Function('java', 'source', 'cache', 'cookie', body + '\n;return {' + names.map(n => JSON.stringify(n) + ':' + n).join(',') + '};')(
                host, context.source, context.cache, context.cookieApi);
            context.jsLibThis = Object.assign({java: host, source: context.source, cache: context.cache, cookie: context.cookieApi}, result || {});
            context.jsLib = {};
            for (const name of names) {
                const value = result && result[name];
                context.jsLib[name] = typeof value === 'function' ? value.bind(context.jsLibThis) : value;
            }
        } catch (e) {
            context.jsLibError = e;
            recordScriptDiagnostic(context, body, e);
            throw new Error('jsLib 加载失败: ' + e.message);
        }
    }

    function containsTopLevelReturn(script) {
        let depth = 0, quote = '', lineComment = false, blockComment = false, escape = false;
        let functionBodies = [], pendingFunction = false, pendingArrow = false;
        for (let i = 0; i < script.length;) {
            const c = script[i], n = script[i + 1];
            if (lineComment) { if (c === '\n') lineComment = false; i++; continue; }
            if (blockComment) { if (c === '*' && n === '/') { blockComment = false; i += 2; } else i++; continue; }
            if (quote) {
                if (escape) escape = false;
                else if (c === '\\') escape = true;
                else if (c === quote) quote = '';
                i++; continue;
            }
            if (c === '/' && n === '/') { lineComment = true; i += 2; continue; }
            if (c === '/' && n === '*') { blockComment = true; i += 2; continue; }
            if (c === '"' || c === "'" || c === '`') { quote = c; i++; continue; }
            if (/[A-Za-z_$]/.test(c)) {
                let end = i + 1;
                while (end < script.length && /[\w$]/.test(script[end])) end++;
                const word = script.slice(i, end);
                if (word === 'function') pendingFunction = true;
                else if (word === 'return' && functionBodies.length === 0) return true;
                i = end; continue;
            }
            if (c === '=' && n === '>') { pendingArrow = true; i += 2; continue; }
            if (c === '{') {
                depth++;
                if (pendingFunction || pendingArrow) functionBodies.push(depth);
                pendingFunction = false; pendingArrow = false;
            } else if (c === '}') {
                if (functionBodies[functionBodies.length - 1] === depth) functionBodies.pop();
                depth = Math.max(0, depth - 1);
            }
            i++;
        }
        return false;
    }

    function evalLegadoScript(script, rawTarget, baseUrl = '', variables = {}, context = null) {
        let result = rawTarget;
        if (rawTarget instanceof Node) {
            result = rawTarget.outerHtml();
        }

        const host = variables.java || new JsHost(baseUrl, context && context.source);
        context = context || host._context;
        // By Legado standard, java.getElement(s) defaults to querying current `result` (the HTML page)
        host.setContent(result, baseUrl);

        const cleanScript = String(script || '');

        const cookieApi = (context && context.cookieApi) || (host && host.cookie) || (variables && variables.cookie) || null;
        const sandboxKeys = ['java', 'result', 'src', 'baseUrl', 'source', 'cache', 'cookie', 'org', ...Object.keys(variables).filter(k => !['java','result','src','baseUrl','source','cache','cookie','org'].includes(k))];
        const sandboxVals = [host, result, result, baseUrl, context && context.source || {}, context && context.cache || new Map(), cookieApi, jsoupHostApi, ...Object.keys(variables).filter(k => !['java','result','src','baseUrl','source','cache','cookie','org'].includes(k)).map(k => variables[k])];

        // Use QuickJS's compile-only parser when running through the native
        // bridge, so the original Program completion (including a trailing
        // IIFE) is preserved without speculative execution. The pure qjs
        // fallback supports Program scripts only.
        const hasNativeProgramCheck = typeof globalThis.__legado_can_eval_program === 'function';
        const isProgram = hasNativeProgramCheck
            ? globalThis.__legado_can_eval_program(cleanScript)
            : !containsTopLevelReturn(cleanScript);
        let compiled;
        try {
            if (isProgram) {
                compiled = new Function(...sandboxKeys,
                    'return eval(' + JSON.stringify(cleanScript) + ');');
            } else {
                compiled = new Function(...sandboxKeys, cleanScript);
            }
        } catch (compileError) {
            recordScriptDiagnostic(context, cleanScript, compileError);
            return undefined;
        }
        try {
            return compiled(...sandboxVals);
        } catch (e) {
            recordScriptDiagnostic(context, cleanScript, e);
            return undefined;
        }
    }

    // =========================================================================
    // 6. Complete Legado BookSource Engine (Parse Sources, Search, TOC, Content)
    // =========================================================================

    class LegadoEngine {
        static parseBookSources(jsonString) {
            if (!jsonString || typeof jsonString !== 'string') return [];
            const trimmed = jsonString.trim();
            if (!trimmed) return [];

            let parsed;
            try {
                parsed = JSON.parse(trimmed);
            } catch (e) {
                return [];
            }

            const rawList = [];
            if (Array.isArray(parsed)) {
                for (const item of parsed) rawList.push(item);
            } else if (parsed && typeof parsed === 'object') {
                const candidate = parsed.data || parsed.list || parsed.sources || parsed.bookSources;
                if (Array.isArray(candidate)) {
                    for (const item of candidate) rawList.push(item);
                } else if (candidate && typeof candidate === 'object' && Array.isArray(candidate.list)) {
                    for (const item of candidate.list) rawList.push(item);
                } else if (parsed.bookSourceUrl || parsed.bookSourceName) {
                    rawList.push(parsed);
                }
            }

            const validSources = [];
            for (const item of rawList) {
                if (item && typeof item === 'object' && item.bookSourceUrl && item.bookSourceName) {
                    validSources.push(Object.assign({}, item, {
                        bookSourceUrl: String(item.bookSourceUrl).trim(),
                        bookSourceName: String(item.bookSourceName).trim(),
                        bookSourceGroup: item.bookSourceGroup ? String(item.bookSourceGroup) : null,
                        bookSourceType: Number(item.bookSourceType) || 0,
                        bookSourceComment: item.bookSourceComment ? String(item.bookSourceComment) : null,
                        enabled: item.enabled !== false,
                        enabledExplore: item.enabledExplore !== false,
                        weight: Number(item.weight) || 0,
                        customOrder: Number(item.customOrder) || 0,
                        header: item.header ? (typeof item.header === 'string' ? item.header : JSON.stringify(item.header)) : null,
                        loginUrl: item.loginUrl ? String(item.loginUrl) : null,
                        searchUrl: item.searchUrl ? String(item.searchUrl) : null,
                        exploreUrl: item.exploreUrl ? String(item.exploreUrl) : null,
                        ruleSearch: item.ruleSearch || null,
                        ruleExplore: item.ruleExplore || null,
                        ruleBookInfo: item.ruleBookInfo || null,
                        ruleToc: item.ruleToc || null,
                        ruleContent: item.ruleContent || null,
                        ruleReview: item.ruleReview || null,
                        jsLib: item.jsLib || null,
                        lastUpdateTime: Number(item.lastUpdateTime) || Date.now()
                    }));
                }
            }

            return validSources;
        }

        static parseHeaderMap(headerJson) {
            if (!headerJson) return {};
            if (typeof headerJson === 'object') return headerJson;
            try {
                return JSON.parse(headerJson);
            } catch (e) {
                return {};
            }
        }

        static formatRequest(baseUrl, rawUrlWithOption, defaultHeaders = {}) {
            let targetUrl = rawUrlWithOption.trim();
            let method = 'GET';
            let body = null;
            let charset = null;
            let type = null;
            const headers = Object.assign({}, defaultHeaders);
            let contentType = 'application/x-www-form-urlencoded; charset=utf-8';

            const commaIdx = targetUrl.indexOf(',{') !== -1 ? targetUrl.indexOf(',{') : targetUrl.indexOf(', {');
            if (commaIdx !== -1) {
                const optStr = targetUrl.slice(targetUrl.indexOf('{')).trim();
                targetUrl = targetUrl.slice(0, commaIdx).trim();
                try {
                    const opt = JSON.parse(optStr);
                    if (opt.method) method = String(opt.method).toUpperCase();
                    if (opt.body) body = typeof opt.body === 'string' ? opt.body : JSON.stringify(opt.body);
                    if (opt.charset) charset = String(opt.charset);
                    if (Object.prototype.hasOwnProperty.call(opt, 'type')) type = opt.type;
                    let optionHeaders = opt.headers;
                    if (typeof optionHeaders === 'string') {
                        try { optionHeaders = JSON.parse(optionHeaders); } catch (e) { optionHeaders = null; }
                    }
                    if (optionHeaders && typeof optionHeaders === 'object' && !Array.isArray(optionHeaders)) {
                        Object.assign(headers, optionHeaders);
                    }
                    if (body && body.trim().startsWith('{')) {
                        contentType = 'application/json; charset=utf-8';
                    }
                } catch (e) {}
            }

            const finalUrl = resolveUrl(baseUrl, targetUrl);
            headers['Content-Type'] = contentType;

            return {
                url: finalUrl,
                method,
                body,
                charset,
                type,
                headers
            };
        }

        static buildSearchRequest(source, keyword, page = 1) {
            if (!source || !source.searchUrl) return null;
            const context = getSourceContext(source);
            const host = context.host || (context.host = new JsHost(source.bookSourceUrl, source));
            host.baseUrl = source.bookSourceUrl || '';
            const evaluateUrlScript = script => {
                loadSourceJsLib(context, host);
                return evalLegadoScript(script, '', source.bookSourceUrl || '', {
                    key: keyword, keyword, page, source: context.source, cache: context.cache,
                    java: host, baseUrl: source.bookSourceUrl || '',
                    ...(context.jsLib || {})
                }, context);
            };
            const rawSearchUrl = String(source.searchUrl);
            let substitutedUrl = rawSearchUrl;
            if (/^@js:/i.test(rawSearchUrl)) {
                substitutedUrl = evaluateUrlScript(rawSearchUrl.replace(/^@js:/i, '').trim());
            } else if (/^<js>[\s\S]*<\/js>$/i.test(rawSearchUrl.trim())) {
                substitutedUrl = evaluateUrlScript(rawSearchUrl.trim().slice(4, -5).trim());
            }
            if (substitutedUrl && typeof substitutedUrl === 'object') {
                if (typeof substitutedUrl.url === 'string') {
                    const options = Object.assign({}, substitutedUrl);
                    delete options.url;
                    substitutedUrl = substitutedUrl.url + ',' + JSON.stringify(options);
                } else substitutedUrl = JSON.stringify(substitutedUrl);
            }
            substitutedUrl = String(substitutedUrl == null ? '' : substitutedUrl);
            const encodedKey = encodeURIComponent(keyword);
            if (!/^@js:/i.test(rawSearchUrl) && !/^<js>[\s\S]*<\/js>$/i.test(rawSearchUrl.trim())) substitutedUrl = rawSearchUrl
                .replace(/\{\{key\}\}/g, encodedKey)
                .replace(/\{\{page\}\}/g, String(page))
                .replace(/\{\{page\+1\}\}/g, String(page + 1));

            // Remaining {{...}} templates evaluate as JS with key/page/baseUrl/java.
            substitutedUrl = substitutedUrl.replace(/\{\{([\s\S]*?)\}\}/g, (whole, expr) => {
                try {
                    const val = evaluateUrlScript(expr);
                    return val === undefined || val === null ? '' : String(val);
                } catch (e) {
                    return whole;
                }
            });

            const defaultHeaders = LegadoEngine.parseHeaderMap(source.header);
            return LegadoEngine.formatRequest(source.bookSourceUrl, substitutedUrl, defaultHeaders);
        }

        static parseSearchResult(source, responseText, baseUrl = '') {
            if (!source || !source.ruleSearch || !responseText) return [];
            const rule = source.ruleSearch;
            const base = baseUrl || source.bookSourceUrl;
            const variables = ruleVariables(source);

            const items = RuleAnalyzer.extractList(responseText, rule.bookList, base, variables);

            const books = [];
            for (let i = 0; i < items.length; i++) {
                const el = items[i];
                const name = RuleAnalyzer.extractString(el, rule.name, base, variables);
                if (!name) continue;

                const author = RuleAnalyzer.extractString(el, rule.author, base, variables);
                let bookUrl = RuleAnalyzer.extractString(el, rule.bookUrl, base, variables);
                if (!bookUrl && (el instanceof Node)) {
                    bookUrl = el.attr('href') || (el.selectFirst('a') ? el.selectFirst('a').attr('href') : '');
                }
                bookUrl = resolveUrl(base, bookUrl);

                const coverUrl = RuleAnalyzer.extractString(el, rule.coverUrl, base, variables);
                const intro = RuleAnalyzer.extractString(el, rule.intro, base, variables);
                const latestChapter = RuleAnalyzer.extractString(el, rule.lastChapter, base, variables);
                const kind = RuleAnalyzer.extractString(el, rule.kind, base, variables);
                const wordCount = RuleAnalyzer.extractString(el, rule.wordCount, base, variables);

                books.push({
                    name: name.replace(/^[《<]|(》|>)$/g, '').trim(),
                    author: author.trim(),
                    bookUrl: bookUrl || `${source.bookSourceUrl}#${name}_${author}`,
                    coverUrl: coverUrl ? resolveUrl(base, coverUrl) : null,
                    intro: intro ? intro.trim() : null,
                    latestChapterTitle: latestChapter ? latestChapter.trim() : null,
                    kind: kind ? kind.trim() : null,
                    wordCount: wordCount ? wordCount.trim() : null,
                    origin: source.bookSourceUrl,
                    originName: source.bookSourceName
                });
            }

            return books;
        }

        static parseExploreCategories(exploreUrl) {
            if (!exploreUrl || !exploreUrl.trim()) return [];
            const trimmed = exploreUrl.trim();

            if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
                try {
                    const arr = JSON.parse(trimmed);
                    const list = [];
                    for (const item of arr) {
                        const title = item.title || item.name || '未知分类';
                        const url = item.url || '';
                        if (url) list.push({ title: String(title).trim(), url: String(url).trim() });
                    }
                    if (list.length > 0) return list;
                } catch (e) {}
            }

            const lines = trimmed.split('\n');
            const result = [];
            for (let line of lines) {
                line = line.trim();
                if (!line) continue;
                if (line.includes('::')) {
                    const parts = line.split('::');
                    const title = parts[0].trim();
                    let url = parts[1].trim();
                    if (url.includes('&&{')) url = url.substring(0, url.indexOf('&&{')).trim();
                    if (url) result.push({ title, url });
                } else if (/^(https?:|\/)/i.test(line)) {
                    result.push({ title: '全部推荐', url: line });
                }
            }
            return result;
        }

        static parseBookInfo(source, responseText, baseUrl = '', book = null) {
            if (!source || !source.ruleBookInfo || !responseText) return book;
            const rule = source.ruleBookInfo;
            const base = baseUrl || (book && book.bookUrl) || source.bookSourceUrl;
            const variables = ruleVariables(source);
            let infoResponse = responseText;
            if (rule.init) {
                const initRule = String(rule.init).trim();
                const initialized = RuleAnalyzer.extractString(responseText, initRule, base, variables);
                // @put is a state initializer; JS init scripts may return transformed JSON.
                if (!initRule.startsWith('@put:') && initialized) infoResponse = initialized;
            }

            const name = RuleAnalyzer.extractString(infoResponse, rule.name, base, variables);
            const author = RuleAnalyzer.extractString(infoResponse, rule.author, base, variables);
            const intro = RuleAnalyzer.extractString(infoResponse, rule.intro, base, variables);
            const coverUrl = RuleAnalyzer.extractString(infoResponse, rule.coverUrl, base, variables);
            const tocUrl = RuleAnalyzer.extractString(infoResponse, rule.tocUrl, base, variables);
            const kind = RuleAnalyzer.extractString(infoResponse, rule.kind, base, variables);
            const wordCount = RuleAnalyzer.extractString(infoResponse, rule.wordCount, base, variables);
            const latestChapter = RuleAnalyzer.extractString(infoResponse, rule.lastChapter, base, variables);

            const parsedBook = Object.assign({}, book || {}, {
                name: name ? name.trim() : (book ? book.name : ''),
                author: author ? author.trim() : (book ? book.author : ''),
                intro: intro ? intro.trim() : (book ? book.intro : null),
                coverUrl: coverUrl ? resolveUrl(base, coverUrl) : (book ? book.coverUrl : null),
                tocUrl: tocUrl ? resolveUrl(base, tocUrl) : null,
                kind: kind ? kind.trim() : (book ? book.kind : null),
                wordCount: wordCount ? wordCount.trim() : (book ? book.wordCount : null),
                latestChapterTitle: latestChapter ? latestChapter.trim() : (book ? book.latestChapterTitle : null)
            });
            Object.assign(getSourceContext(source).book, parsedBook);
            return parsedBook;
        }

        static parseToc(source, responseText, baseUrl = '', book = null) {
            if (!source || !source.ruleToc || !responseText) return { chapters: [], nextTocUrl: null };
            const rule = source.ruleToc;
            const context = getSourceContext(source);
            const bookContext = book || context.book;
            if (book) Object.assign(context.book, book);
            const base = baseUrl || (bookContext && bookContext.bookUrl) || source.bookSourceUrl;
            const variables = ruleVariables(source);
            variables.book = bookContext;

            let items = RuleAnalyzer.extractList(responseText, rule.chapterList, base, variables);
            if (items.length === 0 && typeof responseText === 'string') {
                const doc = parseHTML(responseText);
                items = doc.select('#list dd a, .catalog a, #chapter-list a, .mulu a, #readerlist li a, .listmain dd a');
            }

            // nextTocUrl may point at a pagination link that also matched the
            // chapter list; resolve it first so that item can be excluded.
            let nextTocUrl = null;
            if (rule.nextTocUrl) {
                const rawNext = RuleAnalyzer.extractString(responseText, rule.nextTocUrl, base, variables);
                if (rawNext && rawNext.trim()) nextTocUrl = resolveUrl(base, rawNext.trim());
            }

            const chapters = [];
            for (let idx = 0; idx < items.length; idx++) {
                const el = items[idx];
                let title = RuleAnalyzer.extractString(el, rule.chapterName, base, variables);
                if (!title && (el instanceof Node)) title = el.text().trim();
                if (!title) continue;

                let rawUrl = RuleAnalyzer.extractString(el, rule.chapterUrl, base, variables);
                if (!rawUrl && (el instanceof Node)) {
                    rawUrl = el.attr('href') || (el.selectFirst('a') ? el.selectFirst('a').attr('href') : '');
                }
                const chapterUrl = resolveUrl(base, rawUrl);

                // Skip the pagination link if it leaked into the chapter list.
                if (nextTocUrl && chapterUrl === nextTocUrl) continue;

                let isVip = false;
                if (rule.isVip) {
                    const vipVal = RuleAnalyzer.extractString(el, rule.isVip, base, variables);
                    isVip = !(vipVal === '' || vipVal === 'null' || vipVal === 'false' || vipVal === '0');
                }

                let chapterInfo = '';
                if (rule.chapterInfo) {
                    chapterInfo = RuleAnalyzer.extractString(el, rule.chapterInfo, base, variables) || '';
                }

                chapters.push({
                    title: title.trim(),
                    url: chapterUrl || `${base}#${idx}`,
                    index: chapters.length,
                    bookUrl: bookContext ? bookContext.bookUrl || '' : '',
                    isVip: isVip,
                    chapterInfo: chapterInfo
                });
            }

            return { chapters, nextTocUrl };
        }

        static parseContent(source, responseText, baseUrl = '') {
            if (!source || !source.ruleContent || !responseText) return { content: '', nextContentUrl: null };
            const rule = source.ruleContent;
            const base = baseUrl || source.bookSourceUrl;
            const variables = ruleVariables(source);

            let content = RuleAnalyzer.extractString(responseText, rule.content, base, variables);

            if (!content && typeof responseText === 'string') {
                const doc = parseHTML(responseText);
                const heuristic = doc.selectFirst('#content, .content, #chaptercontent, .read-content, #htmlContent, .showtxt, .article-content, #ChapterContents, .textarticle, .con');
                content = heuristic ? heuristic.html() : '';
            }

            if (rule.replaceRegex) {
                const parts = rule.replaceRegex.split('##');
                if (parts.length >= 2) {
                    const pattern = parts[1];
                    const replacement = parts.length >= 3 ? parts[2] : '';
                    if (pattern) {
                        try {
                            const reg = new RegExp(pattern, 'g');
                            content = content.replace(reg, replacement);
                        } catch (e) {}
                    }
                }
            }

            content = content
                .replace(/<br\s*\/?>/gi, '\n')
                .replace(/<\/p>/gi, '\n\n')
                .replace(/<p[^>]*>/gi, '　　')
                .replace(/<[^>]+>/g, '')
                .replace(/&nbsp;/gi, ' ')
                .replace(/&lt;/gi, '<')
                .replace(/&gt;/gi, '>')
                .replace(/&amp;/gi, '&')
                .replace(/\n{3,}/g, '\n\n')
                .trim();

            let nextContentUrl = null;
            if (rule.nextContentUrl) {
                const rawNext = RuleAnalyzer.extractString(responseText, rule.nextContentUrl, base, variables);
                if (rawNext && rawNext.trim()) nextContentUrl = resolveUrl(base, rawNext.trim());
            }

            return { content, nextContentUrl };
        }
    }

    global.Legado = {
        Node,
        parseHTML,
        RuleAnalyzer,
        JsHost,
        CookieStore,
        LegadoEngine,
        evalLegadoScript,
        md5,
        base64Encode,
        base64Decode,
        resolveUrl,
        getScriptDiagnostics() { return scriptDiagnostics.slice(); },
        clearScriptDiagnostics() { scriptDiagnostics.length = 0; },
        clearSourceContext(source) { sourceContexts.delete(sourceKey(source)); memoryStores.delete(sourceKey(source)); }
    };

})(typeof globalThis !== 'undefined' ? globalThis : this);
