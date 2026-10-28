# One in-flight profile write; no request queue or automatic retry.
# Native timers, BLE queue and confirmation functions remain authoritative.
# A frame ACK does not confirm dose, scale stop, header, actual temperature or output.
namespace eval ::plugins::decent_remote::receipts {
    variable records {}
    variable active {}
    variable pending {}
    variable queued {}
    variable installed 0
    variable flight {}
    variable serial 0
    variable send_stack {}
    variable ack_stack {}
    variable tainted {}
    variable tainted_all 0
    variable timeout_ms 30000
    variable session [format "%x-%x" [clock seconds] [clock clicks]]
    proc now {} {clock milliseconds}
    proc val {d key {default {}}} {
        if {[dict exists $d $key]} {return [dict get $d $key]}
        return $default
    }
    proc frame_request {method path} {
        set path [string trimright $path /]
        if {$method eq "POST" && $path in {
            /api/v1/recipe /api/v1/profile /api/v1/profile/restore
            /api/v1/profile/save /api/v1/profile/save-as /api/v1/flow-compensation
        }} {return 1}
        return [expr {$method eq "PUT" && [regexp {^/api/(v1/profiles|profile|v2/shot)/[^/]+$} $path]}]
    }
    proc begin {id method path} {
        variable records; variable active; variable session
        set active $id
        dict set records $id [dict create request_id $id session_id $session method $method path $path \
            phase processing accepted 0 app_applied 0 device_confirmed 0 confirmation_scope none started_at_ms [now] \
            may_send_frames [frame_request $method $path]]
    }
    proc mark {id phase note} {
        variable records; variable pending
        if {$id ne {} && [dict exists $records $id]} {
            dict set records $id phase $phase
            dict set records $id device_confirmed 0
            dict set records $id confirmation_note $note
        }
        if {$pending eq $id} {set pending {}}
    }
    proc select_pending {id} {
        variable pending
        if {$pending ne {} && $pending ne $id} {mark $pending superseded newer_profile_request}
        set pending $id
    }
    proc signature {} {
        # Include native conversions, split temperatures, volume/count-start,
        # and future native profile fields, not a hand-picked short field list.
        set keys {profile_filename grinder_dose_weight flow_calibration_multiplier enabled_plugins}
        if {[llength [info commands ::profile_vars]]} {
            set keys [concat $keys [::profile_vars]]
        } else {
            foreach key [array names ::settings] {
                if {[regexp {^(profile_|settings_profile_type$|advanced_shot|espresso_|preinfusion_|flow_profile_|final_desired_|maximum_|pressure_end$|insert_preinfusion_pause$|tank_desired_)} $key]} {lappend keys $key}
            }
        }
        set result {}
        foreach key [lsort -unique $keys] {
            if {[info exists ::settings($key)]} {dict set result $key $::settings($key)}
        }
        # Optional sender compensation is not an installation dependency.
        foreach key {enabled map_id target_file target_title} {
            if {[info exists ::flow_lut_send::$key]} {dict set result flow_lut:$key [set ::flow_lut_send::$key]}
        }
        return $result
    }
    proc native_frame_command {command} {
        set name [namespace tail [lindex $command 0]]
        if {$name eq "confirm_de1_send_shot_frames_worked"} {return 1}
        return [expr {$name eq "de1_comm" && [lindex $command 1] eq "write" && [lindex $command 2] in {HeaderWrite FrameWrite}}]
    }
    proc native_busy {} {
        if {[info exists ::save_settings_to_de1_id] && ![catch {after info $::save_settings_to_de1_id}]} {return 1}
        if {[info exists ::de1(cmdstack)]} {
            foreach entry $::de1(cmdstack) {
                if {[native_frame_command [lindex $entry 1]]} {return 1}
            }
        }
        # An in-flight BLE write has already left cmdstack.
        if {[info exists ::de1(wrote)] && $::de1(wrote) == 1 && [info exists ::de1(previouscmd)] &&
            [native_frame_command $::de1(previouscmd)]} {return 1}
        return 0
    }
    proc taint {parts} {
        variable tainted; variable tainted_all
        if {[dict exists $tainted $parts]} {return}
        # Bound memory without forgetting ambiguity: overflow disables positive
        # confirmation for this App session, but never locks future writes.
        if {[dict size $tainted] >= 128} {set tainted_all 1} else {dict set tainted $parts 1}
    }
    proc release_gate {} {
        variable flight; variable pending
        if {$flight ne {} && $pending eq [dict get $flight id]} {set pending {}}
        set flight {}
    }
    proc reap {} {
        variable flight; variable queued; variable records; variable timeout_ms
        set time [now]; set keep {}
        foreach entry $queued {
            set id [dict get $entry id]; set started [dict get $entry at]
            if {$id ne {} && [dict exists $records $id queued_at_ms]} {set started [dict get $records $id queued_at_ms]}
            if {$time - $started > $timeout_ms} {
                taint [dict get $entry parts]
                if {$id ne {} && [dict exists $records $id] && [dict get $records $id phase] ni {rejected outcome_unknown superseded}} {
                    mark $id unconfirmed_timeout no_confirmation_before_timeout
                }
            } else {lappend keep $entry}
        }
        set queued $keep
        if {$flight ne {} && $time - [dict get $flight started] > $timeout_ms} {
            set id [dict get $flight id]
            if {$id ne {} && [dict exists $records $id] && [dict get $records $id phase] ni {rejected outcome_unknown superseded}} {
                mark $id unconfirmed_timeout no_confirmation_before_timeout
            }
            release_gate
        }
    }
    proc gate_enter {method path id} {
        variable flight; variable queued; variable serial
        if {![frame_request $method $path]} {return {}}
        reap
        if {$flight ne {} || [llength $queued] || [native_busy]} {
            ::plugins::decent_remote::api::fail 409 send_in_progress "上一笔曲线发送或原生传输仍在进行；本次未修改参数，请先查询上一笔结果"
        }
        set ticket [incr serial]
        set flight [dict create ticket $ticket id $id started [now] phase applying]
        return $ticket
    }
    proc gate_finish {ticket response} {
        variable flight; variable queued; variable records
        if {$ticket eq {} || $flight eq {} || [dict get $flight ticket] ne $ticket} {return}
        dict set flight signature [signature]
        dict set flight phase waiting
        set has_frames 0
        foreach entry $queued {if {[dict get $entry ticket] eq $ticket} {set has_frames 1}}
        if {!$has_frames && ![native_busy]} {
            # Non-GHC send_de1_settings_soon schedules nothing. A later App send
            # must not be attached to an old request which never actually sent.
            set id [dict get $flight id]
            if {$id ne {} && [dict exists $records $id] && [dict get $response status] < 400 && ![dict exists $records $id expected_frames]} {
                dict set records $id confirmation_note no_native_send_observed
            }
            release_gate
        }
    }
    proc finish {id response} {
        variable records; variable active; variable pending
        if {$active eq $id} {set active {}}
        if {![dict exists $records $id]} {return}
        set status [dict get $response status]
        dict set records $id http_status $status
        dict set records $id finished_at_ms [now]
        if {$status >= 400} {
            mark $id [expr {$status >= 500 ? "outcome_unknown" : "rejected"}] request_not_completed
            dict set records $id accepted 0
            if {![catch {::json::json2dict [dict get $response body]} err] && [dict exists $err error]} {dict set records $id error [dict get $err error]}
            return
        }
        dict set records $id accepted 1
        if {[dict get $records $id phase] eq "processing"} {dict set records $id phase accepted_unconfirmed}
        if {![catch {::json::json2dict [dict get $response body]} result] && ![catch {dict size $result}]} {
            set readback [val $result readback]
            if {$readback eq {}} {
                foreach key {current_profile recipe} {
                    if {[dict exists $result $key readback]} {set readback [dict get $result $key readback]; break}
                }
            }
            if {$readback in {app_cache file files}} {
                dict set records $id app_applied 1
                if {[dict get $records $id phase] eq "accepted_unconfirmed"} {dict set records $id phase app_applied}
            }
        }
        if {[dict get $records $id may_send_frames] && ![dict exists $records $id expected_frames]} {select_pending $id}
        if {$pending eq $id} {dict set records $id signature [signature]}
    }
    proc send_enter {command op} {catch {observe_send $command}; return}
    proc observe_send {command} {
        variable active; variable pending; variable queued; variable records; variable flight; variable send_stack
        reap
        # Native resets one shared ACK buffer even if this send fails before
        # queuing. Mark previous transfers ambiguous at sender entry.
        set marked {}
        foreach entry $queued {dict set entry ambiguous 1; lappend marked $entry}
        set queued $marked
        set id {}; set ticket [val $flight ticket]
        if {[lindex $command 1] ne {}} {
            if {$pending ne {}} {mark $pending superseded native_override_send}
        } elseif {$active ne {} && [dict exists $records $active] && [dict get $records $active may_send_frames]} {
            set id $active; select_pending $id
        } elseif {$pending ne {} && [dict exists $records $pending signature]} {
            if {[dict get $records $pending signature] eq [signature]} {set id $pending} else {mark $pending superseded app_profile_changed_before_send}
        }
        lappend send_stack [dict create id $id ticket $ticket]
    }
    proc send_leave {command code result op} {catch {complete_send $code}; return}
    proc complete_send {code} {
        variable send_stack; variable queued; variable tainted_all
        set context [lindex $send_stack end]
        if {[llength $send_stack]} {set send_stack [lrange $send_stack 0 end-1]}
        if {$code == 0} {return}
        # A sender can fail after some writes but before its confirmation is
        # queued. Those possible late ACKs have no complete payload to compare.
        # Keep writes recoverable; do not certify subsequent ACKs this session.
        set tainted_all 1
        foreach entry $queued {taint [dict get $entry parts]}
        mark [val $context id] outcome_unknown native_sender_error
    }
    proc queue_trace {command op} {catch {observe_queue $command}; return}
    proc observe_queue {command} {
        variable queued; variable records; variable send_stack
        set call [lindex $command 2]
        if {[namespace tail [lindex $call 0]] ne "confirm_de1_send_shot_frames_worked" || [llength $call] != 2} {return}
        set context [lindex $send_stack end]
        set id [val $context id]; set ticket [val $context ticket]
        set overlap [expr {[llength $queued] > 0}]
        if {$overlap} {
            set prior {}; foreach entry $queued {dict set entry ambiguous 1; lappend prior $entry}; set queued $prior
        }
        lappend queued [dict create id $id ticket $ticket parts [lindex $call 1] ambiguous $overlap at [now] sender_seen [expr {$context ne {}}]]
        if {[llength $queued] > 128} {
            set old [lindex $queued 0]; taint [dict get $old parts]
            mark [dict get $old id] frames_unconfirmed observer_capacity_exceeded
            set queued [lrange $queued 1 end]
        }
        if {$id ne {} && [dict exists $records $id]} {
            dict set records $id expected_frames [lindex $call 1]
            dict set records $id queued_at_ms [now]
            dict set records $id phase frames_queued
        }
    }
    proc observer_ready {} {
        variable installed
        if {!$installed || ![llength [info commands ::parse_binary_shotframe]]} {return 0}
        foreach {command op callback} {
            ::de1_send_shot_frames enter ::plugins::decent_remote::receipts::send_enter
            ::userdata_append enter ::plugins::decent_remote::receipts::queue_trace
            ::confirm_de1_send_shot_frames_worked enter ::plugins::decent_remote::receipts::ack_trace
            ::confirm_de1_send_shot_frames_worked leave ::plugins::decent_remote::receipts::ack_leave
        } {
            if {![llength [info commands $command]] || [lsearch -exact [trace info execution $command] [list $op $callback]] < 0} {return 0}
        }
        return 1
    }
    proc ack_trace {command op} {catch {observe_ack $command}; return}
    proc observe_ack {command} {
        variable pending; variable records; variable queued; variable ack_stack; variable tainted; variable tainted_all
        reap
        set parts [lindex $command 1]; set index -1
        for {set i 0} {$i < [llength $queued]} {incr i} {
            if {[dict get [lindex $queued $i] parts] eq $parts} {set index $i; break}
        }
        set entry {}
        if {$index >= 0} {set entry [lindex $queued $index]; set queued [lreplace $queued $index $index]}
        lappend ack_stack [dict create ticket [val $entry ticket] id [val $entry id] parts $parts]
        set id [val $entry id]
        if {$id eq {} || ![dict exists $records $id] || [dict get $records $id phase] in {superseded rejected outcome_unknown unconfirmed_timeout}} {return}
        set uncertain [expr {$tainted_all || [dict exists $tainted $parts]}]
        set ok [expr {[observer_ready] && [dict get $entry sender_seen] && ![dict get $entry ambiguous] && !$uncertain &&
            [llength $parts] > 0 && [info exists ::de1(shot_frames_sent)]}]
        if {$ok && [llength $parts] != [llength $::de1(shot_frames_sent)]} {set ok 0}
        if {$ok} {
            foreach packed $parts got $::de1(shot_frames_sent) {
                unset -nocomplain fields
                if {[catch {::parse_binary_shotframe $packed fields}] || ![array exists fields] ||
                    [array size fields] < 2 || ![info exists fields(FrameToWrite)] || [catch {dict size $got}]} {
                    set ok 0; break
                }
                foreach {key value} [array get fields] {
                    if {![dict exists $got $key] || [dict get $got $key] ne $value} {set ok 0; break}
                }
                if {!$ok} {break}
            }
        }
        dict set records $id phase [expr {$ok ? "frames_confirmed" : "frames_unconfirmed"}]
        dict set records $id device_confirmed $ok
        dict set records $id confirmation_scope profile_frames_only
        if {$ok} {
            dict set records $id confirmed_at_ms [now]
        } else {
            taint $parts
            set note frame_validation_failed
            if {$uncertain} {set note previous_unconfirmed_identical_frames}
            if {$tainted_all} {set note ack_attribution_ambiguous}
            if {[dict get $entry ambiguous]} {set note overlapping_transfers}
            if {![observer_ready]} {set note observer_unavailable}
            dict set records $id confirmation_note $note
        }
        if {$pending eq $id} {set pending {}}
    }
    proc ack_leave {command code result op} {catch {complete_ack $command $code}; return}
    proc complete_ack {command code} {
        # Release after native confirm clears its shared ACK buffer, not before.
        variable ack_stack; variable flight
        if {![llength $ack_stack]} {return}
        set entry [lindex $ack_stack end]; set ack_stack [lrange $ack_stack 0 end-1]
        if {$code != 0} {taint [dict get $entry parts]; mark [dict get $entry id] outcome_unknown native_confirmation_error}
        if {$flight ne {} && [val $entry ticket] eq [dict get $flight ticket]} {release_gate}
    }
    proc read {id} {
        variable records; variable flight
        reap
        if {![dict exists $records $id]} {::plugins::decent_remote::api::fail 404 receipt_not_found "本次服务进程没有此请求；重启不保留记录"}
        set r [dict get $records $id]
        dict set r in_flight [expr {$flight ne {} && [dict get $flight id] eq $id}]
        foreach key {signature expected_frames may_send_frames} {dict unset r $key}
        return $r
    }
    proc install {} {
        variable installed
        if {$installed} {return}
        foreach command {::userdata_append ::de1_send_shot_frames ::confirm_de1_send_shot_frames_worked} {
            if {![llength [info commands $command]]} {return}
        }
        trace add execution ::de1_send_shot_frames enter ::plugins::decent_remote::receipts::send_enter
        trace add execution ::de1_send_shot_frames leave ::plugins::decent_remote::receipts::send_leave
        trace add execution ::userdata_append enter ::plugins::decent_remote::receipts::queue_trace
        trace add execution ::confirm_de1_send_shot_frames_worked enter ::plugins::decent_remote::receipts::ack_trace
        trace add execution ::confirm_de1_send_shot_frames_worked leave ::plugins::decent_remote::receipts::ack_leave
        set installed 1
    }
    proc uninstall {} {
        variable installed; variable queued; variable pending; variable send_stack; variable ack_stack
        foreach {command op callback} {
            ::de1_send_shot_frames enter ::plugins::decent_remote::receipts::send_enter
            ::de1_send_shot_frames leave ::plugins::decent_remote::receipts::send_leave
            ::userdata_append enter ::plugins::decent_remote::receipts::queue_trace
            ::confirm_de1_send_shot_frames_worked enter ::plugins::decent_remote::receipts::ack_trace
            ::confirm_de1_send_shot_frames_worked leave ::plugins::decent_remote::receipts::ack_leave
        } {catch {trace remove execution $command $op $callback}}
        foreach entry $queued {taint [dict get $entry parts]; mark [dict get $entry id] frames_unconfirmed observer_removed}
        set installed 0; set queued {}; set pending {}; set send_stack {}; set ack_stack {}
        release_gate
    }
}
