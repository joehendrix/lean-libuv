import Lake
open Lake DSL

require alloy from git "https://github.com/tydeu/lean4-alloy.git"

package LibUV where
  -- add package configuration options here

module_data alloy.c.o : BuildJob FilePath

def runPkgConfig (args : Array String) : IO (Array String) := do
  let out ← IO.Process.output { cmd := "pkg-config", args }
  if out.exitCode ≠ 0 then
    let stderr ← IO.getStderr
    stderr.putStr s!"Cannot run pkg-config"
    stderr.flush
    IO.Process.exit 1
  return out.stdout.splitOn.toArray.map String.trimRight

def pkgConfigCFlags (lib : String) : IO (Array String) := runPkgConfig #["--cflags", lib]
def pkgConfigLibs (lib : String) : IO (Array String) := runPkgConfig #["--libs", lib]

@[default_target]
lean_lib LibUV where
  precompileModules := true
  nativeFacets := #[Module.oFacet, `alloy.c.o]
  moreLeancArgs := run_io (pkgConfigCFlags "libuv")
  moreLinkArgs  := run_io (pkgConfigLibs   "libuv")