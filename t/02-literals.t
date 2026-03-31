use v5.42;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Crayon::Test qw[ crayon_expr ];

# Integer
{
    my $ast = crayon_expr('42');
    is $ast->{type}, 'Integer', 'integer type';
    is $ast->{value}, '42', 'integer value';
}

# Hex integer
{
    my $ast = crayon_expr('0xFF');
    is $ast->{type}, 'Integer', 'hex integer type';
    is $ast->{value}, '0xFF', 'hex integer value preserved';
}

# Float
{
    my $ast = crayon_expr('3.14');
    is $ast->{type}, 'Float', 'float type';
    is $ast->{value}, '3.14', 'float value';
}

# Single-quoted string
{
    my $ast = crayon_expr("'hello'");
    is $ast->{type}, 'String', 'single-quoted string type';
    is $ast->{interpolate}, 0, 'single-quoted does not interpolate';
}

# Double-quoted string
{
    my $ast = crayon_expr('"world"');
    is $ast->{type}, 'String', 'double-quoted string type';
    is $ast->{interpolate}, 1, 'double-quoted interpolates';
}

# Bool
{
    my $ast = crayon_expr('true');
    is $ast->{type}, 'Bool', 'true type';
    is $ast->{value}, 1, 'true value';
}
{
    my $ast = crayon_expr('false');
    is $ast->{type}, 'Bool', 'false type';
    is $ast->{value}, 0, 'false value';
}

# undef
{
    my $ast = crayon_expr('undef');
    is $ast->{type}, 'Undef', 'undef type';
}

# Yada
{
    my $ast = crayon_expr('...');
    is $ast->{type}, 'Yada', 'yada type';
}

done_testing;
