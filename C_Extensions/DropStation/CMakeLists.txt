cmake_minimum_required(VERSION 3.16)
project(reaper_dropstation LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(reaper_dropstation SHARED
  src/main.cpp
  src/DragDrop.cpp
)

target_include_directories(reaper_dropstation SYSTEM PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_compile_definitions(reaper_dropstation PRIVATE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
  UNICODE
  _UNICODE
)

if(MSVC)
  target_compile_options(reaper_dropstation PRIVATE
    /W4 /permissive- /EHsc
    "/external:I${CMAKE_CURRENT_SOURCE_DIR}/include"
    /external:W0
  )
endif()

set_target_properties(reaper_dropstation PROPERTIES
  PREFIX ""
  OUTPUT_NAME "reaper_dropstation"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
  ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)

target_link_libraries(reaper_dropstation PRIVATE
  ole32
  shell32
  user32
  uuid
)
