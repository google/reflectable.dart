import "dart:io";

Uri baseUri = Platform.script.resolve("../../../../../");
String pythonPath;

runAnnotatedStepsInSubdirectory(String subdirectory) async {
  Map<String, String> environment =
      new Map<String, String>.from(Platform.environment);

  List<String> buildernameParts =
  environment["BUILDBOT_BUILDERNAME"].split("-");
  buildernameParts[buildernameParts.length - 1] +=
      Platform.pathSeparator + subdirectory;
  environment["BUILDBOT_BUILDERNAME"] = buildernameParts.join("-");
  String annotatedStepsPath = baseUri.resolve(
      "third_party/package-bots/annotated_steps.py").toFilePath();
  print("^^^^^^^ Running $annotatedStepsPath for $subdirectory");
  
  Process process =
      await Process.start(pythonPath, [annotatedStepsPath], environment: environment);
  stdout.addStream(process.stdout);
  stderr.addStream(process.stderr);
  return process.exitCode;
}

// Expects to be called with the path to a python executable as first argument.
// See .test_config.
main(List<String> arguments) async {
  pythonPath = arguments[0];
  print("^^^^^^^ Running annotated_steps_py in subdirectories");
  List<int> exitCodes = [
    await runAnnotatedStepsInSubdirectory("reflectable"),
    await runAnnotatedStepsInSubdirectory("test_reflectable")
  ];
  print("^^^^^^^ Done annotated_steps_py in subdirectories");
  if (!exitCodes.every((int exitCode) => exitCode == 0)) {
    exit(1);
  }
}