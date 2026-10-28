# Country-level usage statistics. No UI, machine control, or shot access.
namespace eval ::plugins::decent_remote::usage {
    variable timer {}; variable started 0; variable generation 0
    variable worker {}; variable pending {}; variable status not_configured
    variable state {}; variable result {}

    proc config {} {
        set enabled 1; set endpoint {}
        if {[info exists ::plugins::decent_remote::settings(usage_enabled)]} {set enabled $::plugins::decent_remote::settings(usage_enabled)}
        if {[info exists ::plugins::decent_remote::settings(usage_endpoint)]} {set endpoint $::plugins::decent_remote::settings(usage_endpoint)}
        if {![string is boolean -strict $enabled] || !$enabled} {return {}}
        if {![regexp {^https://[a-zA-Z0-9][a-zA-Z0-9.-]*/v1/check-in$} $endpoint]} {return {}}
        return $endpoint
    }
    proc state_file {} {return [file join $::plugins::decent_remote::directory usage-state.tdb]}
    proc now {} {clock seconds}
    proc load_state {} {
        set p [state_file]
        if {![file exists $p]} {return [dict create install_id {} last_attempt 0 last_success 0]}
        if {[file size $p] > 1024} {error "Invalid statistics state"}
        set f [open $p r]; try {set d [read $f]} finally {close $f}
        if {[catch {dict size $d}] || [lsort [dict keys $d]] ne {install_id last_attempt last_success}} {error "Invalid statistics state"}
        if {![regexp {^[a-f0-9]{32}$} [dict get $d install_id]]} {error "Invalid statistics state"}
        foreach k {last_attempt last_success} {
            if {![string is wideinteger -strict [dict get $d $k]] || [dict get $d $k] < 0} {error "Invalid statistics state"}
        }
        return $d
    }
    proc save_state {d} {
        set path [state_file]; set temp "${path}.tmp"
        set f [open $temp {WRONLY CREAT TRUNC} 0600]
        try {puts $f $d} finally {close $f}
        file rename -force $temp $path
    }
    proc random_id {} {
        set f [open /dev/urandom rb]
        try {set bytes [read $f 16]} finally {close $f}
        if {[string length $bytes] != 16} {error "Random source unavailable"}
        binary scan $bytes H* id
        return $id
    }
    proc schedule {ms} {
        variable timer; variable started
        if {$timer ne {}} {after cancel $timer; set timer {}}
        if {$started} {set timer [after $ms ::plugins::decent_remote::usage::tick]}
    }
    proc start {} {
        variable started; variable generation; variable status
        if {$started} {return}
        set started 1; incr generation
        set status [expr {[config] eq {} ? "not_configured_or_disabled" : "waiting"}]
        if {[config] ne {}} {schedule 60000}
    }
    proc stop {} {
        variable started; variable generation; variable timer; variable status
        set started 0; incr generation; set status stopped
        if {$timer ne {}} {after cancel $timer; set timer {}}
        # An already-started transfer has a 10-second bound and will clean itself up.
        # Never wait for a network thread on the GUI thread.
    }
    proc idle {} {
        if {[catch {::plugins::decent_remote::device::state} value]} {return 0}
        return [expr {$value in {Idle Sleep}}]
    }
    proc tick {} {
        variable started; variable pending; variable state; variable status; variable generation
        if {!$started} {return}
        schedule 3600000
        set endpoint [config]
        if {$endpoint eq {}} {set status not_configured_or_disabled; return}
        if {$pending ne {} || ![idle]} {schedule 60000; return}
        if {[catch {set state [load_state]}]} {set status state_unavailable; return}
        set t [now]
        # A backwards local clock is handled conservatively: never burst retries.
        if {[dict get $state last_success] > 0 && $t-[dict get $state last_success] < 604800} {set status up_to_date; return}
        if {[dict get $state last_attempt] > 0 && $t-[dict get $state last_attempt] < 86400} {set status retry_later; return}
        if {[dict get $state install_id] eq {}} {
            if {[catch {dict set state install_id [random_id]}]} {set status random_unavailable; return}
        }
        dict set state last_attempt $t
        if {[catch {save_state $state}]} {set status state_unavailable; return}
        set pending [list $generation $endpoint [dict get $state install_id] $t]
        set status updating
        if {[catch {dispatch $endpoint [dict get $state install_id]}]} {set pending {}; set status transport_unavailable}
    }
    proc dispatch {endpoint id} {
        variable worker; variable result
        package require Thread
        set ca [file join [homedir] allcerts.pem]
        if {![file isfile $ca]} {error "Trust store unavailable"}
        set worker [thread::create]
        if {[catch {
            thread::send $worker [list set auto_path $::auto_path]
            trace add variable ::plugins::decent_remote::usage::result write ::plugins::decent_remote::usage::completed
            thread::send -async $worker [list apply [list {endpoint id ca} {
                set h {}
                try {
                    package require TclCurl
                    set h [curl::init]
                    $h configure -url $endpoint -post 1 -postfields [format {{"install_id":"%s"}} $id] \
                        -httpheader {Content-Type:\ application/json} -useragent DecentRemote \
                        -bodyvar response -connecttimeout 5 -timeout 10 -followlocation 0 \
                        -sslverifypeer 1 -sslverifyhost 2 -cainfo $ca -maxfilesize 4096 -verbose 0
                    $h perform
                    set code [$h getinfo responsecode]
                    if {$code == 200 && [string length $response] <= 4096} {
                        package require json
                        set data [::json::json2dict $response]
                        if {[dict exists $data accepted] && [dict get $data accepted] eq "true"} {return [dict create ok 1]}
                    }
                    return [dict create ok 0]
                } on error {e o} {return [dict create ok 0]} finally {
                    if {$h ne {}} {catch {$h cleanup}}
                }
            }] $endpoint $id $ca] ::plugins::decent_remote::usage::result
        } e o]} {
            catch {trace remove variable ::plugins::decent_remote::usage::result write ::plugins::decent_remote::usage::completed}
            catch {thread::release $worker}; set worker {}
            return -options $o $e
        }
    }
    proc completed {args} {
        variable worker; variable pending; variable result; variable generation
        variable started; variable state; variable status
        catch {trace remove variable ::plugins::decent_remote::usage::result write ::plugins::decent_remote::usage::completed}
        if {$worker ne {}} {catch {thread::release $worker}; set worker {}}
        set previous $pending; set pending {}
        if {!$started || [llength $previous] != 4 || [lindex $previous 0] != $generation || [config] ne [lindex $previous 1]} {return}
        if {[catch {dict get $result ok} ok] || $ok ne "1"} {set status retry_later; return}
        if {[catch {set latest [load_state]}] || [dict get $latest install_id] ne [lindex $previous 2]} {set status state_unavailable; return}
        dict set latest last_success [now]
        if {[catch {save_state $latest}]} {set status state_unavailable; return}
        set state $latest; set status up_to_date
    }
}
