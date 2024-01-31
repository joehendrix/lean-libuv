import Lake
open Lake DSL

require alloy from git "https://github.com/tydeu/lean4-alloy.git"

package LibUV where
  -- add package configuration options here

module_data alloy.c.o : BuildJob FilePath

open Lean.Elab.Term
open Lean.Elab
open Lean.Meta
open Lean

def getCoreContext : CoreM Core.Context := read

/--
Executes a term of type `IO α` at elaboration-time
and produces an expression corresponding to the result via `ToExpr α`.
-/
syntax:lead (name := pkgRelPathElab) "pkgRelPath" term : term

@[term_elab pkgRelPathElab]
def elabPkgRelPath : TermElab := fun stx _expectedType? =>
  match stx with
  | `(pkgRelPath $t) => withRef t do
    withRef stx do
      let ctx ← getCoreContext
      let modulePath ← IO.FS.realPath ctx.fileName
      match modulePath.parent with
      | .some ⟨dir⟩ =>
        let s ← elabTerm t (.some (Expr.const ``System.FilePath []))
        let p := mkAppN (.const ``System.FilePath.mk []) #[mkStrLit dir]
        let s := mkAppN (.const ``System.FilePath.mk []) #[s]
        pure <| mkAppN (.const ``System.FilePath.join []) #[p, s]
      | .none =>
        throwErrorAt stx "Could not determine path"
  | _ => throwErrorAt stx s!"Invalid syntax {stx}"

def mkArrayLit (lvl : Level) (type : Expr) (l : List Expr) : Expr :=
  let empty := Expr.app (Expr.const ``Array.empty [lvl]) type
  let push r h := mkAppN (Expr.const ``Array.push [lvl]) #[type, r, h]
  l.foldl push empty

def elabRunPkgConfig (stx : Syntax) (args : Array String) : Elab.TermElabM Expr := do
  Lean.withRef stx do
    match ← (IO.Process.output { cmd := "pkg-config", args }).toBaseIO with
    | .ok out =>
      if out.exitCode != 0 then
        throwErrorAt stx "pkg-config failed: {out.exitCode}"
      let libParts := out.stdout.splitOn
      let stringType := Expr.const ``String []
      libParts
          |>.map (mkStrLit ·.trimRight)
          |> mkArrayLit .zero stringType
          |> pure
    | .error _ =>
        throwErrorAt stx "Could not run pkg-config"

syntax:lead (name := libuvCFlagsElab) "libuvCFlags" : term

@[term_elab libuvCFlagsElab]
def elabLibUVCFlags : Lean.Elab.Term.TermElab := fun stx _expectedType? =>
  elabRunPkgConfig stx #["--cflags", "libuv"]

syntax:lead (name := libuvLibsElab) "libuvLibs" : term

@[term_elab libuvLibsElab]
def elabLibUVLibs : Lean.Elab.Term.TermElab := fun stx _expectedType? =>
  elabRunPkgConfig stx #["--libs", "libuv"]

@[default_target]
lean_lib LibUV where
  precompileModules := true
  nativeFacets := #[Module.oFacet, `alloy.c.o]
  moreLeancArgs := #["-fPIC", s!"-I{pkgRelPath "include"}"] ++ libuvCFlags
  moreLinkArgs  := libuvLibs
