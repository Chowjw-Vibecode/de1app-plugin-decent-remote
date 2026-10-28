# Pure routing. No socket or hardware work on source.
package require json
package require json::write
namespace eval ::plugins::decent_remote::api {
    variable token {}
    variable allow_start 0
    variable root {}
    variable seen {}
    variable adapter ::plugins::decent_remote::device::call
    variable object_fields {recipe settings flow_lut crystal_grinder hds controls scale scheduler charging flow_compensation current_profile favorites shortcuts basic_parameters}
    variable object_array_fields {steps display_steps slots dose_yield temperatures changes}
    variable string_array_fields {autotare_states}
    variable boolean_fields {accepted temporary device_confirmed connected scale_connected loaded initialized enabled installed eligible app_applied available require_scale keep_scale_on steam_enabled water_stop_on_scale machine_usb_enabled usb_override_temporary current_profile_match ack overnight_supported awake_interval_enabled target_effective editable_steps dirty saved remote_start_enabled in_flight}
    variable number_fields {dose_g yield_g temperature_c mix_temperature_c steam_temperature_c flow_ml_s pressure_bar scale_weight_g scale_flow_g_s preheat_phase1_flow_ml_s preheat_phase2_flow_ml_s preheat_timeout_s idle_temperature_c sleep_timeout_minutes awake_brightness sleep_brightness flush_flow_ml_s flush_timeout_s hotwater_flow_ml_s hotwater_temperature_c hotwater_target hotwater_timeout_s firmware_hotwater_volume_ml steam_flow_ml_s steam_timeout_s steam_zero_timeout_s next_wake_at weight_g flow_g_s stop_before_s battery_percent target command estimate stage updated slot selected_slot target_volume_ml volume_count_start temperature seconds flow pressure volume weight max_flow_or_pressure max_flow_or_pressure_range exit_if exit_pressure_over exit_pressure_under exit_flow_over exit_flow_under http_status started_at_ms finished_at_ms queued_at_ms confirmed_at_ms}
    lappend number_fields preinfusion_time preinfusion_flow_rate preinfusion_stop_pressure espresso_hold_time espresso_decline_time espresso_temperature_steps_enabled espresso_temperature_0 espresso_temperature_1 espresso_temperature_2 espresso_temperature_3 temp_bump_time_seconds espresso_pressure pressure_end maximum_flow maximum_flow_range_default flow_profile_hold flow_profile_decline maximum_pressure maximum_pressure_range_default
    proc fail {status code message} {return -code error -errorcode [list REMOTE $status $code] $message}
    proc valid_token {value} {
        expr {[string length $value] >= 8 && [string length $value] <= 128 && ![regexp {[^\x21-\x7e]} $value]}
    }
    proc str {v} {return [::json::write string $v]}
    proc object {d} {
        variable object_fields; variable object_array_fields; variable string_array_fields; variable boolean_fields; variable number_fields
        set fields {}
        dict for {k v} $d {
            if {$k in $object_fields} {set j [object $v]} elseif {$k in $object_array_fields} {
                set rows {}; foreach row $v {lappend rows [object $row]}; set j [::json::write array {*}$rows]
            } elseif {$k in $string_array_fields} {
                set rows {}; foreach row $v {lappend rows [str $row]}; set j [::json::write array {*}$rows]
            } elseif {$k in $boolean_fields && [string is boolean -strict $v]} {
                set j [expr {$v ? "true" : "false"}]
            } elseif {$k in $number_fields && [regexp {^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$} $v]} {set j $v} else {set j [str $v]}
            lappend fields $k $j
        }
        return [::json::write object {*}$fields]
    }
    proc response {status body {type application/json}} {return [dict create status $status body $body type $type]}
    proc value {d k {fallback {}}} {if {[dict exists $d $k]} {return [dict get $d $k]}; return $fallback}
    proc filename {name extension} {
        if {$name eq {} || [file tail $name] ne $name || [string first "\\" $name] >= 0 || [regexp {[\x00-\x1f%]} $name] || [file extension $name] ne $extension} {fail 422 invalid_filename "文件名无效"}
        return $name
    }
    proc path {dir name ext} {
        variable root
        filename $name $ext
        set base [file normalize [file join $root $dir]]
        set p [file join $base $name]
        if {[file exists $p] && ([file type $p] eq "link" || [file dirname [file normalize $p]] ne $base)} {fail 422 invalid_filename "不接受链接或目录外文件"}
        return $p
    }
    proc read_file {p} {
        if {![file isfile $p]} {fail 404 not_found "文件不存在"}
        if {[file size $p] > 8388608} {fail 413 too_large "文件过大"}
        set f [open $p r]; fconfigure $f -translation lf -encoding utf-8
        set s [read $f]; close $f
        return $s
    }
    proc files {dir ext} {
        variable root
        set out {}
        foreach n [lsort [glob -nocomplain -tails -directory [file join $root $dir] *$ext]] {
            if {![catch {path $dir $n $ext}]} {lappend out [str $n]}
        }
        return [::json::write array {*}$out]
    }
    proc invoke {op payload} {variable adapter; return [response 200 [object [{*}$adapter $op $payload]]]}
    proc route {method uri body {headers {}}} {
        if {![string match /api/v1/* $uri]} {return [::plugins::decent_remote::legacy::route $method $uri $headers $body]}
        variable allow_start
        # All mutating operations have an exact method and path.
        set key "$method $uri"
        switch -- $key {
            "GET /api/v1/status" {return [invoke status {}]}
            "GET /api/v1/recipe" {return [invoke recipe.get {}]}
            "POST /api/v1/recipe" {return [invoke recipe.patch [body_object $body]]}
            "GET /api/v1/settings" {return [invoke settings.get {}]}
            "POST /api/v1/settings" {return [invoke settings.patch [body_object $body]]}
            "GET /api/v1/plugins" {return [invoke plugins.status {}]}
            "GET /api/v1/profile" {return [invoke profile.current {}]}
            "POST /api/v1/profile" {return [invoke profile.patch [body_structured $body {steps}]]}
            "POST /api/v1/profile/restore" {return [invoke profile.restore [body_object $body]]}
            "POST /api/v1/profile/save" {return [invoke profile.save [body_object $body]]}
            "POST /api/v1/profile/save-as" {return [invoke profile.save_as [body_object $body]]}
            "POST /api/v1/profiles/import" {
                return [response 200 [object [::plugins::decent_remote::profiles::import_payload [body_object $body]]]]
            }
            "GET /api/v1/favorites" {return [invoke favorites.get {}]}
            "POST /api/v1/favorites" {return [invoke favorites.patch [body_structured $body {slots}]]}
            "GET /api/v1/shortcuts" {return [invoke shortcuts.get {}]}
            "POST /api/v1/shortcuts" {return [invoke shortcuts.patch [body_structured $body {dose_yield temperatures}]]}
            "GET /api/v1/controls" {return [invoke controls.get {}]}
            "POST /api/v1/controls" {return [invoke controls.patch [body_object $body]]}
            "GET /api/v1/scale" {return [invoke scale.get {}]}
            "POST /api/v1/scale" {return [invoke scale.patch [body_object $body]]}
            "GET /api/v1/scheduler" {return [invoke scheduler.get {}]}
            "POST /api/v1/scheduler" {return [invoke scheduler.patch [body_object $body]]}
            "GET /api/v1/charging" {return [invoke charging.get {}]}
            "POST /api/v1/charging" {return [invoke charging.patch [body_object $body]]}
            "GET /api/v1/flow-compensation" {return [invoke flow_compensation.get {}]}
            "POST /api/v1/flow-compensation" {return [invoke flow_compensation.patch [body_object $body]]}
            "GET /api/v1/profiles" - "GET /api/profile" {return [response 200 [files profiles .tcl]]}
            "GET /api/v1/shots" - "GET /api/shot" {return [response 200 [files history .shot]]}
            "GET /api/v1/shots/json" {return [response 200 [files history_v2 .json]]}
            "POST /api/v1/scale/tare" {if {[dict size [body_object $body]]} {fail 422 unknown_field "此操作不接受参数"}; return [invoke scale.tare {}]}
        }
        if {[regexp {^/api/v1/requests/([A-Za-z0-9_-]{8,80})$} $uri -> id]} {
            if {$method ne "GET"} {fail 405 method_not_allowed "执行结果只读"}
            return [response 200 [object [::plugins::decent_remote::receipts::read $id]]]
        }
        if {[regexp {^/api/v1/(machine|grinder)/(wake|sleep|stop|espresso|flush|steam|hotwater|start)$} $uri -> device action]} {
            if {$method ne "POST"} {fail 405 method_not_allowed "此操作仅接受 POST"}
            if {($device eq "machine" && $action eq "start") || ($device eq "grinder" && $action ni {start stop})} {fail 404 not_found "没有此操作"}
            if {[dict size [body_object $body]]} {fail 422 unknown_field "此操作不接受参数"}
            if {$action in {espresso flush steam hotwater start} && !$allow_start} {fail 403 start_disabled "远程启动尚未启用"}
            return [invoke $device.$action {}]
        }
        if {[regexp {^/api/(?:v1/profiles|profile)/([^/]+)$} $uri -> name]} {
            set p [path profiles $name .tcl]
            switch $method {
                GET {return [response 200 [read_file $p] {text/plain; charset=utf-8}]}
                PUT {
                    if {[string trim $body] ni {{} \{\}}} {fail 422 unexpected_body "选择曲线不接受正文"}
                    ::plugins::decent_remote::profiles::validate [read_file $p]
                    return [invoke profile.select [dict create filenameroot [file rootname $name]]]
                }
                default {fail 405 method_not_allowed "曲线接口接受 GET 或 PUT"}
            }
        }
        if {[regexp {^/api/(?:v1/shots|shot)/([^/]+)$} $uri -> name]} {
            if {$method ne "GET"} {fail 405 method_not_allowed "历史只读"}
            return [response 200 [read_file [path history $name .shot]] {text/plain; charset=utf-8}]
        }
        if {[regexp {^/api/(?:v1/shots/json|v2/shot)/([^/]+)$} $uri -> name]} {
            if {$method ne "GET"} {fail 405 method_not_allowed "历史只读"}
            if {[file extension $name] eq {}} {append name .json}
            return [response 200 [read_file [path history_v2 $name .json]]]
        }
        fail 404 not_found "接口不存在；请使用 /api/v1"
    }
    proc dispatch {method uri headers body {query {}}} {
        variable token; variable seen
        set reserved {}; set gate_ticket {}
        # A static sign-in page contains no machine data. API requests below
        # remain authenticated, including every status and history read.
        if {$method eq "GET" && $uri eq "/"} {
            return [::plugins::decent_remote::legacy::route GET / $headers {}]
        }
        if {[catch {
            if {![valid_token $token]} {fail 503 not_configured "接口尚未配置访问密钥"}
            set legacy [expr {![string match /api/v1/* $uri]}]
            set bearer [value $headers authorization]
            set authorized [expr {$bearer eq "Bearer $token"}]
            if {$legacy && $bearer eq {} && [value $query auth] eq $token} {set authorized 1}
            if {!$authorized} {fail [expr {$legacy ? 403 : 401}] unauthorized "访问密钥无效"}
            dict for {k v} $query {
                if {!$legacy || $k ni {auth download}} {fail 400 invalid_query "不支持的查询参数"}
            }
            set origin [value $headers origin]
            set host [value $headers host]
            if {$origin ne {} && ($host eq {} || $origin ni [list "http://$host" "https://$host"])} {fail 403 browser_origin "不接受网页跨源请求"}
            if {[string bytelength $body] > 1048576} {fail 413 too_large "请求内容超过1 MiB"}
            if {[string length $uri] > 1024 || [string first ? $uri] >= 0} {fail 400 invalid_path "请求路径无效"}
            if {$method ni {GET POST PUT}} {fail 405 method_not_allowed "不支持该方法"}
            if {$method ne "GET" && (!$legacy || [value $headers x-request-id] ne {})} {
                set id [value $headers x-request-id]
                if {![regexp {^[A-Za-z0-9_-]{8,80}$} $id]} {fail 400 request_id_required "写操作需要唯一 X-Request-ID"}
                # Reserve before invoking. Failed/unknown actions must not replay either.
                if {[dict exists $seen $id]} {fail 409 duplicate_request "该请求已处理或尝试；请先查询状态，不要重放"}
                if {[dict size $seen] >= 10000} {fail 503 request_limit "本次服务请求记录已满，需要维护重启"}
                dict set seen $id 1
                set reserved $id
                ::plugins::decent_remote::receipts::begin $id $method $uri
            }
            set gate_ticket [::plugins::decent_remote::receipts::gate_enter $method $uri $reserved]
            set r [route $method $uri $body $headers]
        } message options]} {
            set code 500; set tag internal_error; set text "内部处理失败，请查询当前状态"
            set ec [value $options -errorcode]
            if {[lindex $ec 0] eq "REMOTE"} {set code [lindex $ec 1]; set tag [lindex $ec 2]; set text $message}
            set r [response $code [::json::write object error [str $tag] message [str $text]]]
        }
        if {$reserved ne {}} {::plugins::decent_remote::receipts::finish $reserved $r}
        ::plugins::decent_remote::receipts::gate_finish $gate_ticket $r
        return $r
    }
}
source [file join [file dirname [info script]] json_body.tcl]
source [file join [file dirname [info script]] receipts.tcl]
