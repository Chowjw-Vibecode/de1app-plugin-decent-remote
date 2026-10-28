package require tcltest
namespace import ::tcltest::*
source [file join [file dirname [info script]] .. core.tcl]
source [file join [file dirname [info script]] .. transport.tcl]
source [file join [file dirname [info script]] .. profiles.tcl]
source [file join [file dirname [info script]] .. legacy.tcl]
set ::plugins::decent_remote::api::token 123456789012345678901234
set ::plugins::decent_remote::api::adapter ::fake
set headers [dict create authorization {Bearer 123456789012345678901234} x-request-id request-001]
set calls {}
proc fake {op p} {lappend ::calls [list $op $p]; return [dict create accepted 1 operation $op device_confirmed 0]}
proc req {method path {body {}}} {set ::plugins::decent_remote::api::seen {}; return [::plugins::decent_remote::api::dispatch $method $path $::headers $body]}
proc status {r} {dict get $r status}
test auth-1 {} -body {status [::plugins::decent_remote::api::dispatch GET /api/v1/status {} {}]} -result 401
test auth-2 {} -body {set h [dict replace $headers origin https://example.com]; status [::plugins::decent_remote::api::dispatch GET /api/v1/status $h {}]} -result 403
test read-1 {} -body {status [req GET /api/v1/status]} -result 200
test read-2 {} -body {lindex [lindex $calls end] 0} -result status
test json-1 {} -body {status [req POST /api/v1/recipe {not json}]} -result 400
test json-2 {} -body {status [req POST /api/v1/recipe {[1,2]}]} -result 400
test json-3 {} -body {status [req POST /api/v1/recipe {{"dose_g":18} junk}]} -result 400
test patch-1 {} -body {status [req POST /api/v1/recipe {{"dose_g":18.5}}]} -result 200
test start-1 {} -body {status [req POST /api/v1/machine/espresso {{}}]} -result 403
test start-2 {} -body {status [req GET /api/v1/machine/espresso]} -result 405
test start-3 {legacy permission cannot re-enable removed starts} -body {
 set ::plugins::decent_remote::api::allow_start 1
 set before $::calls; set result {}
 foreach kind {espresso flush steam hotwater} {lappend result [status [req POST /api/v1/machine/$kind {{}}]]}
 list $result [expr {$before eq $::calls}]
} -result {{403 403 403 403} 1}
test replay-1 {} -body {status [::plugins::decent_remote::api::dispatch POST /api/v1/machine/espresso $headers {{}}]} -result 409
test stop-1 {} -body {set ::plugins::decent_remote::api::allow_start 0; status [req POST /api/v1/machine/stop {{}}]} -result 200
test fields-1 {} -body {status [req POST /api/v1/scale/tare {{"ignored":true}}]} -result 422
test method-1 {} -body {status [req DELETE /api/v1/recipe]} -result 405
test path-1 {} -body {status [req GET /api/profile/%2e%2e.tcl]} -result 422
test path-2 {} -body {status [req GET /api/shot/../../settings.tdb]} -result 404
test path-3 {} -body {status [req GET "/api/shot/a\\b.shot"]} -result 422
test path-4 {} -body {status [req GET /api/profile/foo.json]} -result 422
set tmp [makeDirectory remote-test]
set ::plugins::decent_remote::api::root $tmp
file mkdir $tmp/profiles $tmp/history $tmp/history_v2
set f [open $tmp/profiles/中文.tcl w]; fconfigure $f -encoding utf-8; puts $f {profile_title 中文}; close $f
file link -symbolic $tmp/profiles/link.tcl $tmp/profiles/中文.tcl
test files-1 {} -body {::json::json2dict [dict get [req GET /api/v1/profiles] body]} -result 中文.tcl
test files-2 {} -body {status [req GET /api/profile/link.tcl]} -result 422
test select-1 {} -body {status [req PUT /api/profile/中文.tcl]} -result 200
test select-2 {} -body {lindex [lindex $calls end] 1} -result {filenameroot 中文}
test select-3 {} -body {status [req PUT /api/profile/missing.tcl]} -result 404
test unicode-1 {} -body {::json::json2dict [::plugins::decent_remote::http::ascii [::json::write object title [::json::write string 中文]]]} -result {title 中文}
namespace eval ::wibble {proc sendresponse {r} {set ::sent $r}}
test transport-1 {} -body {
    ::plugins::decent_remote::http::handle [dict create request [dict create method GET path /api/v1/status rawheader [list {Authorization: Bearer 123456789012345678901234}]]]
    dict get $::sent status
} -result 200
test transport-2 {} -body {
    ::plugins::decent_remote::http::handle [dict create request [dict create method GET path /api/v1/status rawheader [list {Authorization: Bearer 123456789012345678901234} {Authorization: Bearer 123456789012345678901234}]]]
    dict get $::sent status
} -result 401
removeDirectory remote-test
cleanupTests
