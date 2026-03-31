use v5.42;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Crayon::Test qw[ crayon_parse crayon_expr ];

# if
{
    my $ast = crayon_parse('if ($x) { 1 }');
    my $stmt = $ast->{body}{statements}[0];
    is $stmt->{type}, 'Conditional', 'if type';
    is $stmt->{negated}, 0, 'if not negated';
}

# unless
{
    my $ast = crayon_parse('unless ($x) { 1 }');
    my $stmt = $ast->{body}{statements}[0];
    is $stmt->{type}, 'Conditional', 'unless type';
    is $stmt->{negated}, 1, 'unless is negated';
}

# if-elsif-else
{
    my $ast = crayon_parse('if ($a) { 1 } elsif ($b) { 2 } else { 3 }');
    my $stmt = $ast->{body}{statements}[0];
    is $stmt->{type}, 'Conditional', 'if-elsif-else type';
    is scalar $stmt->{elsif_clauses}->@*, 1, 'one elsif';
    ok defined $stmt->{else_block}, 'has else block';
}

# while
{
    my $ast = crayon_parse('while ($x) { 1 }');
    my $stmt = $ast->{body}{statements}[0];
    is $stmt->{type}, 'WhileLoop', 'while type';
    is $stmt->{negated}, 0, 'while not negated';
}

# until
{
    my $ast = crayon_parse('until ($x) { 1 }');
    my $stmt = $ast->{body}{statements}[0];
    is $stmt->{type}, 'WhileLoop', 'until type';
    is $stmt->{negated}, 1, 'until is negated';
}

# foreach
{
    my $ast = crayon_parse('for my $x (1, 2, 3) { say $x }');
    my $stmt = $ast->{body}{statements}[0];
    is $stmt->{type}, 'ForeachLoop', 'foreach type';
    ok defined $stmt->{iterator}, 'has iterator';
}

# C-style for
{
    my $ast = crayon_parse('for (my $i = 0; $i < 3; $i++) { 1 }');
    my $stmt = $ast->{body}{statements}[0];
    is $stmt->{type}, 'CStyleForLoop', 'c-style for type';
}

# postfix if
{
    my $ast = crayon_expr('say "yes" if $x');
    is $ast->{type}, 'ExpressionStatement', 'postfix if wraps in statement';
    is $ast->{modifier}{keyword}, 'if', 'postfix keyword';
}

# postfix unless
{
    my $ast = crayon_expr('say "yes" unless $x');
    is $ast->{modifier}{keyword}, 'unless', 'postfix unless';
}

# last/next
{
    my $ast = crayon_expr('last');
    is $ast->{type}, 'LoopControl', 'last type';
    is $ast->{keyword}, 'last', 'last keyword';
}

{
    my $ast = crayon_expr('next');
    is $ast->{type}, 'LoopControl', 'next type';
    is $ast->{keyword}, 'next', 'next keyword';
}

# return
{
    my $ast = crayon_expr('return 42');
    is $ast->{type}, 'LoopControl', 'return type';
    is $ast->{keyword}, 'return', 'return keyword';
    is $ast->{expression}{type}, 'Integer', 'return value';
}

done_testing;
