## 0.0.1

- Initial release.
- Automatically patch CMake configurations (`windows/CMakeLists.txt` and `windows/runner/CMakeLists.txt`) for flavor-isolated binaries and builds.
- Fix `CMAKE_INSTALL_PREFIX` cache issues on Windows.
- Generate `scripts/ensure_binary.ps1` to automate native binary compilation ahead of launches.
- Generate Visual Studio Code debug configurations (`tasks.json` and `launch.json`) with flavor and compound targets.
- Generate IntelliJ IDEA / Android Studio run configurations (`.idea/runConfigurations/`) with flavor and compound targets.
