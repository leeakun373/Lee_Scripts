#include "features/splitter/domain/BatchJob.h"

#include <windows.h>

#include <algorithm>

#include "features/splitter/domain/AudioReader.h"
#include "features/splitter/domain/SplitEngine.h"
#include "features/splitter/domain/TrackWriter.h"
#include "plugin/PluginContext.h"

namespace lee::splitter {

BatchJob::~BatchJob() {
  cancel_.store(true);
  join_workers();
}

void BatchJob::join_workers() {
  for (auto& t : workers_) {
    if (t.joinable()) t.join();
  }
  workers_.clear();
}

bool BatchJob::Start(void* proj, std::vector<ItemSnapshot> snaps, AlgoMode mode, SplitParams params,
                     std::vector<Layer> layers, std::vector<std::string> suffixes) {
  // Ensure any previous run is fully torn down.
  cancel_.store(true);
  join_workers();

  proj_ = proj;
  mode_ = mode;
  params_ = params;
  layers_ = std::move(layers);
  suffixes_ = std::move(suffixes);
  snaps_ = std::move(snaps);
  if (snaps_.empty() || layers_.empty()) {
    state_ = State::Failed;
    return false;
  }

  total_ = static_cast<int>(snaps_.size());
  ok_ = 0;
  done_.store(0);
  next_index_.store(0);
  cancel_.store(false);
  wrote_ = false;

  // Phase A: read all item audio on the main thread (REAPER accessor API).
  inputs_.assign(snaps_.size(), AudioBuffer{});
  outputs_.assign(snaps_.size(), std::vector<AudioBuffer>(layers_.size()));
  item_ok_.assign(snaps_.size(), 0);
  for (size_t i = 0; i < snaps_.size(); ++i) {
    if (!ReadItemAudio(snaps_[i], inputs_[i])) {
      inputs_[i] = AudioBuffer{};
    }
  }

  // Phase B: launch DSP workers.
  unsigned hw = std::thread::hardware_concurrency();
  if (hw == 0) hw = 2;
  int nworkers = static_cast<int>(std::min<unsigned>(hw, static_cast<unsigned>(total_)));
  if (nworkers > 4) nworkers = 4;
  if (nworkers < 1) nworkers = 1;

  active_workers_.store(nworkers);
  state_ = State::Processing;

  for (int w = 0; w < nworkers; ++w) {
    workers_.emplace_back([this]() {
      for (;;) {
        if (cancel_.load()) break;
        const int i = next_index_.fetch_add(1);
        if (i >= total_) break;

        const AudioBuffer& in = inputs_[static_cast<size_t>(i)];
        bool item_success = !in.empty();
        if (item_success && mode_ == AlgoMode::MidSide && !snaps_[static_cast<size_t>(i)].is_stereo()) {
          item_success = false;
        }
        if (item_success) {
          for (size_t l = 0; l < layers_.size(); ++l) {
            AudioBuffer layer_out;
            if (!ProduceLayer(in, mode_, params_, layers_[l], layer_out)) {
              item_success = false;
              break;
            }
            outputs_[static_cast<size_t>(i)][l] = std::move(layer_out);
          }
        }
        item_ok_[static_cast<size_t>(i)] = item_success ? 1 : 0;
        done_.fetch_add(1);
      }
      active_workers_.fetch_sub(1);
    });
  }
  return true;
}

void BatchJob::Cancel() {
  if (state_ != State::Processing) return;
  cancel_.store(true);
}

void BatchJob::ForceStop() {
  cancel_.store(true);
  join_workers();
  state_ = State::Idle;
  wrote_ = false;
  active_workers_.store(0);
  done_.store(0);
}

void BatchJob::do_writes() {
  const auto& api = lee::Api();
  if (api.PreventUIRefresh) api.PreventUIRefresh(1);
  if (api.Undo_BeginBlock2) api.Undo_BeginBlock2(proj_);

  TrackWriter writer(proj_);
  ok_ = 0;
  for (size_t i = 0; i < snaps_.size(); ++i) {
    if (!item_ok_[i]) continue;
    bool all_layers = true;
    for (size_t l = 0; l < layers_.size(); ++l) {
      const char* suffix = (l < suffixes_.size()) ? suffixes_[l].c_str() : "Layer";
      if (!writer.Write(snaps_[i], outputs_[i][l], suffix)) {
        all_layers = false;
        break;
      }
    }
    if (all_layers) ++ok_;
  }

  if (api.Undo_EndBlock2) api.Undo_EndBlock2(proj_, "Lee Splitter", -1);
  if (api.PreventUIRefresh) api.PreventUIRefresh(-1);
  if (api.UpdateArrange) api.UpdateArrange();
  if (api.GetMainHwnd) {
    HWND h = api.GetMainHwnd();
    if (h) ::SetForegroundWindow(h);
  }
}

void BatchJob::Tick() {
  if (state_ != State::Processing) return;

  // Wait until all workers have finished their loops.
  if (active_workers_.load() > 0) return;
  join_workers();

  if (cancel_.load()) {
    state_ = State::Cancelled;
    return;
  }

  if (!wrote_) {
    wrote_ = true;
    do_writes();
    state_ = State::Done;
  }
}

}  // namespace lee::splitter
