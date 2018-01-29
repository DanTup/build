// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:io/io.dart';
import 'package:meta/meta.dart';
import 'package:shelf/shelf_io.dart';

import 'package:build_runner/build_runner.dart';

const _assumeTty = 'assume-tty';
const _deleteFilesByDefault = 'delete-conflicting-outputs';
const _lowResourcesMode = 'low-resources-mode';
const _failOnSevere = 'fail-on-severe';
const _hostname = 'hostname';
const _output = 'output';
const _config = 'config';
const _verbose = 'verbose';

final _pubBinary = Platform.isWindows ? 'pub.bat' : 'pub';

/// Unified command runner for all build_runner commands.
class BuildCommandRunner extends CommandRunner<int> {
  final List<BuilderApplication> builderApplications;

  BuildCommandRunner(List<BuilderApplication> builderApplications)
      : this.builderApplications = new List.unmodifiable(builderApplications),
        super('build_runner', 'Unified interface for running Dart builds.') {
    addCommand(new _BuildCommand());
    addCommand(new _WatchCommand());
    addCommand(new _ServeCommand());
    addCommand(new _TestCommand());
  }
}

/// Base options that are shared among all commands.
class _SharedOptions {
  /// Skip the `stdioType()` check and assume the output is going to a terminal
  /// and that we can accept input on stdin.
  final bool assumeTty;

  /// By default, the user will be prompted to delete any files which already
  /// exist but were not generated by this specific build script.
  ///
  /// This option can be set to `true` to skip this prompt.
  final bool deleteFilesByDefault;

  /// Any log of type `SEVERE` should fail the current build.
  final bool failOnSevere;

  final bool enableLowResourcesMode;

  /// Read `build.$configKey.yaml` instead of `build.yaml`.
  final String configKey;

  /// Path to the merged output directory, or null if no directory should be
  /// created.
  final String outputDir;

  final bool verbose;

  _SharedOptions._({
    @required this.assumeTty,
    @required this.deleteFilesByDefault,
    @required this.failOnSevere,
    @required this.enableLowResourcesMode,
    @required this.configKey,
    @required this.outputDir,
    @required this.verbose,
  });

  factory _SharedOptions.fromParsedArgs(ArgResults argResults) {
    return new _SharedOptions._(
      assumeTty: argResults[_assumeTty] as bool,
      deleteFilesByDefault: argResults[_deleteFilesByDefault] as bool,
      failOnSevere: argResults[_failOnSevere] as bool,
      enableLowResourcesMode: argResults[_lowResourcesMode] as bool,
      configKey: argResults[_config] as String,
      outputDir: argResults[_output] as String,
      verbose: argResults[_verbose] as bool,
    );
  }
}

/// Options specific to the [_ServeCommand].
class _ServeOptions extends _SharedOptions {
  final String hostName;
  final List<_ServeTarget> serveTargets;

  _ServeOptions._({
    @required this.hostName,
    @required this.serveTargets,
    @required bool assumeTty,
    @required bool deleteFilesByDefault,
    @required bool failOnSevere,
    @required bool enableLowResourcesMode,
    @required String configKey,
    @required String outputDir,
    @required bool verbose,
  })
      : super._(
          assumeTty: assumeTty,
          deleteFilesByDefault: deleteFilesByDefault,
          failOnSevere: failOnSevere,
          enableLowResourcesMode: enableLowResourcesMode,
          configKey: configKey,
          outputDir: outputDir,
          verbose: verbose,
        );

  factory _ServeOptions.fromParsedArgs(ArgResults argResults) {
    var serveTargets = <_ServeTarget>[];
    for (var arg in argResults.rest) {
      var parts = arg.split(':');
      var path = parts.first;
      var port = parts.length == 2 ? int.parse(parts[1]) : 8080;
      serveTargets.add(new _ServeTarget(path, port));
    }
    if (serveTargets.isEmpty) {
      serveTargets.addAll([
        new _ServeTarget('web', 8080),
        new _ServeTarget('test', 8081),
      ]);
    }
    return new _ServeOptions._(
      hostName: argResults[_hostname] as String,
      serveTargets: serveTargets,
      assumeTty: argResults[_assumeTty] as bool,
      deleteFilesByDefault: argResults[_deleteFilesByDefault] as bool,
      failOnSevere: argResults[_failOnSevere] as bool,
      enableLowResourcesMode: argResults[_lowResourcesMode] as bool,
      configKey: argResults[_config] as String,
      outputDir: argResults[_output] as String,
      verbose: argResults[_verbose] as bool,
    );
  }
}

/// A target to serve, representing a directory and a port.
class _ServeTarget {
  final String dir;
  final int port;

  _ServeTarget(this.dir, this.port);
}

abstract class BuildRunnerCommand extends Command<int> {
  List<BuilderApplication> get builderApplications =>
      (runner as BuildCommandRunner).builderApplications;

  BuildRunnerCommand() {
    _addBaseFlags();
  }

  void _addBaseFlags() {
    argParser
      ..addFlag(_assumeTty,
          help: 'Enables colors and interactive input when the script does not'
              ' appear to be running directly in a terminal, for instance when it'
              ' is a subprocess',
          negatable: true)
      ..addFlag(_deleteFilesByDefault,
          help:
              'By default, the user will be prompted to delete any files which '
              'already exist but were not known to be generated by this '
              'specific build script.\n\n'
              'Enabling this option skips the prompt and deletes the files. '
              'This should typically be used in continues integration servers '
              'and tests, but not otherwise.',
          negatable: false,
          defaultsTo: false)
      ..addFlag(_lowResourcesMode,
          help: 'Reduce the amount of memory consumed by the build process. '
              'This will slow down builds but allow them to progress in '
              'resource constrained environments.',
          negatable: false,
          defaultsTo: false)
      ..addOption(_config,
          help: 'Read `build.<name>.yaml` instead of the default `build.yaml`',
          abbr: 'c')
      ..addFlag(_failOnSevere,
          help: 'Whether to consider the build a failure on an error logged.',
          negatable: true,
          defaultsTo: false)
      ..addOption(_output,
          help: 'A directory to write the result of a build to.', abbr: 'o')
      ..addFlag('verbose',
          abbr: 'v',
          defaultsTo: false,
          negatable: false,
          help: 'Enables verbose logging.');
  }

  /// Must be called inside [run] so that [argResults] is non-null.
  ///
  /// You may override this to return more specific options if desired, but they
  /// must extend [_SharedOptions].
  _SharedOptions _readOptions() =>
      new _SharedOptions.fromParsedArgs(argResults);
}

/// A [Command] that does a single build and then exits.
class _BuildCommand extends BuildRunnerCommand {
  @override
  String get name => 'build';

  @override
  String get description =>
      'Performs a single build on the specified targets and then exits.';

  @override
  Future<int> run() async {
    var options = _readOptions();
    var result = await build(builderApplications,
        deleteFilesByDefault: options.deleteFilesByDefault,
        enableLowResourcesMode: options.enableLowResourcesMode,
        failOnSevere: options.failOnSevere,
        configKey: options.configKey,
        assumeTty: options.assumeTty,
        outputDir: options.outputDir,
        verbose: options.verbose);
    if (result.status == BuildStatus.success) {
      return ExitCode.success.code;
    } else {
      return 1;
    }
  }
}

/// A [Command] that watches the file system for updates and rebuilds as
/// appropriate.
class _WatchCommand extends BuildRunnerCommand {
  @override
  String get name => 'watch';

  @override
  String get description =>
      'Builds the specified targets, watching the file system for updates and '
      'rebuilding as appropriate.';

  @override
  Future<int> run() async {
    var options = _readOptions();
    var handler = await watch(builderApplications,
        deleteFilesByDefault: options.deleteFilesByDefault,
        enableLowResourcesMode: options.enableLowResourcesMode,
        failOnSevere: options.failOnSevere,
        configKey: options.configKey,
        assumeTty: options.assumeTty,
        outputDir: options.outputDir,
        verbose: options.verbose);
    await handler.currentBuild;
    await handler.buildResults.drain();
    return ExitCode.success.code;
  }
}

/// Extends [_WatchCommand] with dev server functionality.
class _ServeCommand extends _WatchCommand {
  _ServeCommand() {
    argParser
      ..addOption(_hostname,
          help: 'Specify the hostname to serve on', defaultsTo: 'localhost');
  }

  @override
  String get name => 'serve';

  @override
  String get description =>
      'Runs a development server that serves the specified targets and runs '
      'builds based on file system updates.';

  @override
  _ServeOptions _readOptions() => new _ServeOptions.fromParsedArgs(argResults);

  @override
  Future<int> run() async {
    var options = _readOptions();
    var handler = await watch(builderApplications,
        deleteFilesByDefault: options.deleteFilesByDefault,
        enableLowResourcesMode: options.enableLowResourcesMode,
        failOnSevere: options.failOnSevere,
        configKey: options.configKey,
        assumeTty: options.assumeTty,
        outputDir: options.outputDir,
        verbose: options.verbose);
    var servers = await Future.wait(options.serveTargets.map((target) =>
        serve(handler.handlerFor(target.dir), options.hostName, target.port)));
    await handler.currentBuild;
    for (var target in options.serveTargets) {
      stdout.writeln('Serving `${target.dir}` on port ${target.port}');
    }
    await handler.buildResults.drain();
    await Future.wait(servers.map((server) => server.close()));

    return ExitCode.success.code;
  }
}

/// A [Command] that does a single build and then runs tests using the compiled
/// assets.
class _TestCommand extends BuildRunnerCommand {
  @override
  final argParser = new ArgParser(allowTrailingOptions: false);

  @override
  String get name => 'test';

  @override
  String get description =>
      'Performs a single build on the specified targets and then runs tests '
      'using the compiled assets.';

  @override
  Future<int> run() async {
    _SharedOptions options;
    String outputDir;
    try {
      var packageGraph = new PackageGraph.forThisPackage();
      _ensureBuildTestDependency(packageGraph);
      options = _readOptions();
      // We always need an output dir when running tests, so we create a tmp dir
      // if the user didn't specify one.
      outputDir = options.outputDir ??
          Directory.systemTemp
              .createTempSync('build_runner_test')
              .absolute
              .uri
              .toFilePath();
      var result = await build(builderApplications,
          deleteFilesByDefault: options.deleteFilesByDefault,
          enableLowResourcesMode: options.enableLowResourcesMode,
          failOnSevere: options.failOnSevere,
          configKey: options.configKey,
          assumeTty: options.assumeTty,
          outputDir: outputDir,
          verbose: options.verbose,
          packageGraph: packageGraph);

      if (result.status == BuildStatus.failure) {
        stdout.writeln('Skipping tests due to build failure');
        return 1;
      }

      var testExitCode = await _runTests(outputDir);
      if (testExitCode != 0) {
        // No need to log - should see failed tests in the console.
        exitCode = testExitCode;
      }
      return testExitCode;
    } finally {
      // Clean up the output dir if one wasn't explicitly asked for.
      if (options.outputDir == null && outputDir != null) {
        await new Directory(outputDir).delete(recursive: true);
      }

      await ProcessManager.terminateStdIn();
    }
  }

  /// Runs tests using [precompiledPath] as the precompiled test directory.
  Future<int> _runTests(String precompiledPath) async {
    stdout.writeln('Running tests...\n');
    var extraTestArgs = argResults.rest;
    var testProcess = await new ProcessManager().spawn(
        _pubBinary,
        [
          'run',
          'test',
          '--precompiled',
          precompiledPath,
        ]..addAll(extraTestArgs));
    return testProcess.exitCode;
  }
}

void _ensureBuildTestDependency(PackageGraph packageGraph) {
  if (packageGraph.allPackages['build_test'] == null) {
    throw new StateError('''
Missing dev dependecy on package:build_test, which is required to run tests.

Please update your dev_dependencies section of your pubspec.yaml:

  dev_dependencies:
    build_runner: any
    build_test: any
    # If you need to run web tests, you will also need this dependency.
    build_web_compilers: any
''');
  }
}
