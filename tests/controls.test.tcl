package require tcltest
namespace import ::tcltest::*
set here [file dirname [info script]]
source [file join $here .. adapter.tcl]
set ::calls {}
source [file join $here .. controls.tcl]
namespace import ::plugins::decent_remote::device::*
proc run {command args} {::plugins::decent_remote::device::$command {*}$args}
proc ec {script} {catch {uplevel 1 $script} e opts; dict get $opts -errorcode}
namespace eval ::device::scale {variable autotare_states {Espresso HotWater}}
proc reset {} {
    set ::calls {}; set ::savefail 0; set ::flowbusy 0
    set ::plugins::flow_lut::plugin_loaded 1
    array unset ::settings
    array set ::settings {enabled_plugins flow_lut flush_flow 6 flush_seconds 5 hotwater_flow 8 water_temperature 85 water_volume 50 water_time_max 60 steam_flow 150 steam_temperature 160 steam_timeout 120 steam_disabled 0 water_stop_on_scale 1 start_espresso_only_if_scale_connected 1 stop_weight_before_seconds 0.15 keep_scale_on 1 scheduler_enable 0 scheduler_wake 25200 scheduler_sleep 32400 smart_battery_charging 1 profile_filename Filter3_15g profile_title {Filter3 15g}}
    array unset ::de1
    array set ::de1 {device_handle ble1 scale_device_handle ble2 state 2 substate 0 usb_charger_on 1 scale_weight 5 scale_weight_rate 1}
    array set ::de1_num_state {0 Sleep 2 Idle 4 Espresso}
}
proc save_settings {} {lappend ::calls save; if {$::savefail} {error disk_failure}}
foreach method {set_flush_flow_rate set_flush_timeout set_hotwater_flow_rate set_steam_flow} {
    proc ::$method {value} "lappend ::calls \[list $method \$value\]"
}
proc de1_send_steam_hotwater_settings {} {lappend ::calls native_bundle}
proc next_alarm_time {seconds} {expr {1800000000 + $seconds}}
proc set_alarms_for_de1_wake_sleep {} {lappend ::calls schedule_future}
proc battery_percent {} {return 70}
proc check_battery_charger {} {lappend ::calls smart_policy; set ::de1(usb_charger_on) 1}
proc set_usb_charger_on {v} {lappend ::calls [list usb $v];set ::de1(usb_charger_on) $v}
namespace eval ::plugins::flow_lut {
    proc ensure_free {} {if {$::flowbusy} {error "测试尚未结束"}}
    proc idle {} {}
}
namespace eval ::flow_lut_send {
    variable enabled 0; variable installed 1; variable target_file Filter3_15g
    variable target_title {Filter3 15g}; variable map_id example_map; variable last {}
    proc toggle {} {variable enabled;set enabled [expr {!$enabled}];lappend ::calls native_flow_toggle}
}
test controls-source {module source is inert} -body {reset;source [file join $here .. controls.tcl];set ::calls} -result {}
test controls-get {real units and scale weight semantics} -body {reset;set r [run control_get];list [dict get $r steam_flow_ml_s] [dict get $r hotwater_target_unit] [dict get $r firmware_hotwater_volume_ml] [dict get $r steam_zero_timeout_s]} -result {1.5 g 250 255}
test controls-volume {connected scale with stop disabled retains native firmware250 limit} -body {reset;set ::settings(water_stop_on_scale) 0;set r [run control_get];list [dict get $r hotwater_target_unit] [dict get $r hotwater_stop_mode] [dict get $r firmware_hotwater_volume_ml]} -result {ml firmware_volume 250}
test controls-send {all requested direct setters retain units} -body {reset;run control_patch {flush_flow_ml_s 5.5 flush_timeout_s 4.5 hotwater_flow_ml_s 7.5 steam_flow_ml_s 1.45};list $::calls $::settings(steam_flow)} -result {{{set_flush_flow_rate 5.5} {set_flush_timeout 4.5} {set_hotwater_flow_rate 7.5} {set_steam_flow 145} save} 145}
test controls-bundle {native bundle replaces duplicate setters and preserves steam disabled polarity} -body {reset;set r [run control_patch {steam_enabled false steam_timeout_s 0 hotwater_temperature_c 88 flush_flow_ml_s 5}];list $::calls $::settings(steam_disabled) $::settings(steam_timeout) [dict get $r device_confirmed]} -result {{native_bundle save} 1 0 0}
test controls-range {reject entire invalid payload before mutation} -body {reset;list [ec {run control_patch {flush_flow_ml_s 5 steam_flow_ml_s 2.6}}] $::settings(flush_flow) $::calls} -result {{REMOTE 422 invalid_value} 6 {}}
test controls-precision {reject impossible native increments} -body {reset;ec {run control_patch {hotwater_temperature_c 85.5}}} -result {REMOTE 422 invalid_precision}
test controls-missing {missing native setter leaves settings untouched} -body {reset;rename set_steam_flow held;set code [ec {run control_patch {steam_flow_ml_s 2}}];rename held set_steam_flow;list $code $::settings(steam_flow) $::calls} -result {{REMOTE 501 unsupported} 150 {}}
test controls-busy {in-use machine cannot change controls} -body {reset;set ::de1(state) 4;list [ec {run control_patch {flush_flow_ml_s 5}}] $::calls} -result {{REMOTE 409 busy} {}}
test controls-save {persist failure is unknown, not fictional rollback} -body {reset;set ::savefail 1;list [ec {run control_patch {flush_flow_ml_s 5}}] $::settings(flush_flow) $::calls} -result {{REMOTE 502 apply_unknown} 5 {{set_flush_flow_rate 5} save}}
test scale-readonly {autotare is exposed without a writable switch} -body {reset;list [dict get [run scale_get] autotare_states] [ec {run scale_patch {autotare_states {Idle}}}]} -result {{Espresso HotWater} {REMOTE 422 unknown_field}}
test scale-patch {scale behavior updates settings only, no tare or BLE call} -body {reset;run scale_patch {require_scale false stop_before_s -0.2 keep_scale_on false};list $::settings(start_espresso_only_if_scale_connected) $::settings(stop_weight_before_seconds) $::settings(keep_scale_on) $::calls} -result {0 -0.2 0 save}
test scale-range {stop-before bounds match original calibration} -body {reset;ec {run scale_patch {stop_before_s 1.6}}} -result {REMOTE 422 invalid_value}
test scheduler-patch {native scheduler receives seconds, not immediate wake/sleep} -body {reset;set r [run scheduler_patch {enabled true wake_time 08:09 awake_until 10:11}];list $::settings(scheduler_wake) $::settings(scheduler_sleep) $::calls [dict get $r semantics]} -result {29340 36660 {schedule_future save} forced_awake_interval}
test scheduler-format {reject malformed and cross-midnight interval before mutation} -body {reset;set ::settings(scheduler_enable) 1;list [ec {run scheduler_patch {wake_time 8:00}}] [ec {run scheduler_patch {wake_time 23:00 awake_until 01:00}}] $::calls} -result {{REMOTE 422 invalid_time} {REMOTE 422 overnight_unsupported} {}}
test scheduler-missing {native alarm support required} -body {reset;rename set_alarms_for_de1_wake_sleep held;set code [ec {run scheduler_patch {enabled true}}];rename held set_alarms_for_de1_wake_sleep;list $code $::settings(scheduler_enable)} -result {{REMOTE 501 unsupported} 0}
test charging-mode {three native modes; explicit USB request after policy} -body {reset;set r [run charging_patch {smart_charging_mode night machine_usb_enabled false}];list $::settings(smart_battery_charging) $::de1(usb_charger_on) $::calls [dict get $r usb_override_temporary]} -result {2 0 {smart_policy {usb 0} save} 1}
test charging-invalid {boolean mode is not silently coerced} -body {reset;list [ec {run charging_patch {smart_charging_mode true machine_usb_enabled false}}] $::calls} -result {{REMOTE 422 invalid_value} {}}
test charging-missing {USB unsupported returns501} -body {reset;rename set_usb_charger_on held;set code [ec {run charging_patch {machine_usb_enabled false}}];rename held set_usb_charger_on;set code} -result {REMOTE 501 unsupported}
test flow-enable {reuse native toggle and unchanged request is idempotent} -body {reset;set ::flow_lut_send::enabled 0;run flow_compensation_patch {enabled true};run flow_compensation_patch {enabled true};set ::calls} -result native_flow_toggle
test flow-restrict {cannot change LUT, multiplier or scope} -body {reset;ec {run flow_compensation_patch {enabled true multiplier 1}}} -result {REMOTE 422 unknown_field}
test flow-busy {existing plugin run locks are respected} -body {reset;set ::flowbusy 1;list [ec {run flow_compensation_patch {enabled false}}] $::calls} -result {{REMOTE 409 busy} {}}
test flow-detail {only saved changes/ACK are reported, no computed physical success} -body {
    reset;set ::flow_lut_send::last {state queued message 等待确认 ack 0 updated 123 profile_filename Filter3_15g changes {{target 1 command 0.75 estimate 0.97 stage 3 bracket {{1 2} {3 4}}}}}
    set r [run flow_compensation_get];list [dict get $r ack] [dict get $r current_profile_match] [dict get $r changes]
} -result {0 1 {{target 1 command 0.75 estimate 0.97 stage 3}}}
test flow-unknown-ack {missing ACK remains unknown, not false or success} -body {reset;set ::flow_lut_send::last {state ready message 就绪};dict get [run flow_compensation_get] ack} -result {}
test flow-missing {missing optional plugin remains readable and writes501} -body {
    reset;rename ::flow_lut_send::toggle ::flow_lut_send::held
    set available [dict get [run flow_compensation_get] available]
    set code [ec {run flow_compensation_patch {enabled true}}]
    rename ::flow_lut_send::held ::flow_lut_send::toggle
    list $available $code
} -result {0 {REMOTE 501 unsupported}}
test scheduler-disable {existing unsupported interval never prevents disabling} -body {
    reset;set ::settings(scheduler_enable) 1;set ::settings(scheduler_wake) 80000;set ::settings(scheduler_sleep) 10000
    run scheduler_patch {enabled false};set ::settings(scheduler_enable)
} -result 0
test scheduler-next {enabled next wake is native epoch and no alarm side effect} -body {
    reset;set ::settings(scheduler_enable) 1
    set r [run scheduler_get]
    list [dict get $r next_wake_at] [dict get $r awake_interval_enabled] [dict exists $r awake_interval_active] $::calls
} -result {1800025200 1 0 {}}
test scheduler-disabled-next {disabled next wake is unknown, not a scheduled event} -body {
    reset;dict get [run scheduler_get] next_wake_at
} -result {}
test scheduler-next-missing {enabling without native epoch resolver fails before mutation} -body {
    reset;rename next_alarm_time held
    set code [ec {run scheduler_patch {enabled true}}]
    rename held next_alarm_time
    list $code $::settings(scheduler_enable) $::calls
} -result {{REMOTE 501 unsupported} 0 {}}
test flow-peeked {peeked namespace and wrapper alone do not mean loaded} -body {
    reset;set ::plugins::flow_lut::plugin_loaded 0
    list [dict get [run flow_compensation_get] available] [ec {run flow_compensation_patch {enabled true}}] $::calls
} -result {0 {REMOTE 501 unsupported} {}}
test flow-disabled {enabled list overrides stale loaded flag} -body {
    reset;set ::settings(enabled_plugins) {decent_remote}
    list [dict get [run flow_compensation_get] available] [ec {run flow_compensation_patch {enabled false}}] $::calls
} -result {0 {REMOTE 501 unsupported} {}}
test flow-last-identity {saved ACK is historical and never reassigned to current profile} -body {
    reset;set ::settings(profile_filename) Other;set ::settings(profile_title) Other
    set ::flow_lut_send::last {state confirmed ack 1 profile_filename Filter3_15g}
    set r [run flow_compensation_get]
    list [dict get $r ack] [dict get $r last_profile] [dict get $r current_profile_match] [dict get $r ack_scope]
} -result {1 Filter3_15g 0 last_published_send}
test hotwater-target-ineffective {connected scale without stop-on-scale warns target is ignored} -body {
    reset;set ::settings(water_stop_on_scale) 0;set r [run control_get]
    list [dict get $r target_effective] [expr {[string length [dict get $r hotwater_target_warning]]>0}]
} -result {0 1}
test hotwater-target-effective {scale stop or disconnected volume restores meaningful target} -body {
    reset;set scale [dict get [run control_get] target_effective]
    set ::settings(water_stop_on_scale) 0;set ::de1(scale_device_handle) 0
    set r [run control_get]
    list $scale [dict get $r target_effective] [dict get $r firmware_hotwater_volume_ml]
} -result {1 1 50}
cleanupTests
