FROM efrecon/medium-tcl
MAINTAINER Emmanuel Frecon <efrecon@gmail.com>

COPY *.tcl /opt/mqtt2any/
COPY lib/ /opt/mqtt2any/lib/
COPY exts/*.tcl /opt/mqtt2any/exts/

# Export the plugin directory so it gets easy to test new plugins.
VOLUME /opt/mqtt2any/exts

ENTRYPOINT ["tclsh8.6", "/opt/mqtt2any/mqtt2any.tcl"]