use v5.42;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Crayon::Test qw[ crayon_expr ];

# Binary ops
{
    my $ast = crayon_expr('2 + 3');
    is $ast->{type}, 'BinaryOp', 'binary op type';
    is $ast->{operator}, '+', 'operator';
    is $ast->{left}{type}, 'Integer', 'left operand';
    is $ast->{right}{type}, 'Integer', 'right operand';
}

# String concat
{
    my $ast = crayon_expr('"a" . "b"');
    is $ast->{type}, 'BinaryOp', 'concat type';
    is $ast->{operator}, '.', 'concat op';
}

# Comparison
{
    my $ast = crayon_expr('1 == 2');
    is $ast->{type}, 'BinaryOp', 'equality type';
    is $ast->{operator}, '==', 'equality op';
}

# String comparison
{
    my $ast = crayon_expr('"a" eq "b"');
    is $ast->{type}, 'BinaryOp', 'string eq type';
    is $ast->{operator}, 'eq', 'eq op';
}

# Logical
{
    my $ast = crayon_expr('$x && $y');
    is $ast->{type}, 'BinaryOp', 'logical and type';
    is $ast->{operator}, '&&', '&& op';
}

{
    my $ast = crayon_expr('$x // $y');
    is $ast->{operator}, '//', 'defined-or op';
}

# Low-prec logical
{
    my $ast = crayon_expr('$x and $y');
    is $ast->{type}, 'BinaryOp', 'low-prec and type';
    is $ast->{operator}, 'and', 'and op';
}

# Unary
{
    my $ast = crayon_expr('-$x');
    is $ast->{type}, 'UnaryOp', 'unary type';
    is $ast->{operator}, '-', 'unary minus';
}

{
    my $ast = crayon_expr('!$x');
    is $ast->{type}, 'UnaryOp', 'logical not type';
    is $ast->{operator}, '!', 'not op';
}

# Prefix increment
{
    my $ast = crayon_expr('++$x');
    is $ast->{type}, 'UnaryOp', 'preinc type';
    is $ast->{operator}, '++', 'preinc op';
}

# Postfix increment
{
    my $ast = crayon_expr('$x++');
    is $ast->{type}, 'PostfixOp', 'postinc type';
    is $ast->{operator}, '++', 'postinc op';
}

# Ternary
{
    my $ast = crayon_expr('$x ? 1 : 0');
    is $ast->{type}, 'Ternary', 'ternary type';
    is $ast->{then_expr}{type}, 'Integer', 'then branch';
    is $ast->{else_expr}{type}, 'Integer', 'else branch';
}

# Precedence — tree-sitter nests correctly
{
    my $ast = crayon_expr('2 + 3 * 4');
    is $ast->{type}, 'BinaryOp', 'outer is add';
    is $ast->{operator}, '+', 'outer op is +';
    is $ast->{right}{type}, 'BinaryOp', 'right is mul';
    is $ast->{right}{operator}, '*', 'right op is *';
}

done_testing;
