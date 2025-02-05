/-
Copyright (c) 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Paul Govereau, Sean McLaughlin
-/
import Lean
import NKL

/-
Generate python files form lean definitions.
Note: this library is only used at compile-time.
-/

open Lean Meta

abbrev Handle := IO.FS.Handle

-- Place double-quotes around a string
private def dq (str : String) := s!"\"{str}\""

-- Extract the rightmost string from a Name: A.B.c ==> c
-- We shouldn't find any anonymous or numerical names
-- (such names will generate JSON that mismatches with Python)
private def cname : Name -> MetaM String
  | .str _ s => return s
  | n => throwError s!"Invalid Constructor Name {n}"

-- Print python namedtuple representing a single constructor
private def printTuple
  (h : Handle) (isStruct : Bool)
  (name : String) (fields : List String) : MetaM Unit :=
  do
    let fields := List.map dq fields
    let fn := if isStruct then "struct" else "cons"
    h.putStrLn s!"{name.capitalize} = {fn}({dq name}, {fields})"

-- Generate namedtuple for a structure
private def genStructure (h : Handle) (si : StructureInfo) : MetaM Unit := do
  let name <- cname si.structName
  let ns <- List.mapM cname si.fieldNames.toList
  printTuple h True name ns

-- Generate namedtuple's for an inductive type
-- Note, we assume the inductive type does not have the
-- same name as any of its constructors.
private def genInductive (h : Handle) (tc : Name) : MetaM Unit := do
  let mut names : Array String := #[]
  let tci <- getConstInfoInduct tc
  for c in tci.ctors do
    let ci <- getConstInfoCtor c
    let name <- cname ci.name
    names := names.push name
    forallTelescopeReducing ci.type fun xs _ => do
      let mut ns := []
      for i in [:ci.numFields] do
        let ld <- xs[ci.numParams + i]!.fvarId!.getDecl
        ns := .cons ld.userName.toString ns
      printTuple h False name ns.reverse
  let rhs := String.intercalate " | " (.map .capitalize names.toList)
  h.putStrLn s!"{<- cname tci.name} = {rhs}"

private def genPython (h : Handle) (name : Name) : MetaM Unit := do
  h.putStrLn ""
  match getStructureInfo? (<- getEnv) name with
  | some si => genStructure h si
  | none => genInductive h name

private def header :=
"# This file is automatically generated, do no edit
from functools import namedtuple

def cons(name, args):
  return namedtuple(name, args + [\"struct\"], defaults=[False])

def struct(name, args):
  return namedtuple(name, args + [\"struct\"], defaults=[True])
"

run_meta
  let h <- IO.FS.Handle.mk "interop/nkl/lean_types.py" IO.FS.Mode.write
  h.putStr header
  flip List.forM (genPython h)
    [ `NKL.Const
    , `NKL.Expr
    , `NKL.Stmt
    , `NKL.Fun
    ]
