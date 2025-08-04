use IPC::Wrangler::Policy;
use open ':std', ':encoding(utf8)';
use IPC::Wrangler::Encoding qw(decode encode encode_canonical);
use Test::More;

# Test data sets
my @plain = (
    'hello world',
    'user@example.com',
    'key=value&other=123',
    "foo~bar",
    join('', map(chr($_), (32..126))), # full printable ASCII range
    );

my @binary = (
    "\t",                              # tab (delimiter)
    "~foo",                            # leading tilde (marker)
    "\x00",                            # null
    "\x1F",                            # unit separator
    "\x7F",                            # DEL
    "before\tafter",                   # embedded tab
    "\x00\x01\x02",                    # multi-byte binary
    join('', map(chr($_), (0..255))),  # full single-byte range
    );

my @wide = (
    "通信",
    "связь",
    "κοινωνία",
    "🛜",
    "¯\\_(ツ)_/¯",
    "🤠 IPC::Wrangler",
    );

my @special = (
    '',
    undef,
    [qw(x y z)],
    );

subtest "Plain strings (no encoding)" => sub {
    for my $str (@plain) {
        my $encoded = encode($str);
        is($encoded, $str, "Plain string passed through unchanged: '$str'");
        my @decoded = decode($encoded);
        is_deeply(\@decoded, [$str], "Plain string round-trip: '$str'");
    }
};

subtest "Binary strings (base64 encoding)" => sub {
    for my $str (@binary) {
        my $encoded = encode($str);
        like($encoded, qr/^~[A-Za-z0-9_-]*$/, "Binary string gets ~ encoding: " . sprintf("'%v02x'", $str));
        my @decoded = decode($encoded);
        is_deeply(\@decoded, [$str], "Binary string round-trip: " . sprintf("'%v02x'", $str));
    }
};

subtest "Wide strings (UTF-8 encoding)" => sub {
    for my $str (@wide) {
        my $encoded = encode($str);
        like($encoded, qr/^~@[A-Za-z0-9_-]+$/, "Wide string gets ~@ encoding: '$str'");
        my @decoded = decode($encoded);
        is_deeply(\@decoded, [$str], "Wide string round-trip: '$str'");
    }
};

subtest "Other encodings" => sub {
    for my $data (@special) {
        my $encoded = encode($data);
        like($encoded, qr/^~/, "Special value gets ~ encoding: $encoded");
        my @decoded = decode($encoded);
        is_deeply(\@decoded, [$data], "Special value round-trip: $encoded");
    }
};

subtest "Mixed list round-trip" => sub {
    my @all_strings = (@plain, @binary, @wide, @special);
    my @decoded = decode(encode(@all_strings));
    is_deeply(\@decoded, \@all_strings, "All string types round-trip together");
};

subtest "Canonical JSON" => sub {
    my $data = {
        plain   => \@plain,
        binary  => \@binary,
        wide    => \@wide,
        special => \@special,
    };
    my $encoded = encode_canonical($data);
    is(encode_canonical($data), $encoded, "Both encodings match");
    my ($decoded) = decode($encoded);
    is_deeply($decoded, $data, "Hash round-trip");
};

subtest "List count handling" => sub {
    # Test every combination of these strings!
    my @str = ('', 'foo', '~', '🤠');
    my $nstr = @str;
    for my $len (0..3) {
        for my $i (1 .. $nstr**$len) {
            my $x = $i - 1;
            my @orig;
            while (@orig < $len) {
                my $y = $x % $nstr;
                push @orig, $str[$y];
                $x -= $y;
                $x /= $nstr;
            }
            my $desc = '('.join(', ', map("'$_'", @orig)).')';
            my @decoded = decode(encode(@orig));
            is_deeply(\@decoded, \@orig, "List $desc round-trip");
        }
    }
};

done_testing();
