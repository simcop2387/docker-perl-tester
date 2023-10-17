requires 'Devel::PatchPerl';
requires 'YAML::XS';

on 'develop' => sub {
    requires 'Perl::Tidy';
};

requires 'LWP::Simple';
requires 'LWP::Protocol::https';
requires 'Path::Tiny';
requires 'IO::Async';
requires 'IO::Async::Function';
requires 'IO::Async::Loop::Epoll';
requires 'Getopt::Long';
requires 'Future';
requires 'Path::Tiny';
requires 'IPC::Run';
requires 'Time::HiRes';
requires 'Syntax::Keyword::Try';
requires 'Time::Piece';
