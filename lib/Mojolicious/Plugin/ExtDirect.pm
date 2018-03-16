package Mojolicious::Plugin::ExtDirect;

use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Exception;

use warnings 'FATAL';
no  warnings 'uninitialized'; ## no critic

use RPC::ExtDirect::Config;
use RPC::ExtDirect::API;
use RPC::ExtDirect;

our $VERSION = '0.1.0';

has [qw(api config)];

sub register {
    my ($self, $app, $params) = @_;
    
    my $api    = $params->{api}    || RPC::ExtDirect->get_api();
    my $config = $params->{config} || $api->config;
    
    $self->config($config);
    $self->api($api);
    
    my $routes = $app->routes;
    
    $routes->add_shortcut(extdirect_api => sub { $self->_handle_shortcut('api', @_) });
    $routes->add_shortcut(extdirect_router => sub { $self->_handle_shortcut('router', @_) });
    $routes->add_shortcut(extdirect_events => sub { $self->_handle_shortcut('events', @_) });
    
    return $self;
}

############## PRIVATE METHODS BELOW ##############

sub _handle_shortcut {
    my ($self, $type, $r, $path) = @_;
    
    my $pattern = $r->pattern;
    my $placeholders = $pattern->placeholders;
    
    Mojo::Exception->throw("Route pattern with placeholders is not supported")
        if @$placeholders;
    
    my $full_path = $pattern->render . $path;
    
    if ( $type eq 'api' ) {
        return $r->get($path => sub { $self->_handle_api(@_) });
    }
    elsif ( $type eq 'router' ) {
        $self->config->router_path($full_path);
        return $r->post($path => sub { $self->_handle_router(@_) });
    }
    elsif ( $type eq 'events' ) {
        $self->config->poll_path($full_path);
        return $r->get($path => sub { $self->_handle_events(@_) });
    }
}

sub _handle_api {
    my ($self, $c) = @_;
    
    my $want_json = $c->param('type') eq 'json';
    
    # Get the JavaScript code or JSON blob for API,
    # depending on the query parameter. This feature is not
    # officially supported in Ext Direct spec (yet).
    my $api_def = eval {
        $self->api->get_remoting_api(
            config => $self->config,
            json => $want_json,
        );
    };
    
    Mojo::Exception->throw($@) if $@;
    
    # We need content length in octets. Return content-type is
    # application/javascript, NOT application/json!
    my $content_length = do { use bytes; length $api_def };
    my $content_type   = $want_json ? 'application/json' : 'application/javascript';
    
    $c->res->headers->content_type($content_type);
    $c->res->headers->content_length($content_length);
    
    return $c->render( status => 200, data => $api_def );
}

sub _handle_router {
    my ($self, $c) = @_;
    
    my $config = $self->config;
    my $api = $self->api;
    
    my $router_input = $self->_extract_router_input($c);
    my $env = Mojolicious::Plugin::ExtDirect::Env->new(c => $c);
    
    my $router_class = $config->router_class;
    eval "require $router_class" or Mojo::Exception->throw($@);
    
    my $router = $router_class->new(
        config => $config,
        api    => $api,
    );
    
    my $result = $router->route($router_input, $env);
    
    # Result is in Plack format
    my ($status, $headers, $payload) = @$result;
    
    while ( @$headers ) {
        my $header = shift @$headers;
        my $value = shift @$headers;
        
        $c->res->headers->header($header => $value);
    }
    
    return $c->render( status => $status, data => shift @$payload );
}

sub _handle_events {
    my ($self, $c) = @_;
    
    my $config = $self->config;
    my $api    = $self->api;
    
    my $provider_class = $config->eventprovider_class;
    eval "require $provider_class" or Mojo::Exception->throw($@);
    
    my $env = Mojolicious::Plugin::ExtDirect::Env->new(c => $c);
    
    my $provider = $provider_class->new(
        config => $config,
        api    => $api,
    );
    
    # Polling for events is safe
    my $http_body = $provider->poll($env);
    
    return $c->render( status => 200, json => $http_body );
}

sub _extract_router_input {
    my ($self, $c) = @_;
    
    my $is_form = $c->req->param('extAction') && $c->req->param('extMethod');
    
    if ( not $is_form ) {
        my $postdata = $c->req->body;
        
        return $postdata || undef;
    }
    
    # TODO form/upload handling
    ...
}

# Small utility class, not to be indexed by PAUSE
package
    Mojolicious::Plugin::ExtDirect::Env;

sub new {
    my ($class, %args) = @_;
    
    return bless { %args }, $class;
}

sub http {
    my ($self, $name) = @_;
    
    if ( $name ) {
        return $self->{c}->req->headers->header($name);
    }
    else {
        Mojo::Exception->throw("Env->http() with no arguments should be called in list context")
            unless wantarray;
        
        my $headers = $self->{c}->req->headers;
        
        return @{ $headers->names };
    }
}

sub param {
    my ($self, $name) = @_;
    
    if ( $name ) {
        return $self->{c}->req->param($name);
    }
    else {
        Mojo::Exception->throw("Env->param() with no arguments should be called in list context")
            unless wantarray;
        
        my $params = $self->{c}->req->params;
        
        return @{ $params->names };
    }
}

sub cookie {
    my ($self, $name) = @_;
    
    if ( $name ) {
        return $self->{c}->cookie($name);
    }
    else {
        Mojo::Exception->throw("Env->cookie() with no arguments should be called in list context")
            unless wantarray;
            
        my $cookies = $self->{c}->req->cookies;
        
        return map { $_->name } @$cookies
    }
}

1;

__END__
=pod

=begin readme text

Mojolicious::Plugin::ExtDirect
==============================

=end readme

=for readme stop

=head1 NAME

Mojolicious::Plugin::ExtDirect - RPC::ExtDirect for Mojolicious

=head1 SYNOPSIS

    # Mojolicious application
    package MyApp;
    
    use Mojo::Base 'Mojolicious';
    
    sub startup {
        my ($self) = @_;
        
        $self->plugin('ExtDirect');
        
        my $routes = $self->routes;
        
        $routes->extdirect_api('/direct/api');
        $routes->extdirect_router('/direct/router');
        $routes->extdirect_events('/direct/events');
    }

=head1 DESCRIPTION

=for readme continue

This module provides an L<RPC::ExtDirect> gateway implementation for
L<Mojolicious> environment. It is packaged as a standard Mojolicious plugin.

If you are not familiar with Ext Direct, more information can be found in
L<RPC::ExtDirect::Intro>.

=for readme stop

=begin readme

=head1 INSTALLATION

To install this module type the following:

    perl Makefile.PL
    make && make test
    make install

=end readme

=for readme continue

=head1 BUGS AND LIMITATIONS

At this time there are no known bugs in this module. Please report
problems to the author, patches are always welcome.

Use L<Github tracker|https://github.com/nohuhu/Mojolicious-Plugin-ExtDirect/issues>
to open bug reports. This is the easiest and quickest way to get your
issue fixed.

=for readme continue

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2018 Alex Tokarev E<lt>nohuhu@cpan.orgE<gt>.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself. See L<perlartistic>.

=cut
