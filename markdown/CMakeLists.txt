cmake_minimum_required(VERSION 3.20)
project(DankMarkdown)

find_package(Qt6 REQUIRED COMPONENTS Core Qml Quick)

set(CMAKE_AUTOMOC ON)

# Output the .so directly into the markdown/ source folder
# so QML can find it via a relative import
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR})

qt_add_library(DankMarkdown SHARED
    plugin.cpp
    MarkdownParser.cpp
    vendor/md4c.c
)

target_include_directories(DankMarkdown PRIVATE vendor)

target_link_libraries(DankMarkdown PRIVATE
    Qt6::Core
    Qt6::Qml
    Qt6::Quick
)
