package Crayon::AST;
use v5.42;
use utf8;

use Exporter 'import';

our @EXPORT_OK = qw[
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

## Program structure

sub Program ($body) {
    +{ type => 'Program', body => $body }
}

sub StatementSequence ($statements) {
    +{ type => 'StatementSequence', statements => $statements }
}

sub ExpressionStatement ($expression, $modifier = undef) {
    +{ type => 'ExpressionStatement', expression => $expression, modifier => $modifier }
}

sub PostfixModifier ($keyword, $expression) {
    +{ type => 'PostfixModifier', keyword => $keyword, expression => $expression }
}

sub Block ($statements) {
    +{ type => 'Block', statements => $statements }
}

## Compound statements

sub Conditional ($condition, $negated, $then_block, $elsif_clauses, $else_block) {
    +{
        type          => 'Conditional',
        condition     => $condition,
        negated       => $negated,
        then_block    => $then_block,
        elsif_clauses => $elsif_clauses,
        else_block    => $else_block,
    }
}

sub ElsifClause ($condition, $block) {
    +{ type => 'ElsifClause', condition => $condition, block => $block }
}

sub WhileLoop ($condition, $negated, $block, $continue_block = undef) {
    +{
        type           => 'WhileLoop',
        condition      => $condition,
        negated        => $negated,
        block          => $block,
        continue_block => $continue_block,
    }
}

sub ForeachLoop ($iterator, $list, $block, $continue_block = undef) {
    +{
        type           => 'ForeachLoop',
        iterator       => $iterator,
        list           => $list,
        block          => $block,
        continue_block => $continue_block,
    }
}

sub CStyleForLoop ($init, $condition, $increment, $block) {
    +{
        type      => 'CStyleForLoop',
        init      => $init,
        condition => $condition,
        increment => $increment,
        block     => $block,
    }
}

sub TryCatch ($try_block, $catch_var, $catch_block, $finally_block = undef) {
    +{
        type          => 'TryCatch',
        try_block     => $try_block,
        catch_var     => $catch_var,
        catch_block   => $catch_block,
        finally_block => $finally_block,
    }
}

sub GivenWhen ($keyword, $expression, $block) {
    +{ type => 'GivenWhen', keyword => $keyword, expression => $expression, block => $block }
}

sub Defer ($block) {
    +{ type => 'Defer', block => $block }
}

## Declarations

sub UseDeclaration ($keyword, $module, $version, $imports) {
    +{
        type    => 'UseDeclaration',
        keyword => $keyword,
        module  => $module,
        version => $version,
        imports => $imports,
    }
}

sub VariableDeclaration ($declarator, $variables, $attributes = undef) {
    +{
        type       => 'VariableDeclaration',
        declarator => $declarator,
        variables  => $variables,
        attributes => $attributes,
    }
}

sub SubroutineDeclaration ($declarator, $name, $prototype, $attributes, $signature, $body) {
    +{
        type       => 'SubroutineDeclaration',
        declarator => $declarator,
        name       => $name,
        prototype  => $prototype,
        attributes => $attributes,
        signature  => $signature,
        body       => $body,
    }
}

sub MethodDeclaration ($declarator, $name, $attributes, $signature, $body) {
    +{
        type       => 'MethodDeclaration',
        declarator => $declarator,
        name       => $name,
        attributes => $attributes,
        signature  => $signature,
        body       => $body,
    }
}

sub ClassDeclaration ($name, $version, $attributes, $body) {
    +{
        type       => 'ClassDeclaration',
        name       => $name,
        version    => $version,
        attributes => $attributes,
        body       => $body,
    }
}

sub RoleDeclaration ($name, $version, $attributes, $body) {
    +{
        type       => 'RoleDeclaration',
        name       => $name,
        version    => $version,
        attributes => $attributes,
        body       => $body,
    }
}

sub FieldDeclaration ($variable, $attributes, $default) {
    +{
        type       => 'FieldDeclaration',
        variable   => $variable,
        attributes => $attributes,
        default    => $default,
    }
}

sub PackageDeclaration ($name, $version, $body) {
    +{ type => 'PackageDeclaration', name => $name, version => $version, body => $body }
}

sub Signature ($params) {
    +{ type => 'Signature', params => $params }
}

sub ScalarParam ($name, $default, $named) {
    +{ type => 'ScalarParam', name => $name, default => $default, named => $named }
}

sub SlurpyParam ($sigil, $name) {
    +{ type => 'SlurpyParam', sigil => $sigil, name => $name }
}

sub Attribute ($name, $expression = undef) {
    +{ type => 'Attribute', name => $name, expression => $expression }
}

## Literals

sub Integer ($value) {
    +{ type => 'Integer', value => $value }
}

sub Float ($value) {
    +{ type => 'Float', value => $value }
}

sub String ($value, $interpolate) {
    +{ type => 'String', value => $value, interpolate => $interpolate }
}

sub Bool ($value) {
    +{ type => 'Bool', value => $value }
}

sub Undef () {
    +{ type => 'Undef' }
}

sub SpecialLiteral ($kind) {
    +{ type => 'SpecialLiteral', kind => $kind }
}

sub Regex ($pattern, $replacement, $flags, $kind) {
    +{
        type        => 'Regex',
        pattern     => $pattern,
        replacement => $replacement,
        flags       => $flags,
        kind        => $kind,
    }
}

sub QuotedWords ($words) {
    +{ type => 'QuotedWords', words => $words }
}

sub Version ($value) {
    +{ type => 'Version', value => $value }
}

## Expressions

sub Variable ($sigil, $name, $namespace) {
    +{ type => 'Variable', sigil => $sigil, name => $name, namespace => $namespace }
}

sub BinaryOp ($operator, $left, $right) {
    +{ type => 'BinaryOp', operator => $operator, left => $left, right => $right }
}

sub UnaryOp ($operator, $operand) {
    +{ type => 'UnaryOp', operator => $operator, operand => $operand }
}

sub PostfixOp ($operator, $operand) {
    +{ type => 'PostfixOp', operator => $operator, operand => $operand }
}

sub Ternary ($condition, $then_expr, $else_expr) {
    +{
        type      => 'Ternary',
        condition => $condition,
        then_expr => $then_expr,
        else_expr => $else_expr,
    }
}

sub Assignment ($operator, $target, $value) {
    +{ type => 'Assignment', operator => $operator, target => $target, value => $value }
}

sub Call ($name, $namespace, $args, $block, $sigiled) {
    +{
        type      => 'Call',
        name      => $name,
        namespace => $namespace,
        args      => $args,
        block     => $block,
        sigiled   => $sigiled,
    }
}

sub MethodCall ($invocant, $method, $args, $sigiled) {
    +{
        type     => 'MethodCall',
        invocant => $invocant,
        method   => $method,
        args     => $args,
        sigiled  => $sigiled,
    }
}

sub Subscript ($target, $index, $kind, $arrow) {
    +{ type => 'Subscript', target => $target, index => $index, kind => $kind, arrow => $arrow }
}

sub Dereference ($target, $sigil) {
    +{ type => 'Dereference', target => $target, sigil => $sigil }
}

sub PostfixSlice ($target, $sigil, $index, $kind) {
    +{ type => 'PostfixSlice', target => $target, sigil => $sigil, index => $index, kind => $kind }
}

sub ArrayRef ($elements) {
    +{ type => 'ArrayRef', elements => $elements }
}

sub HashRef ($elements) {
    +{ type => 'HashRef', elements => $elements }
}

sub AnonymousSub ($signature, $prototype, $attributes, $body, $kind) {
    +{
        type       => 'AnonymousSub',
        signature  => $signature,
        prototype  => $prototype,
        attributes => $attributes,
        body       => $body,
        kind       => $kind,
    }
}

sub DoExpression ($kind, $operand) {
    +{ type => 'DoExpression', kind => $kind, operand => $operand }
}

sub ParenExpression ($expression) {
    +{ type => 'ParenExpression', expression => $expression }
}

sub ExpressionList ($expressions, $trailing_comma = 0) {
    +{ type => 'ExpressionList', expressions => $expressions, trailing_comma => $trailing_comma }
}

sub LoopControl ($keyword, $label, $expression) {
    +{ type => 'LoopControl', keyword => $keyword, label => $label, expression => $expression }
}

sub Yada () {
    +{ type => 'Yada' }
}

1;
