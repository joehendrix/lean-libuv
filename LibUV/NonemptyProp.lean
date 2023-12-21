def NonemptyProp := Subtype fun α : Prop => Nonempty α

instance : Inhabited NonemptyProp := ⟨⟨PUnit, ⟨⟨⟩⟩⟩⟩

/-- The underlying type of a `NonemptyType`. -/
abbrev NonemptyProp.type (type : NonemptyProp) : Prop := type.val
