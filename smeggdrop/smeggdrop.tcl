source $SMEGGDROP_ROOT/smeggdrop/versioned_interpreter.tcl
source $SMEGGDROP_ROOT/smeggdrop/commands.tcl

namespace eval smeggdrop {
  proc split_lines {string length} {
    set lines [list]

    foreach source_line [split $string \n] {
      set line ""
      set formatting [empty_formatting]
      
      foreach {format text} [split_on_formatting $source_line] {
        set formatting [parse_formatting $format $formatting]
        set chars [split $text {}]
        if ![llength $chars] {set chars [list {}]}
        
        foreach char $chars {
          if ![buffer line $length $format$char] {
            lappend lines $line
            set line [unparse_formatting $formatting]$char
          }
          set format ""
        }
      }

      lappend lines $line
    }
    
    return $lines
  }
  
  proc buffer {var length char} {
    upvar $var line

    if {![string bytelength $line] && [string index $char 0] eq "\017"} {
      set char [string range $char 1 end]
    }

    if {[string bytelength $line$char] <= $length} {
      append line $char
      return 1
    } else {
      return 0
    }
  }
  
  proc line_length_for channel {
    expr 511 - [string length "PRIVMSG $::botname $channel :"]
  }
  
  proc split_on_formatting string {
    set result [list]
    while {[string length $string]} {
      regexp {^(\003((\d{0,2})(,(\d{0,2}))?)?|\002|\037|\026|\017)?([^\003\002\037\026\017]*)(.*)} \
        $string {} format {} {} {} {} text remainder
      if {$format eq ""} {set format \017}
      lappend result $format $text
      set string $remainder
    }
    return $result
  }

  proc empty_formatting {} {
    list b 0 u 0 r 0 o 0 c 0 fg -1 bg -1
  }
  
  proc parse_formatting {str {state {}}} {
    if {$state eq ""} {
      array set f [empty_formatting]
    } else {
      array set f $state
    }
    set f(c) [set f(o) 0]
    switch -- [string index $str 0] [list \
      \003 {
        regexp {^\003((\d*)(,(\d*))?)?} $str {} a b {} c
        if {$a eq ""} {
          set f(fg) [set f(bg) -1]
          set f(c) 1
        }
        if {!($b eq "")} {
          set f(fg) $b
        }
        if {!($c eq "")} {
          set f(bg) $c
        }
      } \002 {
        set f(b) [expr !$f(b)]
      } \037 {
        set f(u) [expr !$f(u)]
      } \026 {
        set f(r) [expr !$f(r)]
      } \017 {
        set f(o) 1
      }]
    array get f
  }

  proc unparse_formatting {formatting {state {}}} {
    if {$state eq ""} {
      array set old [empty_formatting]
    } else {
      array set old $state
    }
    array set new $formatting
    if $old(o) {
      array set old [empty_formatting]
    }
    if $new(o) {
      return \017
    }
    set ret ""
    foreach k {b u r} {
      if {$old($k) != $new($k)} {
        append ret [string map {b \002 u \037 r \026} $k]
      }
    }
    return $ret[unparse_formatting_color [array get new] [array get old]]
  }
  
  proc unparse_formatting_color {new old} {
    array set n $new
    array set o $old
    if {($n(fg) == -1 && $n(bg) == -1) || ($n(fg) == $o(fg) && $n(bg) == $o(bg))} return
    set ret \003
    if !$n(c) {
      if {$n(fg) != -1 && $n(fg) != $o(fg)} {
        append ret [format %02s $n(fg)]
      }
      if {$n(bg) != -1 && $n(bg) != $o(bg)} {
        append ret ,[format %02s $n(bg)]
      }
    }
    return $ret
  }

  proc to_str string {
    set result ""
    foreach char [split $string {}] {
      if [regexp {[$\\"\[]} $char] {
        append result \\$char
      } elseif [is_unprintable $char] {
        append result \\[format %03o [scan $char %c]]
      } else {
        append result $char
      }
    }
    return "\"$result\""
  }
  
  proc is_unprintable char {
    set c [scan $char %c]
    expr {$c < 32 || $c > 126}
  }
}

proc interp_eval script {
  $::versioned_interpreter interpx . eval $script
}

proc pub:tcl {nick mask hand channel line} {
  after idle [list pub:tcl:perform $nick $mask $hand $channel $line]
}

proc pub:tcl:perform {nick mask hand channel line} {
  global versioned_interpreter

  commands::configure nick mask hand channel line
  commands::increment_eval_count
  
  set author "$nick on $channel <$mask>"

  if [catch {$versioned_interpreter eval $line $author} output] {
    set output "error: $output"
  }

  set lines [smeggdrop::split_lines $output [smeggdrop::line_length_for $channel]]
  
  if {[lsearch -regexp $lines {^\001DCC.*\001}] != -1} {
    set lines [list "error: output contains unsafe CTCP sequence"]
  }
  
  if {[set line_length [llength $lines]] > $::smeggdrop_max_lines} {
    set lines [lrange $lines 0 [expr $::smeggdrop_max_lines - 1]]
    lappend lines \
      "error: output truncated to $::smeggdrop_max_lines of $line_length lines total"
  }
                       
  foreach line $lines {
    putserv "PRIVMSG $channel :$line"
  }
}

if [info exists versioned_interpreter]  {$versioned_interpreter destroy}
if ![info exists smeggdrop_state_path]  {set smeggdrop_state_path  state}
if ![info exists smeggdrop_max_lines]   {set smeggdrop_max_lines   10}
if ![info exists smeggdrop_timeout]     {set smeggdrop_timeout     5000}
if ![info exists smeggdrop_trigger]     {set smeggdrop_trigger     tcl}

bind pub - $smeggdrop_trigger pub:tcl

set versioned_interpreter [versioned_interpreter create %AUTO% \
  $smeggdrop_state_path -verbose true -logcommand ::putlog -timeout $smeggdrop_timeout]

foreach alias [namespace eval commands {info procs}] {
  if {[lsearch -exact [commands::get hidden_procs] $alias] == -1} {
    $versioned_interpreter alias $alias ::commands::$alias
  }
}
