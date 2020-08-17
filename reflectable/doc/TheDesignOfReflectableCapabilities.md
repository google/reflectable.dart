# The Design of Reflectable Capabilities

This document is intended to give a conceptually based presentation of the
design choices that we have made regarding the class `ReflectCapability`
and its subtypes, which is a set of classes declared in the library
`package:reflectable/capability.dart` in
[package reflectable][package_reflectable]. For a more programming oriented
point of view, please consult the
[library documentation][dartdoc_for_capability].
We use the word **capability** to designate instances of subtypes of class
`ReflectCapability`. This class and its subtypes are used when specifying
the level of support that a client of the package reflectable will get
for reflective operations in a given context, e.g., for instances of a
specific class. We use the word **client** when referring to a library
which is importing and using the package reflectable, or a package
containing such a library. Using one or another capability as
metadata on a class `C` in client code may determine whether or not it is
possible to reflectively `invoke` a method on an instance of `C` via an
`InstanceMirror`. Given that one main reason for having the package
reflectable in the first place is to save space consumed by less frugal
kinds of reflection, the ability to restrict reflection support to the
actual needs is a core point in the design of the package.

It should be noted that the notion of capabilities in this document and
in relation to the package reflectable in general is different from the
capability concept known from
[operating systems research][capabilities_in_OS], which is about
unforgeable tokens of authority (that is, large and secret numbers).
Here, a capability is only concerned with the ability to do something,
not with security.

[package_reflectable]: https://github.com/dart-lang/reflectable
[dartdoc_for_capability]: http://www.dartdocs.org/documentation/reflectable/latest/index.html#reflectable/reflectable-capability
[capabilities_in_OS]: https://en.wikipedia.org/wiki/Capability-based_security

# Context and Design Ideas

To understand the topics covered in this document, we need to briefly
outline how to understand the package reflectable as a whole. Then we
proceed to explain how we partition the universe of possible kinds of
support for reflection, such that we have a set of kinds of reflection to
choose from. Finally we explain how capabilities are used to make a
selection among these choices, and how they can be applied to specific
parts of the client program.

## The Package Reflectable

The package reflectable is an example of support for mirror-based
introspective reflection in object-oriented languages in general, and it
should be understandable as such &#91;1&#93;. More specifically, the
reflection API offered by the package reflectable has been copied
verbatim from the API offered by the package `dart:mirrors`, and then
modified in a few ways. As a result, code using `dart:mirrors` should be
very similar to corresponding code using package reflectable. The
differences that do exist were introduced for two reasons:

* By design, some operations which are declared as top-level functions in
  `dart:mirrors` are declared as methods on the class `Reflectable` in
  the package reflectable, because instances of subclasses thereof, known
  as **reflectors**, are intended to play the role as mirror systems
  &#91;1, or search 'mirror systems' below&#93;, and these operations are
  mirror system specific. For instance, the top-level function `reflect`
  in `dart:mirrors` corresponds to two different methods for two different
  mirror systems (with different semantics, so they cannot be merged).

* Some proposals have been made for changes to the `dart:mirrors` API. We
  took the opportunity to try out an **updated API** by making
  modifications in the signatures of certain methods. For instance,
  `InstanceMirror.invoke` will return the result from the method
  invocation, not an `InstanceMirror` wrapping it. In general, mirror
  operations **return base level values** rather than mirrors thereof in
  the cases where the mirrors are frequently discarded immediately, and
  where it is easy to create the mirror if needed. Mirror class method
  signatures have also been modified in one more way: Where
  `dart:mirrors` methods accept arguments or return results involving
  `Symbol`, package reflectable uses **`String`**. This helps avoiding
  difficulties associated with minification (which is an automated,
  pervasive renaming procedure that is applied to programs mainly in
  order to save space), because `String` values remain unchanged
  throughout compilation.

* New methods have been added to certain mirrors such that the package
  reflectable also provides an **extended API** compared to `dart:mirrors`.
  In particular, variable mirrors and parameter mirrors support the method
  `reflectedType` and method mirrors support `reflectedReturnType`. These
  methods are short hands for method invocation chains (that is, they work
  like `.type.reflectedType` respectively `.returnType.reflectedType`).
  The reason for having them is that the intermediate class mirror need
  not exist, which means that the space consumption can be reduced in
  cases where a substantial number of class mirrors would exist only
  because they would occur as intermediate results during execution of
  those particular method call chains. An added method on reflectors
  is `getInstance`, which returns the canonical reflector for a given
  reflector class; this method is needed in order to enable meta-level
  reflection, where the current program is browsed programmatically in
  order to find a suitable mirror system.

In summary, the vast majority of the API offered by the package
reflectable is identical to the API offered by `dart:mirrors`, and design
documents about that API or about reflection in general &#91;2,3&#93;
will serve to document the underlying ideas and design choices.

## Reflection Capability Design

The obvious novel element in package reflectable is that it allows
clients to specify the level of support for reflection in a new way, by
using capabilities in metadata. This section outlines the semantics of
reflection capabilities, i.e., which kinds of criteria they should be
able to express.

In general, we maintain the property that the specifications of
reflection support with one reflector (that is, inside one mirror-system)
are **monotone**, in the sense that any program having a certain amount
of reflection support will support at least as many
reflective operations if additional specifications are added to the given
reflector. In other words, reflection support specifications can request
additional features, they can never prevent any reflection features from
being supported. As a result, we obtain a modularity law: a programmer
who browses source code and encounters a reflection support specification
`S` somewhere can always trust that the corresponding kind of reflection
support will be present in the program. Other parts of the program may
still add even more reflection support, but they cannot withdraw the
features requested by `S`. Similarly, the specifications are
**idempotent**, that is, multiple specifications requesting the same
feature or overlapping feature sets are harmless, it makes no difference
whether a particular thing has been requested once or several times.

### Mirror API Based Capabilities

The level of support for reflection may in principle be specified in many
ways: there is a plethora of ways to use reflection, and ideally the
client should be able to request support for exactly that which is
needed. In order to drastically simplify this universe of possibilities
and still maintain a useful level of expressive power, we have decided to
use the following stratification as an overall framework for the design:

* The most basic kind of reflection support specification simply
  addresses the API of the mirror classes directly, that is, it is
  concerned with "turning on" support for the use of individual methods
  or small groups of methods in the mirror classes. For instance, it is
  possible to turn on support for `InstanceMirror.invoke` using one
  capability, and another capability will turn on
  `ClassMirror.invoke`. In case a supported method is called it behaves
  like the corresponding method in a corresponding mirror class from
  `dart:mirrors` (except for the adjustments mentioned above, such as
  returning a base value rather than a mirror on it). In case an
  unsupported method is called, an exception is thrown.

* As a refinement of the API based specification, we have chosen to focus
  on the specification of allowable argument values given to specific
  methods in the API. For instance, it is possible to specify a predicate
  which is used to filter existing method names such that
  `InstanceMirror.invoke` is supported for methods whose name satisfies
  that predicate. An example usage could be testing, where reflective
  invocation of all methods whose name ends in `...Test` might be a
  convenient feature, as opposed to the purely static approach where
  someone would have to write a centralized listing of all such methods,
  which could then be used to call them.

With these mechanisms, it is possible to specify support for reflection
in terms of mirrors and the features that they offer, independently of
the actual source code in the client program.

### Reflectee Based Capabilities

Another dimension in the support for reflection is the selection of which
parts of the client program the mirrors will be able to reflect upon,
both when a `ClassMirror` reflects upon one of those classes, and when an
`InstanceMirror` reflects upon one of its instances. In short, this
dimension is concerned with the available selection of reflectees.

The general feature covering this type of specification is
**quantification** over source code elements&mdash;in particular over
classes and other top-level declarations. In this area
we have focused on the mechanisms listed below. Note that `MyReflector`
is assumed to be the name of a subclass of `Reflectable` and
`myReflector` is assumed to be a `const` instance of `MyReflector`,
by canonicalization *the* unique `const` instance thereof. This allows us
to refer to the general concept of a reflector in terms of the example,
`myReflector`, along with its class and similar associated
declarations.

* Reflection support is initiated by invoking one of the methods
  `reflect` or `reflectType` on `myReflector`. We have chosen to omit
  the capability to do `reflect` (in the sense that this is always
  possible) because there is little reason for having reflection at all
  without support for instance mirrors. In contrast, we have chosen to
  have a capability for obtaining class mirrors and similar source code
  oriented mirrors, which also controls the ability to perform
  `reflectType`; this is because having these mirrors may be costly in
  terms of program size, and it may not be needed in some situations.
  Finally, we have chosen to omit the method `reflectClass`, because it
  may be replaced by `reflectType`, followed by `originalDeclaration` when
  `isOriginalDeclaration` is `false`.

* The basic mechanism to get reflection support for a class `C` is to
  attach metadata to it, and this metadata must be a reflector such as
  `myReflector`. The class `Reflectable` has a constructor which is
  `const` and takes a single argument of type `List<ReflectCapability>`
  and another constructor which takes up to ten arguments of type
  `ReflectCapability` (thus avoiding the boilerplate that explicitly
  makes it a list). `MyReflector` must have a single constructor which
  is `const` and takes zero arguments. It is thus enforced that
  `MyReflector` passes the `List<ReflectCapability>` in its constructor
  via a superinitializer, such that every instance of `MyReflector` has
  the same state, "the same capabilities". In summary, this basic
  mechanism will request reflection support for one class, at the level
  specified by the capabilities stored in the metadata.

* The reflection support specification can be non-local, that is, it
  could be placed in a different location in the program than on the
  target class itself. This is needed when there is a need to request
  reflection support for a class in a library that cannot be edited (it
  could be predefined, it could be provided by a third party such that
  modifications incur repeated maintenance after updates, etc.). This
  feature has been known as **side tags** since the beginnings of the
  package reflectable. They must be attached as metadata to an import
  directive for the library `package:reflectable/reflectable.dart`.

* Quantification generalizes the single-class specifications by allowing
  a single specification to specify that the capabilities given as its
  arguments should apply to a set of classes or other program
  elements. It is easy to provide quantification mechanisms, but we do
  not want to pollute the package with a bewildering richness of
  quantification mechanisms, so each of the ones we have should be
  comprehensible and reasonably powerful, and they should not overlap. So
  far, we have focused on the following variants:
    * It should be possible to request reflection support for a set of
      classes chosen via some query mechanism. Obvious candidate
      quantification mechanisms quantify over all superclasses; over all
      supertypes; over all subclasses; over all subtypes of a given class;
      and over all classes whose name matches a given pattern.
    * Quantification as in the previous bullet is centralized because it
      is based on one specification which is then used to 'query' the
      whole program for matching entities. It is common and useful to
      supplement this with a decentralized mechanism, where programmers
      explicitly mark each member of a set, for instance by attaching a
      certain marker as metadata to those members. This makes it possible
      to maintain the set precisely and explicitly, even in the cases
      where the members do not share obvious common traits that fit into
      the centralized 'query' approach. A good example is that a set of
      methods can be given reflective support by annotating them with
      metadata; for instance, we may wish to be able to reflectively
      invoke all methods marked with `@businessRule`.

It is worth noting the flexibility that is enabled by the separation of
the mechanisms for supporting specific methods on mirrors (API related)
and for supporting specific target classes (reflectee related). The
separation comes about because API related support is specified in
reflector classes via capabilities, and reflectee related support is
specified by adding reflectors as metadata to top-level declarations
like classes, and via global quantifiers. In particular, it is possible
to use a reflector which is declared in some third-party package, and then
locally specify which classes that reflector should provide reflection
support for, because there is no need to edit the reflector class itself.

We subscribe to a point of view where reflective operations are divided
into (a) operations concerned with the dynamic behavior of instances, and
(b) operations concerned with the structure of the program; let us call the
former **behavioral operations** and the latter **introspective
operations**. As an example, using `InstanceMirror.invoke` in order to
execute a method on the reflectee is a behavioral operation, whereas it is
an introspective operation to use `ClassMirror.declarations` in order to
investigate the set of members that an instance of the reflected class
would have.

An important consequence of this distinction is that behavioral
operations are concerned with the actual behaviors of objects, which
means that inherited method implementations have the same status as
method implementations declared in the class which is the runtime type of
the reflectee. Conversely, introspective operations are concerned with
source code entities such as declarations, and hence the `declarations`
reported for a given class does *not* include inherited declarations,
they must be found by explicitly iterating over the superclass chain.
Similarly, the introspective point of view includes abstract member
declarations, but they are ignored when using the behavioral point of
view.

Finally, we need to elaborate a little on the notion of mirror systems,
which is a term that we have already used several times. As mentioned
earlier, the 2004 OOPSLA paper by Bracha and Ungar establishes the
conceptual foundation for mirrors and mirror systems &#91;1&#93;.
A **mirror system** is a set of features which provide support for
mirror based reflection in a specialized context, e.g., only for some
classes or methods in a given execution rather than all classes and all
methods, or only for some of the features that mirrors can provide, e.g.,
only for reflective invocation of instance methods and not for static
methods. Typical examples could also be mirror systems tailored for
remote debugging, or for compile-time reflection, but those examples
are less relevant here.

With package reflectable, we need the concept of mirror systems because
it can be useful to use several different mirror systems in the same
program, e.g., when a few classes require extensive reflection support
and a large number of other classes require just a little bit. In that
situation, using a powerful mirror system with the former and a minimalist
one with the latter may be worth the effort, due to the globally improved
resource economy.

Some extra complexity must be expected; e.g., if we can obtain both a
"cheap" and a "powerful" mirror for the same object it will happen via
something like `myCheapReflectable.reflect(o)` respectively
`myPowerfulReflectable.reflect(o)`. It is up to the programmer to avoid
asking the cheap one to do powerful things. In return, the program as a
whole may save a substantial amount of space, compared to the situation
where a single mirror system is used and every class with any need for
reflection must carry the full set of data for the most demanding kind
of reflection done anywhere in that program.

# Specifying Reflection Capabilities

As mentioned in the first section of this document, reflection capabilities
are specified using the subtype hierarchy rooted in the class
**`ReflectCapability`** in `package:reflectable/capability.dart`.
Instances of these classes are used to build something that may well be
considered as abstract syntax trees for a domain specific language. This
section describes how this setup can be used to specify reflection support
using that "domain specific language".

The subtype hierarchy under `ReflectCapability` is sealed, in the sense
that there is a set of subtypes of `ReflectCapability` in that library,
and there should never be any other subtypes of that class, as explained
below.

Being used as `const` values, instances of these classes obviously cannot
have mutable state, but some of them do contain `const` values such as
`String`s or `Type`s. Capabilities do not have methods, except the
ones that they inherit from `Object`. Altogether, this means that
instances of these classes cannot "do anything", but they can be used
to build immutable trees, and the universe of possible trees is fixed
because the set of classes is fixed. This makes the trees similar to
abstract syntax trees, and we can ascribe a semantics to these syntax
trees from the outside. That semantics may be implemented by an
interpreter or a translator. The sealedness of the set of classes
involved is required because an unknown subtype of `ReflectCapability`
would not have a semantics, and interpreters and translators would not
be able to handle them.

In other words, we specify reflection capabilities by building a
representation of an expression in a domain specific language; let
us call that language the **reflectable capability language**. There is a
translator for that language, which is an integrated part of the
implementation of the package reflectable (namely the code generator).

It is obviously possible to have multiple representations of expressions
in this language, and we have considered introducing a traditional,
textual syntax for it. We could have a parser that accepts a `String`,
parses it, and yields an abstract syntax tree consisting of instances of
subtypes of `ReflectCapability`, or reports a syntax error. A
`Reflectable` constructor taking a `String` argument could be provided,
and the `String` could be parsed when needed. This would be a convenient
(but less safe) way for programmers to specify reflection support,
possibly as an alternative to the current approach where the abstract
syntax trees must be specified directly.

However, the textual syntax is used in this document only because it is
concise and easy to read, it has not been (and might never be)
implemented. Hence, actual code using the reflectable capability language
will have to use the more verbose form that directly builds an object
structure representing an abstract syntax tree for that
expression. Example code showing how this is done can be found in the
[package test_reflectable][package_test_reflectable].

[package_test_reflectable]: https://github.com/dart-lang/reflectable/tree/master/test_reflectable

In this document, we will discuss this language in terms of its
grammatical structure, along with an informal semantics of each
construct.

## Specifying Mirror API Based Capabilities

Figure 1 shows the raw material for the elements in one part of the
reflectable capability language grammar. The left side of the figure
contains tokens representing abstract concepts for clustering, and the
right side contains tokens representing each of the methods in the entire
mirror API. A few tokens represent more than one method (for instance,
all of `VariableMirror`, `MethodMirror`, and `TypeVariableMirror` have an
`isStatic` getter, and `metadata` is also defined in two classes), but
they have been merged into one token because those methods play the same
role semantically in all contexts where they occur. In other cases where
the semantics differ (`invoke`, `invokeGetter`, `invokeSetter`, and
`declarations`) there are multiple tokens for each method name,
indicating the enclosing mirror class with a prefix ending in `_`.

| **Strong**                     | **Specialization**             |
| ------------------------------ | ------------------------------ |
| *invocation*                   | `instance_invoke` \| `class_invoke` \| `library_invoke` \| `instance_invokeGetter` \| `class_invokeGetter` \| `library_invokeGetter` \| `instance_invokeSetter` \| `class_invokeSetter` \| `library_invokeSetter` \| `delegate` \| `apply` \| `newInstance` |
| *naming*                       | `simpleName` \| `qualifiedName` \| `constructorName` |
| *classification*               | `isPrivate` \| `isTopLevel` \| `isImport` \| `isExport` \| `isDeferred` \| `isShow` \| `isHide` \| `isOriginalDeclaration` \| `isAbstract` \| `isStatic` \| `isSynthetic` \| `isRegularMethod` \| `isOperator` \| `isGetter` \| `isSetter` \| `isConstructor` \| `isConstConstructor` \| `isGenerativeConstructor` \| `isRedirectingConstructor` \| `isFactoryConstructor` \| `isFinal` \| `isConst` \| `isOptional` \| `isNamed` \| `hasDefaultValue` \| `hasReflectee` \| `hasReflectedType` |
| *annotation*                   | `metadata`                     |
| *typing*                       | `instance_type` \| `variable_type` \| `parameter_type` \| `typeVariables` \| `typeArguments` \| `originalDeclaration` \| `isSubtypeOf` \| `isAssignableTo` \| `superclass` \| `superinterfaces` \| `mixin` \| `isSubclassOf` \| `returnType` \| `upperBound` \| `referent` |
| *concretization*               | `reflectee` \| `reflectedType` |
| *introspection*                | `owner` \| `function` \| `uri` \| `library_declarations` \| `class_declarations` \| `libraryDependencies` \| `sourceLibrary` \| `targetLibrary` \| `prefix` \| `combinators` \| `instanceMembers` \| `staticMembers` \| `parameters` \| `callMethod` \| `defaultValue` |
| *text*                         | `location` \| `source`         |

**Figure 1.** Reflectable capability language API raw material.

Figure 2 shows a reduction of this raw material to a set of capabilities
that we consider reasonable. It does not allow programmers to select
their capabilities with the same degree of detail, but we expect that the
complexity reduction is sufficiently valuable to justify the less
fine-grained control.

We have added *`RegExp`* arguments, specifying that each of these
capabilities can meaningfully apply a pattern matching constraint to
select the methods, getters, etc. which are included. Concretely, this
argument is a `String` which is used as a regular expression. The empty
*`RegExp`* is the default value, which means that all entities in the
relevant category are included when the *`RegExp`* is omitted.

Similarly, we have created variants taking a *`MetadataClass`* argument
which expresses that an entity in the relevant category is included iff
it has been annotated with metadata whose type is a subtype of the given
*`MetadataClass`* (it can be the trivial subtype, i.e., *`MetadataClass`*
itself). That argument is an instance of type `Type` corresponding to
the intended class.

In summary, this provides support for centralized and slightly abstract
selection of entities using regular expressions, and it provides support
for decentralized selection of entities using metadata to explicitly mark
the entities.

It is important to note that the *`MetadataClass`* is potentially
unrelated to the package reflectable: We have the use case where some
class `C` from a package `P` unrelated to reflectable happens to fit
well, because instances of `C` are already attached as metadata to the
relevant set of members. That could in turn be because some other package
requires `C` metadata for some other purpose which is somehow linked to
the need for reflection, e.g., serialization.

| **Non-terminal**               | **Expansion**                  |
| ------------------------------ | ------------------------------ |
| *apiSelection*                 | *invocation* \| *annotation* \| *typing* \| *introspection* |
| *invocation*                   | `instanceInvoke([`*`RegExp`*`])` \| `instanceInvokeMeta(`*`MetadataClass`*`)` \| `staticInvoke([`*`RegExp`*`])` \| `staticInvokeMeta(`*`MetadataClass`*`)` \| `topLevelInvoke([`*`RegExp`*`])` \| `topLevelInvokeMeta(`*`MetadataClass`*`)` \| `newInstance([`*`RegExp`*`])` \| `newInstanceMeta(`*`MetadataClass`*`)` |
| *delegation*                   | `delegate` |
| *annotation*                   | `metadata`                     |
| *typing*                       | `type` \| `typeRelations` |
| *introspection*                | `owner` \| `declarations` \| `uri` \| `libraryDependencies` |

**Figure 2.** Reflectable capability language API grammar tokens.

In the category *invocation* we have used the prefix `topLevel` rather
than `library`, because this terminology is common in the existing
documentation of mirror classes. The category *naming* was eliminated
and support for the corresponding features is always provided,
because the need for disabling these features never arose in practice
and they are cheap to support; the category *classification* was handled
in the same manner, and so was *concretization*. The category *text* was
removed because we do not plan to support reflective access to the
source code as a whole at this point.

We have omitted `apply` and `function` because we do not have support for
`ClosureMirror` and we do not expect to get it anytime soon.

The category *delegation* was separated out from *invocation*, because
support for delegation is rather costly.

The category *typing* was simplified in several ways: `instance_type` was
renamed into `type` because of its prominence. The method `reflectType` on
reflectors is only supported when this capability is present. The
capabilities `variable_type`, `parameter_type`, and `returnType` were
unified into `type` because they are concerned with lookups for the same
kind of mirrors, but the set of classes supported is controlled using
a type annotation quantifier, described below. To give some
control over the level of detail in the type related mirrors,
`typeVariables`, `typeArguments`, `originalDeclaration`, `isSubtypeOf`,
`isAssignableTo`, `superclass`, `superinterfaces`, `mixin`,
`isSubclassOf`, `upperBound`, and `referent` were unified into
`typeRelations`; they all address relations among types, type variables,
and `typedef`s, and it may cause a substantial space overhead to preserve
the associated information if it is never used.

The category *introspection* was also simplified: We unified
`class_declarations`, `library_declarations`, `instanceMembers`,
`staticMembers`, `callMethod`, `parameters`, and `defaultValue` into
`declarations`. Finally we unified the import and export properties into
`libraryDependencies` such that it subsumes `sourceLibrary`,
`targetLibrary`, `prefix`, and `combinators`. We have retained the
`owner` capability separately, because we expect the ability to look up
the enclosing declaration for a given declaration to be too costly to
include implicitly as part of another capability. We have also retained
the `uri` capability separately because the preservation of information
about URIs in JavaScript translated code (which is needed in order to
implement the method uri on a library mirror) has been characterized as a
security problem in some contexts.

Note that certain reflective methods are **non-elementary** in the sense
that they can be implemented entirely based on other reflective methods,
the **elementary** ones. This affects the following capabilities:
`isSubtypeOf`, `isAssignableTo`, `isSubclassOf`, `instanceMembers`, and
`staticMembers`. These methods can be implemented in a general manner, so
they are provided as part of the package reflectable rather than being
generated. Hence, they are supported if and only if the methods they rely
on are supported. This is what it means when we say that `instanceMembers`
has been 'unified into' `declarations`.

### Covering Multiple API Based Capabilities Concisely

In order to avoid overly verbose syntax in the cases where relatively
broad reflection support is requested, we have chosen to introduce some
grouping tokens. They do not contribute anything new, they just offer a
more concise notation for certain selections of capabilities that are
expected to occur together frequently. Figure 3 shows these grouping
tokens. As an aid to remember what this additional syntax means, we have
used words ending in 'ing' to give a hint about the tiny amount of
abstraction involved in grouping several capabilities into a single
construct.

| **Group**                      | **Meaning**                      |
| ------------------------------ | -------------------------------- |
| `invoking([`*`RegExp`*`])`     | `instanceInvoke([`*`RegExp`*`])`, `staticInvoke([`*`RegExp`*`])`, `newInstance([`*`RegExp`*`])` |
| `invokingMeta(`*`MetadataClass`*`)` | `instanceInvokeMeta(`*`MetadataClass`*`)`, `staticInvokeMeta(`*`MetadataClass`*`)`, `newInstanceMeta(`*`MetadataClass`*`>)` |
| `typing`   | `type`, `name`, `classify`, `metadata`, `typeRelations`, `owner`, `declarations`, `uri`, `libraryDependencies` |

**Figure 3.** Grouping tokens for the reflectable capability language.

The semantics of including the capability `invoking(`*`RegExp`*`)` where
*`RegExp`* stands for a given argument is identical to the semantics of
including all three capabilities in the same row on the right hand side
of the figure, giving all of them the same *`RegExp`* as
argument. Similarly, `invoking()` without an argument requests support
for reflective invocation of all instance methods, all static methods,
and all constructors. The semantics of including the capability
`invokingMeta(`*`MetadataClass`*`)` is the same as the semantics of
including all three capabilities to the right in the same row, with the
same argument. Finally, the semantics of including `typing`
is to request support for all the capabilities on the right; that is,
requesting support for every feature associated with information about
the program structure.

### Automatically Obtaining Related Capabilities

We have chosen to use the subtype structure among capabilities to ensure
that there is an automatic relation between some of them. For instance, if
you specify the `declarations` capability then the `type` capability is
automatically also included. The reason for this is that the `declarations`
capability is useless unless there are some class or library mirrors from
which those declarations can be obtained, i.e., there is no situation where
anyone would need the `declarations` capability and not the `type` capability.
The details of this mechanism can be inspected by checking the actual
subtype relationships among the capability classes: If a capability class
`C1` is a subtype of another capability class `C0` then inclusion of `C1`
implies inclusion of `C0`.

## Specifying Reflectee Based Capabilities

In the previous section we found a way to specify mirror API based
capabilities as a grammar. It is very simple, because it consists of
terminals only, apart from the fact that some of these terminals take an
argument that is used to restrict the supported arguments to the matching
names. As shown in Fig. 2, the non-terminal *`apiSelection`* covers them
all. We shall use them several at a time, so the typical usage is a list,
written as *`apiSelection*`*.

In this section we discuss how the reflection support specified by a
given *`apiSelection*`* can be requested for a specific set of program
elements. The program elements that receive reflection support are called
the **targets** of the specification, and the specification itself is given
as a superinitializer in a subclass (call it `MyReflector`) of class
`Reflectable`, with a unique instance (call it `myReflector`). Now,
`myReflector` is used as metadata somewhere in the program, and each
kind of capability is only applicable as an annotation in certain
locations, which is discussed below.

Figure 4 shows how capabilities and annotations can be constructed,
generally starting from an *`apiSelection*`*. The non-terminals in
this part of the grammar have been named after the intended location of
the metadata which is or contains a capability of the corresponding kind.

|**Non-terminals**   | **Expansions**                 |
| ------------------ | ------------------------------ |
| *reflector*        | `Reflectable(`*`targetMetadata`*`)`  |
| *targetMetadata*   | *`apiSelection`* \| `subtypeQuantify` \| `superclassQuantify(`*`upperBound`*`, `*`excludeUpperBound`*`)` \| `typeAnnotationQuantify(`*`transitive`*`)` \| `correspondingSetterQuantify` \| `admitSubtype` |
| *globalMetadata*   | `globalQuantify(`*`RegExp`*`, `*`reflector`*`)` \| `globalQuantifyMeta(`*`MetadataClass`*`, `*`reflector`*`)` |

**Figure 4.** Reflectable capability language target selection.

In practice, a *`reflector`* is an instance of a subclass of class
`Reflectable` that is directly attached to a class as metadata, or passed
to a global quantifier; in the running example terminology it is the object
`myReflector`. The reflector has one piece of state that we model with
*`targetMetadata`*. In the grammar in Fig. 4 we use the identifier
`Reflectable` to stand for all the subclasses, and we model the state by
letting it take the corresponding *`targetMetadata`* as an argument. The
semantics of annotating a class with a given *`reflector`* depends on the
*`targetMetadata`*, as described below.

A *`targetMetadata`* capability can be a base level set of capabilities,
that is, an *`apiSelection*`*, and it can also be a quantifier, possibly
taking an argument for expressing variants. The semantics of attaching
a *`reflector`* containing a plain *`apiSelection*`* to a target class
`C` is that reflection support at the level specified by the given
*`apiSelection*`* is provided for the class `C` and instances thereof.

The semantics of attaching a *`reflector`* containing `subtypeQuantify`
to a class `C` is that the reflection support specified by the
*`apiSelection`* elements given to the same *`reflector`* is provided
for all classes which are subtypes of the class `C`, including `C`
itself, and their instances.

The semantics of attaching a *`reflector`* containing
`superclassQuantify(`*`upperBound`*`, `*`excludeUpperBound`*`)`
to a class `C` is that the reflection support specified by the
*`apiSelection`* elements given to the same *`reflector`* is provided
for all classes (and their instances) which are superclasses of the class
`C`, including `C` itself and stopping at the given *`upperBound`* or
immediately below it if *`excludeUpperBound`* is true. If
*`excludeUpperBound`* is omitted then it is taken to be false, and if
*`upperBound`* is omitted then it is taken to be `Object`.

The set of classes receiving reflection support as specified by a given
*`reflector`* is computed as the least fixed point based on these rules.
For instance, `subtypeQuantify` gives rise to repeated addition of
immediate subtypes of the already included classes until such a state is
reached where this does not add any classes. The fixed point computation
adds subtypes first in one phase, and then it adds superclasses in a second
phase. Note that we would trivially have included all classes (under the
upper bound, and with the default upper bound: all classes at all) when
both quantifiers are present if we had used the opposite order, or if we
had run the fixed point iteration on the two together, so the chosen
ordering is the only meaningful ordering.

If the `declarations` capability is specified then it is possible to
obtain a class mirror and then look up the variable mirrors for its
fields and the method mirrors for its methods, getters, and setters
(using the `declarations`, `instanceMembers`, or `staticMembers`
methods on the class mirror). With those mirrors it is in turn
possible to look up further class mirrors, such as the mirrors of
the types of the parameters of the given method mirrors, and that
procedure could be repeated any number of times. This means that a
naively provided support for all reachable class mirrors would easily
cause all classes in a program to be included, even though this may
not be a good choice. Because of this, we have chosen to *omit* all
the class mirrors for the type annotations of declarations by default.
If those class mirrors should indeed be included then they must be
requested explicitly. This is done using the `typeAnnotationQuantify`
capability.

The semantics of attaching a *`reflector`* containing
`typeAnnotationQuantify(`*`transient`*`)` to a class `C` is that the
set of included class mirrors will be enhanced with all the classes
used as type annotations in included members. That is, the set of
already included classes is traversed, each of the included members
of those classes is inspected (a method, say, is included if it
matches the given *`RegExp`* or carries the given type of metadata,
if the corresponding capability takes such an argument). For each
parameter as well as the return value of that method, any given type
annotation which is a class is added to the set of included classes.
This process runs just once if *`transient`* is false or omitted, and
it runs until no more classes are added if *`transient`* is true.

The extension of the set of covered classes based on type annotations,
whether it is a single step or a fixed point iteration, takes place
in a third phase, after the subtype and superclass fixed point
iterations.

The semantics of attaching a *`reflector`* containing `admitSubtype`
to a class `C` is subtle enough to warrant a slightly more detailed
discussion, given in the next section. The basic idea is that it allows
instances of subtypes of the target class to be treated as if they were
instances of the target class.

Finally, we support "side tags" using global quantifiers,
`globalQuantify(`*`RegExp`*`, `*`reflector`*`)` and
`globalQuantifyMeta(`*`MetadataClass`*`, `*`reflector`*`)`. Currently, we have
decided that they must be attached as metadata to an import statement
importing `package:reflectable/reflectable.dart`, but we may relax this
restriction if other placements turn out to be helpful in practice. Due
to the monotone semantics of capabilities it is not a problem if a given
program contains more than one such *`globalMetadata`*, the provided
reflection support will simply be the least one that satisfies all
requests.

The semantics of having `globalQuantify(`*`RegExp`*`, `*`reflector`*`)` in a
program is identical to the semantics of having the given *`reflector`*
attached directly to each of those classes in the program whose qualified
name matches the given *`RegExp`*. Similarly, the semantics of having
`globalQuantifyMeta(`*`MetadataClass`*`, `*`reflector`*`)` in a program is
identical to the semantics of having the given *`reflector`* attached
directly to each of those classes whose metadata includes an instance of
type *`MetadataClass`* or a subtype thereof.

### Included Members and No Such Method

In general, coverage is based on a bottom-up semantics: With a given set
of capabilities, the set of covered classes and the set of covered
members inside them is computed as a query over the given program. This
is a bottom-up semantics because it sets out from the empty coverage and
then extends the coverage with concrete elements that do exist in your
program.

Consider a member in a covered class. If it does *not match* the coverage
criteria (its name does not match a given regular expression and it does
not have any of the requested types of metadata), it has the *same status
as* a class name or member name for which there does *not exist* any
declaration at all. When invoking methods with a given actual list `L` of
arguments, the method is considered to be non-existing even if there is a
declaration of a method with the specified name, if its formal parameter
list does not admit an invocation using `L` as the actual arguments. For
instance, even if `void foo(int i)` exists, it is a no-such-method event
if we encounter the invocation `foo(0, bar: true)`.

The crucial difference between this semantics and the semantics
associated with no-such-method events for a native Dart invocation is
that the method in question may be missing entirely, or it may be denied
coverage, because the given capabilities are too strict. Hence, in order
to enable programmers to handle the no-such-method situations properly
for a reflectable invocation, we treat these situations differently from
the way a native no-such-method situation is treated. Whereas a native
invocation failure causes `noSuchMethod` to be invoked on the same
receiver with an `Invocation` argument that describes the selector and
the arguments, the reflectable invocation failure causes a
`ReflectableNoSuchMethodError` to be thrown. This type of exception
contains a `StringInvocation` which specifies the same information about
the invocation as an `Invocation`, except that its `memberName` is a
string rather than a symbol. Programmers may catch this invocation and
react in whatever way is appropriate in the context, e.g., by calling
their own variant of `noSuchMethod`.

### Completely or Partially Mirrored Instances?

Traditionally, it is assumed that reflective access to an instance, a
class, or some other entity will provide a complete and faithful view of
that entity. For instance, it should be possible for reflective code to
access features declared as private even when that reflective code is
located in a context where non-reflective access to the same features
would not be allowed. Moreover, when a reflective lookup is used to learn
which class a given object is an instance of, it is expected that the
response describes the actual runtime type of the object, and not some
superclass such as the statically known type of that object in some
context.

In the package reflectable there are reasons for violating this
completeness assumption, and some of them are built-in consequences of
the reasons for having this package in the first place. In other words,
these restrictions will not go away entirely. Other restrictions may be
lifted in the future, because they were introduced based on certain
trade-offs made in the implementation of the package.

The main motivation for providing the package reflectable is that the more
general support for reflection provided by the `dart:mirrors` package tends
to be too costly at run time in terms of program size, or maybe the
resource implications of having `dart:mirrors` are such that the support
for `dart:mirrors` has been omitted entirely. Hence, it is a core point for
package reflectable to specify a restricted version of reflection that fits
the purposes of a given program, such that it can be done using a
significantly smaller amount of space. Consequently, it will be perfectly
normal for such a program to have reflective support for an object without
reflective access to, say, some of its methods. There are several other
kinds of coverage which is incomplete by design, and they are not a
problem: they are part of the reason for using package reflectable in the
first place.

The following subsections discuss two different situations where some
restrictions apply that are not there by design. We first discuss cases
where access to private features is incomplete, and then we discuss the
consequences of admitting subtypes as specified with
`admitSubtype(`*`apiSelection*`*`)`.

#### Privacy Related Restrictions

The restrictions discussed in this subsection are motivated by trade-offs
in the implementation in package reflectable, so we need to mention some
implementation details. The package reflectable has been designed for code
generation. The code generator receives a program (which is using package
reflectable) as input, and generates code which provides support for the
requested reflective features, using a "database" of mirror creation
expressions and consulting that database at run time, all implemented using
ordinary, non-reflective code.

Ordinary code cannot violate privacy restrictions. Hence, the reflective
operations provided by package reflectable cannot, say, read or write a
private field in a library which is different from the one that contains
the relevant generated code. But the current code generation approach
always and only generates one new library which contains all the generated
code; this means that no private declaration at all in the program can be
reached from generated code, not even the ones in the current package.

It would in principle be possible to modify all the libraries in the
current package itself, but even though this could be used to get access to
the private declarations locally, it would still leave all private
declarations in imported packages out of reach. However, this would only
help in the cases where a solution is not so desparately needed: Libraries
in the local package could normally just be edited, adding a suitable
public declaration in order to give some kind of access to the member which
is otherwise inaccessible.

There are a couple of exceptions: Mirrors for private classes can be
obtained from a mirror on the enclosing library, and private classes in
superclass chains are preserved, such that it will work to iterate over all
superclasses if superclass quantification has been requested.  But these
private classes do not support invocation of static methods, and they do
not support getting a mirror on their instances.

#### Considerations around Admitting Subtypes

When a *`targetMetadata`* on the form *`apiSelection`*&#42; is attached
to a given class `C`, the effect is that reflection support is provided
for the class `C` and for instances of `C`. However, that support can be
extended to give partial reflection support for instances of subtypes of
`C` in a way that does not incur further costs in terms of program size:
A mirror generated for instances of class `C` can have a `reflectee` (the
object being mirrored by that mirror) whose type is a proper subtype of
`C`. A *`targetMetadata`* on the form
`admitSubtype(`*`apiSelection`*&#42;`)` is used to specify exactly this:
It enables an instance mirror to hold a reflectee which is an instance of
a proper subtype of the type that the mirror was generated for.

The question arises which instance mirror to use for a given object *O*
with runtime type `D` which is given as an argument to the operation
`reflect` on a reflector, when there is no mirror class which was created
for exactly `D`. This is the situation where a subtype reflectee is
actually admitted. In general, there may be multiple candidate mirror
classes corresponding to classes `C1, C2, .. Ck` which are "least
supertypes of `D`" in the sense that no type `E` is a proper supertype of
`D` and a proper subtype of `Ci` for any `i` (this also implies that no
two classes `Ci` and `Cj` are subtypes of each other).  The language
specification includes an algorithm which will find a uniquely determined
supertype of `C1 .. Ck` which is called their **least upper bound**. We
cannot use this algorithm directly because we have an arbitrary subset of
the types in a type hierarchy rather than all types, and then we need to
make a similar decision for this "sparse" subtype hierarchy that only
includes classes with reflection support from the given reflector.
Nevertheless, we expect that it is possible to create a variant of the
least upper bound algorithm which will work for these sparse subtype
hierarchies.

It should be noted that a very basic invariant which is commonly assumed
for reflection support in various languages is violated: An instance
mirror constructed for type `C` can have a reflectee which is an instance
of a proper subtype `D`. Of course, not all mirror systems have anything
like the notion of a mirror that is constructed for a given type, but the
corresponding problem is relevant everywhere: The mirror will not report
on the properties of the object as-is, it will report on the properties
of instances of a supertype. This is a kind of incompleteness, and it
even causes the mirror to give plain *incorrect* descriptions of the
object in some cases.

In particular, assume that an object *O* with runtime type `D` is given,
and that we have an instance mirror *IM* whose reflectee is *O*. Assume
that the class of *IM* was generated for instances of a class `C`, which
is a proper supertype of `D`. It is only because of `admitSubtype` that
it is even possible for *IM* to have a `reflectee` whose `runtimeType` is
not `C`. In many situations this discrepancy makes no difference and *IM*
works fine with *O*, but it is informative to focus on a case where it
really matters:

<!-- Cannot make 'IM' italic in 'IM.type', hence using a rather messy -->
<!-- mixed notation. -->

Let us use a reflective operation on *IM* to get a class mirror for the
class of *O*. *IM*.`type` will return an instance *CM* of the class mirror
for `C`, not a class mirror for *O*'s actual runtime type `D`. If a
programmer uses this approach to look up the name of the class of an
object like *O*, the answer will simply be wrong, it says `"C"` and it
should have said `"D"`. Similarly, if we traverse the superclasses we
will never see the class `D`, nor the intermediate classes between `D`
and `C`. A real-world example is serialization: if we look up the
declarations of fields in order to serialize the reflectee then we will
silently fail to include the fields declared in the ignored subclasses
down to `D`. In general, there are many unpleasant surprises waiting for
the naive user of this feature, so it should be considered to be an
expert-only option.

Why not just do the "right thing" and return a class mirror for `D`? It is
not possible to simply check the `runtimeType` of `reflectee` in the
implementation of the method type, and then deliver a class mirror of `D`
because, typically, there *is* no class mirror for `D`. In fact, the whole
point of having the `admitSubtype` quantifier is that it saves space
because a potentially large number of subtypes of a given type can be
given partial reflection support without the need to generate a
correspondingly large number of mirror classes.

To further clarify what it means to get 'partial' reflective support,
consider some cases:

Reflectively calling instance methods on *O* which are declared in `C` or
inherited into `C` will work as expected, and standard object-oriented
method invocation will ensure that it is the correct method implementation
for *O* which is called, and that might be the implementation which is
available in `C` or it might be an implementation in a proper subtype of
`C`.

Calling instance methods on *O* which are declared in a proper subtype of
`C`, including methods from `D` itself, will not work. This is because
the class of *IM* has been generated under the assumption that no such
methods exist, it only knows about `C` methods. As mentioned, if we fetch
the class of *O* we may get a proper supertype of the actual class of
*O*, and hence all the derived operations will be similarly affected. For
instance, the declarations from *CM* will be the declarations in `C`, and
they have nothing to do with the declarations in `D`. Similarly, if we
traverse the superclasses then we will only see a strict suffix of the
actual list of superclasses of the class of *O*.

Based on these serious issues, we have decided that when an instance
mirror is associated with the `admitSubtype` quantifier, it is a run-time
error to execute the `type` method in order to obtain a mirror of a
class, because it is very unlikely to work as intended when that class is
in fact not the class of the reflectee. Similarly, `declarations` is not
supported in this situation. It would be possible to allow it in the
cases where the match happens to be perfect (`C == D`), but this would
be difficult for programmers to use, and they may as well use
`reflectType(C)` directly if they want to reflect upon a class which is
not taken directly from an instance.

In summary, there is a delicate trade-off to make in the case where an
entire subtype hierarchy should be equipped with reflection support. The
trade off is to either pay the price in terms of program size and get full
support (using `subtypeQuantify`); or to save space aggressively and in
return tolerate the partial support for reflection (using `admitSubtype`).

# Summary

We have described the design of the capabilities used in the package
reflectable to specify the desired level of support for reflection. The
underlying idea is that the capabilities at the base level specify a
selection of operations from the API of the mirror classes, along with some
simple restrictions on the allowable arguments to those operations.  On top
of that, the API based capabilities can be associated with specific parts
of the target program (though at this point only classes) such that exactly
those classes will have the reflection support specified with the API based
capabilities. The target classes can be selected individually, by adding a
reflector as metadata on each target class. Alternatively, target classes
can be selected by quantification: For instance, it is possible to quantify
over all subtypes, in which case not only the class `C` that holds the
metadata receives reflection support, but also all subtypes of `C`.
Finally, it is possible to admit instances of subtypes as reflectees of a
small set of mirrors, such that partial reflection support is achieved for
many classes, without the cost of having many mirror classes.

# References

 1. Gilad Bracha and David Ungar. "Mirrors: design principles for
    meta-level facilities of object-oriented programming languages".  ACM
    SIGPLAN Notices. 24 Oct. 2004: 331-344.
 2. Brian Cantwell Smith. "Procedural reflection in programming
    languages." 1982.
 3. Jonathan M. Sobel and Daniel P. Friedman. "An introduction to
    reflection-oriented programming."  Proceedings of Reflection.
    Apr. 1996.
