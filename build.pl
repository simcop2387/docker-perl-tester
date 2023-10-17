#!/usr/bin/env perl

use strict;
use warnings;
use v5.30;

use IO::Async;
use IO::Async::Function;
use IO::Async::Loop::Epoll;
use Getopt::Long;
use Future;
use Path::Tiny;
use IPC::Run;
use Time::HiRes qw/time usleep/;
use Syntax::Keyword::Try;
use Time::Piece;

my @bases = qw/bullseye-backports bookworm-backports/;
my @options = ("main", "main-threaded", "main-longdouble", "main-quadmath", "main-debugging", "main-longdouble-threaded", "main-quadmath-threaded", "main-debugging-threaded", "main-debugging-longdouble-threaded", "main-debugging-quadmath-threaded", "main-debugging-longdouble", "main-debugging-quadmath");
my @versions = ("5.20.3", "5.22.4", "5.24.4", "5.26.3", "5.28.3", "5.30.3", "5.32.1", "5.34.0", "5.34.1", "5.36.0", "5.36.1", "5.38.0");
my $max_workers = 8;
my $verbose = 1;
my $suffix = "";
my $arch = 'amd64';
my %build_args = ();
my $skip_build = 0;
my @push_repo = ();

my %major_versions = (
  5.10 => '5.10.1',
  5.12 => '5.12.5',
  5.14 => '5.14.4',
  5.16 => '5.16.3',
  5.18 => '5.18.4',
  5.20 => '5.20.3',
  5.22 => '5.22.4',
  5.24 => '5.24.4',
  5.26 => '5.26.3',
  5.28 => '5.28.3',
  5.30 => '5.30.3',
  5.32 => '5.32.1',
  5.34 => '5.34.1',
  5.36 => '5.36.1',
  5.38 => '5.38.0',
);

my $filter_tags_str = '.';

my $commit_ref = $ENV{CI_COMMIT_REF} // 'unknown';

GetOptions('verbose' => \$verbose,
           'quiet' => sub {$verbose = 0},
           'workers=i' => \$max_workers,
           'suffix=s' => \$suffix,
           'arch=s' => \$arch,
           'build_args=s%' => \%build_args,
           'skip_build' => \$skip_build,
           'filter_tags=s' => \$filter_tags_str,
           'push_repo=s@' => \@push_repo,
         );

my $filter_tags_re = qr/$filter_tags_str/;

my $arch_suffix="-$arch";

if ($suffix) {
  $suffix = "-$suffix";
}

my $loop = IO::Async::Loop::Epoll->new();

sub get_tags {
        my ($version, $options, $os_base, $suffix, $arch_suffix) = @_;

        my $expanded_version = $version =~ s/(?<major>5)\.(?<minor>\d+)\.(?<patch>\d+)/sprintf "%d.%03d.%03d", $+{major}, $+{minor}, $+{patch}/er;
        my $short_version = "$+{major}.$+{minor}";

        my @t = (
          "$version-$options-$os_base$suffix$arch_suffix", "$expanded_version-$options-$os_base$suffix$arch_suffix",
          "$version-$options-$os_base$suffix", "$expanded_version-$options-$os_base$suffix",
          "$version-$options-$os_base$arch_suffix", "$expanded_version-$options-$os_base$arch_suffix",
          "$version-$options-$os_base", "$expanded_version-$options-$os_base",
        );
       
        if (grep {$version eq $_} values %major_versions) {
            push @t, (
              "$short_version-$options-$os_base$suffix$arch_suffix",
              "$short_version-$options-$os_base$suffix",
              "$short_version-$options-$os_base$arch_suffix",
              "$short_version-$options-$os_base"
            );
        }

        return \@t;
}

sub get_ts {
  my $t = time();

  return sprintf "%0.04f", $t;
}

sub process_lines {
  my ($disp_prefix, $type, $log_fh, $lines) = @_;

  while ($$lines =~ /\n/m) {
    my $ts = get_ts();
    $$lines =~ s/^(.*?)\n//m;
    my $raw_line = $1;

    my $log_line = "$ts $type: $raw_line\n";
    my $disp_line = "$disp_prefix - $ts $type: $raw_line\n";
    print $disp_line;
    $log_fh->print($log_line);
  }
}

sub run_cmd {
   my ($cmd,$disp_prefix,$log_fh,$input) = @_;

   my ($raw_out, $raw_err);

   try {

   print "Running command $disp_prefix: ".join(' ', @$cmd), "\n";

   return if $skip_build;

   my $handle = IPC::Run::start $cmd, \$input, \$raw_out, \$raw_err; # no timeout here, that's part of the ::Function

   while ($handle->pumpable) {
     $handle->pump();

     process_lines($disp_prefix, "[OUT]", $log_fh, \$raw_out);
     process_lines($disp_prefix, "[ERR]", $log_fh, \$raw_err);

     $handle->reap_nb();
     usleep(100);
   }

   # Nothing we do here is a fatal error.
   finish $handle;

   my $return = $?;

   print "Finished $disp_prefix => $return\n";

   return ($return);
  } catch {
    my $e = $@;

    print "$disp_prefix: $e\n";
    print $log_fh "---------------------\n";
    print $log_fh "Exception: $e\n";
    print $log_fh "---------------------\n";
    return -1;
  }
}

my $builder = IO::Async::Function->new(
   code => sub {
      my ( $version, $options, $os_base ) = @_;

      try {
        my $expanded_version = $version =~ s/(?<major>5)\.(?<minor>\d+)\.(?<patch>\d+)/sprintf "%d.%03d.%03d", $+{major}, $+{minor}, $+{patch}/er;

        my $tags = get_tags($version, $options, $os_base, $suffix, $arch_suffix); 
        
        my $build_date = Time::Piece::gmtime()->datetime();

        my %labels = (
         "org.opencontainers.image.created"=>$build_date,
         "org.label-schema.build-date"=>$build_date,
         "org.opencontainers.image.source"=>"https://gitea.simcop2387.info/simcop2387/docker-perl.git",
         "org.label-schema.vcs-url"=> "https://gitea.simcop2387.info/simcop2387/docker-perl.git",
         "org.opencontainers.image.url"=>"https://gitea.simcop2387.info/simcop2387/docker-perl",
         "org.label-schema.url"=>"https://gitea.simcop2387.info/simcop2387/docker-perl",
         "org.label-schema.usage"=> "https://gitea.simcop2387.info/simcop2387/docker-perl",
         "org.opencontainers.image.revision"=>$commit_ref,
         "org.label-schema.vcs-ref"=> $commit_ref,
         "org.label-schema.version"=> $version,
         "org.label-schema.name"=> "perl-$options",
         "org.label-schema.schema-version"=> "1.0",
       );

        my ($total_output, $total_error, $retval);

        my $startdir = path("output/perls");
        my $log_dir = path("output/logs");
        $log_dir->mkdir();
        my $log_file = $log_dir->child("$expanded_version-$options-$os_base$suffix$arch_suffix-build.log");
        my $log_fh   = $log_file->openw_utf8();
        my $workdir = $startdir->child("$expanded_version-$options-$os_base/");

        if ($workdir->exists()) {
          chdir($workdir);
          my @tag_args = ();

          for my $push_repo (@push_repo) {
            push @tag_args, map {("-t", "${push_repo}:$_")} @$tags;
          }

          my @labels = map {my $k=$_; my $v=$labels{$k}; ("--label", "$k=$v")} keys %labels;
          my @buildargs = map {my $k=$_; my $v=$build_args{$k}; ("--build-arg", "$k=$v")} keys %build_args;

          my $cmd = [qw(docker buildx build --rm=true -f Dockerfile ./ --push --pull=true), @buildargs, @tag_args, @labels];

          print "tags: [", join(', ', @$tags), "]\n";

          my ($output, $error, $retval) = run_cmd($cmd, $tags->[0], $log_fh, "");
        } else {
          print "Failed to find $workdir\n";
        }

        $log_fh->close();

        # Should probably return a success or failure
        return;
      } catch {
        my $e = $@;

        print "EXCEPTION: $e\n";
        return;
      }
   },

   max_workers => $max_workers,
   min_workers => 1,
   max_worker_calls => 1, # always restart, we want to throw away side effects like chdir
   model => "fork",
);

$loop->add($builder);
$builder->start();

my %calls;

#my $count = 0;

ALL: for my $version (@versions) {
  for my $option (@options) {
    for my $base (@bases) {
      #      print "---> $count\n";
      #      last ALL if $count++ == 10;

      my $tags = get_tags($version, $option, $base, $suffix, $arch_suffix); 

      if (grep {$_ =~ /$filter_tags_re/} @$tags) {


        my $rend = "$version-$option-$base";
        my $future = $builder->call(args => [$version, $option, $base])->on_ready(sub {
          delete $calls{$rend};
        });
        $calls{$rend} = $future;
      } else {
        print "Not building $version-$option-$base due to filter\n";
      }
    }
  }
}

my $full_future = Future->wait_all( values %calls );

while (1) {
  print "Is ready? ", $full_future->is_ready()?"yes":"no", "\n";

  my @pending = $full_future->pending_futures;

  print "Pending: ", 0+@pending, "\n";
  print join(", ", keys %calls), "\n";

  print "workers: ", $builder->workers, ", ", $builder->workers_idle, ", ", $builder->workers_busy, "\n";

  $loop->delay_future(after => 1)->get();

  if (@pending < 1) {
    last;
  }
}

my @result = $full_future->get();

use Data::Dumper;
#print Dumper(\@result);
