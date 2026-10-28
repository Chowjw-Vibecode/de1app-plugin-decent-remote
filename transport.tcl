# wibble 0.4 reads request bodies for POST only and sends content as Latin-1.
# Keep that library untouched; normalize bytes at this boundary and close each
# connection so unsupported/unused request bodies can never become a next request.
namespace eval ::plugins::decent_remote::http {
    # Only this listener uses the guarded connection loop. Keep wibble's parser,
    # serializer and every other plugin's listener unchanged.
    variable bind_address {}
    proc socket {flag callback port} {
        variable bind_address
        if {$flag ne "-server"} {error "invalid listener arguments"}
        set args [list -server [list ::plugins::decent_remote::http::accept $port]]
        if {$bind_address ne {}} {lappend args -myaddr $bind_address}
        return [::socket {*}$args $port]
    }
    proc accept {port socket peerhost peerport} {
        # wibble's asynchronous reader recognizes coroutines in this namespace.
        coroutine ::wibble::$socket \
            ::plugins::decent_remote::http::process $port $socket $peerhost $peerport
    }
    proc process {port socket peerhost peerport} {
        set cleanup {}; set phase parse
        try {
            set coro [info coroutine]
            ::wibble::cleanup close_client_socket [list chan close $socket]
            ::wibble::cleanup unset_feed [list ::wibble::icc destroy $coro]
            ::wibble::icc configure $coro accept readable copydone
            chan configure $socket -blocking 0
            set request [::wibble::getrequest $port $socket $peerhost $peerport]
            set phase route
            set response [::wibble::getresponse $request]
            set phase send
            # One request per connection; never reuse unread request bytes.
            send_close $socket $request $response
            catch {chan flush $socket}
        } on error {message options} {
            # wibble::panic dumps headers and query strings. Do not invoke it:
            # those can contain the access key, even for a malformed request.
            if {$phase ne "send"} {
                set code [expr {$phase eq "parse" ? 400 : 500}]
                set body [expr {$code == 400 ? {"error":"invalid_http_request"} : {"error":"internal_error"}}]
                set body \{$body\}
                catch {
                    send_close $socket {protocol HTTP/1.1 method GET header {connection close}} \
                        [dict create status $code header [dict create content-type [dict create {} application/json] cache-control [dict create no-store {}] referrer-policy no-referrer x-content-type-options nosniff connection close] content $body]
                    chan flush $socket
                }
            }
        } finally {
            foreach script [lreverse [dict values $cleanup]] {catch $script}
        }
    }
    proc ascii {s} {
        set out {}
        foreach ch [split $s {}] {
            scan $ch %c n
            if {$n > 65535} {
                set n [expr {$n-65536}]
                append out [format {\u%04x\u%04x} [expr {55296+($n>>10)}] [expr {56320+($n&1023)}]]
            } elseif {$n > 127} {append out [format {\u%04x} $n]} else {append out $ch}
        }
        return $out
    }
    proc utf8 {bytes} {
        set decoded [encoding convertfrom utf-8 $bytes]
        if {[encoding convertto utf-8 $decoded] ne $bytes} {
            ::plugins::decent_remote::api::fail 400 invalid_encoding "请求不是有效 UTF-8"
        }
        return $decoded
    }
    proc request_uri {req} {
        # Raw URI, not wibble's already-normalized Latin-1 path. This preserves
        # the core's query/path checks and permits UTF-8 percent-encoded names.
        set raw [::plugins::decent_remote::api::value $req uri]
        if {$raw eq {}} {return [dict get $req path]}
        if {[string length $raw] > 4096 || [string first # $raw] >= 0 || [regexp {%(?![0-9A-Fa-f]{2})} $raw]} {
            ::plugins::decent_remote::api::fail 400 invalid_path "请求路径无效"
        }
        set raw [lindex [split $raw ?] 0]
        set bytes {}
        for {set i 0} {$i < [string length $raw]} {incr i} {
            set ch [string index $raw $i]
            if {$ch eq "%"} {
                append bytes [binary format H2 [string range $raw [expr {$i+1}] [expr {$i+2}]]]
                incr i 2
            } else {
                scan $ch %c n
                if {$n > 127} {::plugins::decent_remote::api::fail 400 invalid_path "路径中的非 ASCII 字符须进行 URL 编码"}
                append bytes $ch
            }
        }
        set path [utf8 $bytes]
        if {[regexp {[\x00-\x1f\x7f]} $path] || [string first "\\" $path] >= 0 || [regexp {(^|/)\.\.?(/|$)} $path]} {
            ::plugins::decent_remote::api::fail 400 invalid_path "请求路径无效"
        }
        return $path
    }
    proc query_params {raw} {
        set i [string first ? $raw]
        if {$i < 0} {return {}}
        set result {}
        foreach pair [split [string range $raw [expr {$i+1}] end] &] {
            set at [string first = $pair]
            if {$at < 1} {::plugins::decent_remote::api::fail 400 invalid_query "查询参数无效"}
            set k [string range $pair 0 [expr {$at-1}]]
            set v [string range $pair [expr {$at+1}] end]
            # Use the proven percent/UTF8 path decoder with no path semantics in tokens.
            set v [string range [request_uri [dict create uri /[string map {+ %20} $v]]] 1 end]
            if {[dict exists $result $k]} {::plugins::decent_remote::api::fail 400 invalid_query "重复查询参数"}
            dict set result $k $v
        }
        return $result
    }
    proc send_close {socket request response} {
        # The original defaultsend decides lifetime from the request, not response.
        dict set request header connection close
        chan configure $socket -translation crlf
        ::wibble::defaultsend $socket $request $response
        return 0
    }
    proc handle {state} {
        if {[catch {
            set req [dict get $state request]
            set headers {}
            foreach line [::plugins::decent_remote::api::value $req rawheader] {
                if {[regexp {^([^:]+):\s*(.*)$} $line -> k v]} {
                    set k [string tolower [string trim $k]]
                    if {[dict exists $headers $k]} {dict set headers $k __duplicate__} else {dict set headers $k [string trim $v]}
                }
            }
            set method [dict get $req method]
            if {$method ni {GET POST PUT}} {::plugins::decent_remote::api::fail 405 method_not_allowed "当前 HTTP 服务支持 GET、POST 与无正文 PUT"}
            if {$method ne "POST" && ([::plugins::decent_remote::api::value $headers transfer-encoding] ne {} || [::plugins::decent_remote::api::value $headers content-length 0] ne "0")} {
                ::plugins::decent_remote::api::fail 400 unexpected_body "GET 和 PUT 不接受正文"
            }
            set body [utf8 [::plugins::decent_remote::api::value $req rawpost]]
            set uri [request_uri $req]
            set query [query_params [::plugins::decent_remote::api::value $req uri]]
            # Browser filename headers use URL encoding for non-ASCII filenames.
            if {[dict exists $headers filename] && [string first % [dict get $headers filename]] >= 0} {
                dict set headers filename [string range [request_uri [dict create uri /[dict get $headers filename]]] 1 end]
            }
            set r [::plugins::decent_remote::api::dispatch $method $uri $headers $body $query]
        } message options]} {
            set ec [::plugins::decent_remote::api::value $options -errorcode]
            set status 500; set tag internal_error; set message "HTTP 请求处理失败"
            if {[lindex $ec 0] eq "REMOTE"} {
                set status [lindex $ec 1]; set tag [lindex $ec 2]
                # Avoid stack traces or request/header contents in the response.
                set message [dict get {400 {请求格式、路径或正文无效} 405 {当前 HTTP 服务支持 GET、POST 与无正文 PUT}} $status]
            }
            set r [::plugins::decent_remote::api::response $status [::json::write object error [::json::write string $tag] message [::json::write string $message]]]
        }
        set content [dict get $r body]
        set type [dict get $r type]
        if {$type eq "application/json"} {
            set content [ascii $content]
        } else {
            # Reversible carrier: wibble's Latin-1 conversion emits these UTF-8 bytes.
            set content [encoding convertfrom iso8859-1 [encoding convertto utf-8 $content]]
        }
        ::wibble::sendresponse [dict create status [dict get $r status] sendcommand ::plugins::decent_remote::http::send_close header [dict create content-type [dict create {} $type] cache-control [dict create no-store {}] referrer-policy no-referrer x-content-type-options nosniff connection close] content $content]
    }
}
