requires 'perl', 'v5.42.0';
requires 'Text::TreeSitter';

on 'test' => sub {
    requires 'Test2::V0';
    requires 'Capture::Tiny';
};
