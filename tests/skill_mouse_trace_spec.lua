-- Pure virtual-knob geometry for the native mouse trace. No FiveM/CEF claims: real mouse scale,
-- DPI and in-game sensitivity must be checked in game.
local file=assert(io.open('imports/skillCheck/shared.lua'))
local source=file:read('*a'); file:close()
local create,step,R=assert(load(source .. '\nreturn newMouseTrace, stepMouseTrace, TRACE_RADIUS'))()
local TOL=.15

-- Feed a list of absolute points (relative to the gesture start) as per-sample deltas.
local function feed(s,points,direction,t0,dt)
    local px,py,done,t=0,0,false,t0 or 0
    for _,p in ipairs(points) do
        t=t+(dt or 16)
        done=step(s,p[1]-px,p[2]-py,t,direction,TOL) or done
        px,py=p[1],p[2]
    end
    return done,t
end

-- A semicircle drawn from its rightmost point: centre at (-radius, 0) of the start.
local function arc(direction,samples,radius,opts)
    opts=opts or {}
    local sign=(direction=='upper' and -1 or 1)*(opts.wrong and -1 or 1)
    local points={}
    for i=1,samples do
        local a=math.pi*i/samples
        local r=radius*(1+(opts.wobble or 0)*math.sin(i*.5))
        local j=(opts.jitter or 0)*math.sin(i*2.3)
        points[#points+1]={-radius+r*math.cos(a)+j, r*math.sin(a)*sign+j*.5}
    end
    return points
end

assert(R==.5, 'documented base radius')

-- 1. A smooth sweep completes at many frame rates and gesture sizes, both directions.
for _,direction in ipairs({'lower','upper'}) do
    for _,samples in ipairs({12,30,60,144,240}) do
        for _,radius in ipairs({.5,1,2,4}) do
            local s=create()
            assert(feed(s,arc(direction,samples,radius),direction), ('%s arc, %s samples, radius %s'):format(direction,samples,radius))
        end
    end
end

-- 2. A small, wobbly sweep completes (radius just over R, four +-25% radial bumps plus per-sample jitter).
for _,direction in ipairs({'lower','upper'}) do
    local s=create()
    assert(feed(s,arc(direction,60,.6,{wobble=.25,jitter=.03}),direction), direction .. ' wobbly sweep must complete')
end
-- Higher sensitivity shrinks the knob, so an even smaller motion completes.
do local s=create(R/2) assert(feed(s,arc('lower',40,.3),'lower'), 'sensitivity 2 completes a half-size arc') end
do local s=create() assert(not feed(s,arc('lower',40,.3),'lower'), 'default knob needs more than a tiny arc') end

-- 3. Straight swipes never complete, whatever their direction or length.
for _,dir in ipairs({{-1,0},{1,0},{0,1},{0,-1},{-.7,.7},{-.97,.24},{-.99,.05}}) do
    for _,direction in ipairs({'lower','upper'}) do
        local s=create()
        local points={}
        for i=1,200 do points[i]={dir[1]*.05*i, dir[2]*.05*i*(direction=='upper' and -1 or 1)} end
        assert(not feed(s,points,direction), ('straight swipe %.2f,%.2f (%s) must fail'):format(dir[1],dir[2],direction))
        assert(s.progress<.9)
    end
end
do -- a single huge flick (e.g. a frame hitch) cannot jump across the centre
    local s=create()
    assert(not step(s,-3,.2,16,'lower',TOL))
    assert(s.progress<.1, 'a jump across the centre is ignored')
end

-- 4. The wrong direction never completes.
for _,direction in ipairs({'lower','upper'}) do
    for _,radius in ipairs({.5,1,2}) do
        local s=create()
        assert(not feed(s,arc(direction,60,radius,{wrong=true}),direction), direction .. ' mirrored arc must fail')
    end
end

-- 5. Pausing mid-sweep costs nothing; continuing completes.
do
    local s=create()
    local points=arc('lower',60,1)
    local first,second={},{}
    for i=1,30 do first[i]=points[i] end
    for i=31,60 do second[#second+1]={points[i][1]-points[30][1], points[i][2]-points[30][2]} end
    local _,t=feed(s,first,'lower')
    local mid=s.progress
    assert(mid>.3 and mid<.9)
    for i=1,60 do step(s,0,0,t+i*16,'lower',TOL) end -- ~1 s without motion
    assert(s.progress==mid, 'a short pause keeps progress')
    assert(feed(s,second,'lower',t+60*16), 'continuing after a pause completes')
end
do -- a long idle eases progress back instead of resetting it
    local s=create()
    local points=arc('upper',60,1)
    local half={} for i=1,30 do half[i]=points[i] end
    local _,t=feed(s,half,'upper')
    local mid=s.progress
    step(s,0,0,t+2500,'upper',TOL)
    assert(s.progress<mid and s.progress>0, 'long idle eases back gradually')
end

-- Reversal tolerance: jiggling along the tangent does not ratchet the knob forward.
do
    local s=create()
    for i=1,200 do step(s,0,(i%2==0) and -.08 or .08,i*16,'lower',TOL) end
    assert(s.progress<=TOL+.1, 'tangential jiggle nets (almost) nothing')
end
-- Invalid samples are dropped without resetting progress.
do
    local s=create()
    local points=arc('lower',60,1)
    local half={} for i=1,30 do half[i]=points[i] end
    feed(s,half,'lower')
    local mid=s.progress
    step(s,0/0,1,1000,'lower',TOL)
    assert(s.invalid and s.progress==mid, 'NaN is dropped, progress kept')
    step(s,20,0,1016,'lower',TOL)
    assert(s.invalid and s.progress==mid, 'oversized sample is dropped, progress kept')
end
print('relative mouse virtual knob: PASS')
