package IPC::Wrangler::Policy;

use strict;
use warnings;
use utf8;
use feature ':5.14'; # package BLOCK syntax
use if $ENV{DEBUG} => 'IPC::Wrangler::Debug';

=head1 NAME

IPC::Wrangler::Policy - Project pragma policy package

=head1 SYNOPSIS

    use IPC::Wrangler::Policy;

=head1 DESCRIPTION

This module contains common pragmas for the project, reflecting coding
policies.  The first line of code in all packages and scripts should
be C<< use IPC::Wrangler::Policy; >>, replacing the usual pragmas.

=cut

sub import {
    import strict;
    import warnings;
    import utf8;
    import feature ':5.14';
    IPC::Wrangler::Debug->import
        if exists &IPC::Wrangler::Debug::import;
}

1;
