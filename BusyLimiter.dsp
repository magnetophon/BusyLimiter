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
make release out of paralel lin releases, of pow(2,i) length, pick the one that goes up most

first do the release, so attack knows where to start from


*/

///////////////////////////////////////////////////////////////////////////////
//                                  process                                  //
///////////////////////////////////////////////////////////////////////////////


process(x) =
  testSignal@(totalLatency)
, holdGR(testSignal)
, preAttackGR(testSignal)@(1+totalLatency-(bottomAttackTime@totalLatency))
, smoothGRl(testSignal)@(1+totalLatency-(maxAttackTime@totalLatency))
;
///////////////////////////////////////////////////////////////////////////////
//                               implementation                              //
///////////////////////////////////////////////////////////////////////////////
preAttackGR(GR) = (GR:ba.slidingMin(bottomAttackTime,maxAttackTime));
holdGR(GR) =
  (ba.slidingMin(holdTime,maxReleaseTime,GR)@(1+totalLatency-holdTime@(totalLatency-holdTime)))
  :max(_:min(GR@(totalLatency)))~_;
// :max(_:min(preAttackGR(GR@(1+totalLatency-(bottomAttackTime@(1+totalLatency-bottomAttackTime) )))))~_;
comp = hslider("comp", 0, 0, totalLatency, 1);

smoothGRl(GR) = FB~_
with {
  FB(prev) =
    par(i, maxAttackExpo, fade(i)):minN(maxAttackExpo)
// fade(0)
  with {
  new(i) = lowestGRblock(GR,size(i))@(maxAttackTime-size(i));
  newH(i) = new(i):ba.sAndH( reset(i)| (attPhase(prev)==0) );
  prevH(i) = prev:ba.sAndH( reset(i)| (attPhase(prev)==0) );
  reset(i) =
    (newDownSpeed(i) > currentDownSpeed);
  fade(i) =
    crossfade(prevH(i),newH(i) ,ramp(size(i),reset(i)| (attPhase(prev)==0))) // TODO crossfade from current direction to new position
// :min(GR@maxAttackTime)//brute force fade of 64 samples not needed for binary tree attack ?
// sample and hold oldDownSpeed:
// , (select2((newDownSpeed(i) > currentDownSpeed),currentDownSpeed ,newDownSpeed(i)))
  ;
  newDownSpeed(i) = (prev -new(i) )/size(i);
  currentDownSpeed =  prev' - prev;
  size(i) = pow(2,(maxAttackExpo-i));
  }; // ^^ needs prev and oldDownSpeed
  attPhase(prev) = lowestGRblock(GR,maxAttackTime)<prev;
  lowestGRblock(GR,size) = GR:ba.slidingMin(size,maxAttackTime);


  // ramp from 1/n to 1 in n samples.  (don't start at 0 cause when the ramp restarts, the crossfade should start right away)
  // when reset == 1, go back to 0.
  // ramp(n,reset) = select2(reset,_+(1/n):min(1),0)~_;
  ramp(n,reset) = select2(reset,_+(1/n):min(1),1/n)~_;

  crossfade(a,b,x) = it.interpolate_linear(x,a,b);  // faster then: a*(1-x) + b*x;

  minN(n) = opWithNInputs(min,n);
  maxN(n) = opWithNInputs(max,n);

  opWithNInputs =
    case {
      (op,0) => 0:!;
        (op,1) => _;
      (op,2) => op;
      (op,N) => (opWithNInputs(op,N-1),_) : op;
    };
};
///////////////////////////////////////////////////////////////////////////////
//                                 constants                                 //
///////////////////////////////////////////////////////////////////////////////
blockDiagram = 0;

totalLatency = totalAttackLatency + totalReleaseLatency;
// slidingMin(4,4) looks at x@0,x@1,x@2 and x@3, so total latency is 3 samples
totalAttackLatency = maxAttackTime-1;
maxAttackTime = pow(2,maxAttackExpo);
maxAttackExpo =
  select2(blockDiagram
    // ,4 // == 16 samples,
         ,7 // == 128 samples, 2.666 ms at 48k
// ,8 // 256 samples, 5.333 ms at 48k, the max lookahead of fabfilter pro-L is 5ms
         ,2 // == 4 samples, blockdiagram
// ,4 // == 16 samples, blockdiagram
  );

totalReleaseLatency = maxReleaseTime-1;
maxReleaseTime = pow(2,maxReleaseExpo);
maxReleaseExpo =
  select2(blockDiagram
         ,13 // == 8192 samples, 170.666 ms at 48k
         ,4 // == 16 for block diagram
// ,6 // == 64 for block diagram
  );
///////////////////////////////////////////////////////////////////////////////
//                                    GUI                                    //
///////////////////////////////////////////////////////////////////////////////

topAttackTime = hslider("topAttackTime", 3/4*maxAttackTime, 1, maxAttackTime, 1);
bottomAttackTime = hslider("bottomAttackTime", 1/4*maxAttackTime, 1, maxAttackTime, 1);
topReleaseTime = hslider("topReleaseTime", 3/4*maxReleaseTime, 1, maxReleaseTime, 1);
bottomReleaseTime = hslider("bottomReleaseTime", 1/4*maxReleaseTime, 1, maxReleaseTime, 1);
holdTime = hslider("holdTime", 1/4*maxReleaseTime, 1, maxReleaseTime, 1);


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
