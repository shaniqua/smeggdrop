namespace eval meta {
  proc eval_count {} {
    commands::get eval_count
  }
  
  proc line {} {
    commands::get line
  }
  
  proc uptime {} {
    $::versioned_interpreter uptime
  }
}

namespace eval commands {
  meta_proc meta
}
