# The following variables can be set in eggdrop.conf:
#   set smeggdrop_line_length 460
#   set smeggdrop_max_lines   10
#   set smeggdrop_timeout     5000
#   set smeggdrop_trigger     tcl

source scripts/smeggdrop/versioned_interpreter.tcl
source scripts/smeggdrop/commands.tcl

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
  
  set prefix "PRIVMSG $channel :"
  set author "$nick on $channel <$mask>"

  if [catch {$versioned_interpreter eval $line $author} output] {
    set output "error: $output"
  }

  set lines [list]
  set len [expr {$::smeggdrop_line_length - [string length $prefix]}]
    
  # format the output for IRC
  foreach line [split $output \n] {
    set i 0
    while {$i < [string length $line]} {
      set body [string range $line $i [expr {$i+$len-1}]]
      if [regexp -nocase {^\001DCC.*\001} $body] {
        putserv "KILL $nick :UNDOCUMENTED HONEYPOT"
        return
      }
      lappend lines $body
      incr i $len
    }
  }
                     
  if {[llength $lines] > $::smeggdrop_max_lines} {
    set lines [lrange $lines 0 [expr $::smeggdrop_max_lines - 1]]
    lappend lines \
      "error: output exceeded maximum line length of $::smeggdrop_max_lines, truncating"
  }
                       
  foreach line $lines {
    putserv "$prefix$line"
  }
}

if [info exists versioned_interpreter]  {$versioned_interpreter destroy}
if ![info exists smeggdrop_line_length] {set smeggdrop_line_length 460}
if ![info exists smeggdrop_max_lines]   {set smeggdrop_max_lines   10}
if ![info exists smeggdrop_timeout]     {set smeggdrop_timeout     5000}
if ![info exists smeggdrop_trigger]     {set smeggdrop_trigger     tcl}

bind pub - $smeggdrop_trigger pub:tcl

set versioned_interpreter [versioned_interpreter create %AUTO% state \
  -verbose true -logcommand ::putlog -timeout $smeggdrop_timeout]

foreach alias [namespace eval commands {info procs}] {
  if {[lsearch -exact [commands::get hidden_procs] $alias] == -1} {
    $versioned_interpreter alias $alias ::commands::$alias
  }
}
