let
  buildDepError = pkg:
    builtins.throw ''
      The Haskell package set does not contain the package: ${pkg} (build dependency).
      
      If you are using Stackage, make sure that you are using a snapshot that contains the package. Otherwise you may need to update the Hackage snapshot you are using, usually by updating haskell.nix.
      '';
  sysDepError = pkg:
    builtins.throw ''
      The Nixpkgs package set does not contain the package: ${pkg} (system dependency).
      
      You may need to augment the system package mapping in haskell.nix so that it can be found.
      '';
  pkgConfDepError = pkg:
    builtins.throw ''
      The pkg-conf packages does not contain the package: ${pkg} (pkg-conf dependency).
      
      You may need to augment the pkg-conf package mapping in haskell.nix so that it can be found.
      '';
  exeDepError = pkg:
    builtins.throw ''
      The local executable components do not include the component: ${pkg} (executable dependency).
      '';
  legacyExeDepError = pkg:
    builtins.throw ''
      The Haskell package set does not contain the package: ${pkg} (executable dependency).
      
      If you are using Stackage, make sure that you are using a snapshot that contains the package. Otherwise you may need to update the Hackage snapshot you are using, usually by updating haskell.nix.
      '';
  buildToolDepError = pkg:
    builtins.throw ''
      Neither the Haskell package set or the Nixpkgs package set contain the package: ${pkg} (build tool dependency).
      
      If this is a system dependency:
      You may need to augment the system package mapping in haskell.nix so that it can be found.
      
      If this is a Haskell dependency:
      If you are using Stackage, make sure that you are using a snapshot that contains the package. Otherwise you may need to update the Hackage snapshot you are using, usually by updating haskell.nix.
      '';
in { system, compiler, flags, pkgs, hsPkgs, pkgconfPkgs, ... }:
  ({
    flags = {};
    package = {
      specVersion = "0";
      identifier = { name = "composite-aeson"; version = "0.7.1.0"; };
      license = "BSD-3-Clause";
      copyright = "2017 Confer Health, Inc., 2020 Vital Biosciences";
      maintainer = "oss@vitalbio.com";
      author = "Confer Health, Inc";
      homepage = "https://github.com/ConferOpenSource/composite#readme";
      url = "";
      synopsis = "JSON for Vinyl records";
      description = "Integration between Aeson and Vinyl records allowing records to be easily converted to JSON using automatic derivation, explicit formats, or a mix of both.";
      buildType = "Simple";
      isLocal = true;
      };
    components = {
      "library" = {
        depends = [
          (hsPkgs."aeson" or (buildDepError "aeson"))
          (hsPkgs."aeson-better-errors" or (buildDepError "aeson-better-errors"))
          (hsPkgs."base" or (buildDepError "base"))
          (hsPkgs."composite-base" or (buildDepError "composite-base"))
          (hsPkgs."containers" or (buildDepError "containers"))
          (hsPkgs."contravariant" or (buildDepError "contravariant"))
          (hsPkgs."generic-deriving" or (buildDepError "generic-deriving"))
          (hsPkgs."hashable" or (buildDepError "hashable"))
          (hsPkgs."lens" or (buildDepError "lens"))
          (hsPkgs."mmorph" or (buildDepError "mmorph"))
          (hsPkgs."mtl" or (buildDepError "mtl"))
          (hsPkgs."profunctors" or (buildDepError "profunctors"))
          (hsPkgs."scientific" or (buildDepError "scientific"))
          (hsPkgs."tagged" or (buildDepError "tagged"))
          (hsPkgs."template-haskell" or (buildDepError "template-haskell"))
          (hsPkgs."text" or (buildDepError "text"))
          (hsPkgs."time" or (buildDepError "time"))
          (hsPkgs."unordered-containers" or (buildDepError "unordered-containers"))
          (hsPkgs."vector" or (buildDepError "vector"))
          (hsPkgs."vinyl" or (buildDepError "vinyl"))
          ];
        buildable = true;
        };
      tests = {
        "composite-aeson-test" = {
          depends = [
            (hsPkgs."QuickCheck" or (buildDepError "QuickCheck"))
            (hsPkgs."aeson" or (buildDepError "aeson"))
            (hsPkgs."aeson-better-errors" or (buildDepError "aeson-better-errors"))
            (hsPkgs."aeson-qq" or (buildDepError "aeson-qq"))
            (hsPkgs."base" or (buildDepError "base"))
            (hsPkgs."composite-aeson" or (buildDepError "composite-aeson"))
            (hsPkgs."composite-base" or (buildDepError "composite-base"))
            (hsPkgs."containers" or (buildDepError "containers"))
            (hsPkgs."contravariant" or (buildDepError "contravariant"))
            (hsPkgs."generic-deriving" or (buildDepError "generic-deriving"))
            (hsPkgs."hashable" or (buildDepError "hashable"))
            (hsPkgs."hspec" or (buildDepError "hspec"))
            (hsPkgs."lens" or (buildDepError "lens"))
            (hsPkgs."mmorph" or (buildDepError "mmorph"))
            (hsPkgs."mtl" or (buildDepError "mtl"))
            (hsPkgs."profunctors" or (buildDepError "profunctors"))
            (hsPkgs."scientific" or (buildDepError "scientific"))
            (hsPkgs."tagged" or (buildDepError "tagged"))
            (hsPkgs."template-haskell" or (buildDepError "template-haskell"))
            (hsPkgs."text" or (buildDepError "text"))
            (hsPkgs."time" or (buildDepError "time"))
            (hsPkgs."unordered-containers" or (buildDepError "unordered-containers"))
            (hsPkgs."vector" or (buildDepError "vector"))
            (hsPkgs."vinyl" or (buildDepError "vinyl"))
            ];
          buildable = true;
          };
        };
      };
    } // {
    src = (pkgs.lib).mkDefault (pkgs.fetchgit {
      url = "https://github.com/locallycompact/composite";
      rev = "d79c272c5bb2dc8b82fd2a97ef6bb29201760b02";
      sha256 = "182llc7ia2xap3day6h7r1wnwxqf9p57l9jghqj8y7rm57ym2fh2";
      });
    postUnpack = "sourceRoot+=/composite-aeson; echo source root reset to \$sourceRoot";
    }) // { cabal-generator = "hpack"; }