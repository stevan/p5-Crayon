use v5.42;
use utf8;
use Test2::V0;
use lib 'lib', 't/lib';
use Crayon::Test qw[ crayon_eval ];

# Arithmetic
is crayon_eval('2 + 3'), 5, 'addition';
is crayon_eval('10 - 4'), 6, 'subtraction';
is crayon_eval('3 * 7'), 21, 'multiplication';
is crayon_eval('15 / 3'), 5, 'division';
is crayon_eval('17 % 5'), 2, 'modulo';
is crayon_eval('2 ** 10'), 1024, 'exponentiation';

# String
is crayon_eval('"hello" . " " . "world"'), 'hello world', 'concatenation';
is crayon_eval('"ab" x 3'), 'ababab', 'repetition';

# Comparison
ok crayon_eval('1 == 1'), '== true';
ok !crayon_eval('1 == 2'), '== false';
is crayon_eval('5 <=> 3'), 1, 'spaceship positive';

# Logical
is crayon_eval('1 && 2'), 2, '&& truthy';
is crayon_eval('0 || 3'), 3, '|| falsy lhs';
is crayon_eval('undef // 42'), 42, 'defined-or';
ok !crayon_eval('not 1'), 'not';

# Unary
is crayon_eval('-5'), -5, 'unary minus';
is crayon_eval('!0'), 1, 'logical not';
is crayon_eval('my $x = 5; ++$x'), 6, 'prefix increment';
is crayon_eval('my $x = 5; $x++; $x'), 6, 'postfix increment';

# Ternary
is crayon_eval('1 ? "yes" : "no"'), 'yes', 'ternary true';
is crayon_eval('0 ? "yes" : "no"'), 'no', 'ternary false';

# Precedence
is crayon_eval('2 + 3 * 4'), 14, 'mul before add';
is crayon_eval('(2 + 3) * 4'), 20, 'parens override';

done_testing;
