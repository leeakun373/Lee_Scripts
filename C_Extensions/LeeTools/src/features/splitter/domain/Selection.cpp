#include "features/splitter/domain/Selection.h"

#include "plugin/PluginContext.h"

namespace lee::splitter {

SelectionInfo CollectSelection(void* proj) {
  SelectionInfo info;
  const auto& api = lee::Api();
  if (!api.CountSelectedMediaItems || !api.GetSelectedMediaItem) return info;

  info.total_selected = api.CountSelectedMediaItems(proj);
  for (int i = 0; i < info.total_selected; ++i) {
    void* item = api.GetSelectedMediaItem(proj, i);
    if (!item) continue;
    ItemSnapshot snap;
    if (CaptureItemSnapshot(item, snap)) {
      info.items.push_back(std::move(snap));
    }
  }
  info.valid_audio = static_cast<int>(info.items.size());
  info.exactly_one = (info.valid_audio == 1);
  return info;
}

}  // namespace lee::splitter
