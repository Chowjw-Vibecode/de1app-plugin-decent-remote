# Native profile editing and Streamline presets. Sourcing this file is inert.
# Uploaded profile text is data: never source or eval it.
namespace eval ::plugins::decent_remote::device {
    proc editor_profile_data {} {
        require_cmd ::profile_vars ::plugins::decent_remote::profiles::validate
        set data {}
        foreach key [::profile_vars] {
            if {[info exists ::settings($key)]} {dict set data $key $::settings($key)}
        }
        # A profile script can change settings/start actions when selected later.
        if {[string trim [get ::settings(advanced_shot_tcl)]] ne {}} {
            fail 422 executable_profile "远程编辑不接受带可执行 Tcl 的曲线"
        }
        ::plugins::decent_remote::profiles::validate $data
        return $data
    }
    proc editor_root {root} {
        require_cmd ::plugins::decent_remote::api::filename
        ::plugins::decent_remote::api::filename "$root.tcl" .tcl
        if {$root eq {} || $root in {. ..}} {fail 422 invalid_filename "曲线文件名无效"}
        return $root
    }
    proc editor_integer {name value low high} {
        number $name $value $low $high
        if {![string is integer -strict $value]} {fail 422 invalid_value "$name 必须是整数"}
        return $value
    }
    proc editor_text {name value max} {
        if {[string length $value] > $max || [regexp {[\x00-\x08\x0b\x0c\x0e-\x1f]} $value]} {
            fail 422 invalid_value "$name 文字过长或含控制字符"
        }
        return $value
    }
    proc basic_profile_view {} {
        set type [get ::settings(settings_profile_type)]
        set result [dict create display_steps {} display_steps_readback unavailable basic_parameters {}]
        if {$type ni {settings_2a settings_2b}} {return $result}
        set fields {preinfusion_time preinfusion_flow_rate preinfusion_stop_pressure espresso_hold_time espresso_decline_time espresso_temperature_steps_enabled espresso_temperature_0 espresso_temperature_1 espresso_temperature_2 espresso_temperature_3 temp_bump_time_seconds}
        if {$type eq "settings_2a"} {
            set converter ::profile::pressure_to_advanced_list
            lappend fields espresso_pressure pressure_end maximum_flow maximum_flow_range_default
        } else {
            set converter ::profile::flow_to_advanced_list
            lappend fields flow_profile_hold flow_profile_decline maximum_pressure maximum_pressure_range_default
        }
        foreach key $fields {
            if {[info exists ::settings($key)]} {dict set result basic_parameters $key $::settings($key)}
        }
        # Reject malformed active values before the native converter can silently
        # skip a phase. Retain the declared parameters for a read-only diagnosis.
        set active_fields $fields
        lappend active_fields espresso_temperature
        foreach key $active_fields {
            if {[string match espresso_temperature_? $key] && [get ::settings(espresso_temperature_steps_enabled) 0] != 1} {continue}
            if {[info exists ::settings($key)] && [catch {number $key $::settings($key) 0 10000}]} {
                dict set result display_steps_readback invalid_parameters
                return $result
            }
        }
        if {[get ::settings(preinfusion_time) -1] == 0 && [get ::settings(espresso_hold_time) -1] == 0 && [get ::settings(espresso_decline_time) -1] == 0} {
            dict set result display_steps_readback empty
            return $result
        }
        # Native basic profiles keep their controls outside advanced_shot. That
        # variable may still contain a previously selected advanced profile.
        # Convert a local copy for display only: never sync, send, or write back.
        if {![llength [info commands $converter]]} {return $result}
        array set preview [array get ::settings]
        if {[catch {
            set generated [$converter preview]
            set steps [dict get $generated advanced_shot]
            foreach step $steps {dict size $step}
        }]} {return $result}
        dict set result display_steps $steps
        dict set result display_steps_readback native_conversion
        return $result
    }
    proc profile_current {} {
        set result [recipe]
        set advanced [expr {[get ::settings(settings_profile_type)] in {settings_2c settings_2c2}}]
        dict set result editable_steps $advanced
        dict set result steps [expr {$advanced ? [get ::settings(advanced_shot)] : {}}]
        if {!$advanced} {set result [dict merge $result [basic_profile_view]]}
        dict set result volume_count_start [expr {$advanced ? [get ::settings(final_desired_shot_volume_advanced_count_start)] : {}}]
        set volume_key [expr {$advanced ? "final_desired_shot_volume_advanced" : "final_desired_shot_volume"}]
        dict set result target_volume_ml [get ::settings($volume_key)]
        dict set result notes [get ::settings(profile_notes)]
        dict set result dirty [expr {[get ::settings(profile_has_changed) 0] == 1}]
        return $result
    }
    proc editor_steps {steps} {
        if {[catch {llength $steps} n] || $n < 1 || $n > 20} {fail 422 invalid_steps "需要 1 至 20 个完整分段"}
        set out {}; set i 0
        foreach step $steps {
            incr i
            keys $step {name popup pump sensor transition temperature seconds pressure flow volume weight max_flow_or_pressure max_flow_or_pressure_range exit_if exit_type exit_flow_under exit_flow_over exit_pressure_under exit_pressure_over}
            foreach key {pump sensor transition temperature seconds} {
                if {![dict exists $step $key]} {fail 422 missing_field "第 $i 段缺少 $key"}
            }
            foreach {key allowed} {pump {pressure flow} sensor {coffee water} transition {fast smooth}} {
                if {[dict get $step $key] ni $allowed} {fail 422 invalid_value "第 $i 段的 $key 无效"}
            }
            if {![dict exists $step [dict get $step pump]]} {fail 422 missing_field "第 $i 段缺少目标流量或压力"}
            set normalized [dict merge [dict create name "Step $i" popup {} pressure 0 flow 0 volume 0 weight 0 max_flow_or_pressure 0 max_flow_or_pressure_range 0.6 exit_if 0 exit_type flow_under exit_flow_under 0 exit_flow_over 0 exit_pressure_under 0 exit_pressure_over 0] $step]
            foreach {key high} {temperature 105 seconds 127 pressure 12 flow 12 volume 1023 weight 2000 max_flow_or_pressure 12 max_flow_or_pressure_range 12 exit_flow_under 12 exit_flow_over 12 exit_pressure_under 12 exit_pressure_over 12} {
                number "step.$key" [dict get $normalized $key] 0 $high
            }
            set enabled [dict get $normalized exit_if]
            if {![string is boolean -strict $enabled]} {fail 422 invalid_value "exit_if 必须是布尔值"}
            dict set normalized exit_if [expr {$enabled ? 1 : 0}]
            if {[dict get $normalized exit_type] ni {pressure_under pressure_over flow_under flow_over}} {
                fail 422 invalid_value "退出条件类型无效"
            }
            if {[dict get $normalized exit_if] && ![dict exists $step "exit_[dict get $normalized exit_type]"]} {
                fail 422 missing_field "启用退出条件时必须明确给出对应阈值"
            }
            editor_text name [dict get $normalized name] 200
            editor_text popup [dict get $normalized popup] 1000
            lappend out $normalized
        }
        if {[get ::settings(insert_preinfusion_pause) 0] == 1 && $n == 20} {
            fail 422 too_many_steps "启用原生额外预浸暂停时最多允许 19 段"
        }
        return $out
    }
    proc profile_patch {payload} {
        keys $payload {steps dose_g yield_g temperature_c target_volume_ml volume_count_start notes}
        if {![dict size $payload]} {fail 422 empty_patch "至少提供一个曲线字段"}
        guard
        require_cmd ::profile::sync_from_legacy ::send_de1_settings_soon
        set candidate [editor_profile_data]
        set advanced [expr {[get ::settings(settings_profile_type)] in {settings_2c settings_2c2}}]
        if {([dict exists $payload steps] || [dict exists $payload volume_count_start]) && !$advanced} {
            fail 422 advanced_profile_required "分段编辑只适用于高级曲线；基本曲线可调整配方"
        }
        if {[dict exists $payload steps]} {
            dict set candidate advanced_shot [editor_steps [dict get $payload steps]]
            set first [dict get [lindex [dict get $candidate advanced_shot] 0] temperature]
            if {[dict exists $payload temperature_c]} {number temperature_c [dict get $payload temperature_c] 0 105}
            if {[dict exists $payload temperature_c] && [dict get $payload temperature_c] != $first} {
                fail 422 conflicting_temperature "完整分段与全局温度同时提交时，温度必须等于首段温度"
            }
            dict set candidate espresso_temperature $first
        }
        if {[dict exists $payload temperature_c]} {
            number temperature_c [dict get $payload temperature_c] 0 105
            if {![dict exists $payload steps]} {
                require_cmd ::change_espresso_temperature
                number current_temperature [get ::settings(espresso_temperature)] 0 105
                set delta [expr {[dict get $payload temperature_c] - $::settings(espresso_temperature)}]
                if {$advanced} {
                    set changed {}
                    foreach step [dict get $candidate advanced_shot] {
                        set next [expr {[dict get $step temperature] + $delta}]
                        number step_temperature $next 0 105
                        dict set step temperature $next
                        lappend changed $step
                    }
                    dict set candidate advanced_shot $changed
                } elseif {[get ::settings(espresso_temperature_steps_enabled) 0] == 1} {
                    foreach key {espresso_temperature_1 espresso_temperature_2 espresso_temperature_3} {
                        number $key [get ::settings($key)] 0 105
                        set next [expr {$::settings($key) + $delta}]
                        number $key $next 0 105
                        dict set candidate $key $next
                    }
                    dict set candidate espresso_temperature_0 [dict get $payload temperature_c]
                }
                dict set candidate espresso_temperature [dict get $payload temperature_c]
            }
        }
        if {[dict exists $payload dose_g]} {
            number dose_g [dict get $payload dose_g] 0.1 30
            dict set candidate profile_grinder_dose_weight [dict get $payload dose_g]
        }
        if {[dict exists $payload yield_g]} {
            number yield_g [dict get $payload yield_g] 0 2000
            require_cmd ::streamline_set_drink_weight ::device::scale::expecting_present
            foreach key {final_desired_shot_weight final_desired_shot_weight_advanced} {dict set candidate $key [dict get $payload yield_g]}
            foreach key {final_desired_shot_volume final_desired_shot_volume_advanced} {dict set candidate $key 0}
        }
        if {[dict exists $payload target_volume_ml]} {
            number target_volume_ml [dict get $payload target_volume_ml] 0 2000
            set volume_key [expr {$advanced ? "final_desired_shot_volume_advanced" : "final_desired_shot_volume"}]
            dict set candidate $volume_key [dict get $payload target_volume_ml]
        }
        if {[dict exists $payload volume_count_start]} {
            editor_integer volume_count_start [dict get $payload volume_count_start] 0 [llength [dict get $candidate advanced_shot]]
            dict set candidate final_desired_shot_volume_advanced_count_start [dict get $payload volume_count_start]
        }
        if {$advanced && [dict exists $candidate final_desired_shot_volume_advanced_count_start]} {
            editor_integer volume_count_start [dict get $candidate final_desired_shot_volume_advanced_count_start] 0 [llength [dict get $candidate advanced_shot]]
        }
        if {[dict exists $payload notes]} {dict set candidate profile_notes [editor_text notes [dict get $payload notes] 10000]}
        ::plugins::decent_remote::profiles::validate $candidate
        set before [snapshot]
        if {[catch {
            if {[dict exists $payload temperature_c] && ![dict exists $payload steps]} {::change_espresso_temperature $delta}
            if {[dict exists $payload yield_g]} {::streamline_set_drink_weight [dict get $payload yield_g]}
            array set ::settings $candidate
            if {[dict exists $payload dose_g]} {set ::settings(grinder_dose_weight) [dict get $payload dose_g]}
            set ::settings(profile_has_changed) 1
            ::profile::sync_from_legacy
            if {[llength [info commands ::update_de1_explanation_chart]]} {::update_de1_explanation_chart}
            if {[llength [info commands ::profile_has_changed_set_colors]]} {::profile_has_changed_set_colors}
        } err]} {
            restore $before; catch {::profile::sync_from_legacy}
            fail 500 apply_failed "曲线修改失败，已恢复应用设置；未提交发送：$err"
        }
        if {[catch {::send_de1_settings_soon} err]} {fail 502 send_unknown "曲线已在应用更新，发送结果未知：$err"}
        return [dict create accepted 1 temporary 1 device_confirmed 0 readback app_cache current_profile [profile_current]]
    }
    proc profile_restore {payload} {
        keys $payload {}; guard
        set root [editor_root [get ::settings(profile_filename)]]
        # Existing adapter validates file as data, then follows native select/copy/save.
        set result [call profile.select [dict create filenameroot $root]]
        dict set result current_profile [profile_current]
        return $result
    }
    proc editor_saved_check {root expected} {
        set file [::plugins::decent_remote::api::path profiles "$root.tcl" .tcl]
        set actual [::plugins::decent_remote::profiles::validate [::plugins::decent_remote::api::read_file $file]]
        # read_only and read_only_backup are intentionally maintained by native save_profile.
        dict for {key value} $expected {
            if {$key in {read_only read_only_backup}} {continue}
            if {![dict exists $actual $key]} {error "已保存曲线缺少 $key"}
            if {$key eq "settings_profile_type" && $value eq "settings_2c2" && [dict get $actual $key] eq "settings_2c"} {continue}
            if {[dict get $actual $key] ne $value} {error "已保存曲线读回不一致：$key"}
        }
        set json_file [::plugins::decent_remote::api::path profiles_v2 "$root.json" .json]
        set raw [::plugins::decent_remote::api::read_file $json_file]
        if {![::json::validate $raw]} {error "原生 JSON 导出无效"}
        set exported [::json::json2dict $raw]
        if {![dict exists $exported title] || [dict get $exported title] ne [dict get $expected profile_title]} {error "原生 JSON 标题读回不一致"}
    }
    proc editor_save {root title as_new} {
        guard
        require_cmd ::save_profile ::save_settings ::profile::sync_from_legacy ::profile::save ::homedir ::send_de1_settings_soon
        set root [editor_root $root]
        editor_text title $title 200
        if {[string trim $title] eq {}} {fail 422 invalid_value "曲线标题不能为空"}
        if {[llength [info commands ::translate]] && $title eq [::translate Saved]} {fail 422 invalid_value "请勿使用原生保存提示作为标题"}
        set tcl_file [::plugins::decent_remote::api::path profiles "$root.tcl" .tcl]
        set json_file [::plugins::decent_remote::api::path profiles_v2 "$root.json" .json]
        if {$as_new && ([file exists $tcl_file] || [file exists $json_file])} {fail 409 profile_exists "另存目标已存在；不会覆盖"}
        if {!$as_new} {
            validate_profile_file $root
            if {[get ::settings(read_only) 0] == 1} {fail 409 read_only_profile "这是只读原版曲线，请另存为新曲线"}
        }
        set expected [editor_profile_data]
        dict set expected profile_title $title
        # Native save uses this widget even with do_saved_msg=0 when forming (not scheduling) a command.
        if {![info exists ::globals(widget_profile_name_to_save)]} {fail 501 unsupported "当前 App 未加载原生曲线保存界面"}
        if {$as_new} {
            dict set expected read_only 0
            dict unset expected read_only_backup
        }
        ::plugins::decent_remote::profiles::validate $expected
        array set ::settings $expected
        if {$as_new} {unset -nocomplain ::settings(read_only_backup)}
        set ::settings(profile_filename) $root
        set ::settings(original_profile_title) $title
        set ::settings(profile) $title
        if {[catch {
            ::profile::sync_from_legacy
            ::save_profile 0
            if {$::settings(profile_filename) ne $root} {error "原生保存改变了目标文件名"}
            editor_saved_check $root $expected
            ::save_settings
            ::send_de1_settings_soon
        } err]} {
            # Native save writes Tcl and JSON separately. Do not claim a disk rollback.
            fail 502 save_unknown "原生保存或读回未完成；文件可能已更新，请先查询：$err"
        }
        return [dict create accepted 1 saved 1 temporary 0 filename "$root.tcl" json_filename "$root.json" current_profile [profile_current] readback files device_confirmed 0]
    }
    proc profile_save {payload} {
        keys $payload {}
        return [editor_save [get ::settings(profile_filename)] [get ::settings(profile_title)] 0]
    }
    proc profile_save_as {payload} {
        keys $payload {filename title}
        foreach key {filename title} {if {![dict exists $payload $key]} {fail 422 missing_field "缺少 $key"}}
        set filename [::plugins::decent_remote::api::filename [dict get $payload filename] .tcl]
        return [editor_save [file rootname $filename] [dict get $payload title] 1]
    }
    proc editor_streamline {} {
        require_cmd ::refresh_favorite_profile_button_labels ::refresh_favorite_dosebev_button_labels ::refresh_favorite_temperature_button_labels
        foreach key {favorite_profiles favorite_dosebevs favorite_temperatures} {
            if {![info exists ::settings($key)] || [catch {dict size $::settings($key)}]} {fail 501 unsupported "当前皮肤没有可用的 Streamline 常用设置"}
        }
    }
    proc favorites_get {} {
        editor_streamline
        set rows {}; set data $::settings(favorite_profiles)
        for {set slot 1} {$slot <= 5} {incr slot} {
            lappend rows [dict create slot $slot profile [::plugins::decent_remote::api::value [::plugins::decent_remote::api::value $data $slot {}] name] title [string trim [::plugins::decent_remote::api::value [::plugins::decent_remote::api::value $data $slot {}] title]]]
        }
        set selected [::plugins::decent_remote::api::value [::plugins::decent_remote::api::value $data selected {}] number 0]
        return [dict create slots $rows selected_slot $selected readback app_cache]
    }
    proc favorites_patch {payload} {
        keys $payload {slots}; guard; editor_streamline; require_cmd ::save_settings
        if {![dict exists $payload slots] || [llength [dict get $payload slots]] < 1 || [llength [dict get $payload slots]] > 5} {fail 422 invalid_slots "需要 1 至 5 个常用位置"}
        set data $::settings(favorite_profiles); set seen {}
        foreach row [dict get $payload slots] {
            keys $row {slot profile}
            foreach key {slot profile} {if {![dict exists $row $key]} {fail 422 missing_field "常用位置缺少 $key"}}
            set slot [editor_integer slot [dict get $row slot] 1 5]
            if {$slot in $seen} {fail 422 duplicate_slot "同一位置不能重复提交"}; lappend seen $slot
            set root [dict get $row profile]
            set title { }
            if {$root ne {}} {
                editor_root $root
                validate_profile_file $root
                set file [::plugins::decent_remote::api::path profiles "$root.tcl" .tcl]
                set title [dict get [::plugins::decent_remote::api::read_file $file] profile_title]
                if {[string trim $title] eq {}} {fail 422 invalid_profile "常用曲线标题不能为空"}
            }
            dict set data $slot name $root
            dict set data $slot title $title
        }
        set used_roots {}; set used_titles {}; set selected 0
        for {set slot 1} {$slot <= 5} {incr slot} {
            if {![dict exists $data $slot]} {dict set data $slot [dict create name {} title { }]}
            set root [dict get $data $slot name]; set title [dict get $data $slot title]
            if {$root eq {}} {dict set data $slot title { }; continue}
            set display [file tail $title]
            if {$root in $used_roots || $display in $used_titles} {fail 422 duplicate_profile "Streamline 不支持重复曲线或重名常用按钮"}
            lappend used_roots $root; lappend used_titles $display
            if {$display eq [get ::settings(profile_title)]} {set selected $slot}
        }
        # Native refresh otherwise schedules a delayed curve selection on title match.
        dict set data selected number $selected
        set ::settings(favorite_profiles) $data
        if {[catch {::refresh_favorite_profile_button_labels; ::save_settings} err]} {fail 502 apply_unknown "常用位置已更新，刷新或保存结果未知：$err"}
        return [dict create accepted 1 device_confirmed 0 favorites [favorites_get] readback app_cache]
    }
    proc shortcuts_get {} {
        editor_streamline
        set doses {}; set temps {}
        for {set slot 1} {$slot <= 4} {incr slot} {
            set row [::plugins::decent_remote::api::value $::settings(favorite_dosebevs) $slot {}]
            lappend doses [dict create slot $slot dose_g [::plugins::decent_remote::api::value $row value] yield_g [::plugins::decent_remote::api::value $row value2]]
            set row [::plugins::decent_remote::api::value $::settings(favorite_temperatures) $slot {}]
            lappend temps [dict create slot $slot temperature_c [::plugins::decent_remote::api::value $row value]]
        }
        return [dict create dose_yield $doses temperatures $temps readback app_cache]
    }
    proc shortcuts_patch {payload} {
        keys $payload {dose_yield temperatures}; guard; editor_streamline; require_cmd ::save_settings
        if {![dict size $payload]} {fail 422 empty_patch "至少提供一组快捷值"}
        set doses $::settings(favorite_dosebevs); set temps $::settings(favorite_temperatures)
        dict for {group rows} $payload {
            if {[llength $rows] < 1 || [llength $rows] > 4} {fail 422 invalid_slots "每组需要 1 至 4 个快捷值"}
            set seen {}
            set fields [expr {$group eq "dose_yield" ? {slot dose_g yield_g} : {slot temperature_c}}]
            foreach row $rows {
                keys $row $fields
                foreach key $fields {if {![dict exists $row $key]} {fail 422 missing_field "快捷值缺少 $key"}}
                set slot [editor_integer slot [dict get $row slot] 1 4]
                if {$slot in $seen} {fail 422 duplicate_slot "同一位置不能重复提交"}; lappend seen $slot
                if {$group eq "dose_yield"} {
                    number dose_g [dict get $row dose_g] 0.1 30
                    number yield_g [dict get $row yield_g] 0 2000
                    dict set doses $slot value [dict get $row dose_g]
                    dict set doses $slot value2 [dict get $row yield_g]
                } else {
                    number temperature_c [dict get $row temperature_c] 0 105
                    dict set temps $slot value [dict get $row temperature_c]
                }
            }
        }
        set ::settings(favorite_dosebevs) $doses; set ::settings(favorite_temperatures) $temps
        if {[catch {
            if {[dict exists $payload dose_yield]} {::refresh_favorite_dosebev_button_labels}
            if {[dict exists $payload temperatures]} {::refresh_favorite_temperature_button_labels}
            ::save_settings
        } err]} {fail 502 apply_unknown "快捷值已更新，刷新或保存结果未知：$err"}
        return [dict create accepted 1 device_confirmed 0 shortcuts [shortcuts_get] readback app_cache]
    }
}
