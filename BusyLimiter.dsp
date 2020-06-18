declare author "Bart Brouns";
declare name "BusyLimiter";
declare version "0.1";
declare license "AGPLv3";

import("stdfaust.lib");
// TODO: slidingReduce uses too mny blocks:
// if you use a power of 2 for N, there should be no locks turned off, but there are.
// sr = library("slidingReduce.lib");

/*

-



*/

///////////////////////////////////////////////////////////////////////////////
//                                  process                                  //
///////////////////////////////////////////////////////////////////////////////


process =
  testSignal@(totalLatency)
, (testSignal:ba.slidingMin(totalCurveTime,totalCurveTime))
;
///////////////////////////////////////////////////////////////////////////////
//                               implementation                              //
///////////////////////////////////////////////////////////////////////////////


///////////////////////////////////////////////////////////////////////////////
//                                 constants                                 //
///////////////////////////////////////////////////////////////////////////////

// slidingMin(4,4) looks at x@0,x@1,x@2 and x@3, so total latency is 3 samples
totalLatency = totalCurveTime-1;
totalCurveTime = topCurveTime + bottomCurveTime; // == 160 samples, 3.33 ms at 48k

topCurveTime = pow(2,topCurveExpo);
bottomCurveTime = pow(2,bottomCurveExpo);
topCurveExpo = 7; // == 128 samples, 2.6 ms at 48k
bottomCurveExpo = 5; // == 32 samples, 0.666 ms at 48k
// pow(4,2) == 16 for block diagram

///////////////////////////////////////////////////////////////////////////////
//                                    GUI                                    //
///////////////////////////////////////////////////////////////////////////////

blockRate = hslider("[0]block rate", 0.1, 0, 1, 0.001);
noiseLevel = hslider("[1]noise level", 0, 0, 1, 0.01);
noiseRate = hslider("[2]noise rate", 20, 10, 20000, 10);

///////////////////////////////////////////////////////////////////////////////
//                              helper functions                             //
///////////////////////////////////////////////////////////////////////////////

testSignal =
  vgroup("testSignal",
         no.lfnoise0(totalLatency * 8 * blockRate * (no.lfnoise0(totalLatency/2):max(0.1) ))
         :pow(3)*(1-noiseLevel) +(no.lfnoise(noiseRate):pow(3) *noiseLevel):min(0)) ;
