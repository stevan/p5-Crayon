use v5.42;
use utf8;
use Test2::V0;
use lib 'lib', 't/lib';
use Crayon::Test qw[ crayon_parse ];

# Basic class
{
    my $ast = crayon_parse('class Point { }');
    my $stmt = $ast->{body}{statements}[0];
    is $stmt->{type}, 'ClassDeclaration', 'class type';
    is $stmt->{name}, 'Point', 'class name';
    ok defined $stmt->{body}, 'has body';
}

# Class with :isa
{
    my $ast = crayon_parse('class Dog :isa(Animal) { }');
    my $stmt = $ast->{body}{statements}[0];
    is $stmt->{type}, 'ClassDeclaration', 'class with :isa';
    ok $stmt->{attributes}, 'has attributes';
    is $stmt->{attributes}[0]{name}, 'isa', ':isa attribute';
}

# Role
{
    my $ast = crayon_parse('role Printable { }');
    my $stmt = $ast->{body}{statements}[0];
    is $stmt->{type}, 'RoleDeclaration', 'role type';
    is $stmt->{name}, 'Printable', 'role name';
}

# Method
{
    my $ast = crayon_parse('class Foo { method bar ($x) { $x } }');
    my $class = $ast->{body}{statements}[0];
    my $method = $class->{body}{statements}{statements}[0];
    is $method->{type}, 'MethodDeclaration', 'method type';
    is $method->{name}, 'bar', 'method name';
    ok $method->{signature}, 'has signature';
}

# Lexical method (my method)
{
    my $ast = crayon_parse('class Foo { my method secret () { 1 } }');
    my $class = $ast->{body}{statements}[0];
    my $method = $class->{body}{statements}{statements}[0];
    is $method->{type}, 'MethodDeclaration', 'my method type';
    is $method->{declarator}, 'my', 'lexical declarator';
}

# Field with attributes
{
    my $ast = crayon_parse('class Foo { field $x :param :reader; }');
    my $class = $ast->{body}{statements}[0];
    my $field = $class->{body}{statements}{statements}[0]{expression};
    is $field->{type}, 'FieldDeclaration', 'field type';
    is $field->{variable}{name}, 'x', 'field name';
    ok $field->{attributes}, 'field has attributes';
}

# Method call
{
    my $ast = crayon_parse('$obj->method(42);');
    my $stmt = $ast->{body}{statements}[0];
    my $call = $stmt->{expression};
    is $call->{type}, 'MethodCall', 'method call type';
    is $call->{method}, 'method', 'method name';
}

# ADJUST phaser
{
    my $ast = crayon_parse('class Foo { ADJUST { 1 } }');
    my $class = $ast->{body}{statements}[0];
    my $adjust = $class->{body}{statements}{statements}[0];
    is $adjust->{name}, 'ADJUST', 'ADJUST phaser';
}

done_testing;
