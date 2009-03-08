if [info exists smeggdrop_publish_url] {
  namespace eval commands {
    variable last_publish 0

    proc publish message {
      variable last_publish
      set time_since_last_publish [expr [clock seconds] - $last_publish]
      if {$time_since_last_publish < 5} {
        error "can't publish for another [expr 5 - $time_since_last_publish] secs"
      }

      set file [open /tmp/publish-data w]
      fconfigure $file -encoding utf-8
      puts $file $message
      close $file

      set cmd [list exec env \
        PUBLISH_HOSTNAME=$::smeggdrop_publish_hostname \
        PUBLISH_USERNAME=$::smeggdrop_publish_username \
        PUBLISH_PASSWORD=$::smeggdrop_publish_password \
        PUBLISH_FILENAME=$::smeggdrop_publish_filename \
        $::SMEGGDROP_ROOT/bin/publish.rb < /tmp/publish-data]

      if [catch $cmd result] {
        error "publish failed"
      } else {
        set last_publish [clock seconds]
        return $::smeggdrop_publish_url
      }
    }
  }
}
