# Crayon AST Design Specification

## Overview

Crayon is a tree-walking interpreter for a subset of Perl 5.42+, written in Perl. Its purpose is to serve as a Pugs-style experimentation ground for prototyping changes to the Perl 5 core, particularly around MXCL research ideas.

The parser is not hand-written. Crayon uses `tree-sitter-perl` to parse source into a CST, then transforms that CST into the AST defined here. The AST is then walked by the interpreter.

## Architecture

```
Perl 5.42 source → tree-sitter-perl → CST → AST transform → tree-walk interpreter
```

- **Parser**: `tree-sitter-perl` via `Text::TreeSitter` (XS bindings on CPAN)
- **CST→AST transform**: Single recursive walk, pattern-matching on tree-sitter node types
- **Interpreter**: Tree-walking evaluator over the AST
- **Language**: Perl

## Design Decisions

1. **No operator precedence in the AST** — tree-sitter resolves precedence during parsing. `BinaryOp` nodes are flat.
2. **No context sensitivity** — no scalar/list context modeling. The interpreter may add context-like behavior at runtime, but the AST doesn't encode it. This leaves room for experimentation with alternative context models.
3. **Scope resolved at runtime** — variable nodes carry only names, not scope links. The tree-walker maintains an environment/frame chain. This allows experimentation with scoping models.
4. **`if`/`unless` and `while`/`until` collapse** — single node types with a `negated` flag.
5. **`SubroutineDeclaration` and `MethodDeclaration` are separate** — despite similar structure, to allow different dispatch semantics without conditionals in the interpreter.
6. **`true`/`false` are first-class literals** — `Bool` literal type, not runtime `Call` resolution. Matches Perl 5.42 semantics.
7. **Unsupported CST nodes produce clear errors** — anything outside the supported subset dies during the CST→AST transform with a descriptive message.

## Reference Grammar

The file `perlish.bnf` (from a companion Earley+semiring compiler project) serves as the conceptual reference for which constructs are supported. It is not used as parser input.

The file `writing-perl-5.42.md` defines the target Perl dialect, including features like native `class`, lexical methods, postfix dereferencing, signatures, and auto-exported builtins.

## AST Node Types

### Program Structure

#### Program
Top-level node representing a complete source file.
- `body`: StatementSequence

#### StatementSequence
An ordered list of statements.
- `statements`: Statement[]

#### Statement (enum)
One of: Declaration | CompoundStatement | ExpressionStatement | Yada

#### ExpressionStatement
An expression optionally modified by a postfix control keyword.
- `expression`: Expression
- `modifier`: PostfixModifier?

#### PostfixModifier
A trailing `if`, `unless`, `while`, `until`, `for`, or `foreach` clause.
- `keyword`: 'if' | 'unless' | 'while' | 'until' | 'for' | 'foreach'
- `expression`: Expression

#### Block
A brace-delimited sequence of statements.
- `statements`: StatementSequence

---

### Compound Statements

#### Conditional
Covers `if` and `unless` with optional elsif/else chains.
- `condition`: Expression
- `negated`: bool — true for `unless`
- `then_block`: Block
- `elsif_clauses`: ElsifClause[]
- `else_block`: Block?

#### ElsifClause
- `condition`: Expression
- `block`: Block

#### WhileLoop
Covers `while` and `until`.
- `condition`: Expression
- `negated`: bool — true for `until`
- `block`: Block
- `continue_block`: Block?

#### ForeachLoop
Covers both `for` and `foreach` iteration forms.
- `iterator`: Variable? — nil defaults to `$_`
- `list`: Expression
- `block`: Block
- `continue_block`: Block?

#### CStyleForLoop
C-style `for (init; cond; incr)` loop.
- `init`: Expression?
- `condition`: Expression?
- `increment`: Expression?
- `block`: Block

#### TryCatch
Exception handling.
- `try_block`: Block
- `catch_var`: Variable?
- `catch_block`: Block
- `finally_block`: Block?

#### GivenWhen
Covers `given`, `when`, and `default`.
- `keyword`: 'given' | 'when' | 'default'
- `expression`: Expression? — nil for `default`
- `block`: Block

#### Defer
- `block`: Block

---

### Declarations

#### UseDeclaration
`use` and `no` statements.
- `keyword`: 'use' | 'no'
- `module`: string — qualified name
- `version`: string?
- `imports`: Expression[]?

#### VariableDeclaration
`my`, `our`, `state`, `local` variable declarations.
- `declarator`: 'my' | 'our' | 'state' | 'local'
- `variables`: Variable[] — single or list form: `my ($x, $y)`
- `attributes`: Attribute[]?

#### SubroutineDeclaration
Named subroutine definition or forward declaration.
- `declarator`: 'my' | 'our' | 'state' | nil — for lexical subs
- `name`: string
- `prototype`: string?
- `attributes`: Attribute[]?
- `signature`: Signature?
- `body`: Block? — nil for forward declarations

#### MethodDeclaration
Named method definition.
- `declarator`: 'my' | nil — `my method` for lexical/private methods
- `name`: string
- `attributes`: Attribute[]?
- `signature`: Signature?
- `body`: Block

#### ClassDeclaration
Native `class` declaration (Perl 5.42 Corinna-style).
- `name`: string — qualified
- `version`: string?
- `attributes`: Attribute[]?
- `body`: Block? — nil for statement form without block

#### RoleDeclaration
Role declaration (for composition-based OO experimentation).
- `name`: string
- `version`: string?
- `attributes`: Attribute[]?
- `body`: Block?

#### FieldDeclaration
`field` declarations inside classes/roles.
- `variable`: Variable
- `attributes`: Attribute[]? — includes `:param`, `:reader`, `:writer`
- `default`: Expression?

#### PackageDeclaration
Traditional `package` declaration.
- `name`: string — qualified
- `version`: string?
- `body`: Block? — nil for statement form

#### Signature
Subroutine/method signature.
- `params`: SignatureParam[]

#### SignatureParam (enum)
One of: ScalarParam | SlurpyParam

#### ScalarParam
- `name`: string? — nil for anonymous `$`
- `default`: Expression?
- `named`: bool — true for `:$foo` style named params

#### SlurpyParam
- `sigil`: '@' | '%'
- `name`: string?

#### Attribute
- `name`: string
- `expression`: Expression? — the `(args)` part

---

### Expressions

#### Literal (enum)
One of: Integer | Float | String | Regex | QuotedWords | Version | Bool | Undef | SpecialLiteral

#### Integer
- `value`: string — preserves original form (0x, 0b, etc.)

#### Float
- `value`: string

#### String
- `value`: string
- `interpolate`: bool — true for double-quoted/backtick

#### Regex
- `pattern`: string
- `replacement`: string? — for s/// and tr///
- `flags`: string
- `kind`: 'm' | 'qr' | 's' | 'tr' | 'y'

#### QuotedWords
- `words`: string[]

#### Version
- `value`: string

#### Bool
- `value`: bool

#### Undef
(no fields)

#### SpecialLiteral
- `kind`: '__FILE__' | '__LINE__' | '__PACKAGE__'

#### Variable
- `sigil`: '$' | '@' | '%' | '*' | '$#'
- `name`: string — without sigil
- `namespace`: string? — for qualified `Foo::Bar::baz`

#### BinaryOp
All binary operators. Precedence already resolved by tree-sitter.
- `operator`: string — '+', 'eq', '&&', 'and', 'isa', etc.
- `left`: Expression
- `right`: Expression

#### UnaryOp
Prefix unary operators.
- `operator`: string — '-', '!', 'not', '~', '++', '--', '\' (ref)
- `operand`: Expression

#### PostfixOp
Postfix unary operators.
- `operator`: string — '++', '--'
- `operand`: Expression

#### Ternary
- `condition`: Expression
- `then_expr`: Expression
- `else_expr`: Expression

#### Assignment
- `operator`: string — '=', '+=', '//=', etc.
- `target`: Expression
- `value`: Expression

#### Call
Function or builtin invocation.
- `name`: string
- `namespace`: string? — for qualified calls
- `args`: Expression[]?
- `block`: Block? — block-first form: `map { ... } @list`
- `sigiled`: bool — `&foo` style

#### MethodCall
Method invocation on an object.
- `invocant`: Expression
- `method`: string | Variable — Variable for `$obj->$method_ref()`
- `args`: Expression[]?
- `sigiled`: bool — `->&method` style

#### Subscript
Array/hash element or slice access.
- `target`: Expression
- `index`: Expression | ExpressionList
- `kind`: 'array' | 'hash' — `[]` vs `{}`
- `arrow`: bool — `$x->[0]` vs `$x[0]`

#### Dereference
Postfix dereference: `$ref->@*`, `$ref->%*`, etc.
- `target`: Expression
- `sigil`: '$' | '@' | '%' | '&' | '*' | '$#'

#### PostfixSlice
Postfix slice: `$ref->@[0,1]`, `$ref->@{qw[foo bar]}`.
- `target`: Expression
- `sigil`: '@' | '%'
- `index`: ExpressionList
- `kind`: 'array' | 'hash'

#### ArrayRef
Anonymous array reference constructor `[...]`.
- `elements`: Expression[]?

#### HashRef
Anonymous hash reference constructor `+{...}` / `{...}`.
- `elements`: Expression[]?

#### AnonymousSub
Anonymous subroutine or method.
- `signature`: Signature?
- `prototype`: string?
- `attributes`: Attribute[]?
- `body`: Block
- `kind`: 'sub' | 'method'

#### DoExpression
`do BLOCK` or `do EXPR` (file).
- `kind`: 'block' | 'file'
- `operand`: Block | Expression

#### ParenExpression
Parenthesized expression.
- `expression`: Expression

#### ExpressionList
Comma-separated expression list.
- `expressions`: Expression[]
- `trailing_comma`: bool

#### LoopControl
`last`, `next`, `redo`, `goto`, `return`.
- `keyword`: 'last' | 'next' | 'redo' | 'goto' | 'return'
- `label`: string? — for `last LABEL`
- `expression`: Expression? — for `return $value`

#### Yada
The `...` (yada-yada) operator. No fields.

---

## Node Count Summary

| Category | Count |
|---|---|
| Program structure | 6 |
| Compound statements | 8 |
| Declarations | 14 |
| Expressions | 24 |
| **Total** | **52** |

## What Is NOT in This AST

These are explicitly out of scope for the initial implementation:

- **String interpolation** — handled as a runtime concern when evaluating `String` nodes with `interpolate: true`
- **Regex internals** — the pattern is an opaque string passed to Perl's regex engine
- **Heredocs** — may be handled by tree-sitter or a preprocessor; the AST sees them as `String` nodes
- **`format`/`write`** — deprecated, not supported
- **`BEGIN`/`END`/`CHECK`/`INIT`/`UNITCHECK`** — phaser blocks excluded for now
- **Context sensitivity** — no scalar/list context in the AST; runtime experimentation area
- **Scope resolution** — no lexical binding links; runtime experimentation area
- **`eval` (string form)** — potential future addition
- **Typeglob manipulation** — `*foo = \&bar` etc., low priority
