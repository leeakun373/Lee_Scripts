#pragma once



#include <string>
#include <unordered_map>
#include <vector>



namespace lee::radial_menu {



struct ActionEntry {

  int command_id = 0;

  std::string name;

};



struct FxEntry {

  std::string name;

  std::string original_name;

  std::string type;

};



class Catalog {

 public:

  void RequestBuild();

  void TickBuild(int max_items_per_frame = 250);

  bool IsBuilt() const { return built_; }

  bool IsBuilding() const { return building_; }



  const std::vector<ActionEntry>& actions() const { return actions_; }

  const std::vector<FxEntry>& fx_list() const { return fx_; }

  std::vector<ActionEntry> FilterActions(const std::string& query) const;

  std::vector<FxEntry> FilterFx(const std::string& query, const std::string& type_filter) const;

  std::string GetActionNameById(int command_id) const;

 private:

  void BuildActionsBatch(int max_items);

  void BuildFxBatch(int max_items);

  void BuildResourceFilesBatch();

  bool built_ = false;

  bool building_ = false;

  int build_phase_ = 0;  // 0=actions, 1=fx, 2=resource files, 3=done

  int action_index_ = 0;

  int fx_index_ = 0;

  std::vector<ActionEntry> actions_;

  std::vector<FxEntry> fx_;
  std::unordered_map<int, std::string> actions_by_id_;

};



Catalog& GetCatalog();



}  // namespace lee::radial_menu

