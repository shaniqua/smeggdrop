package require snit
package require Tclx

snit::type interpx {
  variable interp
  variable private_key
  variable procs_touched_during_eval -array {}
  variable vars_touched_during_eval -array {}
  variable timed_out
  
  option -onproccreated
  option -onprocupdated
  option -onprocdestroyed
  option -onvarcreated
  option -onvarupdated
  option -onvardestroyed
  option -timeout 6000
  
  constructor args {
    set private_key [expr rand()]
    $self configurelist $args
    $self initialize_interpreter
  }
  
  destructor {
    catch {interp delete $interp}
  }
  
  # introspection
  method procs {} {
    $self . info procs
  }
  
  method vars {} {
    $self . info vars
  }
  
  method scalars {} {
    set result {}
    foreach var [$self vars] {
      if [$self has scalar $var] {
        lappend result $var
      }
    }
    return $result
  }
  
  method arrays {} {
    set result {}
    foreach var [$self vars] {
      if [$self has array $var] {
        lappend result $var
      }
    }
    return $result
  }
  
  method serialize {} {
    set result {}
    
    foreach var [$self vars] {
      lappend result [$self inspect var $var]
    }
    
    foreach proc [$self procs] {
      lappend result [$self inspect proc $proc]
    }
    
    join $result \n
  }
  
  method {inspect var} var {
    if [$self has array $var] {
      $self inspect array $var
    } else {
      $self inspect scalar $var
    }
  }
  
  method {inspect scalar} scalar {
    if [$self has scalar $scalar] {
      list set $scalar [$self . set $scalar]
    } else {
      error "can't read \"$scalar\": no such scalar"
    }
  }
  
  method {inspect array} array {
    if [$self has array $array] {
      list array set $array [$self . array get $array]
    } else {
      error "can't read \"$array\": no such array"
    }
  }
  
  method {inspect proc} proc {
    set args {}
    foreach arg [$self . info args $proc] {
      if [$self . info default $proc $arg ::interpx::default] {
        set arg [list $arg [$self . set ::interpx::default]]
        $self . unset ::interpx::default
      }
      lappend args $arg
    }

    list proc $proc $args [$self . info body $proc]
  }
  
  # aliasing
  method alias {name command args} {
    apply [list $interp alias $name $command] $args
  }
  
  # evaluation
  method eval args {
    if {[lindex $args 0] eq "-notimeout"} {
      set timeout 0
      set script [lindex $args 1]
    } else {
      set timeout 1
      set timed_out 0
      set script [lindex $args 0]
    }

    array set procs_existing_before_eval [list_to_array [$self procs]]
    array set vars_existing_before_eval [list_to_array [$self vars]]

    unset procs_touched_during_eval
    array set procs_touched_during_eval {}

    unset vars_touched_during_eval
    array set vars_touched_during_eval {}
    
    if $timeout {
      signal trap SIGALRM [list ::interpx::timeout $self $private_key]
      alarm [expr {[$self cget -timeout] / 1000.0}]
    }
    
    set code [catch {$interp eval $script} result]
    
    if $timeout {
      alarm 0
      if $timed_out {
        set code 1
        set result "timeout ([$self cget -timeout]ms)"
      }
    }
    
    foreach proc [$self procs] {
      if ![info exists procs_existing_before_eval($proc)] {
        $self did create proc $proc
      } else {
        if [info exists procs_touched_during_eval($proc)] {
          $self did update proc $proc
        }
        unset procs_existing_before_eval($proc)
      }
    }
    
    foreach proc [array names procs_existing_before_eval] {
      $self did destroy proc $proc
    }

    foreach var [$self vars] {
      if ![var_is_traceable $var] continue
      
      if ![info exists vars_existing_before_eval($var)] {
        $self did create var $var
      } else {
        if [info exists vars_touched_during_eval($var)] {
          $self did update var $var
        }
        unset vars_existing_before_eval($var)
      }
    }
    
    foreach var [array names vars_existing_before_eval] {
      if ![var_is_traceable $var] continue
      $self did destroy var $var
    }
    
    return -code $code $result
  }
  
  method {did timeout} key {
    if {$key eq $private_key} {
      set timed_out 1
      error timeout
    }
  }
  
  # traces
  method {trace var} var {
    if [var_is_traceable $var] {
      $self . trace add variable $var write [$self trace_command_for_var $var]
    }
  }

  method {untrace var} var {
    if [var_is_traceable $var] {
      $self . trace remove variable $var write [$self trace_command_for_var $var]
    }
  }
  
  method {did touch var} {key var args} {
    if {$key eq $private_key} {
      set vars_touched_during_eval($var) {}
    }
  }

  method trace_command_for_var var {
    list ::interpx::touched_var $private_key $var
  }

  # callbacks
  method {did create proc} proc {
    $self fire proccreated $proc
  }
  
  method {did update proc} proc {
    $self fire procupdated $proc
  }
  
  method {did destroy proc} proc {
    $self fire procdestroyed $proc
  }
  
  method {did create var} var {
    $self trace var $var
    $self fire varcreated $var
  }
  
  method {did update var} var {
    $self fire varupdated $var
  }
  
  method {did destroy var} var {
    $self untrace var $var
    $self fire vardestroyed $var
  }
  
  method fire {event args} {
    if {[set handler [$self cget -on$event]] ne ""} {
      uplevel #0 [concat $handler $args]
    }
  }
  
  # internal implementations of builtins
  method proc args {
    set name [lindex $args 0]
    if [$self has builtin $name] {
      error "can't override builtin \"$name\""
    }

    set result [apply [list $self . proc] $args]
    set procs_touched_during_eval($name) {}
    return $result
  }
  
  method rename args {
    set name [lindex $args 0]
    if [$self has builtin $name] {
      error "can't rename builtin \"$name\""
    }

    set result [apply [list $self . rename] $args]
    set procs_touched_during_eval($name) {}
    return $result
  }
  
  method for args {
    set body [concat "::interpx::noop;" [lindex $args 3]]
    apply [list $self . for] [lreplace $args 3 3 $body]
  }
  
  method foreach args {
    set body [concat "::interpx::noop;" [lindex $args end]]
    apply [list $self . foreach] [lreplace $args end end $body]
  }
  
  method while args {
    set body [concat "::interpx::noop;" [lindex $args 1]]
    apply [list $self . while] [lreplace $args 1 1 $body]
  }
  
  # predicates
  method {has var} var {
    $self . info exists $var
  }
  
  method {has command} command {
    expr {[llength [$self . info commands $command]] == 1}
  }

  method {has scalar} scalar {
    expr {[$self has var $scalar] && ![$self has array $scalar]}
  }
  
  method {has array} array {
    $self . array exists $array
  }

  method {has proc} proc {
    expr {[llength [$self . info proc $proc]] == 1}
  }
  
  method {has builtin} builtin {
    expr {[$self has command $builtin] && ![$self has proc $builtin]}
  }
  
  # private
  method initialize_interpreter {} {
    set interp [interp create -safe]
    $self preserve array
    $self preserve error
    $self preserve eval
    $self preserve info
    $self preserve set
    $self preserve unset
    $self hide interp
    $self hide namespace
    $self hide trace
    $self hide vwait
    $self reimplement for
    $self reimplement foreach
    $self reimplement proc
    $self reimplement rename
    $self reimplement while
    $self unset_internal_vars
    $self initialize_private_namespace
  }
  
  method unset_internal_vars {} {
    foreach var [$self vars] {
      $self . unset $var
    }
  }
  
  method initialize_private_namespace {} {
    $self . namespace eval ::interpx {}
    $interp alias ::interpx::noop expr 0
    $interp alias ::interpx::timeout ::interpx::timeout
    $self expose {did touch var} ::interpx::touched_var
  }
  
  method hide command {
    $interp hide $command
  }
  
  method restore command {
    $interp alias $command $interp invokehidden $command
  }
  
  method preserve command {
    $self hide $command
    $self restore $command
  }
  
  method expose {command {as {}}} {
    if {$as eq ""} {
      set as $command
    }
    $interp alias $as $self $command
  }
  
  method reimplement command {
    $self hide $command
    $self expose $command
  }
  
  method . {command args} {
    apply [list $interp invokehidden $command] $args
  }
  
  # helpers
  proc list_to_array {list {value {}}} {
    set result {}
    foreach key $list {
      lappend result $key $value
    }
    return $result
  }
  
  proc apply {command arguments} {
    uplevel [concat $command $arguments]
  }
  
  proc var_is_traceable var {
    expr {$var ne "errorCode" && $var ne "errorInfo"}
  }
}

namespace eval interpx {
  proc timeout {interpx private_key} {
    $interpx did timeout $private_key
  }
}
