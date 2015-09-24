How to publish a new version:

* Create a fresh git branch on 'master' to perform the publish operation.
* Update `CHANGELOG.md`.
* Update the version number in `reflectable/pubspec.yaml` and
  `test_reflectable/pubspec.yaml`.
* Land the change. Commit message: "Bumping version to X.X.X"
* Run `pub publish --dry-run` from `reflectable/`.
* Run `pub publish` from `reflectable/`.
* Run `git tag -a -m'Released as version X.X.X' vX.X.X`.
* Run `git push origin refs/tags/vX.X.X:refs/tags/vX.X.X`

The script '../../tool/publish' will perform these steps; one way
to run it is with option `--dry-run`, which will perform the local
steps and only print the commands for the steps that involve the
remote repository. Those commands may then be double-checked, copied
to the command line, and executed. Without `--dry-run` the remote
commands will be executed by the script, but the user must press
[ENTER] before each "dangerous" step (or ^C to bail out).
