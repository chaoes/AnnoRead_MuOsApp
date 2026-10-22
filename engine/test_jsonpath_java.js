import './legado.js';
const L = globalThis.Legado;

function assert(condition, message) {
    if (!condition) throw new Error("Assertion Failed: " + message);
}

console.log("=== Testing JSONPath Filter Predicates & Java Edge Methods ===");

// 1. JSONPath filter predicate [?(@.price > 10)]
const json = {
    store: {
        book: [
            { title: "书A", price: 5, category: "fiction" },
            { title: "书B", price: 15, category: "fiction" },
            { title: "书C", price: 25, category: "science" }
        ]
    }
};

const filtered = L.RuleAnalyzer.extractList(json, '$.store.book[?(@.price > 10)].title');
console.log("filtered titles:", JSON.stringify(filtered));
assert(filtered.length === 2, "Expected 2 filtered books, got " + filtered.length);
assert(filtered[0] === "书B" && filtered[1] === "书C", "Filter values mismatch");

// 2. JSONPath equality filter [?(@.category == 'science')]
const scienceBooks = L.RuleAnalyzer.extractList(json, '$.store.book[?(@.category == "science")].title');
assert(scienceBooks.length === 1 && scienceBooks[0] === "书C", "Category filter failed");

// 3. java.hexEncode / java.hexDecode / java.digest
const h = new L.JsHost('');
assert(h.hexEncode("abc") === "616263", "hexEncode failed");
assert(h.hexDecode("616263") === "abc", "hexDecode failed");
assert(h.digest("MD5", "abc").toLowerCase() === "900150983cd24fb0d6963f7d28e17f72", "java.digest MD5 failed");

// 4. Root Array Filter $[?(@.x > 1)] & slice $[-2:]
const rootArr = [{ id: 1, name: "N1" }, { id: 2, name: "N2" }, { id: 3, name: "N3" }];
const rootFiltered = L.RuleAnalyzer.extractList(rootArr, '$[?(@.id > 1)].name');
assert(rootFiltered.length === 2 && rootFiltered[0] === "N2", "Root array filter failed");
const sliced = L.RuleAnalyzer.extractList(rootArr, '$[-2:].name');
assert(sliced.length === 2 && sliced[0] === "N2" && sliced[1] === "N3", "Array slice failed");

console.log("✔ All JSONPath and java edge methods tests passed!");
