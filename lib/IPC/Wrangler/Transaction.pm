use IPC::Wrangler::Policy;

package IPC::Wrangler::Transaction;

=head1 EXPERIMENTAL

An object of this class is returned when requesting any kind of
operation, client side.  It permits async execution of the operation
without obliging it.

The basic theory is that there are two asynchronous activities to
perform: a "send" activity and a "receive" activity.  The "receive"
won't happen unless the "send" succeeds, but the two do not need to be
forcibly synchronised: they can be effectively simultaneous.  There
may also be a "cleanup" activity.

=cut

use AnyEvent;

sub new {
    my ($class, $on_destroy) = @_;
    return bless([AE::cv, AE::cv,
}

sub _send_cv     { @_ > 1 ? $_[0][0] = $_[1] : $_[0][0] }
sub _receive_cv  { @_ > 1 ? $_[0][1] = $_[1] : $_[0][1] }
sub _response_cb { @_ > 1 ? $_[0][2] = $_[1] : $_[0][2] }
sub _destroy_cb  { @_ > 1 ? $_[0][3] = $_[1] : $_[0][3] }

=head2 send

Block until the request has been sent.

=cut

sub send {
    my ($self) = @_;
    $self->_send_cv->recv;
    return $self;
}

=head2 receive

Block until the response has been received or the timeout is reached.

=cut

sub receive {
    my ($self) = @_;
    $self->_receive_cv->recv;
    return $self;
}

=head2 response

Returns the response, blocking if necessary.

=cut

sub response {
    my ($self) = @_;
    $self->receive;
    return $self->_response;
}

=head2 on_response

Set a callback function to be invoked 
This will be called once per message received in the case of a subscription.

=cut

sub on_response {
    my ($self, $code) = @_;
    $self->_receive_cv->cb(sub { $code->($self->_response) });
    return $self;
}

sub on_finish { }

1;

