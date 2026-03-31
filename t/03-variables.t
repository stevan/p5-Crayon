use v5.42;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Crayon::Test qw[ crayon_expr ];

# Scalar variable
{
    my $ast = crayon_expr('$x');
    is $ast->{type}, 'Variable', 'scalar type';
    is $ast->{sigil}, '$', 'scalar sigil';
    is $ast->{name}, 'x', 'scalar name';
}

# Array variable
{
    my $ast = crayon_expr('@items');
    is $ast->{type}, 'Variable', 'array type';
    is $ast->{sigil}, '@', 'array sigil';
    is $ast->{name}, 'items', 'array name';
}

# Hash variable
{
    my $ast = crayon_expr('%lookup');
    is $ast->{type}, 'Variable', 'hash type';
    is $ast->{sigil}, '%', 'hash sigil';
}

# Variable declaration
{
    my $ast = crayon_expr('my $x');
    is $ast->{type}, 'VariableDeclaration', 'var decl type';
    is $ast->{declarator}, 'my', 'declarator';
    is $ast->{variables}[0]{sigil}, '$', 'declared var sigil';
    is $ast->{variables}[0]{name}, 'x', 'declared var name';
}

# Assignment with declaration
{
    my $ast = crayon_expr('my $x = 42');
    is $ast->{type}, 'Assignment', 'decl assignment type';
    is $ast->{operator}, '=', 'assignment op';
    is $ast->{target}{type}, 'VariableDeclaration', 'target is declaration';
    is $ast->{value}{type}, 'Integer', 'value is integer';
}

# Compound assignment
{
    my $ast = crayon_expr('$x += 5');
    is $ast->{type}, 'Assignment', 'compound assignment type';
    is $ast->{operator}, '+=', 'compound operator';
}

# Array subscript
{
    my $ast = crayon_expr('$a[0]');
    is $ast->{type}, 'Subscript', 'array subscript type';
    is $ast->{kind}, 'array', 'subscript kind';
}

# Hash subscript
{
    my $ast = crayon_expr('$h{"key"}');
    is $ast->{type}, 'Subscript', 'hash subscript type';
    is $ast->{kind}, 'hash', 'subscript kind';
}

done_testing;
