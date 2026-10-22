# Native rule engine build

`make -C engine host` builds the host library; `make -C engine cross` builds the AArch64 muOS library. The build pins libxml2 2.15.4 by SHA-256, extracts it under `engine/build/libxml2-src` (override with `CACHE_ROOT`), and keeps CMake/build products under `engine/build/`. The checked-in source archive permits offline builds. HTML parsing, XPath, output and iconv are retained, while unused features such as ICU, zlib, catalog, schema validation and reader/writer support are disabled; libxml2 is linked statically and hidden inside the rule-engine library. The AArch64 build retains the existing cosh/sinh compatibility wrappers and targets the muOS glibc 2.38 runtime.

`make -C engine test` runs native XPath bridge cases. The project-level `make test` runs the app's offline regression suite. Packaging has not been deployed to or tested on a device.
