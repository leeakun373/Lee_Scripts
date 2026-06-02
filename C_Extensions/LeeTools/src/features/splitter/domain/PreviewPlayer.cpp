#include "features/splitter/domain/PreviewPlayer.h"

#include <windows.h>

#include "reaper_plugin.h"

#include "features/splitter/domain/AudioReader.h"
#include "features/splitter/domain/SplitEngine.h"
#include "features/splitter/domain/WavWriter.h"
#include "plugin/PluginContext.h"

namespace lee::splitter {

namespace {
preview_register_t* AsPreg(unsigned char* storage) {
  return reinterpret_cast<preview_register_t*>(storage);
}
}  // namespace

PreviewPlayer::~PreviewPlayer() {
  Stop();
  if (preg_init_) {
    DeleteCriticalSection(&AsPreg(preg_storage_)->cs);
    preg_init_ = false;
  }
}

void PreviewPlayer::join_worker() {
  if (worker_.joinable()) worker_.join();
  working_.store(false);
}

void PreviewPlayer::halt_playback() {
  const auto& api = lee::Api();
  if (preg_init_ && api.StopPreview) {
    api.StopPreview(reinterpret_cast<void*>(preg_storage_));
  }
  playing_ = false;
}

void PreviewPlayer::release_pcm_source() {
  const auto& api = lee::Api();
  if (preview_src_ && api.PCM_Source_Destroy) {
    api.PCM_Source_Destroy(preview_src_);
    preview_src_ = nullptr;
  }
  if (preg_init_) AsPreg(preg_storage_)->src = nullptr;
}

void PreviewPlayer::Stop() {
  ++generation_;
  halt_playback();
  release_pcm_source();
  join_worker();
  pending_ready_.store(false);
  pending_failed_.store(false);
}

bool PreviewPlayer::start_play(void* proj, const ItemSnapshot& snap, const AudioBuffer& buf,
                               bool route_to_track) {
  const auto& api = lee::Api();
  if (!api.PCM_Source_CreateFromFile || !api.PlayPreview) return false;

  halt_playback();
  release_pcm_source();

  const std::string path = MakeTempWavPath("preview");
  if (!WriteWav24(path, buf)) return false;

  void* src = api.PCM_Source_CreateFromFile(path.c_str());
  if (!src) return false;

  preview_register_t* preg = AsPreg(preg_storage_);
  if (!preg_init_) {
    InitializeCriticalSection(&preg->cs);
    preg_init_ = true;
  }

  preview_src_ = src;
  preg->src = static_cast<PCM_source*>(src);
  preg->volume = 1.0;
  preg->loop = false;
  preg->curpos = 0.0;
  preg->peakvol[0] = preg->peakvol[1] = 0.0;
  preg->preview_track = nullptr;
  preg->m_out_chan = 0;

  int ok = 0;
  if (route_to_track && snap.track && api.PlayTrackPreview2) {
    preg->m_out_chan = -1;
    preg->preview_track = snap.track;
    ok = api.PlayTrackPreview2(proj, reinterpret_cast<void*>(preg_storage_));
  } else {
    ok = api.PlayPreview(reinterpret_cast<void*>(preg_storage_));
  }
  if (!ok) {
    release_pcm_source();
    return false;
  }
  playing_ = true;
  return true;
}

bool PreviewPlayer::RequestLayer(void* proj, const ItemSnapshot& snap, AlgoMode mode,
                                 const SplitParams& params, Layer layer, bool route_to_track) {
  if (playing_ && layer == active_layer_) {
    Stop();
    return true;
  }
  Stop();

  AudioBuffer in;
  if (!ReadItemAudio(snap, in)) return false;

  const uint64_t gen = ++generation_;
  pending_proj_ = proj;
  pending_snap_ = snap;
  pending_layer_ = layer;
  pending_route_ = route_to_track;
  pending_generation_ = gen;
  pending_ready_.store(false);
  pending_failed_.store(false);
  working_.store(true);

  const AudioBuffer in_copy = in;
  const SplitParams params_copy = params;
  worker_ = std::thread([this, in_copy, mode, params_copy, layer, gen]() {
    AudioBuffer out;
    if (!ProduceLayer(in_copy, mode, params_copy, layer, out)) {
      if (generation_.load() == gen) pending_failed_.store(true);
      working_.store(false);
      return;
    }
    if (generation_.load() != gen) {
      working_.store(false);
      return;
    }
    pending_audio_ = std::move(out);
    pending_ready_.store(true);
    working_.store(false);
  });
  return true;
}

void PreviewPlayer::Tick(void* proj) {
  if (!pending_ready_.load() && !pending_failed_.load()) return;

  join_worker();

  if (generation_.load() != pending_generation_) {
    pending_ready_.store(false);
    pending_failed_.store(false);
    return;
  }

  if (pending_failed_.load()) {
    pending_failed_.store(false);
    return;
  }
  if (!pending_ready_.load()) return;
  pending_ready_.store(false);

  if (start_play(proj, pending_snap_, pending_audio_, pending_route_)) {
    active_layer_ = pending_layer_;
  }
}

}  // namespace lee::splitter
