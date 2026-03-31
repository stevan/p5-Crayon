use v5.42;
use utf8;
use Test2::V0;
use lib 'lib', 't/lib';
use Crayon::Test qw[ crayon_parse crayon_expr ];

# try/catch
{
    my $ast = crayon_parse('try { 1 } catch ($e) { 2 }');
    my $stmt = $ast->{body}{statements}[0];
    is $stmt->{type}, 'TryCatch', 'try/catch type';
    ok defined $stmt->{try_block}, 'has try block';
    ok defined $stmt->{catch_block}, 'has catch block';
    is $stmt->{catch_var}{name}, 'e', 'catch variable';
}

# defer
{
    my $ast = crayon_parse('defer { 1 }');
    my $stmt = $ast->{body}{statements}[0];
    is $stmt->{type}, 'Defer', 'defer type';
}

# array ref
{
    my $ast = crayon_expr('[1, 2, 3]');
    is $ast->{type}, 'ArrayRef', 'array ref type';
    ok $ast->{elements}, 'has elements';
}

# hash ref (+ is parsed as unary op wrapping the hash ref)
{
    my $ast = crayon_expr('+{a => 1}');
    is $ast->{type}, 'UnaryOp', 'hash ref wrapped in unary +';
    is $ast->{operand}{type}, 'HashRef', 'hash ref type';
}

# regex
{
    my $ast = crayon_expr('/foo/i');
    is $ast->{type}, 'Regex', 'regex type';
    is $ast->{kind}, 'm', 'match kind';
}

# qr//
{
    my $ast = crayon_expr('qr/bar/');
    is $ast->{type}, 'Regex', 'qr type';
    is $ast->{kind}, 'qr', 'qr kind';
}

# s///
{
    my $ast = crayon_expr('s/foo/bar/g');
    is $ast->{type}, 'Regex', 'substitution type';
    is $ast->{kind}, 's', 's kind';
}

# postfix deref
{
    my $ast = crayon_expr('$ref->@*');
    is $ast->{type}, 'Dereference', 'array deref type';
    is $ast->{sigil}, '@', 'deref sigil';
}

# use
{
    my $ast = crayon_parse('use Foo::Bar;');
    my $stmt = $ast->{body}{statements}[0];
    is $stmt->{type}, 'UseDeclaration', 'use type';
    is $stmt->{keyword}, 'use', 'use keyword';
    like $stmt->{module}, qr/Foo::Bar/, 'module name';
}

# use version
{
    my $ast = crayon_parse('use v5.42;');
    my $stmt = $ast->{body}{statements}[0];
    is $stmt->{type}, 'UseDeclaration', 'use version type';
}

# package
{
    my $ast = crayon_parse('package Foo;');
    my $stmt = $ast->{body}{statements}[0];
    is $stmt->{type}, 'PackageDeclaration', 'package type';
    like $stmt->{name}, qr/Foo/, 'package name';
}

# do block
{
    my $ast = crayon_expr('do { 1 }');
    is $ast->{type}, 'DoExpression', 'do block type';
    is $ast->{kind}, 'block', 'do kind';
}

# sub reference
{
    my $ast = crayon_expr('\&Foo::bar');
    is $ast->{type}, 'UnaryOp', 'sub ref is unary op';
    is $ast->{operator}, '\\', 'ref operator';
    is $ast->{operand}{type}, 'Variable', 'operand is variable';
    is $ast->{operand}{sigil}, '&', 'sigil is &';
    is $ast->{operand}{name}, 'bar', 'function name';
    is $ast->{operand}{namespace}, 'Foo', 'function namespace';
}

# indirect object (block-first call)
{
    my $ast = crayon_expr('List::Util::reduce { $a + $b } @foo');
    is $ast->{type}, 'Call', 'reduce is Call';
    is $ast->{name}, 'reduce', 'function name';
    is $ast->{namespace}, 'List::Util', 'namespace';
    ok $ast->{block}, 'has block arg';
    is $ast->{block}{type}, 'Block', 'block arg is Block';
}

# array slice
{
    my $ast = crayon_expr('@a[0, 1, 2]');
    is $ast->{type}, 'Subscript', 'slice type';
    is $ast->{kind}, 'array', 'slice kind';
    is $ast->{target}{sigil}, '@', 'slice target sigil';
}

# array length
{
    my $ast = crayon_expr('$#array');
    is $ast->{type}, 'Variable', '$# type';
    is $ast->{sigil}, '$#', '$# sigil';
    is $ast->{name}, 'array', '$# name';
}

done_testing;
