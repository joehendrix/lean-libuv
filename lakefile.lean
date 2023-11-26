import Lake
open Lake DSL

require alloy from git "https://github.com/tydeu/lean4-alloy.git"

package LibUV where
  -- add package configuration options here

module_data alloy.c.o : BuildJob FilePath

def flushError (msg : String) : IO Unit := do
  let stderr ← IO.getStdout
  stderr.putStr msg
  stderr.flush


def fatalError (msg : String) (u : UInt8) : IO α := do
  flushError msg
  IO.Process.exit u

def runPkgConfig (args : Array String) : IO (Array String) := do
  let mout ← (Option.some <$> (IO.Process.output { cmd := "pkg-config", args })).tryCatch (fun _ => pure none)
  match mout with
  | Option.none =>
    flushError "Cannot run pkg-config"
    pure #[]
  | Option.some out =>
    if out.exitCode = 0 then
      return out.stdout.splitOn.toArray.map String.trimRight
    else
      flushError "pkg-config failed"
      pure #[]

def pkgConfigCFlags (lib : String) : IO (Array String) := runPkgConfig #["--cflags", lib]
def pkgConfigLibs (lib : String) : IO (Array String) := runPkgConfig #["--libs", lib]

@[default_target]
lean_lib LibUV where
  precompileModules := true
  nativeFacets := #[Module.oFacet, `alloy.c.o]
  moreLeancArgs := #["-fPIC", "-Iinclude"] ++ run_io (pkgConfigCFlags "libuv")
  moreLinkArgs  := run_io (pkgConfigLibs   "libuv")
