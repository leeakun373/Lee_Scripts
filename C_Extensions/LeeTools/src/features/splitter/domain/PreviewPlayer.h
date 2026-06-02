#pragma once

#include <atomic>
#include <cstdint>
#include <thread>

#include "features/splitter/domain/AudioBuffer.h"
#include "features/splitter/domain/ItemSnapshot.h"
#include "features/splitter/domain/SplitMode.h"
#include "features/splitter/domain/SplitParams.h"

namespace lee::splitter {

// Algorithm-mode layer preview (spec section 6). DSP runs off the UI thread;
// playback uses REAPER preview API on the main thread via tick().
class PreviewPlayer {
 public:
  ~PreviewPlayer();
  void Stop();
  void Tick(void* proj);

  bool RequestLayer(void* proj, const ItemSnapshot& snap, AlgoMode mode, const SplitParams& params,
                    Layer layer, bool route_to_track);

  bool is_playing() const { return playing_; }
  bool is_working() const { return working_.load(); }
  Layer active_layer() const { return active_layer_; }

 private:
  void join_worker();
  void halt_playback();
  void release_pcm_source();
  bool start_play(void* proj, const ItemSnapshot& snap, const AudioBuffer& buf, bool route_to_track);

  bool playing_ = false;
  Layer active_layer_ = Layer::Layer1;
  bool preg_init_ = false;
  alignas(16) unsigned char preg_storage_[160];

  void* preview_src_ = nullptr;
  std::atomic<uint64_t> generation_{0};

  std::atomic<bool> working_{false};
  std::thread worker_;
  ItemSnapshot pending_snap_;
  Layer pending_layer_ = Layer::Layer1;
  bool pending_route_ = false;
  void* pending_proj_ = nullptr;
  AudioBuffer pending_audio_;
  std::atomic<bool> pending_ready_{false};
  std::atomic<bool> pending_failed_{false};
  uint64_t pending_generation_ = 0;
};

}  // namespace lee::splitter
