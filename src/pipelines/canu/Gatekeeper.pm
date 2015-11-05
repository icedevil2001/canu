
###############################################################################
 #
 #  This file is part of canu, a software program that assembles whole-genome
 #  sequencing reads into contigs.
 #
 #  This software is based on:
 #    'Celera Assembler' (http://wgs-assembler.sourceforge.net)
 #    the 'kmer package' (http://kmer.sourceforge.net)
 #  both originally distributed by Applera Corporation under the GNU General
 #  Public License, version 2.
 #
 #  Canu branched from Celera Assembler at its revision 4587.
 #  Canu branched from the kmer project at its revision 1994.
 #
 #  This file is derived from:
 #
 #    src/pipelines/ca3g/Gatekeeper.pm
 #
 #  Modifications by:
 #
 #    Brian P. Walenz beginning on 2015-FEB-27
 #      are Copyright 2015 Battelle National Biodefense Institute, and
 #      are subject to the BSD 3-Clause License
 #
 #  File 'README.licenses' in the root directory of this distribution contains
 #  full conditions and disclaimers for each license.
 ##

package canu::Gatekeeper;

require Exporter;

@ISA    = qw(Exporter);
@EXPORT = qw(getNumberOfReadsInStore getNumberOfBasesInStore getExpectedCoverage gatekeeper);

use strict;

use canu::Defaults;
use canu::Execution;



sub storeExists ($$) {
    my $wrk    = shift @_;
    my $asm    = shift @_;

    return (-e "$wrk/$asm.gkpStore");
}



sub getNumberOfReadsInStore ($$) {
    my $wrk    = shift @_;
    my $asm    = shift @_;
    my $nr     = 0;

    #  No file, no reads.

    return($nr)   if (! -e "$wrk/$asm.gkpStore/info.txt");

    #  Read the info file.  gatekeeperCreate creates this at the end.

    open(F, "< $wrk/$asm.gkpStore/info.txt") or caExit("can't open '$wrk/$asm.gkpStore/info.txt' for reading: $!", undef);
    while (<F>) {
        if (m/numReads\s+=\s+(\d+)/) {
            $nr = $1;
        }
    }
    close(F);

    return($nr);
}



sub getNumberOfBasesInStore ($$) {
    my $wrk    = shift @_;
    my $asm    = shift @_;
    my $nb     = 0;
    my $bin    = getBinDirectory();

    #  No file, no bases.

    return($nb)   if (! -e "$wrk/$asm.gkpStore/info.txt");

    if (! -e "$wrk/$asm.gkpStore/reads.txt") {
        runCommandSilently("$wrk/$asm.gkpStore", "$bin/gatekeeperDumpMetaData -G . -reads > reads.txt 2> /dev/null");
    }

    #  Read the info file.  gatekeeperCreate creates this at the end.

    open(F, "< $wrk/$asm.gkpStore/reads.txt") or caExit("can't open '$wrk/$asm.gkpStore/reads.txt' for reading: $!", undef);
    while (<F>) {
        my @v = split '\s+', $_;
        $nb += $v[2];
    }
    close(F);

    return($nb);
}



sub getExpectedCoverage ($$) {
    my $wrk = shift @_;
    my $asm = shift @_;

    return(int(getNumberOfBasesInStore($wrk, $asm) / getGlobal("genomeSize")));
}



sub gatekeeper ($$$@) {
    my $WRK    = shift @_;  #  Root work directory
    my $wrk    = $WRK;
    my $asm    = shift @_;
    my $tag    = shift @_;
    my $bin    = getBinDirectory();
    my @inputs = @_;

    $wrk = "$wrk/correction"  if ($tag eq "cor");
    $wrk = "$wrk/trimming"    if ($tag eq "obt");

    #  An empty store?  Remove it and try again.

    if ((storeExists($wrk, $asm)) && (getNumberOfReadsInStore($wrk, $asm) == 0)) {
        print STDERR "-- Removing empty or incomplate gkpStore '$wrk/$asm.gkpStore'\n";
        runmCommandSilently($wrk, "rm -rf $wrk/$asm.gkpStore");
    }

    #  Store with reads?  Yay!  Report it, then skip.

    goto allDone    if (skipStage($WRK, $asm, "$tag-gatekeeper") == 1);
    goto allDone    if (getNumberOfReadsInStore($wrk, $asm) > 0);

    print STDERR "--\n";
    print STDERR "-- GATEKEEPER (correction)\n"  if ($tag eq "cor");
    print STDERR "-- GATEKEEPER (trimming)\n"    if ($tag eq "obt");
    print STDERR "-- GATEKEEPER (assembly)\n"    if ($tag eq "utg");
    print STDERR "--\n";

    caExit("no input files specified, and store not already created, I have nothing to work on!", undef)
        if (scalar(@inputs) == 0);

    #  Make sure all the inputs are here.

    my $failedFiles = undef;

    foreach my $iii (@inputs) {
        my $file = $iii;  #  This stupid foreach works by reference!

        $file = $2  if ($file =~ m/^(.*):(.*)/);   #  Handle the raw sequence inputs.

        if (! -e $file) {
            if (defined($failedFiles)) {
                $failedFiles .= "; '$file' not found";
            } else {
                $failedFiles = "'$file' not found";
            }
        }
    }
    caExit($failedFiles, undef) if defined($failedFiles);

    #  Build a gkp file for all the raw sequence inputs.  For simplicity, we just copy in any gkp
    #  files as is.  This documents what gatekeeper was built with, etc.

    open(F, "> $wrk/$asm.gkpStore.gkp") or caExit("cant' open '$wrk/$asm.gkpStore.gkp' for writing: $0", undef);

    foreach my $iii (@inputs) {
        if ($iii =~ m/^-(.*):(.*)$/) {
            my $tech = $1;
            my $file = $2;
            my @name = split '/', $2;
            my $name = $name[scalar(@name)-1];

            print F "########################################\n";
            print F "#  $tech: $file\n";
            print F "#\n";
            print F "name   $name\n";
            print F "preset $tech\n";
            print F "$file\n";
            print F "\n";

        } elsif (-e $iii) {
            print F "########################################\n";
            print F "#  $iii\n";
            print F "#\n";
            open(I, "< $iii") or caExit("can't open gatekeeper input '$iii' for reading: $0", undef);
            while (<I>) {
                print F $_;
            }
            close(I);
            print F "\n";

        } else {
            caExit("unrecognized gatekeeper input file '$iii'", undef);
        }
    }

    close(F);

    #  Load the store.

    my $cmd;
    $cmd .= "$bin/gatekeeperCreate \\\n";
    $cmd .= "  -minlength " . getGlobal("minReadLength") . " \\\n";
    $cmd .= "  -o $wrk/$asm.gkpStore.BUILDING \\\n";
    $cmd .= "  $wrk/$asm.gkpStore.gkp \\\n";
    $cmd .= "> $wrk/$asm.gkpStore.err 2>&1";

    stopBefore("gatekeeper", $cmd);

    if (runCommand($wrk, $cmd)) {
        caExit("gatekeeper failed", "$wrk/$asm.gkpStore.err");
    }

    rename "$wrk/$asm.gkpStore.BUILDING",             "$wrk/$asm.gkpStore";
    rename "$wrk/$asm.gkpStore.BUILDING.errorLog",    "$wrk/$asm.gkpStore.errorLog";

    #  Generate some statistics.

    if (! -e "$wrk/$asm.gkpStore/reads.txt") {
        runCommandSilently("$wrk/$asm.gkpStore", "$bin/gatekeeperDumpMetaData -G . -reads > reads.txt 2> /dev/null");
    }

    if (! -e "$wrk/$asm.gkpStore/readlengths.txt") {
        my $nb = 0;
        my @rl;
        my @hi;
        my $mm;

        open(F, "< $wrk/$asm.gkpStore/reads.txt") or caExit("can't open '$wrk/$asm.gkpStore/reads.txt' for reading: $!", undef);
        while (<F>) {
            my @v = split '\s+', $_;

            push @rl, $v[2];           #  Save the length
            $nb += $v[2];              #  Sum the bases
            $hi[int($v[2] / 1000)]++;  #  Add to the histogram (int truncates)
        }
        close(F);

        @rl = sort { $a <=> $b } @rl;
        $mm = int($rl[scalar(@rl)-1] / 1000);  #  max histogram value

        open(F, "> $wrk/$asm.gkpStore/readlengths.txt") or caExit("can't open '$wrk/$asm.gkpStore/readlengths.txt' for writing: $!", undef);
        foreach my $rl (@rl) {
            print F "$rl\n";
        }
        close(F);

        open(F, "> $wrk/$asm.gkpStore/readlengthhistogram.txt") or caExit("can't open '$wrk/$asm.gkpStore/readlengthhistogram.txt' for writing: $!", undef);
        for (my $ii=0; $ii<=$mm; $ii++) {
            my $s = $ii * 1000;
            my $e = $ii * 1000 + 999;

            $hi[$ii] += 0;  #  Otherwise, cells with no count print as null.

            print F "$s\t$e\t$hi[$ii]\n";
        }
        close(F);
    }

    if (! -e "$wrk/$asm.gkpStore/readlengths.png") {
        open(F, "> $wrk/$asm.gkpStore/readlengths.gp") or caExit("can't open '$wrk/$asm.gkpStore/readlengths.gp' for writing: $!", undef);

        print F "set title 'sorted read lengths'\n";
        #print F "set xlabel 'original read length'\n";
        print F "set ylabel 'read length'\n";
        print F "set pointsize 0.25\n";
        print F "set terminal png size 1024,1024\n";
        print F "set output '$wrk/$asm.gkpStore/readlengths.png'\n";
        print F "plot '$wrk/$asm.gkpStore/readlengths.txt' title 'sorted read length' with lines\n";
        close(F);
        runCommandSilently("$wrk/$asm.gkpStore", "gnuplot < $wrk/$asm.gkpStore/readlengths.gp > /dev/null 2>&1");
    }


  finishStage:
    emitStage($WRK, $asm, "$tag-gatekeeper");
    stopAfter("gatekeeper");

  allDone:
    my $reads    = getNumberOfReadsInStore($wrk, $asm);
    my $bases    = getNumberOfBasesInStore($wrk, $asm);
    my $coverage = int(100 * $bases / getGlobal("genomeSize")) / 100;
    my $maxhist  = 0;

    open(F, "< $wrk/$asm.gkpStore/readlengthhistogram.txt") or caExit("can't open '$wrk/$asm.gkpStore/readlengthhistogram.txt' for reading: $!", undef);
    while (<F>) {
        my @v = split '\s+', $_;
        $maxhist = ($maxhist < $v[2]) ? $v[2] : $maxhist;
    }
    close(F);

    my $scale = $maxhist / 70;

    print STDERR "--\n";
    print STDERR "-- In gatekeeper store '$wrk/$asm.gkpStore':\n";
    print STDERR "--   Found $reads reads.\n";
    print STDERR "--   Found $bases bases ($coverage times coverage).\n";
    print STDERR "--\n";
    print STDERR "--   Read length histogram (one '*' equals ", int(100 * $scale) / 100, " reads):\n";

    open(F, "< $wrk/$asm.gkpStore/readlengthhistogram.txt") or caExit("can't open '$wrk/$asm.gkpStore/readlengthhistogram.txt' for reading: $!", undef);
    while (<F>) {
        my @v = split '\s+', $_;

        printf STDERR "--   %6d %6d %6d %s\n", $v[0], $v[1], $v[2], "*" x int($v[2] / $scale);
    }
    close(F);
}
