package require tcltest
namespace import ::tcltest::*
set plugin [file normalize [file join [file dirname [info script]] .. plugin.tcl]]
set access [file join [file dirname $plugin] access.tcl]
set root [makeDirectory access-test]

proc fixture {} {
    catch {interp delete app}
    file delete -force [file join $::root case]
    interp create app
    interp eval app [list set ::root [file join $::root case]]
    interp eval app [list source $::plugin]
    interp eval app {
        proc homedir {} {return $::root}
        proc plugin_directory {} {return plugins}
        ::plugins::decent_remote::load_components
        array set ::plugins::decent_remote::settings {token old-key-123 port 8888 hds_enabled 1 future_setting {keep this value}}
        set ::plugins::decent_remote::api::token old-key-123
        set ::plugins::decent_remote::api::adapter ::fake
        set ::events {}
        proc fake {op p} {lappend ::events $op; return [dict create connected 1]}
        foreach name {start_idle start_sleep start_espresso start_water start_steam start_flush} {
            proc ::$name {args} {error "unexpected hardware call"}
        }
        set ::settings(language) zh-hans
        proc ::page_to_show_when_off {page args} {set ::page $page}
        proc snapshot {} {
            set f [::open [::plugins::decent_remote::access::config_path] r]
            fconfigure $f -encoding utf-8
            set data [read $f]; close $f
            return $data
        }
        proc persist {} {::plugins::decent_remote::access::write_config [array get ::plugins::decent_remote::settings]}
        proc authorize {key} {
            dict get [::plugins::decent_remote::api::dispatch GET /api/v1/status [dict create authorization "Bearer $key"] {}] status
        }
    }
}

proc fake_ui {} {
    interp eval app {
        set ::ui_calls {}; set ::show {}
        proc ::mock_entry {cmd key val} {if {$cmd eq "configure" && $key eq "-show"} {set ::show $val}}
        proc ::dui {args} {
            lappend ::ui_calls $args
            if {[lrange $args 0 1] eq {font get}} {return font}
            if {[lrange $args 0 1] eq {add entry}} {return ::mock_entry}
            return {}
        }
        proc ::plugins {command name page} {
            if {$command ne "gui"} {error "unexpected plugin command"}
            set ::plugins::${name}::ui_entry $page
        }
        proc ::page_show {page} {set ::page $page}
    }
}

# Native gui.tcl uses a separate machine:off destination. A page_show alone
# changes the visible page but not the destination used by later Idle events.
proc native_navigation {} {
    interp eval app {
        array set ::nextpage {machine:off extensions machine:espresso espresso_zoomed machine:sleep saver}
        proc ::page_to_show_when_off {page args} {
            set ::nextpage(machine:off) $page
            page_show $page
        }
        proc ::machine_page {page} {
            if {[info exists ::nextpage(machine:$page)]} {set page $::nextpage(machine:$page)}
            page_show $page
        }
        proc ::open_key_page {} {
            page_to_show_when_off DecentRemoteSettings
            ::plugins::decent_remote::access::open
        }
    }
}

test access-source-inert {No UI, file writes or authentication updates while sourcing} -body {
    fixture
    interp eval app [list source $access]
    interp eval app {list $::plugins::decent_remote::api::token $::plugins::decent_remote::access::built [file exists $::root] $::events}
} -result {old-key-123 0 0 {}}

test default-no-configuration {First startup persists requested default with remote starts off} -body {
    fixture
    interp eval app {
        array unset ::plugins::decent_remote::settings
        ::plugins::decent_remote::configure
        list [dict get [snapshot] token] $::plugins::decent_remote::api::token [info exists ::plugins::decent_remote::api::allow_start]
    }
} -result {admin1234 admin1234 0}

test existing-config-priority {Existing remote key wins over legacy and the default} -body {
    fixture
    interp eval app {
        file mkdir [file join $::root plugins advanced_rest_api]
        set f [::open [file join $::root plugins advanced_rest_api settings.tdb] w]
        puts $f {webserver_authentication 1 webserver_authentication_key legacy-key-123 webserver_port 9999}; close $f
        persist
        ::plugins::decent_remote::configure
        list $::plugins::decent_remote::api::token $::plugins::decent_remote::settings(port) [dict get [snapshot] token]
    }
} -result {old-key-123 8888 old-key-123}

test legacy-disabled-default {A disabled REST key is not inherited} -body {
    fixture
    interp eval app {
        array unset ::plugins::decent_remote::settings
        file mkdir [file join $::root plugins advanced_rest_api]
        set f [::open [file join $::root plugins advanced_rest_api settings.tdb] w]
        puts $f {webserver_authentication 0 webserver_authentication_key legacy-key-123}; close $f
        ::plugins::decent_remote::configure
        dict get [snapshot] token
    }
} -result admin1234

test draft-is-not-active {Typing only changes the local draft} -body {
    fixture
    interp eval app {
        persist
        ::plugins::decent_remote::access::open
        set ::plugins::decent_remote::access::draft new-key-456
        list [authorize old-key-123] [authorize new-key-456] [dict get [snapshot] token]
    }
} -result {200 401 old-key-123}

test cancel-does-not-save {Cancel discards edits and returns to plugin list} -body {
    fixture; fake_ui; native_navigation
    interp eval app {
        persist
        ::plugins::decent_remote::access::open
        set ::plugins::decent_remote::access::draft new-key-456
        ::plugins::decent_remote::access::cancel
        list $::plugins::decent_remote::access::draft $::plugins::decent_remote::api::token [dict get [snapshot] token] $::page
    }
} -result {{} old-key-123 old-key-123 extensions}

test cancel-clears-idle-destination {Idle transitions after Cancel cannot reopen the key page} -body {
    fixture; fake_ui; native_navigation
    interp eval app {
        persist; open_key_page
        set ::plugins::decent_remote::access::draft new-key-456
        ::plugins::decent_remote::access::cancel
        set after_cancel $::page
        machine_page off
        set after_absent $::page
        machine_page off
        list $after_cancel $after_absent $::page $::nextpage(machine:off) \
            $::nextpage(machine:espresso) $::nextpage(machine:sleep) [dict get [snapshot] token]
    }
} -result {extensions extensions extensions extensions espresso_zoomed saver old-key-123}

test save-returns-and-clears-idle-route {Save returns to the list and later Idle cannot reopen it} -body {
    fixture; fake_ui; native_navigation
    interp eval app {
        persist; open_key_page
        set ::plugins::decent_remote::access::draft new-key-456
        ::plugins::decent_remote::access::save
        machine_page off
        set after_save $::page
        ::plugins::decent_remote::access::cancel
        machine_page off
        list $after_save $::page [authorize new-key-456] [authorize old-key-123] \
            [dict get [snapshot] token] $::plugins::decent_remote::access::draft
    }
} -result {extensions extensions 200 401 new-key-456 {}}

test repeated-cancel-idle {Repeated settings visits and native parent exits do not retain a stale key-page route} -body {
    fixture; fake_ui; native_navigation
    interp eval app {
        persist; set before [snapshot]; set destinations {}
        for {set i 0} {$i < 3} {incr i} {
            open_key_page
            set ::plugins::decent_remote::access::draft changed-but-not-saved
            ::plugins::decent_remote::access::cancel
            machine_page off
            lappend destinations $::page
        }
        page_to_show_when_off settings_4
        machine_page off
        list $destinations $::page [expr {[snapshot] eq $before}] $::events
    }
} -result {{extensions extensions extensions} settings_4 1 {}}

test valid-key-boundaries {Visible ASCII including Tcl metacharacters remains data} -body {
    fixture
    interp eval app {
        set special {ab{}[]$;\!}
        list [::plugins::decent_remote::api::valid_token 12345678] [::plugins::decent_remote::api::valid_token [string repeat x 128]] [::plugins::decent_remote::api::valid_token $special]
    }
} -result {1 1 1}

test invalid-keys-no-write {Invalid keys preserve memory and exact disk bytes} -body {
    fixture
    interp eval app {
        persist; set before [snapshot]; set outcomes {}
        foreach key [list {} short [string repeat x 129] {has space} "newline\n" "tabs\t123" "nul\x00key123" "delete\x7f123" 密钥abcdefgh éabcdefgh] {
            set ::plugins::decent_remote::access::draft $key
            lappend outcomes [::plugins::decent_remote::access::save]
            if {$::plugins::decent_remote::api::token ne "old-key-123" || [snapshot] ne $before} {error "invalid key changed active configuration"}
        }
        lsort -unique $outcomes
    }
} -result 0

test saves-immediately {Commit invalidates old authentication without hardware calls} -body {
    fixture
    interp eval app {
        persist
        set ::plugins::decent_remote::access::draft new-key-456
        set saved [::plugins::decent_remote::access::save]
        set no_actions [expr {$::events eq {}}]
        list $saved $no_actions [authorize old-key-123] [authorize new-key-456] [dict get [snapshot] token] [info exists ::plugins::decent_remote::settings(allow_start)]
    }
} -result {1 1 401 200 new-key-456 0}

test reload-persistence {A native-loader-shaped reload keeps the saved key and other settings} -body {
    fixture
    interp eval app {
        persist
        set ::plugins::decent_remote::access::draft new-key-456
        ::plugins::decent_remote::access::save
        set saved [snapshot]
        array unset ::plugins::decent_remote::settings
        array set ::plugins::decent_remote::settings $saved
        set ::plugins::decent_remote::api::token {}
        ::plugins::decent_remote::configure
        list $::plugins::decent_remote::api::token $::plugins::decent_remote::settings(hds_enabled) $::plugins::decent_remote::settings(future_setting)
    }
} -result {new-key-456 1 {keep this value}}

test preserve-disk-extras {Fields unknown to the current runtime are not lost} -body {
    fixture
    interp eval app {
        ::plugins::decent_remote::access::write_config [dict create disk_only {a newer setting}]
        set ::plugins::decent_remote::access::draft new-key-456
        ::plugins::decent_remote::access::save
        list [dict get [snapshot] disk_only] [dict get [snapshot] port] [dict get [snapshot] hds_enabled]
    }
} -result {{a newer setting} 8888 1}

test tcl-metacharacters-are-data {Config serialization does not execute a submitted key} -body {
    fixture
    interp eval app {
        set key {ab{}[]$;\!}
        set ::plugins::decent_remote::access::draft $key
        set ok [::plugins::decent_remote::access::save]
        list $ok [expr {[dict get [snapshot] token] eq $key}] [authorize $key]
    }
} -result {1 1 200}

test save-open-failure {File creation failure leaves active key and previous file unchanged} -body {
    fixture
    interp eval app {
        persist; set before [snapshot]
        rename ::open ::real_open
        proc ::open {path args} {
            if {[string match *.tmp $path]} {error "injected failure"}
            ::real_open $path {*}$args
        }
        set ::plugins::decent_remote::access::draft new-key-456
        list [::plugins::decent_remote::access::save] [expr {[snapshot] eq $before}] $::plugins::decent_remote::api::token
    }
} -result {0 1 old-key-123}

test save-rename-failure {Failed atomic replacement preserves exact file and cleans temporary file} -body {
    fixture
    interp eval app {
        persist; set before [snapshot]
        rename ::file ::real_file
        proc ::file {sub args} {
            if {$sub eq "rename"} {error "injected failure"}
            ::real_file $sub {*}$args
        }
        set ::plugins::decent_remote::access::draft new-key-456
        set ok [::plugins::decent_remote::access::save]
        set leftovers [glob -nocomplain -directory [file dirname [::plugins::decent_remote::access::config_path]] *.tmp .*.tmp]
        list $ok [expr {[snapshot] eq $before}] $::plugins::decent_remote::api::token [llength $leftovers]
    }
} -result {0 1 old-key-123 0}

test malformed-config-not-overwritten {Broken existing settings are not silently replaced} -body {
    fixture
    interp eval app {
        file mkdir [file dirname [::plugins::decent_remote::access::config_path]]
        set f [::open [::plugins::decent_remote::access::config_path] w]; puts -nonewline $f "odd list keys"; close $f
        set ::plugins::decent_remote::access::draft new-key-456
        list [::plugins::decent_remote::access::save] [snapshot] $::plugins::decent_remote::api::token
    }
} -result {0 {odd list keys} old-key-123}

test native-page-entry {Registers settings page once, with masked entry and explicit save/cancel} -body {
    fixture; fake_ui
    interp eval app {
        ::plugins::decent_remote::access::build
        set first $::ui_calls
        ::plugins::decent_remote::access::build
        set entry {}
        foreach row $::ui_calls {if {[lrange $row 0 1] eq {add entry} && "access_key" in $row} {set entry $row}}
        list $::plugins::decent_remote::ui_entry [expr {$::ui_calls eq $first}] [lindex $entry [expr {[lsearch -exact $entry -show] + 1}]] [lindex $entry [expr {[lsearch -exact $entry -trim] + 1}]] [expr {[string first old-key-123 $::ui_calls] == -1}]
    }
} -result {DecentRemoteSettings 1 * 0 1}

test reveal-remask {Visibility is local and reverts on reopening, leaving no draft on exit} -body {
    fixture; fake_ui
    interp eval app {
        ::plugins::decent_remote::access::build
        ::plugins::decent_remote::access::open
        set masked $::show
        ::plugins::decent_remote::access::toggle_visibility
        set revealed $::show
        ::plugins::decent_remote::access::open
        set remasked $::show
        ::plugins::decent_remote::access::discard
        list $masked $revealed $remasked $::plugins::decent_remote::access::draft $::plugins::decent_remote::api::token
    }
} -result {* {} * {} old-key-123}

test native-hide-callback {DUI supplies both page names to the registered hide action} -body {
    fixture; fake_ui
    interp eval app {
        persist
        ::plugins::decent_remote::access::build
        ::plugins::decent_remote::access::open
        set ::plugins::decent_remote::access::draft new-key-456
        ::plugins::decent_remote::access::toggle_visibility
        set hide_action {}
        foreach row $::ui_calls {
            if {[lrange $row 0 3] eq {page add_action DecentRemoteSettings hide}} {
                set hide_action [lindex $row 4]
            }
        }
        if {$hide_action eq {}} {error "No native hide action registered"}
        uplevel #0 [list {*}$hide_action DecentRemoteSettings extensions]
        list $::show $::plugins::decent_remote::access::draft [dict get [snapshot] token] $::plugins::decent_remote::api::token
    }
} -result {* {} old-key-123 old-key-123}

test language-follows-app {The page uses App language each time it opens} -body {
    fixture
    interp eval app {
        ::plugins::decent_remote::access::open
        set zh $::plugins::decent_remote::access::view(save)
        set ::settings(language) en
        ::plugins::decent_remote::access::open
        list $zh $::plugins::decent_remote::access::view(save)
    }
} -result {保存 Save}

test invalid-runtime-token {Authentication preflight applies the same visible-ASCII rule} -body {
    fixture
    interp eval app {set ::plugins::decent_remote::api::token "bad key123"; authorize "bad key123"}
} -result 503

test switches-draft-and-cancel {Switches and port remain drafts until Save} -body {
    fixture
    interp eval app {
        persist; set before [snapshot]
        ::plugins::decent_remote::access::open
        ::plugins::decent_remote::access::toggle_option allow_start
        ::plugins::decent_remote::access::toggle_option hds_enabled
        set ::plugins::decent_remote::access::options(port) 9999
        ::plugins::decent_remote::access::cancel
        list [expr {[snapshot] eq $before}] [info exists ::plugins::decent_remote::api::allow_start] [array size ::plugins::decent_remote::access::options]
    }
} -result {1 0 0}

test settings-save {Port and HDS wait for restart; removed start setting stays absent; usage preserved} -body {
    fixture
    interp eval app {
        set ::plugins::decent_remote::settings(usage_enabled) 1
        set ::plugins::decent_remote::settings(usage_endpoint) https://example.test/usage
        set ::plugins::decent_remote::hds::enabled 1
        set ::plugins::decent_remote::listener sentinel
        ::plugins::decent_remote::access::open
        ::plugins::decent_remote::access::toggle_option allow_start
        ::plugins::decent_remote::access::toggle_option hds_enabled
        set ::plugins::decent_remote::access::options(port) 9999
        set ok [::plugins::decent_remote::access::save]
        set disk [snapshot]
        list $ok [info exists ::plugins::decent_remote::api::allow_start] [dict get $disk port] [dict get $disk hds_enabled] $::plugins::decent_remote::hds::enabled $::plugins::decent_remote::listener [dict get $disk usage_enabled] [dict get $disk usage_endpoint] $::events $::page
    }
} -result {1 0 9999 0 1 sentinel 1 https://example.test/usage {} extensions}

test invalid-options {Invalid controls never partially change authentication or permission} -body {
    fixture
    interp eval app {
        persist; set before [snapshot]; set outcomes {}
        foreach port {0 1023 65536 abc 8888.5 { 8888} 1e4} {
            ::plugins::decent_remote::access::open
            set ::plugins::decent_remote::access::draft new-key-456
            set ::plugins::decent_remote::access::options(port) $port
            set ::plugins::decent_remote::access::options(allow_start) 1
            lappend outcomes [::plugins::decent_remote::access::save]
        }
        ::plugins::decent_remote::access::open
        set ::plugins::decent_remote::access::options(hds_enabled) invalid
        lappend outcomes [::plugins::decent_remote::access::save]
        list [lsort -unique $outcomes] [expr {[snapshot] eq $before}] [info exists ::plugins::decent_remote::api::allow_start] $::plugins::decent_remote::api::token
    }
} -result {0 1 0 old-key-123}

test failed-options-save {Disk error preserves active settings and leaves editable draft} -body {
    fixture
    interp eval app {
        persist
        ::plugins::decent_remote::access::open
        ::plugins::decent_remote::access::toggle_option allow_start
        rename ::plugins::decent_remote::access::write_config ::original_write
        proc ::plugins::decent_remote::access::write_config args {error simulated}
        list [::plugins::decent_remote::access::save] [info exists ::plugins::decent_remote::api::allow_start] [info exists ::plugins::decent_remote::settings(allow_start)] [info exists ::plugins::decent_remote::access::options(allow_start)]
    }
} -result {0 0 0 0}

test no-start-switch {settings page has no remote-start control} -body {
    fixture; fake_ui
    interp eval app {
        ::plugins::decent_remote::access::build
        ::plugins::decent_remote::access::open
        ::plugins::decent_remote::access::toggle_option allow_start
        list [info exists ::plugins::decent_remote::access::options(allow_start)] [string match *allow_start* $::ui_calls]
    }
} -result {0 0}

catch {interp delete app}
removeDirectory access-test
cleanupTests
