namespace eval commands {
  proc history {{start HEAD}} {
    if {[set revision [$::versioned_interpreter git rev-parse --revs-only $start]] eq ""} return
    set revisions [$::versioned_interpreter git rev-list "--pretty=format:%at%n%an <%ae>%n%s" -n 10 $revision]
    set result {}
    foreach {commit date author summary} [split $revisions \n] {
      lappend result [list [lindex $commit 1] $date $author $summary]
    }
    return $result
  }
}
