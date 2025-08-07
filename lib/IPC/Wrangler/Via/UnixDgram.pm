use IPC::Wrangler::Policy;

package IPC::Wrangler::Via::UnixDgram;

# Experimental class: trying to find the right API for the job.

sub new {
    my ($class, $provider, $socket) = @_;
    return bless([$provider, $socket], ref($class)||$class);
}


package IPC::Wrangler::Via::UnixDgram::Client;

use IO::Socket qw(sockaddr_un);
use IO::Socket::UNIX;
use IPC::Wrangler::Encode qw(decode encode encode_canonical);
use IPC::Wrangler::Response qw(GOOD BAD UGLY);
use IPC::Wrangler::Transaction;
use Scalar::Util qw(weaken);
use Socket qw(MSG_DONTWAIT);

use constant DEBUG => 1;

my ($SOCKET, $WATCHER, $ID, %REQ);

# FIXME: this needs to be fork-safe, thread-safe, not rely on a Linux
# abstract socket, remove the socket on exit, etc, etc, etc...
sub _socket {
    unless ($SOCKET) {
        $SOCKET = IO::Socket::UNIX->new(
            Type     => IO::Socket::SOCK_DGRAM,
            Local    => "\0IPC::Wrangler.client.$$",
            Blocking => 0,
            ) or die "Can't create socket: $IO::Socket::errstr\n";
        $WATCHER = AE::io $SOCKET, 0, \&_receive;
    }
    return $SOCKET;
}

sub _receive {
    my $response;
    $SOCKET->recv($response, 65535);
    warn "Got: $response\n" if DEBUG;
    my ($id, $type, @msg) = decode($response);
    return unless exists $MSG{$id};
    my $response =
        $type eq '+' ? GOOD(@msg) :
        $type eq '-' ? BAD(@msg)  :
        $type eq '!' ? UGLY(@msg) :
        UGLY("Malformed response");
    $MSG{$id}->set_response($response);
    return;
}

# FIXME: improve the ID tracking
$ID = 0;
sub _next_id { ++$ID }

sub _send {
    my $server = shift;
    my $id = &_next_id;
    my $trans = $REQ{$id} = IPC::Wrangler::Transaction->new(sub { delete $REQ{$id} });
    weaken $REQ{$ID};
    my $request = encode($id, @_);
    unless (&_socket->send($request, MSG_DONTWAIT, $server)) {
        # respond UGLY
    }
    return $trans;
}


sub new {
    my ($class, $provider, $server) = @_;
    $server = sockaddr_un($server);
    return bless([$provider, $server], ref($class)||$class);
}

sub _provider { $_[0][0] }
sub _server   { $_[0][1] }

sub query {
    my ($self, $name, @args) = @_;
    # Dispatch the query
    # Return the reponse handle
}

sub mutate;

sub subscribe;


package IPC::Wrangler::Via::UnixDgram::Server;

sub new;

sub query; # name => code/object/class?

sub mutation;

sub subscription;

sub serve; # URL


1;
