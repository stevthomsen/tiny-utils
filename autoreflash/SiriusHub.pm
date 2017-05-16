package SiriusHub;

# This package provides functionality for interfacing wih Sirius Hub.
# Requests in this package use JSON

use strict;
use lib qw(/sirius/tools/bkscripts/);
use JSON;
use LWP::UserAgent;
use Exporter;
use vars qw(@ISA @EXPORT @EXPORT_OK);

@ISA = ('Exporter');
@EXPORT = qw(autotest_queue autotest_request_test autotest_submit_results);
@EXPORT_OK = qw(JSON_SUCCESS JSON_ERROR TEST_PASS TEST_FAIL);

use constant JSON_SUCCESS => 'ok';
use constant JSON_ERROR   => 'error';
use constant TEST_PASS    => 'Pass';
use constant TEST_FAIL    => 'Fail';

my $debug = undef;
#$debug = 1;

my $timeout = 30;
my $admin_email;
my $server_addr;

if($debug)
{
	$admin_email = 'chris.dickens@hp.com';
	$server_addr = 'http://epgd272.sdd.hp.com:3000';
}
else
{
	$admin_email = 'siriusdevenv@hp.com';
	$server_addr = 'http://git.vcd.hp.com/sirius_hub';
}

sub submit_hash($$);
sub autotest_queue($$);
sub autotest_request_test($$$);
sub autotest_submit_results($$$$;$$$);
sub my_print($);

sub submit_hash($$)
{
	my ($hash_ptr,$url) = @_;
	return(undef,"Hash pointer is undefined") unless($hash_ptr);
	return(undef,"URL to POST must be specified") unless($url);

	my $encoded_json = encode_json($hash_ptr);
	my_print("Sending encoded JSON string: $encoded_json") if($debug);

	my_print("Attempting to contact server: $server_addr$url") if($debug);
	my $ua = LWP::UserAgent->new(timeout => $timeout);
	$ua->default_header('Accept' => 'application/json');
	push @{ $ua->requests_redirectable }, 'POST';

	my $response = $ua->post($server_addr.$url, { json_data => $encoded_json });
	if($response->code == 200 or $response->code == 400)
	{
		my_print("Received the following response: ".$response->content) if($debug);
		my $json_return = decode_json($response->content);
		my %return_hash = %{$json_return};
		return(\%return_hash,undef);
	}
	else
	{
		my_print($response->message) if($debug);
		return(undef,$response->message);
	}
}

sub autotest_queue($$)
{
	my ($product_phase,$package) = @_;
	return(undef,"Product Phase must be specified") unless($product_phase);

	my $url = "/external/autotest/check_queue";
	my %hash = ();

	$product_phase =~ /^(.*)_([^_]*)$/;

	my $product = $1;
	my $hw_phase = $2;

	$hash{product} = $product;
	$hash{hw_phase} = $hw_phase;
	$hash{type} = ($package) ? "package" : "build";

	return submit_hash(\%hash,$url);
}

sub autotest_request_test($$$)
{
	my ($tester_email,$build_or_package_result_id,$package) = @_;
	return(undef,"Tester email must be specified") unless($tester_email);
	return(undef,"Build Result ID or Package Result ID must be specified") unless($build_or_package_result_id);

	my $url = "/external/autotest/request_test";
	my %hash = ();

	$hash{tester_email} = $tester_email;
	$hash{build_result_id} = $build_or_package_result_id unless($package);
	$hash{package_result_id} = $build_or_package_result_id if($package);

	return submit_hash(\%hash,$url);
}

sub autotest_submit_results($$$$;$$$)
{
	my ($hw_test_id,$result,$problems,$comments,$serial_log,$scm_key,$fw_rev) = @_;
	return(undef,"HW Test ID must be specified") unless($hw_test_id);
	return(undef,"Result must be specified") unless($result);

	my $url = "/external/autotest/submit_result";
	my %hash = ();

	$hash{hw_test_id} = $hw_test_id;
	$hash{result} = $result;
	$hash{problems} = $problems;
	$hash{comments} = $comments;
	$hash{serial_log} = $serial_log if(defined($serial_log));
	$hash{scm_key} = $scm_key if(defined($scm_key));
	$hash{fw_rev} = $fw_rev if(defined($fw_rev));

	return submit_hash(\%hash,$url);
}

sub my_print($)
{
	return;
	my ($msg) = @_;
	my $caller = (caller(1))[3]; # Find out who called me
	$caller=~s/^.*:://; # Remove package name

	print("$caller: $msg\n");
}

1;
