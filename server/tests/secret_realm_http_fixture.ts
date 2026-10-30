// Isolated HTTP fixture for tests/SecretRealmOnlineSmoke.tscn. Compile with the
// server smoke tests, launch from the project root, then run the Godot scene.
import { createServer } from "node:http";
import { mkdirSync, writeFileSync } from "node:fs";
import { GameEngine } from "../src/engine/game_engine";
import { gameConfigTables } from "../src/worker/config_data";
import { MemoryStorage } from "../src/storage/memory";
import { createGameRouter } from "../src/routes/game";
import { WorkerResponse } from "../src/worker/http";
import { signToken } from "../src/middleware/auth";

async function main() {
  const engine = new GameEngine(gameConfigTables), storage = new MemoryStorage();
  const state = engine.createInitialState();
  state.cultivation.current_level = 2;
  engine.secretRealmService.initialize(state);
  const p = state.secret_realm!;
  p.cells.find(c=>c.col===3&&c.row===0)!.item!.id="sword_4";
  const highSource=p.cells.find(c=>c.col===3&&c.row===1)!.item!;
  highSource.id="sword_4";highSource.immovable=false;
  for (const [chain, x, y] of [["qi",4,1],["stamina",4,2],["stone",2,2]] as const) {
    for (const col of [x,x+1]) {
      const cell = p.cells.find(c => c.col === col && c.row === y)!;
      cell.fog = false;
      delete cell.monster;
      cell.item = { uid:engine._nextUid(state), id:`${chain}_1`, immovable:false };
    }
  }
  for (const chain of ["sword","qi","stamina","stone"]) {
    p.stash.push({uid:engine._nextUid(state),id:`${chain}_2`,immovable:false});
  }
  p.stash.push({uid:engine._nextUid(state),id:"sword_1",immovable:true});
  if(process.argv.includes("--combat")) {
    p.stash=[];
    for(const cell of p.cells.filter(c=>c.row<8)) {
      cell.fog=cell.col>=2&&cell.col<=4&&cell.row>=5&&cell.row<=7;
      delete cell.item;
    }
    for(const [col,id] of ["sword_4","qi_3","sword_4","qi_3","sword_7","qi_6"].entries())
      p.cells.find(c=>c.col===col&&c.row===0)!.item={uid:engine._nextUid(state),id,immovable:false};
    for(const [col,row,id] of [[0,1,"sword_2"],[5,2,"qi_2"],[0,4,"sword_2"],[5,7,"qi_2"]] as const)
      p.cells.find(c=>c.col===col&&c.row===row)!.item={uid:engine._nextUid(state),id,immovable:true};
  }
  if(process.argv.includes("--push")) {
    p.stash=[];
    for(const cell of p.cells.filter(c=>c.row<8)) {
      cell.fog=false;delete cell.monster;
      cell.item={uid:engine._nextUid(state),id:"sword_1",immovable:true};
    }
    const at=(col:number,row:number)=>p.cells.find(c=>c.col===col&&c.row===row)!;
    at(0,7).item!.immovable=false;
    at(2,4).item!.id="qi_1";at(2,4).item!.immovable=false;
    for(const col of [4,5]) { at(col,0).item!.id="sword_12";at(col,0).item!.immovable=false; }
  }
  if(process.argv.includes("--stash-burst")) {
    p.stash=[];
    for(const c of p.cells) {
      c.fog=true;delete c.item;delete c.monster;
      if(c.row<2&&c.col>=2&&c.col<=4)c.fog=false;
    }
    const mob=p.cells.find(c=>c.col===1&&c.row===0)!;mob.fog=false;mob.monster="mob_1";
    for(const [n,id] of ["sword_1","qi_5","sword_2","sword_3","sword_4","stamina_2","sword_2","qi_1"].entries())
      p.stash.push({uid:engine._nextUid(state),id,immovable:n<2});
  }
  if(process.argv.includes("--merge-drag")) {
    p.stash=[];
    for(const c of p.cells) {
      c.fog=false;delete c.item;delete c.monster;
      if(c.row===0)c.item={uid:engine._nextUid(state),id:c.col<4?"sword_4":"sword_1",immovable:false};
    }
  }
  await storage.saveState("realm-ui-test",state);
  const router = createGameRouter(storage,engine,"realm-ui-test-secret");
  const token = await signToken({userId:"realm-ui-test",deviceId:"test"},"realm-ui-test-secret");
  let authLogins = 0, failedReload = false;
  const server = createServer(async (req,res) => {
    try {
      let text = "";
      for await (const chunk of req) text += chunk;
      if(process.argv.includes("--relogin") && req.url === "/api/game/state" && authLogins === 1 && !failedReload) {
        failedReload = true;
        res.writeHead(500,{"Content-Type":"application/json"});
        res.end(JSON.stringify({error:"test_state_load_failed"}));
        return;
      }
      if(process.argv.includes("--relogin") && req.url === "/api/auth/login") {
        authLogins++;
        res.writeHead(200,{"Content-Type":"application/json"});
        res.end(JSON.stringify({token,user:{user_id:"realm-ui-test"}}));
        return;
      }
      if(process.argv.includes("--relogin") && req.url === "/api/game/late-realm") {
        await new Promise(resolve=>setTimeout(resolve,700));
        res.writeHead(200,{"Content-Type":"application/json"});
        res.end(JSON.stringify({storage_revision:999,secret_realm:{version:999}}));
        return;
      }
      if(process.argv.includes("--stash-burst")&&req.method==="POST")await new Promise(resolve=>setTimeout(resolve,120));
      const response = new WorkerResponse();
      const found = await router.handle({method:req.method!,path:req.url!.replace(/^\/api\/game/,""),
        body:text?JSON.parse(text):{},headers:{authorization:req.headers.authorization},query:{}},response);
      res.writeHead(found?response.statusCode:404,{"Content-Type":"application/json"});
      res.end(found?await response.toResponse().text():"{}");
    } catch (err) {
      console.error(err);
      res.writeHead(500);res.end('{"error":"internal_error"}');
    }
  });
  server.listen(0,"127.0.0.1",() => {
    const address = server.address() as {port:number};
    mkdirSync(".codex_tmp",{recursive:true});
    writeFileSync(".codex_tmp/realm-http.json",JSON.stringify({base_url:`http://127.0.0.1:${address.port}`,token}));
    console.log("SECRET_REALM_HTTP_READY");
  });
  setTimeout(() => server.close(),120_000).unref();
}
main().catch(err => { console.error(err);process.exitCode=1; });
