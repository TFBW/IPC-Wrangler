package IPC::Wrangler::JSON;

use IPC::Wrangler::Policy;
use Exporter qw(import);
use JSON::MaybeXS qw(JSON decode_json);

=head1 NAME

IPC::Wrangler::JSON - JSON encoding/decoding for IPC::Wrangler

=head1 SYNOPSIS

    use IPC::Wrangler::JSON qw(
        encode_json_ascii
        encode_json_ascii_canonical
        decode_json
        );
    $json = encode_json_ascii({ foo => 'bar', café => 'value' });
    # Returns {"foo":"bar","caf\u00e9":"value"} or similar
    $json = encode_json_ascii_canonical({ foo => 'bar', café => 'value' });
    # Returns {"caf\u00e9":"value","foo":"bar"} exactly
    $data = decode_json($json);

=head1 DESCRIPTION

This module provides a thin wrapper around JSON::MaybeXS configured
for IPC::Wrangler's needs.

=head1 FUNCTIONS

The following functions are available for import.

=cut

our @EXPORT_OK = qw(
    decode_json
    encode_json_ascii
    encode_json_ascii_canonical
    );
my $JSON = JSON;

=head2 decode_json

    $data = decode_json($json);

Decodes JSON text back to Perl data structures.

=head2 encode_json_ascii

    $json = encode_json_ascii($data);

Encodes a Perl data structure to ASCII-only JSON.  Non-ASCII
characters are escaped as \uXXXX sequences.

=cut

my $ASCII;
sub encode_json_ascii {
    return ($ASCII //= $JSON->new->ascii(1))->encode(@_);
}

=head2 encode_json_ascii_canonical

    $json = encode_json_ascii_canonical($data);

Encodes a Perl data structure to ASCII-only JSON with hash keys (if
any) sorted to ensure a deterministic outcome.  Non-ASCII characters
are escaped as \uXXXX sequences.

=cut

my $ASCII_CANON;
sub encode_json_ascii_canonical {
    return ($ASCII_CANON //= $JSON->new->ascii(1)->canonical(1))->encode(@_);
}

1;
