# Typed request parsing. Tcllib's json2dict intentionally erases container types;
# keep them until the route's expected shape has been checked.
namespace eval ::plugins::decent_remote::api {
    proc json_node {tokens cursorName {depth 0}} {
        upvar 1 $cursorName i
        if {$depth > 12 || $i >= [llength $tokens]} {fail 400 invalid_json "JSON 层级或结构无效"}
        set t [lindex $tokens $i]; incr i
        if {$t eq "\{" || $t eq "\["} {
            set isobj [expr {$t eq "\{"}]
            set end [expr {$isobj ? "\}" : "\]"}]
            set out {}
            if {[lindex $tokens $i] eq $end} {incr i; return [list [expr {$isobj ? "object" : "array"}] $out]}
            while {1} {
                if {$isobj} {
                    set k [lindex $tokens $i]; incr i
                    if {[string index $k 0] ne "\"" || [lindex $tokens $i] ne ":"} {fail 400 invalid_json "JSON 对象字段无效"}
                    incr i
                    set k [::json::json2dict $k]
                    if {[dict exists $out $k]} {fail 400 duplicate_field "JSON 包含重复字段"}
                }
                set v [json_node $tokens i [expr {$depth + 1}]]
                if {$isobj} {dict set out $k $v} else {lappend out $v}
                set sep [lindex $tokens $i]; incr i
                if {$sep eq $end} {break}
                if {$sep ne "," || [lindex $tokens $i] eq $end} {fail 400 invalid_json "JSON 分隔符无效"}
            }
            return [list [expr {$isobj ? "object" : "array"}] $out]
        }
        if {[string index $t 0] eq "\""} {return [list string [::json::json2dict $t]]}
        if {$t in {true false}} {return [list boolean $t]}
        if {$t eq "null"} {return [list null {}]}
        if {[regexp {^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$} $t]} {return [list number $t]}
        fail 400 invalid_json "JSON 值无效"
    }
    proc json_tree {body} {
        if {[string bytelength $body] > 65536} {fail 413 too_large "请求内容过大"}
        if {![::json::validate $body]} {fail 400 invalid_json "需要合法的 JSON 对象"}
        set tokens [regexp -all -inline -- $::json::tokenRE $body]
        set i 0
        set node [json_node $tokens i]
        if {$i != [llength $tokens] || [lindex $node 0] ne "object"} {fail 400 invalid_json "需要一个完整 JSON 对象"}
        return [lindex $node 1]
    }
    proc json_scalars {nodes} {
        set out {}
        dict for {k node} $nodes {
            lassign $node type value
            if {$type ni {string number boolean}} {fail 422 invalid_type "字段 $k 需要单个非空值"}
            dict set out $k $value
        }
        return $out
    }
    proc body_object {body} {return [json_scalars [json_tree $body]]}
    proc body_structured {body arrays} {
        set out {}
        dict for {k node} [json_tree $body] {
            lassign $node type value
            if {$k in $arrays} {
                if {$type ne "array"} {fail 422 invalid_type "$k 必须是对象数组"}
                set rows {}
                foreach row $value {
                    if {[lindex $row 0] ne "object"} {fail 422 invalid_type "$k 的每项必须是对象"}
                    lappend rows [json_scalars [lindex $row 1]]
                }
                dict set out $k $rows
            } else {
                dict set out $k [dict get [json_scalars [dict create $k $node]] $k]
            }
        }
        return $out
    }
}
