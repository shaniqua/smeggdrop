namespace eval dict {
  variable cache 
  array set cache {}
        
  variable cache_times
  array set cache_times {}
    
  proc file_is_cached? filename {
    info exists ::dict::cache($filename)
  }
    
  proc file_has_changed? filename {
    if ![info exists ::dict::cache_times($filename)] {
      puts ""
      return 1
    }
    expr {[file mtime $filename] != $::dict::cache_times($filename)}
  }

  proc cache_dictionary filename {
    set file [open $filename r]
    set ::dict::cache($filename) [split [read $file] \n]
    set ::dict::cache_times($filename) [clock seconds]
    close $file 
  }

  proc get_dictionary filename {
    if [file_has_changed? $filename] {
      cache_dictionary $filename
    }
    return $::dict::cache($filename)
  }
}

namespace eval commands {
  proc words {} {
    dict::get_dictionary "$::SMEGGDROP_ROOT/data/words"
  }
}
