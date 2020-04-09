use strict;
use warnings;
package WebService::Paycor;

use HTTP::Thin;
use HTTP::Request::Common qw/GET DELETE PUT POST/;
use HTTP::CookieJar;
use JSON;
use URI;
use Ouch;
use Digest::HMAC_SHA1;
use Moo;

=head1 NAME

WebService::Paycor - A simple client to L<Paycor's|https://www.paycor.com> REST API.

=head1 SYNOPSIS

 use WebService::Paycor;

 my $pc = WebService::Paycor->new(api_key => 'XXXXXXXXXXxxxxxxxxxxxx');

 my $categories = $pc->get('categories');

=head1 DESCRIPTION

A light-weight wrapper for Paycor's RESTful API (Documentation for this API may only be requested from Paycor directly.). This wrapper basically hides the request cycle from you so that you can get down to the business of using the API. It doesn't attempt to manage the data structures or objects the web service interfaces with.

The module takes care of all of these things for you:

=over 4

=item Adding authentication headers

C<WebService::Paycor> adds the authentication header of the type "paycorapi: <lt>Public Key<gt> <lt>HMAC SHA1 Digest<gt>" to each request.

=item Adding api version number to URLs

C<WebService::Paycor> prepends the C< $tj-E<gt>version > to each URL you submit.

=item PUT/POST data translated to JSON

When making a request like:

    $tj->post('customers', { customer_id => '27', exemption_type => 'non_exempt', name => 'Andy Dufresne', });

The data in POST request will be translated to JSON using <JSON::to_json>.

=item Response data is deserialized from JSON and returned from each call.

=back

=head1 EXCEPTIONS

All exceptions in C<WebService::Paycor> are handled by C<Ouch>.  A 500 exception C<"Server returned unparsable content."> is returned if Paycor's server returns something that isn't JSON.  If the request isn't successful, then an exception with the code and response and string will be thrown.

=head1 METHODS

The following methods are available.

=head2 new ( params ) 

Constructor.

=over

=item params

A hash of parameters.

=over

=item public_key, private_key

Your public and private keys for accessing Paycor's API.  Required.

=cut

=item debug_flag

Just a spare, writable flag so that users of the object should log debug information, since Paycor will likely ask for request/response pairs when
you're having problems.

    my $sales_tax = $taxjar->get('taxes', $order_information);
    if ($taxjar->debug_flag) {
        $log->info($taxjar->last_response->request->as_string);
        $log->info($taxjar->last_response->content);
    }

=cut

has public_key => (
    is          => 'ro',
    required    => 1,
);

has private_key => (
    is          => 'ro',
    required    => 1,
);

has debug_flag => (
    is          => 'rw',
    required    => 0,
    default     => sub { 0 },
);

=item agent

A LWP::UserAgent compliant object used to keep a persistent cookie_jar across requests.  By default this module uses HTTP::Thin, but you can supply another object when
creating a WebService::Paycor object.

=back

=back

=cut

has agent => (
    is          => 'ro',
    required    => 0,
    lazy        => 1,
    builder     => '_build_agent',
);

sub _build_agent {
    return HTTP::Thin->new( cookie_jar => HTTP::CookieJar->new() )
}

=head2 last_response

The HTTP::Response object from the last request/reponse pair that was sent, for debugging purposes.

=cut

has last_response => (
    is       => 'rw',
    required => 0,
);

=head2 get(path, params)

Performs a C<GET> request, which is used for reading data from the service.

=over

=item path

The path to the REST interface you wish to call. 

=item params

A hash reference of parameters you wish to pass to the web service.  These parameters will be added as query parameters to the URL for you.

=back

=cut

sub get {
    my ($self, $path, $params) = @_;
    my $uri = $self->_create_uri($path);
    $uri->query_form($params);
    return $self->_process_request( GET $uri->as_string );
}

=head2 delete(path)

Performs a C<DELETE> request, deleting data from the service.

=over

=item path

The path to the REST interface you wish to call.

=item params

A hash reference of parameters you wish to pass to the web service.  These parameters will be added as query parameters to the URL for you.

=back

=cut

sub delete {
    my ($self, $path, $params) = @_;
    my $uri = $self->_create_uri($path);
    $uri->query_form($params);
    return $self->_process_request( DELETE $uri->as_string );
}

=head2 put(path, json)

Performs a C<PUT> request, which is used for updating data in the service.

=over

=item path

The path to the REST interface you wish to call.

=item params

A hash reference of parameters you wish to pass to Paycor.  This will be translated to JSON.

=back

=cut

sub put {
    my ($self, $path, $params) = @_;
    my $uri = $self->_create_uri($path);
    my %headers = ( Content => to_json($params), "Content-Type" => 'application/json', );
    return $self->_process_request( POST $uri->as_string,  %headers );
}

=head2 post(path, params, options)

Performs a C<POST> request, which is used for creating data in the service.

=over

=item path

The path to the REST interface you wish to call.

=item params

A hash reference of parameters you wish to pass to Paycor.  They will be encoded as JSON.

=back

=head2 Notes

The path you provide as arguments to the request methods C<get, post, put delete> should not have a leading slash.

=cut

sub post {
    my ($self, $path, $params) = @_;
    my $uri = $self->_create_uri($path);
    my %headers = ( Content => to_json($params), "Content-Type" => 'application/json', );
    return $self->_process_request( POST $uri->as_string, %headers );
}

sub _create_uri {
    my $self = shift;
    my $path = shift;
    my $host = 'https://secure.paycor.com/';
    return URI->new(join '/', $host, $path);
}

sub _add_auth_header {
    my $self    = shift;
    my $request = shift;
    my $message = join "\n",
                    $request->method,
                    '',
                    '',
                    $request->header('Date'),
                    $request->uri;
    my $digest = Digest::HMAC_SHA1->new($self->private_key);
    $digest->add($message);
    $request->header( paycorapi => $self->public_key().' '.$digest->b64digest );
    return;
}

sub _process_request {
    my $self = shift;
    my $request = shift;
    $self->_add_auth_header($request);
    my $response = $self->agent->request($request);
    $response->request($request);
    $self->last_response($response);
    $self->_process_response($response);
}

sub _process_response {
    my $self = shift;
    my $response = shift;
    my $result = eval { from_json($response->decoded_content) }; 
    if ($@) {
        ouch 500, 'Server returned unparsable content.', { error => $@, content => $response->decoded_content };
    }
    elsif ($response->is_success) {
        return from_json($response->content);
    }
    else {
        ouch $response->code, $response->as_string;
    }
}

=head1 PREREQS

L<HTTP::Thin>
L<Ouch>
L<HTTP::Request::Common>
L<HTTP::CookieJar>
L<JSON>
L<URI>
L<Moo>

=head1 SUPPORT

=over

=item Repository

L<https://github.com/perldreamer/WebService-Paycor>

=item Bug Reports

L<https://github.com/perldreamer/WebService-Paycor/issues>

=back

=head1 AUTHOR

Colin Kuskie <colink_at_plainblack_dot_com>

=head1 LEGAL

This module is Copyright 2020 Plain Black Corporation. It is distributed under the same terms as Perl itself. 

=cut

1;
