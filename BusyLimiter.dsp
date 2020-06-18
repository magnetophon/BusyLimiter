declare author "Bart Brouns";
declare name "BusyLimiter";
declare version "0.1";
declare license "AGPLv3";

import("stdfaust.lib");
// TODO: slidingReduce uses too many blocks:
// if you use a power of 2 for N, there should be no blocks turned off, but there are.
// sr = library("slidingReduce.lib");

/*

idea:
make release paralel lin release, of pow(2,i) length

*/

///////////////////////////////////////////////////////////////////////////////
//                                  process                                  //
///////////////////////////////////////////////////////////////////////////////


process =
  testSignal@(totalLatency)
, preAttackGR@(totalLatency-bottomAttackTime@totalLatency+1)
;
///////////////////////////////////////////////////////////////////////////////
//                               implementation                              //
///////////////////////////////////////////////////////////////////////////////
preAttackGR = (testSignal:ba.slidingMin(bottomAttackTime,maxAttackTime));

///////////////////////////////////////////////////////////////////////////////
//                                 constants                                 //
///////////////////////////////////////////////////////////////////////////////

totalLatency = totalAttackLatency + totalReleaseLatency;
// slidingMin(4,4) looks at x@0,x@1,x@2 and x@3, so total latency is 3 samples
totalAttackLatency = maxAttackTime-1;
maxAttackTime = pow(2,maxAttackExpo);
maxAttackExpo = 7; // == 128 samples, 2.6 ms at 48k
// maxAttackExpo = 8; // 256 samples, 5.3 ms at 48k, the max lookahead of fabfilter pro-L is 5ms
// maxAttackExpo = 4; // == 16 for block diagram

totalReleaseLatency = maxReleaseTime-1;
maxReleaseTime = pow(2,maxReleaseExpo);
maxReleaseExpo = 13; // == 8192 samples, 170.666 ms at 48k
// maxReleaseExpo = 4; // == 16 for block diagram

///////////////////////////////////////////////////////////////////////////////
//                                    GUI                                    //
///////////////////////////////////////////////////////////////////////////////

topAttackTime = hslider("topAttackTime", 3/4*maxAttackTime, 1, maxAttackTime, 1);
bottomAttackTime = hslider("bottomAttackTime", 1/4*maxAttackTime, 1, maxAttackTime, 1);
topReleaseTime = hslider("topReleaseTime", 3/4*maxReleaseTime, 1, maxReleaseTime, 1);
bottomReleaseTime = hslider("bottomReleaseTime", 1/4*maxReleaseTime, 1, maxReleaseTime, 1);


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
