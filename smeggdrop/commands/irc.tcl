namespace eval commands {
  proc names {} {
    variable channel
    return [chanlist $channel]
  }
  
  proc nick {} {
    variable nick
    return $nick
  }
  
  proc channel {} {
    variable channel
    return $channel
  }
  
  proc hostmask {{who ""}} {
    variable channel
    variable mask
    
    set hostmask [getchanhost $who $channel]
    if {$hostmask eq ""} {set hostmask $mask}
    return $hostmask
  }
}
