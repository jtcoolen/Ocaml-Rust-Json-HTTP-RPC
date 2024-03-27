with (import <nixpkgs> {});

 let
   # MUST match resolver in stack.yaml

   native_libs = [
     libffi
     zlib
     ncurses
     gmp
     pkg-config m4 cmake libev libiconv
     gcc
     gmp
     gmpxx
     libcxx
     clang
   ] ++ lib.optionals stdenv.isDarwin (with darwin.apple_sdk.frameworks; [
     Cocoa
     CoreServices
     Security
     CoreFoundation
     IOKit
     AppKit
   ]);

   mkFrameworkFlags = frameworks:
    pkgs.lib.concatStringsSep " " (
      pkgs.lib.concatMap
      (
        framework: [
          "-F${pkgs.darwin.apple_sdk.frameworks.${framework}}/Library/Frameworks"
          "-framework ${framework}"
        ]
      )
      frameworks
    );

 in stdenv.mkDerivation {

   name = "idrisBuildEnv";

   buildInputs = native_libs;

   NIX_LDFLAGS = pkgs.lib.optional pkgs.stdenv.isDarwin (
      mkFrameworkFlags [
        "CoreFoundation"
        "IOKit"
        "AppKit"
        "Security"
      ]);

 LDFLAGS = pkgs.lib.optional pkgs.stdenv.isDarwin (
      mkFrameworkFlags [
        "CoreFoundation"
        "IOKit"
        "AppKit"
        "Security"
      ]);


   STACK_IN_NIX_EXTRA_ARGS = builtins.foldl'
     (acc: lib:
       " --extra-lib-dirs=${lib}/lib --extra-include-dirs=${lib}/include" + acc)
     "" native_libs;
 }
