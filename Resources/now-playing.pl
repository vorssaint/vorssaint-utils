#!/usr/bin/perl
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
#
# Loads the Now Playing adapter library into perl and prints one JSON line.
# perl is a platform binary, so MediaRemote answers it where it no longer
# answers the app (macOS 15.4+). See Sources/NowPlayingAdapter.
use strict;
use warnings;
use DynaLoader;

$| = 1;
my ($library) = @ARGV;
die "usage: now-playing.pl <adapter library>\n" unless defined $library && -f $library;
my $handle = DynaLoader::dl_load_file($library, 0)
    or die "now-playing: cannot load adapter: " . DynaLoader::dl_error() . "\n";
my $symbol = DynaLoader::dl_find_symbol($handle, "vorssaint_now_playing_get")
    or die "now-playing: adapter entry point missing: " . DynaLoader::dl_error() . "\n";
DynaLoader::dl_install_xsub("main::vorssaint_now_playing_get", $symbol);
vorssaint_now_playing_get();
