// zig-protobuf smoke: the generated code of protobuf_smoke.proto (protoc
// 29.5's output, #included below: pkgtest links one source file) against
// libprotobuf. A Shape with repeated, map, bytes, enum and optional fields
// is serialized, parsed back and compared; the same bytes parse through the
// MessageLite interface; the descriptor and reflection see the schema;
// TextFormat prints and parses it (MessageDifferencer compares). Where it
// runs (Windows), the package's own protoc.exe
// (<PREFIX>/Library/zig-libs/<triple>/bin) must print "libprotoc 29.5" and
// regenerate protobuf_smoke.pb.h and .pb.cc byte for byte. Prints the
// results and a last line OK; exit 0 when all match.
#include <cstdio>
#include <cstdlib>
#include <string>

#include <direct.h>

#include "google/protobuf/descriptor.h"
#include "google/protobuf/message_lite.h"
#include "google/protobuf/text_format.h"
#include "google/protobuf/util/message_differencer.h"

#include "protobuf_smoke.pb.cc"

#if defined(PROTOBUF_USE_DLLS)
#error "PROTOBUF_USE_DLLS is set: zig-protobuf is static"
#endif

#if defined(__aarch64__)
#define ZT "aarch64-windows-gnu"
#else
#define ZT "x86_64-windows-gnu"
#endif

static int bad = 0;

static void check(bool ok, const char *what) {
  std::printf("%s: %s\n", what, ok ? "ok" : "FAIL");
  if (!ok) bad++;
}

static std::string slurp(const std::string &path, bool *found) {
  std::string s;
  FILE *f = std::fopen(path.c_str(), "rb");
  *found = f != nullptr;
  if (!f) return s;
  char buf[4096];
  size_t n;
  while ((n = std::fread(buf, 1, sizeof buf, f)) > 0) s.append(buf, n);
  std::fclose(f);
  return s;
}

// cmd.exe /c strips the outer quotes of the whole line, so a quoted program
// path with quoted arguments needs one more pair around everything
static std::string run(const std::string &cmd, int *status) {
  std::string line = "\"" + cmd + "\"";
  std::string out;
  FILE *p = _popen(line.c_str(), "r");
  if (!p) {
    *status = -1;
    return out;
  }
  char buf[512];
  while (std::fgets(buf, sizeof buf, p)) out += buf;
  *status = _pclose(p);
  return out;
}

static void protoc_checks() {
  const char *prefix = std::getenv("PREFIX");
  if (!prefix) {
    std::printf("protoc: PREFIX not set, not checked\n");
    return;
  }
  std::string protoc = std::string(prefix) + "\\Library\\zig-libs\\" ZT "\\bin\\protoc.exe";
  int st = 0;
  std::string v = run("\"" + protoc + "\" --version", &st);
  while (!v.empty() && (v.back() == '\n' || v.back() == '\r')) v.pop_back();
  std::printf("protoc --version: %s\n", v.c_str());
  check(st == 0 && v == "libprotoc 29.5", "protoc --version is libprotoc 29.5");

  const std::string dir = "zig-libs-tests/smoke";
  const std::string gen = "protobuf-smoke-gen";
  _mkdir(gen.c_str());
  run("\"" + protoc + "\" -I" + dir + " --cpp_out=" + gen + " " + dir + "/protobuf_smoke.proto", &st);
  check(st == 0, "protoc.exe --cpp_out ran");
  for (const char *f : {"protobuf_smoke.pb.h", "protobuf_smoke.pb.cc"}) {
    bool have_ref = false, have_new = false;
    std::string ref = slurp(dir + "/" + f, &have_ref);
    std::string got = slurp(gen + "/" + f, &have_new);
    std::string what = std::string("protoc.exe regenerates ") + f + " byte for byte";
    check(have_ref && have_new && ref == got, what.c_str());
  }
}

int main() {
  zigsmoke::Shape s;
  s.set_name("triangle");
  s.set_kind(zigsmoke::Shape::POLYGON);
  for (int i = 0; i < 3; i++) {
    zigsmoke::Point *p = s.add_points();
    p->set_x(i * 10 - 5);
    p->set_y(-i * 7);
  }
  (*s.mutable_tags())["area"] = 12.5;
  (*s.mutable_tags())["scale"] = -0.25;
  s.set_blob(std::string("\x00\x01\xff zig", 7));
  s.set_id(1234567890123LL);

  std::string wire;
  check(s.SerializeToString(&wire), "SerializeToString");
  std::printf("wire size: %zu bytes\n", wire.size());

  zigsmoke::Shape t;
  check(t.ParseFromString(wire), "ParseFromString");
  check(t.name() == "triangle" && t.kind() == zigsmoke::Shape::POLYGON && t.points_size() == 3 &&
            t.points(2).x() == 15 && t.points(2).y() == -14 && t.tags().at("area") == 12.5 &&
            t.tags().at("scale") == -0.25 && t.blob() == std::string("\x00\x01\xff zig", 7) &&
            t.has_id() && t.id() == 1234567890123LL,
        "round trip fields");

  // the lite interface: the same bytes, through MessageLite
  zigsmoke::Shape u;
  google::protobuf::MessageLite &lite = u;
  check(lite.ParseFromString(wire) && lite.SerializeAsString().size() == wire.size() &&
            lite.GetTypeName() == "zigsmoke.Shape",
        "MessageLite parse and type name");

  const google::protobuf::Descriptor *d = zigsmoke::Shape::descriptor();
  const google::protobuf::FieldDescriptor *f = d->FindFieldByName("points");
  check(d->full_name() == "zigsmoke.Shape" && d->field_count() == 6 && f && f->is_repeated() &&
            f->message_type()->full_name() == "zigsmoke.Point",
        "descriptor");
  const google::protobuf::Reflection *r = t.GetReflection();
  check(r->FieldSize(t, f) == 3 && r->GetString(t, d->FindFieldByName("name")) == "triangle", "reflection");

  std::string text;
  check(google::protobuf::TextFormat::PrintToString(t, &text), "TextFormat print");
  zigsmoke::Shape w;
  // map order differs between two maps: compare with MessageDifferencer
  check(google::protobuf::TextFormat::ParseFromString(text, &w) &&
            google::protobuf::util::MessageDifferencer::Equals(w, t),
        "TextFormat parse (MessageDifferencer)");

  protoc_checks();

  if (bad) {
    std::printf("%d check(s) failed\n", bad);
    return 1;
  }
  std::printf("OK\n");
  return 0;
}
