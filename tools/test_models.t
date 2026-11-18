#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use JSON::PP qw(decode_json);
my $c = dirname(dirname(abs_path(__FILE__)));
my $work = tempdir(CLEANUP => 1);
my $cc = $ENV{CC} || 'cc';
is(system($cc, '-std=c99', '-O2', '-Wall', '-Wextra', '-Werror',
          "-I$c/local", "$c/local/CarverRichards.c",
          "$c/local/tests/carver-richards/test_carver_richards.c", '-lm',
          '-o', "$work/carver-richards"), 0, 'model and independent reference compile');
SKIP: {
    skip 'compile failed', 1 unless -x "$work/carver-richards";
    is(system("$work/carver-richards"), 0, 'corrected model matches Bloch-McConnell propagation and limits');
}
open my $fh, '<', "$c/META-C.json" or die $!;
my $meta=decode_json(do { local $/; <$fh> });
for my $name (qw(R2_CR T2_CR R2_CR_pb)) {
    ok(exists $meta->{$name}, "$name is discoverable in catalog");
    is($meta->{$name}{source}, 'C/local/CarverRichards.c', "$name source");
}
done_testing;
