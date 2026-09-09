import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:windows_flavourizer/windows_flavourizer.dart';

void main() {
  group('ArgParser', () {
    test('parses defaults correctly', () {
      final parser = buildArgParser();
      final results = parser.parse([]);

      expect(results['flavors'], equals([]));
      expect(results['ide'], equals('all'));
      expect(results['base-name'], isNull);
      expect(results['help'], isFalse);
      expect(results['version'], isFalse);
      expect(results['scaffold-entry-points'], isFalse);
    });

    test('parses custom flags', () {
      final parser = buildArgParser();
      final results = parser.parse([
        '-f',
        'alpha,beta',
        '-i',
        'vscode',
        '-n',
        'custom_app',
        '-s',
      ]);

      expect(results['flavors'], equals(['alpha', 'beta']));
      expect(results['ide'], equals('vscode'));
      expect(results['base-name'], equals('custom_app'));
      expect(results['scaffold-entry-points'], isTrue);
    });
  });

  group('Windows Flavourizer Workflow', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('wf_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('extractProjectName extracts name correctly', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: my_test_project
description: A test project
version: 1.0.0
''');

      final name = extractProjectName(tempDir);
      expect(name, equals('my_test_project'));
    });

    test('detectFlavors auto-detects flavors from lib/main_*.dart', () {
      final libDir = Directory('${tempDir.path}/lib')..createSync();
      File('${libDir.path}/main_dev.dart').writeAsStringSync('void main() {}');
      File('${libDir.path}/main_prod.dart').writeAsStringSync('void main() {}');

      final detected = detectFlavors(tempDir);
      expect(detected, equals(['dev', 'prod']));
    });

    test('detectFlavors auto-detects flavors from build.gradle', () {
      final gradleDir = Directory('${tempDir.path}/android/app')..createSync(recursive: true);
      File('${gradleDir.path}/build.gradle').writeAsStringSync('''
android {
    flavorDimensions "default"
    productFlavors {
        staging {
            dimension "default"
        }
        production {
            dimension "default"
        }
    }
}
''');

      final detected = detectFlavors(tempDir);
      expect(detected, equals(['production', 'staging']));
    });

    test('scaffoldMissingEntrypoints creates missing entrypoint files', () {
      scaffoldMissingEntrypoints(tempDir, 'my_app', ['dev', 'prod']);

      final devEntry = File('${tempDir.path}/lib/main_dev.dart');
      final prodEntry = File('${tempDir.path}/lib/main_prod.dart');

      expect(devEntry.existsSync(), isTrue);
      expect(prodEntry.existsSync(), isTrue);
      expect(devEntry.readAsStringSync(), contains("currentFlavor = 'dev'"));
    });

    test('createPreLaunchScript creates ensure_binary.ps1', () {
      createPreLaunchScript(tempDir, 'sample_app');
      final script = File('${tempDir.path}/scripts/ensure_binary.ps1');

      expect(script.existsSync(), isTrue);
      final content = script.readAsStringSync();
      expect(content, contains('sample_app_\$Flavor.exe'));
      expect(content, contains('flutter build windows --debug'));
    });

    test('patchRootCMake modifies install prefix and binary name macro', () {
      final cmakeDir = Directory('${tempDir.path}/windows')..createSync();
      final cmakeFile = File('${cmakeDir.path}/CMakeLists.txt');
      cmakeFile.writeAsStringSync('''
cmake_minimum_required(VERSION 3.14)
project(test_app LANGUAGES CXX)

set(BINARY_NAME "test_app")

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "\${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()
''');

      final patched = patchRootCMake(tempDir, 'test_app');
      expect(patched, isTrue);

      final content = cmakeFile.readAsStringSync();
      expect(content, contains('Installation prefix'));
      expect(content, contains('FLUTTER_APP_FLAVOR'));
      expect(content, contains('test_app_\$ENV{APP_FLAVOR}'));
    });

    test('patchRunnerCMake modifies output directories', () {
      final runnerDir = Directory('${tempDir.path}/windows/runner')
        ..createSync(recursive: true);
      final cmakeFile = File('${runnerDir.path}/CMakeLists.txt');
      cmakeFile.writeAsStringSync('''
cmake_minimum_required(VERSION 3.14)
add_executable(\${BINARY_NAME} WIN32
  "main.cpp"
  "runner.exe.manifest"
)
''');

      final patched = patchRunnerCMake(tempDir);
      expect(patched, isTrue);

      final content = cmakeFile.readAsStringSync();
      expect(content, contains('RUNTIME_OUTPUT_DIRECTORY'));
      expect(content, contains('TARGET_FLAVOR'));
    });

    test('generateVSCodeConfigs creates valid JSON configuration files', () {
      generateVSCodeConfigs(tempDir, 'test_app', ['dev', 'prod']);

      final tasksFile = File('${tempDir.path}/.vscode/tasks.json');
      final launchFile = File('${tempDir.path}/.vscode/launch.json');

      expect(tasksFile.existsSync(), isTrue);
      expect(launchFile.existsSync(), isTrue);

      final tasksJson =
          jsonDecode(tasksFile.readAsStringSync()) as Map<String, dynamic>;
      final launchJson =
          jsonDecode(launchFile.readAsStringSync()) as Map<String, dynamic>;

      expect(tasksJson['tasks'], hasLength(2));
      expect(
          launchJson['configurations'], hasLength(3)); // 2 flavors + compound
    });

    test('generateIntelliJConfigs creates expected XML files', () {
      generateIntelliJConfigs(tempDir, 'test_app', ['dev', 'prod']);

      final runDir = Directory('${tempDir.path}/.idea/runConfigurations');
      expect(runDir.existsSync(), isTrue);

      expect(File('${runDir.path}/Windows_dev.xml').existsSync(), isTrue);
      expect(File('${runDir.path}/Windows_prod.xml').existsSync(), isTrue);
      expect(File('${runDir.path}/Ensure_dev_Binary.xml').existsSync(), isTrue);
      expect(
          File('${runDir.path}/Ensure_prod_Binary.xml').existsSync(), isTrue);
      expect(
          File('${runDir.path}/Windows_All_Flavors.xml').existsSync(), isTrue);
    });

    test('run executes full workflow successfully', () {
      // Create minimal Flutter project layout
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('name: my_app\n');
      Directory('${tempDir.path}/windows/runner').createSync(recursive: true);
      File('${tempDir.path}/windows/CMakeLists.txt')
          .writeAsStringSync('set(BINARY_NAME "my_app")\n');
      File('${tempDir.path}/windows/runner/CMakeLists.txt').writeAsStringSync('''
add_executable(\${BINARY_NAME} WIN32
  "runner.exe.manifest"
)
''');

      final out = StringBuffer();
      final err = StringBuffer();

      final code = run(
        ['-f', 'dev,prod'],
        projectDir: tempDir,
        out: out,
        err: err,
      );

      expect(code, equals(0));
      expect(File('${tempDir.path}/scripts/ensure_binary.ps1').existsSync(),
          isTrue);
      expect(File('${tempDir.path}/.vscode/launch.json').existsSync(), isTrue);
      expect(
          File('${tempDir.path}/.idea/runConfigurations/Windows_All_Flavors.xml')
              .existsSync(),
          isTrue);
    });

    test('run returns error exit code when pubspec.yaml is missing', () {
      final out = StringBuffer();
      final err = StringBuffer();

      final code = run([], projectDir: tempDir, out: out, err: err);
      expect(code, equals(1));
      expect(err.toString(),
          contains('Error: Must be run in the root of a Flutter project'));
    });
  });
}
