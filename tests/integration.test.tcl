# End-to-end offline contracts: JSON router -> real adapter -> real modules.
# Only native App/device leaves below are simulated. They retain native units,
# settings/file side effects, and separate Tcl/JSON persistence. No socket, BLE,
# Android command, or full App source is used by this suite.
package require tcltest
namespace import ::tcltest::*
set here [file dirname [info script]]
foreach component {core profiles adapter editor controls} {
    source [file join $here .. $component.tcl]
}
set ::testroot [makeDirectory integration-data-[pid]]
file mkdir [file join $::testroot profiles] [file join $::testroot profiles_v2]
set f [open [file join $here fixtures filter3.tcl] r]
fconfigure $f -encoding utf-8
set ::fixture [read $f]
close $f

namespace eval ::fixture_support {
    proc write {path value} {
        set f [open $path w]
        fconfigure $f -encoding utf-8 -translation lf
        puts -nonewline $f $value
        close $f
    }
    proc read {path} {
        set f [open $path r]
        fconfigure $f -encoding utf-8 -translation lf
        set value [::read $f]
        close $f
        return $value
    }
    proc flat_profile {} {
        set data {}
        foreach key [profile_vars] {
            if {[info exists ::settings($key)]} {dict set data $key $::settings($key)}
        }
        return $data
    }
    # Independent test encoder, not api::object: use the documented step scalar
    # types to emulate a client resubmitting all stages returned by GET /profile.
    proc steps_json {steps} {
        set rows {}
        foreach step $steps {
            set fields {}
            dict for {key value} $step {
                if {$key in {name popup pump sensor transition exit_type}} {
                    set value [::json::write string $value]
                }
                lappend fields $key $value
            }
            lappend rows [::json::write object {*}$fields]
        }
        return [::json::write array {*}$rows]
    }
    # Minimal native-v2 export shape, including the native exit/limiter objects.
    # This is a leaf fixture, not a replacement for the native-source audit.
    proc v2_json {} {
        set rows {}
        foreach step $::settings(advanced_shot) {
            set fields {}
            foreach key {name sensor pump transition} {
                lappend fields $key [::json::write string [dict get $step $key]]
            }
            foreach key {temperature pressure flow seconds volume weight} {
                lappend fields $key [dict get $step $key]
            }
            if {[dict get $step exit_if]} {
                lassign [split [dict get $step exit_type] _] type condition
                lappend fields exit [::json::write object \
                    type [::json::write string $type] condition [::json::write string $condition] \
                    value [dict get $step exit_${type}_${condition}]]
            }
            if {[dict exists $step max_flow_or_pressure_range]} {
                lappend fields limiter [::json::write object value [dict get $step max_flow_or_pressure] \
                    range [dict get $step max_flow_or_pressure_range]]
            }
            lappend rows [::json::write object {*}$fields]
        }
        return [::json::write object title [::json::write string $::settings(profile_title)] \
            notes [::json::write string $::settings(profile_notes)] version 2 \
            type [::json::write string advanced] reference_file [::json::write string $::settings(profile_filename)] \
            target_weight $::settings(final_desired_shot_weight_advanced) \
            target_volume $::settings(final_desired_shot_volume_advanced) \
            target_volume_count_start $::settings(final_desired_shot_volume_advanced_count_start) \
            steps [::json::write array {*}$rows]]
    }
}
proc homedir {} {return $::testroot}
proc profile_vars {} {return [concat [dict keys $::fixture] {advanced_shot_tcl}]}
proc translate {text} {return $text}
namespace eval ::profile {
    variable current {}
    proc sync_from_legacy {} {
        variable current
        lappend ::calls sync
        set current [::fixture_support::v2_json]
    }
    proc save {path} {
        variable current
        sync_from_legacy
        ::fixture_support::write $path $current
    }
}
proc save_settings {} {
    lappend ::calls save_settings
    ::fixture_support::write [file join [homedir] settings.tcl] [array get ::settings]
}
proc send_de1_settings_soon {} {
    lappend ::calls send
    if {$::send_failure} {error simulated_send_failure}
}
proc streamline_set_drink_weight {value} {
    lappend ::calls [list weight $value]
    foreach key {final_desired_shot_weight final_desired_shot_weight_advanced} {set ::settings($key) $value}
    foreach key {final_desired_shot_volume final_desired_shot_volume_advanced} {set ::settings($key) 0}
}
proc change_espresso_temperature {delta} {
    lappend ::calls [list temperature_delta $delta]
    set changed {}
    foreach step $::settings(advanced_shot) {
        dict set step temperature [expr {[dict get $step temperature] + $delta}]
        lappend changed $step
    }
    set ::settings(advanced_shot) $changed
    set ::settings(espresso_temperature) [expr {$::settings(espresso_temperature) + $delta}]
}
proc select_profile {root} {
    lappend ::calls [list select $root]
    set path [file join [homedir] profiles $root.tcl]
    if {![file isfile $path]} {return -1}
    array set ::settings [::fixture_support::read $path]
    set ::settings(profile_filename) $root
    set ::settings(original_profile_title) $::settings(profile_title)
    set ::settings(profile_has_changed) 0
    send_de1_settings_soon
}
proc copy_settings_from_profile_to_streamline {} {
    lappend ::calls copy_to_skin
    set ::settings(grinder_dose_weight) $::settings(profile_grinder_dose_weight)
}
proc save_profile {{saved_msg 1}} {
    lappend ::calls [list save_profile $saved_msg]
    ::fixture_support::write [file join [homedir] profiles $::settings(profile_filename).tcl] \
        [::fixture_support::flat_profile]
    ::profile::save [file join [homedir] profiles_v2 $::settings(profile_filename).json]
    set ::settings(profile_has_changed) 0
}
proc refresh_favorite_profile_button_labels {} {
    lappend ::calls refresh_profiles
    # Streamline would otherwise schedule a selection when title/slot disagree.
    for {set slot 1} {$slot <= 5} {incr slot} {
        if {[file tail [dict get $::settings(favorite_profiles) $slot title]] eq $::settings(profile_title) &&
            [dict get $::settings(favorite_profiles) selected number] != $slot} {
            error unexpected_native_profile_selection
        }
    }
}
proc refresh_favorite_dosebev_button_labels {} {lappend ::calls refresh_doses}
proc refresh_favorite_temperature_button_labels {} {lappend ::calls refresh_temperatures}
foreach {command key} {
    set_flush_flow_rate flush_flow set_flush_timeout flush_seconds
    set_hotwater_flow_rate hotwater_flow set_steam_flow steam_flow
} {
    proc ::$command {value} [format {lappend ::calls [list %s $value]; set ::settings(%s) $value} $command $key]
}
proc de1_send_steam_hotwater_settings {} {lappend ::calls native_bundle}
proc set_alarms_for_de1_wake_sleep {} {lappend ::calls schedule_future}
proc next_alarm_time {seconds} {return [expr {1800000000 + $seconds}]}
proc battery_percent {} {return 70}
proc check_battery_charger {} {lappend ::calls smart_policy; set ::de1(usb_charger_on) 1}
proc set_usb_charger_on {value} {lappend ::calls [list usb $value]; set ::de1(usb_charger_on) $value}
namespace eval ::device::scale {
    variable autotare_states {Espresso HotWater}
    proc expecting_present {} {return 1}
    proc tare {} {incr ::forbidden_calls; error unexpected_tare}
}
foreach command {start_espresso start_flush start_steam start_water start_idle start_sleep set_flow_multiplier} {
    proc ::$command {args} {incr ::forbidden_calls; error unexpected_physical_action}
}

proc reset {} {
    array unset ::settings
    array set ::settings $::fixture
    array set ::settings {
        skin Streamline profile_filename current profile_title Current original_profile_title Current
        read_only 0 profile_has_changed 0 insert_preinfusion_pause 0 grinder_dose_weight 22
        flow_calibration_multiplier 0.75
        flush_flow 6 flush_seconds 5 hotwater_flow 8 water_temperature 85 water_volume 50 water_time_max 60
        steam_flow 150 steam_temperature 160 steam_timeout 120 steam_disabled 0 water_stop_on_scale 1
        start_espresso_only_if_scale_connected 1 stop_weight_before_seconds 0.15 keep_scale_on 1 scale_type TestScale
        scheduler_enable 0 scheduler_wake 25200 scheduler_sleep 32400 smart_battery_charging 1
    }
    set ::settings(favorite_profiles) {
        selected {number 1} 1 {name current title Current} 2 {name other title Other}
        3 {name {} title { }} 4 {name {} title { }} 5 {name {} title { }}
    }
    set ::settings(favorite_dosebevs) {1 {value 15 value2 30} 2 {value 16 value2 32} 3 {value 18 value2 36} 4 {value 20 value2 40}}
    set ::settings(favorite_temperatures) {1 {value 75} 2 {value 80} 3 {value 85} 4 {value 90}}
    array unset ::de1
    array set ::de1 {device_handle fixture-machine scale_device_handle fixture-scale state 2 substate 0 usb_charger_on 1 scale_weight 5 scale_weight_rate 1}
    array set ::de1_num_state {0 Sleep 2 Idle 4 Espresso}
    set ::globals(widget_profile_name_to_save) .fixture-entry
    set ::plugins::decent_remote::api::root $::testroot
    set ::plugins::decent_remote::api::token offline-integration-token-only
    set ::plugins::decent_remote::api::adapter ::plugins::decent_remote::device::call
    set ::plugins::decent_remote::api::allow_start 0
    set ::plugins::decent_remote::api::seen {}
    foreach var {records active pending queued flight send_stack ack_stack tainted} {set ::plugins::decent_remote::receipts::$var {}}
    set ::plugins::decent_remote::receipts::tainted_all 0
    foreach dir {profiles profiles_v2} {
        foreach path [glob -nocomplain -directory [file join $::testroot $dir] *] {file delete $path}
    }
    ::fixture_support::write [file join $::testroot profiles current.tcl] [dict merge $::fixture {profile_title Current read_only 0}]
    ::fixture_support::write [file join $::testroot profiles other.tcl] [dict merge $::fixture {profile_title Other}]
    ::fixture_support::write [file join $::testroot settings.tcl] [array get ::settings]
    set ::calls {}; set ::serial 0; set ::lastid {}; set ::send_failure 0; set ::forbidden_calls 0
}
proc request {method path {body {}} {id {}}} {
    set headers [dict create authorization {Bearer offline-integration-token-only}]
    if {$method ne "GET"} {
        if {$id eq {}} {set id [format integration-%08d [incr ::serial]]}
        set ::lastid $id
        dict set headers x-request-id $id
    }
    return [::plugins::decent_remote::api::dispatch $method $path $headers $body]
}
proc decoded {response} {return [::json::json2dict [dict get $response body]]}
proc receipt {{id {}}} {
    if {$id eq {}} {set id $::lastid}
    return [decoded [request GET /api/v1/requests/$id]]
}
proc current_file {} {return [::fixture_support::read [file join $::testroot profiles current.tcl]]}
proc settings_file {} {return [::fixture_support::read [file join $::testroot settings.tcl]]}

test route-profile-get {advanced profile has real JSON arrays/scalars and reads without effects} -body {
    reset
    set r [request GET /api/v1/profile]
    set raw [dict get $r body]; set data [decoded $r]
    list [dict get $r status] [dict get $data profile] [llength [dict get $data steps]] \
        [regexp {"steps"\s*:\s*\[} $raw] [regexp {"editable_steps"\s*:\s*true} $raw] \
        [regexp {"flow"\s*:\s*5\.0} $raw] [regexp {"dirty"\s*:\s*false} $raw] $::calls
} -result {200 current 7 1 1 1 1 {}}

test route-profile-roundtrip {GET stages can be resubmitted; normalization never edits original file} -body {
    reset
    set before [current_file]
    set original [dict get [decoded [request GET /api/v1/profile]] steps]
    set body [::json::write object steps [::fixture_support::steps_json $original]]
    set r [request POST /api/v1/profile $body]; set data [decoded $r]
    set same 1
    foreach old $original new [dict get $data current_profile steps] {
        dict for {key value} $old {if {[dict get $new $key] ne $value} {set same 0}}
    }
    list [dict get $r status] $same [dict get $data temporary] \
        [dict get [lindex [dict get $data current_profile steps] 0] exit_type] \
        [expr {$before eq [current_file]}] $::settings(flow_calibration_multiplier) \
        [dict get [receipt] phase] [dict get [receipt] device_confirmed] $::calls
} -result {200 1 true flow_under 1 0.75 app_applied false {sync send}}

test route-profile-fields {pressure/flow, limits, exit, volume count and recipe survive structured JSON} -body {
    reset
    set r [request POST /api/v1/profile {
        {"dose_g":19,"yield_g":100,"temperature_c":92,"target_volume_ml":300,"volume_count_start":2,
         "steps":[
           {"name":"高压","pump":"pressure","pressure":8.6,"sensor":"coffee","transition":"fast","temperature":92,"seconds":12,"weight":24,"max_flow_or_pressure":8,"exit_if":true,"exit_type":"pressure_over","exit_pressure_over":8},
           {"name":"尾段","pump":"flow","flow":1.5,"sensor":"water","transition":"smooth","temperature":88,"seconds":50,"max_flow_or_pressure":8}
         ]}
    }]
    set data [decoded $r]; set p [dict get $data current_profile]
    set a [lindex [dict get $p steps] 0]; set b [lindex [dict get $p steps] 1]
    list [dict get $r status] [dict get $p dose_g] [dict get $p yield_g] [dict get $p target_volume_ml] \
        [dict get $p volume_count_start] [dict get $a pressure] [dict get $a exit_if] \
        [dict get $a exit_pressure_over] [dict get $a weight] [dict get $b flow] [dict get $b sensor] \
        [dict get $b max_flow_or_pressure] [dict get $p dirty] [dict get [receipt] device_confirmed]
} -result {200 19 100 300 2 8.6 1 8 24 1.5 water 8 true false}

test route-body-rejection {invalid structured body and executable Tcl fail before any native effect} -body {
    reset
    set before [array get ::settings]; set file_before [current_file]
    set codes {}
    foreach body {
        {{"dose_g":19,"steps":{}}}
        {{"dose_g":19,"steps":[["pump","flow"]]}}
        {{"dose_g":19,"steps":[{"pump":"flow","flow":1,"sensor":"coffee","transition":"fast","temperature":92,"seconds":10,"script":"start_espresso"}]}}
    } {lappend codes [dict get [request POST /api/v1/profile $body] status]}
    ::fixture_support::write [file join $::testroot profiles unsafe.tcl] \
        [dict merge $::fixture {advanced_shot_tcl {start_espresso}}]
    lappend codes [dict get [request PUT /api/v1/profiles/unsafe.tcl] status]
    list $codes [expr {$before eq [array get ::settings]}] [expr {$file_before eq [current_file]}] \
        [dict get [receipt] phase] $::calls $::forbidden_calls
} -result {{422 422 422 422} 1 1 rejected {} 0}

test route-basic-and-count-limit {basic read is truthful; no advanced conversion or invalid preinfuse count} -body {
    reset
    set r [request POST /api/v1/profile { {"volume_count_start":8} }]
    set ::settings(settings_profile_type) settings_2a
    set basic [decoded [request GET /api/v1/profile]]
    set edit [request POST /api/v1/profile {
        {"steps":[{"pump":"flow","flow":1,"sensor":"coffee","transition":"fast","temperature":92,"seconds":10}]}
    }]
    list [dict get $r status] [dict get $basic editable_steps] [dict get $basic steps] \
        [dict get $basic volume_count_start] [dict get $edit status] $::settings(settings_profile_type) $::calls
} -result {422 false {} {} 422 settings_2a {}}

test route-saveas-restore {Unicode save-as persists Tcl/v2 JSON and restore reloads that exact recipe} -body {
    reset
    set before [current_file]
    request POST /api/v1/profile { {"dose_g":19,"yield_g":100,"temperature_c":92,"notes":"中文 [start_espresso]; literal"} }
    set ::settings(read_only) 1
    set blocked [request POST /api/v1/profile/save {{}}]
    set saved [request POST /api/v1/profile/save-as { {"filename":"测试副本.tcl","title":"中文曲线"} }]
    set saved_receipt [receipt]
    set tcl_data [dict get [request GET /api/v1/profiles/测试副本.tcl] body]
    set json_data [::json::json2dict [::fixture_support::read [file join $::testroot profiles_v2 测试副本.json]]]
    request POST /api/v1/profile { {"dose_g":15,"temperature_c":90} }
    set restored [decoded [request POST /api/v1/profile/restore {{}}]]
    set p [dict get $restored current_profile]
    list [dict get $blocked status] [dict get $saved status] \
        [dict get $tcl_data profile_grinder_dose_weight] [dict get $tcl_data final_desired_shot_weight_advanced] \
        [dict get $json_data title] [dict get $json_data target_weight] \
        [dict get [lindex [dict get $json_data steps] 0] temperature] \
        [dict get $p profile] [dict get $p dose_g] [dict get $p temperature_c] [dict get $p dirty] \
        [expr {$before eq [current_file]}] [dict get $saved_receipt phase] \
        [dict get $saved_receipt device_confirmed] $::forbidden_calls
} -result {409 200 19 100 中文曲线 100 92.0 测试副本 19 92 false 1 app_applied false 0}

test route-select-receipt {selection reads its nested recipe cache but never implies a machine ACK} -body {
    reset
    set r [request PUT /api/v1/profiles/other.tcl]
    set data [decoded $r]; set execution [receipt]
    list [dict get $r status] [dict get $data recipe profile] [dict get $data recipe readback] \
        [dict get $execution app_applied] [dict get $execution phase] [dict get $execution device_confirmed] \
        [dict get $execution in_flight] $::calls
} -result {200 other app_cache true app_applied false false {{select other} send copy_to_skin save_settings}}

test route-import-files {JSON import validates then writes Tcl only; Unicode data and original stages survive} -body {
    reset
    set ::settings(profile_title) {导入曲线}
    set content [::fixture_support::v2_json]
    set ::settings(profile_title) Current
    set before [array get ::settings]; set original [current_file]
    set body [::json::write object filename [::json::write string 导入曲线.json] format [::json::write string json] \
        content [::json::write string $content] dry_run true]
    set dry [request POST /api/v1/profiles/import $body]; set check [decoded $dry]
    set dry_phase [dict get [receipt] phase]
    set absent [expr {![file exists [file join $::testroot profiles 导入曲线.tcl]]}]
    set body [::json::write object filename [::json::write string 导入曲线.json] format [::json::write string json] \
        content [::json::write string $content]]
    set r [request POST /api/v1/profiles/import $body]; set data [decoded $r]; set execution [receipt]
    set imported [dict get [request GET /api/v1/profiles/导入曲线.tcl] body]
    list [dict get $dry status] [dict get $check saved] [dict get $check readback] $dry_phase $absent \
        [dict get $r status] [dict get $data filename] [dict get $data saved] [dict get $data readback] \
        [dict get $imported profile_title] [llength [dict get $imported advanced_shot]] \
        [dict get [lindex [dict get $imported advanced_shot] 0] flow] \
        [expr {$before eq [array get ::settings]}] [expr {$original eq [current_file]}] \
        [dict get $execution phase] [dict get $execution in_flight] [dict get $execution device_confirmed] $::calls
} -result {200 false validated accepted_unconfirmed 1 200 导入曲线.tcl true file 导入曲线 7 5.0 1 1 app_applied false false {}}

test route-explicit-save {only explicit save changes current file; saved files and app readback agree} -body {
    reset
    set before [current_file]
    request POST /api/v1/profile { {"dose_g":18.5,"yield_g":37} }
    set unchanged [expr {$before eq [current_file]}]
    set r [request POST /api/v1/profile/save {{}}]
    set data [decoded $r]
    set exported [::json::json2dict [::fixture_support::read [file join $::testroot profiles_v2 current.json]]]
    set collision [request POST /api/v1/profile/save-as { {"filename":"other.tcl","title":"Replacement"} }]
    list $unchanged [dict get $r status] [dict get [current_file] profile_grinder_dose_weight] \
        [dict get [current_file] final_desired_shot_weight_advanced] [dict get $exported target_weight] \
        [dict get $data saved] [dict get $data temporary] [dict get $data readback] [dict get $collision status]
} -result {1 200 18.5 37 37 true false files 409}

test route-presets {favorites/shortcuts roundtrip as typed arrays without applying another recipe} -body {
    reset
    set before [current_file]
    set favorites [request POST /api/v1/favorites { {"slots":[{"slot":1,"profile":"other"},{"slot":2,"profile":"current"}]} }]
    set shortcuts [request POST /api/v1/shortcuts { {"dose_yield":[{"slot":1,"dose_g":19,"yield_g":100}],"temperatures":[{"slot":4,"temperature_c":92}]} }]
    set fav [dict get [decoded $favorites] favorites]; set preset [dict get [decoded $shortcuts] shortcuts]
    list [dict get $favorites status] [llength [dict get $fav slots]] [dict get $fav selected_slot] \
        [dict get [lindex [dict get $fav slots] 0] profile] [dict get [lindex [dict get $preset dose_yield] 0] yield_g] \
        [dict get [lindex [dict get $preset temperatures] 3] temperature_c] \
        [regexp {"slot"\s*:\s*1} [dict get $shortcuts body]] \
        $::settings(profile_filename) $::settings(grinder_dose_weight) $::settings(espresso_temperature) \
        [expr {$before eq [current_file]}] [dict get [settings_file] favorite_profiles selected number] \
        [dict get [receipt] phase]
} -result {200 5 2 other 100 92 1 current 22 94.0 1 2 app_applied}

test route-controls {mixed settings use native units and one bundle, with truthful receipt types} -body {
    reset
    set r [request POST /api/v1/controls {
        {"steam_flow_ml_s":1.45,"steam_enabled":false,"hotwater_temperature_c":88,"flush_flow_ml_s":5.5,"hotwater_flow_ml_s":7.5}
    }]
    set raw [dict get $r body]; set data [decoded $r]; set execution [receipt]
    list [dict get $r status] $::settings(steam_flow) [dict get [settings_file] steam_flow] \
        [dict get $data steam_flow_ml_s] [dict get $data hotwater_target_unit] \
        [regexp {"steam_enabled"\s*:\s*false} $raw] [regexp {"device_confirmed"\s*:\s*false} $raw] \
        [dict get $execution phase] [dict get $execution http_status] $::calls
} -result {200 145 145 1.45 g 1 1 app_applied 200 {native_bundle {set_hotwater_flow_rate 7.5} save_settings}}

test route-controls-atomic {late invalid field prevents earlier valid field and persistent write} -body {
    reset
    set before [settings_file]
    set r [request POST /api/v1/controls { {"flush_flow_ml_s":5,"steam_flow_ml_s":2.6} }]
    list [dict get $r status] $::settings(flush_flow) [expr {$before eq [settings_file]}] \
        [dict get [receipt] phase] $::calls
} -result {422 6 1 rejected {}}

test route-scale {scale policy JSON and native autotare states are independent of physical tare} -body {
    reset
    set r [request POST /api/v1/scale { {"require_scale":false,"stop_before_s":-0.2,"keep_scale_on":false} }]
    set data [decoded $r]
    list [dict get $r status] [dict get $data autotare_states] [dict get $data require_scale] \
        [dict get $data stop_before_s] [dict get $data keep_scale_on] \
        [regexp {"autotare_states"\s*:\s*\[} [dict get $r body]] \
        [dict get [settings_file] start_espresso_only_if_scale_connected] $::calls $::forbidden_calls
} -result {200 {Espresso HotWater} false -0.2 false 1 0 save_settings 0}

test route-schedule-and-charging {time and mode conversions use native leaves without immediate machine start} -body {
    reset
    set schedule [request POST /api/v1/scheduler { {"enabled":true,"wake_time":"09:00","awake_until":"09:30"} }]
    set charge [request POST /api/v1/charging { {"smart_charging_mode":"night","machine_usb_enabled":false} }]
    set s [decoded $schedule]; set c [decoded $charge]
    list [dict get $schedule status] $::settings(scheduler_wake) $::settings(scheduler_sleep) \
        [dict get $s next_wake_at] [dict get $s overnight_supported] \
        [dict get $charge status] $::settings(smart_battery_charging) [dict get $c machine_usb_enabled] \
        [dict get $c usb_override_temporary] [dict get [receipt] device_confirmed] $::forbidden_calls $::calls
} -result {200 32400 34200 1800032400 false 200 2 false true false 0 {schedule_future save_settings smart_policy {usb 0} save_settings}}

test route-unknown-outcome {native send failure retains changed cache and truthful unknown receipt, no retry} -body {
    reset
    set before [current_file]; set ::send_failure 1
    set r [request POST /api/v1/profile { {"dose_g":19} }]
    set id $::lastid; set execution [receipt]
    set replay [request POST /api/v1/profile { {"dose_g":20} } $id]
    set actual [decoded [request GET /api/v1/profile]]
    list [dict get $r status] [dict get $execution phase] [dict get $execution device_confirmed] \
        [dict get $replay status] [dict get $actual dose_g] [dict get [receipt $id] phase] \
        [expr {$before eq [current_file]}] $::calls
} -result {502 outcome_unknown false 409 19 outcome_unknown 1 {sync send}}

test route-start-disabled {default remote-start gate blocks before any native action or confirmation} -body {
    reset
    set r [request POST /api/v1/machine/espresso {{}}]
    set execution [receipt]
    list [dict get $r status] [dict get [decoded $r] error] [dict get $execution phase] \
        [dict get $execution accepted] [dict get $execution device_confirmed] $::calls $::forbidden_calls
} -result {403 start_disabled rejected false false {} 0}

test route-start-policy-readback {compatibility status stays false even if a legacy runtime variable is injected} -body {
    reset
    set disabled [request GET /api/v1/status]
    set ::plugins::decent_remote::api::allow_start 1
    set enabled [request GET /api/v1/status]
    list [regexp {"remote_start_enabled"\s*:\s*false} [dict get $disabled body]] \
        [regexp {"remote_start_enabled"\s*:\s*false} [dict get $enabled body]] $::calls $::forbidden_calls
} -result {1 1 {} 0}

removeDirectory $::testroot
cleanupTests
