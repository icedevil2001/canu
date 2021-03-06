
/******************************************************************************
 *
 *  This file is part of canu, a software program that assembles whole-genome
 *  sequencing reads into contigs.
 *
 *  This software is based on:
 *    'Celera Assembler' (http://wgs-assembler.sourceforge.net)
 *    the 'kmer package' (http://kmer.sourceforge.net)
 *  both originally distributed by Applera Corporation under the GNU General
 *  Public License, version 2.
 *
 *  Canu branched from Celera Assembler at its revision 4587.
 *  Canu branched from the kmer project at its revision 1994.
 *
 *  Modifications by:
 *
 *    Brian P. Walenz beginning on 2018-JUL-21
 *      are a 'United States Government Work', and
 *      are released in the public domain
 *
 *  File 'README.licenses' in the root directory of this distribution contains
 *  full conditions and disclaimers for each license.
 */

#include "kmers.H"
#include "bits.H"

#include "files.H"


kmerCountStatistics::kmerCountStatistics() {
  _numUnique     = 0;
  _numDistinct   = 0;
  _numTotal      = 0;

  _histMax       = 32 * 1024 * 1024;      //  256 MB of histogram data.
  _hist          = new uint64 [_histMax];

  for (uint64 ii=0; ii<_histMax; ii++)
    _hist[ii] = 0;

  _hbigLen       = 0;
  _hbigMax       = 0;
  _hbigCount     = NULL;
  _hbigNumber    = NULL;
}


kmerCountStatistics::~kmerCountStatistics() {
  delete [] _hist;
  delete [] _hbigCount;
  delete [] _hbigNumber;
}



void
kmerCountStatistics::clear(void) {
  _numUnique     = 0;
  _numDistinct   = 0;
  _numTotal      = 0;

  for (uint64 ii=0; ii<_histMax; ii++)
    _hist[ii] = 0;

  _hbigLen       = 0;
}



void
kmerCountStatistics::dump(stuffedBits *bits) {
  bits->setBinary(64, _numUnique);
  bits->setBinary(64, _numDistinct);
  bits->setBinary(64, _numTotal);

  //  Find the last used histogram value.

  uint32  histLast = _histMax;

  while (histLast-- > 0)
    if (_hist[histLast] > 0)
      break;

  histLast++;

  bits->setBinary(32, histLast);                //  Out of order relative to struct to keep
  bits->setBinary(32, _hbigLen);                //  the arrays below word-aligned.

  bits->setBinary(64, histLast, _hist);
  bits->setBinary(64, _hbigLen, _hbigCount);
  bits->setBinary(64, _hbigLen, _hbigNumber);
}


void
kmerCountStatistics::dump(FILE        *outFile) {
  stuffedBits  *bits = new stuffedBits;

  dump(bits);

  bits->dumpToFile(outFile);

  delete bits;
}


void
kmerCountStatistics::load(stuffedBits *bits) {
  uint32  histLast;

  _numUnique   = bits->getBinary(64);
  _numDistinct = bits->getBinary(64);
  _numTotal    = bits->getBinary(64);

  histLast     = bits->getBinary(32);
  _hbigLen     = bits->getBinary(32);

  assert(_hist != NULL);

  _hist        = bits->getBinary(64, histLast, _hist);
  _hbigCount   = bits->getBinary(64, _hbigLen);
  _hbigNumber  = bits->getBinary(64, _hbigLen);
}


void
kmerCountStatistics::load(FILE        *inFile) {
  stuffedBits  *bits = new stuffedBits;

  bits->loadFromFile(inFile);

  load(bits);

  delete bits;
}

