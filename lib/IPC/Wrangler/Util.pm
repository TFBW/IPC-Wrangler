use IPC::Wrangler::Policy;

package IPC::Wrangler::Util;

use Exporter qw(import);

=head1 NAME

IPC::Wrangler::Util - miscellaneous importable functions

=head1 DESCRIPTION

The following functions are available for import.

=cut

our @EXPORT_OK = qw(
    enum
    );

=head2 enum

    $hash = enum(@list);

Given a @list of strings, returns a hashref where the keys are
elements of @list and the value is the corresponding array index.
E.g. C<qw(a b c)> becomes C<< { a => 0, b => 1, c => 2 } >>.

=cut

sub enum {
    my %h;
    $h{$_[$_]} = $_ for 0..$#_;
    return \%h;
}

1;
