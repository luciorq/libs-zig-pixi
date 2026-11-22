// zig-onetbb smoke: tbb::parallel_for sums 1..1e6 over a blocked_range and
// must run on more than one thread (when the machine has more than one).
// Prints OK on success.
#include <oneapi/tbb/blocked_range.h>
#include <oneapi/tbb/info.h>
#include <oneapi/tbb/parallel_for.h>
#include <oneapi/tbb/task_arena.h>
#include <oneapi/tbb/version.h>

#include <atomic>
#include <chrono>
#include <cstdio>
#include <thread>
#include <vector>

int main() {
  const long long n = 1000000;
  const int conc = tbb::info::default_concurrency();
  std::printf("oneTBB %s, default_concurrency %d\n", TBB_runtime_version(), conc);
  std::atomic<long long> sum{0};
  std::vector<std::atomic<int>> seen(static_cast<size_t>(conc) + 1);
  tbb::parallel_for(tbb::blocked_range<long long>(1, n + 1, 1000),
                    [&](const tbb::blocked_range<long long>& r) {
                      long long s = 0;
                      for (long long i = r.begin(); i != r.end(); ++i) s += i;
                      sum += s;
                      int t = tbb::this_task_arena::current_thread_index();
                      if (t >= 0 && t <= conc) seen[static_cast<size_t>(t)] = 1;
                      // keep each chunk busy long enough for workers to join
                      std::this_thread::sleep_for(std::chrono::microseconds(200));
                    });
  int threads = 0;
  for (auto& x : seen) threads += x.load();
  const long long want = n * (n + 1) / 2;
  std::printf("sum %lld (want %lld), threads used %d\n", sum.load(), want, threads);
  if (sum.load() != want) return 1;
  if (conc > 1 && threads < 2) return 2;
  std::puts("OK");
  return 0;
}
