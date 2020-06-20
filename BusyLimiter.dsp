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

new attack idea
when there is a new lower value, check the value of time and sustract it from the previously saved one.
use that to calculate the needed speed, and if it is higher, save the time in a rw_table of size totalLatency.
also save the needed GR in a second table

when time==LatencyCompensatedSavedVlue, SandH the time and speed, read then next value and ramp to the needed GR in the alotted time.


to combat time running into maxClock, make it a ramp.
to make sure we don't get confused at the wrap-around point:
if timeDiff<0 add wrapValue to one end.

needed steps:
- on startup, write the GR to index 1, write maxAttackTime to index 1
- start fading from no gr to the GR at index 1
- on the next sample, see if speed is smaller, write the GR and time to




*/

///////////////////////////////////////////////////////////////////////////////
//                                  process                                  //
///////////////////////////////////////////////////////////////////////////////

process =
  test(testSignal)
// , readIndex/totalTime
// , (timeDiff:hbargraph("timeDiff", 0, maxClock)/maxClock)
// testSignal@(totalLatency)
// , holdGR(testSignal)
// , preAttackGR(testSignal)@(1+totalLatency-(bottomAttackTime@totalLatency))
// , smoothGRl(testSignal)@(1+totalLatency-(maxAttackTime@totalLatency))
;
///////////////////////////////////////////////////////////////////////////////
//                               implementation                              //
///////////////////////////////////////////////////////////////////////////////
test(GR) =
  (clock/maxClock)
, GR@(totalTime -1 )
, (FB(GR)~(_,_) :(_,!))
with {
  // time, wrapped around maxClock
  clock = ((_+1)%maxClock)~_:_-1;
  FB(GR,prev,prevTarget) =
    // timeTable(readIndex) // TODO: make into acual fade
    fade
  , GRTable(readIndex)
  with {
    // save all the time values where a change of direction takes place
    // TODO: remove  min, max, int
    timeTable(readIndex) = rwtable(totalTime  +1, 0.0 , writeIndex:max(0):min(totalTime+1):int , clock , readIndex:max(0):min(totalTime+1):int);
    GRTable(readIndex) = rwtable(totalTime  +1, 0.0 , writeIndex , GR , readIndex);
    directionTable(readIndex) = rwtable(totalTime  +1, 0 , writeIndex , direction , readIndex);
    // in case we need to fade down:
    // - speed is negative, so speed<prevSpeed means we need to fade down faster than we are fading now, so we increase the write index
    // in case we need to fade up:
    // - speed is positive, so speed<prevSpeed means we need to fade up slower than we are fading now, so we increase the write index
    // in case we need to stay put:
    // - speed == prevSpeed so we don't increase the writeIndex
    writeIndex =
      // TODO: fix cornercase when we just arrived and need to go down, but less then we are doing down now.
      select2((proposedSpeed<currentSpeed) | ( ((prev+currentSpeed)==prevTarget) & (GR!=prev))
        // wrap around totalTime
             ,_,(_+1)%totalTime)~(_<:_,_)
// if we get the same write-index twice, that means we need to stay the course, so don't write a new target, so index = totalTime+1
                                 <: select2(_==_',_,totalTime+1)
    ;
    proposedSpeed = (GR-prev)/totalTime;
    // proposedSpeed = speed(timeTable(readIndex),newTime,oldGR,newGR);
    currentSpeed = prev-prev';

    // oldGR = 0;
    // newGR = 0;

    // as soon as the clock is at the time of the new target, we have reached the target so we read the new one (or wait if we are alredy at the target)
    readIndex =
      select2(clock-totalTime == timeTable(_)
             ,_
// wrap around totalTime
             ,(_+1)%totalTime
      )~
      (_<:si.bus(3));
    // readIndex(0) is the current place
    // readIndex(inc) = select2(_ > totalLatency, _+inc, 0 )~(_<:(_,_));
    //
    // the time we have for the fade
    // if clock has wrapped around for newTime, but not yet for oldTime, add the wrap value
    // can not be more than totalLatency
    timeDiff(oldTime,newTime) = select2(oldTime<newTime, newTime-oldTime+maxClock, newTime-oldTime):min(totalLatency);
    // GRdiff(oldGR,newGR) = oldGR-newGR;
    // speed(oldTime,newTime,oldGR,newGR) = GRdiff/timeDiff;
    // TODO: actually implement:
    // prevSpeed(oldTime,newTime,oldGR,newGR) = speed(oldTime,newTime,oldGR,newGR)';

    // * `t`: hold trigger (0 for hold, 1 for bypass)
    // oldTime = clock:ba.sAndH(button("old"):ba.impulsify);
    // newTime = clock:ba.sAndH(button("new"):ba.impulsify);

    fade =
      crossfade(GRTable(readIndex),GRTable((readIndex-1)%totalTime) ,ramp(timeDiff(timeTable(readIndex),timeTable((readIndex-1)%totalTime)),trigRamp));
    trigRamp = clock-totalTime == timeTable((readIndex-1)%totalTime);

    ramp(n,reset) = select2(reset,_+(1/n):min(1),1/n)~_;
    crossfade(a,b,x) =
      it.interpolate_linear(x,a,b);  // faster then: a*(1-x) + b*x;
    // a*(1-x) + b*x; // for readability

    // 3 possible values: down == -1, stationary == 0, up == 1
    direction = ((prev+proposedSpeed)>lowestGRblock(GR,totalTime))*-1 + ((prev+proposedSpeed)<lowestGRblock(GR,totalTime));

    linearLookahead = select3( direction+1
                             , linearAttack
                             , prev
                             , linearRelease);

    linearAttack = 0;
  };
};

///////////////////////////////////////////////////////////////////////////////
//                             old implementation                            //
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
  newH(i) = new(i):ba.sAndH( reset(i)| select2(checkbox("att newH"),0,(attPhase(prev)==0)) );
  prevH(i) = prev:ba.sAndH( reset(i)| select2(checkbox("att prevH"),0,(attPhase(prev)==0)) );
  reset(i) =
    (newDownSpeed(i) > currentDownSpeed);
  fade(i) =
    crossfade(prevH(i),newH(i) ,ramp(size(i),reset(i)| select2(checkbox("att ramp"),0,(attPhase(prev)==0)))) // TODO crossfade from current direction to new position
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
totalTime = pow(2,8):int;
// totalTime = (maxAttackTime + maxReleaseTime):int;
// slidingMin(4,4) looks at x@0,x@1,x@2 and x@3, so total latency is 3 samples
totalAttackLatency = maxAttackTime-1;
maxAttackTime = pow(2,maxAttackExpo);
maxAttackExpo = 8;
// doesn't work with rwtable, TODO: try case?
mAE =
  select2(blockDiagram
    // ,4 // == 16 samples,
    // ,7 // == 128 samples, 2.666 ms at 48k
         ,8 // 256 samples, 5.333 ms at 48k, the max lookahead of fabfilter pro-L is 5ms
// ,2 // == 4 samples, blockdiagram
         ,4 // == 16 samples, blockdiagram
  );

totalReleaseLatency = maxReleaseTime-1;
maxReleaseTime = pow(2,maxReleaseExpo);
maxReleaseExpo = 13;
// doesn't work with rwtable, TODO: try case?
mRE =
  select2(blockDiagram
         ,13 // == 8192 samples, 170.666 ms at 48k
         ,4 // == 16 for block diagram
// ,6 // == 64 for block diagram
  );

// not really the maximum int, but seems a safe bet and equates to more than 6 hours at 48k
// maxClock = 2^30;
maxClock = 2^17;
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
