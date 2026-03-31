use v5.42;
use utf8;
use Test2::V0;
use lib 'lib', 't/lib';
use Crayon::Test qw[ crayon_eval crayon_output ];

is crayon_eval('my $x = 42; $x'), 42, 'scalar declaration and access';
is crayon_eval('my $x = 10; my $y = 20; $x + $y'), 30, 'two variables';
is crayon_eval('my $x = 10; $x += 5; $x'), 15, 'compound assignment +=';
is crayon_eval('my $x = "hello"; $x .= " world"; $x'), 'hello world', '.=';
is crayon_eval('my $x = 1; { my $x = 2; } $x'), 1, 'lexical scoping';
ok !defined crayon_eval('my $x; $x'), 'uninitialized is undef';

done_testing;
