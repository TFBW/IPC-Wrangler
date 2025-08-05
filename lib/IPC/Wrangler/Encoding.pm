use IPC::Wrangler::Policy;

package IPC::Wrangler::Encoding;

use Exporter qw(import);
use IPC::Wrangler::JSON qw(decode_json encode_json_ascii encode_json_ascii_canonical);
use MIME::Base64 qw(decode_base64url encode_base64url);
use Scalar::Util qw(blessed);

=head1 NAME

IPC::Wrangler::Encoding - Simple encoding/decoding for IPC::Wrangler

=head1 SYNOPSIS

    use IPC::Wrangler::Encoding qw(decode encode encode_canonical);
    $string = encode(@data);
    $string = encode_canonical(@data);
    @data = decode($string);

=head1 DESCRIPTION

This module provides decode and encode functions suitable to
serialising request and response parameters over most transports.
Transports are at liberty to choose their own encoding methods, but
these ones are convenient in a broad range of contexts.

The basic details of the encode/decode pattern are as follows.

=over 4

=item List to ASCII string

The data to be encoded is a list; it is encoded into an ASCII string,
limited to the printable characters and tab.

=item Supported types

The list can contain plain strings (including Unicode), undef, and any
references which convert to JSON.  Arbitrary byte-strings are allowed.
Printable ASCII strings not starting with "~" are transported as-is.
Numbers are transported as strings.  Arbitrary objects are supported
if they implement a TO_IPC_DATA method which returns a supported type.

=item Encoded data

The encoded data is restricted to printable ASCII with tab separators
if there is more than one value.  The empty list encodes to the empty
string; everything else produces a non-empty string.

=back

The list elements which can't be transmitted as-is are encoded as
follows.  The initial tilde indicates a special encoding.

  Empty string   => "~"
  Byte string    => "~".base64url($bytes)
  is_utf8 string => "~@".base64url(encode_utf8($string))
  JSONable ref   => "~%".encode_json_ascii($ref)
  undef          => "~?"

The JSON encoding is optimised for ASCII content but will handle
Unicode.  Hash encoding is potentially nondeterministic; use the
encode_canonical() function if deterministic output is required.

=head1 FUNCTIONS

The following functions are available for import.

=cut

our @EXPORT_OK = qw(decode encode encode_canonical);

=head2 decode

    @list = decode($string);

Decodes the $string back to a @list of values.  If the string contains
improper encoding then there are no guarantees as to the result and
exceptions are possible.

=cut

sub decode {
    my $x;
    return map(
        $_ eq '~'  ? '' :
        $_ eq '~?' ? undef :
        /^~%(.*)/  ? decode_json($1) :
        /^~\@(.*)/ ? do { utf8::decode($x = decode_base64url($1)); $x } :
        /^~(.*)/   ? decode_base64url($1) : $_,
        split(/\t/, $_[0], -1)
        );
}

=head2 encode

    $string = encode(@list);

Encodes the @list of values to a $string.  If the @list contains any
items which can't be encoded then there are no guarantees as to the
result and exceptions are possible.

=cut

sub encode {
    my $x;
    return join(
        "\t", map(
            !defined($_)      ? '~?' :
            ref($_)           ? '~%'.encode_json_ascii($_) :
            $_ eq ''          ? '~' :
            utf8::is_utf8($_) ? do { utf8::encode($x = $_); '~@'.encode_base64url($x) } :
            /^~|[^\x20-\x7E]/ ? '~'.encode_base64url($_)  : $_,
            map(blessed($_) ? $_->TO_IPC_DATA : $_, @_)
        ));
}

=head2 encode_canonical

    $string = encode_canonical(@list);

Encodes the @list of values to a $string with assurance that the same
@list always produces the same $string.  If the @list contains any
items which can't be encoded then there are no guarantees as to the
result and exceptions are possible.

=cut

sub encode_canonical {
    my $x;
    return join(
        "\t", map(
            !defined($_)      ? '~?' :
            ref($_)           ? '~%'.encode_json_ascii_canonical($_) :
            $_ eq ''          ? '~' :
            utf8::is_utf8($_) ? do { utf8::encode($x = $_); '~@'.encode_base64url($x) } :
            /^~|[^\x20-\x7E]/ ? '~'.encode_base64url($_)  : $_,
            map(blessed($_) ? $_->TO_IPC_DATA : $_, @_)
        ));
}

1;
