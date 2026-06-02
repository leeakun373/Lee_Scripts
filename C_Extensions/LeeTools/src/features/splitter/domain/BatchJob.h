#pragma once

#include <atomic>
#include <string>
#include <thread>
#include <vector>

#include "features/splitter/domain/AudioBuffer.h"
#include "features/splitter/domain/ItemSnapshot.h"
#include "features/splitter/domain/SplitMode.h"
#include "features/splitter/domain/SplitParams.h"

namespace lee::splitter {

// One processing batch. DSP runs on worker threads; all REAPER reads happen in
// start() (main thread) and all writes happen in tick() (main thread).
class BatchJob {
 public:
  enum class State { Idle, Processing, Done, Cancelled, Failed };

  ~BatchJob();

  // snaps: pre-captured item snapshots. layers/suffixes: parallel arrays of the
  // output layers to render (1 for Quick, 2 for Algorithm Process).
  bool Start(void* proj, std::vector<ItemSnapshot> snaps, AlgoMode mode, SplitParams params,
             std::vector<Layer> layers, std::vector<std::string> suffixes);

  void Cancel();
  // Stop workers, join, return to Idle (call when closing the window).
  void ForceStop();
  void Tick();  // main thread

  bool running() const { return state_ == State::Processing; }
  State state() const { return state_; }
  int total() const { return total_; }
  int done() const { return done_.load(); }
  int ok() const { return ok_; }

 private:
  void join_workers();
  void do_writes();

  State state_ = State::Idle;
  void* proj_ = nullptr;
  AlgoMode mode_ = AlgoMode::TransientSustain;
  SplitParams params_;
  std::vector<Layer> layers_;
  std::vector<std::string> suffixes_;

  std::vector<ItemSnapshot> snaps_;
  std::vector<AudioBuffer> inputs_;
  std::vector<std::vector<AudioBuffer>> outputs_;  // [item][layer]
  std::vector<char> item_ok_;                      // 1 if DSP succeeded for item

  std::vector<std::thread> workers_;
  std::atomic<int> next_index_{0};
  std::atomic<int> active_workers_{0};
  std::atomic<int> done_{0};
  std::atomic<bool> cancel_{false};
  bool wrote_ = false;

  int total_ = 0;
  int ok_ = 0;
};

}  // namespace lee::splitter
