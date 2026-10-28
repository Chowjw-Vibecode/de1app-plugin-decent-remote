package require tcltest 2
namespace import ::tcltest::*
source [file join [file dirname [info script]] .. .. usage.tcl]
source [file join [file dirname [info script]] .. .. adapter.tcl]
namespace eval ::plugins::decent_remote {variable directory; variable settings; array set settings {usage_enabled 1 usage_endpoint https://usage.test/v1/check-in}}
set ::testdir [makeDirectory usage-client]
set ::plugins::decent_remote::directory $::testdir
rename ::plugins::decent_remote::usage::dispatch ::plugins::decent_remote::usage::real_dispatch
proc ::plugins::decent_remote::usage::dispatch {endpoint id} {lappend ::sent [list $endpoint $id]}
rename ::plugins::decent_remote::usage::now ::plugins::decent_remote::usage::real_now
proc ::plugins::decent_remote::usage::now {} {return $::test_now}
rename ::plugins::decent_remote::usage::idle ::plugins::decent_remote::usage::real_idle
proc ::plugins::decent_remote::usage::idle {} {return $::is_idle}
proc reset_usage {} {
 ::plugins::decent_remote::usage::stop
 set ::plugins::decent_remote::usage::pending {}; set ::plugins::decent_remote::usage::state {}
 set ::plugins::decent_remote::usage::worker {};set ::sent {};set ::test_now 2000000000;set ::is_idle 1
 set ::plugins::decent_remote::settings(usage_enabled) 1
 set ::plugins::decent_remote::settings(usage_endpoint) https://usage.test/v1/check-in
 file delete -force [file join $::testdir usage-state.tdb] [file join $::testdir usage-state.tdb.tmp]
}
proc complete_usage {ok} {set ::plugins::decent_remote::usage::result [dict create ok $ok];::plugins::decent_remote::usage::completed}
proc run_usage {} {::plugins::decent_remote::usage::start;::plugins::decent_remote::usage::tick}

test client-1 {no endpoint or disabled means no traffic and no state file} -setup {reset_usage} -body {
 set ::plugins::decent_remote::settings(usage_endpoint) {};run_usage
 set a [list [llength $::sent] [file exists [::plugins::decent_remote::usage::state_file]]]
 ::plugins::decent_remote::usage::stop
 set ::plugins::decent_remote::settings(usage_endpoint) https://usage.test/v1/check-in
 set ::plugins::decent_remote::settings(usage_enabled) 0;run_usage
 list $a [llength $::sent] [file exists [::plugins::decent_remote::usage::state_file]]
} -result {{0 0} 0 0}
test client-2 {one stable random ID survives restarts; success suppresses updates for a week} -setup {reset_usage} -body {
 run_usage;set id [lindex $::sent 0 1];complete_usage 1
 ::plugins::decent_remote::usage::stop;run_usage
 set before [llength $::sent];incr ::test_now 604800;::plugins::decent_remote::usage::tick
 list [regexp {^[a-f0-9]{32}$} $id] $before [llength $::sent] [expr {[lindex $::sent 1 1] eq $id}]
} -result {1 1 2 1}
test client-3 {failure waits 24 hours, including across restart} -setup {reset_usage} -body {
 run_usage;complete_usage 0
 ::plugins::decent_remote::usage::stop;run_usage
 set before [llength $::sent];incr ::test_now 86400;::plugins::decent_remote::usage::tick
 list $before [llength $::sent]
} -result {1 2}
test client-4 {active machine delays statistics without any state write} -setup {reset_usage} -body {
 set ::is_idle 0;run_usage
 set before [llength $::sent];set exists [file exists [::plugins::decent_remote::usage::state_file]]
 set ::is_idle 1;::plugins::decent_remote::usage::tick
 list $before $exists [llength $::sent]
} -result {0 0 1}
test client-5 {single request in flight; disabling or stopping prevents completion persistence} -setup {reset_usage} -body {
 run_usage;::plugins::decent_remote::usage::tick;set n [llength $::sent]
 set ::plugins::decent_remote::settings(usage_enabled) 0;complete_usage 1
 list $n [dict get [::plugins::decent_remote::usage::load_state] last_success]
} -result {1 0}
test client-6 {stopped generation cannot count an old callback after restart} -setup {reset_usage} -body {
 run_usage;::plugins::decent_remote::usage::stop;::plugins::decent_remote::usage::start;complete_usage 1
 list [dict get [::plugins::decent_remote::usage::load_state] last_success] $::plugins::decent_remote::usage::pending
} -result {0 {}}
test client-7 {corrupt state cannot silently create a second installation} -setup {reset_usage} -body {
 set f [open [::plugins::decent_remote::usage::state_file] w];puts $f {invalid state};close $f
 run_usage;list [llength $::sent] $::plugins::decent_remote::usage::status
} -result {0 state_unavailable}
test client-8 {only HTTPS endpoints with the specified path are allowed} -setup {reset_usage} -body {
 set out {}
 foreach u {http://usage.test/v1/check-in https://user:pass@usage.test/v1/check-in https://usage.test/v1/check-in?token=x https://usage.test/other} {
  set ::plugins::decent_remote::settings(usage_endpoint) $u;lappend out [::plugins::decent_remote::usage::config]
 }
 set out
} -result {{} {} {} {}}
test client-9 {a backwards clock cannot trigger a retry burst} -setup {reset_usage} -body {
 run_usage;complete_usage 1;incr ::test_now -3600;::plugins::decent_remote::usage::tick
 llength $::sent
} -result 1
test client-10 {a failed state write blocks network dispatch} -setup {reset_usage} -body {
 rename ::plugins::decent_remote::usage::save_state ::plugins::decent_remote::usage::real_save_state
 proc ::plugins::decent_remote::usage::save_state {d} {error {disk failure}}
 run_usage
 set result [list [llength $::sent] $::plugins::decent_remote::usage::status]
 rename ::plugins::decent_remote::usage::save_state {};rename ::plugins::decent_remote::usage::real_save_state ::plugins::decent_remote::usage::save_state
 set result
} -result {0 state_unavailable}
test client-11 {uses the existing classic state adapter without a newer optional API} -setup {reset_usage} -body {
 set ::de1(state) 2
 set out {}
 foreach value {Idle Sleep Espresso Unknown} {
  set ::de1_num_state(2) $value
  lappend out [::plugins::decent_remote::usage::real_idle]
 }
 set out
} -result {1 1 0 0}
::plugins::decent_remote::usage::stop
removeDirectory $::testdir
set failed $::tcltest::numTests(Failed)
cleanupTests
exit [expr {$failed > 0}]
