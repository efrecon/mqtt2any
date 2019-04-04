array set options {
    -host       "localhost"
    -port       1883
    -user       ""
    -password   ""
    -broker     "mqtt://localhost"

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



proc forward { topic body { dst "" } {qos 1} {retain 0}} {
    if { $::mqtt eq "" } {
        # Construct broker URL out of separate MQTT arguments if necessary and open
        # persistent connection to broker.
        if { $::options(-broker) eq "" } {
            set ::options(-broker) "mqtt://$::options(-user):$::options(-password)@$::options(-host):$::options(-port)/"
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

    debug "Forwarding data to $dst" DEBUG
    smqtt send $::mqtt $dst $body $qos $retain
}