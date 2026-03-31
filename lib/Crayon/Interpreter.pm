use v5.42;
use utf8;
use experimental qw[ class ];

use Crayon::Environment;

class Crayon::Interpreter {
    field $env :param = Crayon::Environment->new;

    method eval ($ast) {
        my $type = $ast->{type};
        my $method = "eval_$type";
        $self->$method($ast);
    }

    method eval_Program ($ast) {
        $self->eval($ast->{body});
    }

    method eval_StatementSequence ($ast) {
        my $result;
        for my $stmt ($ast->{statements}->@*) {
            $result = $self->eval($stmt);
        }
        return $result;
    }

    method eval_ExpressionStatement ($ast) {
        $self->eval($ast->{expression});
    }

    method eval_Integer ($ast) {
        my $value = $ast->{value};
        $value =~ s/_//g;
        if ($value =~ /^0x/i) {
            return hex($value);
        }
        if ($value =~ /^0b/i) {
            return oct($value);
        }
        if ($value =~ /^0o/i) {
            return oct("0" . substr($value, 2));
        }
        return 0 + $value;
    }

    method eval_Float ($ast) {
        my $value = $ast->{value};
        $value =~ s/_//g;
        return 0 + $value;
    }

    method eval_String ($ast) {
        my $value = $ast->{value};
        if ($ast->{interpolate}) {
            $value =~ s/\\n/\n/g;
            $value =~ s/\\t/\t/g;
            $value =~ s/\\\\/\\/g;
            $value =~ s/\\"/"/g;
        }
        return $value;
    }

    method eval_Bool ($ast) {
        return $ast->{value};
    }

    method eval_Undef ($ast) {
        return undef;
    }

    method eval_Yada ($ast) {
        die "Unimplemented";
    }

    method eval_SpecialLiteral ($ast) {
        my $kind = $ast->{kind};
        return '(eval)' if $kind eq '__FILE__';
        return 0        if $kind eq '__LINE__';
        return 'main'   if $kind eq '__PACKAGE__';
        die "Unknown special literal '$kind'\n";
    }

    method eval_Call ($ast) {
        my $name = $ast->{name};
        my @args = map { $self->eval($_) } $ast->{args}->@*;

        if ($name eq 'say') {
            say join('', @args);
            return 1;
        }
        if ($name eq 'print') {
            print join('', @args);
            return 1;
        }

        die "Unknown function '$name'\n";
    }
}

1;
