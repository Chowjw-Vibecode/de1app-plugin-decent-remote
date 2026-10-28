# Local plugin settings only. Sourcing this file does not build UI, write files,
# change authentication, or contact hardware.
namespace eval ::plugins::decent_remote::access {
    variable built 0
    variable entry_widget {}
    variable draft {}
    variable visible 0
    variable view
    array set view {status {} visibility {} title {} hint {} save {} cancel {}}

    proc tr {zh en} {
        set lang en
        if {[llength [info commands ::language]]} {
            set lang [::language]
        } elseif {[info exists ::settings(language)]} {
            set lang $::settings(language)
        }
        if {[string match -nocase zh* $lang]} {return $zh}
        return $en
    }

    proc config_path {} {
        return [file join [homedir] [plugin_directory] decent_remote settings.tdb]
    }

    proc write_config {values} {
        # Preserve unrelated settings, including keys added by newer versions.
        # Never evaluate configuration contents or include a key in diagnostics.
        set path [config_path]
        set stored {}
        if {[file exists $path]} {
            set stored [::plugins::decent_remote::api::read_file $path]
            if {[catch {dict size $stored}]} {error "Invalid plugin configuration"}
        }
        set values [dict merge $stored $values]
        file mkdir [file dirname $path]
        set temporary [file join [file dirname $path] ".[file tail $path].[pid].[clock clicks].tmp"]
        set channel {}
        if {[catch {
            set channel [::open $temporary {WRONLY CREAT EXCL} 0600]
            fconfigure $channel -encoding utf-8 -translation lf
            puts $channel [list {*}$values]
            flush $channel
            close $channel
            set channel {}
            file rename -force $temporary $path
        } message options]} {
            if {$channel ne {}} {catch {close $channel}}
            catch {file delete $temporary}
            # Native log/error dialogs must not accidentally expose a key.
            return -code error "Could not save plugin configuration"
        }
    }

    proc mask {} {
        variable visible; variable entry_widget; variable view
        set visible 0
        set view(visibility) [tr 显示 Show]
        if {$entry_widget ne {} && [llength [info commands $entry_widget]]} {$entry_widget configure -show *}
    }

    proc open {} {
        variable draft; variable view
        set draft $::plugins::decent_remote::settings(token)
        set view(title) [tr 访问密钥 {Access key}]
        set view(hint) [tr {8–128 位英文、数字或符号，不含空格。} {8–128 ASCII letters, numbers or symbols. No spaces.}]
        set view(save) [tr 保存 Save]
        set view(cancel) [tr {取消 / 返回} {Cancel / Back}]
        set view(status) [tr {保存后立即生效，网页需用新密钥重新连接。} {Changes apply immediately. Reconnect the web page with the new key.}]
        if {$draft eq "admin1234"} {set view(status) [tr {当前使用默认密钥，建议修改。} {Using the default key. We recommend changing it.}]}
        mask
    }

    proc toggle_visibility {} {
        variable visible; variable entry_widget; variable view
        set visible [expr {!$visible}]
        set view(visibility) [expr {$visible ? [tr 隐藏 Hide] : [tr 显示 Show]}]
        if {$entry_widget ne {} && [llength [info commands $entry_widget]]} {$entry_widget configure -show [expr {$visible ? {} : "*"}]}
    }

    # DUI hide callbacks pass the old and new pages; Cancel also calls this directly.
    proc discard {{page_to_hide {}} {page_to_show {}}} {
        variable draft; variable view
        set draft {}
        set view(status) {}
        mask
        if {[llength [info commands ::dui]]} {dui platform hide_android_keyboard}
    }

    proc cancel {} {
        discard
        # Plugin settings are opened via page_to_show_when_off. Use the same
        # native path on exit so later Idle events return to the plugin list.
        page_to_show_when_off extensions
    }

    proc save {} {
        variable draft; variable view
        if {![::plugins::decent_remote::api::valid_token $draft]} {
            set view(status) [tr {密钥须为 8–128 位英文、数字或符号，不能含空格。} {Use 8–128 ASCII letters, numbers or symbols, without spaces.}]
            return 0
        }
        set candidate [dict replace [array get ::plugins::decent_remote::settings] token $draft]
        if {[catch {write_config $candidate}]} {
            set view(status) [tr {保存失败，原密钥仍然有效。} {Save failed. The previous key is still active.}]
            return 0
        }
        # Switch authentication only after the complete new file is committed.
        # No App restart, listener changes, or machine actions are involved.
        set ::plugins::decent_remote::settings(token) $draft
        set ::plugins::decent_remote::api::token $draft
        # Successful Save has the same native return route as Cancel. Clear the
        # draft only after committing it, including when the key is unchanged.
        cancel
        return 1
    }

    proc build {} {
        variable built; variable entry_widget
        if {$built || ![llength [info commands ::dui]] || ![llength [info commands ::plugins]]} {return}
        set p DecentRemoteSettings
        dui page add $p -namespace false -bg_color #eef1f4
        dui add dtext $p .07 .12 -text {Decent Remote} -font [dui font get notosansuibold 28] -fill #202a35 -anchor w
        dui add variable $p .07 .23 -textvariable {$::plugins::decent_remote::access::view(title)} -font [dui font get notosansuibold 20] -fill #202a35 -anchor w
        set entry_widget [dui add entry $p .07 .29 -tags access_key -textvariable ::plugins::decent_remote::access::draft -show * -trim 0 -editor_page 0 -canvas_width .66 -canvas_height .10 -font [dui font get notosansuiregular 24] -bg white -fg #202a35 -relief flat -highlightthickness 1 -highlightbackground #c5d0dc]
        dui add dbutton $p .76 .29 -tags visibility -anchor nw -bwidth .17 -bheight .10 -shape round_outline -radius 28 -fill white -outline #c5d0dc -labelvariable {$::plugins::decent_remote::access::view(visibility)} -label_fill #244f75 -label_font [dui font get notosansuibold 19] -command [namespace code toggle_visibility]
        dui add variable $p .07 .44 -textvariable {$::plugins::decent_remote::access::view(hint)} -font [dui font get notosansuiregular 17] -fill #596778 -anchor w -width .86
        dui add variable $p .07 .59 -textvariable {$::plugins::decent_remote::access::view(status)} -font [dui font get notosansuiregular 18] -fill #244f75 -anchor w -width .86
        dui add dbutton $p .07 .78 -tags cancel -anchor nw -bwidth .32 -bheight .11 -shape round_outline -radius 28 -fill white -outline #c5d0dc -labelvariable {$::plugins::decent_remote::access::view(cancel)} -label_fill #202a35 -label_font [dui font get notosansuibold 20] -command [namespace code cancel]
        dui add dbutton $p .61 .78 -tags save -anchor nw -bwidth .32 -bheight .11 -shape round_outline -radius 28 -fill #244f75 -outline #244f75 -labelvariable {$::plugins::decent_remote::access::view(save)} -label_fill white -label_font [dui font get notosansuibold 20] -command [namespace code save]
        dui page add_action $p show [namespace code open]
        dui page add_action $p hide [namespace code discard]
        plugins gui decent_remote $p
        set built 1
    }
}
