# Offline concurrency/ACK regression. The native leaves below are simulated;
# this suite never connects a device, creates a socket, or starts an operation.
package require tcltest
namespace import ::tcltest::*
set here [file dirname [info script]]
foreach component {core profiles legacy} {source [file join $here .. $component.tcl]}
set ::testroot [makeDirectory send-gate-[pid]]
file mkdir [file join $::testroot profiles]
set f [open [file join $::testroot profiles current.tcl] w]
puts $f {profile_title Current settings_profile_type settings_2a}
close $f
proc profile_vars {} {
    return {settings_profile_type espresso_temperature espresso_temperature_0 espresso_temperature_1
        preinfusion_flow_rate final_desired_shot_volume_advanced final_desired_shot_volume_advanced_count_start future_native_parameter}
}
proc userdata_append {description command vital} {lappend ::de1(cmdstack) [list $description $command $vital]}
proc de1_send_shot_frames {{override {}}} {
    incr ::sends
    unset -nocomplain ::de1(shot_frames_sent)
    set ::frames [list [list FrameToWrite 0 SetVal $::settings(preinfusion_flow_rate) Temp $::settings(espresso_temperature_0)]]
    if {$override ne {}} {set ::frames $override}
    userdata_append {Espresso header: fixture} {de1_comm write HeaderWrite fixture} 1
    foreach frame $::frames {userdata_append {Espresso frame #1: fixture} [list de1_comm write FrameWrite $frame] 1}
    if {$::sender_failure} {error simulated_partial_send_failure}
    userdata_append Confirm [list confirm_de1_send_shot_frames_worked $::frames] 1
}
proc confirm_de1_send_shot_frames_worked {parts} {
    incr ::confirmations
    set ::held_during_confirm [expr {$::plugins::decent_remote::receipts::flight ne {}}]
    unset -nocomplain ::de1(shot_frames_sent)
    set ::de1(cmdstack) {}; set ::de1(wrote) 0
    if {$::confirm_failure} {error simulated_confirmation_error}
}
proc parse_binary_shotframe {packed arrayName} {
    upvar 1 $arrayName fields
    switch $::parser {
        empty {return}
        missing_index {array set fields {SetVal 4 Temp 92}; return}
        error {error simulated_parse_error}
        default {array set fields $packed}
    }
}
proc save_settings_to_de1 {} {de1_send_shot_frames}
proc send_de1_settings_soon {} {
    if {[info exists ::save_settings_to_de1_id]} {catch {after cancel $::save_settings_to_de1_id}}
    set ::save_settings_to_de1_id [after 500 save_settings_to_de1]
}
proc fire_timer {} {
    after cancel $::save_settings_to_de1_id
    save_settings_to_de1
}
proc native_recovered {} {set ::de1(cmdstack) {}; set ::de1(wrote) 0}
proc acknowledge {{actual {}}} {
    if {$actual eq {}} {set actual $::frames}
    set ::de1(shot_frames_sent) $actual
    confirm_de1_send_shot_frames_worked $::frames
}
proc fake {operation payload} {
    if {$operation in {status recipe.get profile.current controls.get scale.get}} {
        return [dict create dose_g $::settings(grinder_dose_weight) readback app_cache]
    }
    if {$operation eq "machine.stop"} {incr ::stops; return {accepted 1 device_confirmed 0}}
    if {[dict exists $payload reject]} {::plugins::decent_remote::api::fail 422 invalid_value rejected_before_mutation}
    incr ::mutations
    if {[dict exists $payload dose_g]} {set ::settings(grinder_dose_weight) [dict get $payload dose_g]}
    switch $::send_mode {
        deferred {send_de1_settings_soon}
        direct {de1_send_shot_frames}
        none {}
        fail_after_queue {de1_send_shot_frames; ::plugins::decent_remote::api::fail 502 send_unknown simulated_failure}
    }
    return [dict create accepted 1 readback app_cache device_confirmed 0]
}
proc reset {} {
    if {[info exists ::save_settings_to_de1_id]} {catch {after cancel $::save_settings_to_de1_id}; unset ::save_settings_to_de1_id}
    ::plugins::decent_remote::receipts::uninstall
    foreach var {records active pending queued flight send_stack ack_stack tainted} {set ::plugins::decent_remote::receipts::$var {}}
    set ::plugins::decent_remote::receipts::tainted_all 0
    array unset ::settings
    array set ::settings {
        profile_filename current settings_profile_type settings_2a grinder_dose_weight 18
        espresso_temperature 92 espresso_temperature_0 92 espresso_temperature_1 92
        preinfusion_flow_rate 4 final_desired_shot_volume_advanced 100
        final_desired_shot_volume_advanced_count_start 0 future_native_parameter preserved
    }
    array unset ::de1
    array set ::de1 {cmdstack {} wrote 0 previouscmd {}}
    set ::plugins::decent_remote::api::root $::testroot
    set ::plugins::decent_remote::api::token offline-gate-token-123456789
    set ::plugins::decent_remote::api::seen {}
    set ::plugins::decent_remote::api::adapter fake
    set ::send_mode deferred; set ::mutations 0; set ::sends 0; set ::stops 0
    set ::confirmations 0; set ::serial 0; set ::lastid {}; set ::parser normal; set ::confirm_failure 0; set ::sender_failure 0
    ::plugins::decent_remote::receipts::install
}
proc request {method path {body {}} {legacy_no_id 0}} {
    set headers [dict create authorization {Bearer offline-gate-token-123456789}]
    if {$method ne "GET" && !$legacy_no_id} {
        set ::lastid [format gate-%08d [incr ::serial]]
        dict set headers x-request-id $::lastid
    }
    return [::plugins::decent_remote::api::dispatch $method $path $headers $body]
}
proc receipt {{id {}}} {
    if {$id eq {}} {set id $::lastid}
    return [::json::json2dict [dict get [request GET /api/v1/requests/$id] body]]
}
proc age_flight {} {
    if {$::plugins::decent_remote::receipts::flight ne {}} {
        dict set ::plugins::decent_remote::receipts::flight started [expr {[clock milliseconds]-31000}]
    }
    dict for {id record} $::plugins::decent_remote::receipts::records {
        if {[dict exists $record queued_at_ms]} {dict set ::plugins::decent_remote::receipts::records $id queued_at_ms [expr {[clock milliseconds]-31000}]}
    }
}

test gate-before-deferred-send {second client rejected before mutation; GET and stop remain available} -body {
    reset
    set first [request POST /api/v1/recipe {{"dose_g":19}}]; set owner $::lastid
    set second [request POST /api/v1/recipe {{"dose_g":20}}]
    set get [request GET /api/v1/profile]; set stop [request POST /api/v1/machine/stop {{}}]
    list [dict get $first status] [dict get $second status] $::mutations $::settings(grinder_dose_weight) \
        [dict get [receipt $owner] in_flight] [dict get $get status] [dict get $stop status] $::stops $::sends
} -result {200 409 1 19 true 200 200 1 0}

test gate-ack-release {only matching ACK completes; gate remains held until native confirmation returns} -body {
    reset
    request POST /api/v1/recipe {{"dose_g":19}}; set owner $::lastid
    fire_timer
    set before [receipt $owner]
    acknowledge
    set after [receipt $owner]
    set next [request POST /api/v1/profile {{"dose_g":20}}]
    list [dict get $before phase] [dict get $before device_confirmed] [dict get $before in_flight] \
        $::held_during_confirm [dict get $after phase] [dict get $after device_confirmed] [dict get $after in_flight] \
        [dict get $after confirmation_scope] [dict get $next status]
} -result {frames_queued false true 1 frames_confirmed true false profile_frames_only 200}

test gate-all-profile-writes {new and legacy curve writes share one gate, including legacy requests without ID} -body {
    reset
    request POST /api/v1/recipe {{"dose_g":19}}
    set statuses {}
    foreach {method path} {
        POST /api/v1/recipe POST /api/v1/profile POST /api/v1/profile/restore
        POST /api/v1/profile/save POST /api/v1/profile/save-as POST /api/v1/flow-compensation
        PUT /api/v1/profiles/current.tcl PUT /api/profile/current.tcl PUT /api/v2/shot/123.json
    } {
        set legacy [expr {![string match /api/v1/* $path]}]
        lappend statuses [dict get [request $method $path {{}} $legacy] status]
    }
    list $statuses $::mutations
} -result {{409 409 409 409 409 409 409 409 409} 1}

test gate-legacy-owner {legacy select without request ID also owns an in-flight ticket} -body {
    reset
    set first [request PUT /api/profile/current.tcl {} 1]
    set second [request POST /api/v1/recipe {{"dose_g":20}}]
    fire_timer; acknowledge
    set next [request POST /api/v1/recipe {{"dose_g":21}}]
    list [dict get $first status] [dict get $second status] [dict get $next status] $::mutations
} -result {200 409 200 2}

test gate-app-native-busy {native App sends block remote changes even without a remote owner} -body {
    reset
    de1_send_shot_frames
    set blocked [request POST /api/v1/recipe {{"dose_g":20}}]
    acknowledge
    set next [request POST /api/v1/recipe {{"dose_g":21}}]
    list [dict get $blocked status] [dict get $next status] $::mutations
} -result {409 200 1}

test gate-app-timer {existing native debounce timer blocks editing before any frames exist} -body {
    reset
    send_de1_settings_soon
    set blocked [request POST /api/v1/recipe {{"dose_g":20}}]
    after cancel $::save_settings_to_de1_id
    set next [request POST /api/v1/recipe {{"dose_g":21}}]
    list [dict get $blocked status] [dict get $next status] $::sends $::mutations
} -result {409 200 0 1}

test gate-inflight-native-command {command already dequeued but waiting for BLE response still blocks} -body {
    reset
    set ::de1(wrote) 1; set ::de1(previouscmd) {de1_comm write FrameWrite fixture}
    list [dict get [request POST /api/v1/profile {{"dose_g":19}}] status] $::mutations
} -result {409 0}

test gate-timeout {timeout is unconfirmed, never retries; native queue must drain before another request} -body {
    reset
    request POST /api/v1/recipe {{"dose_g":19}}; set owner $::lastid
    fire_timer; age_flight
    set timed [receipt $owner]
    set blocked [request POST /api/v1/recipe {{"dose_g":20}}]
    native_recovered
    set next [request POST /api/v1/recipe {{"dose_g":21}}]
    list [dict get $timed phase] [dict get $timed device_confirmed] [dict get $timed in_flight] \
        [dict get $blocked status] [dict get $next status] $::sends
} -result {unconfirmed_timeout false false 409 200 1}

test gate-late-identical-ack {old ACK after timeout cannot certify a new identical frame transfer} -body {
    reset
    request POST /api/v1/recipe {{"dose_g":19}}; set old $::lastid
    fire_timer; set old_frames $::frames; age_flight; receipt $old; native_recovered
    request POST /api/v1/recipe {{"dose_g":20}}; set current $::lastid
    fire_timer
    set ::de1(shot_frames_sent) $old_frames
    confirm_de1_send_shot_frames_worked $old_frames
    set got [receipt $current]
    acknowledge
    list [dict get [receipt $old] phase] [dict get $got phase] [dict get $got device_confirmed] \
        [dict get $got confirmation_note] [dict get [receipt $current] device_confirmed]
} -result {unconfirmed_timeout frames_unconfirmed false previous_unconfirmed_identical_frames false}

test gate-failed-ack-ends-tracking {failed frame validation cannot later adopt a matching duplicate callback} -body {
    reset
    request POST /api/v1/recipe {{"dose_g":19}}; set owner $::lastid
    fire_timer; acknowledge {{FrameToWrite 0 SetVal 4.0625 Temp 92}}
    set first [receipt $owner]; set pending $::plugins::decent_remote::receipts::pending
    acknowledge
    list [dict get $first phase] [dict get $first in_flight] $pending [dict get [receipt $owner] device_confirmed]
} -result {frames_unconfirmed false {} false}

test gate-parser-empty {empty parsed array is not a vacuous successful ACK comparison} -body {
    reset
    request POST /api/v1/recipe {{"dose_g":19}}; fire_timer
    set ::parser empty; acknowledge
    list [dict get [receipt] phase] [dict get [receipt] device_confirmed] $::confirmations \
        $::plugins::decent_remote::receipts::pending [dict get [receipt] in_flight]
} -result {frames_unconfirmed false 1 {} false}

test gate-parser-errors {missing index or parser error cannot block native confirmation or report success} -body {
    set result {}
    foreach mode {missing_index error} {
        reset
        request POST /api/v1/recipe {{"dose_g":19}}; fire_timer
        set ::parser $mode; acknowledge
        lappend result [dict get [receipt] device_confirmed] $::confirmations [dict get [receipt] in_flight]
    }
    set result
} -result {false 1 false false 1 false}

test gate-complete-native-snapshot {volume, split temperature and newly added native fields invalidate deferred attribution} -body {
    set phases {}
    foreach key {final_desired_shot_volume_advanced espresso_temperature_1 future_native_parameter} {
        reset
        request POST /api/v1/recipe {{"dose_g":19}}; set owner $::lastid
        set ::settings($key) changed_locally
        fire_timer; acknowledge
        lappend phases [dict get [receipt $owner] phase] [dict get [receipt $owner] device_confirmed]
    }
    set phases
} -result {superseded false superseded false superseded false}

test gate-native-override {native override cannot be misattributed to unchanged global profile state} -body {
    reset
    request POST /api/v1/recipe {{"dose_g":19}}; set owner $::lastid
    after cancel $::save_settings_to_de1_id
    de1_send_shot_frames {{FrameToWrite 0 SetVal 6 Temp 95}}
    acknowledge
    list [dict get [receipt $owner] phase] [dict get [receipt $owner] device_confirmed] [dict get [receipt $owner] in_flight]
} -result {superseded false false}

test gate-observer-missing {missing observers never confirm; timeout unlocks after native work is gone} -body {
    reset
    ::plugins::decent_remote::receipts::uninstall
    request POST /api/v1/recipe {{"dose_g":19}}; set owner $::lastid
    fire_timer; acknowledge
    set blocked [request POST /api/v1/profile {{"dose_g":20}}]
    age_flight
    set old [receipt $owner]
    set next [request POST /api/v1/profile {{"dose_g":21}}]
    list [dict get $blocked status] [dict get $old phase] [dict get $old device_confirmed] [dict get $next status]
} -result {409 unconfirmed_timeout false 200}

test gate-no-native-send {non-GHC app-only changes do not acquire unrelated later App ACKs} -body {
    reset
    set ::send_mode none
    request POST /api/v1/recipe {{"dose_g":19}}; set owner $::lastid
    set before [receipt $owner]
    de1_send_shot_frames; acknowledge
    list [dict get $before in_flight] [dict get $before confirmation_note] \
        [dict get [receipt $owner] phase] [dict get [receipt $owner] device_confirmed]
} -result {false no_native_send_observed app_applied false}

test gate-send-unknown {failure after native queueing holds gate until native completion, never claims success} -body {
    reset
    set ::send_mode fail_after_queue
    set first [request POST /api/v1/recipe {{"dose_g":19}}]; set owner $::lastid
    set blocked [request POST /api/v1/profile {{"dose_g":20}}]
    acknowledge
    list [dict get $first status] [dict get $blocked status] [dict get [receipt $owner] phase] \
        [dict get [receipt $owner] device_confirmed] [dict get [receipt $owner] in_flight]
} -result {502 409 outcome_unknown false false}

test gate-native-confirmation-error {native error after ACK observation retracts confirmation and releases plugin gate} -body {
    reset
    request POST /api/v1/recipe {{"dose_g":19}}; fire_timer
    set ::confirm_failure 1; catch {acknowledge}
    list [dict get [receipt] phase] [dict get [receipt] device_confirmed] [dict get [receipt] in_flight]
} -result {outcome_unknown false false}

test gate-partial-native-send-error {failure before confirmation queue cannot lend late ACKs to a subsequent request} -body {
    reset
    request POST /api/v1/recipe {{"dose_g":19}}; set first $::lastid
    set ::sender_failure 1; catch {fire_timer}
    set failed [receipt $first]
    set blocked [request POST /api/v1/recipe {{"dose_g":20}}]
    age_flight; receipt $first; native_recovered
    set ::sender_failure 0
    set next [request POST /api/v1/recipe {{"dose_g":21}}]; set second $::lastid
    fire_timer; acknowledge
    list [dict get $failed phase] [dict get $failed confirmation_note] [dict get $blocked status] \
        [dict get $next status] [dict get [receipt $second] phase] [dict get [receipt $second] device_confirmed] \
        [dict get [receipt $second] in_flight] $::sends
} -result {outcome_unknown native_sender_error 409 200 frames_unconfirmed false false 2}

test gate-validation-rejected {validation failure releases unstarted owner and cannot attach a future ACK} -body {
    reset
    set rejected [request POST /api/v1/recipe {{"reject":true}}]; set owner $::lastid
    de1_send_shot_frames; acknowledge
    list [dict get $rejected status] $::mutations [dict get [receipt $owner] phase] [dict get [receipt $owner] device_confirmed]
} -result {422 0 rejected false}

test gate-import-independent {file import during a send does not select a curve, change settings or queue another send} -body {
    reset
    request POST /api/v1/recipe {{"dose_g":19}}; set owner $::lastid
    set content {profile_title Imported settings_profile_type settings_2a}
    set body [::json::write object filename [::json::write string imported.tcl] \
        format [::json::write string tcl] content [::json::write string $content] overwrite true]
    set r [request POST /api/v1/profiles/import $body]
    set parsed [::json::json2dict [dict get $r body]]
    list [dict get $r status] [dict get $parsed saved] [dict get $parsed readback] \
        $::mutations $::sends $::settings(profile_filename) [dict get [receipt $owner] in_flight]
} -result {200 true file 1 0 current true}

if {[info exists ::save_settings_to_de1_id]} {after cancel $::save_settings_to_de1_id}
::plugins::decent_remote::receipts::uninstall
removeDirectory $::testroot
cleanupTests
