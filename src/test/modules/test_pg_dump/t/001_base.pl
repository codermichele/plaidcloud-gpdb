use strict;
use warnings;

use Config;
use PostgresNode;
use TestLib;
use Test::More;

my $tempdir       = TestLib::tempdir;
my $tempdir_short = TestLib::tempdir_short;

###############################################################
# This structure is based off of the src/bin/pg_dump/t test
# suite.
###############################################################
# Definition of the pg_dump runs to make.
#
# Each of these runs are named and those names are used below
# to define how each test should (or shouldn't) treat a result
# from a given run.
#
# test_key indicates that a given run should simply use the same
# set of like/unlike tests as another run, and which run that is.
#
# dump_cmd is the pg_dump command to run, which is an array of
# the full command and arguments to run.  Note that this is run
# using $node->command_ok(), so the port does not need to be
# specified and is pulled from $PGPORT, which is set by the
# PostgresNode system.
#
# restore_cmd is the pg_restore command to run, if any.  Note
# that this should generally be used when the pg_dump goes to
# a non-text file and that the restore can then be used to
# generate a text file to run through the tests from the
# non-text file generated by pg_dump.
#
# TODO: Have pg_restore actually restore to an independent
# database and then pg_dump *that* database (or something along
# those lines) to validate that part of the process.

my %pgdump_runs = (
	binary_upgrade => {
		dump_cmd => [
			'pg_dump',                            '--no-sync',
			"--file=$tempdir/binary_upgrade.sql", '--schema-only',
			'--binary-upgrade',                   '--dbname=postgres',
		],
	},
	clean => {
		dump_cmd => [
			'pg_dump', "--file=$tempdir/clean.sql",
			'-c',      '--no-sync',
			'--dbname=postgres',
		],
	},
	clean_if_exists => {
		dump_cmd => [
			'pg_dump',
			'--no-sync',
			"--file=$tempdir/clean_if_exists.sql",
			'-c',
			'--if-exists',
			'--encoding=UTF8',    # no-op, just tests that option is accepted
			'postgres',
		],
	},
	createdb => {
		dump_cmd => [
			'pg_dump',
			'--no-sync',
			"--file=$tempdir/createdb.sql",
			'-C',
			'-R',                 # no-op, just for testing
			'postgres',
		],
	},
	data_only => {
		dump_cmd => [
			'pg_dump',
			'--no-sync',
			"--file=$tempdir/data_only.sql",
			'-a',
			'-v',                 # no-op, just make sure it works
			'postgres',
		],
	},
	defaults => {
		dump_cmd => [ 'pg_dump', '-f', "$tempdir/defaults.sql", 'postgres', ],
	},
	defaults_custom_format => {
		test_key => 'defaults',
		dump_cmd => [
			'pg_dump', '--no-sync', '-Fc', '-Z6',
			"--file=$tempdir/defaults_custom_format.dump", 'postgres',
		],
		restore_cmd => [
			'pg_restore',
			"--file=$tempdir/defaults_custom_format.sql",
			"$tempdir/defaults_custom_format.dump",
		],
	},
	defaults_dir_format => {
		test_key => 'defaults',
		dump_cmd => [
			'pg_dump', '--no-sync', '-Fd',
			"--file=$tempdir/defaults_dir_format", 'postgres',
		],
		restore_cmd => [
			'pg_restore',
			"--file=$tempdir/defaults_dir_format.sql",
			"$tempdir/defaults_dir_format",
		],
	},
	defaults_parallel => {
		test_key => 'defaults',
		dump_cmd => [
			'pg_dump', '--no-sync', '-Fd', '-j2',
			"--file=$tempdir/defaults_parallel", 'postgres',
		],
		restore_cmd => [
			'pg_restore',
			"--file=$tempdir/defaults_parallel.sql",
			"$tempdir/defaults_parallel",
		],
	},
	defaults_tar_format => {
		test_key => 'defaults',
		dump_cmd => [
			'pg_dump', '--no-sync', '-Ft',
			"--file=$tempdir/defaults_tar_format.tar", 'postgres',
		],
		restore_cmd => [
			'pg_restore',
			"--file=$tempdir/defaults_tar_format.sql",
			"$tempdir/defaults_tar_format.tar",
		],
	},
	exclude_table => {
		dump_cmd => [
			'pg_dump',
			'--exclude-table=regress_table_dumpable',
			"--file=$tempdir/exclude_table.sql",
			'postgres',
		],
	},
	extension_schema => {
		dump_cmd => [
			'pg_dump',                              '--schema=public',
			"--file=$tempdir/extension_schema.sql", 'postgres',
		],
	},
	pg_dumpall_globals => {
		dump_cmd => [
			'pg_dumpall',                             '--no-sync',
			"--file=$tempdir/pg_dumpall_globals.sql", '-g',
		],
	},
	no_privs => {
		dump_cmd => [
			'pg_dump',                      '--no-sync',
			"--file=$tempdir/no_privs.sql", '-x',
			'postgres',
		],
	},
	no_owner => {
		dump_cmd => [
			'pg_dump',                      '--no-sync',
			"--file=$tempdir/no_owner.sql", '-O',
			'postgres',
		],
	},
	schema_only => {
		dump_cmd => [
			'pg_dump', '--no-sync', "--file=$tempdir/schema_only.sql",
			'-s', 'postgres',
		],
	},
	section_pre_data => {
		dump_cmd => [
			'pg_dump',                              '--no-sync',
			"--file=$tempdir/section_pre_data.sql", '--section=pre-data',
			'postgres',
		],
	},
	section_data => {
		dump_cmd => [
			'pg_dump',                          '--no-sync',
			"--file=$tempdir/section_data.sql", '--section=data',
			'postgres',
		],
	},
	section_post_data => {
		dump_cmd => [
			'pg_dump', '--no-sync', "--file=$tempdir/section_post_data.sql",
			'--section=post-data', 'postgres',
		],
	},);

###############################################################
# Definition of the tests to run.
#
# Each test is defined using the log message that will be used.
#
# A regexp should be defined for each test which provides the
# basis for the test.  That regexp will be run against the output
# file of each of the runs which the test is to be run against
# and the success of the result will depend on if the regexp
# result matches the expected 'like' or 'unlike' case.
# The runs listed as 'like' will be checked if they match the
# regexp and, if so, the test passes.  All runs which are not
# listed as 'like' will be checked to ensure they don't match
# the regexp; if they do, the test will fail.
#
# The below hashes provide convenience sets of runs.  Individual
# runs can be excluded from a general hash by placing that run
# into the 'unlike' section.
#
# There can then be a 'create_sql' and 'create_order' for a
# given test.  The 'create_sql' commands are collected up in
# 'create_order' and then run against the database prior to any
# of the pg_dump runs happening.  This is what "seeds" the
# system with objects to be dumped out.
#
# Building of this hash takes a bit of time as all of the regexps
# included in it are compiled.  This greatly improves performance
# as the regexps are used for each run the test applies to.

# Tests which are considered 'full' dumps by pg_dump, but there
# are flags used to exclude specific items (ACLs, blobs, etc).
my %full_runs = (
	binary_upgrade  => 1,
	clean           => 1,
	clean_if_exists => 1,
	createdb        => 1,
	defaults        => 1,
	exclude_table   => 1,
	no_privs        => 1,
	no_owner        => 1,);

my %tests = (
	'ALTER EXTENSION test_pg_dump' => {
		create_order => 9,
		create_sql =>
		  'ALTER EXTENSION test_pg_dump ADD TABLE regress_pg_dump_table_added;',
		regexp => qr/^
			\QCREATE TABLE public.regress_pg_dump_table_added (\E
			\n\s+\Qcol1 integer NOT NULL,\E
			\n\s+\Qcol2 integer\E
			\n\);\n/xm,
		like => { binary_upgrade => 1, },
	},

	'CREATE EXTENSION test_pg_dump' => {
		create_order => 2,
		create_sql   => 'CREATE EXTENSION test_pg_dump;',
		regexp       => qr/^
			\QCREATE EXTENSION IF NOT EXISTS test_pg_dump WITH SCHEMA public;\E
			\n/xm,
		like => {
			%full_runs,
			schema_only      => 1,
			section_pre_data => 1,
		},
		unlike => { binary_upgrade => 1, },
	},

	'CREATE ROLE regress_dump_test_role' => {
		create_order => 1,
		create_sql   => 'CREATE ROLE regress_dump_test_role;',
		regexp       => qr/^CREATE ROLE regress_dump_test_role;\n/m,
		like         => { pg_dumpall_globals => 1, },
	},

	'CREATE SEQUENCE regress_pg_dump_table_col1_seq' => {
		regexp => qr/^
                    \QCREATE SEQUENCE public.regress_pg_dump_table_col1_seq\E
                    \n\s+\QAS integer\E
                    \n\s+\QSTART WITH 1\E
                    \n\s+\QINCREMENT BY 1\E
                    \n\s+\QNO MINVALUE\E
                    \n\s+\QNO MAXVALUE\E
                    \n\s+\QCACHE 1;\E
                    \n/xm,
		like => { binary_upgrade => 1, },
	},

	'CREATE TABLE regress_pg_dump_table_added' => {
		create_order => 7,
		create_sql =>
		  'CREATE TABLE regress_pg_dump_table_added (col1 int not null, col2 int);',
		regexp => qr/^
			\QCREATE TABLE public.regress_pg_dump_table_added (\E
			\n\s+\Qcol1 integer NOT NULL,\E
			\n\s+\Qcol2 integer\E
			\n\);\n/xm,
		like => { binary_upgrade => 1, },
	},

	'CREATE SEQUENCE regress_pg_dump_seq' => {
		regexp => qr/^
                    \QCREATE SEQUENCE public.regress_pg_dump_seq\E
                    \n\s+\QSTART WITH 1\E
                    \n\s+\QINCREMENT BY 1\E
                    \n\s+\QNO MINVALUE\E
                    \n\s+\QNO MAXVALUE\E
                    \n\s+\QCACHE 1;\E
                    \n/xm,
		like => { binary_upgrade => 1, },
	},

	'SETVAL SEQUENCE regress_seq_dumpable' => {
		create_order => 6,
		create_sql   => qq{SELECT nextval('regress_seq_dumpable');},
		regexp       => qr/^
			\QSELECT pg_catalog.setval('public.regress_seq_dumpable', 1, true);\E
			\n/xm,
		like => {
			%full_runs,
			data_only        => 1,
			section_data     => 1,
			extension_schema => 1,
		},
	},

	'CREATE TABLE regress_pg_dump_table' => {
		regexp => qr/^
			\QCREATE TABLE public.regress_pg_dump_table (\E
			\n\s+\Qcol1 integer NOT NULL,\E
			\n\s+\Qcol2 integer,\E
			\n\s+\QCONSTRAINT regress_pg_dump_table_col2_check CHECK ((col2 > 0))\E
			\n\);\n/xm,
		like => { binary_upgrade => 1, },
	},

	'COPY public.regress_table_dumpable (col1)' => {
		regexp => qr/^
			\QCOPY public.regress_table_dumpable (col1) FROM stdin;\E
			\n/xm,
		like => {
			%full_runs,
			data_only        => 1,
			section_data     => 1,
			extension_schema => 1,
		},
		unlike => {
			binary_upgrade => 1,
			exclude_table  => 1,
		},
	},

	'REVOKE ALL ON FUNCTION wgo_then_no_access' => {
		create_order => 3,
		create_sql   => q{
			DO $$BEGIN EXECUTE format(
				'REVOKE ALL ON FUNCTION wgo_then_no_access()
				 FROM pg_signal_backend, public, %I',
				(SELECT usename
				 FROM pg_user JOIN pg_proc ON proowner = usesysid
				 WHERE proname = 'wgo_then_no_access')); END$$;},
		regexp => qr/^
			\QREVOKE ALL ON FUNCTION public.wgo_then_no_access() FROM PUBLIC;\E
			\n\QREVOKE ALL ON FUNCTION public.wgo_then_no_access() FROM \E.*;
			\n\QREVOKE ALL ON FUNCTION public.wgo_then_no_access() FROM pg_signal_backend;\E
			/xm,
		like => {
			%full_runs,
			schema_only      => 1,
			section_pre_data => 1,
		},
		unlike => { no_privs => 1, },
	},

	'REVOKE GRANT OPTION FOR UPDATE ON SEQUENCE wgo_then_regular' => {
		create_order => 3,
		create_sql   => 'REVOKE GRANT OPTION FOR UPDATE ON SEQUENCE
							wgo_then_regular FROM pg_signal_backend;',
		regexp => qr/^
			\QREVOKE ALL ON SEQUENCE public.wgo_then_regular FROM pg_signal_backend;\E
			\n\QGRANT SELECT,UPDATE ON SEQUENCE public.wgo_then_regular TO pg_signal_backend;\E
			\n\QGRANT USAGE ON SEQUENCE public.wgo_then_regular TO pg_signal_backend WITH GRANT OPTION;\E
			/xm,
		like => {
			%full_runs,
			schema_only      => 1,
			section_pre_data => 1,
		},
		unlike => { no_privs => 1, },
	},

	'CREATE ACCESS METHOD regress_test_am' => {
		regexp => qr/^
			\QCREATE ACCESS METHOD regress_test_am TYPE INDEX HANDLER bthandler;\E
			\n/xm,
		like => { binary_upgrade => 1, },
	},

	'COMMENT ON EXTENSION test_pg_dump' => {
		regexp => qr/^
			\QCOMMENT ON EXTENSION test_pg_dump \E
			\QIS 'Test pg_dump with an extension';\E
			\n/xm,
		like => {
			%full_runs,
			schema_only      => 1,
			section_pre_data => 1,
		},
	},

	'GRANT SELECT regress_pg_dump_table_added pre-ALTER EXTENSION' => {
		create_order => 8,
		create_sql =>
		  'GRANT SELECT ON regress_pg_dump_table_added TO regress_dump_test_role;',
		regexp => qr/^
			\QGRANT SELECT ON TABLE public.regress_pg_dump_table_added TO regress_dump_test_role;\E
			\n/xm,
		like => { binary_upgrade => 1, },
	},

	'REVOKE SELECT regress_pg_dump_table_added post-ALTER EXTENSION' => {
		create_order => 10,
		create_sql =>
		  'REVOKE SELECT ON regress_pg_dump_table_added FROM regress_dump_test_role;',
		regexp => qr/^
			\QREVOKE SELECT ON TABLE public.regress_pg_dump_table_added FROM regress_dump_test_role;\E
			\n/xm,
		like => {
			%full_runs,
			schema_only      => 1,
			section_pre_data => 1,
		},
		unlike => { no_privs => 1, },
	},

	'GRANT SELECT ON TABLE regress_pg_dump_table' => {
		regexp => qr/^
			\QSELECT pg_catalog.binary_upgrade_set_record_init_privs(true);\E\n
			\QGRANT SELECT ON TABLE public.regress_pg_dump_table TO regress_dump_test_role;\E\n
			\QSELECT pg_catalog.binary_upgrade_set_record_init_privs(false);\E
			\n/xms,
		like => { binary_upgrade => 1, },
	},

	'GRANT SELECT(col1) ON regress_pg_dump_table' => {
		regexp => qr/^
			\QSELECT pg_catalog.binary_upgrade_set_record_init_privs(true);\E\n
			\QGRANT SELECT(col1) ON TABLE public.regress_pg_dump_table TO PUBLIC;\E\n
			\QSELECT pg_catalog.binary_upgrade_set_record_init_privs(false);\E
			\n/xms,
		like => { binary_upgrade => 1, },
	},

	'GRANT SELECT(col2) ON regress_pg_dump_table TO regress_dump_test_role'
	  => {
		create_order => 4,
		create_sql   => 'GRANT SELECT(col2) ON regress_pg_dump_table
						   TO regress_dump_test_role;',
		regexp => qr/^
			\QGRANT SELECT(col2) ON TABLE public.regress_pg_dump_table TO regress_dump_test_role;\E
			\n/xm,
		like => {
			%full_runs,
			schema_only      => 1,
			section_pre_data => 1,
		},
		unlike => { no_privs => 1, },
	  },

	'GRANT USAGE ON regress_pg_dump_table_col1_seq TO regress_dump_test_role'
	  => {
		create_order => 5,
		create_sql => 'GRANT USAGE ON SEQUENCE regress_pg_dump_table_col1_seq
		                   TO regress_dump_test_role;',
		regexp => qr/^
			\QGRANT USAGE ON SEQUENCE public.regress_pg_dump_table_col1_seq TO regress_dump_test_role;\E
			\n/xm,
		like => {
			%full_runs,
			schema_only      => 1,
			section_pre_data => 1,
		},
		unlike => { no_privs => 1, },
	  },

	'GRANT USAGE ON regress_pg_dump_seq TO regress_dump_test_role' => {
		regexp => qr/^
			\QGRANT USAGE ON SEQUENCE public.regress_pg_dump_seq TO regress_dump_test_role;\E
			\n/xm,
		like => { binary_upgrade => 1, },
	},

	'REVOKE SELECT(col1) ON regress_pg_dump_table' => {
		create_order => 3,
		create_sql   => 'REVOKE SELECT(col1) ON regress_pg_dump_table
						   FROM PUBLIC;',
		regexp => qr/^
			\QREVOKE SELECT(col1) ON TABLE public.regress_pg_dump_table FROM PUBLIC;\E
			\n/xm,
		like => {
			%full_runs,
			schema_only      => 1,
			section_pre_data => 1,
		},
		unlike => { no_privs => 1, },
	},

	# Objects included in extension part of a schema created by this extension */
	'CREATE TABLE regress_pg_dump_schema.test_table' => {
		regexp => qr/^
			\QCREATE TABLE regress_pg_dump_schema.test_table (\E
			\n\s+\Qcol1 integer,\E
			\n\s+\Qcol2 integer,\E
			\n\s+\QCONSTRAINT test_table_col2_check CHECK ((col2 > 0))\E
			\n\);\n/xm,
		like => { binary_upgrade => 1, },
	},

	'GRANT SELECT ON regress_pg_dump_schema.test_table' => {
		regexp => qr/^
			\QSELECT pg_catalog.binary_upgrade_set_record_init_privs(true);\E\n
			\QGRANT SELECT ON TABLE regress_pg_dump_schema.test_table TO regress_dump_test_role;\E\n
			\QSELECT pg_catalog.binary_upgrade_set_record_init_privs(false);\E
			\n/xms,
		like => { binary_upgrade => 1, },
	},

	'CREATE SEQUENCE regress_pg_dump_schema.test_seq' => {
		regexp => qr/^
                    \QCREATE SEQUENCE regress_pg_dump_schema.test_seq\E
                    \n\s+\QSTART WITH 1\E
                    \n\s+\QINCREMENT BY 1\E
                    \n\s+\QNO MINVALUE\E
                    \n\s+\QNO MAXVALUE\E
                    \n\s+\QCACHE 1;\E
                    \n/xm,
		like => { binary_upgrade => 1, },
	},

	'GRANT USAGE ON regress_pg_dump_schema.test_seq' => {
		regexp => qr/^
			\QSELECT pg_catalog.binary_upgrade_set_record_init_privs(true);\E\n
			\QGRANT USAGE ON SEQUENCE regress_pg_dump_schema.test_seq TO regress_dump_test_role;\E\n
			\QSELECT pg_catalog.binary_upgrade_set_record_init_privs(false);\E
			\n/xms,
		like => { binary_upgrade => 1, },
	},

	'CREATE TYPE regress_pg_dump_schema.test_type' => {
		regexp => qr/^
                    \QCREATE TYPE regress_pg_dump_schema.test_type AS (\E
                    \n\s+\Qcol1 integer\E
                    \n\);\n/xm,
		like => { binary_upgrade => 1, },
	},

	'GRANT USAGE ON regress_pg_dump_schema.test_type' => {
		regexp => qr/^
			\QSELECT pg_catalog.binary_upgrade_set_record_init_privs(true);\E\n
			\QGRANT ALL ON TYPE regress_pg_dump_schema.test_type TO regress_dump_test_role;\E\n
			\QSELECT pg_catalog.binary_upgrade_set_record_init_privs(false);\E
			\n/xms,
		like => { binary_upgrade => 1, },
	},

	'CREATE FUNCTION regress_pg_dump_schema.test_func' => {
		regexp => qr/^
            \QCREATE FUNCTION regress_pg_dump_schema.test_func() RETURNS integer\E
            \n\s+\QLANGUAGE sql\E
            \n/xm,
		like => { binary_upgrade => 1, },
	},

	'GRANT ALL ON regress_pg_dump_schema.test_func' => {
		regexp => qr/^
			\QSELECT pg_catalog.binary_upgrade_set_record_init_privs(true);\E\n
			\QGRANT ALL ON FUNCTION regress_pg_dump_schema.test_func() TO regress_dump_test_role;\E\n
			\QSELECT pg_catalog.binary_upgrade_set_record_init_privs(false);\E
			\n/xms,
		like => { binary_upgrade => 1, },
	},

	'CREATE AGGREGATE regress_pg_dump_schema.test_agg' => {
		regexp => qr/^
            \QCREATE AGGREGATE regress_pg_dump_schema.test_agg(smallint) (\E
            \n\s+\QSFUNC = int2_sum,\E
            \n\s+\QSTYPE = bigint\E
            \n\);\n/xm,
		like => { binary_upgrade => 1, },
	},

	'GRANT ALL ON regress_pg_dump_schema.test_agg' => {
		regexp => qr/^
			\QSELECT pg_catalog.binary_upgrade_set_record_init_privs(true);\E\n
			\QGRANT ALL ON FUNCTION regress_pg_dump_schema.test_agg(smallint) TO regress_dump_test_role;\E\n
			\QSELECT pg_catalog.binary_upgrade_set_record_init_privs(false);\E
			\n/xms,
		like => { binary_upgrade => 1, },
	},

	'ALTER INDEX pkey DEPENDS ON extension' => {
		create_order => 11,
		create_sql =>
		  'CREATE TABLE regress_pg_dump_schema.extdependtab (col1 integer primary key, col2 int);
		CREATE INDEX ON regress_pg_dump_schema.extdependtab (col2);
		ALTER INDEX regress_pg_dump_schema.extdependtab_col2_idx DEPENDS ON EXTENSION test_pg_dump;
		ALTER INDEX regress_pg_dump_schema.extdependtab_pkey DEPENDS ON EXTENSION test_pg_dump;',
		regexp => qr/^
		\QALTER INDEX regress_pg_dump_schema.extdependtab_pkey DEPENDS ON EXTENSION test_pg_dump;\E\n
		/xms,
		like   => {%pgdump_runs},
		unlike => {
			data_only          => 1,
			extension_schema   => 1,
			pg_dumpall_globals => 1,
			section_data       => 1,
			section_pre_data   => 1,
		},
	},

	'ALTER INDEX idx DEPENDS ON extension' => {
		regexp => qr/^
			\QALTER INDEX regress_pg_dump_schema.extdependtab_col2_idx DEPENDS ON EXTENSION test_pg_dump;\E\n
			/xms,
		like   => {%pgdump_runs},
		unlike => {
			data_only          => 1,
			extension_schema   => 1,
			pg_dumpall_globals => 1,
			section_data       => 1,
			section_pre_data   => 1,
		},
	},

	# Objects not included in extension, part of schema created by extension
	'CREATE TABLE regress_pg_dump_schema.external_tab' => {
		create_order => 4,
		create_sql   => 'CREATE TABLE regress_pg_dump_schema.external_tab
						   (col1 int);',
		regexp => qr/^
			\QCREATE TABLE regress_pg_dump_schema.external_tab (\E
			\n\s+\Qcol1 integer\E
			\n\);\n/xm,
		like => {
			%full_runs,
			schema_only      => 1,
			section_pre_data => 1,
		},
	},);

#########################################
# Create a PG instance to test actually dumping from

my $node = get_new_node('main');
$node->init;
$node->start;

my $port = $node->port;

my $num_tests = 0;

foreach my $run (sort keys %pgdump_runs)
{
	my $test_key = $run;

	# Each run of pg_dump is a test itself
	$num_tests++;

	# If there is a restore cmd, that's another test
	if ($pgdump_runs{$run}->{restore_cmd})
	{
		$num_tests++;
	}

	if ($pgdump_runs{$run}->{test_key})
	{
		$test_key = $pgdump_runs{$run}->{test_key};
	}

	# Then count all the tests run against each run
	foreach my $test (sort keys %tests)
	{
		# If there is a like entry, but no unlike entry, then we will test the like case
		if ($tests{$test}->{like}->{$test_key}
			&& !defined($tests{$test}->{unlike}->{$test_key}))
		{
			$num_tests++;
		}
		else
		{
			# We will test everything that isn't a 'like'
			$num_tests++;
		}
	}
}
plan tests => $num_tests;

#########################################
# Set up schemas, tables, etc, to be dumped.

# Build up the create statements
my $create_sql = '';

foreach my $test (
	sort {
		if ($tests{$a}->{create_order} and $tests{$b}->{create_order})
		{
			$tests{$a}->{create_order} <=> $tests{$b}->{create_order};
		}
		elsif ($tests{$a}->{create_order})
		{
			-1;
		}
		elsif ($tests{$b}->{create_order})
		{
			1;
		}
		else
		{
			0;
		}
	} keys %tests)
{
	if ($tests{$test}->{create_sql})
	{
		$create_sql .= $tests{$test}->{create_sql};
	}
}

# Send the combined set of commands to psql
$node->safe_psql('postgres', $create_sql);

#########################################
# Run all runs

foreach my $run (sort keys %pgdump_runs)
{

	my $test_key = $run;

	$node->command_ok(\@{ $pgdump_runs{$run}->{dump_cmd} },
		"$run: pg_dump runs");

	if ($pgdump_runs{$run}->{restore_cmd})
	{
		$node->command_ok(\@{ $pgdump_runs{$run}->{restore_cmd} },
			"$run: pg_restore runs");
	}

	if ($pgdump_runs{$run}->{test_key})
	{
		$test_key = $pgdump_runs{$run}->{test_key};
	}

	my $output_file = slurp_file("$tempdir/${run}.sql");

	#########################################
	# Run all tests where this run is included
	# as either a 'like' or 'unlike' test.

	foreach my $test (sort keys %tests)
	{
		# Run the test listed as a like, unless it is specifically noted
		# as an unlike (generally due to an explicit exclusion or similar).
		if ($tests{$test}->{like}->{$test_key}
			&& !defined($tests{$test}->{unlike}->{$test_key}))
		{
			if (!ok($output_file =~ $tests{$test}->{regexp},
					"$run: should dump $test"))
			{
				diag("Review $run results in $tempdir");
			}
		}
		else
		{
			if (!ok($output_file !~ $tests{$test}->{regexp},
					"$run: should not dump $test"))
			{
				diag("Review $run results in $tempdir");
			}
		}
	}
}

#########################################
# Stop the database instance, which will be removed at the end of the tests.

$node->stop('fast');
