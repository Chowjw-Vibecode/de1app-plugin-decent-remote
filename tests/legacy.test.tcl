package require tcltest
namespace import ::tcltest::*
set here [file dirname [info script]]
foreach name {core profiles legacy} {source [file join $here .. $name.tcl]}
set ::plugins::decent_remote::directory [file normalize [file join $here ..]]
set ::plugins::decent_remote::api::token 123456789012345678901234
set ::plugins::decent_remote::api::adapter fake
proc fake {op payload} {
    lappend ::calls [list $op $payload]
    switch $op {
        legacy.status {return {is_active true espresso_count 12 steaming_count 6}}
        legacy.details {return {state Espresso espresso_elapsed {0 1 2} espresso_pressure {0 4 8.6} espresso_temperature_basket {80 89 92}}}
        legacy.power {return {is_active false accepted 1 device_confirmed 0 readback requested_target}}
        legacy.sdb {return {{filename 1234 grinder_dose_weight 19 bean_notes 中文}}}
        default {return {accepted 1}}
    }
}
set headers [dict create authorization {Bearer 123456789012345678901234}]
proc req {m p {body {}} {extra {}}} {set ::calls {}; ::plugins::decent_remote::api::dispatch $m $p [dict merge $::headers $extra] $body}
proc code {r} {dict get $r status}
proc data {r} {::json::json2dict [dict get $r body]}
set tmp [makeDirectory legacy-new]
set ::plugins::decent_remote::api::root $tmp
foreach d {profiles history history_v2} {file mkdir $tmp/$d}
foreach {file text} {profiles/测试.tcl {profile_title 测试} history/1234.shot {clock 1234} history_v2/1234.json {{"clock":1234}}} {
    set f [open $tmp/$file w]; fconfigure $f -encoding utf-8; puts -nonewline $f $text; close $f
}
test legacy-auth-query {} -body {code [::plugins::decent_remote::api::dispatch GET /api/status {} {} {auth 123456789012345678901234}]} -result 200
test legacy-auth-missing {} -body {code [::plugins::decent_remote::api::dispatch GET /api/status {} {}]} -result 403
test v1-no-query-auth {} -body {code [::plugins::decent_remote::api::dispatch GET /api/v1/status {} {} {auth 123456789012345678901234}]} -result 401
test legacy-status {} -body {data [req GET /api/status]} -result {is_active true espresso_count 12 steaming_count 6}
test legacy-details {} -body {dict get [data [req GET /api/status/details]] espresso_pressure} -result {0 4 8.6}
test legacy-power-no-id {} -body {req POST /api/status {{"active":false}}; set calls} -result {{legacy.power {active false}}}
test legacy-profile-list {} -body {data [req GET /api/profile/]} -result 测试.tcl
test legacy-profile-download {} -body {dict get [req GET /api/profile/测试.tcl] body} -result {profile_title 测试}
test legacy-profile-select {} -body {set r [req PUT /api/profile/测试.tcl]; list [dict get $r body] $calls} -result {测试.tcl {{profile.select {filenameroot 测试}}}}
test legacy-shots {} -body {data [req GET /api/shot/]} -result 1234.shot
test legacy-shot {} -body {dict get [req GET /api/shot/1234.shot] body} -result {clock 1234}
test legacy-v2 {} -body {data [req GET /api/v2/shot/1234]} -result {clock 1234}
test legacy-dye {} -body {req PUT /api/v2/shot/1234; set calls} -result {{legacy.dye.next {timestamp 1234}}}
test legacy-sdb {} -body {data [req GET /api/v2/shots]} -result {{filename 1234 grinder_dose_weight 19 bean_notes 中文}}
test legacy-flush-is-log {} -body {req GET /api/flush; set calls} -result {{legacy.flush {}}}
test legacy-help {} -body {expr {[llength [dict get [data [req GET /api/help]] endpoints]] >= 15}} -result 1
test legacy-home {} -body {string match {*id="connect-button"*} [dict get [req GET /] body]} -result 1
test upload {} -body {code [req POST /api/profile {profile_title 新曲线} {filename new.tcl}]} -result 200
test upload-replace {} -body {req POST /api/profile {profile_title 更新} {filename new.tcl}; dict get [req GET /api/profile/new.tcl] body} -result {profile_title 更新}
test upload-invalid-atomic {} -body {set r [req POST /api/profile {not a valid profile} {filename new.tcl}]; list [code $r] [dict get [req GET /api/profile/new.tcl] body]} -result {422 {profile_title 更新}}
test upload-no-start {} -body {req POST /api/profile {profile_title 空载} {filename dry.tcl}; set calls} -result {}
test upload-traversal {} -body {list [code [req POST /api/profile {profile_title 不应落地} {filename ../unsafe.tcl}]] [file exists $tmp/unsafe.tcl]} -result {422 0}
test upload-command {} -body {list [code [req POST /api/profile {profile_title 害 advanced_shot_tcl {start_espresso}} {filename bad.tcl}]] $calls} -result {422 {}}
test upload-global-settings {} -body {code [req POST /api/profile {profile_title 害 stress_test 1} {filename bad.tcl}]} -result 422
test upload-duplicate {} -body {code [req POST /api/profile {profile_title a profile_title b} {filename bad.tcl}]} -result 422
test upload-real-filter3 {} -body {
    set text [::plugins::decent_remote::api::read_file [file join $here fixtures filter3.tcl]]
    code [req POST /api/profile $text {filename filter3.tcl}]
} -result 200
test cross-origin {} -body {code [req POST /api/status {{"active":true}} {host tablet:8888 origin http://evil.local}]} -result 403
test same-origin {} -body {code [req POST /api/status {{"active":true}} {host tablet:8888 origin http://tablet:8888}]} -result 200
test legacy-invalid-method {} -body {code [req POST /api/shot/1234.shot]} -result 405
test legacy-missing-json {} -body {code [req GET /api/v2/shot/]} -result 404
test v1-array-not-number {} -body {code [req POST /api/v1/recipe {{"dose_g":[18]}} {x-request-id new-id-001}]} -result 422
test upload-bad-temperature {} -body {code [req POST /api/profile {profile_title bad espresso_temperature nope} {filename bad.tcl}]} -result 422
test upload-negative-pressure {} -body {code [req POST /api/profile {profile_title bad espresso_pressure -999} {filename bad.tcl}]} -result 422
test upload-empty-advanced {} -body {code [req POST /api/profile {profile_title bad settings_profile_type settings_2c advanced_shot {}} {filename bad.tcl}]} -result 422
test upload-legacy-fields {} -body {code [req POST /api/profile {profile_title old grinder_dose_weight {} grinder_setting old} {filename old.tcl}]} -result 200
test upload-retired-official-flag {} -body {
    list [code [req POST /api/profile {profile_title old preinfusion_guarantee 0} {filename old.tcl}]] [code [req POST /api/profile {profile_title old preinfusion_guarantee bad} {filename old.tcl}]]
} -result {200 422}
removeDirectory legacy-new
cleanupTests
