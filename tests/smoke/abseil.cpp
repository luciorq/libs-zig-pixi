// zig-abseil smoke: absl::StrCat, absl::flat_hash_map and absl::Mutex with
// threads. Prints the results and a last line OK; exit 0 when all match.
#include <cstdio>
#include <string>
#include <thread>
#include <vector>

#include "absl/base/thread_annotations.h"
#include "absl/container/flat_hash_map.h"
#include "absl/strings/str_cat.h"
#include "absl/synchronization/mutex.h"

int main() {
  int bad = 0;

  std::string s = absl::StrCat("abseil ", 20250127, " ", 1.5, " ", true);
  std::printf("StrCat: %s\n", s.c_str());
  if (s != "abseil 20250127 1.5 1") bad++;

  absl::flat_hash_map<std::string, int> m;
  for (int i = 0; i < 1000; i++) m[absl::StrCat("k", i)] = i * i;
  std::printf("flat_hash_map: size %zu, k31 = %d\n", m.size(), m["k31"]);
  if (m.size() != 1000 || m["k31"] != 961) bad++;

  absl::Mutex mu;
  long total = 0;
  std::vector<std::thread> threads;
  for (int t = 0; t < 4; t++)
    threads.emplace_back([&] {
      for (int i = 0; i < 10000; i++) {
        absl::MutexLock lock(&mu);
        total++;
      }
    });
  for (auto& th : threads) th.join();
  std::printf("Mutex: 4 threads x 10000 = %ld\n", total);
  if (total != 40000) bad++;

  if (bad) return 1;
  std::printf("OK\n");
  return 0;
}
