namespace eval cache {
  namespace eval buckets {
    proc import {bucket_name {as bucket}} {
      variable ::cache::buckets::$bucket_name
      if ![info exists ::cache::buckets::$bucket_name] {
        array set ::cache::buckets::$bucket_name {}
      }
      uplevel [list upvar ::cache::buckets::$bucket_name $as]
    }
  }
  
  proc keys bucket_name {
    buckets::import $bucket_name
    array names bucket
  }
  
  proc exists {bucket_name key} {
    buckets::import $bucket_name
    info exists bucket($key)
  }
  
  proc get {bucket_name key} {
    buckets::import $bucket_name
    ensure_key_exists $bucket_name $key
    set bucket($key)
  }

  proc put {bucket_name key value} {
    buckets::import $bucket_name
    set bucket($key) $value
  }

  proc fetch {bucket_name key script} {
    if [exists $bucket_name $key] {
      get $bucket_name $key
    } else {
      put $bucket_name $key [interp_eval $script]
    }
  }
  
  proc delete {bucket_name key} {
    buckets::import $bucket_name
    ensure_key_exists $bucket_name $key
    unset bucket($key)
  }

  proc ensure_key_exists {bucket_name key} {
    if ![exists $bucket_name $key] {
      error "bucket \"$bucket_name\" doesn't have key \"$key\""
    }
  }
}

namespace eval commands {
  meta_proc cache delete exists fetch get keys put
}
