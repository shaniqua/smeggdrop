package require snit
package require sha1
source $SMEGGDROP_ROOT/smeggdrop/interpx.tcl

snit::type versioned_interpreter {
  variable state_path
  variable interpx
  variable procs
  variable vars
  variable aliases {}
  variable is_inside_eval 0
  variable state_changed 0
  
  option -verbose    -readonly true -default false
  option -timeout    -readonly true -default 5000
  option -logcommand -readonly true -default {puts stderr}
  
  constructor {path_to_state args} {
    set state_path $path_to_state

    $self configurelist $args
    if [$self cget -verbose] {
      proc log message [list apply [$self cget -logcommand] {$message}]
    }

    $self initialize_interpreter
  }
  
  destructor {
    catch {$interpx destroy}
  }
  
  method interpx args {
    apply $interpx $args
  }

  method initialize_interpreter {} {
    if [info exists interpx] {
      $interpx destroy
    }
    
    set interpx [interpx create %AUTO% \
      -onproccreated    [list $self did create proc]  \
      -onprocupdated    [list $self did update proc]  \
      -onprocdestroyed  [list $self did destroy proc] \
      -onvarcreated     [list $self did create var]   \
      -onvarupdated     [list $self did update var]   \
      -onvardestroyed   [list $self did destroy var]  \
      -timeout          [$self cget -timeout]
    ]
    
    $self initialize_repository
    $self load_state_from_repository
    $self restore_interpreter_aliases
  }
  
  method initialize_repository {} {
    mkdir_p [$self path]
    mkdir_p [$self path procs]
    mkdir_p [$self path vars]
    touch [$self path procs _index]
    touch [$self path vars _index]
    
    if ![$self repository_exists] {
      $self git init
      $self git add procs vars
      $self commit "Created repository"
    }
  }
  
  method load_state_from_repository {{revision HEAD}} {
    $self git checkout -f $revision

    set time [clock clicks]
    log "Loading interpreter state..."

    set script {}
    lappend script [$self read_procs_from_repository]
    lappend script [$self read_vars_from_repository]
    $interpx eval -notimeout [join $script \n]
    
    log "State loaded ([format %.2f [expr {([clock clicks] - $time) / 1000000.0}]] sec)"
  }
  
  method read_procs_from_repository {} {
    set procs [index create %AUTO% [$self path procs _index]]
    set script {}
    foreach proc [$procs keys] {
      lappend script [$self read proc $proc]
    }
    join $script \n
  }
  
  method read_vars_from_repository {} {
    set vars [index create %AUTO% [$self path vars _index]]
    set script {}
    foreach var [$vars keys] {
      lappend script [$self read var $var]
    }
    join $script \n
  }
  
  method {read var} var {
    set kind [lindex [set kind_and_value [$self read object var $var]] 0]
    if {$kind eq "scalar"} {
      list set $var [lindex $kind_and_value 1]
    } elseif {$kind eq "array"} {
      list array set $var [lindex $kind_and_value 1]
    }
  }
  
  method {read proc} proc {
    concat [list proc $proc] [$self read object proc $proc]
  }
  
  method {read object} {kind key} {
    set index ${kind}s
    set filename [$self path $index [[set $index] get $key]]
    set file [open $filename r]
    fconfigure $file -encoding utf-8
    set value [read $file]
    close $file
    return $value
  }
  
  method {write var} var {
    set content [lindex [$interpx inspect var $var] end]
    if [$interpx has scalar $var] {
      set value [list scalar $content]
    } elseif [$interpx has array $var] {
      set value [list array $content]
    }
    $self write object var $var $value
  }
  
  method {write proc} proc {
    set value [lrange [$interpx inspect proc $proc] 2 end]
    $self write object proc $proc $value
  }
  
  method {write object} {kind key value} {
    set index ${kind}s
    set name [[set $index] get $key]
    set filename [$self path $index $name]
    set file [open $filename w]
    fconfigure $file -encoding utf-8
    puts $file $value
    close $file
    $self git add [file join $index $name]
    set state_changed 1
  }
  
  method delete {kind key} {
    set index ${kind}s
    set name [[set $index] delete $key]
    rm_f [$self path $index $name]
    set state_changed 1
  }
  
  method alias {name command args} {
    lappend aliases [list $name $command $args]
    apply [list $interpx alias $name $command] $args
  }
  
  method restore_interpreter_aliases {} {
    foreach alias $aliases {
      apply [list $interpx alias] [concat [lrange $alias 0 end-1] [lindex $alias end]]
    }
  }
  
  method eval {script {author "Administrator <admin@localhost>"} {message ""}}  {
    set is_inside_eval 1
    set code [catch {$interpx eval $script} result]
    set is_inside_eval 0
    
    if $state_changed {
      $procs save_to_file
      $vars save_to_file
    
      if {$message eq ""} {
        set message $script
      }
    
      if {[string length $message] > 1024} {
        set message [string range $message 0 1020]...
      }
    
      $self commit "Evaluated $message" $author
      
      set state_changed 0
    }
    
    return -code $code $result
  }
  
  method rollback {{revision HEAD^}} {
    set revision  [$self git rev-parse --revs-only $revision]
    set revisions [$self revisions $revision]

    foreach revision $revisions {
      $self git revert -n $revision
    }

    $self commit "Rolled back to revision $revision\nReverts [join $revisions]"
    $self initialize_interpreter
  }
  
  method {did create proc} proc {
    if !$is_inside_eval return
    $procs put $proc [sha1 $proc]
    $self write proc $proc
  }
  
  method {did update proc} proc {
    if !$is_inside_eval return
    $self write proc $proc
  }
  
  method {did destroy proc} proc {
    if !$is_inside_eval return
    $self delete proc $proc
  }
  
  method {did create var} var {
    if !$is_inside_eval return
    $vars put $var [sha1 $var]
    $self write var $var
  }
  
  method {did update var} var {
    if !$is_inside_eval return
    $self write var $var
  }
  
  method {did destroy var} var {
    if !$is_inside_eval return
    $self delete var $var
  }
  
  # private
  method path args {
    apply [list file join $state_path] $args
  }
  
  method git args {
    set pwd [pwd]
    cd [$self path]
    set code [catch {apply [list exec git] $args} result]
    cd $pwd
    return -code $code $result
  }
  
  method commit {message {author "Administrator <admin@localhost>"}} {
    set code [catch {$self git commit --author $author -am $message} result]
    if {$code && [regexp -line {^nothing (added )?to commit} $result]} {
      set code 0 
    }

    if [regexp -line {^origin$} [$self git remote]] {
      $self git push origin master 
    }

    return -code $code $result
  }
  
  method revisions {{until ""}} {
    set args HEAD
    if {$until ne ""} {
      lappend args ^$until
    }
    apply [list $self git rev-list] $args
  }
  
  method repository_exists {} {
    catch {$self git status} result
    set has_git_dir [file isdirectory [$self path .git]]
    expr {$has_git_dir && ![regexp {Not a git repository} $result]}
  }

  proc touch filename {
    exec touch $filename
  }
  
  proc mkdir_p directory {
    exec mkdir -p $directory
  }
  
  proc rm_f filename {
    exec rm -f $filename
  }
  
  proc exec args {
    log "--> $args"
    set command [concat $args |& cat]
    set result [apply ::exec $command]
    if {$result ne ""} {log $result}
    return $result
  }
  
  proc cd directory {
    ::cd $directory
    log "(in [pwd])"
  }
  
  proc apply {command arguments} {
    uplevel [concat $command $arguments]
  }
  
  proc sha1 string {
    ::sha1::sha1 $string
  }
  
  proc log message {
  }
}

snit::type versioned_interpreter::index {
  variable filename
  variable values -array {}
  
  constructor path {
    set filename $path
    $self load_from_file
  }
  
  method load_from_file {} {
    $self reset
    set file [open $filename r]
    fconfigure $file -encoding utf-8
    foreach {key value} [read $file] {
      $self put $key $value
    }
    close $file
  }
  
  method save_to_file {} {
    set file [open $filename w]
    fconfigure $file -encoding utf-8
    foreach key [$self keys] {
      puts $file [list $key [$self get $key]]
    }
    close $file
  }
  
  method reset {} {
    unset values
    array set values {}
  }

  method put {key value} {
    set values($key) $value
  }
  
  method get key {
    set values($key)
  }
  
  method delete key {
    set value [$self get $key]
    unset values($key)
    return $value
  }
  
  method has key {
    info exists values($key)
  }
  
  method keys {} {
    lsort [array names values]
  }
}
