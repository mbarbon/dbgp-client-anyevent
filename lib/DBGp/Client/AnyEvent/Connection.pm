package DBGp::Client::AnyEvent::Connection;

use strict;
use warnings;

use AnyEvent::Handle;
use DBGp::Client::AsyncConnection;
use Scalar::Util qw(weaken blessed);

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        handle      => undef,
        connection  => DBGp::Client::AsyncConnection->new(socket => $args{socket}),
    }, $class;
    my $weak_self = $self;
    weaken($weak_self);
    my $handle = AnyEvent::Handle->new(
        fh          => $args{socket},
        on_error    => sub {
            my ($handle, $fatal, $message) = @_;

            $weak_self->{handle} = undef;
            $handle->destroy;
            $weak_self->{connection}->closed;
        },
        on_read     => sub {
            my ($handle) = @_;

            $weak_self->{connection}->add_data($handle->{rbuf});
            substr $handle->{rbuf}, 0, length($handle->{rbuf}), ''
                if defined $handle->{rbuf};
        },
        on_eof      => sub {
            my ($handle) = @_;

            $weak_self->{handle} = undef;
            $handle->destroy;
            $weak_self->{connection}->closed;
        },
    );

    $self->{handle} = $handle;

    return $self;
}

sub DESTROY {
    my ($self) = @_;

    $self->{handle}->destroy if $self->{handle} && !$self->{handle}->destroyed;
}

sub init { $_[0]->{connection}->init }

sub send_command {
    my ($self, $callback_or_condvar, @rest) = @_;
    my ($condvar, $callback);

    if (!defined $callback_or_condvar) {
        $condvar = AnyEvent->condvar;
        $callback = sub { $condvar->send($_[0]) };
    } elsif (ref $callback_or_condvar eq 'CODE') {
        $condvar = AnyEvent->condvar;
        $callback = sub { $condvar->send($_[0]); $callback_or_condvar->($_[0]); };
    } elsif (blessed $callback_or_condvar && $callback_or_condvar->isa('AnyEvent::CondVar')) {
        $condvar = $callback_or_condvar;
        $callback = sub { $condvar->send($_[0]) };
    } else {
        die "callback_or_condvar can be undefined, a code reference or a condvar";
    }
    $self->{connection}->send_command($callback, @rest);

    return $condvar;
}

1;
