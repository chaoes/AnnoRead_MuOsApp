/*
 * aarch64 cross-build compatibility shim for muOS (glibc 2.38, Buildroot).
 *
 * The host cross toolchain (glibc 2.44 headers) makes GCC emit calls to
 * cosh@GLIBC_2.44 / sinh@GLIBC_2.44, which the RG CubeXX firmware does not
 * provide (its libm tops out at GLIBC_2.38). Referencing those symbols would
 * make the shared object fail to load on device.
 *
 * We link with `-Wl,--wrap=cosh -Wl,--wrap=sinh` so every internal reference to
 * cosh()/sinh() is redirected to __wrap_* below, which are implemented purely on
 * top of exp() (available as GLIBC_2.29 on device). This keeps the object free
 * of any symbol newer than GLIBC_2.38.
 *
 * Compiled with -fno-builtin so the compiler does not pattern-match these back
 * into cosh/sinh calls.
 */

#include <math.h>

double __wrap_cosh(double x) {
    double e = exp(x);
    return (e + 1.0 / e) * 0.5;
}

double __wrap_sinh(double x) {
    double e = exp(x);
    return (e - 1.0 / e) * 0.5;
}
