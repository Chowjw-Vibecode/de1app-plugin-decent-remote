# Classic de1app 1.46.1.1 optional controls. Source is inert.
# Native setters only; all readback is app cache, never firmware confirmation.
namespace eval ::plugins::decent_remote::device {
    proc control_bool {key value} {
        if {$value ni {0 1 true false}} {fail 422 invalid_value "$key 必须为布尔值"}
        return [expr {$value in {1 true}}]
    }
    proc need_vars {names} {
        foreach name $names {if {![info exists $name]} {fail 501 unsupported "当前版本缺少设置或状态：$name"}}
    }
    proc controls_nonempty {payload allowed} {
        keys $payload $allowed
        if {![dict size $payload]} {fail 422 empty_patch "至少提供一个设置字段"}
    }
    proc controls_result {data} {dict merge $data [dict create accepted 1 readback app_cache device_confirmed 0]}
    proc controls_unknown {message} {fail 502 apply_unknown "应用值可能已更新；原生发送或保存结果未知，未声称回滚设备：$message"}
    proc controls_map {} {
        # public -> native key, factor, min, max, native quantum
        return {
            flush_flow_ml_s {flush_flow 1 1 10 0.1}
            flush_timeout_s {flush_seconds 1 3 120 0.1}
            hotwater_flow_ml_s {hotwater_flow 1 1 10 0.1}
            hotwater_temperature_c {water_temperature 1 0 100 1}
            hotwater_target {water_volume 1 3 255 1}
            hotwater_timeout_s {water_time_max 1 1 255 1}
            steam_flow_ml_s {steam_flow 100 0.4 2.5 1}
            steam_temperature_c {steam_temperature 1 135 170 1}
            steam_timeout_s {steam_timeout 1 0 255 1}
        }
    }
    proc control_get {} {
        need_vars {::settings(steam_disabled) ::settings(water_stop_on_scale)}
        set connected [expr {[get ::de1(scale_device_handle)] ni {{} 0}}]
        set byweight [expr {$connected && $::settings(water_stop_on_scale)}]
        set out [dict create readback app_cache steam_zero_timeout_s 255 \
            steam_enabled [expr {!$::settings(steam_disabled)}] water_stop_on_scale $::settings(water_stop_on_scale) \
            hotwater_target_unit [expr {$byweight ? "g" : "ml"}] \
            hotwater_stop_mode [expr {$byweight ? "scale_weight" : "firmware_volume"}] \
            target_effective [expr {!$connected || $byweight}] \
            hotwater_target_warning [expr {$connected && !$byweight ? "秤已连接且称重停止关闭：原生固件容量上限固定为250mL，所设目标容量不生效" : ""}] \
            firmware_hotwater_volume_ml [expr {$connected ? 250 : [get ::settings(water_volume)]}]]
        dict for {public spec} [controls_map] {
            lassign $spec native factor
            need_vars [list ::settings($native)]
            set value $::settings($native)
            if {[string is double -strict $value] && $value ne {}} {set value [expr {$value / double($factor)}]}
            dict set out $public $value
        }
        return $out
    }
    proc control_patch {payload} {
        set mapping [controls_map]
        controls_nonempty $payload [concat [dict keys $mapping] {steam_enabled water_stop_on_scale}]
        guard; control_get
        require_cmd ::save_settings
        set staged {}; set sends {}; set bundle 0
        dict for {key value} $payload {
            if {$key eq "steam_enabled"} {
                dict set staged steam_disabled [expr {![control_bool $key $value]}]
                set bundle 1
                continue
            }
            if {$key eq "water_stop_on_scale"} {
                dict set staged water_stop_on_scale [control_bool $key $value]
                continue
            }
            lassign [dict get $mapping $key] native factor low high quantum
            number $key $value $low $high
            need_vars [list ::settings($native)]
            set raw [expr {$value * $factor}]
            set units [expr {$raw / $quantum}]
            if {abs($units-round($units)) > 0.000001} {fail 422 invalid_precision "$key 精度超出设备支持"}
            if {$quantum == 1} {set raw [expr {int(round($raw))}]}
            dict set staged $native $raw
            switch $key {
                flush_flow_ml_s {dict set sends ::set_flush_flow_rate $raw}
                flush_timeout_s {dict set sends ::set_flush_timeout $raw}
                hotwater_flow_ml_s {dict set sends ::set_hotwater_flow_rate $raw}
                steam_flow_ml_s {dict set sends ::set_steam_flow $raw}
                default {set bundle 1}
            }
        }
        if {$bundle} {
            require_cmd ::de1_send_steam_hotwater_settings
            # Native bundle also transmits existing steam flow and flush settings.
            foreach command {::set_steam_flow ::set_flush_flow_rate ::set_flush_timeout} {dict unset sends $command}
        }
        foreach command [dict keys $sends] {require_cmd $command}
        dict for {key value} $staged {set ::settings($key) $value}
        if {[catch {
            if {$bundle} {::de1_send_steam_hotwater_settings}
            dict for {command value} $sends {$command $value}
            ::save_settings
        } message]} {controls_unknown $message}
        dict for {key value} $staged {if {$::settings($key) != $value} {controls_unknown "设置读回不一致：$key"}}
        return [controls_result [control_get]]
    }
    proc scale_get {} {
        need_vars {::settings(start_espresso_only_if_scale_connected) ::settings(stop_weight_before_seconds) ::settings(keep_scale_on) ::device::scale::autotare_states}
        return [dict create readback app_cache connected [expr {[get ::de1(scale_device_handle)] ni {{} 0}}] \
            scale_type [get ::settings(scale_type)] weight_g [get ::de1(scale_weight)] flow_g_s [get ::de1(scale_weight_rate)] \
            autotare_states $::device::scale::autotare_states require_scale $::settings(start_espresso_only_if_scale_connected) \
            stop_before_s $::settings(stop_weight_before_seconds) keep_scale_on $::settings(keep_scale_on)]
    }
    proc scale_patch {payload} {
        controls_nonempty $payload {require_scale stop_before_s keep_scale_on}
        guard; scale_get; require_cmd ::save_settings
        set staged {}
        dict for {key value} $payload {
            switch $key {
                require_scale {dict set staged start_espresso_only_if_scale_connected [control_bool $key $value]}
                keep_scale_on {dict set staged keep_scale_on [control_bool $key $value]}
                stop_before_s {
                    number $key $value -1 1.5
                    if {abs($value*100-round($value*100)) > 0.000001} {fail 422 invalid_precision "提前停止秒数支持0.01秒步长"}
                    dict set staged stop_weight_before_seconds $value
                }
            }
        }
        dict for {key value} $staged {set ::settings($key) $value}
        if {[catch {::save_settings} message]} {controls_unknown $message}
        return [controls_result [scale_get]]
    }
    proc controls_time {field value} {
        if {![regexp {^([01][0-9]|2[0-3]):([0-5][0-9])$} $value -> hh mm]} {fail 422 invalid_time "$field 必须为24小时制 HH:MM"}
        scan $hh %d h; scan $mm %d m
        return [expr {$h * 3600 + $m * 60}]
    }
    proc scheduler_get {} {
        need_vars {::settings(scheduler_enable) ::settings(scheduler_wake) ::settings(scheduler_sleep)}
        set out [dict create readback app_cache enabled $::settings(scheduler_enable) semantics forced_awake_interval local_timezone [clock format [clock seconds] -format %Z] overnight_supported 0]
        foreach {public native} {wake_time scheduler_wake awake_until scheduler_sleep} {
            set value $::settings($native)
            number $native $value 0 86399
            dict set out $public [format %02d:%02d [expr {int($value)/3600}] [expr {(int($value)%3600)/60}]]
        }
        dict set out awake_interval_enabled [expr {$::settings(scheduler_enable) == 1 && $::settings(scheduler_sleep)>$::settings(scheduler_wake)}]
        set next {}
        if {$::settings(scheduler_enable) == 1} {
            require_cmd ::next_alarm_time
            set next [::next_alarm_time $::settings(scheduler_wake)]
        }
        dict set out next_wake_at $next
        return $out
    }
    proc scheduler_patch {payload} {
        controls_nonempty $payload {enabled wake_time awake_until}
        guard; scheduler_get
        require_cmd ::set_alarms_for_de1_wake_sleep ::save_settings
        set staged [dict create scheduler_enable $::settings(scheduler_enable) scheduler_wake $::settings(scheduler_wake) scheduler_sleep $::settings(scheduler_sleep)]
        dict for {key value} $payload {
            switch $key {
                enabled {dict set staged scheduler_enable [control_bool $key $value]}
                wake_time {dict set staged scheduler_wake [controls_time $key $value]}
                awake_until {dict set staged scheduler_sleep [controls_time $key $value]}
            }
        }
        if {[dict get $staged scheduler_enable] && [dict get $staged scheduler_sleep]<[dict get $staged scheduler_wake]} {fail 422 overnight_unsupported "原生保持唤醒区间不支持跨午夜；结束时间须不早于开始时间"}
        if {[dict get $staged scheduler_enable]} {require_cmd ::next_alarm_time}
        dict for {key value} $staged {set ::settings($key) $value}
        # Registers the native future wake alarm; never invokes scheduler_wake,
        # start_schedIdle or the obsolete scheduler_sleep directly.
        if {[catch {::set_alarms_for_de1_wake_sleep; ::save_settings} message]} {controls_unknown $message}
        return [controls_result [scheduler_get]]
    }
    proc charging_get {} {
        need_vars {::settings(smart_battery_charging) ::de1(usb_charger_on)}
        set mode $::settings(smart_battery_charging)
        if {$mode ni {0 1 2}} {fail 501 unsupported "未知智能充电模式"}
        set percent {}
        if {[llength [info commands ::battery_percent]]} {set percent [::battery_percent]}
        return [dict create readback app_cache smart_charging_mode [lindex {off on night} $mode] \
            machine_usb_enabled $::de1(usb_charger_on) battery_percent $percent usb_override_temporary 1]
    }
    proc charging_patch {payload} {
        controls_nonempty $payload {smart_charging_mode machine_usb_enabled}
        guard; charging_get
        require_cmd ::save_settings
        set mode {}; set usb {}
        if {[dict exists $payload smart_charging_mode]} {
            set text [dict get $payload smart_charging_mode]
            set mode [lsearch -exact {off on night} $text]
            if {$mode < 0} {fail 422 invalid_value "智能充电模式须为 off、on 或 night"}
            require_cmd ::check_battery_charger ::set_usb_charger_on ::battery_percent
        }
        if {[dict exists $payload machine_usb_enabled]} {
            set usb [control_bool machine_usb_enabled [dict get $payload machine_usb_enabled]]
            require_cmd ::set_usb_charger_on
        }
        if {$mode ne {}} {set ::settings(smart_battery_charging) $mode}
        if {[catch {
            if {$mode ne {}} {::check_battery_charger}
            # Manual USB request is last; periodic native policy can override it,
            # even mode=off (the native off policy regularly enables USB).
            if {$usb ne {}} {::set_usb_charger_on $usb}
            ::save_settings
        } message]} {controls_unknown $message}
        if {$usb ne {} && [get ::de1(usb_charger_on)] != $usb} {controls_unknown "USB设置应用内读回不一致"}
        return [controls_result [charging_get]]
    }
    proc flow_compensation_get {} {
        if {[get ::plugins::flow_lut::plugin_loaded 0] != 1 ||
            ([info exists ::settings(enabled_plugins)] && "flow_lut" ni $::settings(enabled_plugins)) ||
            ![llength [info commands ::flow_lut_send::toggle]]} {
            return [dict create readback app_cache available 0 installed 0 enabled {} last_state unavailable last_message {原流量补偿插件未加载} changes {} ack {} current_profile_match 0]
        }
        need_vars {::flow_lut_send::enabled ::flow_lut_send::installed ::flow_lut_send::target_file ::flow_lut_send::target_title ::flow_lut_send::map_id}
        set last [get ::flow_lut_send::last]
        set state {}; set message {}
        if {[dict exists $last state]} {set state [dict get $last state]}
        if {[dict exists $last message]} {set message [dict get $last message]}
        set changes {}
        if {[dict exists $last changes]} {
            foreach change [dict get $last changes] {
                set item {}
                foreach key {target command estimate stage} {
                    if {[dict exists $change $key]} {dict set item $key [dict get $change $key]}
                }
                lappend changes $item
            }
        }
        set ack {}; set updated {}; set lastprofile {}
        if {[dict exists $last ack]} {set ack [dict get $last ack]}
        if {[dict exists $last updated]} {set updated [dict get $last updated]}
        if {[dict exists $last profile_filename]} {set lastprofile [dict get $last profile_filename]}
        set match [expr {[get ::settings(profile_filename)] eq $::flow_lut_send::target_file && [get ::settings(profile_title)] eq $::flow_lut_send::target_title}]
        set reason {}
        if {$state in {off bypass blocked maintenance error unconfirmed}} {set reason $message}
        return [dict create readback app_cache available 1 enabled $::flow_lut_send::enabled installed $::flow_lut_send::installed \
            target_file $::flow_lut_send::target_file target_title $::flow_lut_send::target_title map_id $::flow_lut_send::map_id \
            scope existing_plugin_scope last_state $state last_message $message \
            current_profile_match $match changes $changes ack $ack updated $updated \
            last_profile $lastprofile ack_scope last_published_send fallback_reason $reason]
    }
    proc flow_compensation_patch {payload} {
        controls_nonempty $payload {enabled}
        set desired [control_bool enabled [dict get $payload enabled]]
        guard
        if {![dict get [flow_compensation_get] available]} {fail 501 unsupported "原流量补偿插件未加载"}
        require_cmd ::plugins::flow_lut::ensure_free ::plugins::flow_lut::idle
        if {!$::flow_lut_send::installed} {fail 501 unsupported "原流量补偿发送包装尚未安装"}
        if {[catch {::plugins::flow_lut::ensure_free} message]} {fail 409 busy $message}
        if {$desired != $::flow_lut_send::enabled} {
            if {[catch {::flow_lut_send::toggle} message]} {controls_unknown $message}
        }
        if {$desired != $::flow_lut_send::enabled} {controls_unknown "发送补偿配置读回不一致"}
        return [controls_result [flow_compensation_get]]
    }
}
