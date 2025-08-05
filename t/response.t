use IPC::Wrangler::Policy;

use open ':std', ':encoding(utf8)';
use IPC::Wrangler::Response qw(GOOD BAD UGLY try);
use Test::More;

subtest "Factory functions" => sub {
    my $good = GOOD('result', 42, [1,2,3]);
    isa_ok($good, 'IPC::Wrangler::Response::good');
    ok($good->DOES('IPC::Wrangler::Response'));
    
    my $bad = BAD('something failed', 'code=ENOENT', 'retry=false');
    isa_ok($bad, 'IPC::Wrangler::Response::bad');
    ok($bad->DOES('IPC::Wrangler::Response'));
    
    my $ugly = UGLY('system crashed', 'errno=ENOMEM');
    isa_ok($ugly, 'IPC::Wrangler::Response::ugly');
    ok($ugly->DOES('IPC::Wrangler::Response'));
};

subtest "Type checking methods" => sub {
    my $good = GOOD('data');
    my $bad = BAD('error');
    my $ugly = UGLY('crash');
    
    ok($good->is_good && !$good->is_bad && !$good->is_ugly, "GOOD type checks");
    ok(!$bad->is_good && $bad->is_bad && !$bad->is_ugly, "BAD type checks");
    ok(!$ugly->is_good && !$ugly->is_bad && $ugly->is_ugly, "UGLY type checks");
};

subtest "reason method" => sub {
    is(GOOD('data')->reason, '', "GOOD has empty reason");
    is(BAD('failed')->reason, 'failed', "BAD returns reason");
    is(BAD('failed', 'code1', 'code2')->reason, 'failed', "BAD reason ignores codes");
    is(UGLY('crashed')->reason, 'crashed', "UGLY returns reason");
    is(UGLY('crashed', 'errno=5')->reason, 'crashed', "UGLY reason ignores codes");
};

subtest "codes method" => sub {
    is_deeply([GOOD('data')->codes], [], "GOOD has no codes");
    is_deeply([BAD('failed')->codes], [], "BAD with no codes");
    is_deeply([BAD('failed', 'code1')->codes], ['code1'], "BAD with one code");
    is_deeply([BAD('failed', 'code1', 'code2')->codes], ['code1', 'code2'], "BAD with multiple codes");
    is_deeply([UGLY('crashed', 'errno=5', 'signal=SEGV')->codes], ['errno=5', 'signal=SEGV'], "UGLY with codes");
};

subtest "result method" => sub {
    # GOOD results
    my @result = GOOD('single')->result;
    is_deeply(\@result, ['single'], "GOOD result in list context");
    
    my $scalar = GOOD('single')->result;
    is($scalar, 'single', "GOOD result in scalar context");
    
    @result = GOOD('multiple', 'values', 42)->result;
    is_deeply(\@result, ['multiple', 'values', 42], "GOOD multiple results");
    
    $scalar = GOOD('first', 'second')->result;
    is($scalar, 'first', "GOOD scalar gets first result");
    
    @result = GOOD()->result;
    is_deeply(\@result, [], "GOOD empty result");
    
    # BAD/UGLY should die
    eval { BAD('failed')->result };
    like($@, qr/\[BAD\] failed/, "BAD result dies with reason");
    
    eval { UGLY('crashed')->result };
    like($@, qr/\[UGLY\] crashed/, "UGLY result dies with reason");
};

subtest "on_gbu method" => sub {
    my $good = GOOD('data');
    my $bad = BAD('failed');
    my $ugly = UGLY('crashed');
    
    # Scalar values
    is($good->on_gbu('ok', 'err', 'crash'), 'ok', "GOOD selects first value");
    is($bad->on_gbu('ok', 'err', 'crash'), 'err', "BAD selects second value");
    is($ugly->on_gbu('ok', 'err', 'crash'), 'crash', "UGLY selects third value");
    
    # CODE references
    my $good_called = 0;
    my $bad_called = 0;
    my $ugly_called = 0;
    
    my $result = $good->on_gbu(
        sub { $good_called++; 'good-result' },
        sub { $bad_called++; 'bad-result' },
        sub { $ugly_called++; 'ugly-result' }
    );
    is($result, 'good-result', "GOOD calls first CODE");
    is($good_called, 1, "GOOD CODE was called");
    is($bad_called + $ugly_called, 0, "Other CODEs not called");
    
    $result = $bad->on_gbu(
        sub { $good_called++; 'good-result' },
        sub { $bad_called++; 'bad-result' },
        sub { $ugly_called++; 'ugly-result' }
    );
    is($result, 'bad-result', "BAD calls second CODE");
    is($bad_called, 1, "BAD CODE was called");
    
    $result = $ugly->on_gbu(
        sub { $good_called++; 'good-result' },
        sub { $bad_called++; 'bad-result' },
        sub { $ugly_called++; 'ugly-result' }
    );
    is($result, 'ugly-result', "UGLY calls third CODE");
    is($ugly_called, 1, "UGLY CODE was called");
    
    # Mixed scalar and CODE
    is($good->on_gbu('literal', sub { 'computed' }, 'other'), 'literal', "GOOD prefers scalar over CODE");
    is($bad->on_gbu('literal', sub { 'computed' }, 'other'), 'computed', "BAD calls CODE when provided");
};

subtest "try function - success cases" => sub {
    # Simple success
    my $response = try sub { 'hello' };
    isa_ok($response, 'IPC::Wrangler::Response::good');
    is($response->result, 'hello', "try wraps simple return in GOOD");
    
    # Multiple returns
    $response = try sub { ('a', 'b', 'c') };
    is_deeply([$response->result], ['a', 'b', 'c'], "try handles multiple returns");
    
    # With arguments
    $response = try sub { my ($x, $y) = @_; $x + $y }, 5, 7;
    is($response->result, 12, "try passes arguments correctly");
    
    # Empty return
    $response = try sub { return; };
    is_deeply([$response->result], [], "try handles empty return");
};

subtest "try function - response passthrough" => sub {
    # Returning GOOD directly
    my $response = try sub { GOOD('direct') };
    isa_ok($response, 'IPC::Wrangler::Response::good');
    is($response->result, 'direct', "try passes through GOOD response");
    
    # Returning BAD directly  
    $response = try sub { BAD('failed', 'code=ERR') };
    isa_ok($response, 'IPC::Wrangler::Response::bad');
    is($response->reason, 'failed', "try passes through BAD response");
    is_deeply([$response->codes], ['code=ERR'], "BAD codes preserved");
    
    # Returning UGLY directly
    $response = try sub { UGLY('crashed') };
    isa_ok($response, 'IPC::Wrangler::Response::ugly');
    is($response->reason, 'crashed', "try passes through UGLY response");
    
    # Multiple returns where first is response - should wrap in GOOD
    $response = try sub { (GOOD('first'), 'second') };
    isa_ok($response, 'IPC::Wrangler::Response::good');
    is_deeply([$response->result], [GOOD('first'), 'second'], "try wraps multiple returns even if first is response");
};

subtest "try function - exception handling" => sub {
    # Simple exception
    my $response = try sub { die "something bad\n" };
    isa_ok($response, 'IPC::Wrangler::Response::ugly');
    is($response->reason, 'Exception: something bad', "try catches exceptions as UGLY");
    
    # Exception with chomp needed
    $response = try sub { die "with newline\n" };
    is($response->reason, 'Exception: with newline', "try chomps exception message");
    
    # Exception in argument processing
    $response = try sub { my $x = $_[0]; die "arg was $x" }, "test";
    like($response->reason, qr/Exception:.*arg was test/, "try handles exceptions with arguments");
};

subtest "try function - invalid code parameter" => sub {
    # Non-code reference
    for ("scalar", [], undef) {
        my $response = try($_);
        isa_ok($response, 'IPC::Wrangler::Response::ugly');
        like($response->reason, qr/^BUG:/, "try rejects non-code");
    }
};

subtest "DOES method" => sub {
    my $good = GOOD();
    my $bad = BAD('err');
    my $ugly = UGLY('crash');
    
    ok($good->DOES('IPC::Wrangler::Response'), "GOOD DOES Response");
    ok($bad->DOES('IPC::Wrangler::Response'), "BAD DOES Response");  
    ok($ugly->DOES('IPC::Wrangler::Response'), "UGLY DOES Response");
};

subtest "Edge cases and data types" => sub {
    # Unicode in reasons/codes
    my $response = BAD('ошибка', 'код=ошибка');
    is($response->reason, 'ошибка', "Unicode reason preserved");
    is_deeply([$response->codes], ['код=ошибка'], "Unicode codes preserved");
    
    # Binary data
    my $binary = "\x00\x01\x02\xFF";
    $response = GOOD($binary);
    is($response->result, $binary, "Binary data in GOOD result");
    
    # References
    my $hashref = { key => 'value', nested => [1, 2, 3] };
    $response = GOOD($hashref);
    is_deeply($response->result, $hashref, "Complex references preserved");
    
    # undef values
    $response = GOOD(undef, 'after');
    is_deeply([$response->result], [undef, 'after'], "undef values preserved");
    
    # Empty strings
    $response = BAD('', 'code=EMPTY');
    is($response->reason, '', "Empty reason string allowed");
};

subtest "Realistic usage patterns" => sub {
    # File operation simulation
    my $simulate_file_read = sub {
        my ($filename) = @_;
        return BAD("File not found", "errno=ENOENT") if $filename eq 'missing.txt';
        return UGLY("Permission denied", "errno=EACCES") if $filename eq 'forbidden.txt'; 
        return GOOD("file contents here");
    };
    
    my $response = try($simulate_file_read, 'data.txt');
    ok($response->is_good, "Successful file read");
    is($response->result, "file contents here", "File contents returned");
    
    $response = try($simulate_file_read, 'missing.txt');
    ok($response->is_bad, "Missing file is BAD");
    is($response->reason, "File not found", "Appropriate error message");
    
    $response = try($simulate_file_read, 'forbidden.txt');
    ok($response->is_ugly, "Permission error is UGLY");
    
    # Network operation with on_gbu
    my $result = $response->on_gbu(
        "Success!",
        "Client error - check your request",
        "Server error - try again later"
    );
    is($result, "Server error - try again later", "UGLY gets appropriate message");
};

done_testing();
