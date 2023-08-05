#!/usr/bin/perl
# very simple bot that tails a nethack xlogfile and posts to mastodon.
#
# this started out as https://codeberg.org/kvibber/fedbotrandom
#
# run without any parameters to use config from fedbot_nao.config,
# or pass the config file name to use as the first parameter.
#

use strict;
use warnings;
use LWP;
use Fcntl qw(SEEK_END);

# Load config file
my $configPath = $ARGV[0] || 'fedbot_nao.config';
my %CONFIG;

open configFile, '<', $configPath || die "Cannot open configuration at $configPath";

my @lines = <configFile>;
close configFile;
foreach my $configLine(@lines) {
    if ($configLine =~ /^\s*([A-Za-z0-9_]+)\s*:\s*(.*)\s*$/) {
        $CONFIG{$1}=$2;
    }
}


sub parse_xlogline {
    my $line = shift;

    my %ret;
    my @dat = ( split( /\t/, $line) );

    foreach my $a (@dat) {
        my @t = ( split( /=/, $a) );
        $ret{$t[0]} = $t[1];
    }

    $ret{firstchar} = substr($ret{name}, 0, 1);

    return %ret;
}


my $first_warn_not_posting = 0;

sub post_to_fed {
    my $content = shift;

    return if (!$content || $content eq "");

    if (!exists($CONFIG{'INSTANCE_HOST'}) || !exists($CONFIG{'API_ACCESS_TOKEN'})) {
        print STDERR "Not posting, missing either INSTANCE_HOST or API_ACCESS_TOKEN\n" if (!$first_warn_not_posting);
        $first_warn_not_posting = 1;
        print "\nContent:$content\n";
        return;
    }

    my $url = "https://${CONFIG{'INSTANCE_HOST'}}/api/v1/statuses?access_token=${CONFIG{'API_ACCESS_TOKEN'}}";


    my $browser = LWP::UserAgent->new;

    my $response = $browser->post( $url,
                                   [
                                    status => $content,
                                    visibility => $CONFIG{'VISIBILITY'} || 'unlisted'
                                   ],
        );

    if ($response->is_success) {
        print "Posted [$content]\n";
    } else {
	print STDERR "Failed: " , $response->status_line, "\n";
    }
}


sub tail {
    open my $loghandle, '<', $CONFIG{'TAIL_FILE'}
        or die "Unable to open " . $CONFIG{'TAIL_FILE'} . " for reading: $!";

    my $line;
    my $sleepwait = int($CONFIG{'SLEEP_WAIT'} || 5);

    $sleepwait = 5 if ($sleepwait < 1);

    seek $loghandle, 0, SEEK_END;

    $loghandle->clearerr();

    while (1) {
        $line = <$loghandle>;
        if (!$line || !($line =~ /\n$/) || ($line =~ /^\s*$/)) {
            $loghandle->clearerr();
            sleep $sleepwait;
            next;
        }

        $line =~ s/\n$//;

        if (exists($CONFIG{'LINE_EXTRA_DATA'})) {
            $line .= "\t$CONFIG{'LINE_EXTRA_DATA'}";
        }

        my %d = parse_xlogline($line);

        if (exists($CONFIG{'FILTER'})) {
            my $filter = $CONFIG{'FILTER'};
            if ($filter =~ /^([^=]+)=(.*)$/) {
                my ($fld, $dat) = ($1, $2);
                next if (!exists($d{$fld}));
                next if ($d{$fld} ne $dat);
            } else {
                next if (!($line =~ /$CONFIG{'FILTER'}/));
            }
        }

        my $str = "#NetHack $d{version}: $d{name} ($d{role} $d{race} $d{gender} $d{align}) $d{death} with $d{points} points, in $d{turns} turns.";

        if (exists($d{dumpfileurl}) && exists($d{dumpfileext})) {
            $str .= "\n$d{dumpfileurl}/$d{firstchar}/$d{name}/dumplog/$d{starttime}.$d{dumpfileext}";
        }

        post_to_fed($str);
    }
}

tail();
