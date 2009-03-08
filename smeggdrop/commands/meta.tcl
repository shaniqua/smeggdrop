namespace eval meta {
  proc eval_count {} {
    commands::get eval_count
  }
  
  proc line {} {
    commands::get line
  }
}

namespace eval commands {
  meta_proc meta
}
