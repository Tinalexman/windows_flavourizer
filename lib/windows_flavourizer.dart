import 'dart:io';

import 'package:args/args.dart';

/// Current version of `windows_flavourizer`.
const String packageVersion = '0.0.1';

/// Builds the [ArgParser] used to parse command-line arguments.
ArgParser buildArgParser() {
  return ArgParser()
    ..addMultiOption(
      'flavors',
      abbr: 'f',
      help: 'Comma-separated list of flavors (optional if auto-detected)',
    )
    ..addOption(
      'ide',
      abbr: 'i',
      help: 'Target IDE configuration to generate: intellij, vscode, or all',
      allowed: ['intellij', 'vscode', 'all'],
      defaultsTo: 'all',
    )
    ..addOption(
      'base-name',
      abbr: 'n',
      help: 'Base binary name (defaults to pubspec name)',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message and exit.',
    )
    ..addFlag(
      'version',
      abbr: 'v',
      negatable: false,
      help: 'Show version information and exit.',
    )
    ..addFlag(
      'scaffold-entry-points',
      abbr: 's',
      help: 'Automatically create lib/main_<flavor>.dart if missing',
      defaultsTo: false,
    );
}

/// Detect if the project already has flavors configured
List<String> detectFlavors(Directory projectDir) {
  Set<String> flavors = {};

  // Source 1: Check lib/main_*.dart files
  Directory libDir = Directory('${projectDir.path}/lib');
  if (libDir.existsSync()) {
    Iterable<File> mainFiles = libDir.listSync().whereType<File>().where(
        (file) => RegExp(r'^main_[a-zA-Z0-9_-]+\.dart$')
            .hasMatch(file.uri.pathSegments.last));

    for (File file in mainFiles) {
      String name = file.uri.pathSegments.last;
      String flavor = name.replaceFirst('main_', '').replaceFirst('.dart', '');
      flavors.add(flavor);
    }
  }

  // Source 2: Check android/app/build.gradle (or .kts)
  File gradleFile = File('${projectDir.path}/android/app/build.gradle');
  File gradleKtsFile = File('${projectDir.path}/android/app/build.gradle.kts');
  File? targetGradle = gradleFile.existsSync()
      ? gradleFile
      : (gradleKtsFile.existsSync() ? gradleKtsFile : null);

  if (targetGradle != null) {
    String content = targetGradle.readAsStringSync();
    // Regex matching: productFlavors { flavorName { ... } }
    RegExp flavorBlockRegex =
        RegExp(r'productFlavors\s*\{([^}]+)\}', multiLine: true);
    RegExpMatch? match = flavorBlockRegex.firstMatch(content);
    if (match != null) {
      String blockContent = match.group(1)!;
      RegExp entryRegex = RegExp(r'([a-zA-Z0-9_-]+)\s*\{');
      for (RegExpMatch entry in entryRegex.allMatches(blockContent)) {
        String flavor = entry.group(1)!.trim();
        if (flavor != 'create') {
          // Filter out Kotlin DSL create("flavor") keyword if partially matched
          flavors.add(flavor);
        }
      }
    }
  }

  // Source 3: Check flavorizr configuration in pubspec.yaml
  File pubspecFile = File('${projectDir.path}/pubspec.yaml');
  if (pubspecFile.existsSync()) {
    String content = pubspecFile.readAsStringSync();
    if (content.contains('flavorizr:')) {
      RegExp flavorizrRegex =
          RegExp(r'^\s{4}([a-zA-Z0-9_-]+):\s*$', multiLine: true);
      Iterable<RegExpMatch> matches = flavorizrRegex.allMatches(content);
      for (RegExpMatch m in matches) {
        flavors.add(m.group(1)!.trim());
      }
    }
  }

  return flavors.toList()..sort();
}

void scaffoldMissingEntrypoints(
  Directory projectDir,
  String baseName,
  List<String> flavors,
) {
  Directory libDir = Directory('${projectDir.path}/lib');
  if (!libDir.existsSync()) {
    libDir.createSync(recursive: true);
  }

  for (String flavor in flavors) {
    File entrypoint = File('${libDir.path}/main_$flavor.dart');
    if (!entrypoint.existsSync()) {
      entrypoint.writeAsStringSync('''import 'package:flutter/material.dart';
import 'package:$baseName/main.dart' as app;

/// Global access to active flavor if needed
const String currentFlavor = '$flavor';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Launch base application
  app.main();
}
''');
      stdout
          .writeln(' [x] Scaffolded missing entrypoint: lib/main_$flavor.dart');
    }
  }
}

/// Extracts the project name from the `pubspec.yaml` in [dir].
String? extractProjectName(Directory dir) {
  File pubspecFile = File('${dir.path}/pubspec.yaml');
  if (!pubspecFile.existsSync()) return null;

  List<String> lines = pubspecFile.readAsLinesSync();
  for (String line in lines) {
    if (line.trim().startsWith('name:')) {
      return line.split(':')[1].trim();
    }
  }
  return null;
}

/// Executes the flavourizer workflow with the given [arguments].
int run(
  List<String> arguments, {
  Directory? projectDir,
  StringSink? out,
  StringSink? err,
}) {
  StringSink output = out ?? stdout;
  StringSink error = err ?? stderr;
  ArgParser parser = buildArgParser();

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    error.writeln('Error: ${e.message}\n');
    error.writeln('Usage: windows_flavourizer [options]\n');
    error.writeln(parser.usage);
    return 64; // EX_USAGE
  }

  if (results['help'] == true) {
    output.writeln(
        'windows_flavourizer - Automates multi-flavor Windows runner setup for Flutter\n');
    output.writeln('Usage: windows_flavourizer [options]\n');
    output.writeln(parser.usage);
    return 0;
  }

  if (results['version'] == true) {
    output.writeln('windows_flavourizer version $packageVersion');
    return 0;
  }

  Directory dir = projectDir ?? Directory.current;
  File pubspecFile = File('${dir.path}/pubspec.yaml');

  if (!pubspecFile.existsSync()) {
    error.writeln(
        'Error: Must be run in the root of a Flutter project (no pubspec.yaml found).');
    return 1;
  }

  List<String> flavors = results['flavors'] as List<String>;
  String ide = results['ide'] as String;

  // 1. Determine base binary name
  String baseName = results['base-name'] ?? '';
  if (baseName.isEmpty) {
    baseName = extractProjectName(dir) ?? '';
  }

  if (baseName.isEmpty) {
    error.writeln(
        'Error: Could not determine base binary name from pubspec.yaml.');
    return 1;
  }

  if (flavors.isEmpty) {
    stdout.writeln('No flavors specified with -f. Attempting auto-detection...');
    flavors = detectFlavors(dir);

    if (flavors.isEmpty) {
      stderr.writeln(
        'Could not auto-detect flavors. Please pass flavors explicitly:\n'
            '  windows_flavor_tool -f dev,staging,prod',
      );
      exit(1);
    }
    stdout.writeln('Auto-detected flavors: $flavors\n');
  }

  if (results['scaffold-entry-points'] as bool) {
    scaffoldMissingEntrypoints(dir, baseName, flavors);
  }

  output.writeln('Setting up Windows flavors for "$baseName"');
  output.writeln('>>> Flavors: $flavors');
  output.writeln('>>> Target IDE: $ide\n');

  // 2. Generate the ensure_binary.ps1 script
  createPreLaunchScript(dir, baseName, out: output);

  // 3. Patch CMakeLists.txt files
  patchRootCMake(dir, baseName, out: output);
  patchRunnerCMake(dir, out: output);

  // 4. Generate Run Configurations
  if (ide == 'vscode' || ide == 'all') {
    generateVSCodeConfigs(dir, baseName, flavors, out: output);
  }

  if (ide == 'intellij' || ide == 'all') {
    generateIntelliJConfigs(dir, baseName, flavors, out: output);
  }

  output.writeln(
      '\nDone! Restart or reload your IDE project to see the new configurations.');
  return 0;
}

/// Generates the pre-launch compilation PowerShell script `scripts/ensure_binary.ps1`.
void createPreLaunchScript(Directory dir, String baseName, {StringSink? out}) {
  StringSink output = out ?? stdout;
  String scriptPath = '${dir.path}/scripts/ensure_binary.ps1';
  File file = File(scriptPath);
  file.parent.createSync(recursive: true);

  file.writeAsStringSync('''
param(
    [Parameter(Mandatory=\$true)][string]\$Flavor,
    [Parameter(Mandatory=\$true)][string]\$Target
)

\$binaryPath = "build\\windows\\x64\\\$Flavor\\runner\\\$Flavor\\Debug\\${baseName}_\$Flavor.exe"

if (Test-Path \$binaryPath) {
    exit 0
}

Write-Host "[Pre-Run] Compiling native Windows binary for flavor '\$Flavor'..." -ForegroundColor Cyan

\$env:APP_FLAVOR = \$Flavor
flutter build windows --debug --flavor \$Flavor --target \$Target

if (Test-Path \$binaryPath) {
    exit 0
} else {
    Write-Error "[Pre-Run] Build finished but \$binaryPath not found."
    exit 1
}
''');
  output.writeln(' [x] Created scripts/ensure_binary.ps1');
}

/// Patches `windows/CMakeLists.txt` to inject dynamic flavor-aware binary naming.
bool patchRootCMake(Directory dir, String baseName, {StringSink? out}) {
  StringSink output = out ?? stdout;
  File file = File('${dir.path}/windows/CMakeLists.txt');
  if (!file.existsSync()) return false;

  String content = file.readAsStringSync();

  // Fix install prefix force to prevent Program Files permission error
  String badInstallPattern =
      'if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)\n  set(CMAKE_INSTALL_PREFIX "\${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)\nendif()';
  String goodInstall =
      'set(CMAKE_INSTALL_PREFIX "\${BUILD_BUNDLE_DIR}" CACHE PATH "Installation prefix" FORCE)';
  if (content.contains(badInstallPattern)) {
    content = content.replaceFirst(badInstallPattern, goodInstall);
  }

  // Inject flavor-aware binary name macro if not already added
  if (!content.contains('FLUTTER_APP_FLAVOR')) {
    RegExp binaryRegex = RegExp(r'set\(BINARY_NAME\s*"[^"]+"\s*\)');
    String flavorMacro = '''
if(DEFINED ENV{APP_FLAVOR})
  set(BINARY_NAME "${baseName}_\$ENV{APP_FLAVOR}")
elseif(DEFINED ENV{FLUTTER_APP_FLAVOR})
  set(BINARY_NAME "${baseName}_\$ENV{FLUTTER_APP_FLAVOR}")
else()
  set(BINARY_NAME "$baseName")
endif()''';

    if (binaryRegex.hasMatch(content)) {
      content = content.replaceFirst(binaryRegex, flavorMacro);
    }
  }

  file.writeAsStringSync(content);
  output.writeln(' [x] Patched windows/CMakeLists.txt');
  return true;
}

/// Patches `windows/runner/CMakeLists.txt` to isolate output directories per flavor.
bool patchRunnerCMake(Directory dir, {StringSink? out}) {
  StringSink output = out ?? stdout;
  File file = File('${dir.path}/windows/runner/CMakeLists.txt');
  if (!file.existsSync()) return false;

  String content = file.readAsStringSync();

  if (!content.contains('RUNTIME_OUTPUT_DIRECTORY')) {
    String targetAnchor = 'add_executable(\${BINARY_NAME} WIN32';
    String flavorProperties = '''
add_executable(\${BINARY_NAME} WIN32
if(DEFINED ENV{APP_FLAVOR})
  set(TARGET_FLAVOR "\$ENV{APP_FLAVOR}")
elseif(DEFINED ENV{FLUTTER_APP_FLAVOR})
  set(TARGET_FLAVOR "\$ENV{FLUTTER_APP_FLAVOR}")
endif()

if(DEFINED TARGET_FLAVOR)
  set_target_properties(\${BINARY_NAME} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "\${CMAKE_BINARY_DIR}/runner/\${TARGET_FLAVOR}/\$<CONFIG>"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "\${CMAKE_BINARY_DIR}/runner/\${TARGET_FLAVOR}/Debug"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "\${CMAKE_BINARY_DIR}/runner/\${TARGET_FLAVOR}/Release"
    RUNTIME_OUTPUT_DIRECTORY_PROFILE "\${CMAKE_BINARY_DIR}/runner/\${TARGET_FLAVOR}/Profile"
  )
endif()''';

    content = content.replaceFirst(targetAnchor, flavorProperties);
    file.writeAsStringSync(content);
    output.writeln(' [x] Patched windows/runner/CMakeLists.txt');
    return true;
  }
  return false;
}

/// Generates `.vscode/tasks.json` and `.vscode/launch.json` for VS Code.
void generateVSCodeConfigs(
  Directory dir,
  String baseName,
  List<String> flavors, {
  StringSink? out,
}) {
  StringSink output = out ?? stdout;
  Directory vscodeDir = Directory('${dir.path}/.vscode');
  if (!vscodeDir.existsSync()) {
    vscodeDir.createSync(recursive: true);
  }

  // 1. tasks.json
  StringBuffer tasksJson = StringBuffer('''{
  "version": "2.0.0",
  "tasks": [''');

  for (int i = 0; i < flavors.length; i++) {
    final flavor = flavors[i];
    final targetPath = File('${dir.path}/lib/main_$flavor.dart').existsSync()
        ? 'lib/main_$flavor.dart'
        : 'lib/main.dart';

    tasksJson.write('''
    {
      "label": "Ensure $flavor Binary",
      "type": "shell",
      "command": "powershell.exe",
      "args": [
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "\${workspaceFolder}/scripts/ensure_binary.ps1",
        "-Flavor",
        "$flavor",
        "-Target",
        "$targetPath"
      ],
      "presentation": {
        "reveal": "silent",
        "panel": "shared"
      }
    }${i < flavors.length - 1 ? ',' : ''}''');
  }
  tasksJson.write('\n  ]\n}');
  File('${vscodeDir.path}/tasks.json').writeAsStringSync(tasksJson.toString());
  output.writeln(' [x] Generated .vscode/tasks.json');

  // 2. launch.json
  StringBuffer launchJson = StringBuffer('''{
  "version": "0.2.0",
  "configurations": [''');

  for (int i = 0; i < flavors.length; i++) {
    String flavor = flavors[i];
    String targetPath = File('${dir.path}/lib/main_$flavor.dart').existsSync()
        ? 'lib/main_$flavor.dart'
        : 'lib/main.dart';

    launchJson.write('''
    {
      "name": "Windows ($flavor)",
      "request": "launch",
      "type": "dart",
      "program": "$targetPath",
      "preLaunchTask": "Ensure $flavor Binary",
      "args": [
        "-d",
        "windows",
        "--flavor",
        "$flavor",
        "--use-application-binary=\${workspaceFolder}/build/windows/x64/$flavor/runner/$flavor/Debug/${baseName}_$flavor.exe"
      ]
    }${i < flavors.length - 1 ? ',' : ''}''');
  }

  // Add a compound target to launch all flavors at once
  String flavorNamesQuoted = flavors.map((f) => '"Windows ($f)"').join(', ');
  launchJson.write(''',
    {
      "name": "Windows (All Flavors)",
      "configurations": [$flavorNamesQuoted]
    }
  ]
}''');

  File('${vscodeDir.path}/launch.json')
      .writeAsStringSync(launchJson.toString());
  output.writeln(' [x] Generated .vscode/launch.json');
}

/// Generates run configuration XML files in `.idea/runConfigurations/` for IntelliJ IDEA and Android Studio.
void generateIntelliJConfigs(
  Directory dir,
  String baseName,
  List<String> flavors, {
  StringSink? out,
}) {
  StringSink output = out ?? stdout;
  Directory runConfigsDir = Directory('${dir.path}/.idea/runConfigurations');
  if (!runConfigsDir.existsSync()) {
    runConfigsDir.createSync(recursive: true);
  }

  for (final flavor in flavors) {
    String targetPath = 'lib/main_$flavor.dart';
    String targetName = File('${dir.path}/$targetPath').existsSync()
        ? targetPath
        : 'lib/main.dart';

    // 1. Generate the Pre-Launch Task as a Project Run Configuration
    File taskConfigFile =
        File('${runConfigsDir.path}/Ensure_${flavor}_Binary.xml');
    String taskXml = '''<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="Ensure $flavor Binary" type="ShConfigurationType">
    <option name="SCRIPT_TEXT" value="powershell.exe -ExecutionPolicy Bypass -File &quot;\$PROJECT_DIR\$/scripts/ensure_binary.ps1&quot; -Flavor $flavor -Target $targetName" />
    <option name="INDEPENDENT_SCRIPT_PATH" value="true" />
    <option name="SCRIPT_PATH" value="" />
    <option name="SCRIPT_OPTIONS" value="" />
    <option name="INDEPENDENT_SCRIPT_WORKING_DIRECTORY" value="true" />
    <option name="SCRIPT_WORKING_DIRECTORY" value="\$PROJECT_DIR\$" />
    <option name="INDEPENDENT_INTERPRETER_PATH" value="true" />
    <option name="INTERPRETER_PATH" value="" />
    <option name="INTERPRETER_OPTIONS" value="" />
    <option name="EXECUTE_IN_TERMINAL" value="false" />
    <option name="EXECUTE_SCRIPT_FILE" value="false" />
    <envs />
    <method v="2" />
  </configuration>
</component>''';
    taskConfigFile.writeAsStringSync(taskXml);

    // 2. Generate the Flutter Run Configuration referencing the Pre-Launch Task
    final configFile = File('${runConfigsDir.path}/Windows_$flavor.xml');
    final xml = '''<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="Windows ($flavor)" type="FlutterRunConfigurationType" factoryName="Flutter">
    <option name="additionalArgs" value="-d windows --flavor $flavor --use-application-binary=\$PROJECT_DIR\$\\build\\windows\\x64\\$flavor\\runner\\$flavor\\Debug\\${baseName}_$flavor.exe" />
    <option name="buildFlavor" value="$flavor" />
    <option name="filePath" value="\$PROJECT_DIR\$/$targetName" />
    <envs>
      <env name="APP_FLAVOR" value="$flavor" />
    </envs>
    <method v="2">
      <option name="RunConfigurationTask" enabled="true" run_configuration_name="Ensure $flavor Binary" run_configuration_type="ShConfigurationType" />
    </method>
  </configuration>
</component>''';

    configFile.writeAsStringSync(xml);
    output
        .writeln(' [x] Generated .idea/runConfigurations/Windows_$flavor.xml');
  }

  // 3. Generate Compound Configuration to run all flavors together
  File compoundFile = File('${runConfigsDir.path}/Windows_All_Flavors.xml');
  StringBuffer compoundXml =
      StringBuffer('''<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="Windows (All Flavors)" type="CompoundRunConfigurationType">
''');

  for (final flavor in flavors) {
    compoundXml.write(
        '    <toRun name="Windows ($flavor)" type="FlutterRunConfigurationType" />\n');
  }

  compoundXml.write('''    <method v="2" />
  </configuration>
</component>''');

  compoundFile.writeAsStringSync(compoundXml.toString());
  output.writeln(
      ' [x] Generated .idea/runConfigurations/Windows_All_Flavors.xml');
}
