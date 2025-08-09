use IPC::Wrangler::Policy;

package IPC::Wrangler::Deadline;

use Exporter qw(import);
use Scalar::Util qw(looks_like_number);
use Socket qw(SO_RCVTIMEO SO_SNDTIMEO);
use Time::HiRes qw(time);

=head1 NAME

IPC::Wrangler::Deadline - object for managing timeouts

=head1 SYNOPSIS

    use IPC::Wrangler::Deadline qw(to_seconds deadline_in);
    $sec = to_seconds($duration);
    $deadline = deadline_in($duration);
    $sec = $deadline->remaining;
    $bool = $deadline->expired;
    $deadline->setsockopt($sock);

=head1 DESCRIPTION

This module provides a simple object model for deadlines and timeouts.
It also has a specialised method for setting socket timeout options to
match the deadline, and a simple duration string parser function.

L<Time::HiRes> is used for deadlines; numbers can be floats.

=cut

our @EXPORT_OK = qw(to_seconds deadline_in deadline_at);

=head1 FUNCTIONS

The following functions can be imported.

=head2 to_seconds

    $sec = to_seconds($duration);

Converts $duration to a number of seconds.  The duration can be either
a plain number, in which case it is passed through as is, or a number
with a suffix of "s" (seconds), "m" (minutes), "h" (hours), or "d"
(days); e.g. "2.5m" is 150 seconds.  Dies if $duration is invalid.

=cut

my %UNIT = (
    s => 1,
    m => 60,
    h => 60 * 60,
    d => 60 * 60 * 24,
    );

sub to_seconds {
    my ($t) = @_;
    unless (looks_like_number($t)) {
        die "Invalid duration '$t'\n"
            unless $t =~ /^(.+)(.)$/
            and looks_like_number($1)
            and $UNIT{$2};
        $t = $1 * $UNIT{$2};
    }
    return $t;
}

=head2 deadline_in, deadline_at

Function shortcuts for class methods new_in() and new_at().

=cut

sub deadline_in { __PACKAGE__->new_in(@_) }
sub deadline_at { __PACKAGE__->new_at(@_) }

=head2 METHODS

The main interface is the object model, as follows.

=head2 new_in

    $self = $class->new_in($duration);

Creates an object with a deadline $duration in the future.  THe
$duration is interpreted through the to_seconds() function, above.

=cut

sub new_in {
    my ($class, $rel) = @_;
    return $class->new_at(time + to_seconds($rel));
}

=head2 new_at

    $self = $class->new_at($time);

Creates an object with a deadline at the given Unix epoch $time.

=cut

sub new_at {
    my ($class, $time) = @_;
    return bless(\$time, ref($class)||$class);
}

=head2 remaining

    $sec = $self->remaining;

Returns the number of seconds remaining until the deadline is reached,
or zero if the deadline has been reached.

=cut

sub remaining {
    my ($self) = @_;
    my $rem = $$self - time;
    return $rem > 0 ? $rem : 0;
}

=head2 expired

Returns true if the deadline has been reached.

=cut

sub expired { time > ${$_[0]} }

=head2 setsockopt

    $self->setsockopt($socket);

Sets read/write timeouts on the $socket to match the deadline, or sets
non-blocking mode if expired.  The $socket should be an L<IO::Socket>
object.  Call this immediately before performing IO operations and be
ready to catch EAGAIN, EWOULDBLOCK, and possibly EINPROGRESS errors.
Dies if any of the changes fail or returns $self.

=cut

sub setsockopt {
    my ($self, $sock) = @_;
    my $rem = $$self - time;
    if ($rem > 0) {
        $sock->blocking(1)
            // die "Can't set socket to blocking mode: $!\n";
        my $sec = int($rem);
        my $timeval = pack('l!l!', $sec, int(1_000_000 * ($rem - $sec)));
        $sock->sockopt(SO_RCVTIMEO, $timeval)
            // die "Can't set SO_RCVTIMEO: $!\n";
        $sock->sockopt(SO_SNDTIMEO, $timeval)
            // die "Can't set SO_SNDTIMEO: $!\n";
    }
    else {
        $sock->blocking(0)
            // die "Can't set socket to non-blocking mode: $!\n";
    }
    return $self;
}

1;
