package require tcltest
namespace import ::tcltest::*
source [file join [file dirname [info script]] .. adapter.tcl]
proc reset {} {
    array unset ::settings
    array set ::settings {settings_profile_type settings_2a espresso_temperature 92 espresso_temperature_steps_enabled 1 espresso_temperature_0 92 espresso_temperature_1 91 espresso_temperature_2 90 espresso_temperature_3 89 grinder_dose_weight 18 profile_grinder_dose_weight 18 final_desired_shot_weight 36 final_desired_shot_weight_advanced 36 phase_1_flow_rate 20 phase_2_flow_rate 40 hot_water_idle_temp 990 espresso_warmup_timeout 10 screen_saver_delay 60 app_brightness 70 saver_brightness 0}
    array unset ::de1
    array set ::de1 {device_handle ble1 scale_device_handle ble2 state 2 substate 0}
    array set ::de1_num_state {0 Sleep 2 Idle 4 Espresso}
    set ::calls {}; set ::ghc 0
    set ::settings(skin) Streamline
}
namespace eval ::profile {proc sync_from_legacy {} {lappend ::calls sync}}
namespace eval ::device::scale {proc expecting_present {} {return 1}; proc tare {} {lappend ::calls tare}}
proc change_espresso_temperature {delta} {
    foreach key {espresso_temperature espresso_temperature_0 espresso_temperature_1 espresso_temperature_2 espresso_temperature_3} {set ::settings($key) [expr {$::settings($key)+$delta}]}
}
proc streamline_set_drink_weight {v} {set ::settings(final_desired_shot_weight) $v; set ::settings(final_desired_shot_weight_advanced) $v; set ::settings(final_desired_shot_volume) 0; set ::settings(final_desired_shot_volume_advanced) 0}
foreach cmd {send_de1_settings_soon save_settings set_heater_tweaks delay_screen_saver start_idle start_sleep start_espresso start_flush start_steam start_water} {
    proc ::$cmd {} [list lappend ::calls $cmd]
}
proc display_brightness {v} {lappend ::calls [list brightness $v]}
proc ghc_required {} {return $::ghc}
proc invoke {op {payload {}}} {::plugins::decent_remote::device::call $op $payload}
proc errorcode {script} {catch {uplevel 1 $script} result opts; dict get $opts -errorcode}

test source-1 {source does not start equipment} -body {reset; source [file join [file dirname [info script]] .. adapter.tcl]; set ::calls} -result {}
test status-1 {status has no credentials or connection handles} -body {reset; set ::settings(password) secret; set s [invoke status]; expr {[string first secret $s]<0 && [string first ble1 $s]<0 && [dict get $s state] eq "Idle"}} -result 1
test recipe-1 {combine and preserve temperature offsets without saving curve} -body {reset; set r [invoke recipe.patch {dose_g 20 yield_g 40 temperature_c 94}]; list $::settings(espresso_temperature_3) $::settings(grinder_dose_weight) $::settings(final_desired_shot_weight_advanced) $::calls [dict get $r device_confirmed]} -result {91 20 40 {sync send_de1_settings_soon} 0}
test recipe-2 {validate entire request before mutation} -body {reset; list [errorcode {invoke recipe.patch {dose_g 21 temperature_c 106}}] $::settings(grinder_dose_weight) $::calls} -result {{REMOTE 422 invalid_value} 18 {}}
test recipe-3 {reject offset clipping} -body {reset; set ::settings(espresso_temperature_3) 104; list [errorcode {invoke recipe.patch {temperature_c 94}}] $::calls} -result {{REMOTE 422 invalid_value} {}}
test recipe-4 {missing native method fails before mutation} -body {reset; rename ::send_de1_settings_soon ::saved_sender; set result [errorcode {invoke recipe.patch {dose_g 20}}]; rename ::saved_sender ::send_de1_settings_soon; list $result $::settings(grinder_dose_weight)} -result {{REMOTE 501 unsupported} 18}
test disconnected-1 {no command while disconnected} -body {reset; set ::de1(device_handle) 0; list [errorcode {invoke machine.wake}] $::calls} -result {{REMOTE 409 disconnected} {}}
test busy-1 {busy recipe fails} -body {reset; set ::de1(state) 4; list [errorcode {invoke recipe.patch {dose_g 20}}] $::calls} -result {{REMOTE 409 busy} {}}
test ghc-1 {removed espresso start rejects before native control} -body {reset; set ::ghc 1; list [errorcode {invoke machine.espresso}] $::calls} -result {{REMOTE 403 start_disabled} {}}
test busy-2 {stop remains possible during extraction} -body {reset; set ::de1(state) 4; set r [invoke machine.stop]; list [dict get $r accepted] $::calls [dict get $r device_confirmed]} -result {1 start_idle 0}
test stop-idle-sleep {stop never wakes or re-enters an inactive machine} -body {
    reset; set actions {}
    foreach state {2 0} {set ::de1(state) $state; lappend actions [dict get [invoke machine.stop] action]}
    list $actions $::calls
} -result {{not_needed not_needed} {}}
test settings-1 {public units read back and write cached firmware units} -body {reset; set r [invoke settings.patch {preheat_phase1_flow_ml_s 3 idle_temperature_c 95 sleep_timeout_minutes 20}]; list $::settings(phase_1_flow_rate) $::settings(hot_water_idle_temp) $::settings(screen_saver_delay) [dict get $r settings idle_temperature_c] $::calls} -result {30 950 20 95.0 {set_heater_tweaks delay_screen_saver save_settings}}
test settings-2 {reject unknown fields and infinity} -body {reset; list [errorcode {invoke settings.patch {password test}}] [errorcode {invoke settings.patch {awake_brightness Inf}}] $::calls} -result {{REMOTE 422 unknown_field} {REMOTE 422 invalid_value} {}}
test tare-1 {tare uses native method} -body {reset; invoke scale.tare; set ::calls} -result tare
test grinder-1 {missing plugin has explicit unsupported response} -body {reset; errorcode {invoke grinder.start}} -result {REMOTE 501 unsupported}
test settings-3 {timeout uses tenths of a second} -body {reset; invoke settings.patch {preheat_timeout_s 2.5}; list $::settings(espresso_warmup_timeout) [dict get [invoke settings.get] preheat_timeout_s]} -result {25 2.5}
test settings-4 {device bounds and integer precision} -body {reset; list [errorcode {invoke settings.patch {preheat_phase1_flow_ml_s 6.1}}] [errorcode {invoke settings.patch {idle_temperature_c 95.1}}] [errorcode {invoke settings.patch {sleep_timeout_minutes 0.5}}]} -result {{REMOTE 422 invalid_value} {REMOTE 422 invalid_precision} {REMOTE 422 invalid_precision}}
test settings-5 {awake brightness uses native platform chain} -body {reset; invoke settings.patch {awake_brightness 65}; set ::calls} -result {{brightness 65} save_settings}
test settings-6 {sleep brightness applies only while sleeping} -body {reset; set ::de1(state) 0; invoke settings.patch {sleep_brightness 5}; set ::calls} -result {{brightness 5} save_settings}
test recipe-5 {failed in-memory native conversion restores snapshot before sender} -body {
    reset
    rename ::profile::sync_from_legacy ::profile::saved_sync
    proc ::profile::sync_from_legacy {} {error "mock conversion failure"}
    set code [errorcode {invoke recipe.patch {dose_g 20 yield_g 40}}]
    rename ::profile::sync_from_legacy {}; rename ::profile::saved_sync ::profile::sync_from_legacy
    list $code $::settings(grinder_dose_weight) $::settings(final_desired_shot_weight) $::calls
} -result {{REMOTE 500 apply_failed} 18 36 {}}
test recipe-6 {advanced step temperatures validated before any mutation} -body {
    reset; set ::settings(settings_profile_type) settings_2c; set ::settings(advanced_shot) {{temperature 92} {temperature 104}}
    list [errorcode {invoke recipe.patch {temperature_c 94}}] $::calls
} -result {{REMOTE 422 invalid_value} {}}
test grinder-2 {uses existing control chain and no direct BLE write} -body {
    reset
    namespace eval ::plugins::crystal_grinder {
        variable connected 1; variable initialized 1; variable operation {}
        proc begin {kind} {lappend ::calls [list crystal_begin $kind]}
    }
    invoke grinder.start; invoke grinder.stop; set ::calls
} -result {{crystal_begin start} {crystal_begin stop}}
test plugin-state {peeked namespace is not a running plugin} -body {
    reset
    set ::plugins::crystal_grinder::plugin_loaded 0
    set a [dict get [invoke plugins.status] crystal_grinder]
    set ::settings(enabled_plugins) crystal_grinder
    set ::plugins::crystal_grinder::plugin_loaded 1
    set b [dict get [invoke plugins.status] crystal_grinder]
    list [dict get $a loaded] [dict get $a enabled] [dict get $b loaded] [dict get $b enabled]
} -result {0 0 1 1}
test legacy-1 {old summary field shape for sleep and idle} -body {
    reset; set ::settings(espresso_count) 12; set ::settings(steaming_count) 3
    set idle [invoke legacy.status]; set ::de1(state) 0
    list $idle [invoke legacy.status]
} -result {{is_active true espresso_count 12 steaming_count 3} {is_active false}}
test legacy-2 {power-on during espresso cannot stop shot} -body {
    reset; set ::de1(state) 4
    list [errorcode {invoke legacy.power {active true}}] $::calls
} -result {{REMOTE 409 busy} {}}
test legacy-3 {already awake is idempotent; sleeping uses native chain} -body {
    reset; invoke legacy.power {active true}; set idle_calls $::calls
    invoke legacy.power {active false}; list $idle_calls $::calls
} -result {{} start_sleep}
test legacy-4 {DYE missing dependency and invalid timestamp are explicit} -body {
    reset; list [errorcode {invoke legacy.dye.next {timestamp 123}}] [errorcode {invoke legacy.dye.next {timestamp {1;start_espresso}}}]
} -result {{REMOTE 501 unsupported} {REMOTE 422 invalid_timestamp}}
namespace eval ::plugins::DYE::shots {
    proc source_next_from {stamp unused fields} {lappend ::calls [list dye $stamp $unused $fields]}
}
set ::plugins::DYE::plugin_loaded 1
test legacy-5 {DYE uses complete original field selection} -body {
    reset; invoke legacy.dye.next {timestamp 1234567890}; set ::calls
} -result {{dye 1234567890 {} {workflow_settings shot_profile ratio drink_weight grinder_dose_weight grinder_setting grinder_model workflow bean_brand bean_type roast_date roast_level bean_notes}}}
namespace eval ::plugins::SDB {variable plugin_loaded 1; proc shots {pattern} {return {clock {1 2} grinder_setting {4} bean_notes {{line1
line2}}}}}
test legacy-6 {missing SDB columns remain blank and no row is dropped} -body {
    reset; set rows [invoke legacy.sdb]
    list [llength $rows] [dict size [lindex $rows 0]] [dict get [lindex $rows 1] clock] [dict get [lindex $rows 1] grinder_setting] [dict get [lindex $rows 0] filename]
} -result {2 16 2 {} {}}
test optional-plugin-disabled {peeked SDB and DYE do not run uninitialized methods} -body {
    reset
    set ::plugins::SDB::plugin_loaded 0;set ::plugins::DYE::plugin_loaded 0
    set result [list [errorcode {invoke legacy.sdb}] [errorcode {invoke legacy.dye.next {timestamp 1234567890}}] $::calls]
    set ::plugins::SDB::plugin_loaded 1;set ::plugins::DYE::plugin_loaded 1
    set result
} -result {{REMOTE 501 plugin_disabled} {REMOTE 501 plugin_disabled} {}}
proc battery_percent {} {return 80}
proc ::profile::filename_from_title {title} {return $title}
proc water_tank_level_to_milliliters {v} {expr {$v * 10}}
test legacy-7 {details retains idle metadata fields with missing values} -body {
    reset; set ::de1(water_level) 10; set ::de1(head_temperature) 92.999
    set r [invoke legacy.details]
    list [dict get $r state] [dict get $r battery_percent] [dict get $r head_temperature] [dict get $r water_level_ml] [dict exists $r bean_notes]
} -result {Idle 80 92.99 100 1}
foreach key {espresso_elapsed espresso_pressure espresso_weight espresso_flow espresso_flow_weight espresso_temperature_basket espresso_temperature_mix} {proc ::$key {args} {return {1.0 2.0}}}
test legacy-8 {details returns all espresso vectors as Tcl lists} -body {
    reset; set ::de1(state) 4; set r [invoke legacy.details]
    list [dict get $r espresso_elapsed] [dict get $r espresso_temperature_mix]
} -result {{1.0 2.0} {1.0 2.0}}
namespace eval ::logging {proc flush_log {} {lappend ::calls flush_log}}
test legacy-9 {log flush uses native logging method} -body {reset; invoke legacy.flush; set ::calls} -result flush_log
set ::profile_test_dir [makeDirectory adapter-profiles]
file mkdir $::profile_test_dir/profiles
proc homedir {} {return $::profile_test_dir}
proc select_profile {root} {lappend ::calls select_profile}
proc copy_settings_from_profile_to_streamline {} {lappend ::calls sync_streamline}
set f [open $::profile_test_dir/profiles/code.tcl w]; puts $f {advanced_shot_tcl {start_espresso}}; close $f
set f [open $::profile_test_dir/profiles/safe.tcl w]; puts $f {profile_title safe advanced_shot_tcl {}}; close $f
test profile-1 {embedded executable Tcl rejected before native selection} -body {
    reset; list [errorcode {invoke profile.select {filenameroot code}}] $::calls
} -result {{REMOTE 422 executable_profile} {}}
test profile-2 {safe profile uses native selection and Streamline synchronization} -body {
    reset; invoke profile.select {filenameroot safe}; set ::calls
} -result {select_profile sync_streamline save_settings}
test profile-3 {payload cannot write arbitrary settings} -body {
    reset; list [errorcode {invoke profile.select {filenameroot safe password injected}}] $::calls
} -result {{REMOTE 422 unknown_field} {}}
removeDirectory adapter-profiles
cleanupTests
