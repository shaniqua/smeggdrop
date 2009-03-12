namespace eval commands {
  proc encoding args {
    if {[string match s* [lindex $args 0]] && [llength $args] > 1} {
      error "can't modify system encoding"
    }
    apply ::encoding $args
  }
}
