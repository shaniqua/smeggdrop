if [info exists nickserv_nickname] {
  bind notc - "*This nickname is registered and protected*" notc:nickserv

  proc notc:nickserv {nick umask handle text {dest ""}} {
    if {[string match *@$::nickserv_service_hostname $umask] && [string match $::nickserv_service_nickname $nick]}  {
      putserv "NICKSERV identify $::nickserv_password"
      putserv "HOSTSERV on"
    }
  }

  proc checknick {} {
    if {$::botnick ne $::nickserv_nickname} {
      putserv "NICKSERV recover $::nickserv_nickname $::nickserv_password"
      putserv "NICKSERV release $::nickserv_nickname $::nickserv_password"
      putserv "NICK $::nickserv_nickname"
      putserv "HOSTSERV on"
    }

    if $::nickserv_check {
      after [expr {$::nickserv_check * 1000}] checknick
    }
  }

  after [expr {$nickserv_check * 1000}] checknick
}
