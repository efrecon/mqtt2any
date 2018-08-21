FROM efrecon/medium-tcl
MAINTAINER Emmanuel Frecon <efrecon@gmail.com>

COPY *.tcl /opt/mqtt2any/
COPY lib/mqtt/ /opt/mqtt2any/lib/mqtt/
COPY lib/toclbox/ /opt/mqtt2any/lib/toclbox/

# Export the plugin directory so it gets easy to test new plugins.
VOLUME /opt/mqtt2any/exts

ENTRYPOINT ["tclsh8.6", "/opt/mqtt2any/mqtt2any.tcl"]