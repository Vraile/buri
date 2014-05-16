#! /bin/sh
#
# Taken from: https://raw.githubusercontent.com/apache/cassandra/cassandra-1.2/debian/init
#
### BEGIN INIT INFO
# Provides:          cassandra
# Required-Start:    $remote_fs $network $named $time
# Required-Stop:     $remote_fs $network $named $time
# Should-Start:      ntp mdadm
# Should-Stop:       ntp mdadm
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: distributed storage system for structured data
# Description:       Cassandra is a distributed (peer-to-peer) system for
#                    the management and storage of structured data.
### END INIT INFO

# Author: Eric Evans <eevans@racklabs.com>

DESC="Cassandra"
NAME=cassandra
PIDFILE=/var/run/$NAME.pid
SCRIPTNAME=/etc/init.d/$NAME
JSVC=/usr/bin/jsvc
WAIT_FOR_START=10
CASSANDRA_HOME={{ cassandra_home }}
CASSANDRA_CONF="${CASSANDRA_HOME}/conf"
CONFDIR="${CASSANDRA_HOME}/conf"
FD_LIMIT=100000

# The first existing directory is used for JAVA_HOME if needed.
JVM_SEARCH_DIRS="/usr/lib/jvm/default-java"

[ -e ${CASSANDRA_CONF}/cassandra.yaml ] || exit 0
[ -e ${CASSANDRA_CONF}/cassandra-env.sh ] || exit 0

# Read configuration variable file if it is present
[ -r /etc/default/$NAME ] && . /etc/default/$NAME

# If JAVA_HOME has not been set, try to determine it.
if [ -z "$JAVA_HOME" ]; then
    # If java is in PATH, use a JAVA_HOME that corresponds to that. This is
    # both consistent with how the upstream startup script works, and how
    # Debian works (read: the use of alternatives to set a system JVM).
    if [ -n "`which java`" ]; then
        java=`which java`
        # Dereference symlink(s)
        while true; do
            if [ -h "$java" ]; then
                java=`readlink "$java"`
                continue
            fi
            break
        done
        JAVA_HOME="`dirname $java`/../"
    # No JAVA_HOME set and no java found in PATH, search for a JVM.
    else
        for jdir in $JVM_SEARCH_DIRS; do
            if [ -x "$jdir/bin/java" ]; then
                JAVA_HOME="$jdir"
                break
            fi
        done
    fi
fi
JAVA="$JAVA_HOME/bin/java"

# Read Cassandra environment file.
. ${CONFDIR}/cassandra-env.sh

if [ -z "$JVM_OPTS" ]; then
    echo "Initialization failed; \$JVM_OPTS not set!" >&2
    exit 3
fi

# Load the VERBOSE setting and other rcS variables
. /lib/init/vars.sh

# Define LSB log_* functions.
# Depend on lsb-base (>= 3.0-6) to ensure that this file is present.
. /lib/lsb/init-functions

#
# Function that returns the applications classpath
#
classpath()
{
    cp="$EXTRA_CLASSPATH"
    for j in ${CASSANDRA_HOME}/lib/*.jar; do
        [ "x$cp" = "x" ] && cp=$j || cp=$cp:$j
    done
    for j in ${CASSANDRA_HOME}/*.jar; do
        [ "x$cp" = "x" ] && cp=$j || cp=$cp:$j
    done

    # use JNA if installed in standard location
    [ -r /usr/share/java/jna.jar ] && cp="$cp:/usr/share/java/jna.jar"

    # Include the conf directory for purposes of log4j-server.properties, and
    # commons-daemon in support of the daemonization class.
    printf "$cp:$CONFDIR:/usr/share/java/commons-daemon.jar"
}

#
# Function that returns 0 if process is running, or nonzero if not.
#
# The nonzero value is 3 if the process is simply not running, and 1 if the
# process is not running but the pidfile exists (to match the exit codes for
# the "status" command; see LSB core spec 3.1, section 20.2)
#
CMD_PATT="-user.cassandra.+CassandraDaemon"
is_running()
{
    if [ -f $PIDFILE ]; then
        pid=`cat $PIDFILE`
        grep -Eq "$CMD_PATT" "/proc/$pid/cmdline" 2>/dev/null && return 0
        return 1
    fi
    return 3
}

#
# Function that starts the daemon/service
#
do_start()
{
    # Return
    #   0 if daemon has been started
    #   1 if daemon was already running
    #   2 if daemon could not be started
    is_running && return 1

    ulimit -l unlimited
    ulimit -n "$FD_LIMIT"

    cassandra_home=`getent passwd cassandra | awk -F ':' '{ print $6; }'`
    cd /    # jsvc doesn't chdir() for us

    $JSVC \
        -user cassandra \
        -home $JAVA_HOME \
        -pidfile $PIDFILE \
        -errfile "&1" \
        -outfile {{ cassandra_log_location }}/output.log \
        -cp `classpath` \
        -Dlog4j.configuration=log4j-server.properties \
        -Dlog4j.defaultInitOverride=true \
        -XX:HeapDumpPath="$cassandra_home/java_`date +%s`.hprof" \
        -XX:ErrorFile="$cassandra_home/hs_err_`date +%s`.log" \
        $JVM_OPTS \
        org.apache.cassandra.service.CassandraDaemon

    is_running && return 0
    for tries in `seq $WAIT_FOR_START`; do
        sleep 1
        is_running && return 0
    done
    return 2
}

#
# Function that stops the daemon/service
#
do_stop()
{
	# Return
	#   0 if daemon has been stopped
	#   1 if daemon was already stopped
	#   2 if daemon could not be stopped
	#   other if a failure occurred
    is_running || return 1
    $JSVC -stop -home $JAVA_HOME -pidfile $PIDFILE \
            org.apache.cassandra.service.CassandraDaemon
    is_running && return 2 || return 0
}

case "$1" in
  start)
	[ "$VERBOSE" != no ] && log_daemon_msg "Starting $DESC" "$NAME"
	do_start
	case "$?" in
		0|1) [ "$VERBOSE" != no ] && log_end_msg 0 ;;
		2) [ "$VERBOSE" != no ] && log_end_msg 1 ;;
	esac
	;;
  stop)
	[ "$VERBOSE" != no ] && log_daemon_msg "Stopping $DESC" "$NAME"
	do_stop
	case "$?" in
		0|1) [ "$VERBOSE" != no ] && log_end_msg 0 ;;
		2) [ "$VERBOSE" != no ] && log_end_msg 1 ;;
	esac
	;;
  restart|force-reload)
	log_daemon_msg "Restarting $DESC" "$NAME"
	do_stop
	case "$?" in
	  0|1)
		do_start
		case "$?" in
			0) log_end_msg 0 ;;
			1) log_end_msg 1 ;; # Old process is still running
			*) log_end_msg 1 ;; # Failed to start
		esac
		;;
	  *)
	  	# Failed to stop
		log_end_msg 1
		;;
	esac
	;;
  status)
    is_running
    stat=$?
    case "$stat" in
      0) log_success_msg "$DESC is running" ;;
      1) log_failure_msg "could not access pidfile for $DESC" ;;
      *) log_success_msg "$DESC is not running" ;;
    esac
    exit "$stat"
    ;;
  *)
	echo "Usage: $SCRIPTNAME {start|stop|restart|force-reload|status}" >&2
	exit 3
	;;
esac

:

# vi:ai sw=4 ts=4 tw=0 et
