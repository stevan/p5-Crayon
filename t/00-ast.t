# t/00-ast.t
use v5.42;
use utf8;
use Test2::V0;

use lib 'lib';
use Crayon::AST qw[
    Program StatementSequence ExpressionStatement PostfixModifier Block
    Integer Float String Bool Undef SpecialLiteral Regex QuotedWords Version
    Variable BinaryOp UnaryOp PostfixOp Ternary Assignment
    Call MethodCall Subscript Dereference PostfixSlice
    ArrayRef HashRef AnonymousSub DoExpression ParenExpression ExpressionList
    LoopControl Yada
    Conditional ElsifClause WhileLoop ForeachLoop CStyleForLoop
    TryCatch GivenWhen Defer
    UseDeclaration VariableDeclaration SubroutineDeclaration MethodDeclaration
    ClassDeclaration RoleDeclaration FieldDeclaration PackageDeclaration
    Signature ScalarParam SlurpyParam Attribute
];

# Program structure
{
    my $node = Integer('42');
    is $node, +{ type => 'Integer', value => '42' }, 'Integer constructor';
}

{
    my $node = String('hello', 0);
    is $node, +{ type => 'String', value => 'hello', interpolate => 0 },
        'String constructor';
}

{
    my $node = Variable('$', 'x', undef);
    is $node, +{ type => 'Variable', sigil => '$', name => 'x', namespace => undef },
        'Variable constructor';
}

{
    my $node = BinaryOp('+', Integer('1'), Integer('2'));
    is $node->{type}, 'BinaryOp', 'BinaryOp type';
    is $node->{operator}, '+', 'BinaryOp operator';
    is $node->{left}{value}, '1', 'BinaryOp left';
    is $node->{right}{value}, '2', 'BinaryOp right';
}

{
    my $node = Bool(1);
    is $node, +{ type => 'Bool', value => 1 }, 'Bool constructor';
}

{
    my $stmts = StatementSequence([Integer('1'), Integer('2')]);
    is scalar $stmts->{statements}->@*, 2, 'StatementSequence has 2 statements';
}

{
    my $cond = Conditional(
        Variable('$', 'x', undef), 0,
        Block(StatementSequence([Integer('1')])),
        [],
        undef,
    );
    is $cond->{type}, 'Conditional', 'Conditional type';
    is $cond->{negated}, 0, 'Conditional not negated';
}

{
    my $sub_node = SubroutineDeclaration(
        undef, 'foo', undef, undef,
        Signature([ScalarParam('x', undef, 0)]),
        Block(StatementSequence([])),
    );
    is $sub_node->{type}, 'SubroutineDeclaration', 'SubroutineDeclaration type';
    is $sub_node->{name}, 'foo', 'SubroutineDeclaration name';
    is $sub_node->{signature}{params}[0]{name}, 'x', 'Signature param name';
}

{
    my $class = ClassDeclaration('Point', undef, undef,
        Block(StatementSequence([])),
    );
    is $class->{type}, 'ClassDeclaration', 'ClassDeclaration type';
    is $class->{name}, 'Point', 'ClassDeclaration name';
}

{
    my $role = RoleDeclaration('Printable', undef, undef, undef);
    is $role->{type}, 'RoleDeclaration', 'RoleDeclaration type';
}

done_testing;
