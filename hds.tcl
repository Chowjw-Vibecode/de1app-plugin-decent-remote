# Optional HDS soft sleep. Loading this file performs no device action.
namespace eval ::plugins::decent_remote::hds {
    variable enabled
    variable installed
    variable wrappers
    if {![info exists enabled]} {set enabled 1}
    if {![info exists installed]} {set installed 0}
    if {![info exists wrappers]} {set wrappers {}}
    proc eligible {} {
        variable enabled
        if {![string is boolean -strict $enabled] || !$enabled} {return 0}
        foreach v {::settings(scale_type) ::settings(keep_scale_on) ::de1(scale_device_handle) ::de1(suuid_decentscale) ::de1(cuuid_decentscale_write)} {
            if {![info exists $v]} {return 0}
        }
        if {$::settings(scale_type) ne "decentscale" || $::de1(scale_device_handle) in {{} 0}} {return 0}
        if {![string is boolean -strict $::settings(keep_scale_on)]} {return 0}
        foreach v [list ::sinstance($::de1(suuid_decentscale)) ::cinstance($::de1(cuuid_decentscale_write))] {
            if {![info exists $v] || [set $v] eq {}} {return 0}
        }
        foreach cmd {::decent_scale_make_command ::userdata_append} {if {![llength [info commands $cmd]]} {return 0}}
        return 1
    }
    proc send_sleep {sleeping} {
        if {![eligible]} {return 0}
        if {$sleeping && !$::settings(keep_scale_on)} {return 0}
        set cmd [::decent_scale_make_command 0A 04 [format %02X $sleeping]]
        ::userdata_append "SCALE: decent_remote HDS soft sleep $sleeping" [list ble write \
            $::de1(scale_device_handle) $::de1(suuid_decentscale) \
            $::sinstance($::de1(suuid_decentscale)) $::de1(cuuid_decentscale_write) \
            $::cinstance($::de1(cuuid_decentscale_write)) $cmd] 0
        return 1
    }
    proc status {} {
        variable installed; variable enabled
        return [dict create enabled $enabled installed $installed eligible [eligible]]
    }
    proc signature {command} {
        if {![llength [info procs $command]]} {return {}}
        set defaults {}
        foreach arg [info args $command] {
            if {[info default $command $arg value]} {dict set defaults $arg $value}
        }
        return [list [info args $command] $defaults [info body $command]]
    }
    proc uninstall {} {
        variable installed; variable wrappers
        if {!$installed} {return [status]}
        # Validate both ownership records before touching either command. Another
        # plugin's wrapper may retain ours in its chain; never remove it blindly.
        foreach {command original} {
            ::decentscale_enable_lcd original_enable_lcd
            ::decentscale_disable_lcd original_disable_lcd
        } {
            if {![dict exists $wrappers $command] || [signature $command] ne [dict get $wrappers $command] ||
                ![llength [info procs [namespace current]::$original]]} {
                return -code error -errorcode {REMOTE 409 hds_wrapper_changed} "秤方法已被其他代码替换，未自动移除 HDS 包装"
            }
        }
        foreach {command original} {
            ::decentscale_enable_lcd original_enable_lcd
            ::decentscale_disable_lcd original_disable_lcd
        } {
            rename $command {}
            rename [namespace current]::$original $command
        }
        set wrappers {}
        set installed 0
        return [status]
    }
    proc install {} {
        variable installed; variable wrappers
        if {[llength [info commands ::plugins::hds_soft_sleep::original_enable_lcd]] ||
            ([info exists ::settings(enabled_plugins)] && "hds_soft_sleep" in $::settings(enabled_plugins))} {
            return -code error -errorcode {REMOTE 409 hds_conflict} "旧 HDS 插件仍启用，请只保留一个 HDS 实现"
        }
        if {$installed} {return [status]}
        foreach command {decentscale_enable_lcd decentscale_disable_lcd} {
            if {![llength [info procs ::$command]]} {
                return -code error -errorcode {REMOTE 501 unsupported} "缺少原生秤方法：$command"
            }
        }
        rename ::decentscale_enable_lcd [namespace current]::original_enable_lcd
        rename ::decentscale_disable_lcd [namespace current]::original_disable_lcd
        proc ::decentscale_enable_lcd {} {
            ::plugins::decent_remote::hds::send_sleep 0
            ::plugins::decent_remote::hds::original_enable_lcd
        }
        proc ::decentscale_disable_lcd {{potentiallypoweroff 1}} {
            if {![::plugins::decent_remote::hds::send_sleep 1]} {
                ::plugins::decent_remote::hds::original_disable_lcd $potentiallypoweroff
            }
        }
        foreach command {::decentscale_enable_lcd ::decentscale_disable_lcd} {
            dict set wrappers $command [signature $command]
        }
        set installed 1
        return [status]
    }
}
