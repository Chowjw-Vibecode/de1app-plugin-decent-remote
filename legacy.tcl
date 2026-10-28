# Backwards-compatible REST routes. Keep native calls in the adapter.
namespace eval ::plugins::decent_remote::legacy {
    proc scalar {v} {
        if {[regexp {^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$} $v]} {return $v}
        return [::json::write string $v]
    }
    proc encode {d} {
        set fields {}
        dict for {k v} $d {
            if {$k in {espresso_elapsed espresso_pressure espresso_weight espresso_flow espresso_flow_weight espresso_temperature_basket espresso_temperature_mix}} {
                set values {}; foreach n $v {lappend values [scalar $n]}
                set j [::json::write array {*}$values]
            } else {set j [scalar $v]}
            lappend fields $k $j
        }
        return [::json::write object {*}$fields]
    }
    proc call {op {payload {}}} {return [{*}$::plugins::decent_remote::api::adapter $op $payload]}
    proc reply {body {type application/json}} {::plugins::decent_remote::api::response 200 $body $type}
    proc route {method uri headers body} {
        set p [string trimright $uri /]
        switch -- "$method $p" {
            "GET " {return [reply [::plugins::decent_remote::api::read_file [file join $::plugins::decent_remote::directory index.html]] {text/html; charset=utf-8}]}
            "GET /api/help" {return [reply [::plugins::decent_remote::api::read_file [file join $::plugins::decent_remote::directory doc.json]]]}
            "GET /api/status" {return [reply [encode [call legacy.status]]]}
            "GET /api/status/details" {return [reply [encode [call legacy.details]]]}
            "POST /api/status" {return [reply [encode [call legacy.power [::plugins::decent_remote::api::body_object $body]]]]}
            "GET /api/flush" {call legacy.flush; return [reply {}]}
            "GET /api/profile" {return [reply [::plugins::decent_remote::api::files profiles .tcl]]}
            "POST /api/profile" {
                set name [::plugins::decent_remote::api::value $headers filename [clock seconds].tcl]
                set name [::plugins::decent_remote::profiles::upload $name $body]
                # Preserve legacy text success response consumed via r.text().
                return [reply "$name written" {text/plain; charset=utf-8}]
            }
            "GET /api/shot" {return [reply [::plugins::decent_remote::api::files history .shot]]}
            "GET /api/v2/shots" {
                set records {}; foreach d [call legacy.sdb] {lappend records [encode $d]}
                return [reply [::json::write array {*}$records]]
            }
        }
        if {[regexp {^/api/profile/([^/]+)$} $p -> name]} {
            set file [::plugins::decent_remote::api::path profiles $name .tcl]
            switch $method {
                GET {return [reply [::plugins::decent_remote::api::read_file $file] {text/plain; charset=utf-8}]}
                PUT {
                    ::plugins::decent_remote::profiles::validate [::plugins::decent_remote::api::read_file $file]
                    call profile.select [dict create filenameroot [file rootname $name]]
                    return [reply $name {text/plain; charset=utf-8}]
                }
                default {::plugins::decent_remote::api::fail 405 method_not_allowed "曲线文件支持 GET、PUT"}
            }
        }
        if {[regexp {^/api/shot/([^/]+)$} $p -> name]} {
            if {$method ne "GET"} {::plugins::decent_remote::api::fail 405 method_not_allowed "历史文件只读"}
            return [reply [::plugins::decent_remote::api::read_file [::plugins::decent_remote::api::path history $name .shot]] {text/plain; charset=utf-8}]
        }
        if {[regexp {^/api/v2/shot/([^/]+)$} $p -> name]} {
            if {$method eq "PUT"} {
                set timestamp [file rootname $name]
                if {[file extension $name] ni {{} .json .shot}} {::plugins::decent_remote::api::fail 422 invalid_filename "历史文件名无效"}
                call legacy.dye.next [dict create timestamp $timestamp]
                return [reply {}]
            }
            if {$method ne "GET"} {::plugins::decent_remote::api::fail 405 method_not_allowed "历史接口支持 GET、PUT"}
            if {[file extension $name] eq {}} {append name .json}
            return [reply [::plugins::decent_remote::api::read_file [::plugins::decent_remote::api::path history_v2 $name .json]]]
        }
        ::plugins::decent_remote::api::fail 404 not_found "接口或文件不存在"
    }
}
