#DESCRIPTION

Running this script will do two things:

1. Prepare a server to accept SSH connections over TLS (even after a reboot).
2. Generate a script that you can then use from any client to access this
   server.

This script takes no arguments and will ask you for input interactively.


#RATIONALE

Why is this useful? What don't we just use SSH?

The main reason is... firewalls: most firewalls only allow HTTP/HTTPS outbound
traffic. Typically people worked around this by configuring their SSH servers
to listen on port 443 (the HTTPS port). However, most firewalls nowadays do not
just look at the destination port, but can actually tell if the outgoing
traffic is TLS (which is where HTTP is encapsulated in HTTPS) or not.

Using a TLS tunnel instead of an SSH one makes it harder (but not impossible!)
for firewalls to detect if this is HTTPS traffic or not.

    NOTE:
      It is not imposible because HTTP traffic is much less 'interactive' than
      the one generated from a remote shell, and an intelligent enough firewall
      should be able to detect this (however, so far, I don't think I have come
      across any of these)

Are there any drawbacks? Sure: speed. The channel is being encrypted twice
(once by TLS and another one by SSH).
Why do we use SSH, then? Couldn't we just directly open a shell inside the
TLS tunnel instead of running SSH? Yes, we could... but then we would miss
all the benefits SSH brings with it: users management, redirection tricks,
etc...

    NOTE:
      Also, the "speed reduction" is minimal. I haven't been able to notice it.


#PREREQUISITES

* You must run this script from a computer that has SSH access to the
  server you want to configure on port 22.
  This is only needed at this stage. Later, for the client to access, the
  server, only port 443 needs to be reachable from the Internet.

* The server must *not* be using port 443 (ie. you cannot have a web 
  server already running there).
  If this is not acceptable, forget about this script and try following the
  instructions detailed on this blog post:

    http://blog.chmd.fr/ssh-over-ssl-episode-4-a-haproxy-based-configuration.html

* This script is just a wrapper that calls 'openssl' (to generate the
  certificates) and 'socat' (to create the tunnel). You need both of them
  installed on the client and the server (and, obviously, 'ssh'/'sshd'):
  
      Examples:
        Debian/Ubuntu --> $ sudo aptitude install socat openssl
        Arch          --> $ sudo pacman -S socat openssl


#IMPLEMENTATION DETAILS

First, using openssl, a pair of TLS (X509) certificates will be generated (one
for the server and one for the client)

    NOTE: Every time this script runs, different pairs of certificates will be
    generated. This means you cannot run this script twice and expect the
    server configured with the first instance to accept connections from the
    client script created in the second instance.

Then, a remote server will be configured (using SSH) like this:
- The server certificate and the public part of the client certificate are
  copied to the '/etc/tls_tunnel_server' folder.
- The init system (either 'init.d' or 'systemd') is configured to run a 'socat'
  command that, using the just copied certificates, creates a TLS tunnel that
  is connected to localhost:22 (ie. the SSH server).
  Only a client with the corresponding client certificate will be granted
  access to the SSH server behind.

Finally, a script is generated meant to be used by the client. This script (a
single 'bash' script) contains everything the client needs: the client
certificate, the public part of the server certificate and the logic to run
socat to establish the TLS tunnel and SSH to use it.


# SECURITY CONSIDERATIONS

* The generated certificates are valid for one year, but you can easily change
  this: search for ````-days 365```` in the script and set the new desired
  value.

* The generated client script ("**ssh_over_tls_tunnel_client.sh**") will only
  connect to the server if it presents the expected certificate. This means
  that, as in a regular HTTPS connections, you can be sure there is no man in
  the middle.

* The server will only accept connections from clients with the expected
  certificate. This certificate is "embeded" inside the generated client script
  ("**ssh_over_tls_tunnel_client.sh**") in plain text. Because of this you
  should probably **not** upload this script to "the cloud", or if you do, first
  encrypt it. Example:

      Encryption (before uploading to the cloud):
      ------------------------------------------

      $ openssl enc -in ssh_over_tls_tunnel_client.sh \
                    -aes-256-cbc                      \
                    -pass stdin  > ssh_over_tls_tunnel_client.sh.enc

      Decryption (after downloading from the cloud):
      ---------------------------------------------

      $ openssl enc -in ssh_over_tls_tunnel_client.sh.enc \
                    -d -aes-256-cbc                       \
                    -pass stdin  > ssh_over_tls_tunnel_client.enc

  Note that *even if you don't encrypt it*, the amount of damage that results
  from this script being leaked to a third party is minimal as it only grants
  the owner permission to establish connection to the SSH server, which requires
  authentication anyway.

