use IPC::Wrangler::Policy;
use open ':std', ':encoding(utf8)';
use IPC::Wrangler::Message qw(encode decode BAD GOOD UGLY try);
use Test::More;

subtest "Basic encode/decode round-trip" => sub {
    my @test_cases = (
        # Simple ASCII
        ['hello'],
        ['hello', 'world'],
        [''],  # empty string
        ['', 'middle', ''],  # empty strings mixed in
        
        # ASCII with special chars in safe range
        ['user@example.com'],
        ['file.txt'],
        ['key=value&other=123'],
        
        # Edge cases for encoding threshold
        [' '],          # space (0x20)
        ['}'],          # right brace (0x7D)
        [chr(0x20)],    # explicit space
        [chr(0x7D)],    # explicit right brace
        );
    
    for my $case (@test_cases) {
        my $encoded = encode(@$case);
        my @decoded = decode($encoded);
        is_deeply(\@decoded, $case, 
                  "Round-trip: " . join(', ', map {"'$_'"} @$case));
    }
};

subtest "Characters that require encoding" => sub {
    my @encode_cases = (
        # Tab (your delimiter)
        ["\t"],
        ["before\tafter"],

        # Tilde (your encoding marker)
        ["~"],
        ["~test"],

        # Non-printable ASCII
        ["\x00"],          # null
        ["\x01"],          # control char
        ["\x1F"],          # unit separator
        ["\x7F"],          # DEL
        ["\xFF"],          # high byte

        # Multi-byte sequences
        ["\x00\x01\x02"],
        ["mix\x00ed"],
        );

    for my $case (@encode_cases) {
        my $encoded = encode(@$case);
        my @decoded = decode($encoded);
        is_deeply(\@decoded, $case,
                  "Encode required: " . join(', ', map {sprintf("'%v02x'", $_)} @$case));

        # Verify encoded form contains base64 marker
        like($encoded, qr/~/, "Encoded form has base64 marker");
    }
};

subtest "UTF-8 handling" => sub {
    # UTF-8 strings should get special ~@ encoding
    my @utf8_cases = (
        "café",
        "北京",
        "🚀",
        "Ñoño",
        "αβγ",
        );

    for my $str (@utf8_cases) {
        utf8::decode($str) unless utf8::is_utf8($str);  # ensure UTF-8 flag

        my $encoded = encode($str);
        my @decoded = decode($encoded);

        is_deeply(\@decoded, [$str], "UTF-8 round-trip: '$str'");
        like($encoded, qr/~\@/, "UTF-8 gets ~@ encoding");
        ok(utf8::is_utf8($decoded[0]), "Decoded result has UTF-8 flag");
    }
};

subtest "Mixed data types" => sub {
    my @mixed = (
        'simple',
        "\x00binary\xFF",
        "utf8_café",
        '',
        'normal_string',
        "\ttab_delimited",
    );

    # Mark the UTF-8 string
    utf8::decode($mixed[2]);

    my $encoded = encode(@mixed);
    my @decoded = decode($encoded);

    is_deeply(\@decoded, \@mixed, "Mixed data types round-trip");
};

subtest "Status functions" => sub {
    my $good = GOOD('data1', 'data2');
    like($good, qr/^\+/, "GOOD starts with +");
    
    my $bad = BAD('error message');
    like($bad, qr/^-/, "BAD starts with -");

    my $ugly = UGLY('exception details');
    like($ugly, qr/^!/, "UGLY starts with !");

    # Test decoding status messages
    my @good_decoded = decode(substr($good, 1));  # strip status char
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

subtest "Edge cases and error conditions" => sub {
    # Empty encode
    my $encoded = encode();
    my @decoded = decode($encoded);
    is_deeply(\@decoded, [], "Empty encode/decode");

    # Single empty string
    $encoded = encode('');
    @decoded = decode($encoded);
    is_deeply(\@decoded, [''], "Single empty string");

    # Multiple empty strings
    $encoded = encode('', '', '');
    @decoded = decode($encoded);
    is_deeply(\@decoded, ['', '', ''], "Multiple empty strings");
};

subtest "No unnecessary encoding" => sub {
    my $simple = join('', map(chr($_), (32..125)));
    my $encoded = encode($simple);
    unlike($encoded, qr/~/, "Simple string not base64 encoded");
    is($encoded, $simple, "Simple string passed through unchanged");
};

subtest "Delimiter handling" => sub {
    # String containing tabs should be encoded
    my $with_tab = "before\tafter";
    my $encoded = encode($with_tab);
    like($encoded, qr/~/, "String with tab gets encoded");

    my @decoded = decode($encoded);
    is_deeply(\@decoded, [$with_tab], "Tab-containing string round-trips");
};

done_testing();
