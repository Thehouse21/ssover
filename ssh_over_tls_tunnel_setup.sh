#!/bin/bash

# Running this script will do two things:
# 
#   1. Prepare a server to accept SSH connections over TLS (even after a
#      reboot).
# 
#   2. Generate a script that you can then use from any client to access this
#      server.
# 
# This script takes no arguments and will ask you for input interactively.
#
# See 'README.md' for more details
#
set -e

OUTPUT_FOLDER=_DELETE_ME_
rm -rf $OUTPUT_FOLDER
mkdir  $OUTPUT_FOLDER

echo ""
echo "Generating client/server certificates. Please wait (this will take a while)..."
echo ""
for FILENAME in server client; do
    openssl genrsa -out $OUTPUT_FOLDER/$FILENAME.key 4096 &>/dev/null
    openssl req -new -key $OUTPUT_FOLDER/$FILENAME.key -x509 -days 3650 -batch -out $OUTPUT_FOLDER/$FILENAME.crt &>/dev/null
    cat $OUTPUT_FOLDER/$FILENAME.key $OUTPUT_FOLDER/$FILENAME.crt >$OUTPUT_FOLDER/$FILENAME.pem
    rm  $OUTPUT_FOLDER/$FILENAME.key
    chmod 600 $OUTPUT_FOLDER/$FILENAME.pem
done


echo "Certificates generated. What do you want to do now?"
echo ""
echo "  1. Automatically configure a >>init.d << based server with the necessary stuff."
echo "  2. Automatically configure a >>systemd<< based server with the necessary stuff."
echo "  3. Show me the instructions to manually configure a generic server."
echo ""
printf "Type '1', '2' '3' and press [ENTER]... "
while read KEY; do
    [[ "$KEY" =~ [1-3] ]] && break
    printf "Try again. type '1', '2' '3' (or CTRL+c to exit) and press [ENTER]... "
done
echo ""
echo ""


if [[ "$KEY" == "1" ]] || [[ "$KEY" == "2" ]]; then
    # Generate wrapper script
    #
    cat <<-EOF > $OUTPUT_FOLDER/ssh_over_tls_tunnel_server.sh
			while true; do
                socat openssl-listen:443,reuseaddr,cert=/etc/ssh_over_tls_tunnel_server/server.pem,cafile=/etc/ssh_over_tls_tunnel_server/client.crt tcp:localhost:22
			    sleep 1
			done
			EOF
fi


if   [[ "$KEY" == "1" ]]; then
    # Generate init.d script
    #
    cat <<-EOF > $OUTPUT_FOLDER/ssh_over_tls_tunnel_server
			### BEGIN INIT INFO
            # Provides:          ssh_over_tls_tunnel_server
			# Required-Start:    \$network \$local_fs \$remote_fs
			# Required-Stop::    \$network \$local_fs \$remote_fs
			# Should-Start:      \$all
			# Should-Stop:       \$all
			# Default-Start:     2 3 4 5
			# Default-Stop:      0 1 6
			# Short-Description: Start the SSH over TLS tunnel server at boot time
			# Description:       Allow remote SSH access over TLS
			### END INIT INFO
			#!/bin/sh
			
            SCRIPT=/usr/local/bin/ssh_over_tls_tunnel_server.sh
			
            PIDFILE=/var/run/ssh_over_tls_tunnel_server.pid
            LOGFILE=/var/log/ssh_over_tls_tunnel_server.log
			
			start() {
			  if [ -f /var/run/\$PIDNAME ] && kill -0 \$(cat /var/run/\$PIDNAME); then
			    echo 'Service already running' >&2
			    return 1
			  fi
			  echo 'Starting service…' >&2
			  local CMD="\$SCRIPT &> \"\$LOGFILE\" & echo \$\!"
			  su -c "\$CMD" > "\$PIDFILE"
			  echo 'Service started' >&2
			}
			
			stop() {
			  if [ ! -f "\$PIDFILE" ] || ! kill -0 \$(cat "\$PIDFILE"); then
			    echo 'Service not running' >&2
			    return 1
			  fi
			  echo 'Stopping service…' >&2
			  kill -15 \$(cat "\$PIDFILE") && rm -f "\$PIDFILE"
			  echo 'Service stopped' >&2
			}
			
			case "\$1" in
			  start)
			    start
			    ;;
			  stop)
			    stop
			    ;;
			  retart)
			    stop
			    start
			    ;;
			  *)
			    echo "Usage: \$0 {start|stop|restart}"
			    ;;
			esac
			
			EOF

    echo "Enter the IP of the remote server (ex: '192.168.10.7' or even 'tom@192.168.10.7'"
    echo "if the remote user is not the same as the current one). Note that the user must"
    printf "belong to the 'sudoers' group in the remote server: "
    read SERVER_USER_IP
    
    echo ""
    echo "We will now copy several files to the server."
    echo "You might be asked for the user password (on the remote server) several times."
    echo "Press [ENTER] to continue..."
    read

    chmod +x $OUTPUT_FOLDER/ssh_over_tls_tunnel_server.sh
    chmod +x $OUTPUT_FOLDER/ssh_over_tls_tunnel_server
    scp $OUTPUT_FOLDER/{ssh_over_tls_tunnel_server.sh,ssh_over_tls_tunnel_server,server.pem,client.crt} $SERVER_USER_IP:/tmp
    ssh $SERVER_USER_IP "sudo -- sh -c 'mv    /tmp/ssh_over_tls_tunnel_server.sh  /usr/local/bin;         \
                                        mv    /tmp/ssh_over_tls_tunnel_server     /etc/init.d;            \
                                        mkdir /etc/ssh_over_tls_tunnel_server    2>/dev/null || true;     \
                                        mv    /tmp/server.pem            /etc/ssh_over_tls_tunnel_server; \
                                        mv    /tmp/client.crt            /etc/ssh_over_tls_tunnel_server; \
                                        update-rc.d ssh_over_tls_tunnel_server defaults;                  \
                                        /etc/init.d/ssh_over_tls_tunnel_server start'
                        "

elif [[ "$KEY" == "2" ]]; then
    # Generate systemd unit file
    #
    cat <<-EOF > $OUTPUT_FOLDER/ssh_over_tls_tunnel_server.service
			[Unit]
			Description=Allow remote SSH access over TLS
			
			[Service]
			ExecStart=/usr/local/bin/ssh_over_tls_tunnel_server.sh
			
			[Install]
			WantedBy=multi-user.target
			EOF

    chmod +x $OUTPUT_FOLDER/ssh_over_tls_tunnel_server.sh
    #chmod +x $OUTPUT_FOLDER/ssh_over_tls_tunnel_server.service
    scp $OUTPUT_FOLDER/{ssh_over_tls_tunnel_server.sh,ssh_over_tls_tunnel_server.server,server.pem,client.crt} $SERVER_USER_IP:/tmp
    ssh $SERVER_USER_IP "sudo -- sh -c 'mv    /tmp/ssh_over_tls_tunnel_server.sh        /usr/local/bin;         \
                                        mv    /tmp/ssh_over_tls_tunnel_server.service   /etc/systemd/system;    \
                                        mkdir /etc/ssh_over_tls_tunnel_server         2>/dev/null || true;      \
                                        mv    /tmp/server.pem                 /etc/ssh_over_tls_tunnel_server;  \
                                        mv    /tmp/client.crt                 /etc/ssh_over_tls_tunnel_server;  \
                                        systemctl enable ssh_over_tls_tunnel_server;'
                        "

elif [[ "$KEY" == "3" ]]; then
    echo "Manual setup of the TLS tunnel in a generic server:"
    echo "  1. Copy 'server.pem' and 'client.crt' to the server:"
    echo "       $ scp $OUTPUT_FOLDER/server.pem root@<server_ip>:/etc/ssh_over_tls_tunnel_server"
    echo "       $ scp $OUTPUT_FOLDER/client.crt root@<server_ip>:/etc/ssh_over_tls_tunnel_server"
    echo "  2. Add a script that runs (with root privileges) the following code every time the server boots:"
    echo "       > while true; do"
    echo "       >     socat openssl-listen:443,reuseaddr,cert=/etc/ssh_over_tls_tunnel_server/server.pem,cafile=/etc/ssh_over_tls_tunnel_server/client.crt tcp:localhost:22"
    echo "       >     sleep 1"
    echo "       > done"
fi


# Create client "all-in-one" script

cat <<-EOF > $OUTPUT_FOLDER/ssh_over_tls_tunnel_client.sh
		#!/bin/bash
		
		if [[ -z "\$1" ]]; then
		    echo "Usage: %S [<user>@]<remote_server_ip> [extra ssh options, like '-X']"
		    exit 0
		fi
		
        SERVER=\$(echo \$1 | sed 's:.*@::')
		if [[ "\$SERVER" == "\$1" ]];then
		    USER=""
		else
            USER=\$(echo \$1 | sed 's:@.*::')@
		fi
		shift
		
		CLIENT_CERT=\$(mktemp /tmp/client.pem.XXXXXX)
		SERVER_CERT=\$(mktemp /tmp/server.crt.XXXXXX)
		cat \$0 | awk '/BEGIN client.pem/{flag=1;next}/END client.pem/{flag=0}flag' > \$CLIENT_CERT
		cat \$0 | awk '/BEGIN server.crt/{flag=1;next}/END server.crt/{flag=0}flag' > \$SERVER_CERT
		trap 'rm -f \$CLIENT_CERT \$SERVER_CERT' INT TERM HUP EXIT
		
		printf "Setting TLS tunnel up... "
		socat tcp-listen:6969,reuseaddr openssl-connect:\$SERVER:443,cert=\$CLIENT_CERT,cafile=\$SERVER_CERT,commonname= &
		sleep 3
		echo "Done!"
		echo "SSH'ing into 'localhost:6969' to access the remote server..."
		
		ssh \${USER}localhost -p 6969 \$@
		
		exit
		
		
		################################################################################
		# From this point on nothing is executed
		################################################################################
		
		EOF
echo "BEGIN client.pem"         >> $OUTPUT_FOLDER/ssh_over_tls_tunnel_client.sh
cat  $OUTPUT_FOLDER/client.pem  >> $OUTPUT_FOLDER/ssh_over_tls_tunnel_client.sh
echo "END client.pem"           >> $OUTPUT_FOLDER/ssh_over_tls_tunnel_client.sh
echo "BEGIN server.crt"         >> $OUTPUT_FOLDER/ssh_over_tls_tunnel_client.sh
cat  $OUTPUT_FOLDER/server.crt  >> $OUTPUT_FOLDER/ssh_over_tls_tunnel_client.sh
echo "END server.crt"           >> $OUTPUT_FOLDER/ssh_over_tls_tunnel_client.sh
chmod +x $OUTPUT_FOLDER/ssh_over_tls_tunnel_client.sh

echo ""
echo "This is how you connect to the TLS server from a client PC:"
echo "  * Option A: with a script"
echo "      1. Simply take the ($OUTPUT_FOLDER/just generated) 'ssh_over_tls_tunnel_client.sh' script with you and execute"
echo "         it from the client"
echo "  * Option B: manually"
echo "      1. Copy 'client.pem' and 'server.crt' to the client:"
echo "           $ scp $OUTPUT_FOLDER/client.pem <user>@<client_ip>:~/ssh_over_tls_tunnel_client"
echo "           $ scp $OUTPUT_FOLDER/server.crt <user>@<client_ip>:~/ssh_over_tls_tunnel_client"
echo "      2. Run the following command in a terminal, don't close it:"
echo "           $ socat tcp-listen:6969,reuseaddr openssl-connect:<server_ip>:443,cert=~/ssh_over_tls_tunnel_client/client.pem,cafile=~/ssh_over_tls_tunnel_client/server.crt,commonname= "
echo "      3. Run the following command in a new terminal:"
echo "           $ ssh <user>@localhost -p 6969"
echo "      4. Once you are finished, 'exit' the ssh session and socat will automatically terminate"
echo "           $ exit"
echo ""
echo "ONE MORE THING:"
echo "Don't forget to *delete* the output folder ('$OUTPUT_FOLDER') on *this* PC"
echo "once you are done. It contains certificates that should remain secret!"
echo ""

