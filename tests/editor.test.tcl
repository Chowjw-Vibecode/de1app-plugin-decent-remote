package require tcltest
namespace import ::tcltest::*
set testdir [file dirname [info script]]
foreach component {core profiles adapter editor} {source [file join $testdir .. $component.tcl]}
set ::testroot [makeDirectory editor-data]
file mkdir [file join $::testroot profiles] [file join $::testroot profiles_v2]
set f [open [file join $testdir fixtures filter3.tcl] r]; fconfigure $f -encoding utf-8
set ::fixture [read $f]; close $f
proc profile_vars {} {return [dict keys $::fixture]}
proc homedir {} {return $::testroot}
proc write_utf8 {path contents} {set f [open $path w]; fconfigure $f -encoding utf-8; puts -nonewline $f $contents; close $f}
namespace eval ::profile {
    proc sync_from_legacy {} {lappend ::calls sync}
    proc save {filename} {write_utf8 $filename [::json::write object title [::json::write string $::settings(profile_title)]]; return 1}
}
namespace eval ::device::scale {proc expecting_present {} {return 1}}
proc save_settings {} {lappend ::calls save_settings}
proc send_de1_settings_soon {} {lappend ::calls send}
proc translate {v} {return $v}
proc streamline_set_drink_weight {v} {
    lappend ::calls [list weight $v]
    set ::settings(final_desired_shot_weight) $v
    set ::settings(final_desired_shot_weight_advanced) $v
    set ::settings(final_desired_shot_volume) 0
    set ::settings(final_desired_shot_volume_advanced) 0
}
proc change_espresso_temperature {delta} {lappend ::calls [list change_temperature $delta]}
proc select_profile {root} {
    lappend ::calls [list select $root]
    set file [file join [homedir] profiles $root.tcl]
    if {![file exists $file]} {return -1}
    array set ::settings [::plugins::decent_remote::api::read_file $file]
    set ::settings(profile_filename) $root
    set ::settings(profile_has_changed) 0
    send_de1_settings_soon
}
proc copy_settings_from_profile_to_streamline {} {
    lappend ::calls copy_to_skin
    set ::settings(grinder_dose_weight) $::settings(profile_grinder_dose_weight)
}
proc save_profile {{saved_msg 1}} {
    lappend ::calls [list save_profile $saved_msg]
    set data {}
    foreach k [profile_vars] {if {[info exists ::settings($k)]} {dict set data $k $::settings($k)}}
    write_utf8 [file join [homedir] profiles $::settings(profile_filename).tcl] $data
    ::profile::save [file join [homedir] profiles_v2 $::settings(profile_filename).json]
    set ::settings(profile_has_changed) 0
}
proc refresh_favorite_profile_button_labels {} {lappend ::calls refresh_profiles}
proc refresh_favorite_dosebev_button_labels {} {lappend ::calls refresh_doses}
proc refresh_favorite_temperature_button_labels {} {lappend ::calls refresh_temperatures}
proc reset {} {
    array unset ::settings
    array set ::settings $::fixture
    array set ::settings {skin Streamline profile_title Current profile_filename current original_profile_title Current read_only 0 grinder_dose_weight 22 profile_has_changed 0 insert_preinfusion_pause 0}
    set ::settings(favorite_profiles) [dict create selected {number 1} 1 {name current title Current} 2 {name other title Other} 3 {name {} title { }} 4 {name {} title { }} 5 {name {} title { }}]
    set ::settings(favorite_dosebevs) {1 {value 15 value2 30} 2 {value 16 value2 32} 3 {value 18 value2 36} 4 {value 20 value2 40}}
    set ::settings(favorite_temperatures) {1 {value 75} 2 {value 80} 3 {value 85} 4 {value 90}}
    array unset ::de1
    array set ::de1 {device_handle ble1 state 2 substate 0}
    array set ::de1_num_state {0 Sleep 2 Idle 4 Espresso}
    set ::globals(widget_profile_name_to_save) .entry
    set ::plugins::decent_remote::api::root $::testroot
    set current [dict merge $::fixture {profile_title Current read_only 0}]
    write_utf8 [file join $::testroot profiles current.tcl] $current
    write_utf8 [file join $::testroot profiles other.tcl] [dict merge $::fixture {profile_title Other}]
    foreach filename {copy.tcl 中文.tcl} {file delete -force [file join $::testroot profiles $filename]}
    foreach filename {copy.json 中文.json} {file delete -force [file join $::testroot profiles_v2 $filename]}
    set ::calls {}
}
proc edit {method args} {::plugins::decent_remote::device::$method {*}$args}
proc errorcode {script} {catch {uplevel 1 $script} result opts; dict get $opts -errorcode}
proc one_step {{flow 4}} {return [dict create pump flow flow $flow sensor coffee transition fast temperature 92 seconds 10]}
proc patch_steps {steps {extras {}}} {edit profile_patch [dict merge {volume_count_start 0} $extras [dict create steps $steps]]}

test source-1 {source is inert} -body {reset; source [file join $testdir .. editor.tcl]; set ::calls} -result {}
test current-1 {full advanced profile is readable without commands} -body {reset; set r [edit profile_current]; list [dict get $r profile] [dict get $r editable_steps] [llength [dict get $r steps]] $::calls} -result {current 1 7 {}}
test current-2 {basic curve does not present stale advanced stages as editable} -body {reset; set ::settings(settings_profile_type) settings_2a; set r [edit profile_current]; list [dict get $r editable_steps] [dict get $r steps] [dict get $r volume_count_start]} -result {0 {} {}}
test patch-1 {complete stages normalized and temporarily sent without file write} -body {
    reset; set before [::plugins::decent_remote::api::read_file [file join $::testroot profiles current.tcl]]
    set r [patch_steps [list [one_step]] {dose_g 19 yield_g 100}]
    set step [lindex $::settings(advanced_shot) 0]
    list [dict get $r temporary] [dict get $r current_profile dose_g] [dict get $step flow] [dict get $step exit_if] [dict get $step volume] $::settings(espresso_temperature) $::calls [expr {$before eq [::plugins::decent_remote::api::read_file [file join $::testroot profiles current.tcl]]}]
} -result {1 19 4 0 0 92 {{weight 100} sync send} 1}
test patch-2 {sensor pressure limiter and conditional exit preserved} -body {
    reset
    set step [dict merge [one_step] {pump pressure pressure 8.6 sensor water max_flow_or_pressure 8 max_flow_or_pressure_range 0.5 exit_if true exit_type flow_under exit_flow_under 1.5 weight 24}]
    patch_steps [list $step]
    set actual [lindex $::settings(advanced_shot) 0]
    list [dict get $actual pump] [dict get $actual pressure] [dict get $actual sensor] [dict get $actual weight] [dict get $actual exit_if] [dict get $actual exit_flow_under]
} -result {pressure 8.6 water 24 1 1.5}
test patch-3 {unknown step field blocked before any mutation} -body {
    reset; set old $::settings(advanced_shot)
    list [errorcode {patch_steps [list [dict merge [one_step] {script {start_espresso}}]]}] [expr {$old eq $::settings(advanced_shot)}] $::calls
} -result {{REMOTE 422 unknown_field} 1 {}}
test patch-4 {single-stage duration bounded to native 127 seconds} -body {reset; list [errorcode {patch_steps [list [dict merge [one_step] {seconds 180}]]}] $::calls} -result {{REMOTE 422 invalid_value} {}}
test patch-5 {conditional exit requires explicit matching threshold} -body {reset; errorcode {patch_steps [list [dict merge [one_step] {exit_if true exit_type pressure_over}]]}} -result {REMOTE 422 missing_field}
test patch-6 {invalid enum} -body {reset; errorcode {patch_steps [list [dict merge [one_step] {sensor scale}]]}} -result {REMOTE 422 invalid_value}
test patch-7 {step volume bounded to firmware U10} -body {reset; errorcode {patch_steps [list [dict merge [one_step] {volume 1024}]]}} -result {REMOTE 422 invalid_value}
test patch-8 {empty stages refused} -body {reset; errorcode {patch_steps {}}} -result {REMOTE 422 invalid_steps}
test patch-9 {invalid numeric prevents dose mutation} -body {reset; list [errorcode {patch_steps [list [dict merge [one_step] {flow NaN}]] {dose_g 19}}] $::settings(grinder_dose_weight) $::calls} -result {{REMOTE 422 invalid_value} 22 {}}
test patch-10 {complete stages and global temp must agree} -body {reset; errorcode {patch_steps [list [one_step]] {temperature_c 93}}} -result {REMOTE 422 conflicting_temperature}
test patch-11 {changing global temperature preserves offsets using native chain} -body {
    reset; edit profile_patch {temperature_c 95}
    list $::settings(espresso_temperature) [dict get [lindex $::settings(advanced_shot) end] temperature] $::calls
} -result {95 89.0 {{change_temperature 1.0} sync send}}
test patch-12 {volume target can be explicitly combined with scale target} -body {reset; edit profile_patch {yield_g 100 target_volume_ml 150}; list $::settings(final_desired_shot_weight_advanced) $::settings(final_desired_shot_volume_advanced)} -result {100 150}
test patch-13 {volume start must remain valid after shortening stages} -body {reset; errorcode {edit profile_patch [dict create steps [list [one_step]]]}} -result {REMOTE 422 invalid_value}
test patch-14 {twenty stages plus native extra pause refused} -body {reset; set ::settings(insert_preinfusion_pause) 1; errorcode {patch_steps [lrepeat 20 [one_step]]}} -result {REMOTE 422 too_many_steps}
test patch-15 {basic profile is not silently converted by stage edit} -body {reset; set ::settings(settings_profile_type) settings_2a; list [errorcode {patch_steps [list [one_step]]}] $::settings(settings_profile_type) $::calls} -result {{REMOTE 422 advanced_profile_required} settings_2a {}}
test patch-16 {active machine rejects edits} -body {reset; set ::de1(state) 4; list [errorcode {edit profile_patch {dose_g 19}}] $::calls} -result {{REMOTE 409 busy} {}}
test patch-17 {scripted current profiles refused} -body {reset; set ::settings(advanced_shot_tcl) {start_espresso}; list [errorcode {edit profile_patch {dose_g 19}}] $::calls} -result {{REMOTE 422 executable_profile} {}}
test patch-18 {sync failure restores memory and does not send} -body {
    reset; rename ::profile::sync_from_legacy ::profile::saved_sync
    proc ::profile::sync_from_legacy {} {error failed}
    set result [errorcode {edit profile_patch {dose_g 19}}]
    rename ::profile::sync_from_legacy {}; rename ::profile::saved_sync ::profile::sync_from_legacy
    list $result $::settings(grinder_dose_weight) $::calls
} -result {{REMOTE 500 apply_failed} 22 {}}
test restore-1 {restore follows native select and copies dose from saved profile} -body {reset; edit profile_patch {dose_g 19}; set ::calls {}; set r [edit profile_restore {}]; list $::settings(grinder_dose_weight) $::calls [dict get $r current_profile dirty]} -result {22 {{select current} send copy_to_skin save_settings} 0}
test save-1 {explicit save writes native Tcl and JSON and reads both back} -body {
    reset; edit profile_patch {dose_g 19 yield_g 100}; set ::calls {}; set r [edit profile_save {}]
    set raw [::plugins::decent_remote::api::read_file [file join $::testroot profiles current.tcl]]
    list [dict get $r saved] [dict get $raw profile_grinder_dose_weight] [dict get $r readback] $::calls
} -result {1 19 files {sync {save_profile 0} save_settings send}}
test save-2 {read-only originals require save-as} -body {reset; set ::settings(read_only) 1; list [errorcode {edit profile_save {}}] $::calls} -result {{REMOTE 409 read_only_profile} {}}
test save-3 {save-as selects explicit name without modifying original file} -body {
    reset; set before [::plugins::decent_remote::api::read_file [file join $::testroot profiles current.tcl]]
    set ::settings(read_only) 1
    set r [edit profile_save_as {filename 中文.tcl title 测试曲线}]
    list [dict get $r filename] $::settings(profile_filename) $::settings(profile_title) $::settings(read_only) [expr {$before eq [::plugins::decent_remote::api::read_file [file join $::testroot profiles current.tcl]]}]
} -result {中文.tcl 中文 测试曲线 0 1}
test save-4 {existing file cannot be overwritten by save-as} -body {reset; list [errorcode {edit profile_save_as {filename other.tcl title New}}] $::calls $::settings(profile_filename)} -result {{REMOTE 409 profile_exists} {} current}
test save-5 {orphaned JSON also prevents collision} -body {reset; write_utf8 [file join $::testroot profiles_v2 copy.json] {{}}; errorcode {edit profile_save_as {filename copy.tcl title Copy}}} -result {REMOTE 409 profile_exists}
test save-6 {traversal refused} -body {reset; errorcode {edit profile_save_as {filename ../outside.tcl title Copy}}} -result {REMOTE 422 invalid_filename}
test save-7 {empty title refused} -body {reset; errorcode {edit profile_save_as {filename copy.tcl title { }}}} -result {REMOTE 422 invalid_value}
test save-8 {native reserved saved label refused} -body {reset; errorcode {edit profile_save_as {filename copy.tcl title Saved}}} -result {REMOTE 422 invalid_value}
test save-9 {missing native save UI support fails before settings mutation} -body {reset; unset ::globals(widget_profile_name_to_save); list [errorcode {edit profile_save_as {filename copy.tcl title Copy}}] $::settings(profile_filename) $::calls} -result {{REMOTE 501 unsupported} current {}}
test save-10 {native partial failure is unknown, not false successful rollback} -body {
    reset; rename save_profile saved_native_save
    proc save_profile {args} {error "native storage error"}
    set result [errorcode {edit profile_save_as {filename copy.tcl title Copy}}]
    rename save_profile {}; rename saved_native_save save_profile
    list $result $::settings(profile_filename)
} -result {{REMOTE 502 save_unknown} copy}
test favorites-1 {read five slots without changing profile} -body {reset; set r [edit favorites_get]; list [llength [dict get $r slots]] [dict get $r selected_slot] $::calls} -result {5 1 {}}
test favorites-2 {reorder preserving selection to avoid native delayed select} -body {
    reset; set r [edit favorites_patch {slots {{slot 1 profile other} {slot 2 profile current}}}]
    list [dict get $r favorites selected_slot] $::settings(profile_filename) [dict get $::settings(favorite_profiles) 1 name] $::calls
} -result {2 current other {refresh_profiles save_settings}}
test favorites-3 {clear is a blank button, does not select any other curve} -body {reset; edit favorites_patch {slots {{slot 1 profile {}}}}; list [dict get $::settings(favorite_profiles) 1 title] [dict get $::settings(favorite_profiles) selected number] $::settings(profile_filename)} -result {{ } 0 current}
test favorites-4 {duplicate root/title refused atomically} -body {reset; list [errorcode {edit favorites_patch {slots {{slot 3 profile other}}}}] [dict get $::settings(favorite_profiles) 3 name] $::calls} -result {{REMOTE 422 duplicate_profile} {} {}}
test favorites-5 {invalid file does not mutate earlier slot} -body {reset; list [errorcode {edit favorites_patch {slots {{slot 1 profile {}} {slot 2 profile missing}}}}] [dict get $::settings(favorite_profiles) 1 name] $::calls} -result {{REMOTE 404 profile_not_found} current {}}
test favorites-6 {duplicate slot refused} -body {reset; errorcode {edit favorites_patch {slots {{slot 1 profile {}} {slot 1 profile other}}}}} -result {REMOTE 422 duplicate_slot}
test favorites-7 {unsupported skin explicit 501} -body {reset; rename refresh_favorite_profile_button_labels saved_refresh; set result [errorcode {edit favorites_get}]; rename saved_refresh refresh_favorite_profile_button_labels; set result} -result {REMOTE 501 unsupported}
test shortcuts-1 {reads four paired and four temperature values} -body {reset; set r [edit shortcuts_get]; list [llength [dict get $r dose_yield]] [dict get [lindex [dict get $r dose_yield] 2] dose_g] [dict get [lindex [dict get $r temperatures] 3] temperature_c] $::calls} -result {4 18 90 {}}
test shortcuts-2 {writes presets without applying them to recipe} -body {reset; edit shortcuts_patch {dose_yield {{slot 1 dose_g 19 yield_g 100}} temperatures {{slot 4 temperature_c 92}}}; list [dict get $::settings(favorite_dosebevs) 1 value2] [dict get $::settings(favorite_temperatures) 4 value] $::settings(grinder_dose_weight) $::settings(espresso_temperature) $::calls} -result {100 92 22 94.0 {refresh_doses refresh_temperatures save_settings}}
test shortcuts-3 {all shortcut groups validated before mutation} -body {reset; list [errorcode {edit shortcuts_patch {dose_yield {{slot 1 dose_g 19 yield_g 100}} temperatures {{slot 4 temperature_c 999}}}}] [dict get $::settings(favorite_dosebevs) 1 value] $::calls} -result {{REMOTE 422 invalid_value} 15 {}}
test shortcuts-4 {unknown and incomplete fields refused} -body {reset; list [errorcode {edit shortcuts_patch {temperatures {{slot 1 temperature_c 93 calibration 1}}}}] [errorcode {edit shortcuts_patch {dose_yield {{slot 1 dose_g 19}}}}]} -result {{REMOTE 422 unknown_field} {REMOTE 422 missing_field}}
test shortcuts-5 {out of range slot refused} -body {reset; errorcode {edit shortcuts_patch {temperatures {{slot 5 temperature_c 93}}}}} -result {REMOTE 422 invalid_value}
test no-start {no editor path invokes machine or grinder starts} -body {reset; edit profile_patch {dose_g 19}; edit profile_save {}; edit shortcuts_patch {temperatures {{slot 4 temperature_c 92}}}; expr {![regexp {start_|begin|set_flow_multiplier} $::calls]}} -result 1
removeDirectory $::testroot
cleanupTests
