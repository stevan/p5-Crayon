use v5.42;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Crayon::Transform;
use Crayon::Parser;

sub transform_expr ($source) {
    my ($tree, $src) = Crayon::Parser::parse($source . ';');
    my $ast = Crayon::Transform::transform($tree->root_node, $src);
    # Program -> StatementSequence -> first statement
    my $stmt = $ast->{body}{statements}[0];
    # ExpressionStatement -> expression
    return $stmt->{expression} if $stmt->{type} eq 'ExpressionStatement';
    return $stmt;
}

# Integer
{
    my $ast = transform_expr('42');
    is $ast->{type}, 'Integer', 'integer type';
    is $ast->{value}, '42', 'integer value';
}

# Hex integer
{
    my $ast = transform_expr('0xFF');
    is $ast->{type}, 'Integer', 'hex integer type';
    is $ast->{value}, '0xFF', 'hex integer value preserved';
}

# Float
{
    my $ast = transform_expr('3.14');
    is $ast->{type}, 'Float', 'float type';
    is $ast->{value}, '3.14', 'float value';
}

# Single-quoted string
{
    my $ast = transform_expr("'hello'");
    is $ast->{type}, 'String', 'single-quoted string type';
    is $ast->{interpolate}, 0, 'single-quoted does not interpolate';
}

# Double-quoted string
{
    my $ast = transform_expr('"world"');
    is $ast->{type}, 'String', 'double-quoted string type';
    is $ast->{interpolate}, 1, 'double-quoted interpolates';
}

# Bool true
{
    my $ast = transform_expr('true');
    is $ast->{type}, 'Bool', 'true type';
    is $ast->{value}, 1, 'true value';
}

# Bool false
{
    my $ast = transform_expr('false');
    is $ast->{type}, 'Bool', 'false type';
    is $ast->{value}, 0, 'false value';
}

# undef
{
    my $ast = transform_expr('undef');
    is $ast->{type}, 'Undef', 'undef type';
}

# Yada
{
    my $ast = transform_expr('...');
    is $ast->{type}, 'Yada', 'yada type';
}

done_testing;
