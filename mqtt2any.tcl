#!/bin/sh
# the next line restarts using tclsh \
        exec tclsh "$0" "$@"

set resolvedArgv0 [file dirname [file normalize $argv0/___]];  # Trick to resolve last symlink
set appname [file rootname [file tail $resolvedArgv0]]
set rootdir [file normalize [file dirname $resolvedArgv0]]
foreach module [list toclbox mqtt] {
    foreach search [list lib/$module ../common/$module] {
        set dir [file join $rootdir $search]
        if { [file isdirectory $dir] } {
            ::tcl::tm::path add $dir
        }
    }
}
foreach search [list lib/modules] {
    set dir [file join $rootdir $search]
    if { [file isdirectory $dir] } {
        ::tcl::tm::path add $dir
    }
}

package require Tcl 8.6
package require toclbox
package require smqtt
set prg_args {
    -help       ""                 "Print this help and exit"
    -verbose    "* INFO"           "Verbosity specification for program and modules"
    -port       1883               "Port at MQTT broker to send to"
    -host       localhost          "Hostname of remote MQTT broker"
    -user       ""                 "Username to authenticate with at MQTT broker"
    -password   ""                 "Password to authenticate with at MQTT broker"
    -broker     ""                 "Remote MQTT broker to connect to, e.g. mqtt://localhost/ alt. to individual MQTT-related options"
    -exts       "%prgdir%/exts"    "Path to plugins directory"
    -routes     ""                 "Topic routing"
    -keepalive  60                 "Keep-alive frequency, in secs."
    -name       "%hostname%-%pid%-%prgname%"  "MQTT client name"
    -clean      on                 "MQTT clean connection?"
    -retry      "100:120000"       "Retry connection?"
    -qos        1                  "QoS for subscriptions"
}


# ::help:dump -- Dump help
#
#       Dump help based on the command-line option specification and
#       exit.
#
# Arguments:
#	hdr	Leading text to prepend to help message
#
# Results:
#       None.
#
# Side Effects:
#       Exit program
proc ::help:dump { { hdr "" } } {
    global appname
    
    if { $hdr ne "" } {
        puts $hdr
        puts ""
    }
    puts "NAME:"
    puts "\t$appname - Routes MQTT topics subscriptions"
    puts ""
    puts "USAGE"
    puts "\t${appname}.tcl \[options\]"
    puts ""
    puts "OPTIONS:"
    foreach { arg val dsc } $::prg_args {
        puts "\t[string range ${arg}[string repeat \  13] 0 13]$dsc (default: ${val})"
    }
    exit
}
# Did we ask for help at the command-line, print out all command-line options
# described above and exit.
toclbox pullopt argv opts
if { [toclbox getopt opts -help] } {
    ::help:dump
}

# Extract list of command-line options into array that will contain program
# state.  The description array contains help messages, we get rid of them on
# the way into the main program's status array.
array set MQ2A {
    plugins {}
    mqtt    ""
    retry   -1
}
foreach { arg val dsc } $prg_args {
    set MQ2A($arg) $val
}
for { set eaten "" } {$eaten ne $opts } {} {
    set eaten $opts
    foreach opt [array names MQ2A -*] {
        toclbox pushopt opts $opt MQ2A
    }
}
# Remaining args? Dump help and exit
if { [llength $opts] > 0 } {
    ::help:dump "[lindex $opts 0] is an unknown command-line option!"
}
# Setup program verbosity and arrange to print out how we were started if
# relevant.
toclbox verbosity {*}$MQ2A(-verbose)
set startup "Starting $appname with following options\n"
foreach {k v} [array get MQ2A -*] {
    append startup "\t[string range $k[string repeat \  10] 0 10]: $v\n"
}
toclbox debug DEBUG [string trim $startup]

# Possibly read nodes, routes etc. information from files instead, since these
# might get big or want to be hidden from command-line
toclbox apparmor -allow */bin/echo \
                 -allow */bin/printf \
                 -allow */bin/grep \
                 -allow */bin/sed \
                 -allow */bin/awk \
                 -allow */bin/jq \
                 -allow */bin/cut \
                 -allow */bin/head \
                 -allow */bin/tail \
                 -allow */bin/tr \
                 -allow */bin/sort
toclbox offload MQ2A(-routes) 3 "routes"
toclbox offload MQ2A(-broker) 1 "broker"
toclbox offload MQ2A(-password) -1 "password"


# ::debug -- Slave debug helper
#
#       This procedure is aliased into the slave interpreters. It arranges to
#       push the name of the "package" (in that case the source of the plugin)
#       at the beginning of the arguments. This is usefull to detect which
#       plugin is sending output and to select output from specific plugins in
#       larger projects via the -verbose command-line option.
#
# Arguments:
#	pkg	Name of package (will be name of plugin)
#	msg	Message
#	lvl	Debug level
#
# Results:
#       None.
#
# Side Effects:
#       None.
proc ::debug { pkg msg {lvl "DEBUG"}} {
    toclbox log $lvl $msg $pkg
}


# ::plugin:init -- Initialise plugin facility
#
#       Loops through the specified routes to create and initialise
#       the requested plugins.  Each plugin filename will lead to the
#       creation of a safe interpreter with the same name.  The
#       content of the file will be sourced in the interpreter and the
#       interpreter will be donated the commands "debug".
#
# Arguments:
#       None.
#
# Results:
#       List of created slave interpreters
#
# Side Effects:
#       None.
proc ::plugin:init { } {
    global MQ2A
    
    set slaves [list]
    foreach { subscription route options } $MQ2A(-routes) {
        toclbox log info "Routing topics from queue $subscription through $route"
        lassign [split $route "@"] proc fname
        
        # Use a "!" leading character for the filename as a marker for non-safe
        # interpreters.
        if { [string index $fname 0] eq "!" } {
            set strong 1
            set fname [string range $fname 1 end]
        } else {
            set strong 0
        }
        
        foreach dir $MQ2A(-exts) {
            set plugin [file join [toclbox resolve $dir [list appname $::appname]] $fname]
            
            if { [file exists $plugin] && [file type $plugin] eq "file" \
                        && ![dict exists $MQ2A(plugins) $route] } {
                # Arrange to automatically pass further all environment
                # variables that start with the same as the rootname of the
                # plugin implementation.
                set envptn [string toupper [file rootname [file tail $plugin]]]*
                # Create slave interpreter and give it two commands to interact
                # with us: disque to operate on jobs and debug to output some
                # debugging information.
                if { $strong } {
                    set slave [::toclbox::interp::create $plugin \
                                    -environment $envptn \
                                    -alias [list debug ::debug $fname] \
                                    {*}$options]
                } else {
                    set slave [::toclbox::interp::create $plugin \
                                    -safe \
                                    -environment $envptn \
                                    -alias [list debug ::debug $fname] \
                                    {*}$options]
                }
                if { $slave ne "" } {
                    $slave alias debug ::debug $fname

                    dict set MQ2A(plugins) $route $slave
                    lappend slaves $slave
                }
                break;         # First match wins!
            }
        }
    }

    return $slaves
    
}


proc Receiver { subscription topic body } {
    global MQ2A

    foreach { s route options } $MQ2A(-routes) {
        if { $s eq $subscription } {
            if { [dict exists $MQ2A(plugins) $route] } {
                set slave [dict get $MQ2A(plugins) $route]
                if { [interp exists $slave] } {
                    lassign [split $route "@"] proc fname
                    # Isolate procedure name from possible arguments.
                    set call [split $proc !]
                    set proc [lindex $call 0]
                    set args [lrange $call 1 end]
                    # Pass entire topic and body to the plugin procedure.
                    if { [catch {$slave eval [linsert $args 0 $proc $topic $body]} res] } {
                        toclbox log warn "Error when calling back $proc: $res"
                    } else {
                        toclbox log debug "Successfully called $proc for topic $topic: $res"
                    }
                } else {
                    toclbox log warn "Cannot find slave interp for $route anymore!"
                }
            } else {
                toclbox log warn "Cannot find plugin at $fname for $route"
            }
        }
    }
}


proc ::Subscribe { mqtt } {
    global MQ2A

    # Connect to all subscriptions specified as part of the
    # command-line options.
    foreach { subscription route options } $MQ2A(-routes) {
        $mqtt subscribe $subscription [list ::Receiver $subscription] $MQ2A(-qos)
    }
}

::toclbox::common::defaults ::smqtt \
                    -keepalive  $MQ2A(-keepalive) \
                    -name       $MQ2A(-name) \
                    -clean      $MQ2A(-clean) \
                    -retry      $MQ2A(-retry)

# Construct broker URL out of separate MQTT arguments if necessary and open
# persistent connection to broker.
if { $MQ2A(-broker) eq "" } {
    set MQ2A(-broker) "mqtt://$MQ2A(-user):$MQ2A(-password)@$MQ2A(-host):$MQ2A(-port)/"
}
set MQ2A(mqtt) [smqtt new $MQ2A(-broker) -connected ::Subscribe]
if { $MQ2A(mqtt) eq "" } {
    exit 1
}

# Read list of recognised plugins out from the routes.  Plugins are only to be
# found in the directory specified as part of the -exts option.  Each file will
# be sourced into a safe interpreter and will be given the command called
# "debug"
if { [llength [plugin:init]] } {
    vwait forever
} else {
    toclbox debug WARN "No successfull routing established, aborting"
}
