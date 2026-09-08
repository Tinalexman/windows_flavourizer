# Windows Flavourizer

[![pub package](https://img.shields.io/pub/v/windows_flavourizer.svg)](https://pub.dev/packages/windows_flavourizer)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.0.0%20%3C4.0.0-blue.svg)](https://dart.dev)
[![Platform](https://img.shields.io/badge/platform-windows-0078D6.svg)](https://flutter.dev/desktop)

**Windows Flavourizer** is a command-line tool that automates multi-flavor Windows runner setup and IDE run/debug configurations for Flutter desktop projects on **VS Code** and **IntelliJ IDEA / Android Studio**.

---

## 💡 The Problem

Flutter natively supports flavor-based development for mobile (Android product flavors and iOS schemes), but Windows desktop flavor support poses several hurdles:

1. **Build Artifact Collisions**: By default, Flutter compiles the Windows runner into a single shared output directory (`build/windows/x64/runner/<CONFIG>`). Switching between flavors overwrites previously compiled binaries and leads to stale or mismatched builds.
2. **Identical Executable Names**: The binary name in `windows/CMakeLists.txt` is hardcoded (e.g., `set(BINARY_NAME "my_app")`). Flutter does not dynamically rename the output executable per flavor.
3. **CMake Install Prefix Errors**: Default CMake configs can attempt to install to system directories like `Program Files`, resulting in permission errors.
4. **IDE Debugging Friction**: Launching and debugging specific flavors directly from IDE run configurations often fails to attach properly or rebuilds the wrong flavor target.

---

## ✨ What Windows Flavourizer Does

`windows_flavourizer` provides a one-command solution that transforms your Flutter Windows project:

- **Isolated Binary Output**: Patches `windows/runner/CMakeLists.txt` so each flavor outputs to its own directory:
  `build/windows/x64/<flavor>/runner/<flavor>/<CONFIG>/`
- **Dynamic Binary Naming**: Patches `windows/CMakeLists.txt` to suffix binary names with the active flavor (e.g., `my_app_dev.exe`, `my_app_prod.exe`).
- **CMake Permission Fix**: Resolves `CMAKE_INSTALL_PREFIX` permission conflicts automatically.
- **Pre-Launch Build Automation**: Generates `scripts/ensure_binary.ps1`, a PowerShell script that checks if the flavor binary exists, and compiles it via `flutter build windows --debug --flavor <flavor>` if needed.
- **VS Code Configurations**: Generates `.vscode/tasks.json` and `.vscode/launch.json` with pre-launch tasks, entrypoint mapping, `--use-application-binary` launch args, and a compound launcher to run all flavors concurrently.
- **IntelliJ / Android Studio Configurations**: Generates `.idea/runConfigurations/` XML files for each flavor and a compound configuration to launch all flavors at once.

---

## 📦 Installation

You can activate `windows_flavourizer` globally:

```bash
dart pub global activate windows_flavourizer
```

Or add it as a `dev_dependency` in your Flutter project's `pubspec.yaml`:

```yaml
dev_dependencies:
  windows_flavourizer: ^0.0.1
```

---

## 🚀 Usage

Run the tool from the **root directory** of your Flutter project:

### If activated globally:
```bash
windows_flavourizer [options]
```

### If added as a dev dependency:
```bash
dart run windows_flavourizer [options]
```

---

## ⚙️ CLI Options

| Option | Abbreviation | Default | Description |
|---|:---:|:---:|---|
| `--flavors` | `-f` | `dev,staging,prod` | Comma-separated list of flavors to generate configurations for. |
| `--ide` | `-i` | `all` | Target IDE configurations to generate: `intellij`, `vscode`, or `all`. |
| `--base-name` | `-n` | `name` in `pubspec.yaml` | Base binary name for the executable. |
| `--help` | `-h` | - | Show usage information and exit. |
| `--version` | `-v` | - | Show version information and exit. |

---

## 📖 Examples

### 1. Default Setup (dev, staging, prod for both IDEs)
```bash
windows_flavourizer
```

### 2. Custom Flavors
```bash
windows_flavourizer --flavors dev,qa,prod
```

### 3. Target Specific IDE
Generate configurations only for **VS Code**:
```bash
windows_flavourizer --ide vscode
```

Generate configurations only for **IntelliJ IDEA / Android Studio**:
```bash
windows_flavourizer --ide intellij
```

### 4. Custom Base Binary Name
```bash
windows_flavourizer --base-name my_custom_app
```

---

## 📁 Recommended Project Structure

`windows_flavourizer` automatically checks for dedicated flavor entrypoints. If a flavor-specific entrypoint is found (`lib/main_<flavor>.dart`), it is used; otherwise, it falls back to `lib/main.dart`:

```
my_flutter_app/
├── lib/
│   ├── main.dart            # Fallback entrypoint
│   ├── main_dev.dart        # Entrypoint for 'dev' flavor
│   ├── main_staging.dart    # Entrypoint for 'staging' flavor
│   └── main_prod.dart       # Entrypoint for 'prod' flavor
├── scripts/
│   └── ensure_binary.ps1    # [Generated] Pre-launch build script
├── windows/
│   ├── CMakeLists.txt       # [Patched] Dynamic binary naming & install prefix fix
│   └── runner/
│       └── CMakeLists.txt   # [Patched] Flavor-specific output directories
├── .vscode/                 # [Generated if ide is vscode or all]
│   ├── launch.json
│   └── tasks.json
└── .idea/runConfigurations/ # [Generated if ide is intellij or all]
    ├── Ensure_dev_Binary.xml
    ├── Windows_dev.xml
    ├── Windows_All_Flavors.xml
    └── ...
```

---

## 🖥️ Running in Your IDE

### Visual Studio Code
1. Open the **Run and Debug** panel (`Ctrl + Shift + D`).
2. Select your target configuration from the dropdown:
   - **Windows (dev)**
   - **Windows (staging)**
   - **Windows (prod)**
   - **Windows (All Flavors)** *(launches all flavors simultaneously)*
3. Press **F5** to start debugging.

### IntelliJ IDEA / Android Studio
1. Reload or restart the IDE project if needed.
2. Select your run configuration from the top toolbar dropdown:
   - **Windows (dev)**
   - **Windows (staging)**
   - **Windows (prod)**
   - **Windows (All Flavors)**
3. Click the **Run** or **Debug** icon.

---

## 🔧 How It Works Under the Hood

1. **Pre-Launch Validation (`scripts/ensure_binary.ps1`)**:
   Checks whether `build\windows\x64\$Flavor\runner\$Flavor\Debug\<baseName>_$Flavor.exe` exists. If not present, it sets `$env:APP_FLAVOR` and executes `flutter build windows --debug --flavor $Flavor --target $Target`.

2. **Root CMake (`windows/CMakeLists.txt`)**:
   Injects logic to inspect environment variables `APP_FLAVOR` and `FLUTTER_APP_FLAVOR`, dynamically setting `BINARY_NAME` to `${baseName}_${FLAVOR}`.

3. **Runner CMake (`windows/runner/CMakeLists.txt`)**:
   Applies `set_target_properties` with custom `RUNTIME_OUTPUT_DIRECTORY` targets:
   - Debug: `build/windows/x64/<flavor>/runner/<flavor>/Debug`
   - Release: `build/windows/x64/<flavor>/runner/<flavor>/Release`
   - Profile: `build/windows/x64/<flavor>/runner/<flavor>/Profile`

4. **Fast IDE Launch**:
   Launch configs execute Flutter using `--use-application-binary` pointing directly to the compiled flavor executable. This bypasses repetitive CMake re-generation during normal debug sessions while keeping hot reload and debugging fully functional.

---

## ⚠️ Assumptions and Prerequisites

### Standard Flutter CMake Templates
- It assumes `windows/CMakeLists.txt` uses the standard Flutter variable definition line `set(BINARY_NAME "...")` and the default installation prefix block (`if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)...`).
- It assumes `windows/runner/CMakeLists.txt` declares `add_executable(${BINARY_NAME} WIN32` as the target anchor for injecting `isolate_flavor_runner_target`.
- Projects with custom, non-standard CMake templates may require manual adjustments.

### Windows Host Environment
- It assumes execution on Windows where `powershell.exe` is present in `PATH`.
- It assumes the local security/execution policy allows `-ExecutionPolicy Bypass` when executing `ensure_binary.ps1`.

### Standard Windows Executable Output Paths
It assumes the compiled artifact resides at:

```plaintext
build\windows\x64\<flavor>\runner\<flavor>\Debug\<baseName>_<flavor>.exe
```

If a project renames the target binary inside CMake to something other than `${baseName}_${flavor}`, the runner will not locate it.

### IDE Workspace Layouts
- **IntelliJ / Android Studio**: Assumes the standard `.idea/` folder structure exists (or will be parsed on open) so it can register project-contained `.idea/runConfigurations/*.xml` files.
- **VS Code**: Assumes configurations should live inside `.vscode/tasks.json` and `.vscode/launch.json`.

### Platform Scope
It remains strictly targeted at Windows desktop runners (`windows/`). It does not configure iOS/macOS Xcode schemes or Android Gradle build variants beyond reading Gradle flavors for discovery.

---

## 🛠️ Troubleshooting

- **First-Time Build Takes Time**: The very first time you launch a flavor, the pre-launch task will compile the native Windows binary. Subsequent launches will detect the existing binary and start instantly.
- **Cache Invalidation**: If you modify native C++ code or plugins, clean the build cache to ensure a fresh compilation:
  ```bash
  flutter clean
  flutter pub get
  ```
- **PowerShell Script Execution**: Generated tasks run PowerShell with `-ExecutionPolicy Bypass`. If running `scripts/ensure_binary.ps1` manually in a terminal, ensure your PowerShell execution policy allows local scripts:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```

---

## 📄 License

This project is open source and available under the terms defined in the repository.
