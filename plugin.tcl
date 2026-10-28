# Metadata/source is inert. de1app calls main only when enabled.
namespace eval ::plugins::decent_remote {
    variable author "JW / Codex"
    variable version 0.3.5
    variable name "Decent Remote"
    variable description "Local browser control for classic de1app"
    variable directory [file dirname [info script]]
    foreach {key default} {started 0 loaded 0 listener {} registered 0} {
        if {![info exists $key]} {set $key $default}
    }
    variable settings
    proc load_components {} {
        variable loaded; variable directory
        if {$loaded} {return}
        foreach file {core.tcl access.tcl profiles.tcl legacy.tcl adapter.tcl controls.tcl editor.tcl hds.tcl usage.tcl transport.tcl} {source [file join $directory $file]}
        set loaded 1
    }
    proc configure {} {
        variable settings
        # Standard plugin loader loads our settings before main. On first use only,
        # Inherit an existing key/port as data, without executing a file. The
        # requested default only applies when neither installation has a key.
        set persist 0
        if {![info exists settings(token)] || $settings(token) eq {}} {
            set old [file join [homedir] [plugin_directory] advanced_rest_api settings.tdb]
            if {[file isfile $old]} {
                set d [::plugins::decent_remote::api::read_file $old]
                if {![catch {dict size $d}] && [dict exists $d webserver_authentication_key] && [dict exists $d webserver_authentication] && [dict get $d webserver_authentication] == 1} {
                    set settings(token) [dict get $d webserver_authentication_key]
                    if {![info exists settings(port)] && [dict exists $d webserver_port]} {set settings(port) [dict get $d webserver_port]}
                    set persist 1
                }
            }
        }
        if {![info exists settings(token)] || $settings(token) eq {}} {set settings(token) admin1234; set persist 1}
        foreach {key default} {port 8888 hds_enabled 0 usage_enabled 1 usage_endpoint https://decent-remote-usage.decent-remote-stats.workers.dev/v1/check-in} {if {![info exists settings($key)]} {set settings($key) $default}}
        if {![string is integer -strict $settings(port)] || $settings(port) < 1024 || $settings(port) > 65535} {error "无效服务端口"}
        if {![::plugins::decent_remote::api::valid_token $settings(token)]} {error "访问密钥须为8–128位英文、数字或符号，不含空白"}
        foreach key {hds_enabled} {if {![string is boolean -strict $settings($key)]} {error "无效开关：$key"}}
        if {[info exists settings(allow_start)]} {unset settings(allow_start); set persist 1}
        if {$persist} {::plugins::decent_remote::access::write_config [array get settings]}
        set ::plugins::decent_remote::api::root [homedir]
        set ::plugins::decent_remote::api::token $settings(token)
        set ::plugins::decent_remote::hds::enabled $settings(hds_enabled)
    }
    proc unregister {} {
        variable registered
        if {!$registered} {return}
        set keep {}
        foreach {prefix cmd options} $::wibble::zonehandlers {
            if {$cmd ne "::plugins::decent_remote::http::handle"} {lappend keep $prefix $cmd $options}
        }
        set ::wibble::zonehandlers $keep
        set registered 0
    }
    proc main {} {
        variable started; variable settings; variable listener; variable registered
        if {$started} {return}
        foreach old {advanced_rest_api web_api hds_soft_sleep} {
            if {([info exists ::settings(enabled_plugins)] && $old in $::settings(enabled_plugins)) ||
                ($old in {advanced_rest_api web_api} && [llength [info commands ::wibble::check_auth]])} {error "请停用旧 REST 与 HDS 插件并重启 App，避免叠加加载"}
        }
        package require wibble
        load_components
        configure
        ::plugins::decent_remote::access::build
        set hds_before $::plugins::decent_remote::hds::installed
        if {[catch {
            # Bind first: occupied port must not leave HDS wrappers installed.
            set listener [::wibble::listen $settings(port) ::plugins::decent_remote::http::socket]
            if {$settings(hds_enabled)} {::plugins::decent_remote::hds::install}
            ::wibble::handle / ::plugins::decent_remote::http::handle
            set registered 1
            ::plugins::decent_remote::receipts::install
        } err opts]} {
            if {$listener ne {}} {catch {close $listener}; set listener {}}
            unregister
            ::plugins::decent_remote::receipts::uninstall
            if {!$hds_before && $::plugins::decent_remote::hds::installed} {::plugins::decent_remote::hds::uninstall}
            return -options $opts $err
        }
        set started 1
        catch {::plugins::decent_remote::usage::start}
    }
    proc stop {} {
        variable listener; variable started
        if {$listener ne {}} {catch {close $listener}; set listener {}}
        unregister
        if {[llength [info commands ::plugins::decent_remote::receipts::uninstall]]} {::plugins::decent_remote::receipts::uninstall}
        if {[llength [info commands ::plugins::decent_remote::hds::uninstall]]} {::plugins::decent_remote::hds::uninstall}
        if {[llength [info commands ::plugins::decent_remote::usage::stop]]} {::plugins::decent_remote::usage::stop}
        set started 0
    }
}
