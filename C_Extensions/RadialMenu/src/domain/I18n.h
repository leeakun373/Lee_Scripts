#pragma once

#include <string>

namespace lee::radial_menu {

enum class Lang { Zh, En };

class I18n {
 public:
  static I18n& Instance();
  void LoadFromExtState();
  void SetLang(Lang l);
  Lang lang() const { return lang_; }
  const char* Tr(const char* key) const;

 private:
  I18n() = default;
  Lang lang_ = Lang::Zh;
};

}  // namespace lee::radial_menu
