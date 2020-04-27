# Changelog for Shakebook

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
