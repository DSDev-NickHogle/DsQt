# Versioning, App Metadata, and Qt Discovery Guide

This document explains how DsQt and downstream applications track, stamp, and display version information across builds, packages, logs, and Windows Explorer file metadata, as well as the simplified Qt discovery architecture.

---

## 1. Motivation & Historical Problems

Prior to this versioning architecture, version management in DsQt and downstream applications suffered from several issues:

1. **Dual Source of Truth & Drift**: DsQt stored `0.1.0` in `Library/VERSION.txt`. In GitHub Actions CI (`build-library.yml`), runs generated a version using `${{ github.run_number }}` (e.g. `0.1.0.139`) and pushed a tag (`library/v0.1.0.139`), but never passed this into CMake.
2. **Missing Installed Metadata**: When DsQt was installed to `~/Documents/DsQt`, no file existed to tell downstream projects what Git commit, branch, or dirty status was linked.
3. **PE Binary vs Display Discrepancy**: Windows binaries store version information in two formats:
   - **Fixed Info Struct (`FILEVERSION` / `PRODUCTVERSION`)**: Requires strictly 4 integers separated by commas (e.g. `1,0,10,0`) for OS loader compatibility.
   - **`StringFileInfo` (`ProductVersion`, `Comments`)**: Free-form text for display in Windows Explorer.
   Downstream projects duplicated ~30 lines of bespoke regexes in every `CMakeLists.txt` to parse Git tags into comma strings.
4. **Qt Discovery Fragmentation**: Multiple conflicting layers (`CMAKE_PREFIX_PATH`, `Qt6_DIR`, `CMakeUserPresets.json`, Qt Creator kits, batch files, and custom scripts like `Qt6AutoDetect.cmake`) fought each other when locating Qt.

---

## 2. Standardized Version Taxonomy

DsQt standardizes on symmetrical, prefix-separated variables across both the library and downstream applications:

| Scope | Variable | Format | Example | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **DsQt Library** | `DSQT_VERSION` | 4-part dot-separated | `0.2.0.71` | CMake `project(Dsqt VERSION ...)` and package versioning. |
| | `DSQT_VERSION_COMMA` | 4-part comma-separated | `0,2,0,71` | Windows PE resource `FILEVERSION` / `PRODUCTVERSION`. |
| | `DSQT_VERSION_GIT` | Free-form string | `0.2.0+71 (main@b80746d)` | Startup banner, About dialog, and `app.rc` Comments. |
| **Downstream App** | `DS_APP_VERSION` | 4-part dot-separated | `1.0.10.7` | CMake `project(AppName VERSION ...)`. |
| | `DS_APP_VERSION_COMMA` | 4-part comma-separated | `1,0,10,7` | Windows PE resource `FILEVERSION` / `PRODUCTVERSION`. |
| | `DS_APP_VERSION_GIT` | Free-form string | `1.0.10+7 (main@0c233a8-dirty)` | Startup banner, About dialog, and `app.rc` ProductVersion. |

### How the 4-part Tuple is Calculated
`dsqt_get_git_version()` queries Git describe tags and automatically calculates:
- If a tag is standard SemVer (e.g. `v1.0.10`):
  - `MAJOR.MINOR.PATCH.COMMITS_AHEAD` (e.g. `1.0.10.7` if 7 commits ahead of tag, or `1.0.10.0` if exactly on tag).
- If a legacy tag has 4 parts (e.g. `library/v0.1.0.139`):
  - `MAJOR.MINOR.PATCH.(BASE_BUILD + COMMITS_AHEAD)` so that versions are always strictly monotonic and never go backwards.
- `DS_APP_VERSION_COMMA` is automatically populated in the caller's scope without needing a third argument.

---

## 3. Windows Explorer Metadata (`app.rc.in`)

Downstream projects embed versioning into Windows PE resources via `cmake/app.rc.in`:

```rc
VS_VERSION_INFO VERSIONINFO
 FILEVERSION @DS_APP_VERSION_COMMA@
 PRODUCTVERSION @DS_APP_VERSION_COMMA@
 FILEFLAGS 0
 FILEFLAGSMASK VS_FFI_FILEFLAGSMASK
 FILEOS VOS_NT_WINDOWS32
 FILETYPE VFT_APP
 FILESUBTYPE VFT2_UNKNOWN
BEGIN
    BLOCK "StringFileInfo"
    BEGIN
        BLOCK "040904E4"
        BEGIN
            VALUE "CompanyName", "Downstream"
            VALUE "FileDescription", "@DS_PROJECT_DESC@"
            VALUE "FileVersion", "@DS_APP_VERSION@"
            VALUE "InternalName", "@DS_APP_NAME@"
            VALUE "LegalCopyright", "Copyright © Downstream. All rights reserved."
            VALUE "OriginalFilename", "@DS_EXE_NAME@.exe"
            VALUE "ProductName", "@DS_PROJECT_NAME@"
            VALUE "ProductVersion", "@DS_APP_VERSION_GIT@"
            VALUE "Comments", "Built with DsQt @DSQT_VERSION_GIT@"
        END
    END
    BLOCK "VarFileInfo"
    BEGIN
        VALUE "Translation", 0x409, 1252
    END
END
```

When right-clicking `app.exe` in Windows Explorer $\rightarrow$ **Properties $\rightarrow$ Details**:
- **Product version**: `1.0.10+7 (windows-build-test@0c233a8-dirty)`
- **Comments**: `Built with DsQt 0.2.0+71 (main@b80746d)`

---

## 4. Install-Time Stamping (`dsqt_version_git.txt`)

To ensure multi-config safety (Debug vs. Release builds coexisting in `~/Documents/DsQt`):
1. During `cmake --install --config <CONFIG>`, DsQt writes:
   `${CMAKE_INSTALL_PREFIX}/lib/<CONFIG>/dsqt_version_git.txt`
2. When a downstream consumer calls `find_package(Dsqt REQUIRED ...)`, `DsqtConfig.cmake` resolves the file matching the consumer's `CMAKE_BUILD_TYPE`:
   `${DSQT_INSTALL_PREFIX}/lib/${CMAKE_BUILD_TYPE}/dsqt_version_git.txt`
3. `DsqtConfig.cmake` exports `DSQT_VERSION_GIT` to the consumer project automatically.

---

## 5. Qt Discovery Architecture (`DsqtQtDetect.cmake`)

Rather than maintaining custom scripts like `Qt6AutoDetect.cmake` in every client project, Qt discovery is centralized in DsQt:

### Standardized Search Order
When Qt is not already specified, CMake probes in order:
1. `Qt6_ROOT` or `-DQT_VERSION_OR_PATH` (CLI or Preset override)
2. Environment variable `$ENV{QTDIR}`
3. Sibling folder: `../Qt/*/msvc2022_64` or `../../Qt/*/msvc2022_64`
4. Standard install: `C:/Qt/*/msvc2022_64`

### Separation of Responsibilities
- **`Qt6_ROOT`**: Dedicated exclusively to locating Qt.
- **`CMAKE_PREFIX_PATH`**: Kept clean and unpolluted for DsQt, vcpkg, and user dependencies.
- **`build_and_install.bat`**: Acts as a thin wrapper. Passing `-qt <arg>` simply forwards `-DQT_VERSION_OR_PATH="<arg>"` to CMake without batch-file regexes or duplicate directory checks.
- **Qt Creator**: Uses its Kit prefix natively; CMake detects it and skips auto-discovery.

---

## 6. Migration Guide for Existing Downstream Projects

To upgrade an existing downstream application:

### Step 1: Remove Legacy Auto-Detect Scripts
Delete any project-local `cmake/Qt6AutoDetect.cmake` and remove calls to it from `CMakeLists.txt`.

### Step 2: Update `CMakeLists.txt`
```cmake
# 1. Find DsQt
find_package(Dsqt REQUIRED COMPONENTS Core Bridge ...)
message(STATUS "Built against DsQt: ${DSQT_VERSION_GIT}")

# 2. Resolve App Git Version (automatically sets DS_APP_VERSION_COMMA)
dsqt_get_git_version("${CMAKE_CURRENT_SOURCE_DIR}" DS_APP_VERSION_GIT DS_APP_VERSION)
message(STATUS "App Version: ${DS_APP_VERSION_GIT} (SemVer: ${DS_APP_VERSION})")

# 3. Define Project
project(${DS_APP_NAME} VERSION ${DS_APP_VERSION} LANGUAGES CXX)

# 4. Configure app.rc
configure_file("cmake/app.rc.in" "app.rc")

# 5. Pass compile definitions to target
target_compile_definitions(${DS_EXE_NAME} PRIVATE
    DS_APP_VERSION_GIT="${DS_APP_VERSION_GIT}"
    DSQT_VERSION_GIT="${DSQT_VERSION_GIT}"
)
```

### Step 3: Configure `main.cpp`
`DsGuiApplication` automatically initializes `applicationVersion()` to `DS_APP_VERSION_GIT` in its constructor:

```cpp
// Set application identity before DsGuiApplication constructor prints startup banner
QCoreApplication::setOrganizationName("Downstream");
QCoreApplication::setApplicationName("AppName");
QCoreApplication::setOrganizationDomain("downstream.com");

DsGuiApplication app(argc, argv);
```

### Step 4: Startup Banner & About Dialog
Upon startup, `DsGuiApplication` prints:
```text
========================================
AppName v 1.0.10+7 (main@0c233a8-dirty)
DsQt 0.2.0+71 (main@b80746d) | Qt 6.10.0 | PID: 1234
Started: 2026-10-22T14:30:00
========================================
```
The **Help $\rightarrow$ About** dialog in `DsAppMenuBar` anchors beneath the top menu bar (`y: window.y + windowMenuBar.height + 10`), ensuring accessibility on wide museum canvas displays when remoting via LogMeIn (LMI).

---

## 7. CI Workflow Roadmap (`build-library.yml`)

The legacy CI pattern of appending `${{ github.run_number }}` to create automated Git tags on every commit is retired in favor of standard release automation:

1. **Delete `Library/VERSION.txt`**: Single source of truth is Git tags.
2. **Stop Automated Push of Tags on Every Commit**:
   - Commits to `main` compile and run tests.
   - Tags are pushed only when publishing formal releases (`v0.2.0`, `v0.2.1`, etc.).
3. **CI Artifact Naming**:
   - `build-library.yml` determines the version from `git describe --tags --always`.
   - Downloadable zip artifacts are named `dsqt-${VERSION}.zip`.
4. **Transition to `v0.2.0`**:
   - Moving the base tag from legacy `0.1.0` to `v0.2.0` cleans the slate of all historical `0.1.0.x` run-number tags, establishing monotonic 4-part versions (`0.2.0.commits_ahead`) moving forward.
