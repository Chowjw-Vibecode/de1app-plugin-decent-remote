package require tcltest
namespace import ::tcltest::*
source [file join [file dirname [info script]] .. core.tcl]
source [file join [file dirname [info script]] .. profiles.tcl]
set tmp [makeDirectory profile-import]
set ::plugins::decent_remote::api::root $tmp
proc imp {name content {format tcl} args} {::plugins::decent_remote::profiles::import_payload [dict create filename $name content $content format $format {*}$args]}
proc code {script} {catch {uplevel 1 $script} e o; return [dict get $o -errorcode]}
set basic {profile_title 测试曲线 original_profile_title 原曲线 profile_filename old advanced_shot_tcl {}}
set native {{"version":2,"type":"advanced","title":"中文曲线","author":"作者","notes":"说明","steps":[{"name":"注水","temperature":93,"sensor":"water","pump":"flow","transition":"smooth","pressure":3,"flow":2,"seconds":30,"volume":100,"weight":45,"exit":{"type":"flow","condition":"under","value":1},"limiter":{"value":4,"range":0.5}}],"target_weight":45,"target_volume":100,"target_volume_count_start":0,"tank_temperature":0,"legacy_profile_type":"settings_2c","hidden":0,"lang":"zh","beverage_type":"espresso","reference_file":"原曲线","changes_since_last_espresso":""}}
test import-1 {Chinese Tcl saved/readback} -body {imp 中文 $basic} -result {filename 中文.tcl title 测试曲线 format tcl saved 1 readback file}
test import-2 {duplicate blocked} -body {code {imp 中文 $basic}} -result {REMOTE 409 already_exists}
test import-3 {explicit replace} -body {dict get [imp 中文 {profile_title 替换} tcl overwrite true] saved} -result 1
test import-4 {dry no file} -body {set r [imp preview $basic tcl dry_run true]; list [dict get $r saved] [file exists $tmp/profiles/preview.tcl]} -result {0 0}
test import-5 {JSON full mapping} -body {
 imp 曲线.json $native json
 set p [::plugins::decent_remote::api::read_file $tmp/profiles/曲线.tcl]
 set s [lindex [dict get $p advanced_shot] 0]
 list [dict get $p profile_title] [dict get $s exit_type] [dict get $s exit_flow_under] [dict get $s max_flow_or_pressure] [dict get $p final_desired_shot_weight_advanced] [dict exists $p profile_grinder_dose_weight]
} -result {中文曲线 flow_under 1 4 45 0}
test import-6 {script prohibited} -body {code {imp bad {profile_title Bad advanced_shot_tcl {exec touch /tmp/should-not-exist}}}} -result {REMOTE 422 invalid_profile}
test import-7 {Tcl duplicate fields} -body {code {imp bad {profile_title A profile_title B}}} -result {REMOTE 422 invalid_profile}
test import-8 {path traversal} -body {code {imp ../bad $basic}} -result {REMOTE 422 invalid_filename}
test import-9 {unknown format} -body {code {imp bad $basic yaml}} -result {REMOTE 422 invalid_profile}
test import-10 {unknown JSON fields rejected} -body {code {imp bad [string map {{"version":2} {"invented":4,"version":2}} $native] json}} -result {REMOTE 422 invalid_profile}
test import-11 {duplicate JSON fields rejected} -body {code {imp bad [string map {{"version":2} {"version":2,"version":2}} $native] json}} -result {REMOTE 400 duplicate_field}
test import-12 {range rejected} -body {code {imp bad [string map {{"temperature":93} {"temperature":200}} $native] json}} -result {REMOTE 422 invalid_profile}
test import-13 {unknown step preserves no silent loss} -body {code {imp bad [string map {{"name":"注水"} {"unknown":1,"name":"注水"}} $native] json}} -result {REMOTE 422 invalid_profile}
test import-14 {invalid boolean} -body {code {imp bad $basic tcl overwrite yes}} -result {REMOTE 422 invalid_profile}
test import-15 {no native calls or current recipe mutations} -body {
 set ::settings(profile_filename) unchanged
 proc ::select_profile args {error "must not run"}
 proc ::save_settings args {error "must not run"}
 imp inert $basic
 set ::settings(profile_filename)
} -result unchanged
test import-16 {legacy overwrite remains} -body {
 ::plugins::decent_remote::profiles::upload 中文.tcl $basic
 dict get [::plugins::decent_remote::api::read_file $tmp/profiles/中文.tcl] profile_title
} -result 测试曲线
test import-17 {non-data Tcl rejected without executing} -body {code {imp bad {set ::owned 1}}} -result {REMOTE 422 invalid_profile}
test import-18 {missing JSON target remains missing} -body {
 set j [string map {{,"target_weight":45} {}} $native]
 imp no-target $j json
 dict exists [::plugins::decent_remote::api::read_file $tmp/profiles/no-target.tcl] final_desired_shot_weight_advanced
} -result 0
test import-19 {dangling symbolic link rejected} -body {
 set f [open $tmp/profiles/target.tcl w]; close $f
 file link -symbolic $tmp/profiles/link.tcl $tmp/profiles/target.tcl
 file delete $tmp/profiles/target.tcl
 code {imp link $basic tcl overwrite true}
} -result {REMOTE 422 invalid_profile}
test import-20 {blank title} -body {code {imp empty {profile_title {}}}} -result {REMOTE 422 invalid_profile}
test import-21 {bad exit enum} -body {code {imp badexit [string map {{"condition":"under"} {"condition":"bad"}} $native] json}} -result {REMOTE 422 invalid_profile}
test import-22 {duplicate step JSON keys} -body {code {imp duplicate-step [string map {{"flow":2} {"flow":2,"flow":3}} $native] json}} -result {REMOTE 400 duplicate_field}
# Pinned to classic 1.46.1.1 vars.tcl::profile_vars; no native code is sourced.
set nativeProfileKeys { advanced_shot espresso_temperature_steps_enabled author read_only read_only_backup espresso_hold_time preinfusion_time espresso_pressure espresso_decline_time pressure_end espresso_temperature espresso_temperature_0 espresso_temperature_1 espresso_temperature_2 espresso_temperature_3 settings_profile_type flow_profile_preinfusion flow_profile_preinfusion_time flow_profile_hold flow_profile_hold_time flow_profile_decline flow_profile_decline_time flow_profile_minimum_pressure preinfusion_flow_rate profile_notes final_desired_shot_volume final_desired_shot_weight final_desired_shot_weight_advanced tank_desired_water_temperature final_desired_shot_volume_advanced profile_title profile_language preinfusion_stop_pressure profile_hide final_desired_shot_volume_advanced_count_start beverage_type maximum_pressure maximum_pressure_range_advanced maximum_flow_range_advanced maximum_flow maximum_pressure_range_default maximum_flow_range_default insert_preinfusion_pause profile_grinder_dose_weight profile_grinder_setting}
test import-23 {every native saved profile key is allowlisted} -body {
 set missing {}
 foreach k $nativeProfileKeys {if {$k ni [::plugins::decent_remote::profiles::allowed]} {lappend missing $k}}
 set missing
} -result {}
test import-24 {legacy range and native identity metadata roundtrip} -body {
 set text [dict merge $basic {maximum_flow_range 0.6 maximum_pressure_range 0.6 profile_to_save 测试曲线}]
 imp legacy-fields $text
 set back [::plugins::decent_remote::api::read_file $tmp/profiles/legacy-fields.tcl]
 list [dict get $back maximum_flow_range] [dict get $back maximum_pressure_range] [dict get $back profile_to_save]
} -result {0.6 0.6 测试曲线}
test import-25 {legacy range must be numeric} -body {code {imp bad-range [dict merge $basic {maximum_flow_range nope}]}} -result {REMOTE 422 invalid_profile}
test import-26 {legacy range bounds remain enforced} -body {code {imp bad-range [dict merge $basic {maximum_pressure_range 99}]}} -result {REMOTE 422 invalid_profile}
test import-27 {similar arbitrary settings still rejected} -body {code {imp bad-range [dict merge $basic {maximum_flow_range_unknown 0.6}]}} -result {REMOTE 422 invalid_profile}
# Synthetic parameter export covering legacy fields and full advanced-stage input.
# Test data only; not a brewing recommendation or a user profile.
set syntheticExport {advanced_shot {{exit_if 1 volume 500 max_flow_or_pressure_range 0.4 transition fast popup {} exit_flow_under 0 temperature 91.0 weight 22.0 name {test pressure step} pressure 8.4 pump pressure sensor coffee exit_type flow_under exit_flow_over 0 exit_pressure_over 0 max_flow_or_pressure 8.0 seconds 11.00 exit_pressure_under 0} {flow 1.8 exit_if 1 volume 500 max_flow_or_pressure_range 0.4 transition fast popup {} exit_flow_under 0 temperature 87.0 weight 0.0 name {test flow step} pressure 8.4 pump flow sensor coffee exit_type flow_under exit_flow_over 0 exit_pressure_over 0 max_flow_or_pressure 8.0 seconds 45 exit_pressure_under 0}}
author {Decent Remote tests}
beverage_type espresso
espresso_decline_time 60
espresso_hold_time 12
espresso_pressure 9.0
espresso_temperature 91.0
espresso_temperature_0 91.0
espresso_temperature_1 91.0
espresso_temperature_2 91.0
espresso_temperature_3 91.0
espresso_temperature_steps_enabled 0
final_desired_shot_volume 0
final_desired_shot_volume_advanced 0
final_desired_shot_volume_advanced_count_start 0
final_desired_shot_weight 76
final_desired_shot_weight_advanced 76
flow_profile_decline 1
flow_profile_decline_time 23
flow_profile_hold 1.8
flow_profile_hold_time 0
flow_profile_minimum_pressure 6
flow_profile_preinfusion 4.2
flow_profile_preinfusion_time 6
maximum_flow 0
maximum_flow_range 0.6
maximum_flow_range_advanced 0.4
maximum_flow_range_default 1.0
maximum_pressure 0
maximum_pressure_range 0.6
maximum_pressure_range_advanced 0.9
maximum_pressure_range_default 0.9
original_profile_title {测试曲线}
preinfusion_flow_rate 4
preinfusion_guarantee 0
preinfusion_stop_pressure 4.0
preinfusion_time 0
pressure_end 7.7
profile_filename Test_Two_Stage
profile_language zh-hans
profile_notes {Synthetic parser fixture. Values exercise legacy field preservation; do not brew this test profile.}
profile_title {测试曲线}
profile_to_save {测试曲线}
settings_profile_type settings_2c
tank_desired_water_temperature 0
profile_grinder_dose_weight 18
read_only 0
profile_hide 0
}
test import-28 {synthetic full-profile dry-run without rewriting parameters} -body {
 set result [imp Test_Two_Stage.tcl $syntheticExport tcl dry_run true]
 list [dict get $result saved] [dict get $result title] [file exists $tmp/profiles/Test_Two_Stage.tcl] [expr {[::plugins::decent_remote::profiles::validate $syntheticExport] eq $syntheticExport}]
} -result {0 测试曲线 0 1}
test import-29 {full profile may pass legacy upload and native save validator} -body {
 ::plugins::decent_remote::profiles::upload Test_Two_Stage.tcl $syntheticExport
 set text [::plugins::decent_remote::api::read_file $tmp/profiles/Test_Two_Stage.tcl]
 list [dict get [::plugins::decent_remote::profiles::validate $text] profile_to_save] [dict get $text maximum_flow_range] [llength [dict get $text advanced_shot]]
} -result {测试曲线 0.6 2}
removeDirectory $tmp
cleanupTests
