use IPC::Wrangler::Policy;
use open ':std', ':encoding(utf8)';
use IPC::Wrangler::Message qw(encode decode BAD GOOD UGLY try);
use Test::More;

# Test data sets
my @plain = (
    'hello',
    'user@example.com',
    'key=value&other=123',
    join('', map(chr($_), (32..125))), # full printable ASCII range bar tilde
    );

my @binary = (
    '',                                # empty string (special case)
    "\t",                              # tab (delimiter)
    "~",                               # tilde (marker)
    "\x00",                            # null
    "\x1F",                            # unit separator
    "\x7F",                            # DEL
    "before\tafter",                   # embedded tab
    "foo~bar",                         # embedded tilde
    "\x00\x01\x02",                    # multi-byte binary
    join('', map(chr($_), (0..255))),  # full single-byte range
    );

my @wide = (
    "通信",
    "связь",
    "κοινωνία",
    "🚀",
    "¯\\_(ツ)_/¯",
    "🤠 IPC::Wrangler",
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

subtest "Mixed list round-trip" => sub {
    my @all_strings = (@plain, @binary, @wide);
    my @decoded = decode(encode(@all_strings));
    is_deeply(\@decoded, \@all_strings, "All string types round-trip together");
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

subtest "Status functions" => sub {
    my $good = GOOD('data1', 'data2');
    like($good, qr/^\+/, "GOOD starts with +");
    
    my $bad = BAD('error message');
    like($bad, qr/^-/, "BAD starts with -");
    
    my $ugly = UGLY('exception details');
    like($ugly, qr/^!/, "UGLY starts with !");
    
    # Test decoding status messages
    my @good_decoded = decode(substr($good, 1));
    is_deeply(\@good_decoded, ['data1', 'data2'], "GOOD data decoded");
    
    my @bad_decoded = decode(substr($bad, 1));
    is_deeply(\@bad_decoded, ['error message'], "BAD message decoded");
    
    my @ugly_decoded = decode(substr($ugly, 1));
    is_deeply(\@ugly_decoded, ['exception details'], "UGLY message decoded");
};

subtest "try() function" => sub {
    # Successful case
    my $result = try(sub { GOOD('success') });
    like($result, qr/^\+/, "try() with successful code returns GOOD");
    
    # Exception case
    $result = try(sub { die "test error" });
    like($result, qr/^!/, "try() with exception returns UGLY");
    like($result, qr/test error/, "try() includes exception message");
    
    # Invalid return case
    $result = try(sub { "invalid" });
    like($result, qr/^!/, "try() with invalid return gives UGLY");
    
    # Undef return case
    $result = try(sub { return undef });
    like($result, qr/^!/, "try() with undef return gives UGLY");
    
    # Non-code case
    $result = try("not code");
    like($result, qr/^!/, "try() with non-code gives UGLY");
};

done_testing();
