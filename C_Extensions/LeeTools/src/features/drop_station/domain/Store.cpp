#include "features/drop_station/domain/Store.h"

#include <windows.h>

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "plugin/PluginContext.h"

namespace lee::dropstation::Store {
namespace {

// ---------------------------------------------------------------------------
// UTF-16 <-> UTF-8 helpers
// ---------------------------------------------------------------------------

std::string to_utf8(const std::wstring& w) {
  if (w.empty()) {
    return {};
  }
  const int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()),
                                    nullptr, 0, nullptr, nullptr);
  if (n <= 0) {
    return {};
  }
  std::string out(static_cast<size_t>(n), '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()),
                      out.data(), n, nullptr, nullptr);
  return out;
}

std::wstring from_utf8(const char* p, size_t len) {
  if (!p || len == 0) {
    return {};
  }
  return lee::Utf8ToWide(p, len);
}

// ---------------------------------------------------------------------------
// Minimal JSON encoder/decoder for {"entries":[{"path":"...","label":"..."}]}.
// Hand-rolled to avoid pulling a JSON library into the DLL.
// ---------------------------------------------------------------------------

void append_json_string(std::string& out, const std::string& s) {
  out.push_back('"');
  for (char raw : s) {
    unsigned char c = static_cast<unsigned char>(raw);
    switch (c) {
      case '"':  out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\b': out += "\\b";  break;
      case '\f': out += "\\f";  break;
      case '\n': out += "\\n";  break;
      case '\r': out += "\\r";  break;
      case '\t': out += "\\t";  break;
      default:
        if (c < 0x20) {
          char buf[8];
          wsprintfA(buf, "\\u%04x", c);
          out += buf;
        } else {
          out.push_back(static_cast<char>(c));
        }
        break;
    }
  }
  out.push_back('"');
}

// Numeric format helper. We use plain "%.9g" -- enough precision for sample
// accuracy at 384 kHz over a few hours, while staying compact in the .RPP.
void append_json_number(std::string& out, double v) {
  char buf[40];
  std::snprintf(buf, sizeof(buf), "%.9g", v);
  out += buf;
}

std::string serialize(const Model& model) {
  // Schema v2: each entry is
  //   {"path":"...","label":"...","guid":"{..}",
  //    "off":<takeOffsetSec>,"len":<itemLenSec>,
  //    "fi":<fadeInSec>,"fo":<fadeOutSec>,
  //    "iv":<itemVol>,"tv":<takeVol>,"pr":<playrate>}
  // The wrapper carries "v":2 so a future reader can branch cleanly. Schema
  // v1 (no version, just path+label) is still recognised on load.
  std::string out;
  out += "{\"v\":2,\"entries\":[";
  const auto& entries = model.entries();
  for (size_t i = 0; i < entries.size(); ++i) {
    if (i != 0) {
      out.push_back(',');
    }
    out += "{\"path\":";
    append_json_string(out, to_utf8(entries[i].path));
    out += ",\"label\":";
    append_json_string(out, to_utf8(entries[i].label));
    if (!entries[i].item_guid.empty()) {
      out += ",\"guid\":";
      append_json_string(out, entries[i].item_guid);
    }
    out += ",\"off\":"; append_json_number(out, entries[i].take_offset);
    out += ",\"len\":"; append_json_number(out, entries[i].length);
    out += ",\"fi\":";  append_json_number(out, entries[i].fade_in);
    out += ",\"fo\":";  append_json_number(out, entries[i].fade_out);
    out += ",\"iv\":";  append_json_number(out, entries[i].item_volume);
    out += ",\"tv\":";  append_json_number(out, entries[i].take_volume);
    out += ",\"pr\":";  append_json_number(out, entries[i].playrate);
    out.push_back('}');
  }
  out += "]}";
  return out;
}

class Parser {
 public:
  explicit Parser(const std::string& src) : src_(src) {}

  bool parse(std::vector<DropEntry>& out) {
    skip_ws();
    if (!consume('{')) return false;
    skip_ws();
    if (peek() == '}') { i_++; return true; }
    while (true) {
      skip_ws();
      std::string key;
      if (!parse_string(key)) return false;
      skip_ws();
      if (!consume(':')) return false;
      skip_ws();
      if (key == "entries") {
        if (!parse_entries(out)) return false;
      } else {
        if (!skip_value()) return false;
      }
      skip_ws();
      if (peek() == ',') { i_++; continue; }
      if (peek() == '}') { i_++; return true; }
      return false;
    }
  }

 private:
  const std::string& src_;
  size_t i_ = 0;

  char peek() const { return i_ < src_.size() ? src_[i_] : '\0'; }

  void skip_ws() {
    while (i_ < src_.size()) {
      char c = src_[i_];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') { i_++; continue; }
      break;
    }
  }

  bool consume(char c) {
    if (peek() != c) return false;
    i_++;
    return true;
  }

  bool parse_string(std::string& out) {
    if (!consume('"')) return false;
    out.clear();
    while (i_ < src_.size()) {
      char c = src_[i_++];
      if (c == '"') return true;
      if (c == '\\') {
        if (i_ >= src_.size()) return false;
        char esc = src_[i_++];
        switch (esc) {
          case '"':  out.push_back('"'); break;
          case '\\': out.push_back('\\'); break;
          case '/':  out.push_back('/'); break;
          case 'b':  out.push_back('\b'); break;
          case 'f':  out.push_back('\f'); break;
          case 'n':  out.push_back('\n'); break;
          case 'r':  out.push_back('\r'); break;
          case 't':  out.push_back('\t'); break;
          case 'u': {
            if (i_ + 4 > src_.size()) return false;
            unsigned int code = 0;
            for (int k = 0; k < 4; ++k) {
              char h = src_[i_++];
              code <<= 4;
              if (h >= '0' && h <= '9') code |= static_cast<unsigned int>(h - '0');
              else if (h >= 'a' && h <= 'f') code |= static_cast<unsigned int>(h - 'a' + 10);
              else if (h >= 'A' && h <= 'F') code |= static_cast<unsigned int>(h - 'A' + 10);
              else return false;
            }
            // Encode codepoint into UTF-8 (BMP-only; surrogate pairs not needed
            // for typical file paths, but we still emit them as raw bytes if
            // ever encountered).
            if (code < 0x80) {
              out.push_back(static_cast<char>(code));
            } else if (code < 0x800) {
              out.push_back(static_cast<char>(0xC0 | (code >> 6)));
              out.push_back(static_cast<char>(0x80 | (code & 0x3F)));
            } else {
              out.push_back(static_cast<char>(0xE0 | (code >> 12)));
              out.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3F)));
              out.push_back(static_cast<char>(0x80 | (code & 0x3F)));
            }
            break;
          }
          default: return false;
        }
      } else {
        out.push_back(c);
      }
    }
    return false;
  }

  bool parse_entries(std::vector<DropEntry>& out) {
    if (!consume('[')) return false;
    skip_ws();
    if (peek() == ']') { i_++; return true; }
    while (true) {
      skip_ws();
      DropEntry entry;
      if (!parse_entry(entry)) return false;
      out.push_back(std::move(entry));
      skip_ws();
      if (peek() == ',') { i_++; continue; }
      if (peek() == ']') { i_++; return true; }
      return false;
    }
  }

  bool parse_entry(DropEntry& entry) {
    if (!consume('{')) return false;
    skip_ws();
    if (peek() == '}') { i_++; return true; }
    while (true) {
      skip_ws();
      std::string key;
      if (!parse_string(key)) return false;
      skip_ws();
      if (!consume(':')) return false;
      skip_ws();

      // We accept either a quoted string or a raw number. Booleans / nulls
      // we silently skip via skip_value().
      if (peek() == '"') {
        std::string val;
        if (!parse_string(val)) return false;
        if      (key == "path")  entry.path     = from_utf8(val.data(), val.size());
        else if (key == "label") entry.label    = from_utf8(val.data(), val.size());
        else if (key == "guid")  entry.item_guid = val;
      } else {
        // Capture the raw numeric token so we can strtod() it without
        // re-implementing a number parser.
        size_t start = i_;
        if (!skip_value()) return false;
        if (i_ > start) {
          std::string numtok(src_.data() + start, i_ - start);
          char* endp = nullptr;
          double v = std::strtod(numtok.c_str(), &endp);
          if (endp != numtok.c_str()) {
            if      (key == "off") entry.take_offset = v;
            else if (key == "len") entry.length      = v;
            else if (key == "fi")  entry.fade_in     = v;
            else if (key == "fo")  entry.fade_out    = v;
            else if (key == "iv")  entry.item_volume = v;
            else if (key == "tv")  entry.take_volume = v;
            else if (key == "pr")  entry.playrate    = v;
          }
        }
      }

      skip_ws();
      if (peek() == ',') { i_++; continue; }
      if (peek() == '}') { i_++; return true; }
      return false;
    }
  }

  bool skip_value() {
    // Skip strings/numbers/null/true/false/objects/arrays we don't care about.
    char c = peek();
    if (c == '"') {
      std::string tmp;
      return parse_string(tmp);
    }
    if (c == '{') {
      int depth = 0;
      while (i_ < src_.size()) {
        char ch = src_[i_++];
        if (ch == '{') depth++;
        else if (ch == '}') { depth--; if (depth == 0) return true; }
        else if (ch == '"') { --i_; std::string tmp; if (!parse_string(tmp)) return false; }
      }
      return false;
    }
    if (c == '[') {
      int depth = 0;
      while (i_ < src_.size()) {
        char ch = src_[i_++];
        if (ch == '[') depth++;
        else if (ch == ']') { depth--; if (depth == 0) return true; }
        else if (ch == '"') { --i_; std::string tmp; if (!parse_string(tmp)) return false; }
      }
      return false;
    }
    while (i_ < src_.size()) {
      char ch = src_[i_];
      if (ch == ',' || ch == '}' || ch == ']' || ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t') break;
      i_++;
    }
    return true;
  }
};

bool deserialize(const std::string& s, std::vector<DropEntry>& out) {
  out.clear();
  if (s.empty()) {
    return true;
  }
  Parser parser(s);
  return parser.parse(out);
}

}  // namespace

bool Load(void* reaproject, Model& model) {
  const auto& api = lee::Api();
  if (!api.GetProjExtState) {
    return false;
  }
  // First call with empty buffer to probe size. REAPER returns "needed size";
  // we pick a sane upper bound and grow if necessary.
  std::vector<char> buf;
  buf.resize(64 * 1024);
  int rc = api.GetProjExtState(reaproject, kExtName, kKeyEntries,
                               buf.data(), static_cast<int>(buf.size()));
  if (rc <= 0) {
    // No state yet, or read failure -> treat as empty list (clear current).
    model.reset({});
    return true;
  }
  if (static_cast<size_t>(rc) >= buf.size()) {
    buf.resize(static_cast<size_t>(rc) + 1);
    rc = api.GetProjExtState(reaproject, kExtName, kKeyEntries,
                             buf.data(), static_cast<int>(buf.size()));
    if (rc <= 0) {
      model.reset({});
      return true;
    }
  }
  std::string payload(buf.data());
  std::vector<DropEntry> entries;
  deserialize(payload, entries);
  model.reset(std::move(entries));
  return true;
}

namespace {

// SEH cannot live in a function that requires object unwinding, so we hop one
// stack frame into this POD-only helper. Returns true on normal completion,
// false if a hardware exception was caught.
bool seh_write_extstate(int (*setter)(void*, const char*, const char*, const char*),
                        void* proj, const char* ext, const char* key,
                        const char* value,
                        void (*markDirty)(void*)) {
  __try {
    setter(proj, ext, key, value);
    if (markDirty) markDirty(proj);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

}  // namespace

bool Save(void* reaproject, const Model& model) {
  const auto& api = lee::Api();
  if (!api.SetProjExtState) {
    OutputDebugStringA("[Lee] Store::Save: SetProjExtState unavailable\n");
    return false;
  }
  std::string payload = serialize(model);
  char info[96];
  std::snprintf(info, sizeof(info),
                "[Lee] Store::Save: %zu entries, %zu bytes\n",
                model.entries().size(), payload.size());
  OutputDebugStringA(info);

  if (!seh_write_extstate(api.SetProjExtState, reaproject,
                          kExtName, kKeyEntries, payload.c_str(),
                          api.MarkProjectDirty)) {
    OutputDebugStringA("[Lee] Store::Save: SEH caught during SetProjExtState\n");
    return false;
  }
  return true;
}

}  // namespace lee::dropstation::Store
