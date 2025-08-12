use IPC::Wrangler::Policy;

package IPC::Wrangler::Client::Socket;

use IPC::Wrangler::Encoding qw(encode_canonical);
use IPC::Wrangler::Util qw(enum);

use constant enum qw(PROVIDER SERVER);

=head1 EXPERIMENTAL

Trying to find a good API.  Current theory is that I need to do a
better job of abstracting out the request object, but I can have a
single socket client object for both synchronous and asynchronous
operation.  The async version can make use of AnyEvent without a
direct dependency, passively detecting availability.

=head1 PROTOCOL

Messages are terminated with "\n" (platform-specific).  Messages are
byte-strings which must not contain "\n".  Client speaks first and
sends one message.  In all cases except subscription, server then
sends one message and closes the socket.  In the subscriptions case,
the server may send any number of messages before closing the socket.
If the client wishes to signal end of subscription, it may close the
socket or shut down the send half; the server may attempt to send a
final message when it detects this EOF, but should close the socket
immediately afterwards.  Either party may close the socket at any time
during the protocol and the other party is expected to deal with it:
clients should synthesise an UGLY response; servers should cancel
associated work; incomplete messages should be discarded.

=cut

my $TRN = "IPC::Wrangler::Client::Socket::base";

sub new {
    my ($class, $provider, $server) = @_;
    return bless([$provider, $server], ref($class)||$class);
}

sub request {
    my ($self, $type, @args) = @_;
    return encode_canonical($type, $self->[PROVIDER], @args);
}

sub query {
    my ($self, @args) = @_;
    return $TRN->new($self->[SERVER], $self->request(Q => @args));
}


package IPC::Wrangler::Client::Socket::base;

use IO::Socket::UNIX;
use IPC::Wrangler::Deadline qw(deadline_in);
use IPC::Wrangler::Encoding qw(decode);
use IPC::Wrangler::Response qw(GOOD BAD UGLY);
use IPC::Wrangler::Util qw(enum);
use Socket qw(SOCK_STREAM SO_RCVTIMEO SO_SNDTIMEO);

use constant enum qw(RESPONSE SOCK DEADLINE BUFFER CB AE_IN AE_OUT AE_TIMER);
use constant DEFAULT_TIMEOUT => 10;
use constant MAX_READ => 2 ** 18; # 256KB
use constant MSG_NOSIGNAL
    => exists(&Socket::MSG_NOSIGNAL) ? Socket::MSG_NOSIGNAL() : 0;
use constant SO_NOSIGPIPE
    => exists(&Socket::SO_NOSIGPIPE) ? Socket::SO_NOSIGPIPE() : 0;

sub BLOCKED { $!{EAGAIN} || $!{EWOULDBLOCK} }
sub USING_AE { exists(&AnyEvent::io) }

sub new {
    my ($class, $server, $msg, $tlim) = @_;
    my $self = bless([], ref($class)||$class);
    my $sock = IO::Socket::UNIX->new(Type => SOCK_STREAM, Peer => $server)
        // return $self->error("Can't create socket: $!");
    $self->[SOCK] = $sock;
    $sock->sockopt(SO_NOSIGPIPE, 1)
        if SO_NOSIGPIPE; # avoid SIGPIPE if possible
    my $deadline = $self->[DEADLINE] = deadline_in($tlim // DEFAULT_TIMEOUT);
    #@! Sending:<$msg>
    $msg .= "\n";
    # Attempt one-shot non-blocking write: it usually works.
    $sock->blocking(0);
    my $n = send($sock, $msg, MSG_NOSIGNAL);
    return $self->io_error("Send")
        unless defined $n or BLOCKED;
    substr($msg, 0, $n, '');
    $self->[BUFFER] = '';
    return $self->event_io($msg)
        if USING_AE;
    # Send the rest with blocking and timeouts.
    while ($msg ne '') {
        #@! Sent partial: $n bytes; @{[length $msg]} remaining
        my $err = $self->set_timeout;
        return $self->error("Set timeout failed: $err")
            if $err;
        if ($n = send($sock, $msg, MSG_NOSIGNAL)) { substr($msg, 0, $n, '') }
        elsif ($!{EINTR}) { $n = 0 }
        else { return $self->io_error("Send") }
    }
    #@! Send complete
    return $self;
}

sub set_cb {
    my $self = shift;
    $self->[CB] = shift;
    return $self;
}

sub event_io {
    my ($self, $msg) = @_;
    my $sock = $self->[SOCK]
        or return $self->error("BUG: attempt to do async_io with no socket");
    my $rem = $self->[DEADLINE] ? $self->[DEADLINE]->remaining : 0;
    return $self->error("Zero deadline", 'TIMEOUT')
        unless $rem > 0;
    #@! Set up AnyEvent watchers; @{[length $msg]} bytes to send
    # Note that $self->error wipes all these
    $self->[AE_IN] = AnyEvent->io(
        fh => $sock, poll => 'r', cb => sub {
            recv($sock, my $msg, MAX_READ, MSG_NOSIGNAL)
                // return $!{EINTR} ? 0 : $self->io_error("Recv");
            #@! AE recv @{[length $msg]} bytes
            return $self->error("Provider closed socket", 'EOF')
                if $msg eq '';
            $self->[BUFFER] .= $msg;
            1 while $self->extract_response;
        });
    $self->[AE_OUT] = AnyEvent->io(
        fh => $sock, poll => 'w', cb => sub {
            my $n = send($sock, $msg, MSG_NOSIGNAL);
            $n //= $!{EINTR} ? 0 : -1;
            #@! AE send: $n
            substr($msg, 0, $n, '') if $n > 0;
            $self->io_error("Send") if $n < 0;
            undef $self->[AE_OUT] if $n == -1 or $msg eq '';
        }) if $msg ne '';
    $self->[AE_TIMER] = AnyEvent->timer(
        after => $rem, cb => sub {
            #@! AE timeout
            $self->error("Timed out", 'TIMEOUT');
        });
    return $self;
}

# Extracts next response from buffer; returns response or undef
sub extract_response {
    my ($self) = @_;
    return () unless defined $self->[BUFFER];
    my $eol = index($self->[BUFFER], "\n");
    return () if $eol < 0;
    #@! Complete response found
    $self->[RESPONSE] = IPC::Wrangler::Response->new(
        decode(substr($self->[BUFFER], 0, $eol))
        );
    substr($self->[BUFFER], 0, $eol + length("\n"), '');
    $self->[CB]->($self)
        if $self->[CB];
    return $self->[RESPONSE];
}

# Sets a locally-generated error response
sub error {
    my $self = shift;
    #@! Error: @_
    my $cb = $self->[CB];
    @$self = ();
    $self->[RESPONSE] = UGLY(@_, 'LOCAL');
    $cb->($self) if $cb;
    return $self;
}

# Fail based on $!
sub io_error {
    my ($self, $op) = @_;
    return BLOCKED ?
        $self->error("$op timed out", 'TIMEOUT') :
        $self->error("$op failed: $!");
}

# Returns $self after populating RESPONSE
sub receive {
    my ($self) = @_;
    my $sock = $self->[SOCK]
        or return $self->error("requested response with no socket");
    if (USING_AE) {
        #@! Awaiting response (AE)
        my $cv = AnyEvent->condvar;
        my $cb = $self->[CB];            # note old CB
        $self->[CB] = sub { $cv->send }; # steal CB
        $cv->recv;                       # wait for response
        $self->[CB] = $cb;               # restore old CB
        $cb->($self) if $cb;             # call old CB
    }
    else {
        #@! Awaiting response
        my ($r, $err, $msg);
        until ($r = $self->extract_response) {
            $err = $self->set_timeout;
            return $self->error("Set timeout failed: $err")
                if $err;
            recv($sock, $msg, MAX_READ, MSG_NOSIGNAL)
                // ($!{EINTR} ? next : return $self->io_error("Recv"));
            #@! Received @{[length $msg]} bytes
            return $self->error("Provider closed socket", 'EOF')
                if $msg eq '';
            $self->[BUFFER] .= $msg;
        }
    }
    return $self;
}

sub response {
    my ($self) = @_;
    return $self->[RESPONSE] // $self->receive->[RESPONSE];
}

sub has_response { defined $_[0]->[RESPONSE] }

# Set socket to block with timeout or not block at all; return error
sub set_timeout {
    my ($self) = @_;
    my $sock = $self->[SOCK]
        or return "no socket";
    my $rem = $self->[DEADLINE]->remaining;
    if ($rem > 0) {
        $sock->blocking(1)
            // return "can't set socket to blocking mode: $!";
        my $sec = int($rem);
        my $timeval = pack('l!l!', $sec, int(1_000_000 * ($rem - $sec)));
        $sock->sockopt(SO_RCVTIMEO, $timeval)
            // return "can't set SO_RCVTIMEO: $!";
        $sock->sockopt(SO_SNDTIMEO, $timeval)
            // return "can't set SO_SNDTIMEO: $!";
    }
    else {
        $sock->blocking(0)
            // return "can't set socket to non-blocking mode: $!";
    }
    return;
}

sub DESTROY {
    #@! DESTROY $_[0]
}

1;
