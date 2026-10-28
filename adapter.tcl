# Adapter for the inspected classic de1app 1.46.1.1 (Streamline).
# No commands run when this file is sourced. All telemetry is app-cache data.
namespace eval ::plugins::decent_remote::device {
    proc fail {status code message} {return -code error -errorcode [list REMOTE $status $code] $message}
    proc get {name {fallback {}}} {if {[info exists $name]} {return [set $name]}; return $fallback}
    proc require_cmd {args} {
        foreach cmd $args {if {![llength [info commands $cmd]]} {fail 501 unsupported "当前版本缺少原生方法：$cmd"}}
    }
    proc require_plugin {name command} {
        require_cmd $command
        if {[get ::plugins::${name}::plugin_loaded 0] != 1} {
            fail 501 plugin_disabled "$name 插件未启用或尚未加载完成"
        }
    }
    proc number {name value low high} {
        if {![string is double -strict $value] || [catch {expr {$value >= $low && $value <= $high}} ok] || !$ok} {
            fail 422 invalid_value "$name 必须为 $low 至 $high 的有限数值"
        }
        return $value
    }
    proc keys {payload allowed} {
        if {[catch {dict size $payload}]} {fail 400 invalid_payload "请求必须是字段对象"}
        foreach k [dict keys $payload] {if {$k ni $allowed} {fail 422 unknown_field "不支持字段：$k"}}
    }
    proc connected {} {expr {[get ::de1(device_handle)] ni {{} 0}}}
    proc state {} {
        set code [get ::de1(state)]
        return [get ::de1_num_state($code) Unknown]
    }
    proc guard {{states {Idle Sleep}}} {
        if {![connected]} {fail 409 disconnected "咖啡机未连接"}
        if {[state] ni $states} {fail 409 busy "当前机器状态不允许该操作：[state]"}
        foreach v {::app_updating ::de1(currently_updating_firmware) ::de1(in_fw_update_mode)} {
            if {[get $v 0] ni {0 {}}} {fail 409 updating "应用或固件正在更新"}
        }
    }
    proc recipe {} {
        set type [get ::settings(settings_profile_type)]
        set weightkey [expr {$type in {settings_2a settings_2b} ? "final_desired_shot_weight" : "final_desired_shot_weight_advanced"}]
        return [dict create profile [get ::settings(profile_filename)] title [get ::settings(profile_title)] \
            profile_type $type dose_g [get ::settings(grinder_dose_weight)] yield_g [get ::settings($weightkey)] \
            temperature_c [get ::settings(espresso_temperature)] readback app_cache]
    }
    proc snapshot {} {return [array get ::settings]}
    proc restore {snapshot} {
        # Only restores application memory. Never claim rollback of a queued BLE write.
        foreach key [array names ::settings] {
            if {![dict exists $snapshot $key]} {unset ::settings($key)}
        }
        array set ::settings $snapshot
    }
    proc recipe_patch {payload} {
        keys $payload {dose_g yield_g temperature_c}
        if {![dict size $payload]} {fail 422 empty_patch "至少提供一个配方字段"}
        guard
        require_cmd ::send_de1_settings_soon ::profile::sync_from_legacy
        dict for {k v} $payload {
            switch $k {
                dose_g {number $k $v 0.1 30}
                yield_g {number $k $v 0 2000; require_cmd ::streamline_set_drink_weight ::device::scale::expecting_present}
                temperature_c {
                    number $k $v 0 105
                    require_cmd ::change_espresso_temperature
                    number current_temperature [get ::settings(espresso_temperature)] 0 105
                    set delta [expr {$v - $::settings(espresso_temperature)}]
                    if {[get ::settings(settings_profile_type)] in {settings_2a settings_2b}} {
                        if {[get ::settings(espresso_temperature_steps_enabled) 0] == 1} {
                            foreach key {espresso_temperature_1 espresso_temperature_2 espresso_temperature_3} {
                                number $key [get ::settings($key)] 0 105
                                number $key [expr {$::settings($key) + $delta}] 0 105
                            }
                        }
                    } else {
                        set steps [get ::settings(advanced_shot)]
                        if {![llength $steps]} {fail 409 invalid_profile "高级曲线缺少温度分段"}
                        foreach step $steps {
                            if {![dict exists $step temperature]} {fail 409 invalid_profile "曲线分段缺少温度"}
                            set t [dict get $step temperature]
                            number step_temperature $t 0 105
                            number step_temperature [expr {$t + $delta}] 0 105
                        }
                    }
                }
            }
        }
        set before [snapshot]
        # Stage all in-memory changes before scheduling a device transfer.
        if {[catch {
            if {[dict exists $payload dose_g]} {
                set ::settings(grinder_dose_weight) [dict get $payload dose_g]
                set ::settings(profile_grinder_dose_weight) [dict get $payload dose_g]
            }
            if {[dict exists $payload yield_g]} {::streamline_set_drink_weight [dict get $payload yield_g]}
            if {[dict exists $payload temperature_c]} {::change_espresso_temperature $delta}
            set ::settings(profile_has_changed) 1
            ::profile::sync_from_legacy
            set actual [recipe]
            dict for {k v} $payload {if {[dict get $actual $k] != $v} {error "配方应用内读回不一致：$k"}}
        } err]} {
            restore $before
            catch {::profile::sync_from_legacy}
            fail 500 apply_failed "配方修改失败，已恢复应用设置；未提交发送：$err"
        }
        if {[catch {::send_de1_settings_soon} err]} {
            fail 502 send_unknown "配方已在应用中更新，发送结果未知，未声称设备回滚：$err"
        }
        return [dict create accepted 1 temporary 1 readback app_cache recipe [recipe] device_confirmed 0]
    }
    proc settings_map {} {
        # Public units differ from firmware's tenths for flows and idle temperature.
        return [dict create preheat_phase1_flow_ml_s {phase_1_flow_rate 10 0.5 6} \
            preheat_phase2_flow_ml_s {phase_2_flow_rate 10 0.5 8} \
            preheat_timeout_s {espresso_warmup_timeout 10 1 30} \
            idle_temperature_c {hot_water_idle_temp 10 0 99} \
            sleep_timeout_minutes {screen_saver_delay 1 0 480} \
            awake_brightness {app_brightness 1 0 100} sleep_brightness {saver_brightness 1 0 100}]
    }
    proc settings_get {} {
        set out [dict create readback app_cache]
        dict for {public spec} [settings_map] {
            lassign $spec key factor low high
            set value [get ::settings($key)]
            if {[string is double -strict $value] && $value ne {}} {set value [expr {$value / double($factor)}]}
            dict set out $public $value
        }
        return $out
    }
    proc settings_patch {payload} {
        set mapping [settings_map]
        keys $payload [dict keys $mapping]
        if {![dict size $payload]} {fail 422 empty_patch "至少提供一个设置字段"}
        guard
        set heater 0
        dict for {k v} $payload {
            lassign [dict get $mapping $k] key factor low high
            number $k $v $low $high
            set raw [expr {$v * $factor}]
            if {abs($raw-round($raw)) > 0.000001} {fail 422 invalid_precision "$k 的精度超出设备支持"}
            if {$key eq "hot_water_idle_temp" && int(round($raw)) % 5 != 0} {fail 422 invalid_precision "待机温度仅支持 0.5 摄氏度步长"}
            if {![info exists ::settings($key)]} {fail 501 unsupported "当前应用没有设置：$key"}
            if {$key in {phase_1_flow_rate phase_2_flow_rate hot_water_idle_temp espresso_warmup_timeout}} {set heater 1}
        }
        require_cmd ::save_settings
        if {$heater} {require_cmd ::set_heater_tweaks}
        if {[dict exists $payload sleep_timeout_minutes]} {require_cmd ::delay_screen_saver}
        if {[dict exists $payload awake_brightness] || [dict exists $payload sleep_brightness]} {require_cmd ::display_brightness}
        set before [snapshot]
        dict for {k v} $payload {
            lassign [dict get $mapping $k] key factor low high
            set ::settings($key) [expr {int(round($v * $factor))}]
        }
        set actual [settings_get]
        dict for {k v} $payload {
            if {[dict get $actual $k] != $v} {restore $before; fail 500 readback_failed "设置应用内读回不一致：$k"}
        }
        # Native methods can queue writes. An error after this point is not a rollback.
        if {[catch {
            if {$heater} {::set_heater_tweaks}
            if {[dict exists $payload sleep_timeout_minutes]} {::delay_screen_saver}
            if {[state] eq "Idle" && [dict exists $payload awake_brightness]} {::display_brightness $::settings(app_brightness)}
            if {[state] eq "Sleep" && [dict exists $payload sleep_brightness]} {::display_brightness $::settings(saver_brightness)}
            ::save_settings
        } err]} {fail 502 apply_unknown "应用值已更新，原生设置调用结果未知：$err"}
        return [dict create accepted 1 settings [settings_get] readback app_cache device_confirmed 0]
    }
    proc machine {operation} {
        switch $operation {
            wake {guard {Sleep Idle}; set command ::start_idle}
            sleep {guard; set command ::start_sleep}
            stop {
                guard {Idle Sleep Espresso Steam HotWater HotWaterRinse}
                # start_idle would wake a sleeping machine. A stop with nothing
                # running must leave both Sleep and Idle unchanged.
                if {[state] in {Idle Sleep}} {return [dict create accepted 1 operation stop action not_needed device_confirmed 0]}
                set command ::start_idle
            }
            espresso - flush - steam - hotwater {
                guard {Idle}
                require_cmd ::ghc_required
                if {[::ghc_required]} {fail 409 ghc_required "机器要求实体冲煮头操作，远程启动不可用"}
                if {$operation eq "espresso" && [get ::settings(start_espresso_only_if_scale_connected) 0] == 1 && [get ::de1(scale_device_handle)] in {{} 0}} {
                    fail 409 scale_disconnected "该配方要求秤连接后才能启动"
                }
                set command [dict get {espresso ::start_espresso flush ::start_flush steam ::start_steam hotwater ::start_water} $operation]
            }
            default {fail 404 unknown_operation "未知机器操作"}
        }
        require_cmd $command
        $command
        return [dict create accepted 1 operation $operation device_confirmed 0]
    }
    proc plugins_status {} {
        set out {}
        foreach name {flow_lut crystal_grinder} {
            set ns ::plugins::$name
            # de1app peeks/sources disabled plugins too. Only its loader flag
            # proves main ran; namespace existence does not.
            set data [dict create loaded [expr {[get ${ns}::plugin_loaded 0] == 1}] \
                enabled [expr {$name in [get ::settings(enabled_plugins)]}]]
            foreach key {version connected initialized operation} {
                if {[info exists ${ns}::$key]} {dict set data $key [set ${ns}::$key]}
            }
            dict set out $name $data
        }
        if {[llength [info commands ::plugins::decent_remote::hds::status]]} {dict set out hds [::plugins::decent_remote::hds::status]}
        return $out
    }
    proc grinder {kind} {
        require_cmd ::plugins::crystal_grinder::begin
        if {[get ::plugins::crystal_grinder::connected 0] != 1} {fail 409 disconnected "小方未连接"}
        if {$kind eq "start"} {
            guard {Idle Sleep}
            if {[get ::plugins::crystal_grinder::initialized 0] != 1} {fail 409 not_ready "小方尚未读取完整参数"}
            if {[get ::plugins::crystal_grinder::operation] ne {}} {fail 409 busy "小方有操作正在执行"}
        }
        ::plugins::crystal_grinder::begin $kind
        return [dict create accepted 1 operation $kind device_confirmed 0]
    }
    proc legacy_status {} {
        set out [dict create is_active [expr {[state] eq "Sleep" ? "false" : "true"}]]
        if {[state] ne "Sleep"} {
            foreach key {espresso_count steaming_count} {dict set out $key [get ::settings($key)]}
        }
        return $out
    }
    proc legacy_details {} {
        require_cmd ::battery_percent
        set sub [get ::de1(substate)]
        set out [dict create state [state] substate [get ::de1_substate_types($sub) Unknown] battery_percent [::battery_percent] charger_on [get ::de1(usb_charger_on)]]
        if {[state] eq "Idle"} {
            require_cmd ::profile::filename_from_title ::water_tank_level_to_milliliters
            dict set out profile [::profile::filename_from_title [get ::settings(profile_title)]]
            foreach key {profile_filename profile_grinder_dose_weight grinder_dose_weight settings_profile_type final_desired_shot_weight final_desired_shot_weight_advanced final_desired_shot_volume final_desired_shot_volume_advanced espresso_temperature espresso_count steaming_count bean_brand bean_type bean_notes roast_date roast_level} {
                dict set out $key [get ::settings($key)]
            }
            dict set out skin [::profile::filename_from_title [get ::settings(skin)]]
            foreach key {head_temperature mix_temperature steam_heater_temperature} {
                set v [get ::de1($key)]
                if {$v ne {} && [string is double -strict $v] && ![catch {expr {floor($v*100)/100}} rounded]} {set v $rounded}
                dict set out $key $v
            }
            set level [get ::de1(water_level)]
            dict set out water_level_ml [expr {$level eq {} ? {} : [::water_tank_level_to_milliliters $level]}]
        } elseif {[state] eq "Espresso"} {
            foreach key {espresso_elapsed espresso_pressure espresso_weight espresso_flow espresso_flow_weight espresso_temperature_basket espresso_temperature_mix} {
                require_cmd ::$key
                dict set out $key [::$key range 0 end]
            }
        }
        return $out
    }
    proc legacy_sdb {} {
        require_plugin SDB ::plugins::SDB::shots
        set columns [::plugins::SDB::shots *]
        if {[catch {dict size $columns}]} {fail 502 invalid_sdb "SDB 返回格式无效"}
        set fields {clock grinder_setting grinder_model profile_title bean_desc bean_brand bean_type bean_notes drink_weight grinder_dose_weight target_drink_weight extraction_time filename espresso_enjoyment espresso_notes shot_desc}
        set count 0
        foreach field $fields {
            if {[dict exists $columns $field]} {set count [expr {max($count,[llength [dict get $columns $field]])}]}
        }
        set result {}
        for {set i 0} {$i < $count} {incr i} {
            set row {}
            foreach field $fields {
                set value {}
                if {[dict exists $columns $field]} {set value [lindex [dict get $columns $field] $i]}
                if {$field in {bean_notes espresso_notes}} {set value [string map {\n \\n} $value]}
                dict set row $field $value
            }
            lappend result $row
        }
        return $result
    }
    proc validate_profile_file {root} {
        require_cmd ::homedir
        set base [file normalize [file join [::homedir] profiles]]
        set file [file join $base $root.tcl]
        if {![file isfile $file]} {fail 404 profile_not_found "曲线文件不存在"}
        if {[file type $file] eq "link" || [file dirname [file normalize $file]] ne $base} {fail 422 invalid_profile "不接受链接或目录外曲线"}
        if {[file size $file] > 8388608} {fail 413 too_large "曲线文件过大"}
        set f [open $file r]
        fconfigure $f -encoding utf-8
        set code [catch {read $f} content options]
        close $f
        if {$code} {return -options $options $content}
        if {[catch {dict size $content}]} {fail 422 invalid_profile "曲线必须为 Tcl 数据列表，不是可执行脚本"}
        if {[llength [info commands ::plugins::decent_remote::profiles::validate]]} {
            ::plugins::decent_remote::profiles::validate $content
        }
        if {[dict exists $content advanced_shot_tcl] && [string trim [dict get $content advanced_shot_tcl]] ne {}} {
            fail 422 executable_profile "远程选择不接受带可执行 Tcl 的曲线"
        }
    }
    proc call {operation payload} {
        switch $operation {
            legacy.status {keys $payload {}; return [legacy_status]}
            legacy.details {keys $payload {}; return [legacy_details]}
            legacy.sdb {keys $payload {}; return [legacy_sdb]}
            legacy.flush {
                keys $payload {}; require_cmd ::logging::flush_log
                ::logging::flush_log
                return [dict create accepted 1]
            }
            legacy.power {
                keys $payload {active}
                if {![dict exists $payload active] || [dict get $payload active] ni {true false 1 0}} {fail 422 invalid_value "active 必须为布尔值"}
                guard
                set active [expr {[dict get $payload active] in {true 1}}]
                if {$active && [state] ne "Idle"} {machine wake}
                if {!$active && [state] ne "Sleep"} {machine sleep}
                return [dict create is_active [expr {$active ? "true" : "false"}] accepted 1 readback requested_target device_confirmed 0]
            }
            legacy.dye.next {
                keys $payload {timestamp}
                if {![dict exists $payload timestamp] || ![regexp {^[1-9][0-9]{0,18}$} [dict get $payload timestamp]] || ![string is wideinteger -strict [dict get $payload timestamp]]} {fail 422 invalid_timestamp "需要正整数出杯时间戳"}
                guard
                require_plugin DYE ::plugins::DYE::shots::source_next_from
                set fields {workflow_settings shot_profile ratio drink_weight grinder_dose_weight grinder_setting grinder_model workflow bean_brand bean_type roast_date roast_level bean_notes}
                ::plugins::DYE::shots::source_next_from [dict get $payload timestamp] {} $fields
                return [dict create accepted 1 device_confirmed 0]
            }
            status {
                keys $payload {}
                set out [dict create connected [connected] state [state] substate [get ::de1(substate)] recipe [recipe] readback app_cache \
                    remote_start_enabled [get ::plugins::decent_remote::api::allow_start 0]]
                foreach {field key} {temperature_c head_temperature mix_temperature_c mix_temperature steam_temperature_c steam_heater_temperature flow_ml_s flow pressure_bar pressure scale_weight_g scale_weight scale_flow_g_s scale_weight_rate} {
                    dict set out $field [get ::de1($key)]
                }
                dict set out scale_connected [expr {[get ::de1(scale_device_handle)] ni {{} 0}}]
                return $out
            }
            recipe.get {keys $payload {}; return [recipe]}
            recipe.patch {return [recipe_patch $payload]}
            profile.current {keys $payload {}; require_cmd ::plugins::decent_remote::device::profile_current; return [profile_current]}
            profile.patch {return [profile_patch $payload]}
            profile.restore {return [profile_restore $payload]}
            profile.save {return [profile_save $payload]}
            profile.save_as {return [profile_save_as $payload]}
            favorites.get {keys $payload {}; return [favorites_get]}
            favorites.patch {return [favorites_patch $payload]}
            shortcuts.get {keys $payload {}; return [shortcuts_get]}
            shortcuts.patch {return [shortcuts_patch $payload]}
            controls.get {keys $payload {}; return [control_get]}
            controls.patch {return [control_patch $payload]}
            scale.get {keys $payload {}; return [scale_get]}
            scale.patch {return [scale_patch $payload]}
            scheduler.get {keys $payload {}; return [scheduler_get]}
            scheduler.patch {return [scheduler_patch $payload]}
            charging.get {keys $payload {}; return [charging_get]}
            charging.patch {return [charging_patch $payload]}
            flow_compensation.get {keys $payload {}; return [flow_compensation_get]}
            flow_compensation.patch {return [flow_compensation_patch $payload]}
            settings.get {keys $payload {}; return [settings_get]}
            settings.patch {return [settings_patch $payload]}
            plugins.status {keys $payload {}; return [plugins_status]}
            scale.tare {
                keys $payload {}; guard
                if {[get ::de1(scale_device_handle)] in {{} 0}} {fail 409 scale_disconnected "秤未连接"}
                require_cmd ::device::scale::tare
                ::device::scale::tare
                return [dict create accepted 1 device_confirmed 0]
            }
            profile.select {
                keys $payload {filenameroot}; guard
                if {![dict exists $payload filenameroot]} {fail 422 missing_field "缺少曲线文件名"}
                set root [dict get $payload filenameroot]
                if {$root eq {} || [file tail $root] ne $root || $root in {. ..} || [string first "\\" $root] >= 0} {fail 422 invalid_profile "曲线文件名无效"}
                validate_profile_file $root
                require_cmd ::select_profile ::save_settings
                if {[::select_profile $root] eq "-1"} {fail 404 profile_not_found "曲线文件不存在"}
                if {[get ::settings(skin)] eq "Streamline"} {
                    require_cmd ::copy_settings_from_profile_to_streamline
                    ::copy_settings_from_profile_to_streamline
                }
                ::save_settings
                set result [dict create accepted 1 recipe [recipe] device_confirmed 0]
                # Return the exact selected parameter snapshot with this request;
                # the browser must not attach its receipt to a later GET.
                if {[llength [info commands ::plugins::decent_remote::device::profile_current]]} {
                    dict set result current_profile [profile_current]
                }
                return $result
            }
            machine.wake - machine.sleep - machine.stop - machine.espresso - machine.flush - machine.steam - machine.hotwater {
                keys $payload {}; return [machine [lindex [split $operation .] 1]]
            }
            grinder.start - grinder.stop {keys $payload {}; return [grinder [lindex [split $operation .] 1]]}
            default {fail 404 unknown_operation "不支持的操作：$operation"}
        }
    }
}
