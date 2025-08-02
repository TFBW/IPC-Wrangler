package IPC::Wrangler::Message;

use IPC::Wrangler::Policy;
use Exporter qw(import);
use MIME::Base64 qw(decode_base64url encode_base64url);

our @EXPORT_OK = qw(BAD GOOD UGLY decode encode try);

sub BAD  { '-'.encode($_[0]) }

sub GOOD { '+'.encode(@_) }

sub UGLY { '!'.encode($_[0]) }

sub decode {
    my $x;
    return map(
        $_ eq '~'  ? '' :
        /^~\@(.*)/ ? do { utf8::decode($x = decode_base64url($1)); $x } :
        /^~(.*)/   ? decode_base64url($1) : $_,
        split(/\t/, $_[0], -1)
        );
}

sub encode {
    my $x;
    return join(
        "\t", map(
            $_ eq ''          ? '~' :
            utf8::is_utf8($_) ? do { utf8::encode($x = $_); '~@'.encode_base64url($x) } :
            /[^\x20-\x7D]/    ? '~'.encode_base64url($_)  : $_,
            @_
        ));
}

sub try {
    my $code = shift // '';
    return UGLY("Attempt to try() non-code '$code'")
        unless ref($code) eq 'CODE';
    my $result = eval { $code->(@_) };
    if (my $ex = $@) { chomp $ex; return UGLY("Exception: $ex") }
    return UGLY("Invalid result (undef)")
        unless defined $result;
    return $result =~ /^[-+!]/ ? $result : UGLY("Invalid result ('$result')");
}

1;
