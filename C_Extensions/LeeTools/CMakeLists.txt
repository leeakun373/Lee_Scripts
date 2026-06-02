cmake_minimum_required(VERSION 3.16)
project(reaper_lee_tools LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(REAIMGUI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/reaimgui")

add_library(reaper_lee_tools SHARED
  # plugin shell
  src/plugin/main.cpp
  src/plugin/PluginContext.cpp
  src/plugin/CommandRegistry.cpp
  src/plugin/AppTimer.cpp
  src/plugin/FeatureRegistry.cpp

  # shared (cross-feature, no business logic)
  src/shared/reaper/ReaImGuiApi.cpp
  src/shared/ui/LeeUiTheme.cpp

  # platform (OS capabilities)
  src/platform/win/OsFileDrag.cpp

  # features/drop_station
  src/features/drop_station/Register.cpp
  src/features/drop_station/domain/Model.cpp
  src/features/drop_station/domain/Store.cpp
  src/features/drop_station/domain/SliceReplicator.cpp
  src/features/drop_station/ui/Window.cpp

  # features/item_hub
  src/features/item_hub/Register.cpp
  src/features/item_hub/domain/ParamSpec.cpp
  src/features/item_hub/domain/Session.cpp
  src/features/item_hub/ui/HubWindow.cpp

  # shared/dsp
  src/shared/dsp/Fft.cpp
  src/shared/dsp/Stft.cpp
  src/shared/dsp/Median.cpp
  src/shared/dsp/Envelope.cpp

  # features/splitter
  src/features/splitter/Register.cpp
  src/features/splitter/domain/Prefs.cpp
  src/features/splitter/domain/ItemSnapshot.cpp
  src/features/splitter/domain/AudioReader.cpp
  src/features/splitter/domain/Selection.cpp
  src/features/splitter/domain/SplitEngine.cpp
  src/features/splitter/domain/WavWriter.cpp
  src/features/splitter/domain/TrackWriter.cpp
  src/features/splitter/domain/BatchJob.cpp
  src/features/splitter/domain/PreviewPlayer.cpp
  src/features/splitter/domain/algorithms/TransientSustain.cpp
  src/features/splitter/domain/algorithms/MidSide.cpp
  src/features/splitter/domain/algorithms/Hpss.cpp
  src/features/splitter/domain/algorithms/TonalNoise.cpp
  src/features/splitter/domain/algorithms/FgAmbient.cpp
  src/features/splitter/ui/SplitterWindow.cpp
)

target_include_directories(reaper_lee_tools SYSTEM PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${REAIMGUI_DIR}"
)

target_compile_definitions(reaper_lee_tools PRIVATE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
  UNICODE
  _UNICODE
)

if(MSVC)
  target_compile_options(reaper_lee_tools PRIVATE
    /W4 /permissive- /EHsc /utf-8
    "/external:I${CMAKE_CURRENT_SOURCE_DIR}/include"
    "/external:I${REAIMGUI_DIR}"
    /external:W0
  )
endif()

set_target_properties(reaper_lee_tools PROPERTIES
  PREFIX ""
  OUTPUT_NAME "reaper_lee_tools"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
  ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)

target_link_libraries(reaper_lee_tools PRIVATE
  ole32
  shell32
  user32
  uuid
)
