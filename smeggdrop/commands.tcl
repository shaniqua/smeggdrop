source $SMEGGDROP_ROOT/smeggdrop/meta_proc.tcl

foreach script [glob -nocomplain $SMEGGDROP_ROOT/smeggdrop/commands/*.tcl] {
  source $script
}

namespace eval commands {
  variable nick
  variable mask
  variable hand
  variable channel
  variable line
  variable eval_count -1
  variable hidden_procs hidden
  
  proc hidden {proc name args body} {
    variable hidden_procs
    uplevel [list proc $name $args $body]
    lappend hidden_procs $name
  }
  
  hidden proc configure args {
    foreach var $args {
      variable $var
      set $var [uplevel [list set $var]]
    }
  }

  hidden proc increment_eval_count {} {
    variable eval_count
    incr eval_count
  }
  
  hidden proc get var {
    variable $var
    set $var
  }
  
  hidden proc apply {command arguments} {
    uplevel [concat $command $arguments]
  }
}
