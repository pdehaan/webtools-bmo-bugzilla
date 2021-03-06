# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TrackingFlags;

use strict;

use base qw(Bugzilla::Extension);

use Bugzilla::Extension::TrackingFlags::Constants;
use Bugzilla::Extension::TrackingFlags::Flag;
use Bugzilla::Extension::TrackingFlags::Flag::Bug;
use Bugzilla::Extension::TrackingFlags::Admin;

use Bugzilla::Bug;
use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Extension::BMO::Data;
use Bugzilla::Field;
use Bugzilla::Install::Filesystem;
use Bugzilla::Product;

our $VERSION = '1';

sub page_before_template {
    my ($self, $args) = @_;
    my $page = $args->{'page_id'};
    my $vars = $args->{'vars'};

    if ($page eq 'tracking_flags_admin_list.html') {
        Bugzilla->user->in_group('admin')
            || ThrowUserError('auth_failure',
                              { group  => 'admin',
                                action => 'access',
                                object => 'administrative_pages' });
        admin_list($vars);

    } elsif ($page eq 'tracking_flags_admin_edit.html') {
        Bugzilla->user->in_group('admin')
            || ThrowUserError('auth_failure',
                              { group  => 'admin',
                                action => 'access',
                                object => 'administrative_pages' });
        admin_edit($vars);
    }
}

sub template_before_process {
    my ($self, $args) = @_;
    my $file = $args->{'file'};
    my $vars = $args->{'vars'};

    if ($file eq 'bug/create/create.html.tmpl'
        || $file eq 'bug/create/create-winqual.html.tmpl')
    {
        $vars->{'tracking_flags'} = Bugzilla::Extension::TrackingFlags::Flag->match({
            product   => $vars->{'product'}->name,
            enter_bug => 1,
            is_active => 1,
        });

        $vars->{'tracking_flag_types'} = FLAG_TYPES;
    }
    elsif ($file eq 'bug/edit.html.tmpl'|| $file eq 'bug/show.xml.tmpl'
           || $file eq 'email/bugmail.html.tmpl' || $file eq 'email/bugmail.txt.tmpl')
    {
        # note: bug/edit.html.tmpl doesn't support multiple bugs
        my $bug = exists $vars->{'bugs'} ? $vars->{'bugs'}[0] : $vars->{'bug'};

        if ($bug && !$bug->{error}) {
            $vars->{'tracking_flags'} = Bugzilla::Extension::TrackingFlags::Flag->match({
                product     => $bug->product,
                component   => $bug->component,
                bug_id      => $bug->id,
                is_active   => 1,
            });
        }

        $vars->{'tracking_flag_types'} = FLAG_TYPES;
    }
    elsif ($file eq 'list/edit-multiple.html.tmpl' && $vars->{'one_product'}) {
        $vars->{'tracking_flags'} = Bugzilla::Extension::TrackingFlags::Flag->match({
            product   => $vars->{'one_product'}->name,
            is_active => 1
        });
    }
}

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    $args->{'schema'}->{'tracking_flags'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            field_id => {
                TYPE => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'fielddefs',
                    COLUMN => 'id',
                    DELETE => 'CASCADE'
                }
            },
            name => {
                TYPE    => 'varchar(64)',
                NOTNULL => 1,
            },
            description => {
                TYPE    => 'varchar(64)',
                NOTNULL => 1,
            },
            type => {
                TYPE    => 'varchar(64)',
                NOTNULL => 1,
            },
            sortkey => {
                TYPE    => 'INT2',
                NOTNULL => 1,
                DEFAULT => '0',
            },
            enter_bug => {
                TYPE    => 'BOOLEAN',
                NOTNULL => 1,
                DEFAULT => 'TRUE',
            },
            is_active => {
                TYPE    => 'BOOLEAN',
                NOTNULL => 1,
                DEFAULT => 'TRUE',
            },
        ],
        INDEXES => [
            tracking_flags_idx => {
                FIELDS => ['name'],
                TYPE => 'UNIQUE',
            },
        ],
    };
    $args->{'schema'}->{'tracking_flags_values'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            tracking_flag_id => {
                TYPE       => 'INT3',
                NOTNULL    => 1,
                REFERENCES => {
                    TABLE  => 'tracking_flags',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                },
            },
            setter_group_id => {
                TYPE       => 'INT3',
                NOTNULL    => 0,
                REFERENCES => {
                    TABLE  => 'groups',
                    COLUMN => 'id',
                    DELETE => 'SET NULL',
                },
            },
            value => {
                TYPE    => 'varchar(64)',
                NOTNULL => 1,
            },
            sortkey => {
                TYPE    => 'INT2',
                NOTNULL => 1,
                DEFAULT => '0',
            },
            enter_bug => {
                TYPE    => 'BOOLEAN',
                NOTNULL => 1,
                DEFAULT => 'TRUE',
            },
            is_active => {
                TYPE    => 'BOOLEAN',
                NOTNULL => 1,
                DEFAULT => 'TRUE',
            },
        ],
        INDEXES => [
            tracking_flags_values_idx => {
                FIELDS => ['tracking_flag_id', 'value'],
                TYPE => 'UNIQUE',
            },
        ],
    };
    $args->{'schema'}->{'tracking_flags_bugs'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            tracking_flag_id => {
                TYPE       => 'INT3',
                NOTNULL    => 1,
                REFERENCES => {
                    TABLE  => 'tracking_flags',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                },
            },
            bug_id => {
                TYPE       => 'INT3',
                NOTNULL    => 1,
                REFERENCES => {
                    TABLE  => 'bugs',
                    COLUMN => 'bug_id',
                    DELETE => 'CASCADE',
                },
            },
            value => {
                TYPE    => 'varchar(64)',
                NOTNULL => 1,
            },
        ],
        INDEXES => [
            tracking_flags_bugs_idx => {
                FIELDS => ['tracking_flag_id', 'bug_id'],
                TYPE => 'UNIQUE',
            },
        ],
    };
    $args->{'schema'}->{'tracking_flags_visibility'} = {
        FIELDS => [
            id => {
                TYPE       => 'MEDIUMSERIAL',
                NOTNULL    => 1,
                PRIMARYKEY => 1,
            },
            tracking_flag_id => {
                TYPE       => 'INT3',
                NOTNULL    => 1,
                REFERENCES => {
                    TABLE  => 'tracking_flags',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                },
            },
            product_id => {
                TYPE       => 'INT2',
                NOTNULL    => 1,
                REFERENCES => {
                    TABLE  => 'products',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                },
            },
            component_id => {
                TYPE       => 'INT2',
                NOTNULL    => 0,
                REFERENCES => {
                    TABLE  => 'components',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                },
            },
        ],
        INDEXES => [
            tracking_flags_visibility_idx => {
                FIELDS => ['tracking_flag_id', 'product_id', 'component_id'],
                TYPE => 'UNIQUE',
            },
        ],
    };
}

sub install_update_db {
    my $dbh = Bugzilla->dbh;

    my $fk = $dbh->bz_fk_info('tracking_flags', 'field_id');
    if ($fk and !defined $fk->{DELETE}) {
        $fk->{DELETE} = 'CASCADE';
        $dbh->bz_alter_fk('tracking_flags', 'field_id', $fk);
    }

    $dbh->bz_add_column(
        'tracking_flags',
        'enter_bug',
        {
            TYPE    => 'BOOLEAN',
            NOTNULL => 1,
            DEFAULT => 'TRUE',
        }
    );
}

sub install_filesystem {
    my ($self, $args) = @_;
    my $files = $args->{files};
    my $extensions_dir = bz_locations()->{extensionsdir};
    $files->{"$extensions_dir/TrackingFlags/bin/bulk_flag_clear.pl"} = {
        perms => Bugzilla::Install::Filesystem::OWNER_EXECUTE
    };
}

sub active_custom_fields {
    my ($self, $args) = @_;
    my $fields    = $args->{'fields'};
    my $params    = $args->{'params'};
    my $product   = $params->{'product'};
    my $component = $params->{'component'};

    # Create a hash of current fields based on field names
    my %field_hash = map { $_->name => $_ } @$$fields;

    my @tracking_flags;
    if ($product) {
        $params->{'product_id'}   = $product->id;
        $params->{'component_id'} = $component->id if $component;
        $params->{'is_active'}    = 1;
        @tracking_flags = @{ Bugzilla::Extension::TrackingFlags::Flag->match($params) };
    }
    else {
        @tracking_flags = Bugzilla::Extension::TrackingFlags::Flag->get_all;
    }

    # Add tracking flags to fields hash replacing if already exists for our
    # flag object instead of the usual Field.pm object
    foreach my $flag (@tracking_flags) {
        $field_hash{$flag->name} = $flag;
    }

    @$$fields = sort { $a->sortkey <=> $b->sortkey } values %field_hash;
}

sub buglist_columns {
    my ($self, $args) = @_;
    my $columns = $args->{columns};
    my $dbh = Bugzilla->dbh;
    my @tracking_flags = Bugzilla::Extension::TrackingFlags::Flag->get_all;
    foreach my $flag (@tracking_flags) {
        $columns->{$flag->name} = {
            name  => "COALESCE(map_" . $flag->name . ".value, '---')",
            title => $flag->description
        };
    }
}

sub buglist_column_joins {
    my ($self, $args) = @_;
    # if there are elements in the tracking_flags array, then they have been
    # removed from the query, so we mustn't generate joins
    return if scalar @{ $args->{search}->{tracking_flags} };

    my $column_joins = $args->{'column_joins'};
    my @tracking_flags = Bugzilla::Extension::TrackingFlags::Flag->get_all;
    foreach my $flag (@tracking_flags) {
        $column_joins->{$flag->name} = {
            as    => 'map_' . $flag->name,
            table => 'tracking_flags_bugs',
            extra => [ 'map_' . $flag->name . '.tracking_flag_id = ' . $flag->flag_id ]
        };
    }
}

sub bug_create_cf_accessors {
    my ($self, $args) = @_;
    # Create the custom accessors for the flag values
    my @tracking_flags = Bugzilla::Extension::TrackingFlags::Flag->get_all;
    foreach my $flag (@tracking_flags) {
        my $flag_name = $flag->name;
        if (!Bugzilla::Bug->can($flag_name)) {
            my $accessor = sub {
                my $self = shift;
                return $self->{$flag_name} if defined $self->{$flag_name};
                if (!exists $self->{'_tf_bug_values_preloaded'}) {
                    # preload all values currently set for this bug
                    my $bug_values
                        = Bugzilla::Extension::TrackingFlags::Flag::Bug->match({ bug_id => $self->id });
                    foreach my $value (@$bug_values) {
                        $self->{$value->tracking_flag->name} = $value->value;
                    }
                    $self->{'_tf_bug_values_preloaded'} = 1;
                }
                return $self->{$flag_name} ||= '---';
            };
            no strict 'refs';
            *{"Bugzilla::Bug::$flag_name"} = $accessor;
        }
        if (!Bugzilla::Bug->can("set_$flag_name")) {
            my $setter = sub {
                my ($self, $value) = @_;
                $value = ref($value) eq 'ARRAY'
                         ? $value->[0]
                         : $value;
                $self->set($flag_name, $value);
            };
            no strict 'refs';
            *{"Bugzilla::Bug::set_$flag_name"} = $setter;
        }
    }
}

sub bug_editable_bug_fields {
    my ($self, $args) = @_;
    my $fields = $args->{'fields'};
    my @tracking_flags = Bugzilla::Extension::TrackingFlags::Flag->get_all;
    foreach my $flag (@tracking_flags) {
        push(@$fields, $flag->name);
    }
}

sub search_operator_field_override {
    my ($self, $args) = @_;
    my $operators = $args->{'operators'};
    my @tracking_flags = Bugzilla::Extension::TrackingFlags::Flag->get_all;
    foreach my $flag (@tracking_flags) {
        $operators->{$flag->name} = {
            _non_changed => sub {
                _tracking_flags_search_nonchanged($flag->flag_id, @_)
            }
        };
    }
}

sub _tracking_flags_search_nonchanged {
    my ($flag_id, $search, $args) = @_;
    my ($bugs_table, $chart_id, $joins, $value, $operator) =
        @$args{qw(bugs_table chart_id joins value operator)};
    my $dbh = Bugzilla->dbh;

    return if ($operator =~ m/^changed/);

    my $bugs_alias  = "tracking_flags_bugs_$chart_id";
    my $flags_alias = "tracking_flags_$chart_id";

    my $bugs_join = {
        table => 'tracking_flags_bugs',
        as    => $bugs_alias,
        from  => $bugs_table . ".bug_id",
        to    => "bug_id",
        extra => [$bugs_alias . ".tracking_flag_id = $flag_id"]
    };

    push(@$joins, $bugs_join);

    $args->{'full_field'} = "COALESCE($bugs_alias.value, '---')";
}

sub bug_end_of_create {
    my ($self, $args) = @_;
    my $bug       = $args->{'bug'};
    my $timestamp = $args->{'timestamp'};
    my $user      = Bugzilla->user;

    my $params = Bugzilla->request_cache->{tracking_flags_create_params};
    return if !$params;

    my $tracking_flags = Bugzilla::Extension::TrackingFlags::Flag->match({
        product   => $bug->product,
        component => $bug->component,
        is_active => 1,
    });

    foreach my $flag (@$tracking_flags) {
        next if !$params->{$flag->name};
        foreach my $value (@{$flag->values}) {
            next if $value->value ne $params->{$flag->name};
            next if $value->value eq '---'; # do not insert if value is '---', same as empty
            if (!$flag->can_set_value($value->value)) {
                ThrowUserError('tracking_flags_change_denied',
                               { flag => $flag, value => $value });
            }
            Bugzilla::Extension::TrackingFlags::Flag::Bug->create({
                tracking_flag_id => $flag->flag_id,
                bug_id           => $bug->id,
                value            => $value->value,
            });
            # Add the name/value pair to the bug object
            $bug->{$flag->name} = $value->value;
        }
    }
}

sub object_end_of_set_all {
    my ($self, $args) = @_;
    my $object = $args->{object};
    my $params = $args->{params};

    return unless $object->isa('Bugzilla::Bug');

    # Do not filter by product/component as we may be changing those
    my $tracking_flags = Bugzilla::Extension::TrackingFlags::Flag->match({
        bug_id    => $object->id,
        is_active => 1,
    });

    foreach my $flag (@$tracking_flags) {
        my $flag_name = $flag->name;
        if (exists $params->{$flag_name}) {
            my $value = ref($params->{$flag_name}) eq 'ARRAY'
                        ? $params->{$flag_name}->[0]
                        : $params->{$flag_name};
            $object->set($flag_name, $value);
        }
    }
}

sub bug_check_can_change_field {
    my ($self, $args) = @_;
    my ($bug, $field, $old_value, $new_value, $priv_results)
        = @$args{qw(bug field old_value new_value priv_results)};

    return if $field !~ /^cf_/ or $old_value eq $new_value;
    return unless my $flag = Bugzilla::Extension::TrackingFlags::Flag->new({ name => $field });

    if ($flag->can_set_value($new_value)) {
        push @$priv_results, PRIVILEGES_REQUIRED_NONE;
    }
    else {
        push @$priv_results, PRIVILEGES_REQUIRED_EMPOWERED;
    }
}

sub bug_end_of_update {
    my ($self, $args) = @_;
    my ($bug, $old_bug, $timestamp, $changes)
        = @$args{qw(bug old_bug timestamp changes)};
    my $user = Bugzilla->user;

    # Do not filter by product/component as we may be changing those
    my $tracking_flags = Bugzilla::Extension::TrackingFlags::Flag->match({
        bug_id    => $bug->id,
        is_active => 1,
    });

    my (@flag_changes);
    foreach my $flag (@$tracking_flags) {
        my $flag_name = $flag->name;
        my $new_value = $bug->$flag_name;
        my $old_value = $old_bug->$flag_name;

        if ($new_value ne $old_value) {
            # Do not allow if the user cannot set the old value or the new value
            if (!$flag->can_set_value($new_value)) {
                 ThrowUserError('tracking_flags_change_denied',
                                { flag => $flag, value => $new_value });
            }
            push(@flag_changes, { flag    => $flag,
                                  added   => $new_value,
                                  removed => $old_value });
        }
    }

    foreach my $change (@flag_changes) {
        my $flag    = $change->{'flag'};
        my $added   = $change->{'added'};
        my $removed = $change->{'removed'};

        if ($added eq '---') {
            $flag->bug_flag->remove_from_db();
        }
        elsif ($removed eq '---') {
            Bugzilla::Extension::TrackingFlags::Flag::Bug->create({
                tracking_flag_id => $flag->flag_id,
                bug_id           => $bug->id,
                value            => $added,
            });
        }
        else {
            $flag->bug_flag->set_value($added);
            $flag->bug_flag->update($timestamp);
        }

        $changes->{$flag->name} = [ $removed, $added ];
        LogActivityEntry($bug->id, $flag->name, $removed, $added, $user->id, $timestamp);

        # Update the name/value pair in the bug object
        $bug->{$flag->name} = $added;
    }
}

sub bug_end_of_create_validators {
    my ($self, $args) = @_;
    my $params = $args->{params};

    # We need to stash away any params that are setting/updating tracking
    # flags early on. Otherwise set_all or insert_create_data will complain.
    my @tracking_flags = Bugzilla::Extension::TrackingFlags::Flag->get_all;
    my $cache = Bugzilla->request_cache->{tracking_flags_create_params} ||= {};
    foreach my $flag (@tracking_flags) {
        my $flag_name = $flag->name;
        if (defined $params->{$flag_name}) {
            $cache->{$flag_name} = delete $params->{$flag_name};
        }
    }
}

sub mailer_before_send {
    my ($self, $args) = @_;
    my $email = $args->{email};

    # Add X-Bugzilla-Tracking header or add to it
    # if already exists
    if ($email->header('X-Bugzilla-ID')) {
        my $bug_id = $email->header('X-Bugzilla-ID');

        my $tracking_flags
            = Bugzilla::Extension::TrackingFlags::Flag->match({ bug_id => $bug_id });

        my @set_values = ();
        foreach my $flag (@$tracking_flags) {
            next if $flag->bug_flag->value eq '---';
            push(@set_values, $flag->description . ":" . $flag->bug_flag->value);
        }

        if (@set_values) {
            my $set_values_string = join(' ', @set_values);
            if ($email->header('X-Bugzilla-Tracking')) {
                $set_values_string = $email->header('X-Bugzilla-Tracking') .
                                     " " . $set_values_string;
            }
            $email->header_set('X-Bugzilla-Tracking' => $set_values_string);
        }
    }
}

# Purpose: generically handle generating pretty blocking/status "flags" from
# custom field names.
sub quicksearch_map {
    my ($self, $args) = @_;
    my $map = $args->{'map'};

    foreach my $name (keys %$map) {
        if ($name =~ /^cf_(blocking|tracking|status)_([a-z]+)?(\d+)?$/) {
            my $type = $1;
            my $product = $2;
            my $version = $3;

            if ($version) {
                $version = join('.', split(//, $version));
            }

            my $pretty_name = $type;
            if ($product) {
                $pretty_name .= "-" . $product;
            }
            if ($version) {
                $pretty_name .= $version;
            }

            $map->{$pretty_name} = $name;
        }
    }
}

__PACKAGE__->NAME;
