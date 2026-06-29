#include "domain/Catalog.h"



#include <algorithm>
#include <cctype>
#include <filesystem>



#include "plugin/PluginContext.h"



namespace lee::radial_menu {

namespace {



Catalog g_catalog;



std::string Lower(std::string s) {

  for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));

  return s;

}



bool FuzzyMatch(const std::string& hay, const std::string& query) {

  if (query.empty()) return true;

  size_t start = 0;

  for (char qc : query) {

    if (std::isspace(static_cast<unsigned char>(qc))) continue;

    const char lc = static_cast<char>(std::tolower(static_cast<unsigned char>(qc)));

    size_t pos = hay.find(lc, start);

    if (pos == std::string::npos) return false;

    start = pos + 1;

  }

  return true;

}



}  // namespace



Catalog& GetCatalog() { return g_catalog; }



void Catalog::RequestBuild() {

  if (built_ || building_) return;

  building_ = true;

  build_phase_ = 0;

  action_index_ = 0;

  fx_index_ = 0;

  actions_.clear();

  fx_.clear();

  actions_by_id_.clear();

}



void Catalog::BuildActionsBatch(int max_items) {

  const auto& api = lee::Api();

  if (!api.CF_EnumerateActions) {

    build_phase_ = 1;

    return;

  }

  char namebuf[512] = {};

  int added = 0;

  for (;; ++action_index_) {

    if (added >= max_items) return;

    const int cmd = api.CF_EnumerateActions(nullptr, action_index_, namebuf);

    if (cmd <= 0) {

      std::sort(actions_.begin(), actions_.end(),

                [](const ActionEntry& a, const ActionEntry& b) { return a.name < b.name; });

      for (const auto& a : actions_) actions_by_id_[a.command_id] = a.name;

      build_phase_ = 1;

      action_index_ = 0;

      return;

    }

    actions_.push_back({cmd, namebuf});

    ++added;

  }

}



void Catalog::BuildFxBatch(int max_items) {

  const auto& api = lee::Api();

  if (!api.EnumInstalledFX) {

    build_phase_ = 2;

    return;

  }

  char name[512] = {};

  char ident[256] = {};

  int added = 0;

  for (;; ++fx_index_) {

    if (added >= max_items) return;

    if (!api.EnumInstalledFX(fx_index_, name, static_cast<int>(sizeof(name)), ident)) {

      std::sort(fx_.begin(), fx_.end(),

                [](const FxEntry& a, const FxEntry& b) { return Lower(a.name) < Lower(b.name); });

      build_phase_ = 2;

      fx_index_ = 0;

      return;

    }

    FxEntry e;

    e.original_name = name;

    e.name = name;

    e.type = "Other";

    if (e.name.rfind("VST3:", 0) == 0) {

      e.type = "VST3";

      e.name = e.name.substr(6);

    } else if (e.name.rfind("VST:", 0) == 0) {

      e.type = "VST";

      e.name = e.name.substr(5);

    } else if (e.name.rfind("JS:", 0) == 0) {

      e.type = "JS";

      e.name = e.name.substr(4);

    } else if (e.name.rfind("AU:", 0) == 0) {

      e.type = "AU";

      e.name = e.name.substr(4);

    } else if (e.name.rfind("CLAP:", 0) == 0) {

      e.type = "CLAP";

      e.name = e.name.substr(6);

    } else if (e.name.rfind("LV2:", 0) == 0) {

      e.type = "LV2";

      e.name = e.name.substr(5);

    }

    fx_.push_back(e);

    ++added;

  }

}



void Catalog::TickBuild(int max_items_per_frame) {

  if (built_ || !building_) return;

  if (build_phase_ == 0) {

    BuildActionsBatch(max_items_per_frame);

  } else if (build_phase_ == 1) {

    BuildFxBatch(max_items_per_frame);

  } else if (build_phase_ == 2) {

    BuildResourceFilesBatch();

  }

}

void Catalog::BuildResourceFilesBatch() {
  const auto& api = lee::Api();
  if (!api.GetResourcePath) {
    built_ = true;
    building_ = false;
    return;
  }
  char res[512] = {};
  api.GetResourcePath(res, sizeof(res));
  namespace fs = std::filesystem;
  const fs::path root(res);
  const auto scan_ext = [&](const fs::path& dir, const char* ext, const char* type) {
    if (!fs::exists(dir)) return;
    try {
      for (const auto& ent : fs::recursive_directory_iterator(dir)) {
        if (!ent.is_regular_file()) continue;
        const auto p = ent.path();
        if (p.extension() != ext) continue;
        FxEntry e;
        e.original_name = p.string();
        e.name = p.stem().string();
        e.type = type;
        fx_.push_back(std::move(e));
      }
    } catch (...) {
    }
  };
  scan_ext(root / "FXChains", ".RfxChain", "Chain");
  scan_ext(root / "TrackTemplates", ".RTrackTemplate", "Template");
  std::sort(fx_.begin(), fx_.end(),
            [](const FxEntry& a, const FxEntry& b) { return Lower(a.name) < Lower(b.name); });
  built_ = true;
  building_ = false;
}

std::string Catalog::GetActionNameById(int command_id) const {
  const auto it = actions_by_id_.find(command_id);
  if (it != actions_by_id_.end()) return it->second;
  return "Unknown Action";
}



std::vector<ActionEntry> Catalog::FilterActions(const std::string& query) const {

  std::vector<ActionEntry> out;

  const std::string q = Lower(query);

  for (const auto& a : actions_) {

    const std::string hay = Lower(a.name + " " + std::to_string(a.command_id));

    if (FuzzyMatch(hay, q)) out.push_back(a);

  }

  return out;

}



std::vector<FxEntry> Catalog::FilterFx(const std::string& query, const std::string& type_filter) const {

  std::vector<FxEntry> out;

  const std::string q = Lower(query);

  for (const auto& f : fx_) {

    if (type_filter != "All" && !type_filter.empty() && f.type != type_filter) continue;

    const std::string hay = Lower(f.name + " " + f.original_name);

    if (FuzzyMatch(hay, q)) out.push_back(f);

  }

  return out;

}



}  // namespace lee::radial_menu

