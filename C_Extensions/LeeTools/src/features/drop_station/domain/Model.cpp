#include "features/drop_station/domain/Model.h"

#include <algorithm>
#include <cmath>
#include <cwctype>
#include <set>

namespace lee::dropstation {
namespace {

std::wstring to_lower(std::wstring s) {
  std::transform(s.begin(), s.end(), s.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  return s;
}

bool same_path(const std::wstring& a, const std::wstring& b) {
  // Windows paths are case-insensitive. Normalise both before comparing.
  return to_lower(a) == to_lower(b);
}

}  // namespace

namespace {

// Slice equality used as a dedup fallback when GUID is unavailable. Two
// entries are "the same slice" if they point at the same source file (case
// insensitive) AND start at the same source offset AND span the same length.
// Tolerance avoids spurious mismatches from double rounding (1us is well below
// any audible resolution).
bool same_slice(const DropEntry& a, const DropEntry& b) {
  constexpr double kEps = 1e-6;
  if (!same_path(a.path, b.path)) return false;
  if (std::abs(a.take_offset - b.take_offset) > kEps) return false;
  if (std::abs(a.length - b.length) > kEps) return false;
  return true;
}

}  // namespace

bool Model::add(const DropEntry& entry) {
  if (entry.path.empty()) {
    return false;
  }
  // Preferred dedup: REAPER item GUID. If the caller managed to capture one
  // we trust it absolutely -- adding the *same* item twice is a no-op, while
  // three different items on the same source remain three entries.
  if (!entry.item_guid.empty()) {
    for (const auto& existing : entries_) {
      if (existing.item_guid == entry.item_guid) {
        return false;
      }
    }
  } else {
    // Fallback for entries loaded from legacy stores (or hypothetically from
    // REAPER builds missing guidToString): dedup by source + offset + length.
    for (const auto& existing : entries_) {
      if (existing.item_guid.empty() && same_slice(existing, entry)) {
        return false;
      }
    }
  }
  entries_.push_back(entry);
  bump();
  return true;
}

void Model::remove_at(size_t index) {
  if (index >= entries_.size()) {
    return;
  }
  entries_.erase(entries_.begin() + static_cast<std::ptrdiff_t>(index));
  bump();
}

void Model::remove_indices(const std::vector<size_t>& indices) {
  if (indices.empty()) {
    return;
  }
  std::set<size_t, std::greater<size_t>> sorted_desc(indices.begin(), indices.end());
  for (size_t idx : sorted_desc) {
    if (idx < entries_.size()) {
      entries_.erase(entries_.begin() + static_cast<std::ptrdiff_t>(idx));
    }
  }
  bump();
}

void Model::sort_by_label() {
  std::sort(entries_.begin(), entries_.end(), [](const DropEntry& a, const DropEntry& b) {
    return to_lower(a.label) < to_lower(b.label);
  });
  bump();
}

}  // namespace lee::dropstation
