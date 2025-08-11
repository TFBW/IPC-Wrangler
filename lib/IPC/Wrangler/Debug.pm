package IPC::Wrangler::Debug;

use strict;
use warnings;

use Filter::Util::Call;

=head1 NAME

IPC::Wrangler::Debug - source filter which turns comments into log messages

=head1 SYNOPSIS

    use if $ENV{DEBUG}, 'IPC::Wrangler::Debug';
    #@! This is a debug message.

=head1 DESCRIPTION

This module is a Perl source filter which turns lines starting with
optional whitespace then "#@!" into debug output.  Without the filter,
these will typically be simple comments.  Any whitespace immediately
after "#@!" is skipped, then the remainder of the line is interpreted
as a double-quoted string.  To simplify quoting, backticks are not
permitted in the string and will be stripped: you will be warned if
this happens.

At run time, debug output is sent to STDERR via warn() with a simple
elapsed time counter and file name/line prefix.  If STDERR is a TTY,
the prefix part is ANSI coloured for visual distinctiveness.

=head1 NOTE

I'm not suggesting this as a general-purpose debug mechanism: Perl
source filters are fraught with peril and should be used B<very>
sparingly.  That said, this approach has three significant advantages
over any other approach.

=over 4

=item *

The source is valid and reasonable when the filter is excluded.

=item *

The filter can be excluded very easily via "use if".

=item *

There is B<zero> overhead for the debug log when excluded.

=back

This allows debug messages to be added without performance concerns,
and they act as reasonably informative comments even when inactive.
Just be careful not to include the debug-marker "#@!" at the start of
a line in the middle of a multi-line string, or similar.

=cut

my $COL = -t STDERR ? "\e[91;44m" : '';
my $OFF = -t STDERR ? "\e[0m"     : '';

sub import {
    filter_add sub {
        my $status = filter_read();
        if ($status > 0 and /^(\s*)#\@!\s*(.*)/) {
            my $debug = $2;
            my $stripwarn =
                $debug =~ tr/`//d ?
                q|BEGIN { warn "Backticks stripped from debug message" } | :
                '';
            $_ = qq|$1${stripwarn}warn IPC::Wrangler::Debug::msg(__FILE__, __LINE__, qq`$debug`);\n|;
        }
        return $status;
    };
}

sub msg {
    my ($file, $line, $msg) = @_;
    my $t = time - $^T;
    my $s = $t % 60;
    my $m = int($t / 60);
    return sprintf(
        "%s%02d:%02d [%s:%d]%s %s\n",
        $COL, $m, $s, $file, $line, $OFF, $msg
        );
}

1;
