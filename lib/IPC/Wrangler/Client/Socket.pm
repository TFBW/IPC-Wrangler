use IPC::Wrangler::Policy;

package IPC::Wrangler::Client::Socket;

use IPC::Wrangler::Encoding qw(encode_canonical);
use IPC::Wrangler::Util qw(enum);

use constant enum qw(PROVIDER SERVER);

=head1 EXPERIMENTAL

Trying to find a good API.  Current theory is that there is a common
front end class which can generate transactions in multiple backend
classes depending on the preferred IO model: e.g. blocking, AnyEvent.

=cut

my $TRN = "IPC::Wrangler::Client::Socket::blocking";

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


package IPC::Wrangler::Client::Socket::blocking;

use IO::Socket::UNIX;
use IPC::Wrangler::Deadline qw(deadline_in);
use IPC::Wrangler::Encoding qw(decode);
use IPC::Wrangler::Response qw(GOOD BAD UGLY);
use IPC::Wrangler::Util qw(enum);
use Socket qw(SOCK_STREAM);

use constant enum qw(SOCK DEADLINE BUFFER RESPONSE);
use constant DEBUG => 1;
use constant DEFAULT_TIMEOUT => 10;
use constant MAX_READ => 2 ** 18; # 256KB
use constant MSG_NOSIGNAL
    => exists(&Socket::MSG_NOSIGNAL) ? Socket::MSG_NOSIGNAL() : 0;
use constant SO_NOSIGPIPE
    => exists(&Socket::SO_NOSIGPIPE) ? Socket::SO_NOSIGPIPE() : 0;

sub new {
    my ($class, $server, $msg, $tlim) = @_;
    $tlim //= DEFAULT_TIMEOUT;
    my $self = bless([], ref($class)||$class);
    $self->[SOCK] = IO::Socket::UNIX->new(Type => SOCK_STREAM, Peer => $server)
        // return $self->error("Can't create socket: $!");
    $self->[SOCK]->sockopt(SO_NOSIGPIPE, 1)
        if SO_NOSIGPIPE; # avoid SIGPIPE if possible
    $self->[DEADLINE] = deadline_in($tlim);
    return $self->send($msg);
}

sub error {
    my $self = shift;
    $self->[RESPONSE] = UGLY(@_, 'LOCAL');
    return $self;
}

sub timeout { $_[0]->error("Timed out", 'TIMEOUT') }

sub send {
    my ($self, $msg) = @_;
    my $sock = $self->[SOCK]
        or return $self->error("BUG: attempt to send with no socket");
    warn "Sending: $msg\n" if DEBUG;
    $msg .= "\n";
    my $n;
    while (length($msg)) {
        $self->[DEADLINE]->setsockopt($sock);
        if ($n = send($sock, $msg, MSG_NOSIGNAL)) {
            substr($msg, 0, $n, '');
            warn "Sent: $n bytes; @{[length($msg)]} remain\n" if DEBUG;
        }
        else {
            return $self->timeout
                if $!{EAGAIN} || $!{EWOULDBLOCK};
            return $self->error("Write failed: $!");
        }
    }
    return $self;
}

sub receive {
    my ($self) = @_;
    my $sock = $self->[SOCK]
        or return $self->error("BUG: attempt to receive with no socket");
    warn "Awaiting response\n" if DEBUG;
    my ($n, $eol);
    $self->[BUFFER] //= '';
    while (($eol = index($self->[BUFFER], "\n")) == -1) {
        $self->[DEADLINE]->setsockopt($sock);
        last unless $n = sysread(
            $sock, $self->[BUFFER], MAX_READ, length($self->[BUFFER])
            );
        warn "Got: $n bytes\n" if DEBUG;
    }
    if ($eol >= 0) {
        warn "Response received\n" if DEBUG;
        my ($type, @msg) = decode(substr($self->[BUFFER], 0, $eol));
        $self->[RESPONSE] =
            $type eq '+' ? GOOD(@msg) :
            $type eq '-' ? BAD(@msg)  :
            $type eq '!' ? UGLY(@msg) :
            UGLY("Malformed response");
        substr($self->[BUFFER], 0, $eol + length("\n"), '');
    }
    elsif (defined $n) { $self->error("Provider closed socket", 'EOF') }
    elsif ($!{EAGAIN} || $!{EWOULDBLOCK}) { $self->timeout }
    else { $self->error("Read failed: $!") }
    return $self;
}

sub response {
    my ($self) = @_;
    return $self->[RESPONSE] // $self->receive->[RESPONSE];
}

1;
