# TODO Management

This file documents our conventions regarding `TODO` comments in the
source code of this package.

## TODO Comment Format

TODO comments are initiated by text on the following format:
`TODO(<id>) <category>:`. Here, `<id>` is either an LDAPs of
a person who is expected to be in the best position to resolve
that particular issue, or a reference to an issue on the form
`#<number>` which currently blocks the solution. Finally,
`<category>` is one of several categories of TODO tasks which
are described below.

Note that the `TODO(<id>)` format follows the standard used in
Google code for Java, C++, Python, R, and possibly others (which
allows but does not require a final colon), whereas ` <category>:`
is a local extension for this package.

## TODO Categories

The categories are intended to help understanding the nature of each TODO
and the status of the package as a whole; they may help organizing the
elimination of TODO related tasks, e.g., by separating bug fixes from
potential future enhancements. We use the following categories:

 * `doc`: A piece of documentation needs improvement.
 * `feature`: A client-visible feature needs to be implemented or debugged.
 * `implement`: A non-client-visible implementation effort is needed.
 * `algorithm`: An algorithm needs to be improved.
 * `diagnostic`: A diagnostic message is missing, wrong, or spurious.
 * `clarify`: clarify the given issue, thus preparing some action.
 * `future`: The issue described could be addressed in the future.

The script `grep_todos` can be used to find or count TODOs in each or
all categories, and it can be used to find TODOs whose category is missing
or unknown.

NB: Please note that an update to the set of categories above must be
accompanied by a corresponding update to the script `grep_todos`.
