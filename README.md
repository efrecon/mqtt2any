# mqtt2any

This program implements a generic [MQTT] subscription handler. It accepts a
number of routes that will pass data acquired from topics corresponding to
specific subscriptionsto sandboxed [Tcl](https://www.tcl.tk/)
[interpreters](https://www.tcl.tk/man/tcl8.6/TclCmd/safe.htm) for treatment. The
sandboxing is able to restrict which part of the disk hierarchy is accessible to
the interpreters, and which hosts these interpreters are allowed to communicate
with. This manual describes command-line options and the interaction between the
topic subscriptions and procedures.

## Command-Line Options

The program only accepts single-dash led full options on the command-line.
The complete list of recognised options can be found below:

- `-broker` is a URL-like specification pointing at the broker server. The
  specification should be of the form
  `mqtt://<username>:<password>@<hostname>:<port>` where the authorisation
  information and port number can be omitted. The default is to attempt
  connection to `localhost`. A leading scheme of `mqtts://` will turn on TLS
  encryption when talking to the broker. The scheme can be entirely omitted, in
  which case a warning will be printed out and the default of `mqtt://` used.
  
- `-exts` is a whitespace separated list of directory specifications where to
  look for plugins.
  
- `-routes` is a list of triplets describing the routes for data transformation
  depending on incoming paths. The first item is a topic subsription, the second
  item a specification for how to transform data (see below) and the third item
  is a list of dash-led options and their values (see below).
  
- `-keepalive` is the MQTT keep-alive period, expressed in seconds. It defaults
  to a minute.

- `-clean` should be a boolean (`on` or `off` for example) and asks to establish
  a clean MQTT connection to the broker (or not). It defaults to yes.

- `-name` is the client name sent to the MQTT broker. In that string,
  `%`-surrounded strings will be replaced by the values of those tokens, e.g.
  `hostname`, `pid`, `prgname`. It defaults to a good unique default.

## Routing

Through its `-routes` command-line option, you will be able to bind procedures
to a specific subscription. The topic at which data was received and the data
itself are always passed as arguments to the procedures and these will be able
to operate as they which on the data acquired from the broker. You will also be
able to pass arguments to those procedures in order to refine what they should
perform for example. Data treatment occuring in plugins will be executed within
safe Tcl interpreters, which guarantees maximum flexibility when it comes to
transformation capabilities while guaranteeing security through encapsulation of
all IO and system commands.

All `tcl` files implementing the plugins should be placed in the directories
that is pointed at by the `-exts` option. Binding between subscriptions and
procedures occurs through the `-routes` option. For example, starting the
program with `-routes "# print@printer.tcl \"\""` will arrange for all data
posted to all topics to be routed towards the procedure `print` that can be
found in the file `printer.tcl`. Whenever data is available, the procedure will
be called with the following arguments.

1. The complete topic where data was acquired.

2. The content of the data.

The procedure `print` is then free to perform any kind of operations it deems
necessary on the data. An example `print` procedure is availabe under the `exts`
subdirectory in the `printer.tcl` file. The procedure will print the content of
each data block.

### Additional Arguments

To pass arguments to the procedure, you can separate them with `!`-signs after
the name of the procedure.  These arguments will be blindly passed after the
requested URL and the data to the procedure when it is executed. So, for
example, if your route contained a plugin specification similar to
`myproc!onearg!3@myplugin.tcl`, procedure `myproc` in `myplugin.tcl` would be
called with 4 arguments everytime data is available, i.e. the topic, the data
itself and `onearg` and `3` as arguments.  Spaces are allowed in arguments, as
long as you specify quotes (or curly-braces) around the procedure call
construct.

### Escaping Safe Interpreters

Every route will be executed in a safe interpreter, meaning that it will have a
number of heavy restriction as to how the interpreter is able to interoperate
with its environment and external resources. When specifying routes, the last
item of each routing specification triplet is a list of dash-led options
followed by values, options that can be used to tame the behaviour of the
interpreter and selectively let it access external resources of various sorts.
These options can appear as many times as necessary and are understood as
follows:

- `-access` will allow the interpreter to access a given file or directory on
  disk. The interpreter will be able to both read and write to that location.

- `-allow` takes a host pattern and a port as a value, separated by a colon.
  This allows the interpreter to access hosts matching that pattern with the
  [socket] command.

- `-deny` takes the same form as `-allow`, but will deny access to the host
  (pattern) and port. Allowance and denial rules are taken in order, so `-deny`
  can be used to selectively deny to some of the hosts that would otherwise have
  had been permitted using `-allow`.

- `-package` takes the name of a package, possibly followed by a colon and a
  version number as a value. It will arrange for the interpreter to load that
  package (at that version number).

- `-environment` takes either an environment variable or a variable and its
  value. When followed by the name of a variable followed by an equal `=` sign
  and a value, this will set the environment variable to that value in the
  interpreter. When followed by just the name of an environment variable, it
  will arrange to pass the variable (and its value) to the safe interpreter.

  [socket]: https://www.tcl.tk/man/tcl/TclCmd/socket.htm

#### Strong Interpreters

Whenever the name of the file from which the interpreter is to be created starts
with an exclamation mark (`!`), the sign will be removed from the name when
looking for the implementation and the interpreter will be a regular (non-safe)
interpreter. This allows for more powerful interpreters, or to make use of
packages that have no support for the safe base.

Creating non-safe interpreters is not the preferred way of interacting with
external code. It should only be used in controlled and trusted environments.
Otherwise, `mqtt2any` is tuned for working with code in sandboxed interpreters
and the additional security that safe interpreters provide.

## Example

Runnint the following command leverages the `$SYS` tree made available at the
[mosquitto](http://test.mosquitto.org/) project. This uses the example data
dumping procedure described above.

    ./mqtt2any.tcl -broker mqtt://test.mosquitto.org -verbose "printer.tcl DEBUG * INFO" -routes "\$SYS/# print@printer.tcl \"\""

## Docker

A Docker [image](https://hub.docker.com/r/efrecon/mqtt2any/) is provided. The
image builds upon [efrecon/medium-tcl] in order to provide a rather complete
Tcl-programming environment for running MQTT treatment scripts. In order to
provide your own scripts, easiest is to make them available under the
`/var/mqtt2any/exts` directory of containers based on this image.

  [efrecon/medium-tcl]: https://hub.docker.com/r/efrecon/medium-tcl/