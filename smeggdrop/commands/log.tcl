if [info exists smeggdrop_log_max_lines] {
  bind pubm - * pubm:smeggdrop_log_line
  array set smeggdrop_log_lines {}

  proc pubm:smeggdrop_log_line {nick mask hand channel line} {
    lappend ::smeggdrop_log_lines($channel) [list [clock seconds] $nick $mask $line]
    if {[set length [llength $::smeggdrop_log_lines($channel)]] >= $::smeggdrop_log_max_lines} {
      set ::smeggdrop_log_lines($channel) \
        [lrange $::smeggdrop_log_lines($channel) [expr $length - $::smeggdrop_log_max_lines] end]
    }
  }

  namespace eval commands {
    proc log {} {
      variable channel
      set ::smeggdrop_log_lines($channel)
    }
  }
}
