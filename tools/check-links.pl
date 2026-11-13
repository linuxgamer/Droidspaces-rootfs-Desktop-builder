#!/usr/bin/perl
# check_links.pl — verify that relative links/anchors in Markdown resolve.
#
# Usage: perl check_links.pl <repo-root>
# Exit code 1 if any broken relative link is found.
use strict;
use warnings;
use utf8;
binmode(STDOUT, ':encoding(UTF-8)');

my $root = shift @ARGV or die "usage: check_links.pl <repo-root>\n";
my $list = `cd '$root' && git -c core.quotepath=false ls-files`;
my @md = grep { /\.md$/ } split /\n/, $list;

my @broken;
my $checked = 0;

for my $file (@md) {
    open my $fh, '<:encoding(UTF-8)', "$root/$file" or next;
    my @lines = <$fh>;
    close $fh;
    my $lineno = 0;
    for my $line (@lines) {
        $lineno++;
        # Markdown inline links: [text](target)
        while ($line =~ /\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g) {
            my $target = $1;
            next if $target =~ m{^(?:https?:|mailto:|#|ftp:)};
            next if $target eq '';
            (my $path = $target) =~ s/#.*$//;
            next if $path eq '';
            $checked++;
            my ($dir) = $file =~ m{^(.*)/[^/]+$};
            $dir = '' unless defined $dir;
            my $resolved = $dir eq '' ? $path : "$dir/$path";
            # Normalize ./ and ../ segments
            my @parts;
            for my $seg (split m{/}, $resolved) {
                next if $seg eq '' || $seg eq '.';
                if ($seg eq '..') { pop @parts; next }
                push @parts, $seg;
            }
            my $norm = join '/', @parts;
            unless (-e "$root/$norm") {
                push @broken, "$file:$lineno -> $target";
            }
        }
    }
}

print "Checked $checked relative links in ", scalar(@md), " Markdown files.\n";
if (@broken) {
    print "\nBROKEN (", scalar(@broken), "):\n";
    print "$_\n" for @broken;
    exit 1;
}
print "All relative links resolve.\n";
