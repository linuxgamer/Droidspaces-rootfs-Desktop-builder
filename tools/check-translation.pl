#!/usr/bin/perl
# check-translation.pl — fail if Chinese text is left outside the Chinese docs.
#
# Usage: perl tools/check-translation.pl [repo-root]
#
# A line is accepted when it carries upstream's Chinese+English twin, e.g.
#   log "<zh text>" "Could not record the version."
#   printf '%s' "10158 3003 9997 20158 50158msg '<zh text>' '<en text>')"
# Lines that are Chinese-only, including comments, are reported as failures.
# Chinese reference docs (README.zh.md, scripts/README_zh.md, docs/zh/) are skipped.
use strict;
use warnings;
use utf8;
binmode(STDOUT, ':encoding(UTF-8)');

my $root = shift @ARGV // '.';

my @files = grep { !/\.(?:jpe?g|png|gif|webp|ico|tar|gz|xz|zip)$/i }
    split /\n/, `git -C '$root' -c core.quotepath=false ls-files`;

sub is_zh_doc {
    my $f = shift;
    return 1 if $f eq 'README.zh.md';
    return 1 if $f eq 'scripts/README_zh.md';
    return 1 if $f =~ m{^docs/zh/};
    return 1 if $f eq 'LICENSE';
    return 0;
}

# A line counts as already bilingual when an English string follows the Chinese
# one, which is this project's convention:
#     log "<zh text>" "<en text>"
#     printf '%s' "$(msg '<zh text>' '<en text>')"
#     message "<zh text>" "<en text>"
#
# The test is: take the text after the LAST Chinese character and look for a
# quoted English string there. Working from the tail survives nested quoting such
# as "$(msg "zh" "en")", which a flat quote scanner cannot parse, and it stops a
# shell variable ("$OPTARG") or a trailing comment from being mistaken for a twin
# because those sit before the Chinese or contain no English words.

sub is_bilingual_pair {
    my $line = shift;

    my $last_han = -1;
    while ($line =~ /\p{Han}/g) { $last_han = $+[0] }
    return 0 if $last_han < 0;

    my $tail = substr($line, $last_han);
    return 0 if $tail eq '';

    # Try every quote in the tail as a possible OPENING quote. Starting only at the
    # first one would land on the closing quote of the Chinese string and consume the
    # English string as an "even" partner, so quote parity has to be ignored.
    my @positions;
    push @positions, $-[0] while $tail =~ /["']/g;

    for my $p (@positions) {
        my $sub = substr($tail, $p);
        next unless $sub =~ /^(["'])((?:\\.|(?!\1)[^\\])*)\1/s;
        my $atom = $2;
        next if $atom =~ /\p{Han}/;
        return 1 if $atom =~ /[A-Za-z]{3,}/;
    }
    return 0;
}

# Chinese that is deliberately kept because it is FUNCTIONAL, not prose: it is
# matched against output produced by upstream code, so translating it would break
# behaviour. Each entry is scoped to one file and one narrow line shape, and every
# entry must say why — this list is not a place to hide untranslated text.
#
# 1. Confirmation prompts accept the Chinese word for yes (0x662f) as an extra
#    affirmative token. It only widens accepted input; English users are unaffected
#    and Chinese users keep working.
# 2. droidspaces-tui.sh detects the *old upstream one-shot installer*, which prints
#    Chinese. The pattern must match that Chinese output to keep compatibility.
# 3. install-usb-manager.sh patches strings inside the upstream USB manager, whose
#    own UI is Chinese, so the search and replacement text must stay Chinese.
my @functional_chinese = (
    {
        file  => qr{scripts/tui/(?:droidspaces-tui|install-tui|install-mesa|install-winefonts)\.sh$},
        line  => qr/y\|yes\|(?:1\|)?\x{662f}\)/,
        why   => 'accepts the Chinese word for yes as an extra affirmative token',
    },
    {
        file  => qr{scripts/tui/droidspaces-tui\.sh$},
        line  => qr/\[\[ "\$output" == \*/,
        why   => 'matches Chinese output of the legacy upstream one-shot installer',
    },
    {
        file  => qr{scripts/install-usb-manager\.sh$},
        line  => qr/^\s*-e 's\|.*sudo apt install python3-pyqt5/,
        why   => 'rewrites a Chinese message inside the upstream Chinese-language USB manager',
    },
    {
        file  => qr{scripts/generate-rootfs-manifests\.sh$},
        line  => qr/^\s*\[[\w.-]+\]='|^\s*(?:name|description)="\$\{distro_(?:name|detail_zh)/,
        why   => 'manifest descriptions for the zh release channel are Chinese data, like docs/zh',
    },
    {
        file  => qr{scripts/publish-cnb-rootfs\.sh$},
        line  => qr/^\s*release_(?:name|body)=/,
        why   => 'the CNB mirror publishes release notes for Chinese readers, like docs/zh',
    },
    {
        file  => qr{^(?:README\.md|scripts/README\.md|docs/en/README\.md)$},
        line  => qr{\[[^\]]*\]\((?:README\.zh\.md|README_zh\.md|\.\./zh/README\.md)\)},
        why   => 'language-switcher links label the Chinese docs in Chinese',
    },
);

sub is_functional_chinese {
    my ($file, $line) = @_;
    for my $entry (@functional_chinese) {
        next unless $file =~ $entry->{file};
        return 1 if $line =~ $entry->{line};
    }
    return 0;
}

my @bad;
for my $f (@files) {
    next if is_zh_doc($f);
    open my $fh, '<:encoding(UTF-8)', "$root/$f" or next;
    my @raw = <$fh>;
    close $fh;

    my @logical;
    my ($buf, $start, $n) = ('', 1, 0);
    for my $l (@raw) {
        $n++;
        $start = $n if $buf eq '';
        if ($l =~ /\\\s*$/) {
            # Drop the line-continuation backslash so the call reads as one line.
            $l =~ s/\\\s*$//;
            $buf .= $l . ' ';
            next;
        }
        push @logical, [$start, $buf . $l];
        $buf = '';
    }
    push @logical, [$start, $buf] if $buf ne '';

    for my $e (@logical) {
        my ($ln, $l) = @$e;
        next unless $l =~ /\p{Han}/;
        next if is_bilingual_pair($l);
        next if is_functional_chinese($f, $l);
        # Collapse the joined continuation lines so one finding is one output line.
        (my $t = $l) =~ s/\s*\n\s*/ /g;
        $t =~ s/\s+$//;
        push @bad, "$f:$ln: $t";
    }
}

if (@bad) {
    print "Chinese text still present outside the Chinese docs:\n";
    print "$_\n" for @bad;
    print "\n", scalar(@bad), " line(s) need translation.\n";
    exit 1;
}
print "OK: no untranslated Chinese outside the Chinese reference docs.\n";
exit 0;
