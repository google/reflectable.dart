coverage_reflectable
----------------

This package contains code that enables coverage measurements on the 
reflectable transformer by running `pub build --mode=debug test` in
'test_reflectable', and gathering data using the 'observatory'.

The script `bin/unexecuted_lines` will perform the steps needed. It must be
executed with `bin` as the current working directory.

It will gather the coverage information and print a summary, listing
each library where there are any lines with executable code that have not
been executed, followed by a list of line numbers of the unexecuted lines.

Note that there are no measurements, at this point, addressing the execution
of code using reflectable. The coverage measurements are only concerned with
the transformation process.
