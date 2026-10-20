# DsqtGitVersion.cmake
# -----------------------------------------------------------------------------
# General-purpose Git describe version resolution for DsQt and downstream apps.
#
# Provides:
#   dsqt_get_git_version(
#       <repo_dir>
#       <out_git_version>       # e.g. "1.0.10+7 (main@0c233a8-dirty)"
#       <out_version>           # e.g. "1.0.10.7" (4-part tuple for CMake project())
#       [TAG_MATCH <pattern>]   # e.g. "library/*" or "v*" (default: all tags)
#       [DEFAULT_VERSION <ver>] # fallback if untagged or not git (default: "0.1.0")
#   )
# Note:
#   Automatically sets `<out_version>_COMMA` in the caller's scope
#   (e.g. `DS_APP_VERSION_COMMA = "1,0,10,7"`) for Windows PE resource files.
# -----------------------------------------------------------------------------

function(dsqt_get_git_version repo_dir out_git_version out_version)
    # Parse keyword options
    cmake_parse_arguments(ARG "" "TAG_MATCH;DEFAULT_VERSION" "" ${ARGN})

    set(_default_ver "0.1.0")
    if(ARG_DEFAULT_VERSION)
        set(_default_ver "${ARG_DEFAULT_VERSION}")
    endif()

    find_package(Git QUIET)
    set(_git_root "")

    if(GIT_FOUND)
        # Discover repository root containing .git
        execute_process(
            COMMAND ${GIT_EXECUTABLE} -C "${repo_dir}" rev-parse --show-toplevel
            RESULT_VARIABLE _toplevel_res
            OUTPUT_VARIABLE _toplevel_out
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        if(_toplevel_res EQUAL 0 AND _toplevel_out)
            set(_git_root "${_toplevel_out}")
        endif()
    endif()

    # If not a git repository, apply default versioning
    if(NOT _git_root)
        string(REPLACE "." ";" _parts "${_default_ver}")
        list(LENGTH _parts _len)
        while(_len LESS 4)
            list(APPEND _parts "0")
            math(EXPR _len "${_len} + 1")
        endwhile()
        list(SUBLIST _parts 0 4 _parts_4)
        list(JOIN _parts_4 "." _fallback_dot)
        list(JOIN _parts_4 "," _fallback_comma)

        set(${out_git_version} "${_fallback_dot}" PARENT_SCOPE)
        set(${out_version} "${_fallback_dot}" PARENT_SCOPE)
        set(${out_version}_COMMA "${_fallback_comma}" PARENT_SCOPE)
        return()
    endif()

    # Query git describe
    set(_describe_cmd ${GIT_EXECUTABLE} -C "${_git_root}" describe --tags --always)
    if(ARG_TAG_MATCH)
        list(APPEND _describe_cmd --match "${ARG_TAG_MATCH}")
    endif()

    execute_process(
        COMMAND ${_describe_cmd}
        RESULT_VARIABLE _desc_res
        OUTPUT_VARIABLE _raw_desc
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )

    # Query short commit hash
    execute_process(
        COMMAND ${GIT_EXECUTABLE} -C "${_git_root}" rev-parse --short HEAD
        OUTPUT_VARIABLE _short_sha
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )

    # Query branch name
    execute_process(
        COMMAND ${GIT_EXECUTABLE} -C "${_git_root}" rev-parse --abbrev-ref HEAD
        OUTPUT_VARIABLE _branch
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_branch STREQUAL "HEAD" OR _branch STREQUAL "")
        execute_process(
            COMMAND ${GIT_EXECUTABLE} -C "${_git_root}" branch --show-current
            OUTPUT_VARIABLE _branch
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
    endif()

    # Check for uncommitted changes in tracked files
    set(_dirty_suffix "")
    execute_process(
        COMMAND ${GIT_EXECUTABLE} -C "${_git_root}" diff-index --quiet HEAD --
        RESULT_VARIABLE _dirty_res
        ERROR_QUIET
    )
    if(NOT _dirty_res EQUAL 0)
        execute_process(
            COMMAND ${GIT_EXECUTABLE} -C "${_git_root}" stash create
            OUTPUT_VARIABLE _stash_sha
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        if(_stash_sha)
            string(SUBSTRING "${_stash_sha}" 0 7 _stash_short)
            set(_dirty_suffix "-dirty-${_stash_short}")
        else()
            set(_dirty_suffix "-dirty")
        endif()
    endif()

    # Strip prefixes like library/, library/v, or v
    string(REGEX REPLACE "^(library/v?|v)" "" _clean_desc "${_raw_desc}")

    set(_ahead "0")
    set(_sha "${_short_sha}")

    if(_clean_desc MATCHES "^([0-9]+(\\.[0-9]+)+)-([0-9]+)-g([0-9a-fA-F]+)$")
        set(_tag "${CMAKE_MATCH_1}")
        set(_ahead "${CMAKE_MATCH_3}")
        set(_sha "${CMAKE_MATCH_4}")
        if(_branch AND NOT _branch STREQUAL "HEAD")
            set(_full "${_tag}+${_ahead} (${_branch}@${_sha}${_dirty_suffix})")
        else()
            set(_full "${_tag}+${_ahead} (${_sha}${_dirty_suffix})")
        endif()
    elseif(_clean_desc MATCHES "^([0-9]+(\\.[0-9]+)+)$")
        set(_tag "${CMAKE_MATCH_1}")
        if(_dirty_suffix)
            if(_branch AND NOT _branch STREQUAL "HEAD")
                set(_full "${_tag} (${_branch}@${_short_sha}${_dirty_suffix})")
            else()
                set(_full "${_tag} (${_short_sha}${_dirty_suffix})")
            endif()
        else()
            set(_full "${_tag} (${_short_sha})")
        endif()
    else()
        set(_tag "${_default_ver}")
        if(_branch AND NOT _branch STREQUAL "HEAD")
            set(_full "${_default_ver} (${_branch}@${_short_sha}${_dirty_suffix})")
        else()
            set(_full "${_default_ver} (${_short_sha}${_dirty_suffix})")
        endif()
    endif()

    # Split tag numbers into a list
    string(REPLACE "." ";" _tag_parts "${_tag}")
    list(LENGTH _tag_parts _tag_len)

    if(_tag_len GREATER_EQUAL 4)
        # Tag already has a 4th build component (e.g. library/v0.1.0.139)
        # Base 4th + commits ahead ensures monotonic progression without backwards regression
        list(GET _tag_parts 0 _p1)
        list(GET _tag_parts 1 _p2)
        list(GET _tag_parts 2 _p3)
        list(GET _tag_parts 3 _p4_base)
        math(EXPR _p4 "${_p4_base} + ${_ahead}")
    elseif(_tag_len EQUAL 3)
        # Standard SemVer tag (e.g. v1.0.10) -> 4th number is commits ahead
        list(GET _tag_parts 0 _p1)
        list(GET _tag_parts 1 _p2)
        list(GET _tag_parts 2 _p3)
        set(_p4 "${_ahead}")
    elseif(_tag_len EQUAL 2)
        list(GET _tag_parts 0 _p1)
        list(GET _tag_parts 1 _p2)
        set(_p3 "0")
        set(_p4 "${_ahead}")
    else()
        list(GET _tag_parts 0 _p1)
        set(_p2 "0")
        set(_p3 "0")
        set(_p4 "${_ahead}")
    endif()

    set(_dot_version "${_p1}.${_p2}.${_p3}.${_p4}")
    set(_comma_version "${_p1},${_p2},${_p3},${_p4}")

    set(${out_git_version} "${_full}" PARENT_SCOPE)
    set(${out_version} "${_dot_version}" PARENT_SCOPE)
    set(${out_version}_COMMA "${_comma_version}" PARENT_SCOPE)
endfunction()
