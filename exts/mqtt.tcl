array set options {
    -host       "localhost"
    -port       1883
    -user       ""
    -password   ""
    -proto      "mqtt"
    -broker     "mqtt://localhost"
    -limits     {}

    obfuscate      {"-password"}
}

# Connection to MQTT
set ::mqtt ""


# Set options from the environment variables (e.g. content of environment
# variable MQTT_BROKER would change the option -broker).
foreach k [array names options -*] {
    set envvar [string toupper [file rootname [file tail [info script]]]]_[string toupper [string trimleft $k -]]
    if { [info exists ::env($envvar)] } {
        if { $k in $options(obfuscate) } {
            debug "Setting option $k to [string repeat "*" [string length [set ::env($envvar)]]] (via environment)" NOTICE
        } else {
            debug "Setting option $k to [set ::env($envvar)] (via environment)" NOTICE
        }
        set options($k) [set ::env($envvar)]
    }
    if { $k in $options(obfuscate) } {
        debug "Option $k is [string repeat "*" [string length $options($k)]]" INFO
    } else {
        debug "Option $k is $options($k)" INFO
    }
}


# Read limits from file whenever appropriate
if { [string index $::options(-limits) 0] eq "@" } {
    debug "Reading rate limiting from [string range $::options(-limits) 1 end]" NOTICE
    set fd [open [string range $::options(-limits) 1 end]]
    set ::options(-limits) [list]
    while {![eof $fd]} {
        set line [string trim [gets $fd]]
        if { $line ne "" && [string index $line 0] ne "\#" } {
            if { $line eq "-" } {
                lappend ::options(-limits) ""
            } else {
                lappend ::options(-limits) $line
            }
        }
    }
    close $fd
    debug "Read [expr {[llength $::options(-limits)]/4}] rate-limiting specifications" INFO
}


##### Following code from https://wiki.tcl-lang.org/page/Converting+human+time+durations
proc HowLong {len unit} {
    if { [string is integer -strict $len] } {
        switch -glob -- $unit {
            "\[Yy\]*" {
                return [expr {$len*31536000}];   # Leap years?
            }
            "\[Mm\]\[Oo\]*" -
            "m*" {
                return [expr {$len*2592000}]
            }
            "\[Ww\]*" {
                return [expr {$len*604800}]
            }
            "\[Dd\]*" {
                return [expr {$len*86400}]
            }
            "\[Hh\]*" {
                return [expr {$len*3600}]
            }
            "\[Mm\]\[Ii\]*" -
            "M" {
                return [expr {$len*60}]
            }
            "\[Ss\]*" {
                return $len
            }
        }
    }
    return 0
}


proc Duration { str } {
    set words {}
    while {[scan $str %s%n word length] == 2} {
        lappend words $word
        set str [string range $str $length end]
    }

    set seconds 0
    for {set i 0} {$i<[llength $words]} {incr i} {
        set f [lindex $words $i]
        if { [scan $f %d%n n length] == 2 } {
            set unit [string range $f $length end]
            if { $unit eq "" } {
                incr seconds [HowLong $n [lindex $words [incr i]]]
            } else {
                incr seconds [HowLong $n $unit]
            }
        }
    }

    return $seconds
}
##### End of code from https://wiki.tcl-lang.org/page/Converting+human+time+durations

# Does a topic match an MQTT pattern (copied from mqtt library)
proc match {pattern topic} {
	if {[string index $topic 0] eq "$"} {
	    if {[string index $pattern 0] ne "$"} {
            return 0
        }
	}
	foreach p [split $pattern /] n [split $topic /] {
	    if {$p eq "#"} {
		    return 1
	    } elseif {$p ne $n && $p ne "+"} {
		    return 0
	    }
	}
	return 1
}

proc reset { pattern } {
    set varname ::limiter_[regsub -all -nocase {[^\w/#+]} $pattern _]
    upvar \#0 $varname LIMIT
    set LIMIT(messages) 0
    set LIMIT(bytes) 0
    set LIMIT(timer) [after $LIMIT(-period) [list ::reset $pattern]]
}

proc forward { topic body { dst "" } {qos 1} {retain 0}} {
    if { $::mqtt eq "" } {
        # Construct broker URL out of separate MQTT arguments if necessary and open
        # persistent connection to broker.
        if { $::options(-broker) eq "" } {
            set ::options(-broker) "$::options(-proto)://$::options(-user):$::options(-password)@$::options(-host):$::options(-port)/"
            debug "Constructed broker URL: mqtt://$::options(-user):*****@$::options(-host):$::options(-port)/" NOTICE
        }       
        set ::mqtt [smqtt new $::options(-broker)]
    }

    # Nothing to do on empty data
    if { [string trim $body] eq "" } {
        return
    }

    # Same destination topic as reception topic if nothing specified, otherwise
    # split on / and make sure the destination topic can use each parts as %1%,
    # %2%, etc.
    if { $dst eq "" } {
        set dst $topic
    } else {
        set items [split $topic "/"]
        set mapper [list]
        for {set i 0} {$i<[llength $items]} {incr i} {
            lappend mapper %$i% [lindex $items $i]
        }
        lappend mapper %topic% $topic
        set dst [string map $mapper $dst]
    }

    set forward 1
    foreach {pattern period messages bytes} $::options(-limits) {
        if { [match $pattern $dst] } {
            set varname ::limiter_[regsub -all -nocase {[^\w/#+]} $pattern _]
            if { ! [info exists $varname] } {
                # Create a limiter "object"
                upvar \#0 $varname LIMIT
                set LIMIT(-pattern) $pattern
                if { [string is integer -strict $period] } {
                    set LIMIT(-period) $period
                } else {
                    set secs [Duration $period]
                    set LIMIT(-period) [expr {$secs*1000}]
                    debug "Converted period $period to $LIMIT(-period) ms" INFO
                }
                set LIMIT(-messages) $messages
                set LIMIT(-bytes) $bytes
                set LIMIT(messages) 0
                set LIMIT(bytes) 0
                set LIMIT(timer) [after $LIMIT(-period) [list ::reset $pattern]]
                set txt "Created rate limiter for destination topics matching $LIMIT(-pattern)"
                if { $LIMIT(-messages) > 0 } {
                    append txt " max. $LIMIT(-messages) messages / $LIMIT(-period) ms."
                } elseif { $LIMIT(-messages) == 0 } {
                    append txt " all messages discarded."
                }
                if { $LIMIT(-bytes) > 0 } {
                    append txt " max. $LIMIT(-bytes) bytes / $LIMIT(-period) ms."
                } elseif { $LIMIT(-bytes) == 0 } {
                    append txt " all messages discarded."
                }
                debug $txt NOTICE
            }

            # Check against known limits and decide to forward or not.
            upvar \#0 $varname LIMIT
            set len [string length $body]
            if { ( $LIMIT(-messages) < 0 || $LIMIT(messages) + 1 < $LIMIT(-messages) ) \
                && ( $LIMIT(-bytes) < 0 || $LIMIT(bytes) + $len < $LIMIT(-bytes) )} {
                set forward 1
                incr LIMIT(messages)
                incr LIMIT(bytes) $len
            } else {
                set forward 0
                debug "Rejecting data to $dst, would override rate limit for $pattern" NOTICE
            }
            break;   # Stop decisions on first match
        }
    }

    if { $forward } {
        debug "Forwarding data to $dst" DEBUG
        smqtt send $::mqtt $dst $body $qos $retain
    }
}