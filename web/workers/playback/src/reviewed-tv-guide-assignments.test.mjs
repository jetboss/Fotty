import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { buildBroadcastSnapshot } from "./broadcast-registry-policy.mjs";
import { reviewedTVGuideAssignments } from "./reviewed-tv-guide-assignments.mjs";
const now=new Date("2026-11-01T00:00:00Z");
const guide=(extra={})=>({id:"tv-guide:"+"a".repeat(64),channelID:"sports-channel:espn2-latinamerica-south",market:"UY",sport:"baseball",
  title:"MLB – Regular season – Milwaukee Brewers vs. Tampa Bay Rays",start:"2026-11-01T00:00:00.000Z",observedAt:now.toISOString(),
  expiresAt:new Date(+now+4*3600000).toISOString(),...extra});
const fixture=(extra={})=>({fixtureID:"sports-fixture:mlb:123",sport:"baseball",competitionID:"mlb",participants:["Milwaukee Brewers","Tampa Bay Rays"],
  start:"2026-11-01T00:30:00.000Z",observedAt:now.toISOString(),status:"scheduled",verified:true,squad:{gender:"men",ageGroup:"senior"},...extra});
test("a unique fresh official MLB fixture admits its explicitly dated regional station without changing kickoff",async()=>{
  const r=await reviewedTVGuideAssignments([guide()],[fixture()],now);
  assert.equal(r.broadcasts.length,1);assert.equal(r.links.length,1);assert.equal(r.links[0].state,"listed");
  assert.equal(r.links[0].fixtureFingerprint.start,fixture().start);assert.equal(r.broadcasts[0].start,guide().start);
  assert.deepEqual(r.broadcasts[0].squad,fixture().squad);assert.equal(r.links[0].matchMethod,"channel-assignment");assert.equal(r.broadcasts[0].expiresAt,new Date(+now+600000).toISOString());
});
test("conditional postseason/ordinal and replay facts remain browsable guide data without an invented match route",async()=>{
  for(const title of ["MLB – World Series – Game #6 (if necessary) – Milwaukee Brewers vs. Tampa Bay Rays",
    "MLB – Juego #6 – Milwaukee Brewers vs. Tampa Bay Rays","MLB – Repetición – Milwaukee Brewers vs. Tampa Bay Rays"]){
    const r=await reviewedTVGuideAssignments([guide({title})],[fixture()],now);assert.equal(r.links.length,0);
  }
});
test("the already-active NHL fixture authority supplies exact teams and squad for dated hockey coverage",async()=>{
  const row=guide({sport:"hockey",title:"NHL – New Jersey Devils vs. Edmonton Oilers"});
  const official=fixture({fixtureID:"sports-fixture:nhl:1",sport:"hockey",competitionID:"nhl",participants:["Edmonton Oilers","New Jersey Devils"]});
  const result=await reviewedTVGuideAssignments([row],[official],now);
  assert.equal(result.links.length,1);assert.equal(result.links[0].state,"listed");
  assert.equal(result.providers[0].scope,"hockey");assert.deepEqual(result.broadcasts[0].squad,official.squad);
  assert.equal(result.broadcasts[0].competitionID,"nhl");
});
test("same-day doubleheaders, wrong participants/date, old source and terminal official status cannot borrow a channel",async()=>{
  const cases=[[fixture(),fixture({fixtureID:"sports-fixture:mlb:124",start:"2026-11-01T01:00:00.000Z"})],
    [fixture({participants:["Other team","Tampa Bay Rays"]})],[fixture({start:"2026-11-02T00:30:00.000Z"})],
    [fixture({status:"finished"})],[fixture({verified:false})],[fixture({squad:undefined})],[fixture({squad:{gender:"women",ageGroup:"senior"}})],[fixture({observedAt:new Date(+now-600001).toISOString()})]];
  for(const fs of cases)assert.equal((await reviewedTVGuideAssignments([guide()],fs,now)).links.length,0);
  const later=new Date(+now+600001);assert.equal((await reviewedTVGuideAssignments([guide()],[fixture({observedAt:later.toISOString()})],later)).links.length,0);
});
test("unsupported official sport scopes and unreviewed regional station contracts cannot activate new feeds",async()=>{
  assert.equal((await reviewedTVGuideAssignments([guide({sport:"american-football",title:"NFL – Home vs. Away"})],[fixture()],now)).links.length,0);
  await assert.rejects(reviewedTVGuideAssignments([guide({market:"US"})],[fixture()],now),/invalid-tv-guide/);
});
test("the shared native wire fixture remains output from the real backend builders",async()=>{
  const wire=JSON.parse(await readFile(new URL("../../../../FottyTests/Fixtures/reviewed-tv-guide-snapshot.json",import.meta.url),"utf8"));
  const at=new Date(wire.generatedAt);
  const official=wire.links.map(link=>({...link.fixtureFingerprint,status:"scheduled",verified:true,observedAt:wire.generatedAt}));
  const result=await reviewedTVGuideAssignments(wire.tvGuide,official,at);
  assert.deepEqual(wire,{...await buildBroadcastSnapshot({...result,now:at}),tvGuide:wire.tvGuide});
});
