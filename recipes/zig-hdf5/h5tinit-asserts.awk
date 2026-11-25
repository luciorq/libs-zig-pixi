# H5Tinit.c (H5detect's output) -> C11 _Static_asserts of every layout
# value it sets, to compile for the target with H5pubconf.h on the include
# path (build.sh). Fails (exit 1) on a type name it does not know or a
# file without the expected values.
function ctype(n) {
  if (n == "SCHAR") return "signed char"
  if (n == "UCHAR") return "unsigned char"
  if (n == "SHORT") return "short"
  if (n == "USHORT") return "unsigned short"
  if (n == "INT") return "int"
  if (n == "UINT") return "unsigned int"
  if (n == "LONG") return "long"
  if (n == "ULONG") return "unsigned long"
  if (n == "LLONG") return "long long"
  if (n == "ULLONG") return "unsigned long long"
  if (n == "FLOAT") return "float"
  if (n == "DOUBLE") return "double"
  if (n == "LDOUBLE") return "long double"
  if (n ~ /^U?INT(_LEAST|_FAST)?(8|16|32|64)$/) return tolower(n) "_t"
  if (n == "POINTER") return "void *"
  if (n == "HVL") return "hvl_t"
  if (n == "HOBJREF") return "hobj_ref_t"
  if (n == "HDSETREGREF") return "hdset_reg_ref_t"
  if (n == "REF") return "H5R_ref_t"
  print "h5tinit-asserts: unknown type " n > "/dev/stderr"; bad = 1; exit 1
}
function fprefix(n) {
  if (n == "FLOAT") return "FLT"
  if (n == "DOUBLE") return "DBL"
  if (n == "LDOUBLE") return "LDBL"
  print "h5tinit-asserts: unknown float type " n > "/dev/stderr"; bad = 1; exit 1
}
function check(expr) { printf "_Static_assert(%s, \"%s\");\n", expr, expr; n_checks++ }
function val(line) { sub(/^[^=]*= */, "", line); sub(/;.*$/, "", line); return line }
BEGIN {
  print "#include <stddef.h>"
  print "#include <stdint.h>"
  print "#include <float.h>"
  print "#include \"hdf5.h\""
}
{ sub(/\r$/, "") }
/dt->shared->type = / { kind = val($0); delete f; next }
/dt->shared->size = / { f["size"] = val($0); next }
/dt->shared->u\.atomic\.(prec|offset|order) = / {
  k = $0; sub(/^.*u\.atomic\./, "", k); sub(/ .*$/, "", k); f[k] = val($0); next
}
/dt->shared->u\.atomic\.u\.i\.sign = / { f["isign"] = val($0); next }
/dt->shared->u\.atomic\.u\.f\.[a-z]+ = / {
  k = $0; sub(/^.*u\.atomic\.u\.f\./, "", k); sub(/ .*$/, "", k); f["f" k] = val($0); next
}
/if\(\(H5T_NATIVE_[A-Z0-9_]+_g = H5I_register/ {
  name = $0; sub(/^.*H5T_NATIVE_/, "", name); sub(/_g = .*$/, "", name)
  t = ctype(name); n_types++
  check("sizeof(" t ") == " f["size"])
  check("H5T_ORDER_LE == " f["order"] " && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__")
  check(f["offset"] " == 0")
  if (kind == "H5T_INTEGER") {
    check(f["prec"] " == 8 * sizeof(" t ")")
    if (f["isign"] == "H5T_SGN_2") check("(" t ")-1 < 0")
    else check("(" t ")-1 > 0")
  } else if (kind == "H5T_FLOAT") {
    p = fprefix(name)
    implied = (f["fnorm"] == "H5T_NORM_IMPLIED") ? 1 : 0
    check("FLT_RADIX == 2")
    check(f["fmpos"] " == 0")
    check(f["fmsize"] " == " p "_MANT_DIG - " implied)
    check("(1LL << (" f["fesize"] " - 1)) == " p "_MAX_EXP")
    check(f["febias"] " == " p "_MAX_EXP - 1")
    check(f["fepos"] " == " f["fmsize"])
    check(f["fsign"] " == " f["fepos"] " + " f["fesize"])
    check(f["prec"] " == " f["fsign"] " + 1")
  } else { print "h5tinit-asserts: unknown kind " kind > "/dev/stderr"; bad = 1; exit 1 }
  next
}
/^ *H5T_(NATIVE_)?[A-Z0-9_]+_COMP_ALIGN_g = / {
  name = $0; sub(/^ *H5T_(NATIVE_)?/, "", name); sub(/_COMP_ALIGN_g = .*$/, "", name)
  t = ctype(name); n_align++
  check("offsetof(struct { char c; " t " x; }, x) == " val($0))
  next
}
/H5T_native_order_g = / { check(val($0) " == H5T_ORDER_LE"); next }
END {
  if (bad) exit 1
  # H5detect 1.12.1 writes 37 native types, the struct alignment of 8 of
  # them and of 5 pointer, vlen and reference types
  if (n_types != 37 || n_align != 13) {
    printf "h5tinit-asserts: %d types, %d alignments (expected 37, 13)\n", n_types, n_align > "/dev/stderr"
    exit 1
  }
}
