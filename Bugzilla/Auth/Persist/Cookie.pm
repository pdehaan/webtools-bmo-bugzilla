# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Netscape Communications
# Corporation. Portions created by Netscape are
# Copyright (C) 1998 Netscape Communications Corporation. All
# Rights Reserved.
#
# Contributor(s): Terry Weissman <terry@mozilla.org>
#                 Dan Mosedale <dmose@mozilla.org>
#                 Joe Robins <jmrobins@tgix.com>
#                 Dave Miller <justdave@syndicomm.com>
#                 Christopher Aillon <christopher@aillon.com>
#                 Gervase Markham <gerv@gerv.net>
#                 Christian Reis <kiko@async.com.br>
#                 Bradley Baetz <bbaetz@acm.org>
#                 Erik Stambaugh <erik@dasbistro.com>
#                 Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::Auth::Persist::Cookie;
use strict;
use fields qw();

use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Token;

use Bugzilla::Auth::Login::Cookie qw(login_token);

use List::Util qw(first);

sub new {
    my ($class) = @_;
    my $self = fields::new($class);
    return $self;
}

sub persist_login {
    my ($self, $user) = @_;
    my $dbh = Bugzilla->dbh;
    my $cgi = Bugzilla->cgi;
    my $input_params = Bugzilla->input_params;

    my $ip_addr;
    if ($input_params->{'Bugzilla_restrictlogin'}) {
        $ip_addr = remote_ip();
        # The IP address is valid, at least for comparing with itself in a
        # subsequent login
        trick_taint($ip_addr);
    }

    $dbh->bz_start_transaction();

    my $login_cookie = 
        Bugzilla::Token::GenerateUniqueToken('logincookies', 'cookie');

    $dbh->do("INSERT INTO logincookies (cookie, userid, ipaddr, lastused)
              VALUES (?, ?, ?, NOW())",
              undef, $login_cookie, $user->id, $ip_addr);

    # Issuing a new cookie is a good time to clean up the old
    # cookies.
    $dbh->do("DELETE FROM logincookies WHERE lastused < "
             . $dbh->sql_date_math('LOCALTIMESTAMP(0)', '-',
                                   MAX_LOGINCOOKIE_AGE, 'DAY'));

    $dbh->bz_commit_transaction();

    # Prevent JavaScript from accessing login cookies.
    my %cookieargs = ('-httponly' => 1);

    # Remember cookie only if admin has told so
    # or admin didn't forbid it and user told to remember.
    if ( Bugzilla->params->{'rememberlogin'} eq 'on' ||
         (Bugzilla->params->{'rememberlogin'} ne 'off' &&
          $input_params->{'Bugzilla_remember'} &&
          $input_params->{'Bugzilla_remember'} eq 'on') ) 
    {
        # Not a session cookie, so set an infinite expiry
        $cookieargs{'-expires'} = 'Fri, 01-Jan-2038 00:00:00 GMT';
    }
    if (Bugzilla->params->{'ssl_redirect'}) {
        # Make these cookies only be sent to us by the browser during 
        # HTTPS sessions, if we're using SSL.
        $cookieargs{'-secure'} = 1;
    }

    $cgi->send_cookie(-name => 'Bugzilla_login',
                      -value => $user->id,
                      %cookieargs);
    $cgi->send_cookie(-name => 'Bugzilla_logincookie',
                      -value => $login_cookie,
                      %cookieargs);
}

sub logout {
    my ($self, $param) = @_;

    my $dbh = Bugzilla->dbh;
    my $cgi = Bugzilla->cgi;
    my $input = Bugzilla->input_params;
    $param = {} unless $param;
    my $user = $param->{user} || Bugzilla->user;
    my $type = $param->{type} || LOGOUT_ALL;

    if ($type == LOGOUT_ALL) {
        $dbh->do("DELETE FROM logincookies WHERE userid = ?",
                 undef, $user->id);
        return;
    }

    # The LOGOUT_*_CURRENT options require the current login cookie.
    # If a new cookie has been issued during this run, that's the current one.
    # If not, it's the one we've received.
    my @login_cookies;
    my $cookie = first {$_->name eq 'Bugzilla_logincookie'}
                       @{$cgi->{'Bugzilla_cookie_list'}};
    if ($cookie) {
        push(@login_cookies, $cookie->value);
    }
    else {
        push(@login_cookies, $cgi->cookie("Bugzilla_logincookie"));
    }

    # If we are a webservice using a token instead of cookie
    # then add that as well to the login cookies to delete
    if (my $login_token = $user->authorizer->login_token) {
        push(@login_cookies, $login_token->{'login_token'});
    }

    # Make sure that @login_cookies is not empty to not break SQL statements.
    push(@login_cookies, '') unless @login_cookies;

    # These queries use both the cookie ID and the user ID as keys. Even
    # though we know the userid must match, we still check it in the SQL
    # as a sanity check, since there is no locking here, and if the user
    # logged out from two machines simultaneously, while someone else
    # logged in and got the same cookie, we could be logging the other
    # user out here. Yes, this is very very very unlikely, but why take
    # chances? - bbaetz
    map { trick_taint($_) } @login_cookies;
    @login_cookies = map { $dbh->quote($_) } @login_cookies;
    if ($type == LOGOUT_KEEP_CURRENT) {
        $dbh->do("DELETE FROM logincookies WHERE " .
                 $dbh->sql_in('cookie', \@login_cookies, 1) .
                 " AND userid = ?",
                 undef, $user->id);
    } elsif ($type == LOGOUT_CURRENT) {
        $dbh->do("DELETE FROM logincookies WHERE " .
                 $dbh->sql_in('cookie', \@login_cookies) .
                 " AND userid = ?",
                 undef, $user->id);
    } else {
        die("Invalid type $type supplied to logout()");
    }

    if ($type != LOGOUT_KEEP_CURRENT) {
        clear_browser_cookies();
    }

}

sub clear_browser_cookies {
    my $cgi = Bugzilla->cgi;
    $cgi->remove_cookie('Bugzilla_login');
    $cgi->remove_cookie('Bugzilla_logincookie');
    $cgi->remove_cookie('sudo');
}

1;
