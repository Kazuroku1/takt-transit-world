import { describe, expect, it, vi } from 'vitest';
import { CITIES, ROUTES, gameReducer, levelFor, newGame, parseSave, questsFor, upgradeCost, xpFor } from './game';
import type { GameState } from './game';

const advance=(initial:GameState,seconds:number,step=1)=>{
  let state=initial;for(let t=0;t<seconds;t+=step)state=gameReducer(state,{type:'tick',dt:Math.min(step,seconds-t)});return state;
};

describe('The first playable session',()=>{
  it('starts a bus, buys only predefined lines, claims a quest once and unlocks a tram',()=>{
    let s=newGame();
    expect(s.cities.zurich.routes.map(r=>r.id)).toEqual(['b31']);
    expect(gameReducer(s,{type:'buy',id:'made-up-line'})).toBe(s);
    expect(gameReducer(s,{type:'buy',id:'t4'})).toBe(s);
    s=gameReducer(s,{type:'buy',id:'b33'});
    expect(s.cash).toBe(650);
    expect(s.cities.zurich.routes).toHaveLength(2);
    expect(gameReducer(s,{type:'buy',id:'b33'})).toBe(s);
    s=gameReducer(s,{type:'claim',id:'second'});
    expect(s.cash).toBe(1300);
    expect(levelFor(s.xp)).toBe(2);
    expect(gameReducer(s,{type:'claim',id:'second'})).toBe(s);
    s=gameReducer(s,{type:'buy',id:'t4'});
    expect(s.cash).toBe(200);
    expect(s.cities.zurich.routes.map(r=>r.id)).toContain('t4');
  });
  it('rejects purchases with insufficient funds and unearned rewards',()=>{
    const s={...newGame(),cash:0};
    expect(gameReducer(s,{type:'buy',id:'b33'})).toBe(s);
    expect(gameReducer(s,{type:'upgrade',id:'b31'})).toBe(s);
    expect(gameReducer(s,{type:'claim',id:'p500'})).toBe(s);
    expect(gameReducer(s,{type:'city',id:'bern'})).toBe(s);
  });
  it('pays for completed journeys and preserves partial progress',()=>{
    let s=advance(newGame(),13);
    expect(s.passengers).toBe(0);
    s=advance(s,1);
    expect(s.passengers).toBe(8);
    expect(s.cash).toBe(1232);
    expect(s.cities.zurich.routes[0].carried).toBe(8);
    expect(s.cities.zurich.routes[0].progress).toBe(0);
  });
  it('increases capacity when upgrading, with a limit of five vehicles',()=>{
    let s={...newGame(),cash:100000};
    const cost=upgradeCost(ROUTES[0],1);
    s=gameReducer(s,{type:'upgrade',id:'b31'});
    expect(s.cash).toBe(100000-cost);
    s=advance(s,14);
    expect(s.passengers).toBe(16);
    for(let i=0;i<3;i++)s=gameReducer(s,{type:'upgrade',id:'b31'});
    expect(s.cities.zurich.routes[0].tier).toBe(5);
    expect(gameReducer(s,{type:'upgrade',id:'b31'})).toBe(s);
  });
});

describe('Progression, events and multiple cities',()=>{
  it('awards the same XP regardless of tick size',()=>{
    const initial=gameReducer(newGame(),{type:'buy',id:'b33'});
    const a=advance(initial,100,1),b=advance(initial,100,2);
    expect(a.passengers).toBe(b.passengers);
    expect(a.xp).toBe(b.xp);
    expect(a.cash).toBe(b.cash);
  });
  it('validates city requirements and keeps all discovered networks earning',()=>{
    let s={...newGame(),cash:10000,xp:xpFor(3)};
    s=gameReducer(s,{type:'city',id:'bern'});
    expect(s.cityId).toBe('bern');
    expect(s.cash).toBe(7200);
    expect(s.cities.zurich.routes).toHaveLength(1);
    s=advance(s,14);
    expect(s.passengers).toBe(16);
    const cash=s.cash;
    s=gameReducer(s,{type:'city',id:'zurich'});
    expect(s.cash).toBe(cash);
    expect(gameReducer(s,{type:'city',id:'tokyo'})).toBe(s);
  });
  it('starts and expires a temporary bonus event',()=>{
    let s=advance(newGame(),120);
    expect(s.event?.endsAt).toBe(155);
    const cash=s.cash;s=advance(s,6);
    expect(s.cash-cash).toBe(48);
    s=advance(s,30);
    expect(s.event).toBeNull();
  });
  it('opens every transport type and city through an earned progression loop',()=>{
    let s=newGame();
    for(let t=0;t<3600;t+=5){
      s=advance(s,5,5);
      for(const q of questsFor(s))if(q.current>=q.target)s=gameReducer(s,{type:'claim',id:q.id});
      for(const r of ROUTES)s=gameReducer(s,{type:'buy',id:r.id});
      for(const c of CITIES)if(!s.cities[c.id])s=gameReducer(s,{type:'city',id:c.id});
    }
    expect(Object.keys(s.cities)).toHaveLength(8);
    expect(Object.values(s.cities).flatMap(c=>c.routes).some(r=>r.id==='a1')).toBe(true);
    expect(s.cash).toBeGreaterThanOrEqual(0);
  });
  it('daily rewards survive reloads and reset on the next local day',()=>{
    vi.useFakeTimers();vi.setSystemTime(new Date(2026,9,28,12));
    try{
      let s=advance(newGame(),1);
      s={...s,earned:s.earned+5000};
      const q=questsFor(s).find(q=>q.category==='daily')!;
      expect(q.current).toBe(5000);
      s=gameReducer(s,{type:'claim',id:q.id});
      s=parseSave(JSON.stringify(s));
      expect(gameReducer(s,{type:'claim',id:q.id})).toBe(s);
      vi.setSystemTime(new Date(2026,9,29,12));
      s=advance(s,1);
      const tomorrow=questsFor(s).find(q=>q.category==='daily')!;
      expect(tomorrow.id).not.toBe(q.id);
      expect(tomorrow.current).toBe(0);
    }finally{vi.useRealTimers();}
  });
});

describe('Save data integrity',()=>{
  it('round-trips the entire city and settings state',()=>{
    let s=advance(gameReducer(newGame(),{type:'buy',id:'b33'}),27);
    s=gameReducer(s,{type:'settings',settings:{night:true,reducedMotion:true}});
    expect(parseSave(JSON.stringify(s))).toEqual(s);
  });
  it.each(['broken JSON','null','{}',JSON.stringify({...newGame(),cash:-1}),JSON.stringify({...newGame(),cityId:'missing'}),JSON.stringify({...newGame(),cities:{zurich:{routes:[{id:'missing',tier:1,carried:0,progress:0}]}}}),JSON.stringify({...newGame(),cities:{zurich:{routes:[{id:'b31',tier:1,carried:0,progress:1000}]}}})])('recovers from invalid save data: %s',(raw)=>{
    const recovered=parseSave(raw);expect(recovered.cash).toBe(1200);expect(recovered.cityId).toBe('zurich');expect(recovered.passengers).toBe(0);
  });
  it('ignores invalid clock deltas',()=>{
    const s=newGame();for(const dt of [NaN,Infinity,-1,0])expect(gameReducer(s,{type:'tick',dt})).toBe(s);
  });
});
