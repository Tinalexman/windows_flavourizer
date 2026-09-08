# Example: Multi-Flavor Flutter Windows Project

This example demonstrates how to configure and use `windows_flavourizer` in a Flutter desktop application.

---

## 1. Project Setup

Create dedicated entrypoint files for your flavors in the `lib/` directory:

### `lib/main_dev.dart`
```dart
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp(flavor: 'Development'));
}

class MyApp extends StatelessWidget {
  final String flavor;
  const MyApp({super.key, required this.flavor});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App ($flavor)',
      theme: ThemeData(primarySwatch: Colors.green),
      home: Scaffold(
        appBar: AppBar(title: Text('Flutter Windows: $flavor')),
        body: Center(child: Text('Running on $flavor')),
      ),
    );
  }
}
```

### `lib/main_prod.dart`
```dart
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp(flavor: 'Production'));
}

class MyApp extends StatelessWidget {
  final String flavor;
  const MyApp({super.key, required this.flavor});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App ($flavor)',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: Scaffold(
        appBar: AppBar(title: Text('Flutter Windows: $flavor')),
        body: Center(child: Text('Running on $flavor')),
      ),
    );
  }
}
```

---

## 2. Run Windows Flavourizer

From the root directory of your Flutter project, run:

```bash
# Using dart run (if added as dev_dependency):
dart run windows_flavourizer --flavors dev,staging,prod

# Or globally:
windows_flavourizer -f dev,staging,prod
```

---

## 3. Generated Files

The tool generates the following files:

```
my_app/
├── scripts/
│   └── ensure_binary.ps1
├── windows/
│   ├── CMakeLists.txt        (Patched with dynamic binary naming)
│   └── runner/
│       └── CMakeLists.txt    (Patched with isolated output directories)
├── .vscode/
│   ├── launch.json           (Debug configs for dev, staging, prod, and all)
│   └── tasks.json            (Pre-launch compilation tasks)
└── .idea/runConfigurations/
    ├── Ensure_dev_Binary.xml
    ├── Windows_dev.xml
    ├── Windows_staging.xml
    ├── Windows_prod.xml
    └── Windows_All_Flavors.xml
```

---

## 4. Run & Debug

- **VS Code**: Press `Ctrl+Shift+D` to open Run & Debug, select **Windows (dev)**, and press `F5`.
- **IntelliJ IDEA / Android Studio**: Select **Windows (dev)** from the run configuration dropdown and click **Run** or **Debug**.
