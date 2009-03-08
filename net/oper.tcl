if [info exists oper_nickname] {
  # Oper on startup
  bind raw - "001" raw:operify

  # Set usermodes when opped
  bind notc - "*You are now an IRC Operator.*" notc:usermodes

  proc notc:usermodes {nick uhost hand text {dest ""}} {
    global botnick
    if {[string match *@$::oper_service_hostname $uhost] && [string match $::oper_service_nickname $nick]} {
      putserv "MODE $botnick +H"
    }
  }

  proc raw:operify args {
    global botnick
    putlog "$botnick is asking for oper status"
    putserv "OPER $::oper_nickname $::oper_password"
  }
}
