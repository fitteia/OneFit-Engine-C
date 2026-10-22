#!/usr/bin/env perl
# Tests for xmgr.c's plot commands and their failures, without installing an
# engine. Run: perl tools/test_plotting.t   (make plot-selftest)
# xmgr.c is compiled into a small harness; plot-go, grace, cop, epstopdf and
# display are stand-ins on PATH that record how they were called.
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $HERE   = dirname(abs_path($0));
my $C_ROOT = abs_path("$HERE/..");

sub slurp { open my $f, '<:raw', $_[0] or return ''; local $/; scalar(<$f>) // '' }
sub spew  { make_path(dirname($_[0])); open my $f, '>:raw', $_[0] or die "$_[0]: $!"; print {$f} $_[1]; close $f }

my $scratch = tempdir('ofe-plot-test-XXXXXX', TMPDIR => 1, CLEANUP => 1);
spew("$scratch/harness.c", qq{#include "$C_ROOT/core/onefit-3.1/xmgr.c"\n} . <<'C');
int NT=1, Ma=1, display_flag=0;
char *GRAPH_TYPE="PDF";
char *xs[]={"lin"}, *ys[]={"lin"}, *gp[]={"fit-curves-1"}, *par[]={"fit1.agr-par"};
char **xscale=xs, **yscale=ys, **gph_name=gp, **XMGR_PAR_FILE=par;
double xv[]={0}, xmv[]={1}; double *xm=xv, *xM=xmv, *_T=NULL;
int print_data(char *file,int nfile) { return 0; }
void nrerror(char error_text[]) { fprintf(stderr, "%s\n", error_text); exit(1); }
int main(int argc,char **argv) {
 if(argc>1 && !strcmp(argv[1],"no-param")) XMGR_PAR_FILE=NULL;
 if(argc>2) display_flag=1;
 xmgr("xmgrace","PDF"); return 0;
}
C
my $binary = "$scratch/harness";
system('gcc', '-DDEBIAN9', '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections',
    "$scratch/harness.c", '-o', $binary, '-lm') == 0 or BAIL_OUT('the harness does not compile');

# run_case(\@args, NAME => value ...): runs the harness in a fresh directory
# with the stand-in tools (each exits with its FAIL_* variable, 0 if unset)
# and returns its exit status, its stderr and the tools' trace.
my $case = 0;
sub run_case {
    my ($args, %changes) = @_;
    my $d = "$scratch/case" . ++$case;
    my %fails = ('plot-go' => 'FAIL_PLOTTER', grace => 'FAIL_PLOTTER', epstopdf => 'FAIL_CONVERTER',
                 cop => 'FAIL_DATA', display => 'UNUSED');
    for my $tool (sort keys %fails) {
        spew("$d/bin/$tool", "#!/bin/sh\n"
            . ($tool eq 'plot-go' ? "[ \"\$1\" = -version ] && { [ -n \"\$PLOTGO_VERSION\" ] && echo \"plot-go \$PLOTGO_VERSION: draws Grace projects\"; exit 0; }\n" : '')
            . qq{printf "%s\\n" "$tool \$*" >> "\$TRACE"\n}
            . qq{exit "\${$fails{$tool}:-0}"\n});
        chmod 0755, "$d/bin/$tool";
    }
    # sed as macOS has it: it edits only regular files in place
    spew("$d/bin/sed", "#!/bin/sh\ncase \" \$* \" in *\" -i\"*) for f; do :; done; [ -L \"\$f\" ] && { echo \"sed: \$f: in-place editing only works for regular files\" >&2; exit 1; };; esac\nexec /usr/bin/sed \"\$@\"\n");
    chmod 0755, "$d/bin/sed";
    if (delete $changes{LINKED}) { # a per-block folder's link to the fit folder's file
        spew("$d/fit/fit-curves-1", "1 2\n");
        symlink("$d/fit/fit-curves-1", "$d/fit-curves-1") or die $!;
    }
    else { spew("$d/fit-curves-1", "1 2\n") }
    local %ENV = (%ENV, PATH => "$d/bin:/usr/bin:/bin", TRACE => "$d/trace", OFE_PLOTTER => '', %changes);
    my $cmd = join ' ', 'cd', quotemeta($d), '&&', 'timeout', '5', quotemeta($binary),
        (map { quotemeta } @$args), '>out', '2>err';
    system('/bin/sh', '-c', $cmd);
    return ($? >> 8, slurp("$d/err"), slurp("$d/trace"));
}

subtest 'plot-go normally, Grace when OFE_PLOTTER asks for it' => sub {
    my ($status, $err, $trace) = run_case([]);
    is $status, 0;
    like $trace, qr/plot-go -settype xydy/;
    ($status, $err, $trace) = run_case([], OFE_PLOTTER => 'grace');
    is $status, 0;
    like $trace, qr/grace -settype xydy/;
};

subtest 'a plot without a parameter file: plot-go when it scales bare data' => sub {
    for my $version ('1.2.0-pre3', '1.2.0', '1.2.0-rc1', '1.2.1', '1.3.0', '2.0.0', 'dev') {
        for my $args (['no-param'], ['no-param', 'display']) {
            my ($status, $err, $trace) = run_case($args, PLOTGO_VERSION => $version);
            is $status, 0, "$version @$args" or diag $err;
            like $trace, qr/^plot-go -nxy fit-curves-1 -settype xydy gnu0\.da_ -hdevice EPS -hardcopy -printfile fit-curves-1\.eps -saveall fit-curves-1\.agr/m, $version;
            if ($version eq '1.2.0-pre3') {
                like $trace, qr/^epstopdf fit-curves-1\.eps$/m;
            }
            else {
                like $trace, qr/^plot-go -nxy fit-curves-1 -settype xydy gnu0\.da_ -hdevice PDF -hardcopy -printfile fit-curves-1\.pdf$/m, "$version: its own PDF";
                unlike $trace, qr/^epstopdf/m;
            }
            unlike $trace, qr/^grace /m;
        }
    }
    my ($status, $err, $trace) = run_case(['no-param'], PLOTGO_VERSION => '1.2.0-pre3', OFE_PLOTTER => 'grace');
    like $trace, qr/^grace -nxy fit-curves-1/m, 'OFE_PLOTTER=grace still forces Grace';
};

subtest 'plot-go writes the PDF itself from v1.2.0-pre4 on, the EPS too' => sub {
    for my $version ('1.2.0-pre4', '1.2.0', '1.3.0', 'dev') {
        for my $args (['param'], ['param', 'display'], ['no-param', 'display']) {
            my ($status, $err, $trace) = run_case($args, PLOTGO_VERSION => $version);
            is $status, 0, "$version @$args" or diag $err;
            like $trace, qr/^plot-go .*-hdevice EPS -hardcopy -printfile fit-curves-1\.eps -saveall fit-curves-1\.agr$/m, "$version @$args: EPS";
            like $trace, qr/^plot-go .*-hdevice PDF -hardcopy -printfile fit-curves-1\.pdf$/m, "$version @$args: PDF";
            unlike $trace, qr/^epstopdf/m;
            if (@$args > 1) { like $trace, qr/^display fit-curves-1\.pdf$/m }
        }
    }
    my ($status, $err, $trace) = run_case(['param'], PLOTGO_VERSION => '1.2.0-pre3');
    like $trace, qr/^epstopdf fit-curves-1\.eps$/m, 'pre3: through epstopdf';
    unlike $trace, qr/-hdevice PDF/;
    ($status, $err, $trace) = run_case(['param'], PLOTGO_VERSION => '1.2.0-pre4', OFE_PLOTTER => 'grace');
    like $trace, qr/^grace .*-hdevice EPS/m, 'Grace: through epstopdf';
    like $trace, qr/^epstopdf fit-curves-1\.eps$/m;
    unlike $trace, qr/-hdevice PDF/;
    ($status, $err, $trace) = run_case(['param', 'display'], PLOTGO_VERSION => '1.2.0-pre4', FAIL_PLOTTER => 3);
    like $err, qr/plot command failed/, 'a failed plot-go';
    unlike $trace, qr/display /;
};

subtest 'a plot without a parameter file uses Grace with an older plot-go' => sub {
    for my $version ('', '1.2.0-pre2', '1.2.0-pre1', '1.1.1', '0.2.46') {
        my ($status, $err, $trace) = run_case(['no-param'], PLOTGO_VERSION => $version);
        is $status, 0, "'$version'" or diag $err;
        like $trace, qr/^grace -nxy fit-curves-1/m, "'$version'";
        unlike $trace, qr/^plot-go -/m;
    }
};

subtest 'a plot without a parameter file uses Grace defaults' => sub {
    for my $args (['no-param'], ['no-param', 'display']) {
        my ($status, $err, $trace) = run_case($args);
        is $status, 0, "@$args" or diag $err;
        like $trace, qr/grace -nxy fit-curves-1 -settype xydy gnu0\.da_/;
        like $trace, qr/-printfile fit-curves-1\.eps -saveall fit-curves-1\.agr/;
        unlike $trace, qr/epstopdf fit-curves-1\.eps -saveall/;
    }
};

# a failed plot is a warning, not a failed fit: the results are written
subtest 'a failed plotter skips the conversion and the display' => sub {
    my ($status, $err, $trace) = run_case(['param', 'display'], FAIL_PLOTTER => 7);
    is $status, 0 or diag $err;
    like $err, qr/plot command failed/;
    like $err, qr/this block's plot is missing/;
    unlike $trace, qr/epstopdf/;
    unlike $trace, qr/display /;
};

subtest 'an older plot-go forced without a parameter file warns and uses Grace' => sub {
    my ($status, $err, $trace) = run_case(['no-param'], OFE_PLOTTER => 'plot-go');
    is $status, 0 or diag $err;
    like $err, qr/needs plot-go v1\.2\.0-pre3 or later/;
    like $trace, qr/grace -nxy fit-curves-1/;
    unlike $trace, qr/plot-go -/;
};

subtest 'a failed conversion skips the display' => sub {
    my ($status, $err, $trace) = run_case(['param', 'display'], FAIL_CONVERTER => 9);
    is $status, 0 or diag $err;
    like $err, qr/plot command failed/;
    unlike $trace, qr/display /;
};

subtest 'a failed data preparation skips the plot' => sub {
    my ($status, $err, $trace) = run_case([], FAIL_DATA => 4);
    is $status, 0 or diag $err;
    like $err, qr/preparation failed/;
    unlike $trace, qr/plot-go -/;
};

subtest 'a curve file that is a link (a per-block folder) is plotted' => sub {
    my ($status, $err, $trace) = run_case(['param'], LINKED => 1);
    is $status, 0 or diag $err;
    unlike $err, qr/plot command failed/;
    like $trace, qr/plot-go -settype xydy gnu0\.da_ -nxy fit-curves-1 -param/;
    like $trace, qr/epstopdf fit-curves-1\.eps/;
};

done_testing;
