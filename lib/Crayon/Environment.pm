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
        return $bindings{$name} if exists $bindings{$name};
        die "Undefined variable '$name'\n" unless $parent;
        return $parent->lookup($name);
    }

    method assign ($name, $value) {
        if (exists $bindings{$name}) {
            $bindings{$name} = $value;
            return $value;
        }
        die "Undefined variable '$name'\n" unless $parent;
        return $parent->assign($name, $value);
    }

    method exists ($name) {
        return 1 if exists $bindings{$name};
        return $parent->exists($name) if $parent;
        return 0;
    }

    method child () {
        Crayon::Environment->new(parent => $self);
    }
}

1;
