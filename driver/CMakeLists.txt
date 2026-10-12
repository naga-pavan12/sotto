cmake_minimum_required(VERSION 3.16)
project(SottoAudio CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Compile-time identity. SOTTO_TEAM_ID is empty for unsigned local builds and
# set from the signing identity for distributable builds.
set(SOTTO_TEAM_ID "" CACHE STRING "Signing Team ID baked into the bridge auth check")
set(SOTTO_BUNDLE_ID "io.github.sotto-audio.Sotto" CACHE STRING "Authorized app bundle id")

include(FetchContent)
FetchContent_Declare(libASPL
  GIT_REPOSITORY https://github.com/gavv/libASPL.git
  GIT_TAG v3.1.2)
FetchContent_MakeAvailable(libASPL)

add_library(SottoAudio MODULE Driver.cpp auth.cpp)
set_target_properties(SottoAudio PROPERTIES PREFIX "" SUFFIX "" OUTPUT_NAME "SottoAudio")
target_compile_definitions(SottoAudio PRIVATE
  SOTTO_TEAM_ID="${SOTTO_TEAM_ID}"
  SOTTO_BUNDLE_ID="${SOTTO_BUNDLE_ID}")
target_link_libraries(SottoAudio PRIVATE libASPL)

find_library(LIB_CoreFoundation CoreFoundation REQUIRED)
find_library(LIB_CoreAudio CoreAudio REQUIRED)
find_library(LIB_Security Security REQUIRED)
target_link_libraries(SottoAudio PRIVATE ${LIB_CoreFoundation} ${LIB_CoreAudio} ${LIB_Security})

# Assemble the .driver bundle directory.
set(BUNDLE "${CMAKE_BINARY_DIR}/SottoAudio.driver")
add_custom_command(TARGET SottoAudio POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "${BUNDLE}/Contents/MacOS"
  COMMAND ${CMAKE_COMMAND} -E make_directory "${BUNDLE}/Contents/Resources"
  COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:SottoAudio> "${BUNDLE}/Contents/MacOS/SottoAudio"
  COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist" "${BUNDLE}/Contents/Info.plist"
  COMMENT "Assembling SottoAudio.driver bundle")

# Standalone auth unit test.
add_executable(auth_test tests/auth_test.cpp auth.cpp)
target_compile_definitions(auth_test PRIVATE
  SOTTO_TEAM_ID="${SOTTO_TEAM_ID}" SOTTO_BUNDLE_ID="${SOTTO_BUNDLE_ID}")
target_link_libraries(auth_test PRIVATE ${LIB_CoreFoundation} ${LIB_Security})
enable_testing()
add_test(NAME auth COMMAND auth_test)
