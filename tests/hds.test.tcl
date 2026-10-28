package require tcltest
namespace import ::tcltest::*
source [file join [file dirname [info script]] .. hds.tcl]
proc reset {} {
    set ::calls {}
    array unset ::settings
    array set ::settings {scale_type decentscale keep_scale_on 1}
    array set ::de1 {scale_device_handle ble2 suuid_decentscale service cuuid_decentscale_write characteristic}
    array set ::sinstance {service 1}; array set ::cinstance {characteristic 2}
    set ::plugins::decent_remote::hds::enabled 1
}
proc decentscale_enable_lcd {} {lappend ::calls enable}
proc decentscale_disable_lcd {{poweroff 1}} {lappend ::calls [list disable $poweroff]}
proc decent_scale_make_command {args} {return $args}
proc userdata_append {label command priority} {lappend ::calls [list ble [lindex $command end]]}
test hds-1 {install and repeat install do not send anything} -body {reset; ::plugins::decent_remote::hds::install; ::plugins::decent_remote::hds::install; set ::calls} -result {}
test hds-2 {HDS sleep uses soft command without power off} -body {reset; decentscale_disable_lcd; set ::calls} -result {{ble {0A 04 01}}}
test hds-3 {HDS wake exits soft sleep before native enable} -body {reset; decentscale_enable_lcd; set ::calls} -result {{ble {0A 04 00}} enable}
test hds-4 {other scales preserve original behavior} -body {reset; set ::settings(scale_type) acaia; decentscale_disable_lcd 0; set ::calls} -result {{disable 0}}
test hds-5 {unknown keep-scale policy does not send soft sleep} -body {reset; unset ::settings(keep_scale_on); decentscale_disable_lcd; set ::calls} -result {{disable 1}}
test hds-6 {missing characteristic cannot send soft sleep} -body {reset; unset ::cinstance(characteristic); decentscale_disable_lcd; set ::calls} -result {{disable 1}}
test hds-7 {disabled HDS preserves original method} -body {reset; set ::plugins::decent_remote::hds::enabled 0; decentscale_enable_lcd; set ::calls} -result enable
test hds-8 {old enabled plugin causes conflict} -body {reset; set ::settings(enabled_plugins) {hds_soft_sleep decent_remote}; catch {::plugins::decent_remote::hds::install} e o; dict get $o -errorcode} -result {REMOTE 409 hds_conflict}
test hds-9 {keep-scale-off retains native sleep while wake exits soft sleep} -body {reset; set ::settings(keep_scale_on) 0; decentscale_disable_lcd; decentscale_enable_lcd; set ::calls} -result {{disable 1} {ble {0A 04 00}} enable}
test hds-10 {unknown invalid policy blocks soft command} -body {reset; set ::settings(keep_scale_on) maybe; decentscale_enable_lcd; set ::calls} -result enable
test hds-11 {uninstall restores both originals without BLE and can repeat} -body {
    reset; ::plugins::decent_remote::hds::uninstall; ::plugins::decent_remote::hds::uninstall
    set effects $::calls
    decentscale_enable_lcd; decentscale_disable_lcd 0
    list $effects $::calls [dict get [::plugins::decent_remote::hds::status] installed]
} -result {{} {enable {disable 0}} 0}
test hds-12 {reinstall after rollback is safe and loading source keeps ownership} -body {
    reset; ::plugins::decent_remote::hds::install
    source [file join [file dirname [info script]] .. hds.tcl]
    ::plugins::decent_remote::hds::install
    list $::calls [dict get [::plugins::decent_remote::hds::status] installed]
} -result {{} 1}
test hds-13 {changed wrapper blocks all removal, including unchanged partner} -body {
    reset
    rename ::decentscale_disable_lcd ::other_saved_disable
    proc ::decentscale_disable_lcd {{potentiallypoweroff 1}} {lappend ::calls other}
    set enable_before [info body ::decentscale_enable_lcd]
    catch {::plugins::decent_remote::hds::uninstall} err options
    set unchanged [expr {$enable_before eq [info body ::decentscale_enable_lcd]}]
    rename ::decentscale_disable_lcd {}; rename ::other_saved_disable ::decentscale_disable_lcd
    list [dict get $options -errorcode] $unchanged $::calls [dict get [::plugins::decent_remote::hds::status] installed]
} -result {{REMOTE 409 hds_wrapper_changed} 1 {} 1}
test hds-14 {modified signature default is also an ownership conflict} -body {
    reset
    set body [info body ::decentscale_disable_lcd]
    proc ::decentscale_disable_lcd {{potentiallypoweroff 0}} $body
    catch {::plugins::decent_remote::hds::uninstall} err options
    proc ::decentscale_disable_lcd {{potentiallypoweroff 1}} $body
    set code [dict get $options -errorcode]
    ::plugins::decent_remote::hds::uninstall
    list $code $::calls
} -result {{REMOTE 409 hds_wrapper_changed} {}}
cleanupTests
