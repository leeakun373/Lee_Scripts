#pragma once

#include "features/drop_station/domain/Model.h"

namespace lee::dropstation {

// Per-project persistence layer. Encodes entries as a tiny custom JSON string
// (no third-party deps) and stores via REAPER's SetProjExtState/GetProjExtState
// so the list lives inside each .RPP and is naturally isolated per project.
namespace Store {

constexpr const char kExtName[] = "Lee_DropStation";
constexpr const char kKeyEntries[] = "entries_v1";

// Loads entries for the given project into the model (overwrites current).
// Returns true on success (including the empty case when no state exists yet).
bool Load(void* reaproject, Model& model);

// Serialises the current model and writes it to the given project's ext state.
// Calls MarkProjectDirty so the user sees the dot-on-title.
bool Save(void* reaproject, const Model& model);

}  // namespace Store

}  // namespace lee::dropstation
