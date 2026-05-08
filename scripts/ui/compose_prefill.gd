class_name ComposePrefill
extends RefCounted

# Transient state passed between Inbox and Compose panels.
# Set by Inbox when user clicks "compose action toward referent."
# Read and cleared by Compose on _ready.
static var target_ref: StringName = &""
static var target_kind: StringName = &""  # &"place" or &"character"
