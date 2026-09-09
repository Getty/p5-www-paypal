#!/usr/bin/env perl
use strict;
use warnings;

# maint/regen-operations.pl
#
# Regenerate the per-controller openapi_operations tables from PayPal's
# published OpenAPI 3 specifications, and diff them against what the
# WWW::PayPal::API::* controllers currently ship.
#
# This is a MAINTENANCE tool. It PRINTS ready-to-paste Perl hash literals
# and an actionable diff to STDOUT. It NEVER modifies lib/ -- the dist
# deliberately hand-maintains the operation tables (no codegen in lib/), so
# the maintainer copies the relevant lines across by hand.

use FindBin ();
use File::Spec ();
use Cwd ();
use Getopt::Long qw(GetOptions);
use Pod::Usage qw(pod2usage);
use JSON::MaybeXS qw(decode_json);

our $VERSION = '0.001';

# ---------------------------------------------------------------------------
# Configuration: spec file -> controller mapping.
#
# PayPal publishes one OpenAPI JSON per API. Some map 1:1 to a controller;
# billing_subscriptions_v1.json covers BOTH the Plans and the Subscriptions
# controllers, so those two entries share the spec and each carries a
# path_filter that selects only its half of the paths object.
# ---------------------------------------------------------------------------
my @CONTROLLERS = (
    {
        name => 'Orders',
        file => 'lib/WWW/PayPal/API/Orders.pm',
        spec => 'checkout_orders_v2.json',
    },
    {
        name => 'Payments',
        file => 'lib/WWW/PayPal/API/Payments.pm',
        spec => 'payments_payment_v2.json',
    },
    {
        name => 'Products',
        file => 'lib/WWW/PayPal/API/Products.pm',
        spec => 'catalogs_products_v1.json',
    },
    {
        name        => 'Plans',
        file        => 'lib/WWW/PayPal/API/Plans.pm',
        spec        => 'billing_subscriptions_v1.json',
        path_filter => qr{^/v1/billing/plans(?:/|$)},
    },
    {
        name        => 'Subscriptions',
        file        => 'lib/WWW/PayPal/API/Subscriptions.pm',
        spec        => 'billing_subscriptions_v1.json',
        path_filter => qr{^/v1/billing/subscriptions(?:/|$)},
    },
    {
        # No controller exists yet -- informational table only, no diff.
        name          => 'Webhooks',
        spec          => 'notifications_webhooks_v1.json',
        informational => 1,
    },
);

my $DEFAULT_BASE_URL =
    'https://raw.githubusercontent.com/paypal/paypal-rest-api-specifications/main/openapi';

# HTTP method keys that may appear under a path item in OpenAPI 3.
my %HTTP_METHOD = map { $_ => 1 } qw(get put post delete patch head options trace);

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
my %opt = (
    'base-url' => $DEFAULT_BASE_URL,
    'spec-dir' => undef,
    'lib-dir'  => undef,
    'only'     => undef,
    'help'     => 0,
);
GetOptions( \%opt,
    'base-url=s',
    'spec-dir=s',
    'lib-dir=s',
    'only=s',
    'help|h',
) or pod2usage(2);
pod2usage(-verbose => 2, -exitval => 0) if $opt{help};

# Dist root defaults to the parent of this script's maint/ directory, so the
# tool works no matter what the current directory is.
my $dist_root = Cwd::abs_path(File::Spec->catdir($FindBin::RealBin, File::Spec->updir));
my $lib_dir   = $opt{'lib-dir'} ? Cwd::abs_path($opt{'lib-dir'}) : $dist_root;

# Optional --only filter (comma-separated controller names, case-insensitive).
my %only;
if (defined $opt{only}) {
    %only = map { lc($_) => 1 } grep { length } split /\s*,\s*/, $opt{only};
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
my $exit = 0;
eval {
    run();
    1;
} or do {
    my $err = $@ || 'unknown error';
    $err =~ s/\n+$//;
    print STDERR "regen-operations: $err\n";
    exit 1;
};
exit $exit;

sub run {
    print_header();

    my %spec_cache;    # spec file -> decoded hashref (fetched/loaded once)
    my @summary;

    for my $ctrl (@CONTROLLERS) {
        next if %only && !$only{ lc $ctrl->{name} };

        print "=" x 78, "\n";
        print "## $ctrl->{name}   (spec: $ctrl->{spec})\n";
        print "=" x 78, "\n\n";

        # Load the spec (cached). For informational controllers a fetch
        # failure is a warning, not a fatal error.
        my $spec = $spec_cache{ $ctrl->{spec} };
        if (!$spec) {
            my $loaded = eval { load_spec($ctrl->{spec}) };
            if (!$loaded) {
                my $err = $@ || 'unknown error';
                $err =~ s/\n+$//;
                if ($ctrl->{informational}) {
                    print "  [skipped] could not load spec: $err\n\n";
                    next;
                }
                die "$err\n";
            }
            $spec = $spec_cache{ $ctrl->{spec} } = $loaded;
        }

        # Extract spec operations, honouring an optional path filter.
        my $spec_ops = extract_spec_ops($spec, $ctrl->{path_filter});

        # 1. Emit the ready-to-paste table.
        print "--- extracted openapi_operations (paste into builder) ---\n\n";
        print format_table($spec_ops);
        print "\n";

        if ($ctrl->{informational}) {
            print "  NOTE: no WWW::PayPal::API::$ctrl->{name} controller exists yet.\n";
            print "        Table shown for reference only; nothing to diff.\n\n";
            push @summary, sprintf('%-14s informational only (%d spec ops)',
                $ctrl->{name}, scalar keys %$spec_ops);
            next;
        }

        # 2. Parse the controller's current table and diff.
        my $ctrl_file = File::Spec->catfile($lib_dir, $ctrl->{file});
        my $ctrl_ops  = parse_controller_ops($ctrl_file);

        my ($missing, $extra, $mismatch, $renamed) = diff_ops($spec_ops, $ctrl_ops);

        print "--- diff vs current controller ($ctrl->{file}) ---\n\n";
        print_diff($missing, $extra, $mismatch, $renamed);
        print "\n";

        push @summary, sprintf(
            '%-14s spec=%-2d controller=%-2d | +%d missing  -%d extra  ~%d mismatch  =%d renamed',
            $ctrl->{name}, scalar keys %$spec_ops, scalar keys %$ctrl_ops,
            scalar @$missing, scalar @$extra, scalar @$mismatch, scalar @$renamed,
        );
    }

    print "=" x 78, "\n";
    print "## Summary\n";
    print "=" x 78, "\n\n";
    print "  $_\n" for @summary;
    print "\n";
    print "  Reminder: this tool does NOT modify lib/. Update the\n";
    print "  openapi_operations builders by hand from the tables above.\n\n";
}

# ---------------------------------------------------------------------------
# spec loading
# ---------------------------------------------------------------------------
sub load_spec {
    my ($file) = @_;

    my $bytes;
    if (defined $opt{'spec-dir'}) {
        my $path = File::Spec->catfile($opt{'spec-dir'}, $file);
        open my $fh, '<:raw', $path
            or die "cannot read local spec '$path': $!";
        local $/;
        $bytes = <$fh>;
        close $fh;
    }
    else {
        my $url = "$opt{'base-url'}/$file";
        $bytes = fetch($url);
    }

    my $data = eval { decode_json($bytes) };
    die "spec '$file' is not valid JSON: $@" if $@;
    die "spec '$file' has no 'paths' object\n"
        unless ref $data eq 'HASH' && ref $data->{paths} eq 'HASH';
    return $data;
}

sub fetch {
    my ($url) = @_;
    require LWP::UserAgent;
    my $ua = LWP::UserAgent->new(
        timeout => 30,
        agent   => "WWW-PayPal-regen-operations/$VERSION",
    );
    my $res = $ua->get($url);
    die sprintf("fetch failed: %s -> %s\n", $url, $res->status_line)
        unless $res->is_success;
    my $bytes = $res->content;
    die "fetch failed: $url -> empty response body\n"
        unless defined $bytes && length $bytes;
    return $bytes;
}

# ---------------------------------------------------------------------------
# extraction
# ---------------------------------------------------------------------------

# Walk the OpenAPI paths object -> { operationId => { method, path } }.
sub extract_spec_ops {
    my ($spec, $path_filter) = @_;
    my %ops;
    my $paths = $spec->{paths};
    for my $path (keys %$paths) {
        next if $path_filter && $path !~ $path_filter;
        my $item = $paths->{$path};
        next unless ref $item eq 'HASH';
        for my $method (keys %$item) {
            next unless $HTTP_METHOD{ lc $method };
            my $op = $item->{$method};
            next unless ref $op eq 'HASH';
            my $id = $op->{operationId};
            unless (defined $id && length $id) {
                warn "  [warn] $path " . uc($method)
                    . ": no operationId in spec, skipped\n";
                next;
            }
            warn "  [warn] duplicate operationId '$id' in spec ($path)\n"
                if exists $ops{$id};
            $ops{$id} = { method => uc($method), path => $path };
        }
    }
    return \%ops;
}

# Light, eval-free parse of a controller's openapi_operations builder.
# The table entries are one-per-line hash literals; we isolate the builder's
# returned hash first so POD examples elsewhere in the file can't leak in.
sub parse_controller_ops {
    my ($file) = @_;
    open my $fh, '<:encoding(UTF-8)', $file
        or die "cannot read controller '$file': $!\n";
    local $/;
    my $src = <$fh>;
    close $fh;

    my ($block) = $src =~ /has\s+openapi_operations\b.*?\breturn\s*\{(.*?)\n\s*\};/s;
    die "could not find openapi_operations builder in '$file'\n"
        unless defined $block;

    my %ops;
    for my $line (split /\n/, $block) {
        next unless $line =~ /'([^']+)'\s*=>\s*\{(.*)\}\s*,?\s*$/;
        my ($id, $inner) = ($1, $2);
        my ($method) = $inner =~ /method\s*=>\s*'([^']*)'/;
        my ($path)   = $inner =~ /path\s*=>\s*'([^']*)'/;
        next unless defined $method && defined $path;
        $ops{$id} = { method => $method, path => $path };
    }
    die "parsed no operations from '$file' (format changed?)\n"
        unless keys %ops;
    return \%ops;
}

# ---------------------------------------------------------------------------
# diff
# ---------------------------------------------------------------------------
sub diff_ops {
    my ($spec_ops, $ctrl_ops) = @_;
    my (@missing, @extra, @mismatch);

    for my $id (sort keys %$spec_ops) {
        if (!exists $ctrl_ops->{$id}) {
            push @missing, $id;
        }
        else {
            my ($s, $c) = ($spec_ops->{$id}, $ctrl_ops->{$id});
            push @mismatch, { id => $id, spec => $s, ctrl => $c }
                if $s->{method} ne $c->{method} || $s->{path} ne $c->{path};
        }
    }
    for my $id (sort keys %$ctrl_ops) {
        push @extra, $id unless exists $spec_ops->{$id};
    }

    # Advisory reconciliation: a spec-only id and a controller-only id that
    # share the same METHOD+path are the SAME endpoint under a different
    # operationId (a rename), not a genuine gap. Surface those so the diff
    # is actionable when the dist's naming diverges from PayPal's.
    my %ctrl_by_ep;
    for my $id (@extra) {
        my $o = $ctrl_ops->{$id};
        $ctrl_by_ep{"$o->{method} $o->{path}"} = $id;
    }
    my @renamed;
    for my $id (@missing) {
        my $o  = $spec_ops->{$id};
        my $ep = "$o->{method} $o->{path}";
        if (my $cid = $ctrl_by_ep{$ep}) {
            push @renamed, { spec => $id, ctrl => $cid, ep => $ep };
        }
    }

    return (\@missing, \@extra, \@mismatch, \@renamed);
}

sub print_diff {
    my ($missing, $extra, $mismatch, $renamed) = @_;

    if (!@$missing && !@$extra && !@$mismatch) {
        print "  in sync: spec and controller agree on every operationId.\n";
        return;
    }

    if (@$missing) {
        print "  in spec but MISSING from controller:\n";
        printf "    + %s\n", $_ for @$missing;
    }
    if (@$extra) {
        print "  in controller but NOT in spec:\n";
        printf "    - %s\n", $_ for @$extra;
    }
    if (@$mismatch) {
        print "  method/path MISMATCH (same operationId):\n";
        for my $m (@$mismatch) {
            printf "    ~ %s\n", $m->{id};
            printf "        spec:       %-6s %s\n", $m->{spec}{method}, $m->{spec}{path};
            printf "        controller: %-6s %s\n", $m->{ctrl}{method}, $m->{ctrl}{path};
        }
    }
    if (@$renamed) {
        print "  NOTE: same endpoint, different operationId (likely a rename,\n";
        print "        not a missing/extra pair -- reconcile the naming):\n";
        for my $r (@$renamed) {
            printf "    = %-40s spec '%s'  <->  controller '%s'\n",
                $r->{ep}, $r->{spec}, $r->{ctrl};
        }
    }
}

# ---------------------------------------------------------------------------
# formatting
# ---------------------------------------------------------------------------
sub format_table {
    my ($ops) = @_;
    my @ids = sort keys %$ops;
    return "    (no operations)\n" unless @ids;

    my $id_w     = max_len(map { "'$_'" } @ids);
    my $method_w = max_len(map { "'$_->{method}'," } values %$ops);

    my $out = '';
    for my $id (@ids) {
        my $o = $ops->{$id};
        $out .= sprintf "    %-*s => { method => %-*s path => '%s' },\n",
            $id_w, "'$id'",
            $method_w, "'$o->{method}',",
            $o->{path};
    }
    return $out;
}

sub max_len {
    my $max = 0;
    for (@_) {
        my $l = length $_;
        $max = $l if $l > $max;
    }
    return $max;
}

sub print_header {
    my $source = defined $opt{'spec-dir'}
        ? "local spec dir: $opt{'spec-dir'}"
        : "network: $opt{'base-url'}";
    print <<"HEADER";
# WWW::PayPal :: OpenAPI operation-table regenerator
#
# spec source : $source
# lib dir     : $lib_dir
#
# This report is INFORMATIONAL. It prints the tables + a diff; it does NOT
# edit any file under lib/. Update the openapi_operations builders by hand.

HEADER
}

__END__

=pod

=head1 NAME

regen-operations.pl - regenerate WWW::PayPal openapi_operations tables from
PayPal's published OpenAPI specs

=head1 SYNOPSIS

    # Fetch the live specs and report tables + diffs for every controller:
    perl maint/regen-operations.pl

    # Only some controllers:
    perl maint/regen-operations.pl --only Orders,Subscriptions

    # Run offline against a local checkout of the spec repo:
    perl maint/regen-operations.pl --spec-dir /path/to/openapi

    # Point at a mirror / fork of the spec repo:
    perl maint/regen-operations.pl --base-url https://example.com/openapi

=head1 DESCRIPTION

Each C<WWW::PayPal::API::*> controller hand-maintains an C<openapi_operations>
table mapping C<operationId> to C<< { method, path } >>. There is deliberately
B<no> runtime spec parsing in F<lib/> -- the tables are pre-computed by hand.

This maintenance tool automates I<extracting> those tables from PayPal's
published OpenAPI 3 JSON specs so a human can keep the hand-maintained tables
in sync. For each controller it:

=over 4

=item 1.

Fetches (or reads locally) the relevant spec and walks its C<paths> object,
collecting every C<< operationId => { method, path } >> (upper-cased method,
verbatim path).

=item 2.

Prints the extracted table as a ready-to-paste Perl hash literal in the exact
shape the builders use, sorted by C<operationId> for stable diffs.

=item 3.

Parses the controller's I<current> C<openapi_operations> builder and diffs it
against the spec: operationIds present in the spec but missing from the
controller, ones present in the controller but not the spec, and any
method/path mismatches. When the dist's naming diverges from PayPal's it also
flags spec/controller operationIds that describe the B<same> endpoint (same
method + path) under a different name.

=back

=head2 IMPORTANT: this tool never writes to lib/

Output goes to STDOUT only. The distribution's invariant is that the operation
tables are hand-maintained (no codegen in F<lib/>), so B<the maintainer copies
the relevant lines across by hand> after reviewing the diff. This script will
not, and must not, edit any controller.

=head2 Spec -> controller mapping

    checkout_orders_v2.json       -> API::Orders
    payments_payment_v2.json      -> API::Payments
    catalogs_products_v1.json     -> API::Products
    billing_subscriptions_v1.json -> API::Plans         (paths /v1/billing/plans*)
    billing_subscriptions_v1.json -> API::Subscriptions (paths /v1/billing/subscriptions*)
    notifications_webhooks_v1.json-> (no controller; informational table only)

C<billing_subscriptions_v1.json> is a single spec covering both the Plans and
the Subscriptions APIs; the two controllers share it and each selects its half
of the C<paths> object by path prefix.

=head1 OPTIONS

=over 4

=item B<--base-url> URL

Base URL the per-API spec files are fetched from. Defaults to the C<main>
branch of C<paypal/paypal-rest-api-specifications> on raw.githubusercontent.com.

=item B<--spec-dir> DIR

Read the spec files from a local directory (e.g. a checkout of the spec repo)
instead of fetching over the network. Files are looked up by their published
name, e.g. C<DIR/checkout_orders_v2.json>.

=item B<--lib-dir> DIR

Distribution root that contains F<lib/> (defaults to the parent of this
script's F<maint/> directory), used to locate the controller C<.pm> files for
the diff.

=item B<--only> NAME[,NAME...]

Restrict the run to the named controllers (case-insensitive): C<Orders>,
C<Payments>, C<Products>, C<Plans>, C<Subscriptions>, C<Webhooks>.

=item B<--help>, B<-h>

Show this documentation.

=back

=head1 EXIT STATUS

C<0> on success, C<2> on a usage error, C<1> on any other error (e.g. a spec
fetch failure or an unparseable controller). A non-empty diff is not an error.

=head1 SEE ALSO

L<WWW::PayPal::Role::OpenAPI>,
L<https://github.com/paypal/paypal-rest-api-specifications>

=cut
