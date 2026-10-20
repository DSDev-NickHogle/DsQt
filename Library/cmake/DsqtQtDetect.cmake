# DsqtQtDetect.cmake
# -----------------------------------------------------------------------------
# Centralized Qt6 discovery helper for DsQt and downstream applications.
#
# Searches for Qt6 in the following priority order:
#   1. Explicit cache variable `Qt6_ROOT` or `-DQT_VERSION_OR_PATH=<ver|path>`
#   2. Standard environment variable `$ENV{QTDIR}`
#   3. Sibling directories (e.g. `downstream/Qt/*/msvc2022_64` or `../Qt/*/msvc2022_64`)
#   4. Standard installation directory (`C:/Qt/*/msvc2022_64`)
#
# Upon detection, sets `Qt6_ROOT` in the cache without polluting or clobbering
# `CMAKE_PREFIX_PATH`.
# -----------------------------------------------------------------------------

function(dsqt_detect_qt)
    # If Qt6 has already been found or Qt6_ROOT is explicitly configured, nothing to do
    if(Qt6_FOUND OR Qt6_ROOT)
        return()
    endif()

    if(NOT WIN32)
        return()
    endif()

    # Check if caller passed a version or path override via -DQT_VERSION_OR_PATH=...
    set(_req_ver "*")
    if(DEFINED QT_VERSION_OR_PATH AND NOT QT_VERSION_OR_PATH STREQUAL "")
        # If it looks like a direct path (contains slashes)
        if(QT_VERSION_OR_PATH MATCHES "[/\\\\]")
            if(EXISTS "${QT_VERSION_OR_PATH}/lib/cmake/Qt6/Qt6Config.cmake" OR
               EXISTS "${QT_VERSION_OR_PATH}/bin/qmake.exe")
                set(Qt6_ROOT "${QT_VERSION_OR_PATH}" CACHE PATH "Qt6 root directory" FORCE)
                message(STATUS "DsQt: Using explicit Qt6_ROOT: ${Qt6_ROOT}")
                return()
            endif()
        else()
            # It's a specific version string, e.g. "6.10.2"
            set(_req_ver "${QT_VERSION_OR_PATH}")
        endif()
    endif()

    # Search candidates in prioritized order
    set(_candidate_patterns "")

    # 1. Environment variable QTDIR
    if(DEFINED ENV{QTDIR} AND NOT "$ENV{QTDIR}" STREQUAL "")
        list(APPEND _candidate_patterns "$ENV{QTDIR}")
    endif()

    # 2. Sibling directory relative to project source root and install location
    list(APPEND _candidate_patterns
        "${CMAKE_CURRENT_LIST_DIR}/../../Qt/${_req_ver}/msvc2022_64"
        "${CMAKE_CURRENT_LIST_DIR}/../../../Qt/${_req_ver}/msvc2022_64"
        "${CMAKE_SOURCE_DIR}/../Qt/${_req_ver}/msvc2022_64"
        "${CMAKE_SOURCE_DIR}/../../Qt/${_req_ver}/msvc2022_64"
    )

    # 3. Standard default install directory
    list(APPEND _candidate_patterns
        "C:/Qt/${_req_ver}/msvc2022_64"
    )

    foreach(_pattern IN LISTS _candidate_patterns)
        file(GLOB _matches LIST_DIRECTORIES true "${_pattern}")
        if(_matches)
            # Pick highest matching version
            list(SORT _matches COMPARE NATURAL ORDER DESCENDING)
            list(GET _matches 0 _selected_qt)
            if(EXISTS "${_selected_qt}/lib/cmake/Qt6/Qt6Config.cmake" OR
               EXISTS "${_selected_qt}/bin/qmake.exe")
                set(Qt6_ROOT "${_selected_qt}" CACHE PATH "Qt6 root directory")
                message(STATUS "DsQt: Auto-discovered Qt6_ROOT at ${Qt6_ROOT}")
                return()
            endif()
        endif()
    endforeach()
endfunction()
