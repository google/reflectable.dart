/// Creates a symlink to the reflectable package next to this package.
import "dart:io";

void main(List<String> args) {
  String projectRoot = args[0];
  // If projectRoot is relative we want to make it absolute, so the link
  // will be to an absolute location.
  Uri currentPathUri = new Uri.file(Directory.current.path +
                                    Platform.pathSeparator);
  Uri projectRootUri = currentPathUri.resolve(projectRoot);
  Uri reflectableLocation = projectRootUri.resolve(
      "../../../../../dart/third_party/pkg/reflectable/reflectable");
  Uri destination = projectRootUri.resolve("../reflectable/reflectable");
  print("Making a link to ${reflectableLocation.toFilePath()} "
        "at ${destination.toFilePath()}");
  new Link.fromUri(destination).create(reflectableLocation.toFilePath());
}
