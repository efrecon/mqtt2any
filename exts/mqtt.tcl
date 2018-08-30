array set options {
    -broker     "mqtt://localhost"
}

# Connection to MQTT
set ::mqtt ""


# Set options from the environment variables (e.g. content of environment
# variable MQTT_BROKER would change the option -broker).
foreach k [array names options -*] {
    set envvar [string toupper [file rootname [file tail [info script]]]]_[string toupper [string trimleft $k -]]
    if { [info exists ::env($envvar)] } {
        debug "Setting option $k to [set ::env($envvar)] (via environment)" NOTICE
        set options($k) [set ::env($envvar)]
    }
    debug "Option $k is $options($k)" INFO
}



proc forward { topic body { dst "" } {qos 1} {retain 0}} {
    if { $::mqtt eq "" } {
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