package require tcltest
namespace import ::tcltest::*
set plugin [file normalize [file join [file dirname [info script]] .. plugin.tcl]]
set root [makeDirectory lifecycle]
proc fixture {} {
    catch {interp delete app}
    interp create app
    interp eval app [list source $::plugin]
    interp eval app [list set ::root $::root]
    interp eval app {
        package provide wibble 0.4
        namespace eval ::wibble {
            variable zonehandlers {}
            proc handle {p cmd args} {lappend ::wibble::zonehandlers $p $cmd $args}
            proc listen {port args} {if {$::fail_bind} {error occupied}; incr ::binds; open /dev/null w}
        }
        proc homedir {} {return $::root}
        proc plugin_directory {} {return plugins}
        proc save_plugin_settings {name} {incr ::saves}
        proc decentscale_enable_lcd {} {lappend ::events enable}
        proc decentscale_disable_lcd {{p 1}} {lappend ::events disable}
        set ::settings(enabled_plugins) {decent_remote}
        array set ::plugins::decent_remote::settings {token 123456789012345678901234 port 8888 allow_start 0 hds_enabled 1 usage_endpoint {}}
        set ::events {}; set ::binds 0; set ::saves 0; set ::fail_bind 0
    }
}
test source-inert {} -body {fixture; interp eval app {list $::events $::binds $::plugins::decent_remote::started}} -result {{} 0 0}
test old-plugin-conflict {} -body {fixture; interp eval app {set ::settings(enabled_plugins) {advanced_rest_api decent_remote}; catch {::plugins::decent_remote::main} msg; list $::binds $::events [string match {*停用*} $msg]}} -result {0 {} 1}
test occupied-no-hds {} -body {fixture; interp eval app {set ::fail_bind 1; catch {::plugins::decent_remote::main}; list $::events $::plugins::decent_remote::hds::installed $::plugins::decent_remote::started $::wibble::zonehandlers}} -result {{} 0 0 {}}
test repeated-main {} -body {fixture; interp eval app {::plugins::decent_remote::main; ::plugins::decent_remote::main; list $::binds $::events $::plugins::decent_remote::hds::installed [llength $::wibble::zonehandlers]}} -result {1 {} 1 3}
test occupied-retry {} -body {fixture; interp eval app {set ::fail_bind 1; catch {::plugins::decent_remote::main}; set ::fail_bind 0; ::plugins::decent_remote::main; list $::binds $::events $::plugins::decent_remote::hds::installed}} -result {1 {} 1}
test stop-no-device {} -body {fixture; interp eval app {::plugins::decent_remote::main; ::plugins::decent_remote::stop; list $::events $::plugins::decent_remote::hds::installed $::wibble::zonehandlers [info body ::decentscale_enable_lcd]}} -result {{} 0 {} {lappend ::events enable}}
test hds-install-failure {} -body {fixture; interp eval app {rename ::decentscale_enable_lcd {}; catch {::plugins::decent_remote::main}; list $::plugins::decent_remote::listener $::plugins::decent_remote::started $::wibble::zonehandlers}} -result {{} 0 {}}
test restart-after-stop {} -body {fixture; interp eval app {::plugins::decent_remote::main; ::plugins::decent_remote::stop; ::plugins::decent_remote::main; list $::binds $::plugins::decent_remote::hds::installed $::events}} -result {2 1 {}}
test register-failure-rollback {} -body {fixture; interp eval app {proc ::wibble::handle {args} {error mock}; catch {::plugins::decent_remote::main}; list $::plugins::decent_remote::listener $::plugins::decent_remote::hds::installed $::events}} -result {{} 0 {}}
test inherit-existing-key-port {} -body {
    fixture
    interp eval app {
        file mkdir [file join $::root plugins advanced_rest_api]
        set f [open [file join $::root plugins advanced_rest_api settings.tdb] w]
        puts $f {webserver_authentication 1 webserver_authentication_key abcdefghijklmnopqrstuvwxyz webserver_port 8899}
        close $f
        unset ::plugins::decent_remote::settings(token) ::plugins::decent_remote::settings(port)
        ::plugins::decent_remote::main
        set f [open [file join $::root plugins decent_remote settings.tdb] r]
        set saved [read $f]; close $f
        list [expr {$::plugins::decent_remote::settings(token) eq "abcdefghijklmnopqrstuvwxyz"}] $::plugins::decent_remote::settings(port) [expr {[dict get $saved token] eq "abcdefghijklmnopqrstuvwxyz"}] $::events
    }
} -result {1 8899 1 {}}
test statistics-default-endpoint {a fresh configuration has the deployed endpoint without starting network work} -body {
    fixture
    interp eval app {
        unset ::plugins::decent_remote::settings(usage_endpoint)
        ::plugins::decent_remote::load_components
        ::plugins::decent_remote::configure
        list $::plugins::decent_remote::settings(usage_enabled) $::plugins::decent_remote::settings(usage_endpoint) $::plugins::decent_remote::started
    }
} -result {1 https://decent-remote-usage.decent-remote-stats.workers.dev/v1/check-in 0}
test statistics-unconfigured-integration {explicitly unconfigured statistics cannot create an identity or schedule network work} -body {
    fixture
    interp eval app {
        ::plugins::decent_remote::main
        list $::plugins::decent_remote::started $::plugins::decent_remote::usage::started \
            $::plugins::decent_remote::usage::timer \
            [file exists [::plugins::decent_remote::usage::state_file]] $::events
    }
} -result {1 1 {} 0 {}}
test statistics-stop-cancels-timer {configured background timer follows plugin lifecycle without machine commands} -body {
    fixture
    interp eval app {
        set ::plugins::decent_remote::settings(usage_endpoint) https://usage.test/v1/check-in
        ::plugins::decent_remote::main
        set timer $::plugins::decent_remote::usage::timer
        set scheduled [expr {$timer ne {} && $timer in [after info]}]
        ::plugins::decent_remote::stop
        list $scheduled [expr {$timer in [after info]}] $::plugins::decent_remote::usage::started $::events
    }
} -result {1 0 0 {}}
test statistics-start-failure-isolated {statistics startup failure cannot disable the local control API} -body {
    fixture
    interp eval app {
        ::plugins::decent_remote::load_components
        proc ::plugins::decent_remote::usage::start {} {error {synthetic statistics failure}}
        ::plugins::decent_remote::main
        list $::plugins::decent_remote::started [expr {$::plugins::decent_remote::listener ne {}}] \
            [llength $::wibble::zonehandlers] $::events
    }
} -result {1 1 3 {}}
catch {interp eval app {::plugins::decent_remote::stop}}
interp delete app
removeDirectory lifecycle
cleanupTests
