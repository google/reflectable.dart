# Testing package reflectable

In order to faithfully play the role as a client of package
reflectable including its code generation facility, test
files have been placed in a separate repository,
`https://github.com/dart-lang/test_reflectable`. It may then
have its own build.yaml and use reflectable "from the
outside", just like any other client of reflectable.

