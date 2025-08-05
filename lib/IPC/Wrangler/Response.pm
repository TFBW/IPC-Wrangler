use IPC::Wrangler::Policy;

package IPC::Wrangler::Response;

use Exporter qw(import);
use Scalar::Util qw(blessed);

=head1 NAME

IPC::Wrangler::Response - IPC response object abstraction

=head1 SYNOPSIS

    use IPC::Wrangler::Response qw(GOOD BAD UGLY try);
    $response = try {
        my ($x) = @_;
        return GOOD($x + 1) if $x > 0;
        return BAD("x must be positive");
    } @args;
    print $response->on_gbu(
        "That worked.\n",
        "That didn't work.\n",
        "That crashed!\n"
        );

=head1 DESCRIPTION

L<IPC::Wrangler> uses an object abstraction for IPC responses.  This
module documents response objects and provides factory functions for
generating them, plus a function for generating such a response from
arbitrary code.  The general theory is that IPC responses come in
three kinds: GOOD, BAD, and UGLY, as follows.

=over 4

=item GOOD

Normal responses which represent the data associated with the
fulfilment of a request, or just a positive anknowledgement.

=item BAD

Negative responses which indicate that the request was understood but
rejected, whether for policy reasons or because certain requirements
were not met.

=item UGLY

Failures which lie outside the normal parameters of the request: some
resource may have been unavailable, or some part of the process failed
for miscellaneous reasons.  The request itself has not been rejected
as such, retrying may be a reasonable strategy.

=back

The parameters returned in a GOOD response are completely specific to
the request.  The BAD and UGLY responses consist of a "reason" string,
intended as an informative error message, followed by optional error
code strings which can be used to convey more specific details.  The
@codes are an informal mechanism: the suggested approach is to use
"name=val" strings with distinctive names for which a client may scan.

There can be some question as to what kind of response is appropriate
to various conditions.  Sometimes it's best to send a negative outcome
in a GOOD response, so long as the structure of the data returned
makes the failure clear.  Consider the ergonomics of response-checking
when choosing a strategy.

=head1 FUNCTIONS

This module offers the following functions for import.

=cut

our @EXPORT_OK = qw(BAD GOOD UGLY try);

=head2 GOOD

    $response = GOOD(@result);

Factory function for generating GOOD response objects.  The arguments
become the result.

=cut

sub GOOD { bless([@_], 'IPC::Wrangler::Response::good') }

=head2 BAD, UGLY

    $response = BAD($reason, @codes);
    $response = UGLY($reason, @codes);

Factory function for generating BAD and UGLY response objects.  Both
take a reason string and optional @codes.  The reason string is a
generic error message; the codes are strings which may convey more
information about the failure in a machine-readable way.

=cut

sub BAD  { bless([@_], 'IPC::Wrangler::Response::bad' ) }
sub UGLY { bless([@_], 'IPC::Wrangler::Response::ugly') }

=head2 try

    $response = try($code, @args);

Invokes C<< @result = $code->(@args) >> and returns the @result as a
response object.  If the $code returns a single blessed object which
evaluates true for C<< ->DOES('IPC::Wrangler::Response') >> (such as
GOOD, BAD, or UGLY), then that object is the $response; otherwise,
$response is C<< GOOD(@result) >>.  If $code is not a CODE ref or it
raises an exception when called, then $response is UGLY.

=cut

sub try {
    my $code = shift;
    unless (ref($code) eq 'CODE') {
        $code = ref($code) || (defined($code) ? qq("$code") : 'undef');
        return UGLY("BUG: attempt to try($code)");
    }
    my @result = eval { $code->(@_) };
    if (my $ex = $@) {
        chomp $ex;
        return UGLY("Exception: $ex");
    }
    return @result == 1 && blessed($result[0]) && $result[0]->DOES(__PACKAGE__)
        ? $result[0] : GOOD(@result);
}

sub DOES { $_[1] && $_[1] eq __PACKAGE__ }

=head1 OBJECT MODEL

B<IPC::Wrangler::Response> objects, whether GOOD, BAD, or UGLY, have
the following methods.

=head2 is_good, is_bad, is_ugly

Boolean methods which take no arguments and return true for the given
response type.

=head2 on_gbu

    $value = $response->on_gbu($good, $bad, $ugly);

Returns $good, $bad, or $ugly, depending on the response type.  If the
chosen value is a CODE reference, it is invoked with no arguments, and
$value is whatever that CODE returns.

=head2 reason

Returns empty string for GOOD, the "reason" string for BAD and UGLY.

=head2 codes

Returns empty list for GOOD, the @codes (if any) for BAD and UGLY.

=head2 result

Returns the list of results or the first item in a scalar context for
GOOD; dies for BAD and UGLY.

=cut

package IPC::Wrangler::Response::good {
    *DOES = \&IPC::Wrangler::Response::DOES;
    sub is_good { 1 }
    sub is_bad  { 0 }
    sub is_ugly { 0 }
    sub on_gbu  { ref($_[1]) eq 'CODE' ? $_[1]->() : $_[1] }
    sub reason  { '' }
    sub codes   { () }
    sub result  { wantarray ? @{$_[0]} : $_[0][0] }
}

package IPC::Wrangler::Response::bad {
    *DOES = \&IPC::Wrangler::Response::DOES;
    sub is_good { 0 }
    sub is_bad  { 1 }
    sub is_ugly { 0 }
    sub on_gbu  { ref($_[2]) eq 'CODE' ? $_[2]->() : $_[2] }
    sub reason  { $_[0][0] }
    sub codes   { @{$_[0]}[1..$#{$_[0]}] }
    sub result  { die "[BAD] $_[0][0]\n" }
}

package IPC::Wrangler::Response::ugly {
    *DOES = \&IPC::Wrangler::Response::DOES;
    sub is_good { 0 }
    sub is_bad  { 0 }
    sub is_ugly { 1 }
    sub on_gbu  { ref($_[3]) eq 'CODE' ? $_[3]->() : $_[3] }
    sub reason  { $_[0][0] }
    sub codes   { @{$_[0]}[1..$#{$_[0]}] }
    sub result  { die "[UGLY] $_[0][0]\n" }
}

1;
