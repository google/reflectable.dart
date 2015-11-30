How to publish a new version:

* Create a fresh git branch on 'master' to perform the publish operation.
* Update `CHANGELOG.md`.
* Update the version number of `pubspec.yaml` in `reflectable`,
  `test_reflectable`, and `coverage_reflectable`.
* Land the change. Commit message: "Bumping version to X.X.X"
* Run `pub publish --dry-run` from `reflectable/`.
* Run `pub publish` from `reflectable/`.
* Run `git tag -a -m'Released as version X.X.X' vX.X.X`.
* Run `git push origin refs/tags/vX.X.X:refs/tags/vX.X.X`

The script '../../tool/publish' will guide you through these steps,
making a few changes to files where the procedure is mechanical, and
announcing that other steps (like editing `CHANGELOG.md`) must be
performed. At the end it prints a list of commands to execute,
including the correct version numbers.
