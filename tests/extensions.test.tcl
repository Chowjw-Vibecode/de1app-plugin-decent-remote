package require tcltest
namespace import ::tcltest::*
source [file join [file dirname [info script]] .. core.tcl]
set ::plugins::decent_remote::api::token abcdefghijklmnopqrstuvwxyz
set ::plugins::decent_remote::api::adapter fake
set serial 0
proc fake {op payload} {
    set ::called [list $op $payload]
    if {[dict exists $payload force_error]} {::plugins::decent_remote::api::fail 502 send_unknown "发送未知"}
    return [dict create accepted 1 readback app_cache device_confirmed 0]
}
proc request {path body} {
    incr ::serial
    set ::lastid [format req-%08d $::serial]
    ::plugins::decent_remote::api::dispatch POST $path [dict create authorization {Bearer abcdefghijklmnopqrstuvwxyz} x-request-id $::lastid] $body
}
proc code {body} {dict get [request /api/v1/profile $body] status}
test nested-valid {} -body {code {{"steps":[{"pump":"flow","flow":1.0}],"dose_g":19}}} -result 200
test nested-retain {} -body {dict get [lindex $called 1] steps} -result {{pump flow flow 1.0}}
test nested-empty-array {} -body {code {{"steps":[]}}} -result 200
test nested-wrong-object {} -body {code {{"steps":{}}}} -result 422
test nested-string-as-list {} -body {code {{"steps":"{pump flow flow 1}"}}} -result 422
test nested-array-as-objects {} -body {code {{"steps":[["pump","flow"]]}}} -result 422
test nested-json-in-string {} -body {code {{"notes":"value: [not an array]"}}} -result 200
test duplicate-keys {} -body {code {{"dose_g":19,"dose_g":20}}} -result 400
test duplicate-decoded-keys {} -body {code {{"dose_g":19,"\u0064ose_g":20}}} -result 400
test trailing-value {} -body {code {{} {}}} -result 400
test trailing-comma {} -body {code {{"steps":[{},]}}} -result 400
test top-array {} -body {code {[]}} -result 400
test null-not-zero {} -body {code {{"dose_g":null}}} -result 422
test deep-nesting {} -body {code [string repeat {"a": 15][string repeat } 15]} -result 400
test unknown-container {} -body {code {{"settings":{"calibration":1}}}} -result 422
test old-flat-reject-container {} -body {dict get [request /api/v1/recipe {{"dose_g":[]}}] status} -result 422
test serializer-types {} -body {
    set j [::plugins::decent_remote::api::object {steps {{name 中文 flow 1.5 seconds 12}} slots {{slot 1 profile test}} autotare_states {Espresso HotWater} editable_steps 1 next_wake_at 123}]
    list [regexp {"steps"\s*:\s*\[} $j] [regexp {"flow"\s*:\s*1.5} $j] [regexp {"editable_steps"\s*:\s*true} $j] [::json::validate $j]
} -result {1 1 1 1}
test receipt-rejected {} -body {
    request /api/v1/profile {{"steps":null}}
    dict get [::plugins::decent_remote::receipts::read $lastid] phase
} -result rejected
test receipt-unknown {} -body {
    request /api/v1/profile {{"force_error":true}}
    dict get [::plugins::decent_remote::receipts::read $lastid] phase
} -result outcome_unknown
test receipt-app-only {} -body {
    request /api/v1/recipe {{"dose_g":19}}
    set r [::plugins::decent_remote::receipts::read $lastid]
    list [dict get $r phase] [dict get $r device_confirmed]
} -result {app_applied 0}
test receipt-route {} -body {
    set r [::plugins::decent_remote::api::dispatch GET /api/v1/requests/$lastid [dict create authorization {Bearer abcdefghijklmnopqrstuvwxyz}] {}]
    list [dict get $r status] [dict get [::json::json2dict [dict get $r body]] request_id]
} -match glob -result {200 req-*}
test receipt-replay-does-not-replace {} -body {
    set r [::plugins::decent_remote::api::dispatch POST /api/v1/recipe [dict create authorization {Bearer abcdefghijklmnopqrstuvwxyz} x-request-id $lastid] {{"dose_g":18}}]
    list [dict get $r status] [dict get [::plugins::decent_remote::receipts::read $lastid] phase]
} -result {409 app_applied}
# Mock the real confirmation call. These traces cannot send or run a machine.
proc userdata_append {description command flag} {lappend ::queue $command}
proc confirm_de1_send_shot_frames_worked {parts} {incr ::native_confirmations; unset -nocomplain ::de1(shot_frames_sent)}
proc parse_binary_shotframe {packed arrayName} {upvar 1 $arrayName fields; array set fields $packed}
proc receipt_request {path body} {
    incr ::serial
    set ::lastid [format req-%08d $::serial]
    ::plugins::decent_remote::receipts::begin $::lastid POST $path
    ::plugins::decent_remote::receipts::finish $::lastid [::plugins::decent_remote::api::response 200 {{"accepted":true,"readback":"app_cache","device_confirmed":false}}]
}
proc de1_send_shot_frames {{override {}}} {
    unset -nocomplain ::de1(shot_frames_sent)
    userdata_append Confirm [list confirm_de1_send_shot_frames_worked $::frames] 1
}
set native_confirmations 0; set queue {}
::plugins::decent_remote::receipts::install
test ack-exact-match {} -body {
    receipt_request /api/v1/recipe {{"dose_g":19}}
    set frames {{FrameToWrite 0 SetVal 1.0} {FrameToWrite 1 SetVal 0.75}}
    de1_send_shot_frames
    set ::de1(shot_frames_sent) $frames
    confirm_de1_send_shot_frames_worked $frames
    set r [::plugins::decent_remote::receipts::read $lastid]
    list [dict get $r phase] [dict get $r device_confirmed] [dict get $r confirmation_scope] $native_confirmations
} -result {frames_confirmed 1 profile_frames_only 1}
test ack-mismatch-native-continues {} -body {
    receipt_request /api/v1/recipe {{"dose_g":19}}
    de1_send_shot_frames
    set ::de1(shot_frames_sent) {{FrameToWrite 0 SetVal 1.0} {FrameToWrite 1 SetVal 0.8125}}
    confirm_de1_send_shot_frames_worked $frames
    list [dict get [::plugins::decent_remote::receipts::read $lastid] phase] $native_confirmations
} -result {frames_unconfirmed 2}
test old-ack-not-new-request {} -body {
    receipt_request /api/v1/recipe {{"dose_g":19}}
    de1_send_shot_frames
    set old $lastid
    receipt_request /api/v1/recipe {{"dose_g":20}}
    set ::de1(shot_frames_sent) $frames
    confirm_de1_send_shot_frames_worked $frames
    list [dict get [::plugins::decent_remote::receipts::read $old] phase] [dict get [::plugins::decent_remote::receipts::read $lastid] device_confirmed]
} -result {superseded 0}
test changed-app-profile-not-confirmed {} -body {
    receipt_request /api/v1/recipe {{"dose_g":19}}
    set ::settings(profile_filename) new_other_profile
    de1_send_shot_frames
    dict get [::plugins::decent_remote::receipts::read $lastid] phase
} -result superseded
test invalid-new-request-preserves-old-tracking {} -body {
    receipt_request /api/v1/recipe {{"dose_g":19}}
    set old $lastid
    request /api/v1/profile {{"steps":null}}
    list $::plugins::decent_remote::receipts::pending [dict get [::plugins::decent_remote::receipts::read $old] phase]
} -match glob -result {req-* app_applied}
test overlapping-identical-acks-never-prove-new-request {} -body {
    set ::plugins::decent_remote::receipts::queued {}
    receipt_request /api/v1/recipe {{"dose_g":19}}
    de1_send_shot_frames
    receipt_request /api/v1/recipe {{"dose_g":19}}
    de1_send_shot_frames
    set ::de1(shot_frames_sent) $frames
    confirm_de1_send_shot_frames_worked $frames
    set first [dict get [::plugins::decent_remote::receipts::read $lastid] device_confirmed]
    set ::de1(shot_frames_sent) $frames
    confirm_de1_send_shot_frames_worked $frames
    set r [::plugins::decent_remote::receipts::read $lastid]
    list $first [dict get $r device_confirmed] [dict get $r confirmation_note]
} -result {0 0 overlapping_transfers}
test queue-timeout-not-success {} -body {
    receipt_request /api/v1/recipe {{"dose_g":19}}
    de1_send_shot_frames
    dict set ::plugins::decent_remote::receipts::records $lastid queued_at_ms [expr {[clock milliseconds]-31000}]
    set r [::plugins::decent_remote::receipts::read $lastid]
    list [dict get $r phase] [dict get $r device_confirmed]
} -result {unconfirmed_timeout 0}
test uninstall-observer {} -body {::plugins::decent_remote::receipts::uninstall; list [trace info execution ::userdata_append] [trace info execution ::confirm_de1_send_shot_frames_worked]} -result {{} {}}
cleanupTests
