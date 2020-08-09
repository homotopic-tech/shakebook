# Changelog for Shakebook

## (v0.12.0.0)

* Standardize top level strategy for supplying template values as follows:
  * Pick an oracle that returns a composite.
  * Pick a template.
  * Pick a formatting strategy.

## (v0.11.0.0)

* Introduce [composite-aeson](https://hackage.haskell.org/package/composite-aeson) for supplying and formatting template values.

## (v0.10.0.0)

* Add [lucid](https://hackage.haskell.org/package/lucid).
* Add [lucid-cdn](https://hackage.haskell.org/package/lucid-cdn).
* Add `withCdnImports` to `Shakebook.Conventions`.
* Add `defaultCdnImports` to `Shakebook.Defaults`.

## (v0.9.1.0)

* Add [ixset-typed-conversions](https://hackage.haskell.org/package/ixset-typed-conversions) for producing `Zipper`s and `HashMap`s.

## (v0.9.0.0)

* Upgrade shake-plus to v0.2.0.0.
* Change `readmarkdownFile` to use `FileLike`.
* Add `readMediaWikiFile` and `readLaTeXFile`.

## (v0.8.1.0)

* Update pandoc to v2.10.
* Strengthen aeson bound to v1.5.2.0.

## (v0.7.4.0)

* Strengthen bounds on `aeson`, `ixset-typed` and `shake-plus`.
* Add [binary-instances](https://hackage.haskell.org/package/sitemap-gen) for `Value` binary instance.
* Add [http-conduit](https://hackage.haskell.org/package/http-conduit).
* Add new module `Shakebook.Conduit` containing `addRemoteJSONOracleCache` and `RemoteJSONCache` data
  type for remote JSON caching.

## (v0.7.3.0)

* Add `Shakebook.Sitemap` module using [sitemap-gen](https://hackage.haskell.org/package/sitemap-gen).
* Relax bounds on `aeson`.

## (v0.7.2.0)

* Upgrade to [aeson-with](https://hackage.haskell.org/package/aeson-with) v0.1.1.0.

## (v0.7.1.0)

* Upgrade to [zipper-extra](https://hackage.haskell.org/package/zipper-extra) v0.1.3.0.
* Add `postZipper` for creating a `Zipper` from an `IxSet` of Posts.

## (v0.7.0.0)

* Switch to [ixset-typed](httos://hackage.haskell.org/package/ixset-typed).
* Drop `Shakebook.Data` module and move to `Shakebook.Pandoc` and `Shakebook.Conventions`.
* Add `postIndex` function.

## (v0.6.0.0)

* Drop `Display` instances for `Within` and `Path`.
* Introduce [ixset](https://hackage.haskell.org/package/ixset).

## (v0.5.1.0)

* Add `tagIndex` and `monthIndex` instead of filter and partition functions.
* Drop `hashable-time` dependency.

## (v0.5.0.0)

* Upgrade to [shake-plus](https://hackage.haskell.org/package/shake-plus) v0.1.6.0.
* Drop `enrichFullUrl`, `enrichUrl` and `enrichSupposedUrl`.
* Drop `immediateShoots`.
* Drop dependency on `extra`.
* Remove `withXExtension` function and Depend on new library [path-extensions](https://hackage.haskell.org/package/path-extensions).
* Re-export `Development.Shake.Plus` and `Data.Aeson`
* Re-expot most `Shakebook` submodules.
* Re-export Text.Pandoc.Highlighting

## (v0.4.0.0)

* Remove `SBConfig` and constraints from this library. This was only here for refactoring
  convenience and creating a context should be up to the user.

## (v0.3.1.0)

* Add `withContent` lens.
* Add lifted version of `flattenMeta` from `Slick.Pandoc`.

## (v0.3.0.0)

* Upgrade to [shake-plus](https://hackage.haskell.org/package/shake-plus) v0.1.3.0
  to take advantage of new interface consistency.
* readMarkdownFile now extracts images from the pandoc and calls need on them.
* Removed most default code, moved back to user level.
* Tempate now uses caching for loading posts resulting in significant speedup.
* Add withSocialLinks function.
* Remove affix-style
* Add `sbGlobalApply` to apply a function on every page that comes into
  existence whether generated or loaded.
* Removed `Shakebook.Aeson` and moved to new library [aeson-with](https://hackage.haskell.org/package/aeson-with)

## (v0.2.2.0)

* Depend on new experimental library
  [shake-plus](https://hackage.haskell.org/package/shake-plus), that includes
re-exports of the Shake API based on the
[path](https://hackage.haskell.org/package/path) library for well-typed paths
and the [within](https://hackage.haskell.org/package/within) library which
introduces the `Within` type for representing a `Path` within a `Path`.
* Zipper functionality moved to external library
  [zipper-extra](https://hackage.haskell.org/package/zipper-extra).
* `Shakebook` and `ShakebookA` dropped in favour of `ShakePlus` and `RAction`
   from `shake-plus`.

## (v0.2.0.3)

* Add logging to Shakebook's monads via RIO's logging methods.
* Add testing framework.
* Add hackage documentation.

## (v0.1.5.0)

* Factored out API into this library.
* Standardised lens and enrichment functions.
* Supports user-specified enrichments.
* Adds a Shakebook monad and a ShakebookA monad that wraps shake's
  Rules and shake's Action monads respectively.
* Supports reader based config of input and output directories, baseUrl,
  markdown reader and writer config options and posts per page.
* Supports more general pager specifications allowing user specified data
  extraction from the URL fragment into a page Zipper.
* Adds general loading function via `loadSortFilterExtract` for loading
  markdown via the monad through patterns.

## (v0.1.0.0)

* Note: Unreleased in this repo. Copied from original shakebook.site template.
* Shake static site application that can export technical documentation both to
  HTML and to PDF using [pandoc](https://pandoc.org)
* Comes with a [nix](https://nixos.org/nix/) shell with full
* [LaTeX](https://www.latex-project.org/) and video rendering capabilities.
* Supports user configuration of table of contents via the `Shakefile.hs`
* Supports additional compilation units via [shake](https://shakebuild.com).
* Features two examples - one video rendering example with
  [reanimate](https://hackage.haskell.org/package/reanimate) and one generated
image using [R](https://www.r-project.org/) using
[inline-r](https://hackage.haskell.org/package/inline-r).
* Supports a blog section with tags, links to tag filtered pages and links to
  month filtered pages.
* Includes [bootstrap](https://getbootstrap.com/) and
  [fontawesome](https://fontawesome.com/) Supports
* [MathJax](https://www.mathjax.org/) and code syntax highlighting via pandoc's
  highlighting engine.  Features an example documentation section containing
the documentation for Shakebook itself.
* Supports [Atom](https://validator.w3.org/feed/docs/atom.html) feed generation
  from blog data.
