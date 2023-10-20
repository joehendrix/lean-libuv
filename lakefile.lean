import Lake
open Lake DSL

require alloy from git "https://github.com/tydeu/lean4-alloy.git"

package LibUV where
  -- add package configuration options here

module_data alloy.c.o : BuildJob FilePath

@[default_target]
lean_lib LibUV {
  precompileModules := true
  nativeFacets := #[Module.oFacet, `alloy.c.o]
  moreLeancArgs := #["-I/opt/homebrew/include"] 
  moreLinkArgs := #["-L/opt/homebrew/lib", "-luv"]
}