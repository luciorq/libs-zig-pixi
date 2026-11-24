// zig-gmp smoke test: the C++ bindings (gmpxx, libc++), prints OK.
#include <gmpxx.h>
#include <iostream>
#include <sstream>

int main() {
    mpz_class a("123456789012345678901234567890");
    mpz_class sq = a * a;
    const char *want = "15241578753238836750495351562536198787501905199875019052100";
    if (sq.get_str() != want) {
        std::cout << "FAIL: a*a = " << sq << " (want " << want << ")\n";
        return 1;
    }
    mpq_class r(1, 3);
    r += mpq_class(1, 6);
    std::ostringstream s;
    s << r;
    if (s.str() != "1/2") {
        std::cout << "FAIL: 1/3 + 1/6 = " << s.str() << " (want 1/2)\n";
        return 1;
    }
    std::cout << "gmpxx: a*a = " << sq << "\nOK\n";
    return 0;
}
