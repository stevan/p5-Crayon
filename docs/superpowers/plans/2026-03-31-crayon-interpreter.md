# Crayon Interpreter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a tree-walking interpreter for a Perl 5.42 subset, using tree-sitter-perl for parsing and a custom CST→AST transform layer.

**Architecture:** Perl source → tree-sitter-perl (CST) → recursive transform (AST) → tree-walking evaluator. The AST uses simple hashrefs with constructor functions. The interpreter maintains a runtime scope chain for variable resolution.

**Tech Stack:** Perl 5.42, Text::TreeSitter (CPAN, XS bindings), tree-sitter-perl grammar, Test2::V0, Capture::Tiny

**Spec:** `docs/superpowers/specs/2026-03-31-chalk-ast-design.md`

---

## File Structure

```
lib/Crayon.pm                    # Main entry point: parse + transform + eval
lib/Crayon/AST.pm                # Node constructor functions (all 52 types)
lib/Crayon/Parser.pm             # Text::TreeSitter wrapper
lib/Crayon/Transform.pm          # CST→AST recursive walk
lib/Crayon/Interpreter.pm        # Tree-walking evaluator
lib/Crayon/Environment.pm        # Lexical scope chain (frames)
bin/crayon                       # CLI entry point
t/lib/Crayon/Test.pm             # Test helpers (crayon_eval, crayon_output)
t/00-ast.t                       # AST constructor tests
t/01-parser.t                    # tree-sitter parsing smoke test
t/02-literals.t                  # Literal values end-to-end
t/03-variables.t                 # Variable declaration + access
t/04-operators.t                 # Binary, unary, postfix, ternary
t/05-control-flow.t              # if/unless/while/for/foreach/loop control
t/06-subroutines.t               # Sub declaration, call, closures, signatures
t/07-classes.t                   # Class, method, field, constructor
t/08-roles.t                     # Role declaration and composition
cpanfile                         # CPAN dependencies
share/build-grammar.sh           # Script to build tree-sitter-perl .dylib/.so
```

---

### Task 1: Project Setup

**Files:**
- Create: `cpanfile`
- Create: `share/build-grammar.sh`
- Create: `.gitignore`

- [ ] **Step 1: Create cpanfile**

```perl
requires 'perl', 'v5.42.0';
requires 'Text::TreeSitter';

on 'test' => sub {
    requires 'Test2::V0';
    requires 'Capture::Tiny';
};
```

- [ ] **Step 2: Create the grammar build script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Build tree-sitter-perl grammar for use with Text::TreeSitter
#
# Prerequisites:
#   - C compiler (cc)
#   - libtree-sitter installed (brew install tree-sitter)
#   - git

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRAMMAR_DIR="$SCRIPT_DIR/tree-sitter-perl"
OUTPUT="$SCRIPT_DIR/perl.dylib"

# Adjust extension for Linux
if [[ "$(uname)" == "Linux" ]]; then
    OUTPUT="$SCRIPT_DIR/perl.so"
fi

if [[ ! -d "$GRAMMAR_DIR" ]]; then
    echo "Cloning tree-sitter-perl..."
    git clone --depth 1 https://github.com/tree-sitter-perl/tree-sitter-perl.git "$GRAMMAR_DIR"
fi

echo "Building grammar..."
cc -shared -fPIC -o "$OUTPUT" \
    -I"$GRAMMAR_DIR/src" \
    "$GRAMMAR_DIR/src/parser.c" \
    "$GRAMMAR_DIR/src/scanner.c"

echo "Built: $OUTPUT"
```

- [ ] **Step 3: Create .gitignore**

```
share/tree-sitter-perl/
share/perl.dylib
share/perl.so
```

- [ ] **Step 4: Create directory structure**

Run:
```bash
mkdir -p lib/Crayon t/lib/Crayon bin share
```

- [ ] **Step 5: Install dependencies and build grammar**

Run:
```bash
cpanm --installdeps .
chmod +x share/build-grammar.sh
./share/build-grammar.sh
```

Expected: Grammar compiles successfully, `share/perl.dylib` (or `share/perl.so`) exists.

- [ ] **Step 6: Commit**

```bash
git init
git add cpanfile share/build-grammar.sh .gitignore
git commit -m "feat: project setup with dependencies and grammar build script"
```

---

### Task 2: AST Node Module

**Files:**
- Create: `lib/Crayon/AST.pm`
- Create: `t/00-ast.t`

- [ ] **Step 1: Write the failing test**

```perl
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
    my $sub = SubroutineDeclaration(
        undef, 'foo', undef, undef,
        Signature([ScalarParam('x', undef, 0)]),
        Block(StatementSequence([])),
    );
    is $sub->{type}, 'SubroutineDeclaration', 'SubroutineDeclaration type';
    is $sub->{name}, 'foo', 'SubroutineDeclaration name';
    is $sub->{signature}{params}[0]{name}, 'x', 'Signature param name';
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib t/00-ast.t`
Expected: FAIL — `Can't locate Crayon/AST.pm`

- [ ] **Step 3: Write the AST module**

```perl
# lib/Crayon/AST.pm
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

# -- Program structure --

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

# -- Compound statements --

sub Conditional ($condition, $negated, $then_block, $elsif_clauses, $else_block) {
    +{  type           => 'Conditional',
        condition      => $condition,
        negated        => $negated,
        then_block     => $then_block,
        elsif_clauses  => $elsif_clauses,
        else_block     => $else_block,
    }
}

sub ElsifClause ($condition, $block) {
    +{ type => 'ElsifClause', condition => $condition, block => $block }
}

sub WhileLoop ($condition, $negated, $block, $continue_block = undef) {
    +{  type            => 'WhileLoop',
        condition       => $condition,
        negated         => $negated,
        block           => $block,
        continue_block  => $continue_block,
    }
}

sub ForeachLoop ($iterator, $list, $block, $continue_block = undef) {
    +{  type            => 'ForeachLoop',
        iterator        => $iterator,
        list            => $list,
        block           => $block,
        continue_block  => $continue_block,
    }
}

sub CStyleForLoop ($init, $condition, $increment, $block) {
    +{  type       => 'CStyleForLoop',
        init       => $init,
        condition  => $condition,
        increment  => $increment,
        block      => $block,
    }
}

sub TryCatch ($try_block, $catch_var, $catch_block, $finally_block = undef) {
    +{  type           => 'TryCatch',
        try_block      => $try_block,
        catch_var      => $catch_var,
        catch_block    => $catch_block,
        finally_block  => $finally_block,
    }
}

sub GivenWhen ($keyword, $expression, $block) {
    +{ type => 'GivenWhen', keyword => $keyword, expression => $expression, block => $block }
}

sub Defer ($block) {
    +{ type => 'Defer', block => $block }
}

# -- Declarations --

sub UseDeclaration ($keyword, $module, $version, $imports) {
    +{  type     => 'UseDeclaration',
        keyword  => $keyword,
        module   => $module,
        version  => $version,
        imports  => $imports,
    }
}

sub VariableDeclaration ($declarator, $variables, $attributes = undef) {
    +{  type        => 'VariableDeclaration',
        declarator  => $declarator,
        variables   => $variables,
        attributes  => $attributes,
    }
}

sub SubroutineDeclaration ($declarator, $name, $prototype, $attributes, $signature, $body) {
    +{  type        => 'SubroutineDeclaration',
        declarator  => $declarator,
        name        => $name,
        prototype   => $prototype,
        attributes  => $attributes,
        signature   => $signature,
        body        => $body,
    }
}

sub MethodDeclaration ($declarator, $name, $attributes, $signature, $body) {
    +{  type        => 'MethodDeclaration',
        declarator  => $declarator,
        name        => $name,
        attributes  => $attributes,
        signature   => $signature,
        body        => $body,
    }
}

sub ClassDeclaration ($name, $version, $attributes, $body) {
    +{  type        => 'ClassDeclaration',
        name        => $name,
        version     => $version,
        attributes  => $attributes,
        body        => $body,
    }
}

sub RoleDeclaration ($name, $version, $attributes, $body) {
    +{  type        => 'RoleDeclaration',
        name        => $name,
        version     => $version,
        attributes  => $attributes,
        body        => $body,
    }
}

sub FieldDeclaration ($variable, $attributes, $default) {
    +{  type        => 'FieldDeclaration',
        variable    => $variable,
        attributes  => $attributes,
        default     => $default,
    }
}

sub PackageDeclaration ($name, $version, $body) {
    +{  type     => 'PackageDeclaration',
        name     => $name,
        version  => $version,
        body     => $body,
    }
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

# -- Expressions: Literals --

sub Integer ($value) {
    +{ type => 'Integer', value => $value }
}

sub Float ($value) {
    +{ type => 'Float', value => $value }
}

sub String ($value, $interpolate) {
    +{ type => 'String', value => $value, interpolate => $interpolate }
}

sub Regex ($pattern, $replacement, $flags, $kind) {
    +{  type         => 'Regex',
        pattern      => $pattern,
        replacement  => $replacement,
        flags        => $flags,
        kind         => $kind,
    }
}

sub QuotedWords ($words) {
    +{ type => 'QuotedWords', words => $words }
}

sub Version ($value) {
    +{ type => 'Version', value => $value }
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

# -- Expressions: Core --

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
    +{  type       => 'Ternary',
        condition  => $condition,
        then_expr  => $then_expr,
        else_expr  => $else_expr,
    }
}

sub Assignment ($operator, $target, $value) {
    +{ type => 'Assignment', operator => $operator, target => $target, value => $value }
}

sub Call ($name, $namespace, $args, $block, $sigiled) {
    +{  type       => 'Call',
        name       => $name,
        namespace  => $namespace,
        args       => $args,
        block      => $block,
        sigiled    => $sigiled,
    }
}

sub MethodCall ($invocant, $method, $args, $sigiled) {
    +{  type      => 'MethodCall',
        invocant  => $invocant,
        method    => $method,
        args      => $args,
        sigiled   => $sigiled,
    }
}

sub Subscript ($target, $index, $kind, $arrow) {
    +{  type    => 'Subscript',
        target  => $target,
        index   => $index,
        kind    => $kind,
        arrow   => $arrow,
    }
}

sub Dereference ($target, $sigil) {
    +{ type => 'Dereference', target => $target, sigil => $sigil }
}

sub PostfixSlice ($target, $sigil, $index, $kind) {
    +{  type    => 'PostfixSlice',
        target  => $target,
        sigil   => $sigil,
        index   => $index,
        kind    => $kind,
    }
}

sub ArrayRef ($elements) {
    +{ type => 'ArrayRef', elements => $elements }
}

sub HashRef ($elements) {
    +{ type => 'HashRef', elements => $elements }
}

sub AnonymousSub ($signature, $prototype, $attributes, $body, $kind) {
    +{  type        => 'AnonymousSub',
        signature   => $signature,
        prototype   => $prototype,
        attributes  => $attributes,
        body        => $body,
        kind        => $kind,
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `perl -Ilib t/00-ast.t`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/Crayon/AST.pm t/00-ast.t
git commit -m "feat: AST node constructor module with 52 node types"
```

---

### Task 3: Parser + Test Helpers

**Files:**
- Create: `lib/Crayon/Parser.pm`
- Create: `t/lib/Crayon/Test.pm`
- Create: `t/01-parser.t`

This task integrates Text::TreeSitter and writes a CST exploration test to verify the API and node type names we expect.

- [ ] **Step 1: Write the failing parser test**

```perl
# t/01-parser.t
use v5.42;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Crayon::Parser;

# Smoke test: can we parse Perl source?
{
    my ($tree, $source) = Crayon::Parser::parse('my $x = 42;');
    my $root = $tree->root_node;
    is $root->type, 'source_file', 'root node is source_file';
    ok $root->child_count > 0, 'root has children';
}

# Verify key node types exist in a simple expression
{
    my ($tree, $source) = Crayon::Parser::parse('my $x = 1 + 2;');
    my $root = $tree->root_node;

    # Walk and collect all node types
    my @types;
    my $walk; $walk = sub ($node) {
        push @types, $node->type if $node->is_named;
        for my $i (0 .. $node->child_count - 1) {
            $walk->($node->child($i));
        }
    };
    $walk->($root);

    ok((grep { $_ eq 'variable_declaration' } @types), 'found variable_declaration');
    ok((grep { $_ eq 'binary_expression' } @types),    'found binary_expression');
    ok((grep { $_ eq 'number' } @types),               'found number');
}

# Verify we can access the source text via byte offsets
{
    my $code = 'say "hello";';
    my ($tree, $source) = Crayon::Parser::parse($code);
    my $root = $tree->root_node;
    my $text = Crayon::Parser::node_text($root, $source);
    is $text, $code, 'node_text extracts source text';
}

done_testing;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib -It/lib t/01-parser.t`
Expected: FAIL — `Can't locate Crayon/Parser.pm`

- [ ] **Step 3: Write the Parser module**

```perl
# lib/Crayon/Parser.pm
package Crayon::Parser;
use v5.42;
use utf8;

use Text::TreeSitter;
use Text::TreeSitter::Language;

use File::Basename qw[ dirname ];
use File::Spec;

my $GRAMMAR_PATH;

sub _find_grammar () {
    return $GRAMMAR_PATH if $GRAMMAR_PATH;

    my $share = File::Spec->catdir(dirname(dirname(dirname(__FILE__))), 'share');
    for my $ext (qw[ dylib so ]) {
        my $path = File::Spec->catfile($share, "perl.$ext");
        if (-f $path) {
            $GRAMMAR_PATH = $path;
            return $path;
        }
    }
    die "Cannot find tree-sitter-perl grammar in $share/\n"
      . "Run: ./share/build-grammar.sh\n";
}

my $_parser;

sub _parser () {
    return $_parser if $_parser;

    my $lang = Text::TreeSitter::Language::load(_find_grammar(), 'tree_sitter_perl');

    $_parser = Text::TreeSitter::Parser->new;
    $_parser->set_language($lang);
    return $_parser;
}

sub parse ($source) {
    my $parser = _parser();
    my $tree = $parser->parse_string($source);
    return ($tree, $source);
}

sub node_text ($node, $source) {
    return substr($source, $node->start_byte, $node->end_byte - $node->start_byte);
}

1;
```

**Note:** The exact Text::TreeSitter API (especially `Language::load` and `Parser->new`) may differ slightly from what's shown here. If the test fails with an API mismatch, consult `perldoc Text::TreeSitter::Language` and `perldoc Text::TreeSitter::Parser` and adjust the method calls accordingly. The rest of the plan depends on `parse()` returning `($tree, $source)` and `node_text()` working — those interfaces are stable regardless of the underlying API.

- [ ] **Step 4: Write the test helper module**

```perl
# t/lib/Crayon/Test.pm
package Crayon::Test;
use v5.42;
use utf8;

use Exporter 'import';
use Capture::Tiny qw[ capture_stdout ];

our @EXPORT_OK = qw[ crayon_eval crayon_output crayon_ast ];

sub crayon_eval ($source) {
    require Crayon;
    return Crayon::eval_source($source);
}

sub crayon_output ($source) {
    require Crayon;
    my $output = capture_stdout { Crayon::eval_source($source) };
    return $output;
}

sub crayon_ast ($source) {
    require Crayon;
    return Crayon::parse_to_ast($source);
}

1;
```

- [ ] **Step 5: Run parser test to verify it passes**

Run: `perl -Ilib -It/lib t/01-parser.t`
Expected: All tests pass. If any fail due to Text::TreeSitter API differences, adjust `Crayon::Parser` accordingly.

- [ ] **Step 6: Commit**

```bash
git add lib/Crayon/Parser.pm t/lib/Crayon/Test.pm t/01-parser.t
git commit -m "feat: tree-sitter parser integration and test helpers"
```

---

### Task 4: Transform Foundation + Literals

**Files:**
- Create: `lib/Crayon/Transform.pm`
- Create: `t/02-literals.t`

- [ ] **Step 1: Write the failing test**

```perl
# t/02-literals.t
use v5.42;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Crayon::Transform;
use Crayon::Parser;

sub transform_expr ($source) {
    my ($tree, $src) = Crayon::Parser::parse($source . ';');
    my $ast = Crayon::Transform::transform($tree->root_node, $src);
    # Program -> StatementSequence -> first statement -> ExpressionStatement -> expression
    return $ast->{body}{statements}[0]{expression};
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
    is $ast->{value}, 'hello', 'string value without quotes';
    is $ast->{interpolate}, 0, 'single-quoted does not interpolate';
}

# Double-quoted string
{
    my $ast = transform_expr('"world"');
    is $ast->{type}, 'String', 'double-quoted string type';
    is $ast->{value}, 'world', 'string value';
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib -It/lib t/02-literals.t`
Expected: FAIL — `Can't locate Crayon/Transform.pm`

- [ ] **Step 3: Write the Transform module foundation**

```perl
# lib/Crayon/Transform.pm
package Crayon::Transform;
use v5.42;
use utf8;

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
use Crayon::Parser qw[];

# ---- Helpers ----

sub _text ($node, $source) {
    Crayon::Parser::node_text($node, $source);
}

sub _named_children ($node) {
    my @children;
    for my $i (0 .. $node->child_count - 1) {
        my $child = $node->child($i);
        push @children, $child if $child->is_named;
    }
    return @children;
}

sub _all_children ($node) {
    map { $node->child($_) } 0 .. $node->child_count - 1;
}

sub _child_by_field ($node, $field) {
    $node->child_by_field_name($field);
}

sub _first_anon_keyword ($node, $source) {
    for my $i (0 .. $node->child_count - 1) {
        my $child = $node->child($i);
        if (!$child->is_named) {
            my $text = _text($child, $source);
            return $text if $text =~ /^[a-z]/;
        }
    }
    return undef;
}

# ---- Main entry ----

sub transform ($node, $source) {
    _transform_node($node, $source);
}

sub _transform_node ($node, $source) {
    my $type = $node->type;

    my $method = "_transform_$type";
    $method =~ s/[^a-zA-Z0-9_]/_/g;

    if (my $handler = __PACKAGE__->can($method)) {
        return $handler->($node, $source);
    }

    die "Unsupported CST node type: $type at byte " . $node->start_byte . "\n";
}

# ---- Program structure ----

sub _transform_source_file ($node, $source) {
    my @stmts;
    for my $child (_named_children($node)) {
        push @stmts, _transform_node($child, $source);
    }
    Program(StatementSequence(\@stmts));
}

sub _transform_expression_statement ($node, $source) {
    my @children = _named_children($node);
    my $expr = _transform_node($children[0], $source);
    ExpressionStatement($expr);
}

# ---- Literals ----

sub _transform_number ($node, $source) {
    my $text = _text($node, $source);
    if ($text =~ /[.eE]/ && $text !~ /^0[xXbBoO]/) {
        Float($text);
    } else {
        Integer($text);
    }
}

sub _transform_string_literal ($node, $source) {
    my $text = _text($node, $source);
    # Strip surrounding quotes
    my $value = substr($text, 1, length($text) - 2);
    String($value, 0);
}

sub _transform_interpolated_string_literal ($node, $source) {
    my $text = _text($node, $source);
    my $value = substr($text, 1, length($text) - 2);
    String($value, 1);
}

sub _transform_command_string ($node, $source) {
    my $text = _text($node, $source);
    my $value = substr($text, 1, length($text) - 2);
    String($value, 1);
}

sub _transform_boolean ($node, $source) {
    my $text = _text($node, $source);
    Bool($text eq 'true' ? 1 : 0);
}

sub _transform_undef_expression ($node, $source) {
    Undef();
}

sub _transform_yadayada ($node, $source) {
    Yada();
}

sub _transform_heredoc_token ($node, $source) {
    my $text = _text($node, $source);
    String($text, 1);
}

sub _transform_quoted_word_list ($node, $source) {
    my $text = _text($node, $source);
    # Extract words from qw(...) — strip qw and delimiters
    $text =~ s/^qw\s*[\(\[\{<]//;
    $text =~ s/[\)\]\}>]$//;
    my @words = split /\s+/, $text;
    QuotedWords(\@words);
}

sub _transform_func0op_call_expression ($node, $source) {
    my $text = _text($node, $source);
    if ($text eq '__FILE__') {
        SpecialLiteral('__FILE__');
    } elsif ($text eq '__LINE__') {
        SpecialLiteral('__LINE__');
    } elsif ($text eq '__PACKAGE__') {
        SpecialLiteral('__PACKAGE__');
    } else {
        Call($text, undef, undef, undef, 0);
    }
}

1;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `perl -Ilib -It/lib t/02-literals.t`
Expected: All tests pass. Some tests may fail if tree-sitter-perl uses different node types for certain literals — adjust the `_transform_*` handler names to match.

- [ ] **Step 5: Commit**

```bash
git add lib/Crayon/Transform.pm t/02-literals.t
git commit -m "feat: CST→AST transform with literal support"
```

---

### Task 5: Environment + Interpreter Core + Literals

**Files:**
- Create: `lib/Crayon/Environment.pm`
- Create: `lib/Crayon/Interpreter.pm`
- Create: `lib/Crayon.pm`
- Modify: `t/02-literals.t` (add end-to-end tests)

- [ ] **Step 1: Add end-to-end literal tests to t/02-literals.t**

Append to `t/02-literals.t`:

```perl
use Crayon::Test qw[ crayon_eval crayon_output ];

# End-to-end evaluation
is crayon_eval('42'), 42, 'eval integer';
is crayon_eval('3.14'), 3.14, 'eval float';
is crayon_eval("'hello'"), 'hello', 'eval single-quoted string';
is crayon_eval('"world"'), 'world', 'eval double-quoted string';
is crayon_eval('true'), 1, 'eval true';
is crayon_eval('false'), 0, 'eval false';
ok !defined crayon_eval('undef'), 'eval undef';

# Output
is crayon_output('say 42'), "42\n", 'say integer';
is crayon_output('say "hello"'), "hello\n", 'say string';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib -It/lib t/02-literals.t`
Expected: FAIL — `Can't locate Crayon/Environment.pm` or `Can't locate Crayon.pm`

- [ ] **Step 3: Write the Environment module**

```perl
# lib/Crayon/Environment.pm
package Crayon::Environment;
use v5.42;
use utf8;

use experimental qw[ class ];

class Crayon::Environment {
    field $parent :param = undef;
    field %bindings;

    method define ($name, $value) {
        $bindings{$name} = $value;
        return $value;
    }

    method lookup ($name) {
        if (exists $bindings{$name}) {
            return $bindings{$name};
        }
        if (defined $parent) {
            return $parent->lookup($name);
        }
        die "Undefined variable: $name\n";
    }

    method assign ($name, $value) {
        if (exists $bindings{$name}) {
            $bindings{$name} = $value;
            return $value;
        }
        if (defined $parent) {
            return $parent->assign($name, $value);
        }
        die "Cannot assign to undeclared variable: $name\n";
    }

    method exists ($name) {
        return 1 if exists $bindings{$name};
        return $parent->exists($name) if defined $parent;
        return 0;
    }

    method child () {
        Crayon::Environment->new(parent => $self);
    }
}

1;
```

- [ ] **Step 4: Write the Interpreter module**

```perl
# lib/Crayon/Interpreter.pm
package Crayon::Interpreter;
use v5.42;
use utf8;

use experimental qw[ class ];

use Crayon::Environment;

class Crayon::Interpreter {
    field $env :param = Crayon::Environment->new;

    method eval ($ast) {
        my $type = $ast->{type};
        my $method = "eval_$type";

        if (my $handler = $self->can($method)) {
            return $self->$handler($ast);
        }

        die "Cannot evaluate AST node type: $type\n";
    }

    # -- Program structure --

    method eval_Program ($node) {
        $self->eval($node->{body});
    }

    method eval_StatementSequence ($node) {
        my $result = undef;
        for my $stmt ($node->{statements}->@*) {
            $result = $self->eval($stmt);
        }
        return $result;
    }

    method eval_ExpressionStatement ($node) {
        $self->eval($node->{expression});
    }

    # -- Literals --

    method eval_Integer ($node) {
        my $val = $node->{value};
        # Handle hex, octal, binary
        if ($val =~ /^0[xX]/) {
            return hex($val);
        } elsif ($val =~ /^0[bB]/) {
            return oct($val);
        } elsif ($val =~ /^0[oO]/) {
            return oct($val);
        } elsif ($val =~ /^0[0-7]+$/) {
            return oct($val);
        }
        $val =~ s/_//g;
        return 0 + $val;
    }

    method eval_Float ($node) {
        my $val = $node->{value};
        $val =~ s/_//g;
        return 0.0 + $val;
    }

    method eval_String ($node) {
        my $val = $node->{value};
        if ($node->{interpolate}) {
            # Basic escape processing for now
            $val =~ s/\\n/\n/g;
            $val =~ s/\\t/\t/g;
            $val =~ s/\\\\/\\/g;
            $val =~ s/\\"/"/g;
        }
        return $val;
    }

    method eval_Bool ($node) {
        return $node->{value};
    }

    method eval_Undef ($node) {
        return undef;
    }

    method eval_Yada ($node) {
        die "Unimplemented\n";
    }

    method eval_SpecialLiteral ($node) {
        my $kind = $node->{kind};
        if ($kind eq '__FILE__') {
            return '(eval)';
        } elsif ($kind eq '__LINE__') {
            return 0;
        } elsif ($kind eq '__PACKAGE__') {
            return 'main';
        }
    }

    # -- Builtins (minimal, for say/print) --

    method eval_Call ($node) {
        my $name = $node->{name};
        my @args = map { $self->eval($_) } ($node->{args} // [])->@*;

        if ($name eq 'say') {
            say join('', @args);
            return 1;
        } elsif ($name eq 'print') {
            print join('', @args);
            return 1;
        }

        die "Unknown function: $name\n";
    }
}

1;
```

- [ ] **Step 5: Write the main Crayon entry point**

```perl
# lib/Crayon.pm
package Crayon;
use v5.42;
use utf8;

use Crayon::Parser;
use Crayon::Transform;
use Crayon::Interpreter;

sub eval_source ($source) {
    my $ast = parse_to_ast($source);
    my $interp = Crayon::Interpreter->new;
    return $interp->eval($ast);
}

sub parse_to_ast ($source) {
    my ($tree, $src) = Crayon::Parser::parse($source);
    return Crayon::Transform::transform($tree->root_node, $src);
}

1;
```

- [ ] **Step 6: Add say/print call transform support**

Add to `lib/Crayon/Transform.pm`:

```perl
sub _transform_ambiguous_function_call_expression ($node, $source) {
    my $func_node = _child_by_field($node, 'function');
    my $name = _text($func_node, $source);

    my @args;
    for my $child (_named_children($node)) {
        next if _text($child, $source) eq $name;
        push @args, _transform_node($child, $source);
    }

    Call($name, undef, \@args, undef, 0);
}

sub _transform_function_call_expression ($node, $source) {
    my $func_node = _child_by_field($node, 'function');
    my $name = _text($func_node, $source);
    my $args_node = _child_by_field($node, 'arguments');

    my @args;
    if ($args_node) {
        for my $child (_named_children($args_node)) {
            push @args, _transform_node($child, $source);
        }
    }

    Call($name, undef, \@args, undef, 0);
}

sub _transform_func1op_call_expression ($node, $source) {
    my @children = _named_children($node);
    my $func_node = _child_by_field($node, 'function') // $children[0];
    my $name = _text($func_node, $source);

    my @args;
    for my $child (@children) {
        my $text = _text($child, $source);
        next if $text eq $name;
        push @args, _transform_node($child, $source);
    }

    Call($name, undef, \@args, undef, 0);
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `perl -Ilib -It/lib t/02-literals.t`
Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib/Crayon.pm lib/Crayon/Environment.pm lib/Crayon/Interpreter.pm lib/Crayon/Transform.pm t/02-literals.t
git commit -m "feat: interpreter core with environment and literal evaluation"
```

---

### Task 6: Variables + Assignment

**Files:**
- Create: `t/03-variables.t`
- Modify: `lib/Crayon/Transform.pm`
- Modify: `lib/Crayon/Interpreter.pm`

- [ ] **Step 1: Write the failing test**

```perl
# t/03-variables.t
use v5.42;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Crayon::Test qw[ crayon_eval crayon_output ];

# Variable declaration and access
is crayon_eval('my $x = 42; $x'), 42, 'scalar declaration and access';
is crayon_eval('my $x = 10; my $y = 20; $x + $y'), 30, 'two variables';

# Array
is crayon_output('my @a = (1, 2, 3); say $a[0]'), "1\n", 'array element access';

# Hash
is crayon_output('my %h = (a => 1, b => 2); say $h{a}'), "1\n", 'hash element access';

# Assignment operators
is crayon_eval('my $x = 10; $x += 5; $x'), 15, 'compound assignment +=';
is crayon_eval('my $x = "hello"; $x .= " world"; $x'), 'hello world', 'compound assignment .=';

# Nested scope
is crayon_eval('my $x = 1; { my $x = 2; } $x'), 1, 'lexical scoping';

# Undef by default
ok !defined crayon_eval('my $x; $x'), 'uninitialized variable is undef';

done_testing;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib -It/lib t/03-variables.t`
Expected: FAIL — transform errors on variable/assignment nodes

- [ ] **Step 3: Add variable transform handlers**

Add to `lib/Crayon/Transform.pm`:

```perl
# ---- Variables ----

# scalar is unnamed in tree-sitter-perl, so we handle it by type even though is_named is false
sub _transform_scalar ($node, $source) {
    my $text = _text($node, $source);
    # $text is e.g. "$x", "$Foo::bar"
    $text =~ s/^\$//;
    my ($namespace, $name);
    if ($text =~ /^(.+)::([^:]+)$/) {
        ($namespace, $name) = ($1, $2);
    } else {
        $name = $text;
    }
    Variable('$', $name, $namespace);
}

sub _transform_array ($node, $source) {
    my $text = _text($node, $source);
    $text =~ s/^\@//;
    Variable('@', $text, undef);
}

sub _transform_hash ($node, $source) {
    my $text = _text($node, $source);
    $text =~ s/^%//;
    Variable('%', $text, undef);
}

# ---- Variable declarations ----

sub _transform_variable_declaration ($node, $source) {
    my $keyword = _first_anon_keyword($node, $source) // 'my';

    my $var_node = _child_by_field($node, 'variable');
    my $vars_node = _child_by_field($node, 'variables');

    my @variables;
    if ($var_node) {
        push @variables, _transform_node($var_node, $source);
    } elsif ($vars_node) {
        for my $child (_named_children($vars_node)) {
            push @variables, _transform_node($child, $source);
        }
    }

    my $attr_node = _child_by_field($node, 'attributes');
    my $attrs = $attr_node ? _transform_attrlist($attr_node, $source) : undef;

    VariableDeclaration($keyword, \@variables, $attrs);
}

sub _transform_attrlist ($node, $source) {
    my @attrs;
    for my $child (_named_children($node)) {
        my $text = _text($child, $source);
        # attribute may have args: :foo(bar)
        if ($text =~ /^(\w+)\((.+)\)$/) {
            push @attrs, Attribute($1, String($2, 0));
        } else {
            push @attrs, Attribute($text, undef);
        }
    }
    return \@attrs;
}

# ---- Assignment ----

sub _transform_assignment_expression ($node, $source) {
    my $left  = _child_by_field($node, 'left');
    my $right = _child_by_field($node, 'right');
    my $op    = _child_by_field($node, 'operator');

    Assignment(
        _text($op, $source),
        _transform_node($left, $source),
        _transform_node($right, $source),
    );
}

# ---- Subscripts ----

sub _transform_array_element_expression ($node, $source) {
    my $array_node = _child_by_field($node, 'array');
    my $index_node = _child_by_field($node, 'index');

    my $target;
    if ($array_node) {
        $target = _transform_node($array_node, $source);
    } else {
        # Arrow form: first named child is the expression
        my @children = _named_children($node);
        $target = _transform_node($children[0], $source);
    }

    Subscript(
        $target,
        _transform_node($index_node, $source),
        'array',
        !defined($array_node),
    );
}

sub _transform_hash_element_expression ($node, $source) {
    my $hash_node = _child_by_field($node, 'hash');
    my $key_node  = _child_by_field($node, 'key');

    my $target;
    if ($hash_node) {
        $target = _transform_node($hash_node, $source);
    } else {
        my @children = _named_children($node);
        $target = _transform_node($children[0], $source);
    }

    Subscript(
        $target,
        _transform_node($key_node, $source),
        'hash',
        !defined($hash_node),
    );
}

sub _transform_container_variable ($node, $source) {
    my $text = _text($node, $source);
    $text =~ s/^\$//;
    Variable('$', $text, undef);
}

# ---- Lists and parens ----

sub _transform_list_expression ($node, $source) {
    my @exprs;
    for my $child (_named_children($node)) {
        push @exprs, _transform_node($child, $source);
    }
    ExpressionList(\@exprs);
}

sub _transform_parenthesized_expression ($node, $source) {
    my @children = _named_children($node);
    if (@children == 1) {
        ParenExpression(_transform_node($children[0], $source));
    } else {
        my @exprs = map { _transform_node($_, $source) } @children;
        ParenExpression(ExpressionList(\@exprs));
    }
}

# ---- Blocks ----

sub _transform_block ($node, $source) {
    my @stmts;
    for my $child (_named_children($node)) {
        push @stmts, _transform_node($child, $source);
    }
    Block(StatementSequence(\@stmts));
}

sub _transform_block_statement ($node, $source) {
    my @children = _named_children($node);
    _transform_node($children[0], $source);
}
```

Also update `_transform_node` to handle unnamed nodes like `scalar`:

```perl
sub _transform_node ($node, $source) {
    my $type = $node->type;

    # Handle unnamed nodes that we still need to transform
    if (!$node->is_named) {
        if ($type eq 'scalar') {
            return _transform_scalar($node, $source);
        }
        return undef;
    }

    my $method = "_transform_$type";
    $method =~ s/[^a-zA-Z0-9_]/_/g;

    if (my $handler = __PACKAGE__->can($method)) {
        return $handler->($node, $source);
    }

    die "Unsupported CST node type: $type at byte " . $node->start_byte . "\n";
}
```

- [ ] **Step 4: Add variable/assignment interpreter handlers**

Add to `lib/Crayon/Interpreter.pm`:

```perl
    method eval_VariableDeclaration ($node) {
        my $result = undef;
        for my $var ($node->{variables}->@*) {
            $result = $env->define($var->{sigil} . $var->{name}, undef);
        }
        return $result;
    }

    method eval_Variable ($node) {
        my $key = $node->{sigil} . $node->{name};
        return $env->lookup($key);
    }

    method eval_Assignment ($node) {
        my $value = $self->eval($node->{value});
        my $target = $node->{target};

        if ($node->{operator} ne '=') {
            my $current = $self->eval($target);
            my $op = substr($node->{operator}, 0, -1); # strip trailing =
            $value = _apply_binary_op($op, $current, $value);
        }

        if ($target->{type} eq 'Variable') {
            my $key = $target->{sigil} . $target->{name};
            if ($env->exists($key)) {
                return $env->assign($key, $value);
            }
            return $env->define($key, $value);
        } elsif ($target->{type} eq 'Subscript') {
            return $self->_assign_subscript($target, $value);
        }

        die "Cannot assign to " . $target->{type} . "\n";
    }

    method eval_ExpressionList ($node) {
        my @vals = map { $self->eval($_) } $node->{expressions}->@*;
        return @vals;
    }

    method eval_ParenExpression ($node) {
        $self->eval($node->{expression});
    }

    method eval_Subscript ($node) {
        my $target = $self->eval($node->{target});
        my $index  = $self->eval($node->{index});
        if ($node->{kind} eq 'array') {
            return $target->[$index];
        } else {
            return $target->{$index};
        }
    }

    method _assign_subscript ($target_node, $value) {
        my $target = $self->eval($target_node->{target});
        my $index  = $self->eval($target_node->{index});
        if ($target_node->{kind} eq 'array') {
            $target->[$index] = $value;
        } else {
            $target->{$index} = $value;
        }
        return $value;
    }

    method eval_Block ($node) {
        my $prev = $env;
        $env = $env->child;
        my $result = $self->eval($node->{statements});
        $env = $prev;
        return $result;
    }
```

Also handle `VariableDeclaration` in assignment context — when `my $x = 42` comes through as an assignment where the left side is a variable_declaration, the transform should produce the right structure. Add handling for the combined declaration+assignment pattern.

Update `eval_VariableDeclaration` to handle the initial assignment:

The tree-sitter CST for `my $x = 42` produces an `assignment_expression` with a `variable_declaration` on the left. So the transform for `assignment_expression` should detect this:

Update `_transform_assignment_expression` in Transform.pm:

```perl
sub _transform_assignment_expression ($node, $source) {
    my $left  = _child_by_field($node, 'left');
    my $right = _child_by_field($node, 'right');
    my $op    = _child_by_field($node, 'operator');

    my $left_ast = _transform_node($left, $source);

    # my $x = 42 → left is VariableDeclaration, right is the value
    # We keep it as Assignment so the interpreter can define + assign in one step
    Assignment(
        _text($op, $source),
        $left_ast,
        _transform_node($right, $source),
    );
}
```

And update `eval_Assignment` to handle VariableDeclaration targets:

```perl
        if ($target->{type} eq 'Variable') {
            my $key = $target->{sigil} . $target->{name};
            if ($env->exists($key)) {
                return $env->assign($key, $value);
            }
            return $env->define($key, $value);
        } elsif ($target->{type} eq 'VariableDeclaration') {
            # my $x = VALUE → define all declared variables, assign value to last
            my $result = $value;
            my @vars = $target->{variables}->@*;
            if (@vars == 1) {
                my $key = $vars[0]->{sigil} . $vars[0]->{name};
                $env->define($key, $value);
            } else {
                # my ($x, $y) = @list
                my @vals = ref $value eq 'ARRAY' ? @$value : ($value);
                for my $i (0 .. $#vars) {
                    my $key = $vars[$i]->{sigil} . $vars[$i]->{name};
                    $env->define($key, $vals[$i]);
                }
            }
            return $result;
        } elsif ($target->{type} eq 'Subscript') {
            return $self->_assign_subscript($target, $value);
        }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `perl -Ilib -It/lib t/03-variables.t`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/Crayon/Transform.pm lib/Crayon/Interpreter.pm t/03-variables.t
git commit -m "feat: variable declaration, assignment, and subscript access"
```

---

### Task 7: Operators

**Files:**
- Create: `t/04-operators.t`
- Modify: `lib/Crayon/Transform.pm`
- Modify: `lib/Crayon/Interpreter.pm`

- [ ] **Step 1: Write the failing test**

```perl
# t/04-operators.t
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

# String ops
is crayon_eval('"hello" . " " . "world"'), 'hello world', 'concatenation';
is crayon_eval('"ab" x 3'), 'ababab', 'string repetition';

# Comparison
is crayon_eval('1 == 1'), 1, 'numeric equal (true)';
ok !crayon_eval('1 == 2'), 'numeric equal (false)';
is crayon_eval('"a" eq "a"'), 1, 'string equal (true)';
is crayon_eval('5 <=> 3'), 1, 'spaceship positive';
is crayon_eval('3 <=> 5'), -1, 'spaceship negative';
is crayon_eval('3 < 5'), 1, 'less than';

# Logical
is crayon_eval('1 && 2'), 2, 'logical and (truthy)';
is crayon_eval('0 || 3'), 3, 'logical or (falsy lhs)';
is crayon_eval('undef // 42'), 42, 'defined-or';
ok !crayon_eval('not 1'), 'not';
is crayon_eval('1 and 2'), 2, 'low-prec and';
is crayon_eval('0 or 3'), 3, 'low-prec or';

# Unary
is crayon_eval('-5'), -5, 'unary minus';
is crayon_eval('!0'), 1, 'logical not';
is crayon_eval('my $x = 5; ++$x'), 6, 'prefix increment';
is crayon_eval('my $x = 5; --$x'), 4, 'prefix decrement';

# Postfix
is crayon_eval('my $x = 5; $x++; $x'), 6, 'postfix increment';
is crayon_eval('my $x = 5; $x--; $x'), 4, 'postfix decrement';

# Ternary
is crayon_eval('1 ? "yes" : "no"'), 'yes', 'ternary true';
is crayon_eval('0 ? "yes" : "no"'), 'no', 'ternary false';

# Precedence (resolved by tree-sitter)
is crayon_eval('2 + 3 * 4'), 14, 'precedence: mul before add';
is crayon_eval('(2 + 3) * 4'), 20, 'parens override precedence';

done_testing;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib -It/lib t/04-operators.t`
Expected: FAIL — transform errors on binary_expression etc.

- [ ] **Step 3: Add operator transform handlers**

Add to `lib/Crayon/Transform.pm`:

```perl
# ---- Binary expressions ----
# tree-sitter-perl splits these into 4 types by precedence level

sub _transform_binary_expression ($node, $source) {
    my $left  = _child_by_field($node, 'left');
    my $right = _child_by_field($node, 'right');
    my $op    = _child_by_field($node, 'operator');

    BinaryOp(
        _text($op, $source),
        _transform_node($left, $source),
        _transform_node($right, $source),
    );
}

# equality_expression, relational_expression, lowprec_logical_expression
# all have the same field structure
*_transform_equality_expression          = \&_transform_binary_expression;
*_transform_relational_expression        = \&_transform_binary_expression;
*_transform_lowprec_logical_expression   = \&_transform_binary_expression;

# ---- Unary expressions ----

sub _transform_unary_expression ($node, $source) {
    my $operand = _child_by_field($node, 'operand');
    my $op      = _child_by_field($node, 'operator');
    UnaryOp(_text($op, $source), _transform_node($operand, $source));
}

sub _transform_preinc_expression ($node, $source) {
    my $operand = _child_by_field($node, 'operand');
    my $op      = _child_by_field($node, 'operator');
    UnaryOp(_text($op, $source), _transform_node($operand, $source));
}

sub _transform_postinc_expression ($node, $source) {
    my $operand = _child_by_field($node, 'operand');
    my $op      = _child_by_field($node, 'operator');
    PostfixOp(_text($op, $source), _transform_node($operand, $source));
}

sub _transform_refgen_expression ($node, $source) {
    my @children = _named_children($node);
    UnaryOp('\\', _transform_node($children[0], $source));
}

# ---- Ternary ----

sub _transform_conditional_expression ($node, $source) {
    my $cond = _child_by_field($node, 'condition');
    my $then = _child_by_field($node, 'consequent');
    my $else = _child_by_field($node, 'alternative');

    Ternary(
        _transform_node($cond, $source),
        _transform_node($then, $source),
        _transform_node($else, $source),
    );
}
```

- [ ] **Step 4: Add operator interpreter handlers**

Add to `lib/Crayon/Interpreter.pm`:

```perl
    method eval_BinaryOp ($node) {
        my $op = $node->{operator};

        # Short-circuit operators
        if ($op eq '&&' || $op eq 'and') {
            my $left = $self->eval($node->{left});
            return $left ? $self->eval($node->{right}) : $left;
        }
        if ($op eq '||' || $op eq 'or') {
            my $left = $self->eval($node->{left});
            return $left ? $left : $self->eval($node->{right});
        }
        if ($op eq '//') {
            my $left = $self->eval($node->{left});
            return defined($left) ? $left : $self->eval($node->{right});
        }

        my $left  = $self->eval($node->{left});
        my $right = $self->eval($node->{right});
        return _apply_binary_op($op, $left, $right);
    }

    method eval_UnaryOp ($node) {
        if ($node->{operator} eq 'not' || $node->{operator} eq '!') {
            return !$self->eval($node->{operand}) ? 1 : 0;
        }
        if ($node->{operator} eq '\\') {
            # Reference creation — need the variable, not its value
            my $target = $node->{operand};
            if ($target->{type} eq 'Variable') {
                my $key = $target->{sigil} . $target->{name};
                my $val = $env->lookup($key);
                return \$val;
            }
            my $val = $self->eval($target);
            return \$val;
        }
        if ($node->{operator} eq '++') {
            my $key = $node->{operand}{sigil} . $node->{operand}{name};
            my $val = $env->lookup($key) + 1;
            $env->assign($key, $val);
            return $val;
        }
        if ($node->{operator} eq '--') {
            my $key = $node->{operand}{sigil} . $node->{operand}{name};
            my $val = $env->lookup($key) - 1;
            $env->assign($key, $val);
            return $val;
        }

        my $val = $self->eval($node->{operand});
        if ($node->{operator} eq '-') { return -$val }
        if ($node->{operator} eq '+') { return +$val }
        if ($node->{operator} eq '~') { return ~$val }
        die "Unknown unary operator: $node->{operator}\n";
    }

    method eval_PostfixOp ($node) {
        my $key = $node->{operand}{sigil} . $node->{operand}{name};
        my $val = $env->lookup($key);
        if ($node->{operator} eq '++') {
            $env->assign($key, $val + 1);
        } elsif ($node->{operator} eq '--') {
            $env->assign($key, $val - 1);
        }
        return $val; # returns the old value
    }

    method eval_Ternary ($node) {
        if ($self->eval($node->{condition})) {
            return $self->eval($node->{then_expr});
        } else {
            return $self->eval($node->{else_expr});
        }
    }
```

Add the `_apply_binary_op` helper as a package-level function:

```perl
sub _apply_binary_op ($op, $left, $right) {
    return $left +  $right if $op eq '+';
    return $left -  $right if $op eq '-';
    return $left *  $right if $op eq '*';
    return $left /  $right if $op eq '/';
    return $left %  $right if $op eq '%';
    return $left ** $right if $op eq '**';
    return $left .  $right if $op eq '.';
    return $left x  $right if $op eq 'x';
    return $left << $right if $op eq '<<';
    return $left >> $right if $op eq '>>';
    return $left &  $right if $op eq '&';
    return $left |  $right if $op eq '|';
    return $left ^  $right if $op eq '^';

    # Comparison
    return ($left == $right ? 1 : 0) if $op eq '==';
    return ($left != $right ? 1 : 0) if $op eq '!=';
    return ($left <  $right ? 1 : 0) if $op eq '<';
    return ($left <= $right ? 1 : 0) if $op eq '<=';
    return ($left >  $right ? 1 : 0) if $op eq '>';
    return ($left >= $right ? 1 : 0) if $op eq '>=';
    return ($left <=> $right)        if $op eq '<=>';

    # String comparison
    return ($left eq $right ? 1 : 0) if $op eq 'eq';
    return ($left ne $right ? 1 : 0) if $op eq 'ne';
    return ($left lt $right ? 1 : 0) if $op eq 'lt';
    return ($left le $right ? 1 : 0) if $op eq 'le';
    return ($left gt $right ? 1 : 0) if $op eq 'gt';
    return ($left ge $right ? 1 : 0) if $op eq 'ge';
    return ($left cmp $right)        if $op eq 'cmp';

    # Range
    return [$left .. $right] if $op eq '..';

    die "Unknown binary operator: $op\n";
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `perl -Ilib -It/lib t/04-operators.t`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/Crayon/Transform.pm lib/Crayon/Interpreter.pm t/04-operators.t
git commit -m "feat: binary, unary, postfix, and ternary operator support"
```

---

### Task 8: Control Flow

**Files:**
- Create: `t/05-control-flow.t`
- Modify: `lib/Crayon/Transform.pm`
- Modify: `lib/Crayon/Interpreter.pm`

- [ ] **Step 1: Write the failing test**

```perl
# t/05-control-flow.t
use v5.42;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Crayon::Test qw[ crayon_eval crayon_output ];

# if/else
is crayon_output('if (1) { say "yes" }'), "yes\n", 'if true';
is crayon_output('if (0) { say "yes" } else { say "no" }'), "no\n", 'if-else';
is crayon_output('if (0) { say "a" } elsif (1) { say "b" } else { say "c" }'),
    "b\n", 'if-elsif-else';

# unless
is crayon_output('unless (0) { say "yes" }'), "yes\n", 'unless false';

# postfix if
is crayon_output('say "yes" if 1'), "yes\n", 'postfix if true';
is crayon_output('say "yes" if 0'), "", 'postfix if false';

# postfix unless
is crayon_output('say "yes" unless 0'), "yes\n", 'postfix unless';

# while
is crayon_output('my $i = 0; while ($i < 3) { say $i; $i++ }'), "0\n1\n2\n", 'while loop';

# until
is crayon_output('my $i = 0; until ($i >= 3) { say $i; $i++ }'), "0\n1\n2\n", 'until loop';

# C-style for
is crayon_output('for (my $i = 0; $i < 3; $i++) { say $i }'), "0\n1\n2\n", 'c-style for';

# foreach
is crayon_output('for my $x (1, 2, 3) { say $x }'), "1\n2\n3\n", 'foreach';
is crayon_output('for (1, 2, 3) { say $_ }'), "1\n2\n3\n", 'foreach with $_';

# postfix for
is crayon_output('say $_ for 1, 2, 3'), "1\n2\n3\n", 'postfix for';

# last/next
is crayon_output('for my $x (1, 2, 3, 4, 5) { last if $x == 3; say $x }'),
    "1\n2\n", 'last';
is crayon_output('for my $x (1, 2, 3, 4, 5) { next if $x == 3; say $x }'),
    "1\n2\n4\n5\n", 'next';

# return
is crayon_eval('sub foo { return 42 } foo()'), 42, 'return from sub';

done_testing;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib -It/lib t/05-control-flow.t`
Expected: FAIL — transform errors on conditional_statement, loop_statement, etc.

- [ ] **Step 3: Add control flow transform handlers**

Add to `lib/Crayon/Transform.pm`:

```perl
# ---- Conditional statements ----

sub _transform_conditional_statement ($node, $source) {
    my $keyword = _first_anon_keyword($node, $source) // 'if';
    my $negated = $keyword eq 'unless' ? 1 : 0;

    my $cond_node  = _child_by_field($node, 'condition');
    my $block_node = _child_by_field($node, 'block');

    my @elsif_clauses;
    my $else_block;

    for my $child (_all_children($node)) {
        my $type = $child->type;
        if ($type eq 'elsif') {
            my $ec = _child_by_field($child, 'condition');
            my $eb = _child_by_field($child, 'block');
            push @elsif_clauses, ElsifClause(
                _transform_node($ec, $source),
                _transform_node($eb, $source),
            );
        } elsif ($type eq 'else') {
            my $eb = _child_by_field($child, 'block');
            $else_block = _transform_node($eb, $source);
        }
    }

    Conditional(
        _transform_node($cond_node, $source),
        $negated,
        _transform_node($block_node, $source),
        \@elsif_clauses,
        $else_block,
    );
}

# ---- Loops ----

sub _transform_loop_statement ($node, $source) {
    my $keyword = _first_anon_keyword($node, $source) // 'while';
    my $negated = $keyword eq 'until' ? 1 : 0;

    my $cond_node     = _child_by_field($node, 'condition');
    my $block_node    = _child_by_field($node, 'block');
    my $continue_node = _child_by_field($node, 'continue');

    WhileLoop(
        _transform_node($cond_node, $source),
        $negated,
        _transform_node($block_node, $source),
        $continue_node ? _transform_node($continue_node, $source) : undef,
    );
}

sub _transform_for_statement ($node, $source) {
    my $var_node      = _child_by_field($node, 'variable');
    my $list_node     = _child_by_field($node, 'list');
    my $block_node    = _child_by_field($node, 'block');
    my $continue_node = _child_by_field($node, 'continue');

    my $iterator = $var_node ? _transform_node($var_node, $source) : undef;

    ForeachLoop(
        $iterator,
        _transform_node($list_node, $source),
        _transform_node($block_node, $source),
        $continue_node ? _transform_node($continue_node, $source) : undef,
    );
}

sub _transform_cstyle_for_statement ($node, $source) {
    my $init_node = _child_by_field($node, 'initialiser');
    my $cond_node = _child_by_field($node, 'condition');
    my $iter_node = _child_by_field($node, 'iterator');
    my $block_node = _child_by_field($node, 'block');

    CStyleForLoop(
        $init_node ? _transform_node($init_node, $source) : undef,
        $cond_node ? _transform_node($cond_node, $source) : undef,
        $iter_node ? _transform_node($iter_node, $source) : undef,
        _transform_node($block_node, $source),
    );
}

# ---- Postfix modifiers ----

sub _transform_postfix_conditional_expression ($node, $source) {
    my @children = _named_children($node);
    my $cond_node = _child_by_field($node, 'condition');

    # The body is the first named child (the expression)
    my $body = _transform_node($children[0], $source);
    my $cond = _transform_node($cond_node, $source);

    # Determine keyword from anonymous tokens
    my $keyword = 'if';
    for my $child (_all_children($node)) {
        if (!$child->is_named) {
            my $text = _text($child, $source);
            if ($text eq 'unless') { $keyword = 'unless'; last }
        }
    }

    ExpressionStatement($body, PostfixModifier($keyword, $cond));
}

sub _transform_postfix_loop_expression ($node, $source) {
    my @children = _named_children($node);
    my $cond_node = _child_by_field($node, 'condition');

    my $body = _transform_node($children[0], $source);
    my $cond = _transform_node($cond_node, $source);

    my $keyword = 'while';
    for my $child (_all_children($node)) {
        if (!$child->is_named) {
            my $text = _text($child, $source);
            if ($text eq 'until') { $keyword = 'until'; last }
        }
    }

    ExpressionStatement($body, PostfixModifier($keyword, $cond));
}

sub _transform_postfix_for_expression ($node, $source) {
    my @children = _named_children($node);
    my $list_node = _child_by_field($node, 'list');

    my $body = _transform_node($children[0], $source);
    my $list = _transform_node($list_node, $source);

    ExpressionStatement($body, PostfixModifier('for', $list));
}

# ---- Loop control ----

sub _transform_loopex_expression ($node, $source) {
    my $keyword_node = _child_by_field($node, 'loopex');
    my $keyword = _text($keyword_node, $source);

    my @children = _named_children($node);
    my $label;
    my $expr;

    for my $child (@children) {
        next if _text($child, $source) eq $keyword;
        # Could be a label (bareword) or expression
        $label = _text($child, $source);
    }

    LoopControl($keyword, $label, undef);
}

sub _transform_return_expression ($node, $source) {
    my @children = _named_children($node);
    my $expr = @children ? _transform_node($children[0], $source) : undef;
    LoopControl('return', undef, $expr);
}
```

- [ ] **Step 4: Add control flow interpreter handlers**

Add to `lib/Crayon/Interpreter.pm`:

```perl
    method eval_Conditional ($node) {
        my $cond = $self->eval($node->{condition});
        $cond = !$cond if $node->{negated};

        if ($cond) {
            return $self->eval($node->{then_block});
        }

        for my $elsif ($node->{elsif_clauses}->@*) {
            if ($self->eval($elsif->{condition})) {
                return $self->eval($elsif->{block});
            }
        }

        if ($node->{else_block}) {
            return $self->eval($node->{else_block});
        }

        return undef;
    }

    method eval_WhileLoop ($node) {
        my $result = undef;
        while (1) {
            my $cond = $self->eval($node->{condition});
            $cond = !$cond if $node->{negated};
            last unless $cond;

            eval { $result = $self->eval($node->{block}) };
            if ($@) {
                if (ref $@ eq 'HASH' && $@->{type} eq 'last')  { last }
                if (ref $@ eq 'HASH' && $@->{type} eq 'next')  { next }
                die $@;
            }
        }
        return $result;
    }

    method eval_ForeachLoop ($node) {
        my $list_val = $self->eval($node->{list});
        my @list = ref $list_val eq 'ARRAY' ? @$list_val : ($list_val);

        my $result = undef;
        my $iter_name = $node->{iterator}
            ? $node->{iterator}{sigil} . $node->{iterator}{name}
            : '$_';

        my $prev = $env;
        $env = $env->child;

        for my $item (@list) {
            $env->define($iter_name, $item);
            eval { $result = $self->eval($node->{block}) };
            if ($@) {
                if (ref $@ eq 'HASH' && $@->{type} eq 'last')  { last }
                if (ref $@ eq 'HASH' && $@->{type} eq 'next')  { next }
                die $@;
            }
        }

        $env = $prev;
        return $result;
    }

    method eval_CStyleForLoop ($node) {
        my $prev = $env;
        $env = $env->child;

        $self->eval($node->{init}) if $node->{init};
        my $result = undef;

        while (1) {
            if ($node->{condition}) {
                last unless $self->eval($node->{condition});
            }
            eval { $result = $self->eval($node->{block}) };
            if ($@) {
                if (ref $@ eq 'HASH' && $@->{type} eq 'last')  { last }
                if (ref $@ eq 'HASH' && $@->{type} eq 'next')  { }
                else { die $@ }
            }
            $self->eval($node->{increment}) if $node->{increment};
        }

        $env = $prev;
        return $result;
    }

    method eval_PostfixModifier ($node) {
        die "PostfixModifier should not be eval'd directly\n";
    }

    # ExpressionStatement must handle postfix modifiers
    # Update eval_ExpressionStatement:

    method eval_ExpressionStatement ($node) {
        if (my $mod = $node->{modifier}) {
            my $kw = $mod->{keyword};
            if ($kw eq 'if') {
                return $self->eval($node->{expression}) if $self->eval($mod->{expression});
                return undef;
            } elsif ($kw eq 'unless') {
                return $self->eval($node->{expression}) unless $self->eval($mod->{expression});
                return undef;
            } elsif ($kw eq 'while') {
                my $r;
                while ($self->eval($mod->{expression})) {
                    $r = $self->eval($node->{expression});
                }
                return $r;
            } elsif ($kw eq 'until') {
                my $r;
                until ($self->eval($mod->{expression})) {
                    $r = $self->eval($node->{expression});
                }
                return $r;
            } elsif ($kw eq 'for' || $kw eq 'foreach') {
                my $list_val = $self->eval($mod->{expression});
                my @list = ref $list_val eq 'ARRAY' ? @$list_val : ($list_val);
                my $prev = $env;
                $env = $env->child;
                my $r;
                for my $item (@list) {
                    $env->define('$_', $item);
                    $r = $self->eval($node->{expression});
                }
                $env = $prev;
                return $r;
            }
        }
        return $self->eval($node->{expression});
    }

    method eval_LoopControl ($node) {
        my $kw = $node->{keyword};
        if ($kw eq 'return') {
            die +{ type => 'return', value => $node->{expression} ? $self->eval($node->{expression}) : undef };
        }
        die +{ type => $kw, label => $node->{label} };
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `perl -Ilib -It/lib t/05-control-flow.t`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/Crayon/Transform.pm lib/Crayon/Interpreter.pm t/05-control-flow.t
git commit -m "feat: control flow - conditionals, loops, postfix modifiers, loop control"
```

---

### Task 9: Subroutines + Closures

**Files:**
- Create: `t/06-subroutines.t`
- Modify: `lib/Crayon/Transform.pm`
- Modify: `lib/Crayon/Interpreter.pm`

- [ ] **Step 1: Write the failing test**

```perl
# t/06-subroutines.t
use v5.42;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Crayon::Test qw[ crayon_eval crayon_output ];

# Basic sub definition and call
is crayon_eval('sub add ($a, $b) { $a + $b } add(3, 4)'), 7, 'sub with signature';

# Call with parens
is crayon_eval('sub greet () { "hello" } greet()'), 'hello', 'nullary sub';

# Bare call
is crayon_output('sub show ($x) { say $x } show 42'), "42\n", 'bare call';

# Default parameter
is crayon_eval('sub inc ($x, $by = 1) { $x + $by } inc(10)'), 11, 'default param';
is crayon_eval('sub inc ($x, $by = 1) { $x + $by } inc(10, 5)'), 15, 'override default';

# Slurpy
is crayon_eval('sub sum (@nums) { my $t = 0; $t += $_ for @nums; $t } sum(1,2,3)'),
    6, 'slurpy array param';

# Closure
is crayon_eval('
    sub make_adder ($n) {
        sub ($x) { $x + $n }
    }
    my $add5 = make_adder(5);
    $add5->(10)
'), 15, 'closure';

# Lexical sub
is crayon_eval('
    my sub helper ($x) { $x * 2 }
    helper(21)
'), 42, 'lexical sub (my sub)';

# Recursive
is crayon_eval('
    sub factorial ($n) {
        return 1 if $n <= 1;
        $n * factorial($n - 1)
    }
    factorial(5)
'), 120, 'recursion';

# Anonymous sub
is crayon_eval('
    my $double = sub ($x) { $x * 2 };
    $double->(21)
'), 42, 'anonymous sub';

done_testing;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib -It/lib t/06-subroutines.t`
Expected: FAIL — transform errors on subroutine_declaration_statement etc.

- [ ] **Step 3: Add subroutine transform handlers**

Add to `lib/Crayon/Transform.pm`:

```perl
# ---- Subroutine declarations ----

sub _transform_subroutine_declaration_statement ($node, $source) {
    my $name_node = _child_by_field($node, 'name');
    my $body_node = _child_by_field($node, 'body');
    my $attr_node = _child_by_field($node, 'attributes');
    my $lexical   = _child_by_field($node, 'lexical');

    my $name = $name_node ? _text($name_node, $source) : undef;
    my $declarator = $lexical ? _text($lexical, $source) : undef;

    my $sig = _find_signature($node, $source);
    my $proto = _find_prototype($node, $source);
    my $attrs = $attr_node ? _transform_attrlist($attr_node, $source) : undef;
    my $body = $body_node ? _transform_node($body_node, $source) : undef;

    SubroutineDeclaration($declarator, $name, $proto, $attrs, $sig, $body);
}

sub _find_signature ($node, $source) {
    for my $child (_named_children($node)) {
        if ($child->type eq 'signature') {
            return _transform_signature($child, $source);
        }
    }
    return undef;
}

sub _find_prototype ($node, $source) {
    for my $child (_named_children($node)) {
        if ($child->type eq 'prototype') {
            return _text($child, $source);
        }
    }
    return undef;
}

sub _transform_signature ($node, $source) {
    my @params;
    for my $child (_named_children($node)) {
        my $type = $child->type;
        if ($type eq 'mandatory_parameter') {
            my @vars = _all_children($child);
            my $var_text;
            for my $v (@vars) {
                if ($v->type eq 'scalar' || ($v->is_named && $v->type =~ /scalar|array|hash/)) {
                    $var_text = _text($v, $source);
                    last;
                }
            }
            $var_text //= _text($child, $source);
            $var_text =~ s/^\$//;
            push @params, ScalarParam($var_text, undef, 0);
        } elsif ($type eq 'optional_parameter') {
            my $default_node = _child_by_field($child, 'default');
            my @vars = _all_children($child);
            my $var_text;
            for my $v (@vars) {
                $var_text = _text($v, $source) if $v->type eq 'scalar';
            }
            $var_text //= '';
            $var_text =~ s/^\$//;
            push @params, ScalarParam(
                $var_text,
                $default_node ? _transform_node($default_node, $source) : undef,
                0,
            );
        } elsif ($type eq 'named_parameter') {
            my $default_node = _child_by_field($child, 'default');
            my $text = _text($child, $source);
            $text =~ s/^:\s*\$//;
            $text =~ s/\s*=.*//;
            push @params, ScalarParam(
                $text,
                $default_node ? _transform_node($default_node, $source) : undef,
                1,
            );
        } elsif ($type eq 'slurpy_parameter') {
            my $text = _text($child, $source);
            my $sigil = substr($text, 0, 1);
            my $name = length($text) > 1 ? substr($text, 1) : undef;
            push @params, SlurpyParam($sigil, $name);
        }
    }
    Signature(\@params);
}

# ---- Anonymous subs ----

sub _transform_anonymous_subroutine_expression ($node, $source) {
    my $body_node = _child_by_field($node, 'body');
    my $attr_node = _child_by_field($node, 'attributes');

    my $sig = _find_signature($node, $source);
    my $proto = _find_prototype($node, $source);
    my $attrs = $attr_node ? _transform_attrlist($attr_node, $source) : undef;

    AnonymousSub($sig, $proto, $attrs, _transform_node($body_node, $source), 'sub');
}

# ---- Coderef calls: $ref->(args) ----

sub _transform_coderef_call_expression ($node, $source) {
    my $args_node = _child_by_field($node, 'arguments');
    my @children = _named_children($node);

    # First named child is the coderef expression
    my $target = _transform_node($children[0], $source);

    my @args;
    if ($args_node) {
        for my $child (_named_children($args_node)) {
            push @args, _transform_node($child, $source);
        }
    }

    # Model as a method call with no method name (deref call)
    MethodCall($target, undef, \@args, 0);
}
```

- [ ] **Step 4: Add subroutine interpreter handlers**

Add to `lib/Crayon/Interpreter.pm`:

```perl
    method eval_SubroutineDeclaration ($node) {
        my $sub_value = +{
            type      => '_CrayonSub',
            name      => $node->{name},
            signature => $node->{signature},
            body      => $node->{body},
            env       => $env, # capture closure environment
        };

        if ($node->{name}) {
            my $key = '&' . $node->{name};
            $env->define($key, $sub_value);
        }

        return $sub_value;
    }

    method eval_AnonymousSub ($node) {
        return +{
            type      => '_CrayonSub',
            name      => undef,
            signature => $node->{signature},
            body      => $node->{body},
            env       => $env,
        };
    }

    method _call_sub ($sub_val, @args) {
        my $call_env = Crayon::Environment->new(parent => $sub_val->{env});

        # Bind parameters from signature
        if (my $sig = $sub_val->{signature}) {
            my $arg_idx = 0;
            for my $param ($sig->{params}->@*) {
                if ($param->{type} eq 'ScalarParam') {
                    my $name = '$' . ($param->{name} // '_');
                    if ($arg_idx < @args) {
                        $call_env->define($name, $args[$arg_idx++]);
                    } elsif ($param->{default}) {
                        $call_env->define($name, $self->eval($param->{default}));
                    } else {
                        $call_env->define($name, undef);
                    }
                } elsif ($param->{type} eq 'SlurpyParam') {
                    my $name = $param->{sigil} . ($param->{name} // '_');
                    my @rest = @args[$arg_idx .. $#args];
                    $call_env->define($name, \@rest);
                    $arg_idx = @args;
                }
            }
        } else {
            # No signature — put args in @_
            $call_env->define('@_', \@args);
        }

        my $prev = $env;
        $env = $call_env;
        my $result;
        eval {
            $result = $self->eval($sub_val->{body});
        };
        $env = $prev;

        if ($@) {
            if (ref $@ eq 'HASH' && $@->{type} eq 'return') {
                return $@->{value};
            }
            die $@;
        }

        return $result;
    }
```

Update `eval_Call` to handle user-defined subs:

```perl
    method eval_Call ($node) {
        my $name = $node->{name};
        my @args = map { $self->eval($_) } ($node->{args} // [])->@*;

        # Check for user-defined sub
        my $key = '&' . $name;
        if ($env->exists($key)) {
            my $sub_val = $env->lookup($key);
            return $self->_call_sub($sub_val, @args);
        }

        # Builtins
        if ($name eq 'say')   { say join('', @args); return 1 }
        if ($name eq 'print') { print join('', @args); return 1 }
        if ($name eq 'push')  { push $args[0]->@*, @args[1..$#args]; return scalar $args[0]->@* }
        if ($name eq 'pop')   { return pop $args[0]->@* }
        if ($name eq 'shift') { return shift $args[0]->@* }
        if ($name eq 'join')  { return join($args[0], @args[1..$#args]) }
        if ($name eq 'scalar'){ return ref $args[0] eq 'ARRAY' ? scalar $args[0]->@* : $args[0] }
        if ($name eq 'defined') { return defined($args[0]) ? 1 : 0 }
        if ($name eq 'ref')   { return ref($args[0]) // '' }
        if ($name eq 'die')   { die @args ? join('', @args) : "Died\n" }
        if ($name eq 'warn')  { warn join('', @args); return 1 }
        if ($name eq 'sqrt')  { return sqrt($args[0]) }
        if ($name eq 'abs')   { return abs($args[0]) }
        if ($name eq 'chr')   { return chr($args[0]) }
        if ($name eq 'ord')   { return ord($args[0]) }
        if ($name eq 'lc')    { return lc($args[0]) }
        if ($name eq 'uc')    { return uc($args[0]) }
        if ($name eq 'chomp') { chomp $args[0]; return $args[0] }
        if ($name eq 'keys')  { return [ keys $args[0]->%* ] }
        if ($name eq 'values') { return [ values $args[0]->%* ] }
        if ($name eq 'exists') { return 1 } # simplified
        if ($name eq 'delete') { return undef } # simplified

        die "Unknown function: $name\n";
    }

    method eval_MethodCall ($node) {
        my $invocant = $self->eval($node->{invocant});

        # $coderef->(args) — method is undef
        if (!defined $node->{method}) {
            die "Not a CODE reference\n" unless ref $invocant eq 'HASH' && $invocant->{type} eq '_CrayonSub';
            my @args = map { $self->eval($_) } ($node->{args} // [])->@*;
            return $self->_call_sub($invocant, @args);
        }

        # $obj->method(args)
        my $method_name = ref $node->{method} ? $self->eval($node->{method}) : $node->{method};
        my @args = map { $self->eval($_) } ($node->{args} // [])->@*;

        # Object method dispatch — will be implemented fully in Task 10
        if (ref $invocant eq 'HASH' && $invocant->{type} eq '_CrayonObject') {
            return $self->_dispatch_method($invocant, $method_name, @args);
        }

        die "Cannot call method '$method_name' on non-object\n";
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `perl -Ilib -It/lib t/06-subroutines.t`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/Crayon/Transform.pm lib/Crayon/Interpreter.pm t/06-subroutines.t
git commit -m "feat: subroutines with signatures, closures, anonymous subs, and builtins"
```

---

### Task 10: Classes, Methods, Fields

**Files:**
- Create: `t/07-classes.t`
- Modify: `lib/Crayon/Transform.pm`
- Modify: `lib/Crayon/Interpreter.pm`

- [ ] **Step 1: Write the failing test**

```perl
# t/07-classes.t
use v5.42;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Crayon::Test qw[ crayon_eval crayon_output ];

# Basic class with field and method
is crayon_output('
    class Point {
        field $x :param :reader;
        field $y :param :reader;

        method magnitude () {
            sqrt($x**2 + $y**2)
        }
    }
    my $p = Point->new(x => 3, y => 4);
    say $p->magnitude
'), "5\n", 'class with fields and method';

# :writer
is crayon_output('
    class Counter {
        field $count :param :reader :writer = 0;

        method increment () { $count++ }
    }
    my $c = Counter->new;
    $c->increment;
    $c->increment;
    say $c->count
'), "2\n", 'field with :writer and default';

# Lexical method (my method)
is crayon_eval('
    class Calc {
        field $value :param;

        my method double () { $value * 2 }

        method result () { $self->double }
    }
    my $c = Calc->new(value => 21);
    $c->result
'), 42, 'lexical method';

# Inheritance with isa
is crayon_output('
    class Animal {
        field $name :param :reader;
        method speak () { say $name . " speaks" }
    }
    class Dog :isa(Animal) {
        method speak () { say $self->name . " barks" }
    }
    my $d = Dog->new(name => "Rex");
    $d->speak
'), "Rex barks\n", 'class inheritance with :isa';

# ADJUST phaser
is crayon_eval('
    class Validated {
        field $value :param;
        ADJUST {
            die "negative" if $value < 0;
        }
        method value () { $value }
    }
    my $v = Validated->new(value => 42);
    $v->value
'), 42, 'ADJUST phaser runs during construction';

done_testing;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib -It/lib t/07-classes.t`
Expected: FAIL — transform errors on class_statement, method_declaration_statement, etc.

- [ ] **Step 3: Add class/method/field transform handlers**

Add to `lib/Crayon/Transform.pm`:

```perl
# ---- Classes ----

sub _transform_class_statement ($node, $source) {
    my $name_node    = _child_by_field($node, 'name');
    my $version_node = _child_by_field($node, 'version');
    my $attr_node    = _child_by_field($node, 'attributes');

    my $name = _text($name_node, $source);
    my $version = $version_node ? _text($version_node, $source) : undef;
    my $attrs = $attr_node ? _transform_attrlist($attr_node, $source) : undef;

    # Find the block child
    my $body;
    for my $child (_named_children($node)) {
        if ($child->type eq 'block') {
            $body = _transform_node($child, $source);
            last;
        }
    }

    ClassDeclaration($name, $version, $attrs, $body);
}

sub _transform_role_statement ($node, $source) {
    my $name_node    = _child_by_field($node, 'name');
    my $version_node = _child_by_field($node, 'version');
    my $attr_node    = _child_by_field($node, 'attributes');

    my $name = _text($name_node, $source);
    my $version = $version_node ? _text($version_node, $source) : undef;
    my $attrs = $attr_node ? _transform_attrlist($attr_node, $source) : undef;

    my $body;
    for my $child (_named_children($node)) {
        if ($child->type eq 'block') {
            $body = _transform_node($child, $source);
            last;
        }
    }

    RoleDeclaration($name, $version, $attrs, $body);
}

# ---- Methods ----

sub _transform_method_declaration_statement ($node, $source) {
    my $name_node = _child_by_field($node, 'name');
    my $body_node = _child_by_field($node, 'body');
    my $attr_node = _child_by_field($node, 'attributes');
    my $lexical   = _child_by_field($node, 'lexical');

    my $name = $name_node ? _text($name_node, $source) : undef;
    my $declarator = $lexical ? _text($lexical, $source) : undef;
    my $sig = _find_signature($node, $source);
    my $attrs = $attr_node ? _transform_attrlist($attr_node, $source) : undef;
    my $body = $body_node ? _transform_node($body_node, $source) : undef;

    MethodDeclaration($declarator, $name, $attrs, $sig, $body);
}

sub _transform_anonymous_method_expression ($node, $source) {
    my $body_node = _child_by_field($node, 'body');
    my $attr_node = _child_by_field($node, 'attributes');

    my $sig = _find_signature($node, $source);
    my $attrs = $attr_node ? _transform_attrlist($attr_node, $source) : undef;

    AnonymousSub($sig, undef, $attrs, _transform_node($body_node, $source), 'method');
}

# ---- Field declarations ----
# field $x :param :reader = default_value
# These come through as variable_declaration with 'field' keyword
# We already handle variable_declaration — add field detection

# Update _transform_variable_declaration to detect 'field':
```

Update `_transform_variable_declaration` in the existing code:

```perl
sub _transform_variable_declaration ($node, $source) {
    my $keyword = _first_anon_keyword($node, $source) // 'my';

    my $var_node = _child_by_field($node, 'variable');
    my $vars_node = _child_by_field($node, 'variables');

    my @variables;
    if ($var_node) {
        push @variables, _transform_node($var_node, $source);
    } elsif ($vars_node) {
        for my $child (_named_children($vars_node)) {
            push @variables, _transform_node($child, $source);
        }
    }

    my $attr_node = _child_by_field($node, 'attributes');
    my $attrs = $attr_node ? _transform_attrlist($attr_node, $source) : undef;

    # Detect 'field' declarations
    if ($keyword eq 'field') {
        my $default = undef;
        # Check for = default_value in the assignment context
        # (field defaults are handled by the enclosing assignment_expression)
        return FieldDeclaration($variables[0], $attrs, $default);
    }

    VariableDeclaration($keyword, \@variables, $attrs);
}
```

Also handle `class_phaser_statement` (ADJUST/BUILD):

```perl
sub _transform_class_phaser_statement ($node, $source) {
    my $phase_node = _child_by_field($node, 'phase');
    my $phase = $phase_node ? _text($phase_node, $source) : 'ADJUST';

    my $body;
    for my $child (_named_children($node)) {
        if ($child->type eq 'block') {
            $body = _transform_node($child, $source);
            last;
        }
    }

    # Model as a SubroutineDeclaration with the phaser name
    SubroutineDeclaration(undef, $phase, undef, undef, undef, $body);
}
```

- [ ] **Step 4: Add class/method/field interpreter handlers**

Add to `lib/Crayon/Interpreter.pm`:

```perl
    method eval_ClassDeclaration ($node) {
        my $class_name = $node->{name};

        # Parse :isa(ParentClass) from attributes
        my $parent_class;
        if ($node->{attributes}) {
            for my $attr ($node->{attributes}->@*) {
                if ($attr->{name} eq 'isa' && $attr->{expression}) {
                    $parent_class = $attr->{expression}{value};
                }
            }
        }

        # Create class meta object
        my $class_meta = +{
            type       => '_CrayonClass',
            name       => $class_name,
            parent     => $parent_class,
            fields     => [],
            methods    => +{},
            adjusts    => [],
        };

        # Evaluate the class body to collect fields, methods, adjusts
        my $prev = $env;
        $env = $env->child;
        $env->define('$__class_meta__', $class_meta);

        if ($node->{body}) {
            for my $stmt ($node->{body}{statements}{statements}->@*) {
                my $type = $stmt->{type};
                if ($type eq 'FieldDeclaration') {
                    $self->_register_field($class_meta, $stmt);
                } elsif ($type eq 'MethodDeclaration') {
                    $self->_register_method($class_meta, $stmt);
                } elsif ($type eq 'SubroutineDeclaration' && ($stmt->{name} eq 'ADJUST' || $stmt->{name} eq 'BUILD')) {
                    push $class_meta->{adjusts}->@*, +{
                        body => $stmt->{body},
                        env  => $env,
                    };
                } elsif ($type eq 'ExpressionStatement') {
                    $self->eval($stmt);
                }
            }
        }

        $env = $prev;

        # Register class globally
        $env->define('&' . $class_name, $class_meta);

        # Add 'new' as a constructor
        $class_meta->{methods}{new} = +{
            type      => '_CrayonBuiltinMethod',
            name      => 'new',
            handler   => sub ($self_obj, @args) {
                $self->_construct_object($class_meta, @args);
            },
        };

        return $class_meta;
    }

    method _register_field ($class_meta, $field_node) {
        my $var = $field_node->{variable};
        my $attrs = $field_node->{attributes} // [];
        my $attr_names = +{ map { $_->{name} => 1 } @$attrs };

        push $class_meta->{fields}->@*, +{
            name     => $var->{name},
            sigil    => $var->{sigil},
            param    => $attr_names->{param} ? 1 : 0,
            reader   => $attr_names->{reader} ? 1 : 0,
            writer   => $attr_names->{writer} ? 1 : 0,
            default  => $field_node->{default},
        };
    }

    method _register_method ($class_meta, $method_node) {
        my $method_val = +{
            type      => '_CrayonMethod',
            name      => $method_node->{name},
            signature => $method_node->{signature},
            body      => $method_node->{body},
            env       => $env,
            lexical   => $method_node->{declarator} ? 1 : 0,
        };
        $class_meta->{methods}{$method_node->{name}} = $method_val;
    }

    method _construct_object ($class_meta, @args) {
        # Build param hash from args
        my %params = @args;

        # Create object
        my $obj = +{
            type   => '_CrayonObject',
            class  => $class_meta->{name},
            fields => +{},
            meta   => $class_meta,
        };

        # Initialize fields (including inherited)
        my @all_fields = $self->_collect_fields($class_meta);
        for my $field (@all_fields) {
            my $key = $field->{sigil} . $field->{name};
            if ($field->{param} && exists $params{$field->{name}}) {
                $obj->{fields}{$key} = $params{$field->{name}};
            } elsif ($field->{default}) {
                $obj->{fields}{$key} = $self->eval($field->{default});
            } else {
                $obj->{fields}{$key} = undef;
            }
        }

        # Run ADJUST/BUILD phasers
        my @adjusts = $self->_collect_adjusts($class_meta);
        for my $adjust (@adjusts) {
            $self->_call_method_on($obj, $class_meta, +{
                type => '_CrayonMethod',
                body => $adjust->{body},
                env  => $adjust->{env},
                signature => undef,
                name => 'ADJUST',
            });
        }

        return $obj;
    }

    method _collect_fields ($class_meta) {
        my @fields;
        if ($class_meta->{parent}) {
            my $parent = $env->lookup('&' . $class_meta->{parent});
            push @fields, $self->_collect_fields($parent) if $parent;
        }
        push @fields, $class_meta->{fields}->@*;
        return @fields;
    }

    method _collect_adjusts ($class_meta) {
        my @adjusts;
        if ($class_meta->{parent}) {
            my $parent = $env->lookup('&' . $class_meta->{parent});
            push @adjusts, $self->_collect_adjusts($parent) if $parent;
        }
        push @adjusts, $class_meta->{adjusts}->@*;
        return @adjusts;
    }

    method _dispatch_method ($obj, $method_name, @args) {
        my $class_meta = $obj->{meta};
        my $method = $self->_find_method($class_meta, $method_name);

        if (!$method) {
            # Check for generated reader/writer
            my @all_fields = $self->_collect_fields($class_meta);
            for my $field (@all_fields) {
                if ($field->{reader} && $field->{name} eq $method_name) {
                    return $obj->{fields}{$field->{sigil} . $field->{name}};
                }
                if ($field->{writer} && $field->{name} eq $method_name && @args) {
                    $obj->{fields}{$field->{sigil} . $field->{name}} = $args[0];
                    return $args[0];
                }
            }
            die "No such method '$method_name' on class $class_meta->{name}\n";
        }

        if ($method->{type} eq '_CrayonBuiltinMethod') {
            return $method->{handler}->($obj, @args);
        }

        return $self->_call_method_on($obj, $class_meta, $method, @args);
    }

    method _find_method ($class_meta, $method_name) {
        if (exists $class_meta->{methods}{$method_name}) {
            my $m = $class_meta->{methods}{$method_name};
            return undef if $m->{lexical}; # lexical methods not visible externally
            return $m;
        }
        if ($class_meta->{parent}) {
            my $parent = $env->lookup('&' . $class_meta->{parent});
            return $self->_find_method($parent, $method_name) if $parent;
        }
        return undef;
    }

    method _call_method_on ($obj, $class_meta, $method, @args) {
        my $call_env = Crayon::Environment->new(parent => $method->{env} // $env);

        # Bind $self
        $call_env->define('$self', $obj);

        # Bind field variables into scope
        for my $field_name (keys $obj->{fields}->%*) {
            $call_env->define($field_name, $obj->{fields}{$field_name});
        }

        # Bind signature params
        if (my $sig = $method->{signature}) {
            my $arg_idx = 0;
            for my $param ($sig->{params}->@*) {
                if ($param->{type} eq 'ScalarParam') {
                    my $name = '$' . ($param->{name} // '_');
                    if ($arg_idx < @args) {
                        $call_env->define($name, $args[$arg_idx++]);
                    } elsif ($param->{default}) {
                        $call_env->define($name, $self->eval($param->{default}));
                    }
                } elsif ($param->{type} eq 'SlurpyParam') {
                    my $name = $param->{sigil} . ($param->{name} // '_');
                    $call_env->define($name, [ @args[$arg_idx .. $#args] ]);
                    $arg_idx = @args;
                }
            }
        }

        my $prev = $env;
        $env = $call_env;
        my $result;
        eval {
            $result = $self->eval($method->{body});
        };

        # Sync field mutations back to object
        for my $field_name (keys $obj->{fields}->%*) {
            if ($call_env->exists($field_name)) {
                $obj->{fields}{$field_name} = $call_env->lookup($field_name);
            }
        }

        $env = $prev;

        if ($@) {
            if (ref $@ eq 'HASH' && $@->{type} eq 'return') {
                return $@->{value};
            }
            die $@;
        }

        return $result;
    }
```

Update `eval_MethodCall` to support class method calls (`Class->new`):

```perl
    method eval_MethodCall ($node) {
        my $invocant_ast = $node->{invocant};
        my $invocant;

        # Check if invocant is a class name (bareword / identifier)
        if ($invocant_ast->{type} eq 'Call' && !$invocant_ast->{args} && !$invocant_ast->{sigiled}) {
            # Could be a class name like Point->new
            my $class_key = '&' . $invocant_ast->{name};
            if ($env->exists($class_key)) {
                my $class_meta = $env->lookup($class_key);
                if (ref $class_meta eq 'HASH' && $class_meta->{type} eq '_CrayonClass') {
                    my $method_name = ref $node->{method} ? $self->eval($node->{method}) : $node->{method};
                    my @args = map { $self->eval($_) } ($node->{args} // [])->@*;
                    if ($method_name eq 'new') {
                        return $self->_construct_object($class_meta, @args);
                    }
                    # Class method (static)
                    die "Cannot call '$method_name' as class method on $class_meta->{name}\n";
                }
            }
        }

        $invocant = $self->eval($invocant_ast);

        # $coderef->(args)
        if (!defined $node->{method}) {
            die "Not a CODE reference\n" unless ref $invocant eq 'HASH' && $invocant->{type} eq '_CrayonSub';
            my @args = map { $self->eval($_) } ($node->{args} // [])->@*;
            return $self->_call_sub($invocant, @args);
        }

        my $method_name = ref $node->{method} eq 'HASH' ? $self->eval($node->{method}) : $node->{method};
        my @args = map { $self->eval($_) } ($node->{args} // [])->@*;

        if (ref $invocant eq 'HASH' && $invocant->{type} eq '_CrayonObject') {
            return $self->_dispatch_method($invocant, $method_name, @args);
        }

        die "Cannot call method '$method_name' on non-object\n";
    }
```

Also add `eval_FieldDeclaration` and handle it being a no-op at class body eval time (already handled by `_register_field`):

```perl
    method eval_FieldDeclaration ($node) {
        # Fields are registered during class evaluation, not executed
        return undef;
    }

    method eval_MethodDeclaration ($node) {
        # Methods are registered during class evaluation, not executed standalone
        # Unless we're outside a class body (shouldn't happen, but safe fallback)
        return undef;
    }
```

- [ ] **Step 5: Add method call transform for arrow syntax**

Add to `lib/Crayon/Transform.pm`:

```perl
sub _transform_method_call_expression ($node, $source) {
    my $invocant_node = _child_by_field($node, 'invocant');
    my $args_node     = _child_by_field($node, 'arguments');

    my $invocant = _transform_node($invocant_node, $source);

    # Method name is an unnamed child token
    my $method_name;
    for my $child (_all_children($node)) {
        if ($child->type eq 'method') {
            $method_name = _text($child, $source);
            last;
        }
    }
    # Fallback: scan for bareword after ->
    if (!$method_name) {
        my $saw_arrow = 0;
        for my $child (_all_children($node)) {
            if (!$child->is_named && _text($child, $source) eq '->') {
                $saw_arrow = 1;
                next;
            }
            if ($saw_arrow && !$child->is_named) {
                $method_name = _text($child, $source);
                last if $method_name =~ /^[a-zA-Z_]/;
            }
        }
    }

    my @args;
    if ($args_node) {
        for my $child (_named_children($args_node)) {
            push @args, _transform_node($child, $source);
        }
    }

    MethodCall($invocant, $method_name, \@args, 0);
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `perl -Ilib -It/lib t/07-classes.t`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/Crayon/Transform.pm lib/Crayon/Interpreter.pm t/07-classes.t
git commit -m "feat: class/method/field support with :param, :reader, :writer, :isa, and ADJUST"
```

---

### Task 11: Roles

**Files:**
- Create: `t/08-roles.t`
- Modify: `lib/Crayon/Interpreter.pm`

- [ ] **Step 1: Write the failing test**

```perl
# t/08-roles.t
use v5.42;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Crayon::Test qw[ crayon_eval crayon_output ];

# Basic role composition
is crayon_output('
    role Greetable {
        method greet () { say "hello from " . $self->name }
    }

    class Person :does(Greetable) {
        field $name :param :reader;
    }

    my $p = Person->new(name => "Alice");
    $p->greet
'), "hello from Alice\n", 'role composition with :does';

# Role with field
is crayon_output('
    role Tagged {
        field $tag :param :reader = "none";
    }

    class Item :does(Tagged) {
        field $name :param :reader;
    }

    my $i = Item->new(name => "widget", tag => "sale");
    say $i->name;
    say $i->tag
'), "widget\nsale\n", 'role contributes fields';

# Multiple roles
is crayon_output('
    role Printable {
        method to_string () { "Printable" }
    }

    role Serializable {
        method serialize () { "Serializable" }
    }

    class Doc :does(Printable) :does(Serializable) {
        field $title :param :reader;
    }

    my $d = Doc->new(title => "test");
    say $d->to_string;
    say $d->serialize
'), "Printable\nSerializable\n", 'multiple roles';

done_testing;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib -It/lib t/08-roles.t`
Expected: FAIL — role composition not implemented

- [ ] **Step 3: Add role support to interpreter**

Add to `lib/Crayon/Interpreter.pm`:

```perl
    method eval_RoleDeclaration ($node) {
        my $role_name = $node->{name};

        my $role_meta = +{
            type    => '_CrayonRole',
            name    => $role_name,
            fields  => [],
            methods => +{},
            adjusts => [],
        };

        my $prev = $env;
        $env = $env->child;
        $env->define('$__class_meta__', $role_meta);

        if ($node->{body}) {
            for my $stmt ($node->{body}{statements}{statements}->@*) {
                my $type = $stmt->{type};
                if ($type eq 'FieldDeclaration') {
                    $self->_register_field($role_meta, $stmt);
                } elsif ($type eq 'MethodDeclaration') {
                    $self->_register_method($role_meta, $stmt);
                }
            }
        }

        $env = $prev;
        $env->define('&' . $role_name, $role_meta);
        return $role_meta;
    }
```

Update `eval_ClassDeclaration` to handle `:does(RoleName)` attribute and compose roles:

Add after class_meta creation and before body evaluation:

```perl
    method eval_ClassDeclaration ($node) {
        my $class_name = $node->{name};

        my $parent_class;
        my @roles;
        if ($node->{attributes}) {
            for my $attr ($node->{attributes}->@*) {
                if ($attr->{name} eq 'isa' && $attr->{expression}) {
                    $parent_class = $attr->{expression}{value};
                }
                if ($attr->{name} eq 'does' && $attr->{expression}) {
                    push @roles, $attr->{expression}{value};
                }
            }
        }

        my $class_meta = +{
            type       => '_CrayonClass',
            name       => $class_name,
            parent     => $parent_class,
            roles      => \@roles,
            fields     => [],
            methods    => +{},
            adjusts    => [],
        };

        my $prev = $env;
        $env = $env->child;
        $env->define('$__class_meta__', $class_meta);

        if ($node->{body}) {
            for my $stmt ($node->{body}{statements}{statements}->@*) {
                my $type = $stmt->{type};
                if ($type eq 'FieldDeclaration') {
                    $self->_register_field($class_meta, $stmt);
                } elsif ($type eq 'MethodDeclaration') {
                    $self->_register_method($class_meta, $stmt);
                } elsif ($type eq 'SubroutineDeclaration' && ($stmt->{name} eq 'ADJUST' || $stmt->{name} eq 'BUILD')) {
                    push $class_meta->{adjusts}->@*, +{
                        body => $stmt->{body},
                        env  => $env,
                    };
                } elsif ($type eq 'ExpressionStatement') {
                    $self->eval($stmt);
                }
            }
        }

        # Compose roles
        for my $role_name (@roles) {
            my $role = $env->lookup('&' . $role_name);
            die "Role '$role_name' not found\n" unless $role;
            die "'$role_name' is not a role\n" unless $role->{type} eq '_CrayonRole';
            $self->_compose_role($class_meta, $role);
        }

        $env = $prev;

        $env->define('&' . $class_name, $class_meta);

        $class_meta->{methods}{new} = +{
            type    => '_CrayonBuiltinMethod',
            name    => 'new',
            handler => sub ($self_obj, @args) {
                $self->_construct_object($class_meta, @args);
            },
        };

        return $class_meta;
    }

    method _compose_role ($class_meta, $role) {
        # Add role fields (unless already defined)
        my %existing_fields = map { $_->{name} => 1 } $class_meta->{fields}->@*;
        for my $field ($role->{fields}->@*) {
            unless ($existing_fields{$field->{name}}) {
                push $class_meta->{fields}->@*, $field;
            }
        }

        # Add role methods (unless already defined — class wins)
        for my $method_name (keys $role->{methods}->%*) {
            unless (exists $class_meta->{methods}{$method_name}) {
                $class_meta->{methods}{$method_name} = $role->{methods}{$method_name};
            }
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `perl -Ilib -It/lib t/08-roles.t`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/Crayon/Interpreter.pm t/08-roles.t
git commit -m "feat: role declaration and composition with :does"
```

---

### Task 12: CLI Entry Point + Use Declarations

**Files:**
- Create: `bin/crayon`
- Modify: `lib/Crayon/Transform.pm`
- Modify: `lib/Crayon/Interpreter.pm`

- [ ] **Step 1: Write the CLI script**

```perl
#!/usr/bin/env perl
# bin/crayon — Crayon interpreter entry point
use v5.42;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Crayon;

my $file = shift @ARGV or die "Usage: crayon <file.pl>\n";
my $source = do { local $/; open my $fh, '<', $file or die "Cannot open $file: $!\n"; <$fh> };

Crayon::eval_source($source);
```

- [ ] **Step 2: Add use/no declaration transform handler**

Add to `lib/Crayon/Transform.pm`:

```perl
sub _transform_use_statement ($node, $source) {
    my $keyword = _first_anon_keyword($node, $source) // 'use';
    my $module_node  = _child_by_field($node, 'module');
    my $version_node = _child_by_field($node, 'version');

    my $module  = $module_node ? _text($module_node, $source) : undef;
    my $version = $version_node ? _text($version_node, $source) : undef;

    # Collect import list from remaining named children
    my @imports;
    for my $child (_named_children($node)) {
        my $ct = $child->type;
        next if $ct eq 'package' || $ct eq 'version';
        push @imports, _transform_node($child, $source);
    }

    UseDeclaration($keyword, $module, $version, @imports ? \@imports : undef);
}

sub _transform_use_version_statement ($node, $source) {
    my $version_node = _child_by_field($node, 'version');
    my $version = $version_node ? _text($version_node, $source) : undef;
    UseDeclaration('use', undef, $version, undef);
}

sub _transform_package_statement ($node, $source) {
    my $name_node    = _child_by_field($node, 'name');
    my $version_node = _child_by_field($node, 'version');
    my $name = _text($name_node, $source);
    my $version = $version_node ? _text($version_node, $source) : undef;

    my $body;
    for my $child (_named_children($node)) {
        if ($child->type eq 'block') {
            $body = _transform_node($child, $source);
            last;
        }
    }

    PackageDeclaration($name, $version, $body);
}
```

- [ ] **Step 3: Add use/package interpreter handlers**

Add to `lib/Crayon/Interpreter.pm`:

```perl
    method eval_UseDeclaration ($node) {
        # For now, silently ignore use/no declarations
        # The interpreter doesn't load external modules
        return undef;
    }

    method eval_PackageDeclaration ($node) {
        # Simple package support — set current package name
        if ($node->{body}) {
            return $self->eval($node->{body});
        }
        return undef;
    }
```

- [ ] **Step 4: Make CLI executable and test it**

Run:
```bash
chmod +x bin/crayon
echo 'say "Hello from Crayon!"' > /tmp/test_crayon.pl
perl -Ilib bin/crayon /tmp/test_crayon.pl
```
Expected: `Hello from Crayon!`

- [ ] **Step 5: Commit**

```bash
git add bin/crayon lib/Crayon/Transform.pm lib/Crayon/Interpreter.pm
git commit -m "feat: CLI entry point and use/package declaration support"
```

---

### Task 13: Constructors, Dereference, and Try/Catch

**Files:**
- Modify: `lib/Crayon/Transform.pm`
- Modify: `lib/Crayon/Interpreter.pm`
- Create: `t/09-misc.t`

- [ ] **Step 1: Write the failing test**

```perl
# t/09-misc.t
use v5.42;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Crayon::Test qw[ crayon_eval crayon_output ];

# Array ref
is crayon_eval('my $a = [1, 2, 3]; $a->[1]'), 2, 'array ref and deref';

# Hash ref
is crayon_eval('my $h = +{a => 1, b => 2}; $h->{b}'), 2, 'hash ref and deref';

# Postfix deref
is crayon_output('my $a = [10, 20, 30]; say $_ for $a->@*'), "10\n20\n30\n", 'postfix array deref';

# Try/catch
is crayon_eval('
    my $result;
    try {
        die "oops";
    } catch ($e) {
        $result = "caught: $e";
    }
    $result
'), "caught: oops\n", 'try/catch';

# Try/catch/finally
is crayon_output('
    try {
        die "fail";
    } catch ($e) {
        say "caught";
    } finally {
        say "done";
    }
'), "caught\ndone\n", 'try/catch/finally';

# Nested data
is crayon_eval('
    my $data = +{
        users => [
            +{ name => "Alice", age => 30 },
            +{ name => "Bob",   age => 25 },
        ],
    };
    $data->{users}->[0]->{name}
'), 'Alice', 'nested data structure access';

done_testing;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `perl -Ilib -It/lib t/09-misc.t`
Expected: FAIL

- [ ] **Step 3: Add constructor and deref transform handlers**

Add to `lib/Crayon/Transform.pm`:

```perl
# ---- Constructors ----

sub _transform_anonymous_array_expression ($node, $source) {
    my @elements;
    for my $child (_named_children($node)) {
        push @elements, _transform_node($child, $source);
    }
    ArrayRef(\@elements);
}

sub _transform_anonymous_hash_expression ($node, $source) {
    my @elements;
    for my $child (_named_children($node)) {
        push @elements, _transform_node($child, $source);
    }
    HashRef(\@elements);
}

# ---- Postfix dereference ----

sub _transform_array_deref_expression ($node, $source) {
    my $target_node = _child_by_field($node, 'arrayref');
    my $target = $target_node
        ? _transform_node($target_node, $source)
        : _transform_node((_named_children($node))[0], $source);
    Dereference($target, '@');
}

sub _transform_hash_deref_expression ($node, $source) {
    my @children = _named_children($node);
    Dereference(_transform_node($children[0], $source), '%');
}

sub _transform_scalar_deref_expression ($node, $source) {
    my @children = _named_children($node);
    Dereference(_transform_node($children[0], $source), '$');
}

# ---- Try/Catch ----

sub _transform_try_statement ($node, $source) {
    my $try_block     = _child_by_field($node, 'try_block');
    my $catch_expr    = _child_by_field($node, 'catch_expr');
    my $catch_block   = _child_by_field($node, 'catch_block');
    my $finally_block = _child_by_field($node, 'finally_block');

    my $catch_var;
    if ($catch_expr) {
        $catch_var = _transform_node($catch_expr, $source);
    }

    TryCatch(
        _transform_node($try_block, $source),
        $catch_var,
        $catch_block ? _transform_node($catch_block, $source) : undef,
        $finally_block ? _transform_node($finally_block, $source) : undef,
    );
}

# ---- Defer ----

sub _transform_defer_statement ($node, $source) {
    my $block_node = _child_by_field($node, 'block');
    Defer(_transform_node($block_node, $source));
}

# ---- Map/Grep ----

sub _transform_map_grep_expression ($node, $source) {
    my $callback = _child_by_field($node, 'callback');
    my $list     = _child_by_field($node, 'list');

    my $func_name;
    for my $child (_all_children($node)) {
        if (!$child->is_named) {
            my $text = _text($child, $source);
            if ($text eq 'map' || $text eq 'grep') {
                $func_name = $text;
                last;
            }
        }
    }
    $func_name //= 'map';

    my $block = $callback ? _transform_node($callback, $source) : undef;
    my @args;
    if ($list) {
        push @args, _transform_node($list, $source);
    }

    Call($func_name, undef, \@args, $block, 0);
}
```

- [ ] **Step 4: Add constructor and deref interpreter handlers**

Add to `lib/Crayon/Interpreter.pm`:

```perl
    method eval_ArrayRef ($node) {
        my @elements = map { $self->eval($_) } ($node->{elements} // [])->@*;
        return \@elements;
    }

    method eval_HashRef ($node) {
        my @elements = map { $self->eval($_) } ($node->{elements} // [])->@*;
        return +{ @elements };
    }

    method eval_Dereference ($node) {
        my $target = $self->eval($node->{target});
        my $sigil = $node->{sigil};
        if ($sigil eq '@') { return ref $target eq 'ARRAY' ? @$target : die "Not an ARRAY ref\n" }
        if ($sigil eq '%') { return ref $target eq 'HASH' ? %$target : die "Not a HASH ref\n" }
        if ($sigil eq '$') { return $$target }
        die "Unsupported dereference sigil: $sigil\n";
    }

    method eval_TryCatch ($node) {
        my $result;
        my $err;
        eval {
            $result = $self->eval($node->{try_block});
        };
        if ($@) {
            $err = $@;
            if ($node->{catch_block}) {
                my $prev = $env;
                $env = $env->child;
                if ($node->{catch_var}) {
                    my $key = $node->{catch_var}{sigil} . $node->{catch_var}{name};
                    $env->define($key, $err);
                }
                $result = $self->eval($node->{catch_block});
                $env = $prev;
            }
        }
        if ($node->{finally_block}) {
            $self->eval($node->{finally_block});
        }
        return $result;
    }

    method eval_Defer ($node) {
        # Defer blocks are tricky — store for end-of-scope execution
        # For now, simplified: just register it (full implementation would use scope guards)
        warn "defer not fully implemented yet\n";
        return undef;
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `perl -Ilib -It/lib t/09-misc.t`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/Crayon/Transform.pm lib/Crayon/Interpreter.pm t/09-misc.t
git commit -m "feat: array/hash refs, postfix deref, try/catch/finally"
```

---

### Task 14: Integration Test

**Files:**
- Create: `t/10-integration.t`
- Create: `examples/point.pl`

- [ ] **Step 1: Write the integration test with a realistic program**

```perl
# examples/point.pl
class Point {
    field $x :param :reader :writer;
    field $y :param :reader :writer;

    method magnitude () {
        sqrt($x**2 + $y**2)
    }

    method to_string () {
        "Point($x, $y)"
    }
}

class Point3D :isa(Point) {
    field $z :param :reader :writer;

    method magnitude () {
        sqrt($x**2 + $y**2 + $z**2)
    }

    method to_string () {
        "Point3D($x, $y, $z)"
    }
}

my $p = Point->new(x => 3, y => 4);
say $p->to_string;
say "magnitude: " . $p->magnitude;

my $p3 = Point3D->new(x => 1, y => 2, z => 2);
say $p3->to_string;
say "magnitude: " . $p3->magnitude;
```

```perl
# t/10-integration.t
use v5.42;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Crayon::Test qw[ crayon_output ];

# Full Point class example
{
    my $source = do {
        local $/;
        open my $fh, '<', 'examples/point.pl' or die "Cannot open examples/point.pl: $!";
        <$fh>
    };
    my $output = crayon_output($source);
    like $output, qr/Point\(3, 4\)/, 'Point to_string';
    like $output, qr/magnitude: 5/, 'Point magnitude';
    like $output, qr/Point3D\(1, 2, 2\)/, 'Point3D to_string';
    like $output, qr/magnitude: 3/, 'Point3D magnitude';
}

# Closures + higher-order functions
{
    my $output = crayon_output('
        sub apply ($fn, $val) { $fn->($val) }
        my $double = sub ($x) { $x * 2 };
        say apply($double, 21)
    ');
    is $output, "42\n", 'higher-order functions';
}

# Role composition with method override
{
    my $output = crayon_output('
        role Describable {
            method describe () { "I am " . $self->name }
        }

        class Thing :does(Describable) {
            field $name :param :reader;
        }

        my $t = Thing->new(name => "widget");
        say $t->describe
    ');
    is $output, "I am widget\n", 'role composition end-to-end';
}

done_testing;
```

- [ ] **Step 2: Run the full test suite**

Run: `prove -Ilib -It/lib t/`
Expected: All tests pass across all test files.

- [ ] **Step 3: Commit**

```bash
git add examples/point.pl t/10-integration.t
git commit -m "feat: integration tests and example programs"
```

---

## Summary

| Task | What It Delivers |
|---|---|
| 1 | Project setup, dependencies, grammar build |
| 2 | AST node constructors (52 types) |
| 3 | Text::TreeSitter integration, test helpers |
| 4 | CST→AST transform for literals |
| 5 | Environment, interpreter core, literal evaluation |
| 6 | Variables, assignment, subscripts, scoping |
| 7 | All operators (binary, unary, postfix, ternary) |
| 8 | Control flow (if/while/for/foreach, postfix, loop control) |
| 9 | Subroutines, signatures, closures, anonymous subs |
| 10 | Classes, methods, fields, inheritance, ADJUST |
| 11 | Roles with :does composition |
| 12 | CLI entry point, use/package declarations |
| 13 | Array/hash refs, postfix deref, try/catch |
| 14 | Integration tests with realistic programs |

After Task 14, you have a working Crayon interpreter that can parse and evaluate Perl 5.42 subset programs with classes, roles, methods, fields, signatures, closures, and control flow — ready for MXCL runtime experiments.
