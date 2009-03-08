# The following variables can be set in eggdrop.conf:
#   set smeggdrop_http_requests_per_eval 5
#   set smeggdrop_http_request_interval  60
#   set smeggdrop_http_request_limit     25
#   set smeggdrop_http_post_limit        150000
#   set smeggdrop_http_transfer_limit    150000
#   set smeggdrop_http_time_limit        5000

# 5 requests, per interpreter eval, per channel (at most 25 requests per minute)
if ![info exists smeggdrop_http_requests_per_eval] {set smeggdrop_http_requests_per_eval 5}
if ![info exists smeggdrop_http_request_interval]  {set smeggdrop_http_request_interval  60}
if ![info exists smeggdrop_http_request_limit]     {set smeggdrop_http_request_limit     25}
if ![info exists smeggdrop_http_post_limit]        {set smeggdrop_http_post_limit        150000}
if ![info exists smeggdrop_http_transfer_limit]    {set smeggdrop_http_transfer_limit    150000}
if ![info exists smeggdrop_http_time_limit]        {set smeggdrop_http_time_limit        5000}

package require http

namespace eval httpx {
  http::config -useragent {Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_6; en-us) AppleWebKit/525.27.1 (KHTML, like Gecko) Version/3.2.1 Safari/525.27.1}

  variable options
  proc option {name args} {
    variable options
    eval [concat [list set options($name)] $args]
  }  

  option requests_per_eval $::smeggdrop_http_requests_per_eval
  option request_interval  $::smeggdrop_http_request_interval
  option request_limit     $::smeggdrop_http_request_limit
  option post_limit        $::smeggdrop_http_post_limit
  option transfer_limit    $::smeggdrop_http_transfer_limit
  option time_limit        $::smeggdrop_http_time_limit
  
  variable requests
  array set requests {}

  proc enforce_limits {} {
    variable requests
    array set current [limit_info]
    
    set eval_request_count 0
    set threshold [expr {$current(seconds) - [option request_interval]}]
    set threshold_request_count 0
    
    foreach limit_info [requests] {
      array set request $limit_info
      if {$request(eval_count) == $current(eval_count)} {
        if {[incr eval_request_count] >= [option requests_per_eval]} {
          error "too many HTTP requests in this eval (max [option requests_per_eval] requests)"
        }
      } elseif {$request(seconds) >= $threshold} {
        if {[incr threshold_request_count] >= [option request_limit]} {
          error "too many HTTP requests (max [option request_limit] requests in [option request_interval] seconds)"
        }
      }
    }
  }

  proc update_limits {} {
    variable requests
    array set current [limit_info]
    set old_requests [requests]
    set new_requests [list [array get current]]
    set threshold [expr {$current(seconds) - [option request_interval]}]
    
    foreach limit_info $old_requests {
      array set request $limit_info
      if {$request(seconds) >= $threshold} {
        lappend new_requests $limit_info
      }
    }

    set requests([limit_key]) $new_requests
    return
  }

  proc requests {} {
    variable requests
    if [info exists requests([limit_key])] {
      set requests([limit_key])
    } else {
      list
    }
  }

  proc limit_key {} {
    ::commands::get channel
  }
  
  proc limit_info {} {
    list seconds [clock seconds] eval_count [::commands::get eval_count]
  }
    
  proc http_proc {name args body} {
    set new_body [list]
    lappend new_body [list enforce_limits]
    lappend new_body "if {\[catch [list $body] {}] == 1} {error \[set {}]}"
    lappend new_body [list update_limits]
    lappend new_body [list set {}]
    set new_body [join $new_body \;]
    proc $name $args $new_body
  }
    
  proc http_read_progress_callback {token total current} {
    upvar #0 $token state
    if {$current > [option transfer_limit]} {
      http::reset $token "transfer exceeded [option transfer_limit] bytes"
    }
  }
    
  proc http_handle_token token {
    upvar #0 $token state
    
    set status $state(status)
    
    if {$status ne "ok"} {
      http::cleanup $token
      error $status
    }
        
    set ret [list]
    lappend ret [http::ncode $token]
    lappend ret $state(meta)
    lappend ret $state(body)
    http::cleanup $token
    return $ret
  }
    
  http_proc head url {
    set token [http::geturl $url -validate 1 -timeout [option time_limit]]
    http_handle_token $token
  }
    
  http_proc get url {
    set token [http::geturl $url \
      -blocksize 1024 \
      -timeout   [option time_limit] \
      -progress  ::httpx::http_read_progress_callback]
        
    http_handle_token $token
  }
    
  http_proc post {url body args} {
    if [llength $args] {
      set body [eval http::formatQuery [concat [list $body] $args]]
    }

    if {[string length $body] > [option post_limit]} {
      error "post body exceeds [option post_limit] bytes"
    }
        
    set token [http::geturl $url \
      -blocksize 1024 \
      -timeout   [option time_limit] \
      -progress  ::httpx::http_read_progress_callback \
      -query     $body]
        
    http_handle_token $token
  }
}

namespace eval commands {
  meta_proc http -namespace httpx head get post
}
