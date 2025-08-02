package IPC::Wrangler::Policy;

use strict;
use warnings;
use utf8;
use feature ':5.12';

=head1 NAME

IPC::Wrangler::Policy - Project pragma policy package

=head1 SYNOPSIS

    use IPC::Wrangler::Policy;

=head1 DESCRIPTION

This module contains common pragmas for the project, reflecting coding
policies.  Replace standard pragma boilerplate with this.

=cut

#binmode(STDIN,  ':utf8');
#binmode(STDOUT, ':utf8');

sub import {
    import strict;
    import warnings;
    import utf8;
    import feature ':5.12';
}

1;
