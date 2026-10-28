# Flat Tcl profile data, never source/eval an uploaded file.
namespace eval ::plugins::decent_remote::profiles {
    proc fail {message} {::plugins::decent_remote::api::fail 422 invalid_profile $message}
    proc allowed {} {
        # Exact stable 1.46.1.1 profile_vars plus legacy metadata seen in native files.
        set keys {advanced_shot espresso_temperature_steps_enabled author read_only read_only_backup espresso_hold_time preinfusion_time espresso_pressure espresso_decline_time pressure_end espresso_temperature espresso_temperature_0 espresso_temperature_1 espresso_temperature_2 espresso_temperature_3 settings_profile_type flow_profile_preinfusion flow_profile_preinfusion_time flow_profile_hold flow_profile_hold_time flow_profile_decline flow_profile_decline_time flow_profile_minimum_pressure preinfusion_flow_rate profile_notes final_desired_shot_volume final_desired_shot_weight final_desired_shot_weight_advanced tank_desired_water_temperature final_desired_shot_volume_advanced profile_title profile_language preinfusion_stop_pressure profile_hide final_desired_shot_volume_advanced_count_start beverage_type maximum_pressure maximum_pressure_range_advanced maximum_flow_range_advanced maximum_flow maximum_pressure_range_default maximum_flow_range_default insert_preinfusion_pause profile_grinder_dose_weight profile_grinder_setting advanced_shot_tcl profile_video_help profile_editor water_temperature grinder_dose_weight grinder_setting}
        # Older official Hybrid/lever/Adaptive files retain this retired flag.
        # Stable 1.46.1.1 no longer references it, but loads it as ordinary data.
        # read_legacy(extra_vars=1) preserves these identity fields (profile.tcl).
        # The two unsuffixed range fields occur in older exported profiles;
        # stable 1.46.1.1 uses *_range_default / *_range_advanced instead.
        lappend keys preinfusion_guarantee original_profile_title profile_filename profile_to_save maximum_flow_range maximum_pressure_range
        if {[llength [info commands ::profile_vars]]} {set keys [concat $keys [::profile_vars]]}
        return $keys
    }
    proc finite {v lo hi} {
        expr {[string is double -strict $v] && ![catch {expr {$v >= $lo && $v <= $hi}} ok] && $ok}
    }
    proc validate {text} {
        if {[string bytelength $text] > 1048576} {fail "曲线文件超过 1 MiB"}
        if {[catch {dict size $text}] || ![dict exists $text profile_title]} {fail "曲线须为含 profile_title 的 Tcl 参数表"}
        if {[llength $text] != 2*[dict size $text]} {fail "曲线包含重复参数"}
        dict for {k v} $text {
            if {$k ni [allowed]} {fail "不允许曲线改写此设置：$k"}
            if {$k eq "advanced_shot_tcl" && [string trim $v] ne {}} {fail "远程接口不执行曲线内 Tcl 脚本"}
            if {$k eq "preinfusion_guarantee" && $v ni {0 1}} {fail "旧预浸标志必须为 0 或 1"}
            set high 10000
            if {$k in {maximum_flow_range maximum_pressure_range}} {set high 12}
            if {[string match *temperature* $k]} {set high 110}
            if {$k in {espresso_pressure pressure_end preinfusion_stop_pressure maximum_pressure flow_profile_minimum_pressure}} {set high 12}
            if {$k in {flow_profile_preinfusion flow_profile_hold flow_profile_decline preinfusion_flow_rate maximum_flow}} {set high 12}
            if {$k in {profile_grinder_dose_weight grinder_dose_weight}} {set high 60}
            set numeric {maximum_flow_range maximum_pressure_range espresso_hold_time preinfusion_time espresso_pressure espresso_decline_time pressure_end espresso_temperature espresso_temperature_0 espresso_temperature_1 espresso_temperature_2 espresso_temperature_3 flow_profile_preinfusion flow_profile_preinfusion_time flow_profile_hold flow_profile_hold_time flow_profile_decline flow_profile_decline_time flow_profile_minimum_pressure preinfusion_flow_rate final_desired_shot_volume final_desired_shot_weight final_desired_shot_weight_advanced tank_desired_water_temperature final_desired_shot_volume_advanced preinfusion_stop_pressure final_desired_shot_volume_advanced_count_start maximum_pressure maximum_pressure_range_advanced maximum_flow_range_advanced maximum_flow maximum_pressure_range_default maximum_flow_range_default profile_grinder_dose_weight water_temperature}
            if {$k in $numeric && ![finite $v 0 $high]} {fail "曲线参数 $k 数值无效"}
            if {$k eq "read_only_backup" && $v ne {}} {validate $v}
        }
        set type [::plugins::decent_remote::api::value $text settings_profile_type settings_2a]
        if {$type ni {settings_2a settings_2b settings_2c settings_2c2}} {fail "不支持的曲线类型"}
        if {$type in {settings_2c settings_2c2} && (![dict exists $text advanced_shot] || [dict get $text advanced_shot] eq {})} {fail "高级曲线不能为空"}
        if {[dict exists $text advanced_shot]} {
            set steps [dict get $text advanced_shot]
            if {[catch {llength $steps} n] || $n > 20} {fail "曲线分段格式或数量无效"}
            foreach step $steps {
                if {[catch {dict size $step}]} {fail "曲线分段须为参数表"}
                if {[llength $step] != 2*[dict size $step]} {fail "曲线分段包含重复参数"}
                foreach key {pump sensor transition temperature seconds} {if {![dict exists $step $key]} {fail "曲线分段缺少 $key"}}
                foreach {key values} {pump {pressure flow} sensor {coffee water} transition {fast smooth}} {if {[dict get $step $key] ni $values} {fail "曲线分段 $key 无效"}}
                if {![dict exists $step [dict get $step pump]]} {fail "曲线分段缺少目标压力或流量"}
                foreach {key high} {temperature 110 seconds 10000 pressure 12 flow 12 volume 10000 weight 2000 max_flow_or_pressure 12 max_flow_or_pressure_range 12 exit_pressure_over 12 exit_pressure_under 12 exit_flow_over 12 exit_flow_under 12 exit_if 1} {
                    if {[dict exists $step $key] && ![finite [dict get $step $key] 0 $high]} {fail "曲线分段 $key 数值无效"}
                }
            }
        }
        return $text
    }
    proc upload {name text} {
        validate $text
        set p [::plugins::decent_remote::api::path profiles $name .tcl]
        file mkdir [file dirname $p]
        # Same-directory atomic replace; a failed write never truncates old data.
        set temp "$p.remote-[pid]-[clock clicks].tmp"
        set f {}
        if {[catch {
            set f [open $temp {WRONLY CREAT EXCL}]
            fconfigure $f -encoding utf-8 -translation lf
            puts -nonewline $f $text
            close $f; set f {}
            if {[::plugins::decent_remote::api::read_file $temp] ne $text} {error "写入核对失败"}
            file rename -force $temp $p
        } err opts]} {
            if {$f ne {}} {catch {close $f}}
            catch {file delete $temp}
            return -options $opts $err
        }
        return $name
    }
}

namespace eval ::plugins::decent_remote::profiles {
    # Decode typed JSON through the shared duplicate-key-checking parser.
    proc scalar {node} {
        if {[lindex $node 0] ni {string number boolean}} {fail "曲线字段必须是单值"}
        return [lindex $node 1]
    }
    proc json_profile {content} {
        set tree [::plugins::decent_remote::api::json_tree $content]
        foreach k {version type title steps} {if {![dict exists $tree $k]} {fail "JSON 曲线缺少 $k"}}
        if {[scalar [dict get $tree version]] ne "2" || [scalar [dict get $tree type]] ne "advanced"} {fail "仅支持原生 version 2 advanced JSON 曲线"}
        set map {title profile_title author author notes profile_notes beverage_type beverage_type tank_temperature tank_desired_water_temperature target_weight final_desired_shot_weight_advanced target_volume final_desired_shot_volume_advanced target_volume_count_start final_desired_shot_volume_advanced_count_start lang profile_language hidden profile_hide reference_file profile_filename}
        set out [dict create settings_profile_type settings_2c advanced_shot_tcl {}]
        dict for {k node} $tree {
            if {[dict exists $map $k]} {dict set out [dict get $map $k] [scalar $node]; continue}
            switch -- $k {
                version - type - steps {}
                legacy_profile_type {
                    if {[scalar $node] ni {settings_2c settings_2c2 {}}} {fail "JSON 高级曲线的 legacy_profile_type 不一致"}
                }
                changes_since_last_espresso {
                    if {[lindex $node 1] ne {}} {fail "无法无损导入 changes_since_last_espresso"}
                }
                default {fail "不支持的 JSON 曲线字段：$k"}
            }
        }
        if {[lindex [dict get $tree steps] 0] ne "array"} {fail "steps 必须是数组"}
        set steps {}
        foreach node [lindex [dict get $tree steps] 1] {
            if {[lindex $node 0] ne "object"} {fail "分段必须是对象"}
            set fields [lindex $node 1]
            # Inactive controls are explicit; no dose or beverage target is invented.
            set step [dict create exit_if 0 exit_type pressure_over exit_pressure_over 0 exit_pressure_under 0 exit_flow_over 0 exit_flow_under 0 max_flow_or_pressure 0 max_flow_or_pressure_range 0]
            dict for {k v} $fields {
                if {$k in {name temperature sensor pump transition pressure flow seconds volume weight}} {
                    dict set step $k [scalar $v]
                } elseif {$k eq "exit"} {
                    if {[lindex $v 0] ne "object"} {fail "exit 必须是对象"}
                    set e [::plugins::decent_remote::api::json_scalars [lindex $v 1]]
                    if {[lsort [dict keys $e]] ne {condition type value}} {fail "exit 字段不完整或包含未知字段"}
                    if {[dict get $e type] ni {pressure flow} || [dict get $e condition] ni {over under}} {fail "exit 类型无效"}
                    set kind "[dict get $e type]_[dict get $e condition]"
                    dict set step exit_if 1
                    dict set step exit_type $kind
                    dict set step exit_$kind [dict get $e value]
                } elseif {$k eq "limiter"} {
                    if {[lindex $v 0] ne "object"} {fail "limiter 必须是对象"}
                    set lim [::plugins::decent_remote::api::json_scalars [lindex $v 1]]
                    if {[lsort [dict keys $lim]] ne {range value}} {fail "limiter 字段不完整或包含未知字段"}
                    dict set step max_flow_or_pressure [dict get $lim value]
                    dict set step max_flow_or_pressure_range [dict get $lim range]
                } else {fail "不支持的 JSON 分段字段：$k"}
            }
            foreach k {name temperature sensor pump transition pressure flow seconds volume weight} {
                if {![dict exists $step $k]} {fail "JSON 原生分段缺少 $k"}
            }
            lappend steps $step
        }
        dict set out advanced_shot $steps
        return [validate $out]
    }
    proc import_payload {payload} {
        dict for {k v} $payload {if {$k ni {filename content format overwrite dry_run}} {fail "不支持的导入字段：$k"}}
        foreach k {filename content format} {if {![dict exists $payload $k]} {fail "导入缺少 $k"}}
        set overwrite 0; set dry 0
        foreach {k var} {overwrite overwrite dry_run dry} {
            if {[dict exists $payload $k]} {
                set v [dict get $payload $k]
                if {$v ni {0 1 true false}} {fail "$k 必须是布尔值"}
                set $var [expr {$v in {1 true}}]
            }
        }
        set format [dict get $payload format]
        if {$format ni {tcl json}} {fail "format 必须是 tcl 或 json"}
        set name [dict get $payload filename]
        set ext [file extension $name]
        if {$ext eq {}} {append name .tcl} elseif {$format eq "json" && $ext eq ".json"} {set name "[file rootname $name].tcl"}
        set p [::plugins::decent_remote::api::path profiles $name .tcl]
        # lstat catches dangling links as well as ordinary existing files.
        set exists [expr {![catch {file lstat $p stat}]}]
        if {$exists && $stat(type) ne "file"} {fail "目标必须是普通文件"}
        if {$exists && !$overwrite} {::plugins::decent_remote::api::fail 409 already_exists "同名曲线已存在"}
        set text [dict get $payload content]
        if {$format eq "json"} {set text [json_profile $text]} else {validate $text}
        if {[string trim [dict get $text profile_title]] eq {}} {fail "曲线标题不能为空"}
        if {[dict exists $text advanced_shot]} {
            foreach step [dict get $text advanced_shot] {
                if {[dict exists $step exit_if] && [dict get $step exit_if] ni {0 1}} {fail "exit_if 必须为 0 或 1"}
                if {[dict exists $step exit_type] && [dict get $step exit_type] ni {pressure_under pressure_over flow_under flow_over}} {fail "分段退出条件无效"}
                if {[dict exists $step exit_if] && [dict get $step exit_if] == 1 &&
                    (![dict exists $step exit_type] || ![dict exists $step exit_[dict get $step exit_type]])} {fail "分段退出阈值缺失"}
            }
        }
        set result [dict create filename $name title [dict get $text profile_title] format $format saved 0 readback validated]
        if {$dry} {return $result}
        file mkdir [file dirname $p]
        set temp "$p.import-[pid]-[clock clicks].tmp"
        set f {}
        if {[catch {
            set f [open $temp {WRONLY CREAT EXCL}]
            fconfigure $f -encoding utf-8 -translation lf
            puts -nonewline $f $text
            close $f; set f {}
            if {[::plugins::decent_remote::api::read_file $temp] ne $text} {error "导入文件核对失败"}
            if {$overwrite} {file rename -force $temp $p} else {file rename $temp $p}
            if {[::plugins::decent_remote::api::read_file $p] ne $text} {error "导入后文件核对失败"}
        } err opts]} {
            if {$f ne {}} {catch {close $f}}
            catch {file delete $temp}
            ::plugins::decent_remote::api::fail 500 import_unknown "曲线文件保存未确认，请读取文件核对后再操作"
        }
        dict set result saved 1
        dict set result readback file
        return $result
    }
}
