How to publish a new version:

* Update the version number in `reflectable/pubspec.yaml` and
  `test_reflectable/pubspec.yaml`.
* Update `CHANGELOG.md`.
* Land the change. Commit message: "Bumping version to X.X.X"
* Run `pub publish --dry-run` from `reflectable/`.
* Run `pub publish` from `reflectable/`.
