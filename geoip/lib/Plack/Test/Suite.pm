package Plack::Test::Suite;
use strict;
use warnings;
use Digest::MD5;
use File::ShareDir;
use HTTP::Request;
use HTTP::Request::Common;
use LWP::UserAgent;
use Test::More;
use Test::TCP;
use Plack::Loader;
use Plack::Middleware::Lint;
use Plack::Util;
use Try::Tiny;

my $share_dir = try { File::ShareDir::dist_dir('Plack') } || 'share';

# 0: test name
# 1: request generator coderef.
# 2: request handler
# 3: test case for response
our @TEST = (
    [
        'GET',
        sub {
            my $cb = shift;
            my $res = $cb->(GET "http://127.0.0.1/?name=miyagawa");
            is $res->code, 200;
            is $res->header('content_type'), 'text/plain';
            is $res->content, 'Hello, name=miyagawa';
        },
        sub {
            my $env = shift;
            return [
                200,
                [ 'Content-Type' => 'text/plain', ],
                [ 'Hello, ' . $env->{QUERY_STRING} ],
            ];
        },
    ],
    [
        'POST',
        sub {
            my $cb = shift;
            my $res = $cb->(POST "http://127.0.0.1/", [name => 'tatsuhiko']);
            is $res->code, 200;
            is $res->header('Client-Content-Length'), 14;
            is $res->header('Client-Content-Type'), 'application/x-www-form-urlencoded';
            is $res->header('content_type'), 'text/plain';
            is $res->content, 'Hello, name=tatsuhiko';
        },
        sub {
            my $env = shift;
            my $body;
            $env->{'psgi.input'}->read($body, $env->{CONTENT_LENGTH});
            return [
                200,
                [ 'Content-Type' => 'text/plain',
                  'Client-Content-Length' => $env->{CONTENT_LENGTH},
                  'Client-Content-Type' => $env->{CONTENT_TYPE},
              ],
                [ 'Hello, ' . $body ],
            ];
        },
    ],
    [
        'psgi.url_scheme',
        sub {
            my $cb = shift;
            my $res = $cb->(POST "http://127.0.0.1/");
            is $res->code, 200;
            is $res->header('content_type'), 'text/plain';
            is $res->content, 'http';
        },
        sub {
            my $env = $_[0];
            return [
                200,
                [ 'Content-Type' => 'text/plain', ],
                [ $env->{'psgi.url_scheme'} ],
            ];
        },
    ],
    [
        'return glob',
        sub {
            my $cb  = shift;
            my $res = $cb->(GET "http://127.0.0.1/");
            is $res->code, 200;
            is $res->header('content_type'), 'text/plain';
            like $res->content, qr/^package /;
            like $res->content, qr/END_MARK_FOR_TESTING$/;
        },
        sub {
            my $env = shift;
            open my $fh, '<', __FILE__ or die $!;
            return [
                200,
                [ 'Content-Type' => 'text/plain', ],
                $fh,
            ];
        },
    ],
    [
        'filehandle',
        sub {
            my $cb  = shift;
            my $res = $cb->(GET "http://127.0.0.1/foo.jpg");
            is $res->code, 200;
            is $res->header('content_type'), 'image/jpeg';
            is length $res->content, 4745;
        },
        sub {
            my $env = shift;
            open my $fh, '<', "$share_dir/face.jpg";
            return [
                200,
                [ 'Content-Type' => 'image/jpeg', 'Content-Length' => -s $fh ],
                $fh
            ];
        },
    ],
    [
        'bigger file',
        sub {
            my $cb  = shift;
            my $res = $cb->(GET "http://127.0.0.1/kyoto.jpg");
            is $res->code, 200;
            is $res->header('content_type'), 'image/jpeg';
            is length $res->content, 2397701;
            is Digest::MD5::md5_hex($res->content), '9c6d7249a77204a88be72e9b2fe279e8';
        },
        sub {
            my $env = shift;
            open my $fh, '<', "$share_dir/kyoto.jpg";
            return [
                200,
                [ 'Content-Type' => 'image/jpeg', 'Content-Length' => -s $fh ],
                $fh
            ];
        },
    ],
    [
        'handle HTTP-Header',
        sub {
            my $cb  = shift;
            my $res = $cb->(GET "http://127.0.0.1/foo/?dankogai=kogaidan", Foo => "Bar");
            is $res->code, 200;
            is $res->header('content_type'), 'text/plain';
            is $res->content, 'Bar';
        },
        sub {
            my $env = shift;
            return [
                200,
                [ 'Content-Type' => 'text/plain', ],
                [$env->{HTTP_FOO}],
            ];
        },
    ],
    [
        'handle HTTP-Cookie',
        sub {
            my $cb  = shift;
            my $res = $cb->(GET "http://127.0.0.1/foo/?dankogai=kogaidan", Cookie => "foo");
            is $res->code, 200;
            is $res->header('content_type'), 'text/plain';
            is $res->content, 'foo';
        },
        sub {
            my $env = shift;
            return [
                200,
                [ 'Content-Type' => 'text/plain', ],
                [$env->{HTTP_COOKIE}],
            ];
        },
    ],
    [
        'validate env',
        sub {
            my $cb  = shift;
            my $res = $cb->(GET "http://127.0.0.1/foo/?dankogai=kogaidan");
            is $res->code, 200;
            is $res->header('content_type'), 'text/plain';
            is $res->content, join("\n",
                'REQUEST_METHOD:GET',
                'PATH_INFO:/foo/',
                'QUERY_STRING:dankogai=kogaidan',
                'SERVER_NAME:127.0.0.1',
                "SERVER_PORT:" . $res->request->uri->port,
            )."\n";
        },
        sub {
            my $env = shift;
            my $body;
            $body .= $_ . ':' . $env->{$_} . "\n" for qw/REQUEST_METHOD PATH_INFO QUERY_STRING SERVER_NAME SERVER_PORT/;
            return [
                200,
                [ 'Content-Type' => 'text/plain', ],
                [$body],
            ];
        },
    ],
    [
        '% encoding in PATH_INFO',
        sub {
            my $cb  = shift;
            my $res = $cb->(GET "http://127.0.0.1/foo/bar%2cbaz");
            is $res->content, "/foo/bar,baz", "PATH_INFO should be decoded per RFC 3875";
        },
        sub {
            my $env = shift;
            return [
                200,
                [ 'Content-Type' => 'text/plain', ],
                [ $env->{PATH_INFO} ],
            ];
        },
    ],
    [
        '% double encoding in PATH_INFO',
        sub {
            my $cb  = shift;
            my $res = $cb->(GET "http://127.0.0.1/foo/bar%252cbaz");
            is $res->content, "/foo/bar%2cbaz", "PATH_INFO should be decoded only once, per RFC 3875";
        },
        sub {
            my $env = shift;
            return [
                200,
                [ 'Content-Type' => 'text/plain', ],
                [ $env->{PATH_INFO} ],
            ];
        },
    ],
    [
        'SERVER_PROTOCOL is required',
        sub {
            my $cb  = shift;
            my $res = $cb->(GET "http://127.0.0.1/foo/?dankogai=kogaidan");
            is $res->code, 200;
            is $res->header('content_type'), 'text/plain';
            like $res->content, qr{^HTTP/1\.[01]$};
        },
        sub {
            my $env = shift;
            return [
                200,
                [ 'Content-Type' => 'text/plain', ],
                [$env->{SERVER_PROTOCOL}],
            ];
        },
    ],
    [
        'SCRIPT_NAME should not be undef',
        sub {
            my $cb  = shift;
            my $res = $cb->(GET "http://127.0.0.1/foo/?dankogai=kogaidan");
            is $res->content, 1;
        },
        sub {
            my $env = shift;
            my $cont = defined $env->{'SCRIPT_NAME'};
            return [
                200,
                [ 'Content-Type' => 'text/plain', ],
                [$cont],
            ];
        },
    ],
    [
        # PEP-333 says:
        #    If the iterable returned by the application has a close() method,
        #   the server or gateway must call that method upon completion of the
        #   current request, whether the request was completed normally, or
        #   terminated early due to an error. 
        'call close after read file-like',
        sub {
            my $cb  = shift;
            my $res = $cb->(GET "http://127.0.0.1/call_close");
            is($res->content, '1234');
        },
        sub {
            my $env = shift;
            {
                package CalledClose;
                our $closed = -1;
                sub new { $closed = 0; my $i=0; bless \$i, 'CalledClose' }
                sub getline {
                    my $self = shift;
                    return $$self++ < 4 ? $$self : undef;
                }
                sub close     { ::ok(1, 'closed') if defined &::ok }
            }
            return [
                200,
                [ 'Content-Type' => 'text/plain', ],
                CalledClose->new(),
            ];
        },
    ],
    [
        'has errors',
        sub {
            my $cb  = shift;
            my $res = $cb->(GET "http://127.0.0.1/has_errors");
            is $res->content, 1;
        },
        sub {
            my $env = shift;
            my $err = $env->{'psgi.errors'};
            my $has_errors = defined $err;
            return [
                200,
                [ 'Content-Type' => 'text/plain', ],
                [$has_errors]
            ];
        },
    ],
    [
        'status line',
        sub {
            my $cb  = shift;
            my $res = $cb->(GET "http://127.0.0.1/foo/?dankogai=kogaidan");
            is($res->status_line, '200 OK');
        },
        sub {
            my $env = shift;
            return [
                200,
                [ 'Content-Type' => 'text/plain', ],
                [1]
            ];
        },
    ],
    [
        'Do not crash when the app dies',
        sub {
            my $cb  = shift;
            my $res = $cb->(GET "http://127.0.0.1/");
            is $res->code, 500;
        },
        sub {
            my $env = shift;
            die "Throwing an exception from app handler. Server shouldn't crash.";
        },
    ],
    [
        'multi headers',
        sub {
            my $cb  = shift;
            my $req = HTTP::Request->new(
                GET => "http://127.0.0.1/",
            );
            $req->push_header(Foo => "bar");
            $req->push_header(Foo => "baz");
            my $res = $cb->($req);
            is($res->content, "bar, baz");
        },
        sub {
            my $env = shift;
            return [
                200,
                [ 'Content-Type' => 'text/plain', ],
                [ $env->{HTTP_FOO} ]
            ];
        },
    ],
    [
        'no entity headers on 304',
        sub {
            my $cb  = shift;
            my $res = $cb->(GET "http://127.0.0.1/");
            is $res->code, 304;
            is $res->content, '';
            ok ! defined $res->header('content_type'), "No Content-Type";
            ok ! defined $res->header('content_length'), "No Content-Length";
            ok ! defined $res->header('transfer_encoding'), "No Transfer-Encoding";
        },
        sub {
            my $env = shift;
            return [ 304, [], [] ];
        },
    ],
    [
        'REQUEST_URI is set',
        sub {
            my $cb  = shift;
            my $res = $cb->(GET "http://127.0.0.1/foo/bar%20baz?x=a");
            is $res->content, '/foo/bar%20baz?x=a';
        },
        sub {
            my $env = shift;
            return [ 200, [ 'Content-Type' => 'text/plain' ], [ $env->{REQUEST_URI} ] ];
        },
    ],
    [
        'filehandle with path()',
        sub {
            my $cb  = shift;
            my $res = $cb->(GET "http://127.0.0.1/foo.jpg");
            is $res->code, 200;
            is $res->header('content_type'), 'image/jpeg';
            is length $res->content, 4745;
        },
        sub {
            my $env = shift;
            open my $fh, '<', "$share_dir/face.jpg";
            Plack::Util::set_io_path($fh, "$share_dir/face.jpg");
            return [
                200,
                [ 'Content-Type' => 'image/jpeg', 'Content-Length' => -s $fh ],
                $fh
            ];
        },
    ],

);

sub runtests {
    my($class, $runner) = @_;
    for my $test (@TEST) {
        $runner->(@$test);
    }
}

sub run_server_tests {
    my($class, $server, $server_port, $http_port) = @_;

    if (ref $server ne 'CODE') {
        my $server_class = $server;
        $server = sub {
            my($port, $app) = @_;
            my $server = Plack::Loader->load($server_class, port => $port, host => "127.0.0.1");
            $app = Plack::Middleware::Lint->wrap($app);
            $server->run($app);
        }
    }

    test_tcp(
        client => sub {
            my $port = shift;

            my $ua = LWP::UserAgent->new;
            for my $i (0..$#TEST) {
                my $test = $TEST[$i];
                note $test->[0];
                my $cb = sub {
                    my $req = shift;
                    $req->uri->port($http_port || $port);
                    $req->header('X-Plack-Test' => $i);
                    return $ua->request($req);
                };

                $test->[1]->($cb);
            }
        },
        server => sub {
            my $port = shift;
            my $app  = $class->test_app_handler;
            $server->($port, $app);
        },
        port => $server_port,
    );
}

sub test_app_handler {
    return sub {
        my $env = shift;
        $TEST[$env->{HTTP_X_PLACK_TEST}][2]->($env);
    };
}

1;
__END__

=head1 SYNOPSIS

  # TBD See t/Plack-Servet/*.t for now

=head1 DESCRIPTION

Plack::Test::Suite is a test suite to test a new PSGI server implementation.

=head1 AUTHOR

Tokuhiro Matsuo

Tatsuhiko Miyagawa

Kazuho Oku

=cut

END_MARK_FOR_TESTING
